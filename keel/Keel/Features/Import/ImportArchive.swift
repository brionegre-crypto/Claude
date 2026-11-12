import Foundation
import Compression

/// Reads .zip files without any third-party code: the central directory, stored and DEFLATE entries
/// (via Apple's Compression framework), ZIP64 sizes, and zips inside zips (large workspace exports
/// are often split that way).
enum ZipReader {
    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    static func isZip(_ d: Data) -> Bool {
        d.count > 4 && d[d.startIndex] == 0x50 && d[d.startIndex + 1] == 0x4B && d[d.startIndex + 2] == 0x03 && d[d.startIndex + 3] == 0x04
    }

    private static func u16(_ d: Data, _ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
    private static func u32(_ d: Data, _ o: Int) -> Int { u16(d, o) | u16(d, o + 2) << 16 }
    private static func u64(_ d: Data, _ o: Int) -> Int { u32(d, o) | u32(d, o + 4) << 32 }

    static func entries(_ d: Data) -> [Entry] {
        guard d.count >= 22 else { return [] }
        // End of central directory: scan back from the end (it can be followed by a comment).
        var eocd = -1
        var i = d.count - 22
        let stop = max(0, d.count - 65_557)
        while i >= stop {
            if u32(d, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return [] }
        var count = u16(d, eocd + 10)
        var cd = u32(d, eocd + 16)
        // ZIP64 end of central directory, for very large exports.
        if (cd == 0xFFFFFFFF || count == 0xFFFF), eocd >= 20, u32(d, eocd - 20) == 0x07064b50 {
            let z64 = u64(d, eocd - 20 + 8)
            if z64 + 56 <= d.count, u32(d, z64) == 0x06064b50 {
                count = u64(d, z64 + 32)
                cd = u64(d, z64 + 48)
            }
        }
        var out: [Entry] = []
        var p = cd
        for _ in 0..<count {
            guard p + 46 <= d.count, u32(d, p) == 0x02014b50 else { break }
            let flags = u16(d, p + 8)
            let method = UInt16(u16(d, p + 10))
            var comp = u32(d, p + 20), size = u32(d, p + 24)
            let nameLen = u16(d, p + 28), extraLen = u16(d, p + 30), commentLen = u16(d, p + 32)
            var local = u32(d, p + 42)
            guard p + 46 + nameLen <= d.count else { break }
            let nameData = d.subdata(in: (d.startIndex + p + 46)..<(d.startIndex + p + 46 + nameLen))
            let name = (flags & 0x800 != 0 ? String(data: nameData, encoding: .utf8) : nil)
                ?? String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            // ZIP64 extra field holds the real sizes / offset.
            var e = p + 46 + nameLen
            let end = e + extraLen
            while e + 4 <= end && e + 4 <= d.count {
                let id = u16(d, e), len = u16(d, e + 2)
                if id == 0x0001 {
                    var q = e + 4
                    if size == 0xFFFFFFFF { size = u64(d, q); q += 8 }
                    if comp == 0xFFFFFFFF { comp = u64(d, q); q += 8 }
                    if local == 0xFFFFFFFF { local = u64(d, q) }
                }
                e += 4 + len
            }
            if !name.hasSuffix("/") && !name.hasPrefix("__MACOSX/") && !name.contains("/.DS_Store") && name != ".DS_Store" {
                out.append(Entry(path: name, method: method, compressedSize: comp, size: size, localOffset: local))
            }
            p += 46 + nameLen + extraLen + commentLen
        }
        return out
    }

    static func extract(_ e: Entry, from d: Data) -> Data? {
        let h = e.localOffset
        guard h + 30 <= d.count, u32(d, h) == 0x04034b50 else { return nil }
        let start = h + 30 + u16(d, h + 26) + u16(d, h + 28)
        guard start + e.compressedSize <= d.count else { return nil }
        let src = d.subdata(in: (d.startIndex + start)..<(d.startIndex + start + e.compressedSize))
        switch e.method {
        case 0: return src
        case 8:
            guard e.size > 0 else { return Data() }
            var dst = Data(count: e.size)
            let written = dst.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
                src.withUnsafeBytes { (inp: UnsafeRawBufferPointer) -> Int in
                    guard let o = out.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let i = inp.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                    // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what zip uses.
                    return compression_decode_buffer(o, e.size, i, e.compressedSize, nil, COMPRESSION_ZLIB)
                }
            }
            return written == e.size ? dst : (written > 0 ? dst.prefix(written) : nil)
        default:
            return nil
        }
    }
}

/// Everything picked for an import (files, folders, zips, zips inside zips) as one set of paths.
/// Files are read only when needed, so big exports don't sit in memory twice.
final class ImportArchive: @unchecked Sendable {
    private enum Source { case zip(Data, ZipReader.Entry), file(URL) }
    private var files: [String: Source] = [:]
    private(set) var order: [String] = []
    private var scoped: [URL] = []
    let name: String

