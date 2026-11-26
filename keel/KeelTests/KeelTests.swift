import XCTest
import SwiftData
import UserNotifications
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

    // MARK: Hey Keel

    func testHeyKeelHeardManyWays() {
        XCTAssertEqual(VoiceLoop.wakeMatch("Hey, Keel. What's next?")?.rest, "what's next")
        XCTAssertEqual(VoiceLoop.wakeMatch("hey kiel add milk to groceries")?.rest, "add milk to groceries")
        XCTAssertEqual(VoiceLoop.wakeMatch("so anyway Hey Kyle read my email")?.rest, "read my email")
        XCTAssertNotNil(VoiceLoop.wakeMatch("Okay Keel"))
        XCTAssertNotNil(VoiceLoop.wakeMatch("heykeel"))
        XCTAssertEqual(VoiceLoop.wakeMatch("Hey Keel")?.rest, "")
    }

    func testHeyKeelIgnoresOtherSpeech() {
        XCTAssertNil(VoiceLoop.wakeMatch("hey Kelly how are you"))
        XCTAssertNil(VoiceLoop.wakeMatch("the keel of the boat"))
        XCTAssertNil(VoiceLoop.wakeMatch("hey there"))
        XCTAssertNil(VoiceLoop.wakeMatch(""))
    }

    // MARK: Flow

    func testCaptureGuessesWhatYouMeant() {
        XCTAssertEqual(CaptureClassifier.guess("Lunch with Sam tomorrow 1pm"), .event)
        XCTAssertEqual(CaptureClassifier.guess("remind me to water plants"), .reminder)
        XCTAssertEqual(CaptureClassifier.guess("buy milk"), .task)
        XCTAssertEqual(CaptureClassifier.guess("Idea: a bakery app\nthat delivers"), .note)
    }

    func testLifeAreasFromTitles() {
        XCTAssertEqual(LifeBalance.area(for: "Gym with Alex"), .health)
        XCTAssertEqual(LifeBalance.area(for: "Pay the electric bill"), .wealth)
        XCTAssertEqual(LifeBalance.area(for: "Dinner with mom"), .relationships)
        XCTAssertEqual(LifeBalance.area(for: "Quarterly planning"), .work)
    }

    func testLinksBetweenAnything() throws {
        let ctx = try makeContext()
        let n = Note(title: "Plan"); let t = TaskItem(title: "Do it")
        ctx.insert(n); ctx.insert(t)
        t.sourceNoteId = n.id
        KeelLinks.add("note:\(n.id.uuidString)", "person:abc", ctx: ctx)
        let c = KeelLinks.connected("note:\(n.id.uuidString)", ctx: ctx)
        XCTAssertTrue(c.contains("person:abc"))
        XCTAssertTrue(c.contains("task:\(t.id.uuidString)"))             // made from this page, linked for free
        KeelLinks.remove("note:\(n.id.uuidString)", "person:abc", ctx: ctx)
        XCTAssertFalse(KeelLinks.connected("note:\(n.id.uuidString)", ctx: ctx).contains("person:abc"))
    }

    func testOpenWaterLabel() {
        let a = Date(), b = a.addingTimeInterval(2 * 3600 + 30 * 60)
        XCTAssertEqual(VoyageView.span(a, b), "Open water · 2h 30m")
        XCTAssertEqual(VoyageView.span(a, a.addingTimeInterval(50 * 60)), "Open water · 50 min")
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

    // MARK: AI writing

    func testWriterModelRoundTrip() {
        let m = WriterModel(provider: .claude, model: "claude-sonnet-5-5")
        XCTAssertEqual(WriterModel(id: m.id), m)
        XCTAssertEqual(m.label, "Claude Sonnet")
        XCTAssertEqual(WriterModel(id: "apple|")?.provider, .apple)
        XCTAssertNil(WriterModel(id: "nope|x"))
    }

    func testStreamedTextIsReadFromEachProvider() throws {
        let claude: [String: Any] = ["type": "content_block_delta", "delta": ["type": "text_delta", "text": "Hel"]]
        XCTAssertEqual(try WriterStreams.text(in: claude, provider: .claude), "Hel")
        XCTAssertNil(try WriterStreams.text(in: ["type": "message_start"], provider: .claude))
        XCTAssertThrowsError(try WriterStreams.text(in: ["type": "message_delta", "delta": ["stop_reason": "refusal"]], provider: .claude))
        let openai: [String: Any] = ["choices": [["delta": ["content": "lo"]]]]
        XCTAssertEqual(try WriterStreams.text(in: openai, provider: .openai), "lo")
        let gemini: [String: Any] = ["candidates": [["content": ["parts": [["text": "!"]]]]]]
        XCTAssertEqual(try WriterStreams.text(in: gemini, provider: .gemini), "!")
    }

    func testStreamRequestsAreBuiltForEachProvider() throws {
        for p in [AIProvider.claude, .openai, .gemini] {
            let r = try WriterStreams.request(p, model: "m", key: "k", system: "s", user: "u")
            XCTAssertEqual(r.httpMethod, "POST")
            let body = try XCTUnwrap(r.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
            if p == .gemini { XCTAssertTrue(r.url!.absoluteString.contains("alt=sse")) } else { XCTAssertEqual(body["stream"] as? Bool, true) }
        }
    }

    func testAIPromptCarriesThePage() {
        let p = AIWriter.prompt(for: .edit, instruction: "Shorter", source: "a long line", title: "Trip", page: "Pack bags")
        XCTAssertTrue(p.contains("a long line") && p.contains("Trip") && p.contains("Shorter"))
        XCTAssertTrue(SlashCommand.matching("ai").contains { $0.id == "ai" })
        XCTAssertEqual(SpecialBlock.lang(for: "aiblock"), SpecialBlock.aiblock)
    }

    // MARK: Duplicate tasks

    func testDuplicateTasksAreMerged() throws {
        let ctx = try makeContext()
        let due = Date().addingTimeInterval(3600)
        let a = TaskItem(title: "Empty trash if bin is full", dueDate: due); a.ekReminderId = "r1"
        let b = TaskItem(title: "Empty  trash if bin is full", dueDate: due); b.notes = "kept"
        let c = TaskItem(title: "Rub her feet", dueDate: due)
        let d = TaskItem(title: "Buy milk"), e = TaskItem(title: "Buy milk")       // no date, not linked: left alone
        [a, b, c, d, e].forEach { ctx.insert($0) }
        XCTAssertEqual(TaskDedupe.run(ctx: ctx), 1)
        let left = try ctx.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(left.count, 4)
        XCTAssertTrue(left.contains { $0.ekReminderId == "r1" && $0.notes == "kept" })    // the linked copy stays, with the notes
        XCTAssertEqual(TaskDedupe.run(ctx: ctx), 0)
    }

    // MARK: Typing

    func testTypingSavesRightAwayOnlyWhenThePageMustReact() {
        XCTAssertFalse(BlockTextField.needsNow(old: "Groceries for the wee", new: "Groceries for the week"))   // plain typing waits
        XCTAssertTrue(BlockTextField.needsNow(old: "Milk", new: "Milk\n"))                                    // Return makes a new line
        XCTAssertTrue(BlockTextField.needsNow(old: "", new: "/"))                                             // the / menu
        XCTAssertTrue(BlockTextField.needsNow(old: "", new: "- "))                                            // Markdown shortcut
        XCTAssertTrue(BlockTextField.needsNow(old: "Hello", new: "Hello there, pasted text"))                  // paste
        XCTAssertTrue(BlockTextField.needsNow(old: "Call ", new: "Call @"))                                   // a mention
    }

    // MARK: Booking link, assigning, alerts

    func testBookingSlotsFitYourHoursAndLength() {
        let keys = [BookingLink.minutesKey, BookingLink.daysKey, BookingLink.startKey, BookingLink.endKey, BookingLink.weekendsKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { if let v { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) } } }
        UserDefaults.standard.set(30, forKey: BookingLink.minutesKey)
        UserDefaults.standard.set(7, forKey: BookingLink.daysKey)
        UserDefaults.standard.set(9, forKey: BookingLink.startKey)
        UserDefaults.standard.set(17, forKey: BookingLink.endKey)
        UserDefaults.standard.set(false, forKey: BookingLink.weekendsKey)
        let iso = ISO8601DateFormatter(), cal = Calendar.current
        let slots = BookingLink.slots()
        for s in slots {
            let a = iso.date(from: s["start"]!)!, b = iso.date(from: s["end"]!)!
            XCTAssertEqual(b.timeIntervalSince(a), 30 * 60)
            XCTAssertGreaterThanOrEqual(cal.component(.hour, from: a), 9)
            XCTAssertLessThanOrEqual(b, cal.date(bySettingHour: 17, minute: 0, second: 0, of: a)!)
            XCTAssertFalse([1, 7].contains(cal.component(.weekday, from: a)))       // no weekends
            XCTAssertGreaterThan(a, Date().addingTimeInterval(2 * 3600 - 60))        // never in the next two hours
        }
    }

    func testAssigningATaskMovesItToWaiting() throws {
        let ctx = try makeContext()
        let t = TaskItem(title: "Book the venue"); ctx.insert(t)
        TaskAssign.assign(t, to: "Sam Lee", email: "sam@example.com", ctx: ctx)
        XCTAssertTrue(t.isWaitingOn)
        XCTAssertEqual(TaskAssign.who(t, ctx: ctx)?.name, "Sam Lee")
        let mail = TaskAssign.handoffEmail(t, to: TaskAssign.who(t, ctx: ctx)!)
        XCTAssertEqual(mail.to, "sam@example.com")
        XCTAssertTrue(mail.body.contains("Book the venue") && mail.body.hasPrefix("Hi Sam"))
        TaskAssign.unassign(t, ctx: ctx)
        XCTAssertFalse(t.isWaitingOn)
        XCTAssertNil(TaskAssign.who(t, ctx: ctx))
    }

    func testMailAlertsHaveReplyArchiveAndRead() {
        let ids = MailNotify.categoryDefinition.actions.map(\.identifier)
        XCTAssertEqual(Set(ids), [MailNotify.replyAction, MailNotify.archiveAction, MailNotify.readAction])
        XCTAssertTrue(MailNotify.categoryDefinition.actions.first is UNTextInputNotificationAction)
    }

    func testDatabaseHasTimelineView() {
        XCTAssertTrue(NotesDatabase.views.contains { $0.id == "timeline" })
        XCTAssertTrue(FocusSound.Kind.allCases.contains(.rain) && FocusSound.Kind.allCases.contains(.fan))
    }

    // MARK: Settings on every device

    func testOnlyKeelSettingsSyncAndDeviceOnesStayLocal() {
        XCTAssertTrue(SettingsSync.syncs("ai.provider"))
        XCTAssertTrue(SettingsSync.syncs("ai.writer.default"))
        XCTAssertTrue(SettingsSync.syncs("look.theme"))
        XCTAssertTrue(SettingsSync.syncs("imap.server.icloud:me@icloud.com"))      // so mail works on the Mac too
        XCTAssertFalse(SettingsSync.syncs("reminders.bridge"))                    // only one device syncs Reminders
        XCTAssertFalse(SettingsSync.syncs("calendar.hidden"))                     // calendar ids differ per device
        XCTAssertFalse(SettingsSync.syncs("throttle.backup"))
        XCTAssertFalse(SettingsSync.syncs("AppleLanguages"))                      // iOS's own settings
        XCTAssertFalse(SettingsSync.syncs("NSInterfaceStyle"))
        XCTAssertFalse(SettingsSync.syncs("com.apple.something"))
    }

    // MARK: Body (Tide, Swell, Anchor)

    func testSwellRisesThenLevelsOff() {
        XCTAssertEqual(BodyMath.swell(0), 0)
        XCTAssertLessThan(BodyMath.swell(60), BodyMath.swell(180))
        XCTAssertLessThan(BodyMath.swell(1_000), 100 + 1)
        XCTAssertGreaterThan(BodyMath.swell(180) - BodyMath.swell(60), BodyMath.swell(600) - BodyMath.swell(480))   // levels off
    }

    func testHeartRateZonesCountHarderMinutesMore() {
        let start = Date()
        func hr(_ bpm: Double) -> [BodyRaw.Q] { (0..<30).map { BodyRaw.Q(start: start.addingTimeInterval(Double($0) * 60), end: start.addingTimeInterval(Double($0) * 60), value: bpm) } }
        let easy = BodyMath.trimp(hr(115), maxHR: 190, from: start, to: start.addingTimeInterval(3600))
        let hard = BodyMath.trimp(hr(175), maxHR: 190, from: start, to: start.addingTimeInterval(3600))
        let resting = BodyMath.trimp(hr(60), maxHR: 190, from: start, to: start.addingTimeInterval(3600))
        XCTAssertEqual(resting, 0)
        XCTAssertGreaterThan(hard, easy * 2)
    }

    func testTideFollowsYourOwnNormal() {
        let cal = Calendar.current
        var days: [BodyDay] = (0..<12).map { i in
            var d = BodyDay(day: cal.date(byAdding: .day, value: i - 12, to: cal.startOfDay(for: Date()))!)
            d.hrv = 50 + Double(i % 3); d.rhr = 55 + Double(i % 2); d.asleep = 450; d.inBed = 480
            return d
        }
        var good = BodyDay(day: cal.startOfDay(for: Date())); good.hrv = 70; good.rhr = 50; good.asleep = 470; good.inBed = 490
        var bad = good; bad.hrv = 32; bad.rhr = 64; bad.asleep = 280; bad.inBed = 400
        var a = days + [good], b = days + [bad]
        BodyMath.score(&a, base: 8)
        BodyMath.score(&b, base: 8)
        XCTAssertGreaterThan(a.last!.tide!, 67)
        XCTAssertLessThan(b.last!.tide!, 34)
        XCTAssertGreaterThan(a.last!.anchor!, b.last!.anchor!)
        XCTAssertFalse(a.last!.calibrating)
        days.removeAll()
    }

    func testSwellTargetAndSleepNeed() {
        XCTAssertEqual(BodyMath.swellTarget(80), 60...80)
        XCTAssertEqual(BodyMath.swellTarget(20), 15...35)
        XCTAssertEqual(BodyMath.effortExtra(30), 0)
        XCTAssertGreaterThan(BodyMath.effortExtra(80), 0)
        let tn = BodyMath.tonight([], base: 8)
        XCTAssertEqual(tn.need, 8, accuracy: 0.01)
        XCTAssertEqual(tn.wake.timeIntervalSince(tn.bedtime), 8 * 3600 + 15 * 60, accuracy: 1)
    }

    func testHabitImpactNeedsEnoughDays() {
        let cal = Calendar.current
        var days: [BodyDay] = []
        var journal: [String: [String]] = [:]
        for i in 0..<10 {
            let d = cal.date(byAdding: .day, value: i - 10, to: cal.startOfDay(for: Date()))!
            var b = BodyDay(day: cal.date(byAdding: .day, value: 1, to: d)!)
            let drank = i % 2 == 0
            b.tide = drank ? 40 : 70
            days.append(b)
            if drank { journal[BodyMath.dayKey(d)] = ["Alcohol"] } else { journal[BodyMath.dayKey(d)] = ["Read before bed"] }
        }
        let impact = BodyMath.habitImpact(journal: journal, days: days)
        XCTAssertEqual(impact.first { $0.tag == "Alcohol" }?.delta, -30)
        XCTAssertEqual(BodyMath.habitImpact(journal: [:], days: days).count, 0)
    }

    // MARK: Sun, journal, gifts, upkeep, insights

    func testSunriseAndSunsetMatchTheRealSky() throws {
        // New York, 21 June 2026: sunrise about 5:25 AM, sunset about 8:31 PM (EDT).
        let ny = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        let day = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12)))
        let rise = try XCTUnwrap(SunClock.solar(day, lat: 40.7128, lon: -74.0060, rising: true, zenith: 90.833, timeZone: ny))
        let set = try XCTUnwrap(SunClock.solar(day, lat: 40.7128, lon: -74.0060, rising: false, zenith: 90.833, timeZone: ny))
        let r = cal.dateComponents([.hour, .minute], from: rise), s = cal.dateComponents([.hour, .minute], from: set)
        XCTAssertEqual(Double(r.hour! * 60 + r.minute!), 5 * 60 + 25, accuracy: 5)
        XCTAssertEqual(Double(s.hour! * 60 + s.minute!), 20 * 60 + 31, accuracy: 5)
        // Far north in midsummer the sun doesn't set.
        XCTAssertNil(SunClock.solar(day, lat: 78, lon: 15, rising: false, zenith: 90.833, timeZone: ny))
    }

    func testVoiceJournalFindsTasks() {
        let t = VoiceJournal.tasks("Today was long. I need to call the dentist and I should email Sam about the budget. Remember to buy milk!")
        XCTAssertEqual(t, ["Call the dentist", "Email Sam about the budget", "Buy milk"])
        XCTAssertTrue((1...5).contains(VoiceJournal.mood("I had a wonderful, happy day with friends")))
    }

    func testNextBirthday() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        let soon = Gifts.nextOccurrence(month: 11, day: 20, year: 1990, from: now)
        XCTAssertEqual(soon?.1, 36)
        XCTAssertEqual(cal.component(.year, from: soon!.0), 2026)
        let passed = Gifts.nextOccurrence(month: 3, day: 2, year: nil, from: now)
        XCTAssertEqual(cal.component(.year, from: passed!.0), 2027)
        XCTAssertNil(passed?.1)
    }

    func testUpkeepRepeats() {
        XCTAssertEqual(Upkeep.recurrence(90).frequency, .monthly)
        XCTAssertEqual(Upkeep.recurrence(90).interval, 3)
        XCTAssertEqual(Upkeep.recurrence(365).frequency, .yearly)
        XCTAssertEqual(Upkeep.recurrence(10).frequency, .daily)
        XCTAssertEqual(Upkeep.recurrence(180).fromCompletion, true)
    }

    func testWorkoutPickFollowsTide() {
        XCTAssertEqual(WorkoutPick.pick(tide: 80, swell: 10).title, "Push day")
        XCTAssertEqual(WorkoutPick.pick(tide: 20, swell: 5).title, "Recovery day")
        XCTAssertEqual(WorkoutPick.pick(tide: 80, swell: 95).title, "You've done enough today")
    }

    func testMoodInsightsNeedEnoughDays() {
        let cal = Calendar.current
        var days: [BodyDay] = []
        var moods: [(day: Date, mood: Int)] = []
        for i in 0..<8 {
            let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: Date()))!
            var b = BodyDay(day: d); b.asleep = i % 2 == 0 ? 300 : 480
            days.append(b)
            moods.append((day: d, mood: i % 2 == 0 ? 2 : 4))
        }
        let out = BodyMath.moodInsights(moods: moods, focus: [], days: days)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].contains("lower"))
        XCTAssertTrue(BodyMath.moodInsights(moods: [], focus: [], days: days).isEmpty)
    }

    // MARK: Health tools

    func testAsNeededMedicineWaitsLongEnough() {
        let m = PRNMed(name: "Ibuprofen", dose: "400 mg", minHours: 4, maxPerDay: 3)
        let now = Date()
        XCTAssertNil(PRN.check(m, doses: [], now: now))
        XCTAssertNotNil(PRN.check(m, doses: [PRNDose(medId: m.id, at: now.addingTimeInterval(-2 * 3600))], now: now))
        XCTAssertNil(PRN.check(m, doses: [PRNDose(medId: m.id, at: now.addingTimeInterval(-5 * 3600))], now: now))
    }

    func testBloodPressureCategories() {
        XCTAssertEqual(BloodPressure.category(115, 75).0, "Normal")
        XCTAssertEqual(BloodPressure.category(125, 78).0, "Elevated")
        XCTAssertEqual(BloodPressure.category(135, 85).0, "High (stage 1)")
        XCTAssertEqual(BloodPressure.category(150, 95).0, "High (stage 2)")
    }

    func testCaffeineHalvesEveryFiveHours() {
        let t = Date()
        let d = [Drink(kind: "coffee", at: t.addingTimeInterval(-5 * 3600), caffeine: 100, water: 0)]
        XCTAssertEqual(BodyMath.caffeineNow(d, at: t), 50, accuracy: 0.5)
        XCTAssertEqual(BodyMath.caffeineNow(d, at: t.addingTimeInterval(-6 * 3600)), 0)       // before you drank it
    }

    func testBodyMapKnowsWhatARunWorks() {
        XCTAssertTrue(BodyRegions.worked(by: "Run").contains("f.quadL"))
        XCTAssertTrue(BodyRegions.worked(by: "Swim").contains("b.upperback"))
        XCTAssertEqual(Set(BodyRegions.all.map(\.id)).count, BodyRegions.all.count)          // every region has its own id
        XCTAssertTrue(BodyRegions.worked(by: "Strength").allSatisfy { BodyRegions.region($0) != nil })
    }

    func testCycleEstimate() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let starts = [-62, -34, -6].compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let days = starts.flatMap { s in (0..<4).compactMap { cal.date(byAdding: .day, value: $0, to: s) } }
        let c = BodyMath.cycle(periodDays: days)
        XCTAssertEqual(c?.length, 28)
        XCTAssertEqual(c?.day, 7)
    }

    func testEnergyLeftAndStreak() {
        var d = BodyDay(day: Date()); d.tide = 80; d.swell = 40; d.wake = Date().addingTimeInterval(-6 * 3600)
        XCTAssertEqual(BodyMath.energyLeft(d), 66)
        let cal = Calendar.current
        let days = (0..<5).map { i -> BodyDay in var b = BodyDay(day: cal.date(byAdding: .day, value: i - 4, to: cal.startOfDay(for: Date()))!); b.asleep = i == 0 ? 300 : 450; return b }
        XCTAssertEqual(BodyMath.streak(days) { $0.asleep >= 420 }, 4)
    }

    func testLogDoseCountsAsClosestSlotThenExtra() throws {
        let ctx = try makeContext()
        let m = Medication(name: "Test med", dose: "10 mg", times: [8 * 60, 20 * 60])
        m.pillsLeft = 10
        ctx.insert(m)
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 7, minute: 40, second: 0, of: Date())!
        let open = MedLog.openSlots(m, on: morning, doses: [])
        XCTAssertEqual(MedLog.bestSlot(open, at: morning), 8 * 60)
        let first = MedLog.log(m, slot: MedLog.bestSlot(open, at: morning), at: morning, ctx: ctx)
        XCTAssertEqual(first.slot, 8 * 60)
        XCTAssertEqual(first.takenAt, morning)
        XCTAssertFalse(MedLog.isExtra(first))
        // Same slot again becomes an extra dose instead of overwriting.
        let again = MedLog.log(m, slot: 8 * 60, at: morning, ctx: ctx)
        XCTAssertTrue(MedLog.isExtra(again))
        let extra2 = MedLog.log(m, slot: nil, at: morning, ctx: ctx)
        XCTAssertNotEqual(again.slot, extra2.slot)
        XCTAssertEqual(m.pillsLeft, 7)
        let doses = try ctx.fetch(FetchDescriptor<MedDose>())
        XCTAssertEqual(MedLog.openSlots(m, on: morning, doses: doses), [20 * 60])
    }

    func testBodyMetricFormatAndBaseline() {
        XCTAssertEqual(BodyMetric.sleep.format(7.5), "7h 30m")
        XCTAssertEqual(BodyMetric.sleep.format(7.999), "8h 00m")
        XCTAssertEqual(BodyMetric.hrv.format(54.4), "54 ms")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var days: [BodyDay] = []
        for i in (1...10).reversed() {
            var d = BodyDay(day: cal.date(byAdding: .day, value: -i, to: today)!)
            d.hrv = i.isMultiple(of: 2) ? 50 : 60
            days.append(d)
        }
        let base = BodyDash.baseline(.hrv, days: days, before: today)
        XCTAssertNotNil(base)
        XCTAssertEqual(base?.mean ?? 0, 55, accuracy: 0.01)
        XCTAssertTrue(base?.range.contains(55) ?? false)
        XCTAssertEqual(SleepScheduleCard.hoursFrom6pm(cal.date(bySettingHour: 23, minute: 0, second: 0, of: today)!), 5, accuracy: 0.01)
        XCTAssertEqual(SleepScheduleCard.hoursFrom6pm(cal.date(bySettingHour: 7, minute: 30, second: 0, of: today)!), 13.5, accuracy: 0.01)
        XCTAssertEqual(SleepScheduleCard.clock(5), "11p")
    }

    func testToolkitMath() {
        // Time estimator learns how far off guesses run.
        let est = [KitEstimate(what: "a", guess: 10, actual: 20), KitEstimate(what: "b", guess: 10, actual: 15), KitEstimate(what: "c", guess: 20, actual: 20)]
        XCTAssertEqual(KitEstimator.multiplier(est) ?? 0, 1.5, accuracy: 0.001)
        XCTAssertNil(KitEstimator.multiplier(Array(est.prefix(2))))
        // Chimes every 30 minutes from 9 to 11: 9:30, 10:00, 10:30, 11:00.
        XCTAssertEqual(KitChimes.slots(every: 30, from: 9, to: 11), [570, 600, 630, 660])
        XCTAssertEqual(KitChimes.slots(every: 30, from: 11, to: 9), [])
        // Tip & split.
        let r = KitSplit.perPerson(bill: 100, tipPercent: 20, people: 4)
        XCTAssertEqual(r.total, 120, accuracy: 0.001); XCTAssertEqual(r.each, 30, accuracy: 0.001)
        // Unit price: 1000 g for 3 beats 500 g for 2 by 25%.
        let d = KitDeal.compare(priceA: 2, qtyA: 500, priceB: 3, qtyB: 1000)
        XCTAssertNotNil(d); XCTAssertEqual(d?.saving ?? 0, 25, accuracy: 0.01); XCTAssertNil(KitDeal.compare(priceA: 1, qtyA: 0, priceB: 1, qtyB: 1))
        // Chores rotate one place each week.
        let people = ["Ana", "Ben", "Cy"]
        XCTAssertEqual(KitChoreRotation.person(for: 0, week: 0, people: people), "Ana")
        XCTAssertEqual(KitChoreRotation.person(for: 0, week: 1, people: people), "Ben")
        XCTAssertEqual(KitChoreRotation.person(for: 2, week: 1, people: people), "Ana")
        XCTAssertNil(KitChoreRotation.person(for: 0, week: 0, people: []))
        // Streaks count back from today (or yesterday if today isn't done yet).
        let cal = Calendar.current
        let today = Date()
        let y = cal.date(byAdding: .day, value: -1, to: today)!, y2 = cal.date(byAdding: .day, value: -2, to: today)!
        XCTAssertEqual(Kit.streak([Kit.dayKey(today), Kit.dayKey(y), Kit.dayKey(y2)]), 3)
        XCTAssertEqual(Kit.streak([Kit.dayKey(y), Kit.dayKey(y2)]), 2)
        XCTAssertEqual(Kit.streak([Kit.dayKey(y2)]), 0)
        // Top 3: a day counts only when every written item is done.
        let full = KitTop3Day(day: "2026-01-01", items: ["a", "b", ""], done: [true, true, false])
        let part = KitTop3Day(day: "2026-01-02", items: ["a", "b", "c"], done: [true, false, true])
        XCTAssertEqual(KitTop3.fullDays([full, part]), ["2026-01-01"])
        XCTAssertEqual(KitWords.count("one two\nthree  four"), 4)
        XCTAssertEqual(Kit.clock(65), "1:05"); XCTAssertEqual(Kit.clock(3725), "1:02:05")
        let born = cal.date(byAdding: .day, value: -70, to: today)!
        XCTAssertEqual(KitLifeWeeks.lived(born: born, now: today), 10)
    }

    func testToolkitIsInCompass() {
        XCTAssertEqual(KitCatalog.count, 58)          // 50 everyday tools + 7 body tools + team boards
        let ids = HubCatalog.groups.flatMap(\.tools).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "every Compass tool needs its own id")
        for id in ["top3", "parking", "reframe", "lifeWeeks", "morningPages"] { XCTAssertNotNil(HubCatalog.tool(id), id) }
    }

    func testAppleIntegrationsHelpers() {
        let d = TextDraft(recipients: ["+1 555 0100", "ana@example.com"], body: "On my way!")
        let url = AppleMessages.url(for: d)?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("sms:/open?addresses=+15550100,ana@example.com"), url)
        XCTAssertTrue(url.contains("body=On%20my%20way!"), url)
        XCTAssertTrue((AppleMessages.url(for: TextDraft(body: "hi"))?.absoluteString ?? "").hasPrefix("sms:&body=hi"))

        let start = Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: Date())!
        let late = AppleMessages.runningLate("Design review", start: start, minutes: 10)
        XCTAssertTrue(late.contains("10 min late for Design review"), late)
        XCTAssertTrue(late.contains(start.addingTimeInterval(600).formatted(date: .omitted, time: .shortened)), late)

        let mail = MailHandoff.url(for: MailHandoffDraft(to: ["a@x.com", "b@y.com"], subject: "Hi there", body: "Line"))?.absoluteString ?? ""
        XCTAssertTrue(mail.hasPrefix("mailto:a@x.com,b@y.com?"), mail)
        XCTAssertTrue(mail.contains("subject=Hi%20there"), mail)
    }

    func testTaskDurationDefaultsAndPadding() {
        let d = UserDefaults.standard
        let saved = [ADHDCoach.defaultMinutesKey, ADHDCoach.samplesKey, "adhd.multiplier", ADHDCoach.padKey].map { ($0, d.object(forKey: $0)) }
        defer { for (k, v) in saved { d.set(v, forKey: k) } }
        d.removeObject(forKey: ADHDCoach.defaultMinutesKey); d.removeObject(forKey: ADHDCoach.samplesKey); d.removeObject(forKey: ADHDCoach.padKey)
        d.set(1.5, forKey: "adhd.multiplier")
        let t = TaskItem(title: "Reply to Ana")
        XCTAssertEqual(ADHDCoach.minutes(t), 5, "no length set: the 5-minute default")
        XCTAssertEqual(ADHDCoach.calibratedMinutes(t), 5, "no padding before Keel has timed anything")
        t.estimatedMinutes = 20
        XCTAssertEqual(ADHDCoach.calibratedMinutes(t), 20)
        d.set(3, forKey: ADHDCoach.samplesKey)
        XCTAssertEqual(ADHDCoach.calibratedMinutes(t), 30, "after 3 timed tasks, padded by what was learned")
        d.set(false, forKey: ADHDCoach.padKey)
        XCTAssertEqual(ADHDCoach.calibratedMinutes(t), 20, "padding off")
        d.set(10, forKey: ADHDCoach.defaultMinutesKey)
        XCTAssertEqual(ADHDCoach.minutes(TaskItem(title: "x")), 10)
        XCTAssertEqual(TaskDuration.step(up: 5), 6); XCTAssertEqual(TaskDuration.step(up: 30), 35); XCTAssertEqual(TaskDuration.step(down: 90), 75)
        XCTAssertEqual(TaskDuration.label(90), "1 h 30 min")
    }

    func testStrengthMath() {
        XCTAssertGreaterThan(ExerciseLibrary.all.count, 100)
        XCTAssertEqual(Set(ExerciseLibrary.all.map(\.id)).count, ExerciseLibrary.all.count, "exercise ids are unique")
        XCTAssertTrue(ExerciseLibrary.all.allSatisfy { !$0.primary.isEmpty }, "every exercise works a muscle")
        XCTAssertEqual(StrengthStore.e1RM(LiftSet(reps: 10, weight: 60)), 80, accuracy: 0.01)

        let now = Date()
        var s1 = StrengthSession(name: "A", start: now.addingTimeInterval(-3 * 86_400))
        s1.exercises = [LoggedExercise(exerciseId: "bench-press", sets: [LiftSet(reps: 8, weight: 60, done: true), LiftSet(reps: 8, weight: 60, done: true)])]
        s1.end = s1.start.addingTimeInterval(3600)
        // Hit every set: add weight next time.
        let sug = StrengthStore.suggestion("bench-press", targetReps: 8, in: [s1])
        XCTAssertEqual(sug?.weight ?? 0, 60 + StrengthStore.increment, accuracy: 0.01)
        // Missed reps: repeat the weight.
        var s0 = s1; s0.exercises[0].sets[1].reps = 6
        XCTAssertEqual(StrengthStore.suggestion("bench-press", targetReps: 8, in: [s0])?.weight ?? 0, 60, accuracy: 0.01)

        var s2 = StrengthSession(name: "B", start: now.addingTimeInterval(-3600))
        s2.exercises = [LoggedExercise(exerciseId: "bench-press", sets: [LiftSet(reps: 8, weight: 65, done: true)])]
        s2.end = now
        XCTAssertEqual(StrengthStore.records(in: s2, history: [s1, s2]).map(\.id), ["bench-press"], "a heavier set is a new record")
        let sets = StrengthStore.setsPerMuscle(now: now, in: [s1, s2])
        XCTAssertEqual(sets[.chest] ?? 0, 3, accuracy: 0.01)
        XCTAssertEqual(sets[.triceps] ?? 0, 1.5, accuracy: 0.01)
        let tired = StrengthStore.fatigue(now: now, in: [s1, s2])
        XCTAssertGreaterThan(tired[.chest] ?? 0, tired[.quads] ?? 0)
        XCTAssertGreaterThan(StrengthStore.strain(s1), 0)
    }

    func testBiomarkerExtraction() {
        let report = """
        LIPID PANEL
        Total Cholesterol      212   mg/dL   <200   H
        HDL Cholesterol 48 mg/dL
        LDL Cholesterol (calc)
        138 mg/dL
        Hemoglobin A1c 5.8 %
        Fasting status: 12 hours
        Vitamin D, 25-Hydroxy  22.5 ng/mL  30-100
        """
        let found = Dictionary(uniqueKeysWithValues: Biomarkers.extract(from: report).map { ($0.id, $0.value) })
        XCTAssertEqual(found["chol"], 212)
        XCTAssertEqual(found["hdl"], 48)
        XCTAssertEqual(found["ldl"], 138)
        XCTAssertEqual(found["a1c"], 5.8)
        XCTAssertEqual(found["vitd"], 22.5)
        XCTAssertNil(found["ast"], "\"fasting\" must not read as AST")
        let d = Biomarkers.def("vitd")!
        XCTAssertEqual(Biomarkers.status(d, 22.5).0, "Low")
    }

    func testBioAgeAndEnergyAndNutrition() {
        let fit = BioAge.estimate(BioAgeInputs(age: 40, vo2: 50, rhr: 52, hrv: 60, sleepHours: 7.6, steps: 11000, bmi: 23, systolic: 115))
        let unfit = BioAge.estimate(BioAgeInputs(age: 40, vo2: 28, rhr: 78, hrv: 25, sleepHours: 5.5, steps: 3000, bmi: 32, systolic: 145))
        XCTAssertLessThan(fit.bioAge, 40); XCTAssertGreaterThan(unfit.bioAge, 40)
        XCTAssertGreaterThanOrEqual(fit.confidence, 90)
        XCTAssertEqual(BioAge.estimate(BioAgeInputs(age: 30)).bioAge, 30, accuracy: 0.01, "no data: same as real age")

        let cal = Calendar.current
        var day = BodyDay(day: cal.startOfDay(for: Date()))
        day.tide = 80; day.anchor = 80
        day.wake = cal.date(bySettingHour: 7, minute: 0, second: 0, of: Date())
        let bed = cal.date(bySettingHour: 22, minute: 30, second: 0, of: Date())!
        let line = EnergyBank.timeline(day, bedtime: bed, now: cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!)
        XCTAssertEqual(line.first?.level ?? 0, EnergyBank.charge(day), accuracy: 0.01)
        XCTAssertLessThan(line.last?.level ?? 100, line.first?.level ?? 0, "energy drains through the day")
        XCTAssertTrue(line.contains { $0.forecast } && line.contains { !$0.forecast })

        let good = FoodEntry(name: "Salmon salad", facts: NutritionFacts(calories: 600, protein: 95, fiber: 30, addedSugar: 5, sodiumMg: 900), meal: "lunch", verdict: .green)
        let bad = FoodEntry(name: "Soda and fries", facts: NutritionFacts(calories: 900, protein: 8, fiber: 3, addedSugar: 70, sodiumMg: 3000), meal: "lunch", verdict: .red)
        XCTAssertGreaterThan(NutritionScore.score([good])!.score, NutritionScore.score([bad])!.score)
        XCTAssertNil(NutritionScore.score([]))
    }

    func testBodyProMath() {
        // Plates: 100 kg = 20 kg bar + 40 a side = 25 + 15.
        XCTAssertEqual(PlateMath.perSide(total: 100, unit: "kg"), [25, 15])
        XCTAssertEqual(PlateMath.perSide(total: 20, unit: "kg"), [])
        XCTAssertNil(PlateMath.perSide(total: 15, unit: "kg"))
        XCTAssertEqual(PlateMath.perSide(total: 225, unit: "lb"), [45, 45])
        let w = PlateMath.warmups(to: 100, unit: "kg", step: 2.5)
        XCTAssertEqual(w.map(\.weight), [40, 60, 80]); XCTAssertTrue(w.allSatisfy(\.warmup))

        // Workout builder: low tide gives mobility; otherwise fresh muscles only.
        XCTAssertEqual(WorkoutBuilder.build(tide: 20, goal: .general, kit: .gym, fatigue: [:], weekSets: [:]).name, "Recovery mobility")
        let plan = WorkoutBuilder.build(tide: 80, goal: .muscle, kit: .bodyweight, fatigue: [.quads: 0.9, .glutes: 0.8], weekSets: [:])
        XCTAssertFalse(plan.session.exercises.isEmpty)
        for e in plan.session.exercises {
            let ex = ExerciseLibrary.exercise(e.exerciseId)!
            XCTAssertTrue(TrainingKit.bodyweight.allows.contains(ex.equipment), ex.name)
            XCTAssertFalse(ex.primary.contains(.quads) || ex.primary.contains(.glutes), "\(ex.name) works a tired muscle")
            XCTAssertEqual(e.sets.count, 4)
        }

        // Illness signals need two or more changes from normal.
        let cal = Calendar.current
        var days: [BodyDay] = (1...20).reversed().map { i in
            var d = BodyDay(day: cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: Date()))!)
            d.rhr = 55; d.hrv = 60; d.resp = 14
            return d
        }
        var today = BodyDay(day: cal.startOfDay(for: Date())); today.rhr = 62; today.hrv = 44; today.resp = 14
        days.append(today)
        XCTAssertEqual(BodyAlerts.illnessSignals(days).count, 2)
        days[days.count - 1].hrv = 58
        XCTAssertTrue(BodyAlerts.illnessSignals(days).isEmpty, "one signal alone isn't enough")

        // Goal projection: resting heart rate falling 0.2 a day reaches 55 in about 25 days.
        let trend: [BodyDay] = (0..<20).map { i in
            var d = BodyDay(day: cal.date(byAdding: .day, value: -19 + i, to: cal.startOfDay(for: Date()))!)
            d.rhr = 64 - 0.2 * Double(i)
            return d
        }
        let p = BodyGoals.projection(BodyGoal(metric: "rhr", target: 55), days: trend)
        XCTAssertEqual(p.perWeek ?? 0, -1.4, accuracy: 0.05)
        XCTAssertNotNil(p.eta)
        XCTAssertNil(BodyGoals.projection(BodyGoal(metric: "rhr", target: 70), days: trend).eta, "heading the wrong way")

        XCTAssertGreaterThanOrEqual(ExerciseLibrary.all.count, 700)
        XCTAssertEqual(Set(ExerciseLibrary.all.map(\.id)).count, ExerciseLibrary.all.count)
        for kind in ["Strength", "Cardio", "Mobility", "Yoga"] { XCTAssertGreaterThan(ExerciseLibrary.all.filter { $0.category == kind }.count, 20, kind) }
        // Stretching doesn't count as lifting volume.
        var stretch = StrengthSession(name: "S"); stretch.end = Date()
        stretch.exercises = [LoggedExercise(exerciseId: "pigeon-stretch", sets: [LiftSet(reps: 60, weight: 0, done: true)])]
        XCTAssertTrue(StrengthStore.setsPerMuscle(in: [stretch]).isEmpty)
        XCTAssertEqual(StrengthStore.strain(stretch), 0)
        XCTAssertEqual(ExerciseLibrary.exercise("pigeon-stretch")?.amount(60), "60 s")
    }

    func testTeamBoards() throws {
        let id = "0f2596bc4e06751c98f7b05bfba10c68"
        XCTAssertEqual(TeamAPI.boardId(from: "https://keel-backend.example.dev/t/\(id)"), id)
        XCTAssertEqual(TeamAPI.boardId(from: "  \(id.uppercased())\n"), id)
        XCTAssertNil(TeamAPI.boardId(from: "https://example.com/t/123"))
        let json = """
        {"name":"Launch","owner":"Brian","members":["Brian","Sam Lee"],"version":3,"updated":1,
         "tasks":[{"id":"a1","title":"Write email","notes":"","status":"doing","assignee":"Sam Lee","due":"2026-11-20","createdBy":"Brian","created":1,"updated":2,
                   "comments":[{"id":"c1","by":"Brian","text":"@Sam pricing?","at":3,"mentions":["Sam Lee"]}]}],
         "activity":[{"at":4,"by":"Brian","text":"added it","task":"a1","for":["Sam Lee"]},{"at":5,"by":"Sam Lee","text":"joined the board"}]}
        """
        let b = try JSONDecoder().decode(TeamBoardData.self, from: Data(json.utf8))
        XCTAssertEqual(b.activity.first?.forWhom, ["Sam Lee"])
        XCTAssertNil(b.activity.last?.forWhom)
        XCTAssertEqual(b.tasks.first?.dueDate.map { Calendar.current.component(.day, from: $0) }, 20)
        XCTAssertEqual(TeamAPI.dueString(b.tasks.first?.dueDate), "2026-11-20")

        // Invitations carry their server; boards remember theirs.
        let inv = TeamAPI.invite(from: "https://keel-backend.example.dev/join/9327c9076f94ec811fd201b8")
        XCTAssertEqual(inv?.code, "9327c9076f94ec811fd201b8")
        XCTAssertEqual(inv?.host, "https://keel-backend.example.dev")
        XCTAssertNil(TeamAPI.invite(from: "https://keel-backend.example.dev/join/nope"))
        XCTAssertEqual(TeamBoardRef(id: id, name: "B", url: "https://teams.example.com/t/\(id)").host, "https://teams.example.com")
        // A private board tells you your role; viewers can't edit, admins can manage.
        let secureJSON = """
        {"name":"Launch","owner":"Brian","members":["Brian","Vic"],"version":1,"updated":1,"tasks":[],"activity":[],"secure":true,
         "roles":{"Brian":"owner","Vic":"viewer"},"me":{"name":"Vic","role":"viewer"},"chat":[{"id":"m1","by":"Brian","text":"hi","at":1}],
         "events":[{"id":"e1","title":"Review","start":"2026-11-20T15:00:00Z","end":"2026-11-20T16:00:00Z","notes":"","by":"Brian"}]}
        """
        var sb = try JSONDecoder().decode(TeamBoardData.self, from: Data(secureJSON.utf8))
        XCTAssertFalse(sb.canEdit); XCTAssertFalse(sb.canManage)
        XCTAssertEqual(sb.events?.first?.startDate, ISO8601DateFormatter().date(from: "2026-11-20T15:00:00Z"))
        sb.me = TeamMe(name: "Vic", role: "admin")
        XCTAssertTrue(sb.canEdit); XCTAssertTrue(sb.canManage)
        XCTAssertTrue(b.canEdit, "link boards: everyone edits")
    }

    // MARK: Food logging: catalog, predictions, phrases, products

    func testFoodCatalogSearchAndPhrases() {
        XCTAssertGreaterThan(FoodCatalog.all.count, 180, "every catalog line parses")
        XCTAssertEqual(Set(FoodCatalog.all.map(\.id)).count, FoodCatalog.all.count, "no duplicate foods")
        XCTAssertTrue(FoodCatalog.all.allSatisfy { ($0.facts.calories ?? -1) >= 0 && !$0.emoji.isEmpty })

        XCTAssertEqual(FoodCatalog.search("egg", in: FoodCatalog.all).first?.name, "Egg, large")
        XCTAssertEqual(FoodCatalog.search("lat", in: FoodCatalog.all).first?.name, "Latte")
        XCTAssertEqual(FoodCatalog.search("chipotle", in: FoodCatalog.all).first?.name, "Burrito bowl")
        XCTAssertTrue(FoodCatalog.search("zzzz", in: FoodCatalog.all).isEmpty)
        // Foods you eat often come first.
        var mine = FoodCatalog.all.first { $0.name == "Avocado toast" }!
        mine.source = .mine; mine.timesEaten = 6
        XCTAssertEqual(FoodCatalog.search("to", in: [mine] + FoodCatalog.all).first?.name, "Avocado toast")

        let parts = MealPhrase.parts("2 eggs, toast and a latte")
        XCTAssertEqual(parts.map(\.servings), [2, 1, 1])
        XCTAssertEqual(parts.map(\.text), ["eggs", "toast", "latte"])
        let plate = MealPhrase.resolve("2 eggs, toast and a latte", pool: FoodCatalog.all)
        XCTAssertEqual(plate.map(\.food.name), ["Egg, large", "Toast, whole wheat", "Latte"])
        XCTAssertEqual(plate.first?.facts.calories ?? 0, 144, accuracy: 0.1)
        XCTAssertEqual(MealPhrase.parts("half a bagel").first?.servings, 0.5)
        XCTAssertTrue(MealPhrase.resolve("banana", pool: FoodCatalog.all).isEmpty, "one plain food is just a search")

        XCTAssertEqual(FoodCatalog.match(label: "hamburger")?.name, "Hamburger")
        XCTAssertEqual(FoodCatalog.match(label: "sushi")?.name, "Sushi roll")
        XCTAssertEqual(FoodCatalog.emoji(for: "Banana"), "🍌")

        let product: [String: Any] = ["code": "123", "product_name": "Skyr", "brands": "Siggi's, Other", "image_front_small_url": "https://img/x.jpg",
                                      "nutriments": ["energy-kcal_100g": 59, "proteins_100g": "10.5", "sodium_100g": 0.04]]
        let f = FoodWebSearch.food(from: product)
        XCTAssertEqual(f?.facts.calories, 59)
        XCTAssertEqual(f?.facts.protein, 10.5)
        XCTAssertEqual(f?.facts.sodiumMg ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(f?.serving, "100 g")
        XCTAssertEqual(f?.brand, "Siggi's")
        XCTAssertNil(FoodWebSearch.food(from: ["product_name": "No numbers"]))
    }

    // MARK: Sales & promos, spoken lists, intros, tone

    func testSalesPromoSpokenListsIntroAndTone() {
        let promo = email(from: "deals@shop.com", name: "Shop", subject: "40% off ends tonight", body: "Shop now, free shipping on everything.")
        XCTAssertTrue(MailNoise.isSalesOrPromo(promo))
        let pitch = email(from: "alex@growthco.io", name: "Alex Smith", subject: "Quick question",
                          body: "Hi! We help companies get more leads. Would you be open to a quick call? 15 minutes is all I need. Here's my calendly.com link.")
        XCTAssertTrue(MailNoise.isSalesOrPromo(pitch), "a cold pitch dressed as a personal note")
        XCTAssertFalse(MailNoise.isSalesOrPromo(pitch, knownSender: true), "people you've replied to are never pitches")
        let friend = email(from: "sam@gmail.com", name: "Sam", subject: "Dinner", body: "Can you do a quick call later? Want to plan Saturday.")
        XCTAssertFalse(MailNoise.isSalesOrPromo(friend))
        XCTAssertFalse(AutoDrafts.isRealPerson(pitch), "no drafted replies to sales mail")
        XCTAssertEqual(InboxBrain.tab(promo, score: nil), .promos)

        XCTAssertEqual(SpokenList.detect("Grocery list: milk, eggs and bread"), SpokenList.List(title: "Grocery list", items: ["Milk", "Eggs", "Bread"], checklist: true))
        XCTAssertEqual(SpokenList.detect("I need to call mom, pay rent and book the dentist")?.items, ["Call mom", "Pay rent", "Book the dentist"])
        XCTAssertEqual(SpokenList.detect("First wash the car then buy groceries and finally call Sam")?.items, ["Wash the car", "Buy groceries", "Call Sam"])
        XCTAssertEqual(SpokenList.detect("Ideas for the party: balloons, a cake, music")?.title, "Ideas for the party")
        XCTAssertNil(SpokenList.detect("I went to the store today and it was really busy. Then I came home and made dinner for everyone."))
        XCTAssertNil(SpokenList.detect("Meeting went well, we agreed on the budget"))

        let intro = email(from: "jo@example.com", name: "Jo Park", subject: "Intro: Brian <> Dana", body: "Brian, meet Dana!")
        intro.toLine = "me@keel.app"; intro.ccLine = "dana@example.com"
        var d = ComposeDraft(original: intro)
        XCTAssertTrue(InstantIntro.canApply(d))
        InstantIntro.apply(&d, myAddresses: ["me@keel.app"])
        XCTAssertEqual(d.to, "dana@example.com")
        XCTAssertEqual(d.bcc, "jo@example.com")
        XCTAssertTrue(d.body.hasPrefix("Thanks Jo (moving you to bcc)!"))

        XCTAssertFalse(ToneCheck.flags("PER MY LAST EMAIL, I NEED THIS ASAP!!!!").isEmpty)
        XCTAssertTrue(ToneCheck.flags("Hi Sam, could you send the file when you get a chance? Thanks!").isEmpty)
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 17; c.hour = 23
        let late = Calendar.current.date(from: c)!
        XCTAssertEqual(KindTime.suggestion(now: late).map { Calendar.current.component(.hour, from: $0) }, 8)
        c.hour = 14
        XCTAssertNil(KindTime.suggestion(now: Calendar.current.date(from: c)!))
    }

    func testRoutineFinderAndCalendarFallback() throws {
        let ctx = try makeContext()
        let titles = ["Brush teeth", "Take meds", "Do the dishes", "Take out trash", "Water the plants", "Vacuum", "Email Dana about Q3"]
        let tasks = titles.map { TaskItem(title: $0) }
        tasks.forEach(ctx.insert)
        let s = RoutineFinder.suggest(from: tasks)
        XCTAssertEqual(Set(s.map(\.name)), ["Morning routine", "Evening reset", "Weekly reset"])
        XCTAssertFalse(s.flatMap(\.steps).contains { $0.title == "Email Dana about Q3" }, "real work stays a task")
        XCTAssertEqual(CalendarAI.fallback("delete lunch with Sam tomorrow")?.action, .delete)
        XCTAssertEqual(CalendarAI.fallback("delete lunch with Sam tomorrow")?.match, "lunch with sam")
        if let move = CalendarAI.fallback("move dentist to friday 3pm") {      // depends on the date reader understanding the time
            XCTAssertEqual(move.action, .move)
            XCTAssertEqual(move.match, "dentist")
        }
    }

    func testTaskTrashAndRollover() throws {
        let ctx = try makeContext()
        TaskTrash.empty()
        let t = TaskItem(title: "Call the dentist", dueDate: Date())
        t.notes = "Ask about Friday"; t.tags = ["health"]
        ctx.insert(t)
        TaskActions.delete(t, ctx: ctx)
        XCTAssertEqual(TaskTrash.all.first?.title, "Call the dentist")
        let back = TaskTrash.restore(TaskTrash.all[0], ctx: ctx)
        XCTAssertEqual(back.notes, "Ask about Friday")
        XCTAssertEqual(back.tags, ["health"])
        XCTAssertTrue(TaskTrash.all.isEmpty)

        UserDefaults.standard.set(true, forKey: MorningRollover.onKey)
        UserDefaults.standard.removeObject(forKey: "tasks.rollover.day")
        let old = TaskItem(title: "Overdue", dueDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()))
        ctx.insert(old)
        MorningRollover.runIfDue(ctx: ctx)
        XCTAssertTrue(Calendar.current.isDateInToday(old.dueDate ?? .distantPast))
        UserDefaults.standard.set(false, forKey: MorningRollover.onKey)
    }

    func testQuietHours() {
        let d = UserDefaults.standard
        d.set(true, forKey: QuietHours.onKey); d.set(22 * 60, forKey: QuietHours.startKey); d.set(7 * 60, forKey: QuietHours.endKey)
        d.set(false, forKey: QuietHours.holdKey)
        let cal = Calendar.current
        let late = cal.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
        let early = cal.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        XCTAssertTrue(QuietHours.isQuiet(late)); XCTAssertTrue(QuietHours.isQuiet(early)); XCTAssertFalse(QuietHours.isQuiet(noon))
        XCTAssertEqual(cal.component(.hour, from: QuietHours.endOfQuiet(after: late)), 7)

        let c = UNMutableNotificationContent(); c.title = "Hi"; c.sound = .default
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: cal.date(byAdding: .day, value: 1, to: late)!)
        let r = UNNotificationRequest(identifier: "journal.nightly", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        XCTAssertEqual(QuietHours.adjust(r).content.interruptionLevel, .passive)
        XCTAssertNil(QuietHours.adjust(r).content.sound)
        let med = UNNotificationRequest(identifier: "med.morning", content: c, trigger: r.trigger)
        XCTAssertTrue(QuietHours.adjust(med) === med, "medication reminders always come through unchanged")
        d.set(true, forKey: QuietHours.holdKey)
        let held = QuietHours.adjust(r).trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(held?.dateComponents.hour, 7)
        d.set(false, forKey: QuietHours.onKey); d.set(false, forKey: QuietHours.holdKey)
    }

    func testFocusBestTime() {
        let cal = Calendar.current
        func r(_ h: Int, _ rating: Int) -> FocusReflection {
            FocusReflection(at: cal.date(bySettingHour: h, minute: 0, second: 0, of: Date())!, minutes: 25, rating: rating, note: "")
        }
        let list = [r(9, 3), r(10, 3), r(9, 3), r(15, 1), r(14, 2), r(16, 1)]
        XCTAssertEqual(FocusReflections.bestTime(list), "mornings")
        XCTAssertNil(FocusReflections.bestTime(Array(list.prefix(3))), "needs a few sessions first")
    }

    func testSendChecks() {
        XCTAssertEqual(SendChecks.warnings(body: "Hi, I've attached the deck.", subject: "Deck", attachments: 0, recipients: 1, isForward: false).count, 1)
        XCTAssertTrue(SendChecks.warnings(body: "Hi, I've attached the deck.", subject: "Deck", attachments: 1, recipients: 1, isForward: false).isEmpty)
        XCTAssertTrue(SendChecks.warnings(body: "Thanks!\n> see attached", subject: "Re: x", attachments: 0, recipients: 1, isForward: false).isEmpty, "quoted text doesn't count")
        XCTAssertEqual(SendChecks.warnings(body: "Hi", subject: " ", attachments: 0, recipients: 12, isForward: false).count, 2)
    }

    // A Keel-only list (not in Reminders) survives a sync: its reminder sits in the default list, and that name
    // must not be copied back (it emptied routines linked to the list). Real moves in Reminders still count.
    func testReminderListAfterPull() {
        let lists = ["Reminders", "Groceries", "Morning"]
        XCTAssertEqual(CalendarService.listAfterPull(keel: "Bedtime", reminders: "Reminders", lists: lists, defaultList: "Reminders"), "Bedtime")
        XCTAssertEqual(CalendarService.listAfterPull(keel: "Bedtime", reminders: "Groceries", lists: lists, defaultList: "Reminders"), "Groceries")
        XCTAssertEqual(CalendarService.listAfterPull(keel: "Morning", reminders: "Reminders", lists: lists, defaultList: "Reminders"), "Reminders")
        XCTAssertEqual(CalendarService.listAfterPull(keel: "Morning", reminders: nil, lists: lists, defaultList: "Reminders"), "Morning")
    }

    // MARK: Keel Voice

    func testVoiceCommands() {
        let snip: [(name: String, body: String)] = [(name: "address", body: "12 Harbour Rd, Leeds")]
        XCTAssertEqual(VoiceCleanup.tidy(VoiceCleanup.applyCommands("first thing new line second thing")), "First thing\nSecond thing")
        XCTAssertEqual(VoiceCleanup.tidy(VoiceCleanup.applyCommands("intro new paragraph body")), "Intro\n\nBody")
        XCTAssertEqual(VoiceCleanup.tidy(VoiceCleanup.applyCommands("groceries bullet point milk bullet point eggs")), "Groceries\n- Milk\n- Eggs")
        XCTAssertEqual(VoiceCleanup.tidy(VoiceCleanup.applyCommands("Call Sam. Buy a boat. scratch that")), "Call Sam.")
        XCTAssertEqual(VoiceCleanup.tidy(VoiceCleanup.applyCommands("send it to insert my address please", snippets: snip)), "Send it to 12 Harbour Rd, Leeds please")
    }

    func testVoiceTidy() {
        XCTAssertEqual(VoiceCleanup.tidy("um so I I think uh we should go"), "So I think we should go")
        XCTAssertEqual(VoiceCleanup.tidy("she had had enough , really ."), "She had had enough, really.")      // "had had" is right
        XCTAssertEqual(VoiceCleanup.tidy("the umbrella is here"), "The umbrella is here")                 // "um" inside a word stays
        XCTAssertEqual(VoiceCleanup.finish("Call the dentist.", .task), "Call the dentist")
        XCTAssertEqual(VoiceCleanup.finish("pricing, Q4 deck!", .search), "pricing Q4 deck")
    }

    func testVoiceCorrectsNames() {
        let vocab = ["Priya Shah", "Ecclesiastes", "Jordan"]
        XCTAssertEqual(VoiceCleanup.correctNames("So I need to call Priya Shal on Thursday.", vocabulary: vocab), "So I need to call Priya Shah on Thursday.")
        XCTAssertEqual(VoiceCleanup.correctNames("Reading Eclesiastes tonight", vocabulary: vocab), "Reading Ecclesiastes tonight")
        XCTAssertEqual(VoiceCleanup.correctNames("Priya shall decide", vocabulary: vocab), "Priya shall decide", "two letters off: left alone")
        XCTAssertEqual(VoiceCleanup.correctNames("the jordan river", vocabulary: vocab), "the jordan river", "short words aren't guessed")
    }

    func testVoiceEmailSentences() {
        // Seen from Apple's on-device model in testing: an email as short unpunctuated lines.
        let ai = "hey Sam\nthanks for the deck\nI think the numbers look good\nbut can we move the meeting to Wednesday at two"
        XCTAssertEqual(VoiceCleanup.finish(ai, .email), "Hey Sam,\nThanks for the deck. I think the numbers look good. But can we move the meeting to Wednesday at two.")
        XCTAssertEqual(VoiceCleanup.finish("Thanks for the deck. See you Wednesday.", .email), "Thanks for the deck. See you Wednesday.")
    }

    func testVoiceCleanupGuards() {
        let said = "remind me to send the budget to Priya on Thursday and book the room"
        XCTAssertTrue(VoiceCleanup.looksFaithful("Remind me to send the budget to Priya on Thursday and book the room.", to: said))
        XCTAssertFalse(VoiceCleanup.looksFaithful("Sure! I've added that reminder for you. Anything else I can help with today?", to: said), "an answer, not a cleanup")
        XCTAssertFalse(VoiceCleanup.looksFaithful("Budget.", to: said), "too much dropped")
        XCTAssertFalse(VoiceCleanup.looksFaithful("Priya Shah, thanks for the deck. Can we move it to Wednesday?",
                                                  to: "hey Sam thanks for the deck can we move it to Wednesday"), "a name I didn't say")
        XCTAssertEqual(VoiceCleanup.stripChatter("Here's the cleaned text:\nCall Sam at 3."), "Call Sam at 3.")
        XCTAssertEqual(VoiceCleanup.stripChatter("\"Call Sam at 3.\""), "Call Sam at 3.")
    }

    func testVoicePlacementAboveSignature() {
        let body = "\n\nThanks,\nBrian\n\nOn Mon, Sam wrote:\n> hi"
        let place = KeelMicButton.placer(body, separator: "\n\n", above: ["Thanks,\nBrian", "\nOn "])
        XCTAssertEqual(place("Sounds good, see you Thursday."), "Sounds good, see you Thursday.\n\nThanks,\nBrian\n\nOn Mon, Sam wrote:\n> hi")
        XCTAssertEqual(KeelMicButton.placer("Buy milk", separator: " ", above: [])("and eggs"), "Buy milk and eggs")
    }

    func testVocabularyMiner() {
        let texts = ["Call Priya Shah about the Q4 budget", "Priya Shah sent the Q4 deck", "Sermon prep: Ecclesiastes study", "Ecclesiastes outline for Sunday"]
        let c = VocabularyMiner.candidates(in: texts)
        let terms = VocabularyMiner.terms(from: c)
        XCTAssertTrue(terms.contains { $0.localizedCaseInsensitiveContains("Priya") }, "a person named twice: \(terms)")
        XCTAssertFalse(terms.contains("budget"), "an ordinary word isn't vocabulary")
        XCTAssertTrue(terms.contains("Q4"), "acronyms and codes count: \(terms)")
    }

    /// End to end: real speech (made with macOS `say`) through the engine. Skipped where speech isn't available.
    func testKeelVoiceTranscribesSpeech() async throws {
        guard let url = Bundle(for: KeelTests.self).url(forResource: "dictation-sample", withExtension: "aiff") else { throw XCTSkip("no fixture") }
        let text: String
        do { text = try await KeelVoice.transcribe(file: url, vocabulary: ["Priya Shah"]) }
        catch { throw XCTSkip("speech recognition unavailable here: \(error.localizedDescription)") }
        XCTAssertFalse(text.isEmpty, "heard nothing")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("budget"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Thursday"), text)
    }
}

