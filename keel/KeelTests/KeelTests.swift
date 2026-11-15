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
        XCTAssertEqual(KitCatalog.count, 50)
        let ids = HubCatalog.groups.flatMap(\.tools).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "every Compass tool needs its own id")
        for id in ["top3", "parking", "reframe", "lifeWeeks", "morningPages"] { XCTAssertNotNil(HubCatalog.tool(id), id) }
    }
}
