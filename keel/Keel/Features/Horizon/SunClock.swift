import Foundation
import CoreLocation

/// Real sunrise and sunset for where you are. Uses Apple Weather's own times when Keel has fetched today's
/// weather (so it matches the Weather app exactly), otherwise works them out from your location with the
/// standard solar formula (within a minute or two), otherwise a sensible guess from your time zone.
enum SunClock {
    struct Day: Equatable { var dawn: Date; var rise: Date; var set: Date; var dusk: Date }

    static let latKey = "sun.lat", lonKey = "sun.lon"
    static let weatherKey = "sun.weather"         // [dayKey, rise, set, dawn, dusk] from WeatherKit

    /// Called whenever Keel learns where you are or gets today's weather.
    static func remember(location: CLLocation) {
        UserDefaults.standard.set(location.coordinate.latitude, forKey: latKey)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: lonKey)
        cache = nil
    }
    static func remember(rise: Date?, set: Date?, dawn: Date?, dusk: Date?, for day: Date) {
        guard let rise, let set else { return }
        UserDefaults.standard.set([dayKey(day), rise.timeIntervalSince1970, set.timeIntervalSince1970,
                                   (dawn ?? rise.addingTimeInterval(-1800)).timeIntervalSince1970,
                                   (dusk ?? set.addingTimeInterval(1800)).timeIntervalSince1970], forKey: weatherKey)
        cache = nil
    }

    private static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private static var cache: (key: String, day: Day)?

    static func today(_ now: Date = Date()) -> Day {
        let key = dayKey(now)
        if let c = cache, c.key == key { return c.day }
        let d = compute(now)
        cache = (key, d)
        return d
    }

    private static func compute(_ now: Date) -> Day {
        // 1. Apple Weather's times for today.
        if let a = UserDefaults.standard.array(forKey: weatherKey), a.count == 5, a[0] as? String == dayKey(now),
           let r = a[1] as? Double, let s = a[2] as? Double, let dw = a[3] as? Double, let dk = a[4] as? Double {
            return Day(dawn: Date(timeIntervalSince1970: dw), rise: Date(timeIntervalSince1970: r),
                       set: Date(timeIntervalSince1970: s), dusk: Date(timeIntervalSince1970: dk))
        }
        // 2. Your location (or a guess from your time zone: its central longitude, mid latitude).
        let d = UserDefaults.standard
        let lat = d.object(forKey: latKey) as? Double ?? 40
        let lon = d.object(forKey: lonKey) as? Double ?? Double(TimeZone.current.secondsFromGMT(for: now)) / 3600 * 15
        if let rise = solar(now, lat: lat, lon: lon, rising: true, zenith: 90.833),
           let set = solar(now, lat: lat, lon: lon, rising: false, zenith: 90.833) {
            let dawn = solar(now, lat: lat, lon: lon, rising: true, zenith: 96) ?? rise.addingTimeInterval(-1800)
            let dusk = solar(now, lat: lat, lon: lon, rising: false, zenith: 96) ?? set.addingTimeInterval(1800)
            return Day(dawn: dawn, rise: rise, set: set, dusk: dusk)
        }
        // 3. Polar day or night: a plain 6 AM–9 PM.
        let cal = Calendar.current
        let r = cal.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        let s = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now
        return Day(dawn: r.addingTimeInterval(-1800), rise: r, set: s, dusk: s.addingTimeInterval(1800))
    }

    /// Sunrise or sunset on the calendar day of `date` (local), NOAA's sunrise equation.
    /// Zenith 90.833° is the visible sunrise/sunset; 96° is civil dawn/dusk.
    static func solar(_ date: Date, lat: Double, lon: Double, rising: Bool, zenith: Double, timeZone: TimeZone = .current) -> Date? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let rad = Double.pi / 180
        let n = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let lngHour = lon / 15
        let t = n + ((rising ? 6 : 18) - lngHour) / 24
        let m = 0.9856 * t - 3.289
        var l = m + 1.916 * sin(m * rad) + 0.020 * sin(2 * m * rad) + 282.634
        l = l.truncatingRemainder(dividingBy: 360); if l < 0 { l += 360 }
        var ra = atan(0.91764 * tan(l * rad)) / rad
        ra = ra.truncatingRemainder(dividingBy: 360); if ra < 0 { ra += 360 }
        ra += floor(l / 90) * 90 - floor(ra / 90) * 90
        ra /= 15
        let sinDec = 0.39782 * sin(l * rad)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(zenith * rad) - sinDec * sin(lat * rad)) / (cosDec * cos(lat * rad))
        guard cosH <= 1, cosH >= -1 else { return nil }          // the sun doesn't rise or set that day
        var h = rising ? 360 - acos(cosH) / rad : acos(cosH) / rad
        h /= 15
        let localT = h + ra - 0.06571 * t - 6.622
        var ut = (localT - lngHour).truncatingRemainder(dividingBy: 24); if ut < 0 { ut += 24 }
        // UT hours on this calendar date, then nudged by a day if that lands on the wrong local day.
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard let midnightUTC = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) else { return nil }
        var result = midnightUTC.addingTimeInterval(ut * 3600)
        let localStart = cal.startOfDay(for: date)
        if result < localStart { result = result.addingTimeInterval(86_400) }
        if result >= localStart.addingTimeInterval(86_400) { result = result.addingTimeInterval(-86_400) }
        return result
    }
}