    init(urls: [URL]) {
        name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "\(urls.count) items"
        for u in urls {
            if u.startAccessingSecurityScopedResource() { scoped.append(u) }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                addFolder(u, prefix: u.lastPathComponent)
            } else if let d = try? Data(contentsOf: u, options: .mappedIfSafe), ZipReader.isZip(d) {
                addZip(d, prefix: "", depth: 0)
            } else {
                add(u.lastPathComponent, .file(u))
            }
        }
    }

    deinit { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

    private func add(_ path: String, _ s: Source) {
        let p = ImportPaths.normalize(path)
        guard !p.isEmpty, files[p] == nil else { return }
        files[p] = s
        order.append(p)
    }

    private func addFolder(_ url: URL, prefix: String) {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) else { return }
        let base = url.standardizedFileURL.path
        for case let f as URL in e {
            let rel = String(f.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") && $0 != ".obsidian" }) { continue }
            if (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            let path = prefix + "/" + rel
            if f.pathExtension.lowercased() == "zip", let d = try? Data(contentsOf: f, options: .mappedIfSafe), ZipReader.isZip(d) {
                addZip(d, prefix: (path as NSString).deletingPathExtension + "/", depth: 1)
            } else {
                add(path, .file(f))
            }
        }
    }

    private func addZip(_ d: Data, prefix: String, depth: Int) {
        for e in ZipReader.entries(d) {
            if e.path.lowercased().hasSuffix(".zip"), depth < 3, let inner = ZipReader.extract(e, from: d), ZipReader.isZip(inner) {
                addZip(inner, prefix: prefix, depth: depth + 1)          // "Export-…-Part-1.zip" inside the download
            } else {
                add(prefix + e.path, .zip(d, e))
            }
        }
    }

    var paths: [String] { order }

    func data(_ path: String) -> Data? {
        guard let s = files[ImportPaths.normalize(path)] else { return nil }
        switch s {
        case .zip(let d, let e): return ZipReader.extract(e, from: d)
        case .file(let u): return try? Data(contentsOf: u)
        }
    }

    func text(_ path: String) -> String? {
        guard let d = data(path) else { return nil }
        var s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .utf16) ?? String(data: d, encoding: .isoLatin1)
        if s?.hasPrefix("\u{FEFF}") == true { s?.removeFirst() }
        return s
    }

    func exists(_ path: String) -> Bool { files[ImportPaths.normalize(path)] != nil }
}

enum ImportPaths {
    /// "a/./b/../c%20d.md" → "a/c d.md"
    static func normalize(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        var parts: [Substring] = []
        for p in decoded.replacingOccurrences(of: "\\", with: "/").split(separator: "/") {
            if p == "." || p.isEmpty { continue }
            if p == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(p)
        }
        return parts.joined(separator: "/")
    }

    static func dir(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    static func stem(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    static func ext(_ path: String) -> String { (path as NSString).pathExtension.lowercased() }

    static func resolve(_ link: String, from dir: String) -> String {
        let clean = link.components(separatedBy: "#").first ?? link
        return normalize(dir.isEmpty ? clean : dir + "/" + clean)
    }

    /// Workspace exports add a 32-character id to every name: "Roadmap 3f2a…9c.md" → "Roadmap".
    static func stripId(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s[0-9a-f]{32}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, with: "", options: .regularExpression)
    }

    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff", "tif"]
}
