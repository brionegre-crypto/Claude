import XCTest
import SwiftData
@testable import Keel

/// Keel's automated tests. Xcode Cloud runs these on an iPhone simulator with every build (Test action),
/// so a change that breaks reminders, inbox sorting, notes, backups or encryption is caught before TestFlight.
@MainActor
final class KeelTests: XCTestCase {

    // An in-memory database, so tests never touch your real data.
    private func makeContext() throws -> ModelContext {
        let schema = Schema(KeelStore.syncedTypes + KeelStore.localTypes)
        // In memory and never iCloud: the test database must not try to sync (mail models are local-only by design).
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    private func email(from: String, name: String = "", subject: String = "Hi", body: String = "Can you send it over?") -> EmailMessage {
        EmailMessage(accountId: "acct", providerMessageId: UUID().uuidString, threadId: "t", from: from, fromName: name,
                     subject: subject, snippet: String(body.prefix(80)), bodyPlain: body, receivedAt: Date(), isRead: false)
    }

    // MARK: Reminders (natural language)

    func testRemindMePrefixAndTime() {
        let r = QuickAdd.parse("remind me to call mom tomorrow 5pm")
        XCTAssertEqual(r.title.lowercased(), "call mom")
        let due = try? XCTUnwrap(r.dueDate)
        XCTAssertNotNil(due)
        if let due {
            XCTAssertTrue(Calendar.current.isDateInTomorrow(due))
            XCTAssertEqual(Calendar.current.component(.hour, from: due), 17)
        }
    }

    func testEveryOtherWeek() {
        let r = QuickAdd.parse("water plants every other week")
        XCTAssertEqual(r.recurrence?.frequency, .weekly)
        XCTAssertEqual(r.recurrence?.interval, 2)
        XCTAssertEqual(r.title.lowercased(), "water plants")
    }

    func testEveryOtherWeekday() {
        let r = QuickAdd.parse("team lunch every other tuesday")
        XCTAssertEqual(r.recurrence?.frequency, .weekly)
        XCTAssertEqual(r.recurrence?.interval, 2)
        XCTAssertEqual(r.recurrence?.weekdays, [3])
    }

    func testTagsListAndPriority() {
        let r = QuickAdd.parse("buy paper #work ~Errands !high")
        XCTAssertEqual(r.title, "buy paper")
        XCTAssertEqual(r.tags, ["work"])
        XCTAssertEqual(r.list, "Errands")
        XCTAssertEqual(r.priority, .high)
    }

    // MARK: Mail

    func testRealPeopleVsBusinesses() {
        XCTAssertTrue(AutoDrafts.isRealPerson(email(from: "dana@acme.com", name: "Dana Lee")))
        XCTAssertFalse(AutoDrafts.isRealPerson(email(from: "noreply@acme.com", name: "Acme")))
        XCTAssertFalse(AutoDrafts.isRealPerson(email(from: "support@shop.com", name: "Shop Support")))
        XCTAssertFalse(AutoDrafts.isRealPerson(email(from: "hello@brand.com", name: "Brand Team")))
        XCTAssertFalse(AutoDrafts.isRealPerson(email(from: "dana@acme.com", name: "Acme Inc")))
    }

    func testCustomInboxTabMatching() {
        let tab = CustomMailTab(name: "Clients", senders: ["@acme.com"], keywords: ["invoice"])
        XCTAssertTrue(MailTabs.matches(email(from: "dana@acme.com"), tab))
        XCTAssertTrue(MailTabs.matches(email(from: "x@other.com", subject: "Invoice 42"), tab))
        XCTAssertFalse(MailTabs.matches(email(from: "x@other.com", subject: "Lunch?"), tab))
    }

    func testEmailToKeelAddress() {
        let gmail = MailAccount(provider: .gmail, address: "brian@gmail.com", displayName: "Brian")
        XCTAssertEqual(EmailToKeel.address(for: gmail), "brian+keel@gmail.com")
        let icloud = MailAccount(provider: .icloud, address: "brian@icloud.com", displayName: "Brian")
        XCTAssertNil(EmailToKeel.address(for: icloud))
    }

    func testGenericMeetingTitles() {
        XCTAssertTrue(MeetingTitler.isGeneric("Sync"))
        XCTAssertTrue(MeetingTitler.isGeneric("1:1"))
        XCTAssertFalse(MeetingTitler.isGeneric("Q3 budget review"))
    }

    // MARK: Notes

    func testFormulaMath() {
        let price = DBProperty(name: "Price", kind: .number), qty = DBProperty(name: "Quantity", kind: .number)
        let done = DBProperty(name: "Done", kind: .checkbox)
        let row = Note(title: "Row")
        row.props[price.id] = "12.5"; row.props[qty.id] = "4"; row.props[done.id] = "1"
        let schema = [price, qty, done]
        XCTAssertEqual(DBFormula.evaluate("{Price} * {Quantity}", row: row, schema: schema), "50")
        XCTAssertEqual(DBFormula.evaluate("({Price} + 7.5) / 2", row: row, schema: schema), "10")
        XCTAssertEqual(DBFormula.evaluate("{Done} * 100", row: row, schema: schema), "100")
        XCTAssertEqual(DBFormula.evaluate("1 / 0", row: row, schema: schema), "")          // no crash, just empty
        XCTAssertEqual(DBFormula.evaluate("2 +", row: row, schema: schema), "")             // bad input is ignored
    }

    func testFlashcardsFoundAndScheduled() {
        var toggle = NoteBlock(kind: .toggle, text: "Capital of France?")
        toggle.body = "Paris"
        let n = Note(title: "Study", blocks: [NoteBlock(kind: .text, text: "Mitochondria :: powerhouse of the cell"), toggle, NoteBlock(kind: .text, text: "Not a card")])
        let cards = Flashcards.cards([n])
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(Flashcards.due([n]).count, 2)
        Flashcards.grade(cards[0], 2)                 // Good → not due again today
        XCTAssertEqual(Flashcards.due([n]).count, 1)
        XCTAssertGreaterThan(Flashcards.state(cards[0]).due, Date())
    }

    func testSmartTemplateVariables() {
        let filled = SmartTemplates.fill("Review · {{weekday}} · {{title}}", title: "Weekly")
        XCTAssertFalse(filled.contains("{{"))
        XCTAssertTrue(filled.contains(Date().formatted(.dateTime.weekday(.wide))))
        XCTAssertTrue(filled.hasSuffix("Weekly"))
    }

    func testSupertagsDetected() {
        let defs = Supertags.defaults
        let tags = Supertags.tags(in: "Atomic Habits #book by James Clear", defs: defs)
        XCTAssertEqual(tags.map(\.name), ["book"])
        XCTAssertTrue(Supertags.tags(in: "#bookshelf idea", defs: defs).isEmpty)      // whole word only
    }

    func testLinkRepairFindsClosestPage() throws {
        let ctx = try makeContext()
        let a = Note(title: "Kitchen remodel"); let b = Note(title: "Notes", blocks: [NoteBlock(kind: .text, text: "See [[Kitchn remodel]] and [[Nowhere at all]]")])
        ctx.insert(a); ctx.insert(b)
        let fixes = StarterSetup.brokenLinks([a, b])
        XCTAssertEqual(fixes.count, 2)
        XCTAssertEqual(fixes.first { $0.broken == "Kitchn remodel" }?.fix, "Kitchen remodel")
        XCTAssertNil(fixes.first { $0.broken == "Nowhere at all" }?.fix)
        StarterSetup.repair(fixes.first { $0.broken == "Kitchn remodel" }!, notes: [a, b])
        XCTAssertTrue(b.plainText.contains("[[Kitchen remodel]]"))
    }

    func testMarkdownRoundTrip() {
        let n = Note(title: "Plan", blocks: [NoteBlock(kind: .heading2, text: "Goals"), NoteBlock(kind: .bullet, text: "Ship it"),
                                            NoteBlock(kind: .todo, text: "Write tests")])
        let md = NoteExport.markdown(n)
        let back = MarkdownImport.parse(md, dir: "")
        let kinds = back.blocks.map(\.kind)
        XCTAssertTrue(kinds.contains(.bullet))
        XCTAssertTrue(kinds.contains(.todo))
        XCTAssertTrue(back.blocks.contains { $0.text.contains("Ship it") })
    }

    func testSpecialBlocksStayReadable() {
        var b = NoteBlock(kind: .code, text: "E = mc^2"); b.lang = SpecialBlock.math
        XCTAssertEqual(SpecialBlock.kind(b), SpecialBlock.math)
        var canvas = NoteBlock(kind: .code, text: "{}"); canvas.lang = "keel-canvas"
        XCTAssertNil(SpecialBlock.kind(canvas))
        XCTAssertNotNil(SpecialBlock.lang(for: "columns"))
    }

    // MARK: Safety: trash, backups, encryption

    func testTrashKeepsAndRestoresPage() throws {
        let ctx = try makeContext()
        let n = Note(title: "Keep me", blocks: [NoteBlock(kind: .text, text: "important")])
        ctx.insert(n); try ctx.save()
        let id = n.id
        NoteTrash.delete(n, ctx: ctx); try ctx.save()
        XCTAssertTrue(((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).isEmpty)
        let snap = try XCTUnwrap(NoteTrash.items.first { $0.id == id })
        NoteTrash.restore(snap, ctx: ctx)
        let back = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Note>()).first)
        XCTAssertEqual(back.id, id)
        XCTAssertEqual(back.plainText, "important")
    }

    func testBackupRestoresOnlyWhatsMissing() throws {
        let ctx = try makeContext()
        let n = Note(title: "Backed up"); let t = TaskItem(title: "Task in backup"); let p = Person(name: "Dana")
        ctx.insert(n); ctx.insert(t); ctx.insert(p); try ctx.save()
        let url = try XCTUnwrap(BrainBackup.make(ctx: ctx))
        ctx.delete(n); ctx.delete(t); try ctx.save()
        let c = BrainBackup.restoreMissing(from: url, ctx: ctx)
        XCTAssertEqual(c.notes, 1); XCTAssertEqual(c.tasks, 1); XCTAssertEqual(c.people, 0)    // Dana was never gone
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Note>()).count, 1)
        try? FileManager.default.removeItem(at: url)
    }

    func testLockedPageEncryptsAndDecrypts() throws {
        let n = Note(title: "Secret", blocks: [NoteBlock(kind: .text, text: "the code is 4521")])
        n.isLocked = true
        PageCrypto.encrypt(n)
        try XCTSkipUnless(PageCrypto.isEncrypted(n), "Keychain isn't available in this simulator run")
        XCTAssertFalse(n.plainText.contains("4521"))
        PageCrypto.decrypt(n)
        XCTAssertFalse(PageCrypto.isEncrypted(n))
        XCTAssertEqual(n.plainText, "the code is 4521")
    }

    // MARK: Importers

    func testCSVParsing() {
        let rows = ReadingImport.parseCSV("url,title,selection\nhttps://a.com,\"Hello, world\",\"He said \"\"hi\"\"\"\nhttps://b.com,B,\n")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][1], "Hello, world")
        XCTAssertEqual(rows[1][2], "He said \"hi\"")
        XCTAssertEqual(rows[2][0], "https://b.com")
    }

    func testReaderExtractsArticle() {
        let html = """
        <html><head><title>Big &amp; Bold</title><script>var x = 1;</script></head>
        <body><nav>Menu</nav><article><h2>Intro</h2><p>This is the first real paragraph of the article, long enough to keep.</p>
        <p>Short</p><p>And here is a second paragraph that also has enough words to be kept as content.</p></article></body></html>
        """
        let r = ReaderStore.extract(html)
        XCTAssertEqual(r.title, "Big & Bold")
        XCTAssertEqual(r.paras.first, "Intro")
        XCTAssertEqual(r.paras.count, 3)
        XCTAssertFalse(r.paras.contains("Short"))
        XCTAssertFalse(r.paras.joined().contains("var x"))
    }

    // MARK: Smart paste

    func testPasteSpreadsheetBecomesTable() {
        let b = SmartPaste.blocks(from: "Name\tQty\nApples\t3\nPears\t5")
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.first?.kind, .table)
        XCTAssertEqual(b.first?.rows?[2], ["Pears", "5"])
    }

    func testPasteLinkBecomesBookmark() {
        let b = SmartPaste.blocks(from: "https://example.com/article")
        XCTAssertEqual(b.first?.kind, .bookmark)
        XCTAssertEqual(b.first?.refId, "https://example.com/article")
    }

    func testPasteMarkdownKeepsStructure() {
        let b = SmartPaste.blocks(from: "## Plan\n\n\n\n- one\n- two\n- [ ] call Dana")
        XCTAssertTrue([.heading, .heading2, .heading3].contains(b.first?.kind ?? .text))   // "## Plan" stays a heading
        XCTAssertEqual(b.filter { $0.kind == .bullet }.count, 2)
        XCTAssertEqual(b.filter { $0.kind == .todo }.count, 1)
        XCTAssertFalse(b.contains { $0.kind == .text && $0.text.isEmpty })        // no stray empty lines
    }

    func testPasteRejoinsHardWrappedParagraphs() {
        let b = SmartPaste.blocks(from: "This sentence was wrapped\nin the middle by an email app.\n\nSecond paragraph.")
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b.first?.text, "This sentence was wrapped in the middle by an email app.")
    }

    // MARK: Layout settings

    func testTabBarAlwaysStartsWithToday() {
        let saved = UserDefaults.standard.stringArray(forKey: TabBarConfig.key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: TabBarConfig.key) } else { UserDefaults.standard.removeObject(forKey: TabBarConfig.key) } }
        UserDefaults.standard.set(["notes", "today", "inbox", "calendar", "tasks", "tool:nope", "notes"], forKey: TabBarConfig.key)
        let items = TabBarConfig.items
        XCTAssertEqual(items.first, "today")
        XCTAssertLessThanOrEqual(items.count, TabBarConfig.maxTabs)
        XCTAssertFalse(items.contains("tool:nope"))
        XCTAssertEqual(Set(items).count, items.count)                                  // no section twice
    }

    func testEditDistance() {
        XCTAssertEqual(StarterSetup.distance("kitchen", "kitchn"), 1)
        XCTAssertEqual(StarterSetup.distance("", "abc"), 3)
        XCTAssertEqual(StarterSetup.distance("same", "same"), 0)
    }
}
