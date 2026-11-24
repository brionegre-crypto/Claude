/* Be The Man dashboard. Talks to /api/admin/* (signed-in admins only). */
(function () {
  "use strict";
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var esc = function (v) { return String(v == null ? "" : v).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); };
  var day = function (t) { return t ? new Date(t).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" }) : ""; };
  var when = function (t) { return t ? new Date(t).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }) : ""; };
  var pct = function (a, b) { return b ? Math.round((100 * (a || 0)) / b) + "%" : "–"; };
  var view = $("#view");
  var S = { contacts: [], segments: [], autos: [], forms: [], seqs: [] };
  var HOOKS = {};
  function after(name, fn) { (HOOKS[name] = HOOKS[name] || []).push(fn); }
  function fire(name) { var args = Array.prototype.slice.call(arguments, 1); (HOOKS[name] || []).forEach(function (f) { try { f.apply(null, args); } catch (e) { console.error(e); } }); }

  function flash(msg) { var f = $("#flash"); f.textContent = msg; f.hidden = false; clearTimeout(flash.t); flash.t = setTimeout(function () { f.hidden = true; }, 6000); window.scrollTo({ top: 0, behavior: "smooth" }); }
  function api(path, body) {
    return fetch("/api/admin/" + path, body !== undefined ? { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) } : { credentials: "same-origin" })
      .then(function (r) { if (r.status === 401) { location.href = "/admin-login/"; throw new Error("signed out"); } return r.json(); })
      .then(function (d) { if (!d.ok && d.error) flash(d.error); return d; });
  }
  function dialog(html) { $("#dlgbody").innerHTML = html; $("#dlg").showModal(); return $("#dlgbody"); }
  $("#dlg").addEventListener("click", function (e) { if (e.target.id === "dlg" || e.target.hasAttribute("data-close")) $("#dlg").close(); });
  function tags() { var t = {}; S.contacts.forEach(function (c) { (c.t || "").split("|").filter(Boolean).forEach(function (x) { t[x] = 1; }); }); return Object.keys(t).sort(); }
  function loadContacts() { return api("contacts").then(function (d) { if (d.ok) S.contacts = d.contacts; return S.contacts; }); }
  function preview(subject, body) {
    api("preview", { body: body }).then(function (r) {
      var b = dialog("<h2 style='margin-bottom:10px'>" + esc(subject || "Preview") + "</h2><iframe></iframe><div class='adm-row' style='margin-top:12px'><button class='btn btn-ghost btn-sm' data-close>Close</button></div>");
      $("iframe", b).srcdoc = r.html;
    });
  }
  function testEmail(subject, body) { api("test", { subject: subject, body: body }).then(function (r) { if (r.ok) flash("Test sent to " + r.to + "."); }); }
  var FORMAT = "Write in plain text. A blank line starts a new paragraph. <code>[[Button text|https://link]]</code> on its own line is a button, <code>[text](https://link)</code> a link, <code>**bold**</code> bold, lines starting <code>- </code> a list. <code>{{first_name}}</code> is his first name; <code>{{any_field}}</code> is a custom field.";
  var TEXTNOTE = "Texts start with \"Be The Man:\" and end with \"Reply STOP to opt out.\" automatically. They only go to men who checked the text box, and only between 9 AM and 8 PM Central.";

  // ---------- router ----------
  var VIEWS = {};
  var PARENT = { man: "men" };
  function show(tab) {
    var parts = String(tab || "").split("/"), name = parts[0];
    if (!VIEWS[name]) { name = "overview"; parts = [name]; }
    var hl = PARENT[name] || name;
    $$(".adm-tabs button").forEach(function (b) { b.classList.toggle("on", b.dataset.tab === hl); });
    var h = "#" + parts.join("/");
    if (location.hash !== h) history.replaceState(null, "", h);
    view.innerHTML = "<p class='muted'>Loading…</p>";
    VIEWS[name].apply(null, parts.slice(1).map(function (x) { try { return decodeURIComponent(x); } catch (e) { return x; } }));
  }
  $$(".adm-tabs button").forEach(function (b) { b.onclick = function () { show(b.dataset.tab); }; });

  // ---------- overview ----------
  VIEWS.overview = function () {
    api("overview").then(function (d) {
      if (!d.ok) return;
      $("#unread").hidden = !d.unreadTexts;
      var stat = function (v, l) { return "<div class='adm-stat'><b>" + esc(v) + "</b><span>" + esc(l) + "</span></div>"; };
      var days = []; for (var i = 29; i >= 0; i--) { var dt = new Date(Date.now() - i * 864e5).toISOString().slice(0, 10); days.push(d.growth[dt] || 0); }
      var max = Math.max.apply(null, days.concat([1]));
      var setup = [["Email", d.setup.email], ["Texts (Twilio)", d.setup.texts], ["Bounce protection", d.setup.bounces], ["Hourly scheduler", d.setup.scheduler]]
        .map(function (s) { return "<span class='tag " + (s[1] ? "ok" : "warn") + "'>" + esc(s[0]) + ": " + (s[1] ? "on" : "not set up") + "</span>"; }).join("");
      var tg = Object.keys(d.tags).sort().map(function (t) { return "<span class='tag'>" + esc(t) + " · " + d.tags[t] + "</span>"; }).join("");
      view.innerHTML =
        "<div class='adm-stats'>" + stat(d.active, "Active on email") + stat(d.texting, "Opted in to texts") + stat(d.newThisWeek, "New this week") +
        stat(d.seats ? d.seats.sold + " of " + d.seats.limit : "n/a", "Cohort seats sold") + stat(d.sentToday + " / " + d.cap, "Emails today") +
        stat(d.textsToday + " / " + d.smsCap, "Texts today") + stat(d.unsubscribed, "Unsubscribed") + stat(d.bounced, "Bounced or complained") + "</div>" +
        "<div class='adm-card'><div class='adm-row'><h3>Sign-ups, last 30 days</h3><span class='muted small'>" + days.reduce(function (a, b) { return a + b; }, 0) + " total</span></div><div class='bars'>" +
        days.map(function (n) { return "<i style='height:" + Math.round((90 * n) / max) + "px' title='" + n + "'></i>"; }).join("") + "</div></div>" +
        "<div class='adm-card'><h3>Engagement (active contacts)</h3><div>" +
        ["engaged", "warm", "cold", "new"].map(function (k) { return "<span class='tag'>" + k + " · " + d.engagement[k] + "</span>"; }).join("") +
        "</div><p class='muted small'>Engaged: opened or clicked in the last 30 days. Warm: in the last 90. Cold: 3+ emails and nothing in 90 days. New: not enough emails yet.</p></div>" +
        (tg ? "<div class='adm-card'><h3>Tags</h3><div>" + tg + "</div></div>" : "") +
        "<div class='adm-card'><h3>Setup</h3><div>" + setup + "</div>" + (d.setup.lastTick ? "<p class='muted small'>Scheduler last ran " + when(d.setup.lastTick.at) + ".</p>" : "") + "<p class='muted small'>See Setup and help for the steps.</p></div>" +
        "<div class='adm-row'><h2>Recent emails</h2><button class='btn btn-ghost btn-sm' id='run'>Send due emails now</button></div>" +
        "<div class='adm-table'>" + (d.log.length ? "<table><tr><th>When</th><th>To</th><th>Email</th><th>From</th><th></th></tr>" + d.log.map(function (l) {
          return "<tr><td>" + when(l.at) + "</td><td>" + esc(l.e) + "</td><td>" + esc(l.s) + "</td><td>" + esc(l.k) + "</td><td>" + (l.ok ? "Sent" : "<span class='fail'>Failed: " + esc(l.err || "") + "</span>") + "</td></tr>";
        }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No emails sent yet.</p>") + "</div>";
      fire("overview", d);
      $("#run").onclick = function () {
        api("tick", {}).then(function (r) { if (r.ok) flash(r.busy ? "Already sending. Check again in a minute." : "Sent " + (r.series + r.broadcast) + " email(s) and " + (r.texts || 0) + " text(s)." + (r.capped ? " The daily email limit is reached; the rest go tomorrow." : "")); VIEWS.overview(); });
      };
    });
  };

  // ---------- contacts ----------
  VIEWS.contacts = function () {
    view.innerHTML =
      "<div class='adm-row'><input id='q' class='adm-grow' type='search' placeholder='Search name, email or mobile' aria-label='Search'>" +
      "<select id='tagf' aria-label='Tag'><option value=''>All tags</option></select>" +
      "<select id='statf' aria-label='Status'><option value=''>Any status</option><option>active</option><option>unsubscribed</option><option>bounced</option><option>complained</option><option>unconfirmed</option></select>" +
      "<select id='engf' aria-label='Engagement'><option value=''>Any engagement</option><option>engaged</option><option>warm</option><option>cold</option><option>new</option></select>" +
      "<select id='smsf' aria-label='Texts'><option value=''>Texts: any</option><option value='subscribed'>Opted in to texts</option></select></div>" +
      "<div class='adm-row'><button class='btn btn-primary btn-sm' id='add'>Add a contact</button><button class='btn btn-ghost btn-sm' id='imp'>Import CSV</button><a class='btn btn-ghost btn-sm' href='/api/admin/export'>Export CSV</a><span class='muted' id='count'></span></div>" +
      "<div class='adm-table' id='list'></div>";
    function draw() {
      var q = $("#q").value.trim().toLowerCase(), tg = $("#tagf").value, st = $("#statf").value, en = $("#engf").value, sm = $("#smsf").value;
      var list = S.contacts.filter(function (c) {
        return (!q || (c.email + " " + (c.n || "") + " " + (c.ph || "")).toLowerCase().indexOf(q) >= 0) && (!tg || (c.t || "").split("|").indexOf(tg) >= 0) &&
          (!st || c.s === st) && (!en || c.en === en) && (!sm || c.sm === sm);
      });
      $("#count").textContent = list.length + " of " + S.contacts.length;
      $("#list").innerHTML = list.length ? "<table><tr><th>Name</th><th>Email</th><th>Mobile</th><th>Tags</th><th>Status</th><th>Engagement</th><th>Joined</th></tr>" + list.slice(0, 500).map(function (c) {
        return "<tr class='click' data-e='" + esc(c.email) + "'><td>" + esc(c.n || "") + "</td><td>" + esc(c.email) + "</td><td>" + esc(c.ph || "") + (c.sm === "subscribed" ? " <span class='tag ok'>texts</span>" : "") + "</td><td>" +
          (c.t || "").split("|").filter(Boolean).map(function (t) { return "<span class='tag'>" + esc(t) + "</span>"; }).join("") + "</td><td class='st-" + esc(c.s) + "'>" + esc(c.s) + "</td><td>" + esc(c.en || "") + "</td><td>" + day(c.d) + "</td></tr>";
      }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No contacts match.</p>";
      $$("#list tr.click").forEach(function (r) { r.onclick = function () { openContact(r.dataset.e); }; });
    }
    ["q", "tagf", "statf", "engf", "smsf"].forEach(function (id) { $("#" + id).addEventListener("input", draw); });
    $("#add").onclick = function () {
      var b = dialog("<div class='adm-card' style='margin:0'><h2>Add a contact</h2><label>Email<input id='ae' type='email'></label><label>Name<input id='an'></label><label>Mobile (optional)<input id='ap' type='tel'></label><label>Tags (comma-separated)<input id='at'></label><p class='muted small'>Only add people who asked to hear from you. Adding a mobile number does not opt anyone in to texts.</p><div class='adm-row'><button class='btn btn-primary btn-sm' id='asave'>Add</button><button class='btn btn-ghost btn-sm' data-close>Cancel</button></div></div>");
      $("#asave", b).onclick = function () {
        api("contact", { email: $("#ae", b).value, name: $("#an", b).value, phone: $("#ap", b).value || undefined, addTags: $("#at", b).value.split(",").map(function (s) { return s.trim(); }).filter(Boolean) })
          .then(function (r) { if (r.ok) { flash("Added."); $("#dlg").close(); loadContacts().then(VIEWS.contacts); } });
      };
    };
    $("#imp").onclick = function () {
      var b = dialog("<div class='adm-card' style='margin:0'><h2>Import contacts</h2><p class='muted'>Choose a CSV file (a Kit export works) or paste one. It needs an email column; name, tags and status columns are used if present. Each man keeps his Kit tags, plus the tag below. Anyone Kit lists as unsubscribed, bounced or complained stays that way. No emails are sent and nobody is started on a series.</p><label>CSV file<input type='file' id='ifile' accept='.csv,text/csv'></label><label>Or paste<textarea id='icsv' placeholder='email,first_name,tags,status'></textarea></label><label>Tag<input id='itag' value='Imported'></label><div class='adm-row'><button class='btn btn-primary btn-sm' id='igo'>Import</button><button class='btn btn-ghost btn-sm' data-close>Cancel</button></div></div>");
      $("#ifile", b).onchange = function () { var f = this.files[0]; if (!f) return; var rd = new FileReader(); rd.onload = function () { $("#icsv", b).value = rd.result; flash("Loaded " + Math.max(0, String(rd.result).trim().split(/\r?\n/).length - 1) + " rows. Check the tag, then press Import."); }; rd.readAsText(f); };
      $("#igo", b).onclick = function () { api("import", { csv: $("#icsv", b).value, tag: $("#itag", b).value.trim() }).then(function (r) { if (r.ok) { flash("Imported: " + r.added + " new, " + (r.updated || 0) + " already on your list" + (r.stopped ? ", " + r.stopped + " kept as unsubscribed or bounced" : "") + (r.skipped ? ", " + r.skipped + " skipped without a valid email" : "") + ". No emails were sent."); $("#dlg").close(); loadContacts().then(VIEWS.contacts); } }); };
    };
    loadContacts().then(function () {
      $("#tagf").innerHTML = "<option value=''>All tags</option>" + tags().map(function (t) { return "<option>" + esc(t) + "</option>"; }).join("");
      draw();
    });
  };

  function openContact(email) {
    Promise.all([api("contact?e=" + encodeURIComponent(email)), api("automations")]).then(function (res) {
      var d = res[0], autos = (res[1].automations || []); if (!d.ok) return; var c = d.contact;
      var seq = Object.keys(c.seq || {}).map(function (id) { var s = c.seq[id]; return "<li>Series " + esc(id) + ": " + (s.done ? "finished" : "next " + when(s.next) + " (step " + (s.step + 1) + ")") + "</li>"; }).join("");
      var au = Object.keys(c.auto || {}).map(function (id) { var s = c.auto[id], a = autos.filter(function (x) { return x.id === id; })[0]; return "<li>Automation " + esc(a ? a.name : id) + ": " + (s.done ? "finished" : "next " + when(s.next) + " (step " + (s.step + 1) + ")") + "</li>"; }).join("");
      var fields = Object.keys(c.fields || {}).map(function (k) { return k + "=" + c.fields[k]; }).join("\n");
      var sms = c.sms && c.sms.status === "subscribed" ? "subscribed" : (c.sms ? "unsubscribed" : "none");
      var st = c.stats || {};
      var b = dialog("<div class='adm-card' style='margin:0'><h2>" + esc(c.name || c.email) + "</h2>" +
        "<p class='muted small'>" + esc(c.email) + " · joined " + day(c.created) + (c.source ? " · from " + esc(c.source) : "") + " · " + (st.sent || 0) + " emails, " + (st.opens || 0) + " opens, " + (st.clicks || 0) + " clicks</p>" +
        "<label>Name<input id='cn' value='" + esc(c.name || "") + "'></label>" +
        "<label>Mobile<input id='cp' type='tel' value='" + esc(c.phone || "") + "'></label>" +
        "<label>Texts<select id='csms'><option value='none'>Not opted in</option><option value='subscribed'>Opted in</option><option value='unsubscribed'>Opted out</option></select></label>" +
        "<label id='cnote-w' hidden>How did he agree to texts? (kept as the consent record)<input id='cnote' placeholder='For example: asked on our call, Nov 30'></label>" +
        (c.sms && c.sms.consentAt ? "<p class='muted small'>Text consent: " + when(c.sms.consentAt) + " via " + esc(c.sms.source || "") + "</p>" : "") +
        "<label>Email status<select id='cs'><option>active</option><option>unsubscribed</option><option>bounced</option></select></label>" +
        "<label>Tags (comma-separated)<input id='ct' value='" + esc((c.tags || []).join(", ")) + "'></label>" +
        "<label>Custom fields (one per line, name=value)<textarea id='cf' class='short' placeholder='city=Atlanta'>" + esc(fields) + "</textarea></label>" +
        "<div><p class='muted small'>Series and automations</p><ul class='small'>" + (seq + au || "<li>None</li>") + "</ul></div>" +
        "<div class='adm-row'><select id='cen'><option value=''>Start a series…</option><option value='step1'>Step 1 welcome series</option><option value='cohort'>Founding Cohort reminders</option></select>" +
        "<select id='cau'><option value=''>Start an automation…</option>" + autos.map(function (a) { return "<option value='" + esc(a.id) + "'>" + esc(a.name) + "</option>"; }).join("") + "</select></div>" +
        "<div><p class='muted small'>Activity</p><ul class='timeline'>" + (c.events || []).map(function (e) { return "<li><span>" + when(e.t) + "</span>" + esc(e.y) + (e.d ? ": " + esc(e.d) : "") + "</li>"; }).join("") + "</ul></div>" +
        "<div class='adm-row'><button class='btn btn-primary btn-sm' id='csave'>Save</button><button class='btn btn-ghost btn-sm' id='cdel'>Delete</button><button class='btn btn-ghost btn-sm' data-close>Close</button></div></div>");
      $("#cs", b).value = ["active", "unsubscribed", "bounced"].indexOf(c.status) >= 0 ? c.status : "active";
      fire("contact", c, b);
      $("#csms", b).value = sms;
      $("#csms", b).onchange = function () { $("#cnote-w", b).hidden = !(this.value === "subscribed" && sms !== "subscribed"); };
      $("#csave", b).onclick = function () {
        var now = $("#ct", b).value.split(",").map(function (s) { return s.trim(); }).filter(Boolean);
        var f = {}; $("#cf", b).value.split("\n").forEach(function (l) { var i = l.indexOf("="); if (i > 0) f[l.slice(0, i).trim()] = l.slice(i + 1).trim(); });
        var smsv = $("#csms", b).value;
        api("contact", { email: c.email, name: $("#cn", b).value, phone: $("#cp", b).value.trim(), addTags: now.filter(function (t) { return c.tags.indexOf(t) < 0; }), removeTags: c.tags.filter(function (t) { return now.indexOf(t) < 0; }),
          status: $("#cs", b).value, fields: f, sms: smsv === sms ? undefined : smsv, consentNote: $("#cnote", b).value })
          .then(function (r) { if (r.ok) { flash("Saved."); $("#dlg").close(); loadContacts().then(function () { if ($("#list")) VIEWS.contacts(); }); } });
      };
      $("#cen", b).onchange = function () { var id = this.value; if (id) api("enroll", { email: c.email, id: id }).then(function (r) { if (r.ok) { flash("Started the series. Anything due now has gone out."); $("#dlg").close(); } }); };
      $("#cau", b).onchange = function () { var id = this.value; if (id) api("automation-start", { email: c.email, id: id }).then(function (r) { if (r.ok) { flash("Started the automation."); $("#dlg").close(); } }); };
      $("#cdel", b).onclick = function () { if (confirm("Delete " + c.email + " completely? To stop emails but keep the record, set the status to unsubscribed instead.")) api("contact-delete", { email: c.email }).then(function () { flash("Deleted."); $("#dlg").close(); loadContacts().then(VIEWS.contacts); }); };
    });
  }

  // ---------- segments ----------
  VIEWS.segments = function () {
    Promise.all([api("segments"), loadContacts()]).then(function (res) {
      S.segments = res[0].segments || [];
      draw();
    });
    function card(s, i) {
      return "<div class='adm-card' data-i='" + i + "'><div class='adm-row'><input class='s-name adm-grow' value='" + esc(s.name) + "' aria-label='Segment name'><span class='muted small s-count'>" + (s.count != null ? s.count + " contacts" : "") + "</span></div>" +
        "<label>Has all of these tags<input class='s-all' value='" + esc((s.all || []).join(", ")) + "' placeholder='Step 1, Founding Cohort'></label>" +
        "<label>Has any of these tags<input class='s-any' value='" + esc((s.any || []).join(", ")) + "'></label>" +
        "<label>Has none of these tags<input class='s-none' value='" + esc((s.none || []).join(", ")) + "'></label>" +
        "<div class='adm-row'><label class='inline'>Status<select class='s-status'><option value=''>Any</option><option>active</option><option>unsubscribed</option><option>bounced</option><option>unconfirmed</option></select></label>" +
        "<label class='inline'>Engagement<select class='s-eng'><option value=''>Any</option><option>engaged</option><option>warm</option><option>cold</option><option>new</option></select></label>" +
        "<label class='inline'><input type='checkbox' class='s-texts'" + (s.texts ? " checked" : "") + "> Opted in to texts</label></div>" +
        "<div class='adm-row'><label class='inline'>Joined after<input type='date' class='s-after' value='" + esc(s.joinedAfter || "") + "'></label><label class='inline'>Joined before<input type='date' class='s-before' value='" + esc(s.joinedBefore || "") + "'></label></div>" +
        "<div class='adm-row'><label class='inline'>Custom field<input class='s-fk' placeholder='city' value='" + esc(s.field ? s.field.key : "") + "' size='12'></label><label class='inline'>equals<input class='s-fv' placeholder='(any value)' value='" + esc(s.field ? s.field.value : "") + "' size='14'></label></div>" +
        "<div class='adm-row'><button class='btn btn-ghost btn-sm s-cnt'>Count</button><button class='btn btn-ghost btn-sm s-del'>Delete</button></div></div>";
    }
    function read(el, s) {
      return { id: s.id, name: $(".s-name", el).value, all: $(".s-all", el).value, any: $(".s-any", el).value, none: $(".s-none", el).value, status: $(".s-status", el).value,
        engagement: $(".s-eng", el).value, texts: $(".s-texts", el).checked ? "subscribed" : "", joinedAfter: $(".s-after", el).value, joinedBefore: $(".s-before", el).value,
        field: $(".s-fk", el).value ? { key: $(".s-fk", el).value, value: $(".s-fv", el).value } : null };
    }
    function draw() {
      view.innerHTML = "<div class='adm-row'><h2>Segments</h2><button class='btn btn-ghost btn-sm' id='sadd'>New segment</button><button class='btn btn-primary btn-sm' id='ssave'>Save all</button></div>" +
        "<p class='muted'>A segment is a saved filter. It updates itself as people join, so you can send a broadcast to it any time. Tag lists are comma-separated; tags you have now: " + (tags().map(esc).join(", ") || "none yet") + ".</p>" +
        "<div id='segs'>" + (S.segments.map(card).join("") || "<p class='muted'>No segments yet.</p>") + "</div>";
      $$("#segs .adm-card").forEach(function (el) {
        var s = S.segments[+el.dataset.i];
        $(".s-status", el).value = s.status || ""; $(".s-eng", el).value = s.engagement || "";
        $(".s-cnt", el).onclick = function () { api("segment-count", { segment: read(el, s) }).then(function (r) { if (r.ok) $(".s-count", el).textContent = r.count + " contacts"; }); };
        $(".s-del", el).onclick = function () { if (confirm("Delete this segment? Save to make it final.")) { S.segments.splice(+el.dataset.i, 1); draw(); } };
      });
      $("#sadd").onclick = function () { collect(); S.segments.push({ name: "New segment", all: [], any: [], none: [] }); draw(); };
      $("#ssave").onclick = function () { collect(); api("segments", { segments: S.segments }).then(function (r) { if (r.ok) { flash("Segments saved."); VIEWS.segments(); } }); };
    }
    function collect() { $$("#segs .adm-card").forEach(function (el) { var i = +el.dataset.i; S.segments[i] = read(el, S.segments[i]); }); }
  };

  // ---------- automations ----------
  var STEP_LABEL = { wait: "Wait", email: "Send an email", sms: "Send a text", tag: "Add a tag", untag: "Remove a tag", series: "Start a series", notify: "Email me an alert", iftag: "Continue only if he has a tag", ifnottag: "Stop if he has a tag" };
  var TRIG_LABEL = { form: "Signs up through a form", tag: "Gets a tag", purchase: "Buys something", click: "Clicks a link in an email", sms: "Opts in to texts", referral: "Refers someone who signs up" };
  VIEWS.automations = function () {
    Promise.all([api("automations"), api("forms"), loadContacts()]).then(function (res) {
      S.autos = res[0].automations || []; S.forms = res[1].forms || [];
      draw();
    });
    function trigValue(a) {
      var t = a.trigger || { type: "tag", value: "" };
      if (t.type === "form") return "<select class='a-tv'><option value=''>Any form</option><option value='step1'>Step 1 page</option><option value='lowseat'>Low Seat Check</option>" + S.forms.map(function (f) { return "<option value='" + esc(f.id) + "'>" + esc(f.name) + "</option>"; }).join("") + "</select>";
      if (t.type === "purchase") return "<select class='a-tv'><option value=''>Anything</option><option value='cohort'>The Founding Cohort</option><option value='couples'>Couples counseling</option></select>";
      if (t.type === "sms" || t.type === "referral") return "";
      return "<input class='a-tv' value='" + esc(t.value) + "' placeholder='" + (t.type === "click" ? "Link contains, for example /cohort/" : "Tag name") + "' list='taglist'>";
    }
    function stepHtml(s, i, a) {
      var st = (a.stats || []).filter(function (x) { return x.i === i; })[0];
      var body = "";
      if (s.type === "wait") body = "<div class='adm-row'><label class='inline'><input type='number' min='0' class='st-days' value='" + esc(s.days || 0) + "' style='width:80px'> days</label><label class='inline'><input type='number' min='0' class='st-hours' value='" + esc(s.hours || 0) + "' style='width:80px'> hours</label></div>";
      if (s.type === "email") body = "<label>Subject<input class='st-subj' value='" + esc(s.subject) + "'></label><label>Body<textarea class='st-body'>" + esc(s.body) + "</textarea></label><div class='adm-row'><button class='btn btn-ghost btn-sm st-prev'>Preview</button><button class='btn btn-ghost btn-sm st-test'>Send me a test</button>" +
        (st && st.sent ? "<span class='muted small'>" + st.sent + " sent · " + pct(st.opens, st.sent) + " opened · " + pct(st.clicks, st.sent) + " clicked</span>" : "") + "</div>";
      if (s.type === "sms") body = "<label>Text<textarea class='st-text short' maxlength='600'>" + esc(s.text) + "</textarea></label><p class='muted small'>" + TEXTNOTE + "</p>";
      if (["tag", "untag", "iftag", "ifnottag"].indexOf(s.type) >= 0) body = "<input class='st-tag' value='" + esc(s.tag) + "' placeholder='Tag name' list='taglist'>";
      if (s.type === "series") body = "<select class='st-series'><option value='step1'>Step 1 welcome series</option><option value='cohort'>Founding Cohort reminders</option></select>";
      if (s.type === "notify") body = "<input class='st-note' value='" + esc(s.text) + "' placeholder='What to tell you, for example \"Call him this week\"'>";
      return "<div class='astep' data-s='" + i + "'><div class='astep-h'><b>" + (i + 1) + ". " + esc(STEP_LABEL[s.type]) + "</b><button class='btn btn-ghost btn-sm st-up' title='Move up'>↑</button><button class='btn btn-ghost btn-sm st-down' title='Move down'>↓</button><button class='btn btn-ghost btn-sm st-rm'>Remove</button></div>" + body + "</div>";
    }
    function card(a, i) {
      return "<div class='adm-card' data-i='" + i + "'><div class='adm-row'><input class='a-name adm-grow' value='" + esc(a.name) + "' aria-label='Automation name'><label class='inline'><input type='checkbox' class='a-on'" + (a.enabled ? " checked" : "") + "> On</label>" +
        "<span class='muted small'>" + (a.inProgress || 0) + " in progress</span></div>" +
        "<div class='adm-row'><span class='muted'>When a man</span><select class='a-tt'>" + Object.keys(TRIG_LABEL).map(function (k) { return "<option value='" + k + "'" + (a.trigger && a.trigger.type === k ? " selected" : "") + ">" + TRIG_LABEL[k].toLowerCase() + "</option>"; }).join("") + "</select>" + trigValue(a) + "</div>" +
        "<div class='asteps'>" + (a.steps || []).map(function (s, j) { return stepHtml(s, j, a); }).join("") + "</div>" +
        "<div class='adm-row'><select class='a-add'><option value=''>Add a step…</option>" + Object.keys(STEP_LABEL).map(function (k) { return "<option value='" + k + "'>" + STEP_LABEL[k] + "</option>"; }).join("") + "</select><button class='btn btn-ghost btn-sm a-del'>Delete automation</button></div>" +
        "<p class='muted small'>Each man goes through an automation once. Turn it off to pause new starts and stop men mid-way.</p></div>";
    }
    function readStep(el, s) {
      var o = { type: s.type };
      if (s.type === "wait") { o.days = $(".st-days", el).value; o.hours = $(".st-hours", el).value; }
      if (s.type === "email") { o.subject = $(".st-subj", el).value; o.body = $(".st-body", el).value; }
      if (s.type === "sms") o.text = $(".st-text", el).value;
      if (["tag", "untag", "iftag", "ifnottag"].indexOf(s.type) >= 0) o.tag = $(".st-tag", el).value.trim();
      if (s.type === "series") o.id = $(".st-series", el).value;
      if (s.type === "notify") o.text = $(".st-note", el).value;
      return o;
    }
    function collect() {
      $$("#autos > .adm-card").forEach(function (el) {
        var a = S.autos[+el.dataset.i], tv = $(".a-tv", el);
        a.name = $(".a-name", el).value; a.enabled = $(".a-on", el).checked;
        a.trigger = { type: $(".a-tt", el).value, value: tv ? tv.value.trim() : "" };
        a.steps = $$(".astep", el).map(function (sel) { return readStep(sel, a.steps[+sel.dataset.s]); });
      });
    }
    function draw() {
      view.innerHTML = "<datalist id='taglist'>" + tags().map(function (t) { return "<option value='" + esc(t) + "'>"; }).join("") + "</datalist>" +
        "<div class='adm-row'><h2>Automations</h2><button class='btn btn-ghost btn-sm' id='aadd'>New automation</button><button class='btn btn-primary btn-sm' id='asave'>Save all</button></div>" +
        "<p class='muted'>An automation starts when something happens, then runs its steps in order: waits, emails, texts, tags, series and alerts. " + FORMAT + "</p>" +
        "<div id='autos'>" + (S.autos.map(card).join("") || "<p class='muted'>No automations yet. Try: when a man gets the tag \"Step 1\", wait 21 days, continue only if he doesn't have \"Founding Cohort\", then email him an invitation.</p>") + "</div>";
      $$("#autos > .adm-card").forEach(function (el) {
        var i = +el.dataset.i, a = S.autos[i];
        $(".a-tt", el).onchange = function () { collect(); a.trigger = { type: this.value, value: "" }; draw(); };
        var tv = $(".a-tv", el); if (tv && tv.tagName === "SELECT") tv.value = (a.trigger && a.trigger.value) || "";
        $(".a-add", el).onchange = function () { if (!this.value) return; collect(); a.steps.push({ type: this.value, days: 1, hours: 0, subject: "", body: "", text: "", tag: "", id: "step1" }); draw(); };
        $(".a-del", el).onclick = function () { if (confirm("Delete this automation? Save to make it final.")) { collect(); S.autos.splice(i, 1); draw(); } };
        $$(".astep", el).forEach(function (sel) {
          var j = +sel.dataset.s, s = a.steps[j];
          if (s.type === "series") $(".st-series", sel).value = s.id || "step1";
          $(".st-rm", sel).onclick = function () { collect(); a.steps.splice(j, 1); draw(); };
          $(".st-up", sel).onclick = function () { if (!j) return; collect(); var t = a.steps[j - 1]; a.steps[j - 1] = a.steps[j]; a.steps[j] = t; draw(); };
          $(".st-down", sel).onclick = function () { if (j >= a.steps.length - 1) return; collect(); var t = a.steps[j + 1]; a.steps[j + 1] = a.steps[j]; a.steps[j] = t; draw(); };
          if (s.type === "email") {
            $(".st-prev", sel).onclick = function () { preview($(".st-subj", sel).value, $(".st-body", sel).value); };
            $(".st-test", sel).onclick = function () { testEmail($(".st-subj", sel).value, $(".st-body", sel).value); };
          }
        });
      });
      $("#aadd").onclick = function () { collect(); S.autos.push({ name: "New automation", enabled: false, trigger: { type: "tag", value: "" }, steps: [] }); draw(); };
      $("#asave").onclick = function () { collect(); api("automations", { automations: S.autos }).then(function (r) { if (r.ok) { flash("Automations saved."); VIEWS.automations(); } }); };
    }
  };

  // ---------- forms ----------
  VIEWS.forms = function () {
    api("forms").then(function (d) { S.forms = d.forms || []; draw(); });
    function card(f, i) {
      var url = location.origin + "/f/" + f.id;
      return "<div class='adm-card' data-i='" + i + "'><div class='adm-row'><input class='f-name adm-grow' value='" + esc(f.name) + "' aria-label='Form name'>" + (f.signups != null ? "<span class='muted small'>" + f.signups + " with its tag</span>" : "") + "</div>" +
        (f.created && f.id ? "<p class='small'>Page: <a class='textlink' href='" + esc(url) + "' target='_blank' rel='noopener'>" + esc(url) + "</a></p><label>Embed on another site<input readonly value='" + esc("<iframe src=\"" + url + "?embed=1\" style=\"width:100%;height:" + (f.sms ? 560 : 380) + "px;border:0\" title=\"" + f.name + "\"></iframe>") + "' onclick='this.select()'></label>" : "<p class='muted small'>Save to get the page link and embed code.</p>") +
        "<label>Headline<input class='f-head' value='" + esc(f.headline) + "'></label><label>Text under the headline<textarea class='f-text short'>" + esc(f.text) + "</textarea></label>" +
        "<div class='adm-row'><label class='inline'>Button<input class='f-btn' value='" + esc(f.button || "Sign up") + "' size='16'></label><label class='inline'>Tag<input class='f-tag' value='" + esc(f.tag) + "' list='taglist2' size='16'></label>" +
        "<label class='inline'>Start series<select class='f-series'><option value=''>None</option><option value='step1'>Step 1 welcome series</option><option value='cohort'>Founding Cohort reminders</option></select></label></div>" +
        "<div class='adm-row'><label class='inline'><input type='checkbox' class='f-phone'" + (f.phone ? " checked" : "") + "> Ask for mobile number</label><label class='inline'><input type='checkbox' class='f-sms'" + (f.sms ? " checked" : "") + "> Offer texts (adds the consent checkbox)</label>" +
        "<label class='inline'><input type='checkbox' class='f-doi'" + (f.doubleOptIn ? " checked" : "") + "> Double opt-in (confirm by email)</label></div>" +
        "<label>Message after sign-up<input class='f-ok' value='" + esc(f.success) + "' placeholder=\"You're in. Check your email.\"></label><label>Or send them to a page (optional)<input class='f-redir' value='" + esc(f.redirect) + "' placeholder='/step-1/thanks/'></label>" +
        "<div class='adm-row'><label class='inline'><input type='checkbox' class='f-arch'" + (f.archived ? " checked" : "") + "> Closed</label><button class='btn btn-ghost btn-sm f-del'>Delete</button></div></div>";
    }
    function collect() {
      $$("#forms .adm-card").forEach(function (el) {
        var f = S.forms[+el.dataset.i];
        Object.assign(f, { name: $(".f-name", el).value, headline: $(".f-head", el).value, text: $(".f-text", el).value, button: $(".f-btn", el).value, tag: $(".f-tag", el).value.trim(),
          series: $(".f-series", el).value, phone: $(".f-phone", el).checked, sms: $(".f-sms", el).checked, doubleOptIn: $(".f-doi", el).checked, success: $(".f-ok", el).value,
          redirect: $(".f-redir", el).value.trim(), archived: $(".f-arch", el).checked });
      });
    }
    function draw() {
      view.innerHTML = "<datalist id='taglist2'>" + tags().map(function (t) { return "<option value='" + esc(t) + "'>"; }).join("") + "</datalist>" +
        "<div class='adm-row'><h2>Forms</h2><button class='btn btn-ghost btn-sm' id='fadd'>New form</button><button class='btn btn-primary btn-sm' id='fsave'>Save all</button></div>" +
        "<p class='muted'>Each form gets its own page at bethemansystem.com/f/name and an embed code. Sign-ups get the form's tag, start its series, and trigger any automation set to this form. Your Step 1 page and the Low Seat Check are built in and don't appear here.</p>" +
        "<div id='forms'>" + (S.forms.map(card).join("") || "<p class='muted'>No forms yet.</p>") + "</div>";
      $$("#forms .adm-card").forEach(function (el) {
        var i = +el.dataset.i; $(".f-series", el).value = S.forms[i].series || "";
        $(".f-del", el).onclick = function () { if (confirm("Delete this form? Its page stops working once you save. Closing it is usually better.")) { collect(); S.forms.splice(i, 1); draw(); } };
      });
      $("#fadd").onclick = function () { collect(); S.forms.push({ name: "New form", headline: "", text: "", button: "Sign up", tag: "", series: "", phone: false, sms: false, doubleOptIn: false }); draw(); };
      $("#fsave").onclick = function () { collect(); api("forms", { forms: S.forms }).then(function (r) { if (r.ok) { flash("Forms saved."); VIEWS.forms(); } }); };
    }
    loadContacts();
  };

  // ---------- series ----------
  VIEWS.series = function () {
    api("sequences").then(function (d) {
      if (!d.ok) return; S.seqs = d.sequences;
      view.innerHTML = "<p class='muted'>Each series runs on its own. Edit any step, preview it, send yourself a test, then save. A step can be an email, a text, or both. " + FORMAT + "</p>" +
        S.seqs.map(function (s, si) {
          return "<section class='adm-card' data-si='" + si + "'><div class='adm-row'><h2>" + esc(s.name) + "</h2><span class='muted small'>" + esc(s.starts) + " · " + s.inProgress + " in progress" + (s.edited ? " · edited " + day(s.edited) : "") + "</span></div>" +
            (s.kind === "dated" ? "<p class='muted small'>Dates use Central time, for example 2026-12-09T10:00:00-06:00. A man who joins late skips dates already past.</p>" : "") +
            (s.kind === "weekly" ? "<p class='muted small'>One email each Thursday at 8 AM Central, in this order, starting the Thursday after he joins. No emails " + esc((s.skip || []).join(", ")) + ".</p>" : "") +
            "<div class='asteps'>" + s.emails.map(function (e, i) { return stepCard(s, e, i); }).join("") + "</div>" +
            "<div class='adm-row'><button class='btn btn-ghost btn-sm q-add'>Add a step</button><button class='btn btn-primary btn-sm q-save'>Save series</button>" + (s.edited ? "<button class='btn btn-ghost btn-sm q-reset'>Restore the original</button>" : "") + "</div></section>";
        }).join("");
      $$("section[data-si]").forEach(wire);
    });
    function stepCard(s, e, i) {
      var st = (s.stats || []).filter(function (x) { return x.i === i; })[0];
      return "<div class='astep'><div class='astep-h'><b>Step " + (i + 1) + "</b>" +
        (s.kind === "weekly" ? "<span class='muted small'>Week " + (i + 1) + "</span>" : s.kind === "dated" ? "<label class='inline'>Sends<input class='q-at' value='" + esc(e.at || "") + "' size='26'></label>" : "<label class='inline'>Days after he joins<input class='q-d' type='number' min='0' value='" + esc(e.delayDays || 0) + "' style='width:80px'></label>") +
        "<button class='btn btn-ghost btn-sm q-rm'>Remove</button></div>" +
        "<label>Email subject (leave blank for a text-only step)<input class='q-s' value='" + esc(e.subject || "") + "'></label><label>Email body<textarea class='q-b'>" + esc(e.body || "") + "</textarea></label>" +
        "<label>Text message (optional)<textarea class='q-t short' maxlength='600'>" + esc(e.text || "") + "</textarea></label>" +
        "<div class='adm-row'><button class='btn btn-ghost btn-sm q-prev'>Preview email</button><button class='btn btn-ghost btn-sm q-test'>Send me a test</button>" +
        (st && st.sent ? "<span class='muted small'>" + st.sent + " sent · " + pct(st.opens, st.sent) + " opened · " + pct(st.clicks, st.sent) + " clicked" + (st.unsubs ? " · " + st.unsubs + " unsubscribed" : "") + "</span>" : "") + "</div></div>";
    }
    function wire(sec) {
      var s = S.seqs[+sec.dataset.si];
      function wireStep(card) {
        $(".q-prev", card).onclick = function () { preview($(".q-s", card).value, $(".q-b", card).value); };
        $(".q-test", card).onclick = function () { testEmail($(".q-s", card).value, $(".q-b", card).value); };
        $(".q-rm", card).onclick = function () { if (confirm("Remove this step? It's gone once you save.")) card.remove(); };
      }
      $$(".astep", sec).forEach(wireStep);
      $(".q-add", sec).onclick = function () { var t = document.createElement("div"); t.innerHTML = stepCard(s, { subject: "", body: "", text: "", delayDays: 0, at: "" }, $$(".astep", sec).length); var c = t.firstChild; $(".asteps", sec).appendChild(c); wireStep(c); };
      $(".q-save", sec).onclick = function () {
        var emails = $$(".astep", sec).map(function (c) { var e = { subject: $(".q-s", c).value, body: $(".q-b", c).value, text: $(".q-t", c).value }; if (s.kind === "dated") e.at = $(".q-at", c).value; else if (s.kind !== "weekly") e.delayDays = $(".q-d", c).value; return e; });
        api("sequence", { id: s.id, emails: emails }).then(function (r) { if (r.ok) { flash("Saved. Men already in the series get the new wording from their next step."); VIEWS.series(); } });
      };
      var rs = $(".q-reset", sec); if (rs) rs.onclick = function () { if (confirm("Restore the original steps for this series?")) api("sequence-reset", { id: s.id }).then(function () { flash("Restored."); VIEWS.series(); }); };
    }
  };

  // ---------- broadcasts ----------
  VIEWS.broadcasts = function () {
    Promise.all([api("broadcasts"), api("segments"), loadContacts()]).then(function (res) {
      S.segments = res[1].segments || [];
      var list = res[0].broadcasts || [];
      view.innerHTML = "<div class='adm-row'><h2>Broadcasts</h2><button class='btn btn-primary btn-sm' id='newe'>New email</button><button class='btn btn-ghost btn-sm' id='news'>New text</button></div><div id='bced'></div>" +
        "<div class='adm-table'>" + (list.length ? "<table><tr><th>Message</th><th>Type</th><th>To</th><th>Status</th><th>Sent</th><th>Opened</th><th>Clicked</th></tr>" + list.map(function (b) {
          var st = b.stats || {};
          return "<tr class='click' data-id='" + esc(b.id) + "'><td>" + esc(b.s) + "</td><td>" + (b.ch === "sms" ? "Text" : "Email") + "</td><td>" + esc(audLabel(b.a)) + "</td><td>" + esc(b.st) + (b.st === "scheduled" ? " " + when(b.at) : "") + "</td><td>" + (b.st === "draft" ? "" : (b.sent || 0) + " of " + (b.total || 0)) + "</td><td>" + (b.ch === "sms" || b.st === "draft" ? "" : pct(st.opens, st.sent)) + "</td><td>" + (b.ch === "sms" || b.st === "draft" ? "" : pct(st.clicks, st.sent)) + "</td></tr>";
        }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No broadcasts yet.</p>") + "</div>";
      $$("tr.click", view).forEach(function (r) { r.onclick = function () { api("broadcast?id=" + encodeURIComponent(r.dataset.id)).then(function (x) { if (x.ok) edit(x.broadcast, x.stats); }); }; });
      $("#newe").onclick = function () { edit({ channel: "email", status: "draft", audience: { type: "all" } }); };
      $("#news").onclick = function () { edit({ channel: "sms", status: "draft", audience: { type: "all" } }); };
    });
    function audLabel(a) {
      if (!a || a === "all" || a === "all:") return "Everyone";
      var i = a.indexOf(":"), t = a.slice(0, i), v = a.slice(i + 1);
      if (t === "tag") return "Tag: " + v;
      if (t === "segment") { var s = S.segments.filter(function (x) { return x.id === v; })[0]; return "Segment: " + (s ? s.name : v); }
      if (t === "unopened") return "Didn't open the first send";
      return "Everyone";
    }
    function edit(b, stats) {
      var sms = b.channel === "sms", draft = ["draft", "scheduled"].indexOf(b.status) >= 0, el = $("#bced");
      var aud = b.audience || { type: "all" };
      var opts = "<option value='all:'>Everyone" + (sms ? " who opted in to texts" : " active") + "</option>" + tags().map(function (t) { return "<option value='tag:" + esc(t) + "'>Tag: " + esc(t) + "</option>"; }).join("") +
        S.segments.map(function (s) { return "<option value='segment:" + esc(s.id) + "'>Segment: " + esc(s.name) + "</option>"; }).join("") + (aud.type === "unopened" ? "<option value='unopened:" + esc(aud.value) + "'>People who didn't open the first send</option>" : "");
      var html = "<div class='adm-card'><h2>" + (b.id ? (draft ? "Edit " + (sms ? "text" : "email") : "Sent " + (sms ? "text" : "email")) : "New " + (sms ? "text" : "email")) + "</h2>" +
        "<label>Send to<select id='baud'" + (draft ? "" : " disabled") + ">" + opts + "</select></label><p class='muted small' id='bcount'></p>";
      if (sms) html += "<label>Text<textarea id='btext' class='short' maxlength='600'" + (draft ? "" : " readonly") + ">" + esc(b.text || "") + "</textarea></label><p class='muted small'>" + TEXTNOTE + "</p>";
      else html += "<label>Subject<input id='bsubj' value='" + esc(b.subject || "") + "'" + (draft ? "" : " readonly") + "></label>" +
        "<label>Second subject to test (optional: half get each)<input id='bsubjb' value='" + esc(b.subjectB || "") + "'" + (draft ? "" : " readonly") + "></label>" +
        "<label>Body<textarea id='bbody'" + (draft ? "" : " readonly") + ">" + esc(b.body || "") + "</textarea></label><p class='muted small'>" + FORMAT + "</p>";
      if (draft) {
        html += "<div class='adm-row'>" + (sms ? "<input id='bphone' type='tel' placeholder='Your mobile, for a test'><button class='btn btn-ghost btn-sm' id='btest'>Text me a test</button>" : "<button class='btn btn-ghost btn-sm' id='bprev'>Preview</button><button class='btn btn-ghost btn-sm' id='btest'>Send me a test</button>") +
          "<button class='btn btn-ghost btn-sm' id='bsave'>Save draft</button></div>" +
          "<div class='adm-row'><button class='btn btn-primary btn-sm' id='bsend'>Send now</button><span class='muted'>or schedule</span><input type='datetime-local' id='bat'><button class='btn btn-ghost btn-sm' id='bsched'>Schedule</button>" +
          (b.status === "scheduled" ? "<button class='btn btn-ghost btn-sm' id='bunsched'>Unschedule (" + when(b.scheduledAt) + ")</button>" : "") + (b.id ? "<button class='btn btn-ghost btn-sm' id='bdel'>Delete</button>" : "") + "<button class='btn btn-ghost btn-sm' id='bclose'>Close</button></div>" +
          "<p class='muted small'>Emails go out within the daily limit; the rest go the next day. Texts go out between 9 AM and 8 PM Central. Unsubscribed, bounced and opted-out contacts are always skipped.</p>";
      } else {
        var st = stats || {};
        html += "<p>" + esc(b.status) + " · " + (b.sent || 0) + " sent of " + (b.total || 0) + (b.failed ? " · " + b.failed + " failed" : "") + "</p>";
        if (!sms) {
          html += "<p>" + pct(st.opens, st.sent) + " opened (" + (st.opens || 0) + ") · " + pct(st.clicks, st.sent) + " clicked (" + (st.clicks || 0) + ") · " + (st.unsubs || 0) + " unsubscribed · " + (st.bounces || 0) + " bounced</p>";
          if (b.subjectB && st.v) html += "<p class='small'>A: \"" + esc(b.subject) + "\" " + pct((st.v.A || {}).opens, (st.v.A || {}).sent) + " opened · B: \"" + esc(b.subjectB) + "\" " + pct((st.v.B || {}).opens, (st.v.B || {}).sent) + " opened</p>";
          var links = Object.keys(st.links || {}).sort(function (x, y) { return st.links[y] - st.links[x]; });
          if (links.length) html += "<div class='small'><p class='muted'>Links clicked</p><ul>" + links.map(function (u) { return "<li>" + esc(u) + ": " + st.links[u] + "</li>"; }).join("") + "</ul></div>";
          html += "<p class='muted small'>Opens are approximate: some email apps load images automatically.</p>";
        }
        html += "<div class='adm-row'>" + (!sms && b.status === "sent" ? "<button class='btn btn-ghost btn-sm' id='bresend'>Resend to people who didn't open</button>" : "") + "<button class='btn btn-ghost btn-sm' id='bclose'>Close</button></div>";
      }
      el.innerHTML = html + "</div>";
      $("#baud").value = aud.type + ":" + (aud.value || "");
      function data() { var a = $("#baud").value, i = a.indexOf(":"); return { id: b.id, channel: sms ? "sms" : "email", audience: { type: a.slice(0, i), value: a.slice(i + 1) }, subject: sms ? "" : $("#bsubj").value, subjectB: sms ? "" : $("#bsubjb").value, body: sms ? "" : $("#bbody").value, text: sms ? $("#btext").value : "" }; }
      function count() { var x = data(); api("broadcast-count", { audience: x.audience, channel: x.channel }).then(function (r) { if (r.ok) $("#bcount").textContent = r.count + " " + (sms ? "people opted in to texts" : "active contacts") + " in this audience."; }); }
      count(); $("#baud").onchange = count;
      $("#bclose").onclick = function () { el.innerHTML = ""; };
      if (!draft) { var rs = $("#bresend"); if (rs) rs.onclick = function () { api("broadcast-resend", { id: b.id }).then(function (r) { if (r.ok) { flash("Draft created for people who didn't open. Change the subject, then send."); VIEWS.broadcasts(); setTimeout(function () { edit(r.broadcast); }, 400); } }); }; return; }
      function save() { return api("broadcast", data()).then(function (r) { if (r.ok) b = r.broadcast; return r; }); }
      if (sms) $("#btest").onclick = function () { api("test-sms", { phone: $("#bphone").value, text: $("#btext").value }).then(function (r) { if (r.ok) flash("Test text sent."); }); };
      else { $("#bprev").onclick = function () { preview($("#bsubj").value, $("#bbody").value); }; $("#btest").onclick = function () { testEmail($("#bsubj").value, $("#bbody").value); }; }
      $("#bsave").onclick = function () { save().then(function (r) { if (r.ok) { flash("Draft saved."); VIEWS.broadcasts(); } }); };
      $("#bsend").onclick = function () {
        var x = data(); api("broadcast-count", { audience: x.audience, channel: x.channel }).then(function (c) {
          if (!c.ok || !confirm("Send this " + (sms ? "text" : "email") + " to " + c.count + " " + (c.count === 1 ? "person" : "people") + " now? This can't be undone.")) return;
          save().then(function (r) { if (r.ok) return api("broadcast-send", { id: b.id }); }).then(function (r) { if (r && r.ok) { flash("Sending. Progress shows in the list."); VIEWS.broadcasts(); } });
        });
      };
      $("#bsched").onclick = function () {
        var v = $("#bat").value; if (!v) { flash("Pick a date and time first."); return; }
        save().then(function (r) { if (r.ok) return api("broadcast-send", { id: b.id, at: new Date(v).toISOString() }); }).then(function (r) { if (r && r.ok) { flash("Scheduled for " + when(new Date(v).getTime()) + "."); VIEWS.broadcasts(); } });
      };
      var un = $("#bunsched"); if (un) un.onclick = function () { api("broadcast-unschedule", { id: b.id }).then(function (r) { if (r.ok) { flash("Back to draft."); VIEWS.broadcasts(); } }); };
      var del = $("#bdel"); if (del) del.onclick = function () { if (confirm("Delete this draft?")) api("broadcast-delete", { id: b.id }).then(function () { VIEWS.broadcasts(); }); };
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  };

  // ---------- texts ----------
  VIEWS.texts = function () {
    api("texts").then(function (d) {
      if (!d.ok) return;
      $("#unread").hidden = true;
      var threads = {};
      d.texts.forEach(function (t) { if (!t.ph) return; (threads[t.ph] = threads[t.ph] || []).push(t); });
      var phones = Object.keys(threads).sort(function (a, b) { return threads[b][0].at - threads[a][0].at; });
      view.innerHTML = (d.ready ? "" : "<div class='adm-card'><h3>Texting isn't connected yet</h3><p class='muted'>Everything is built. Add your Twilio keys in Cloudflare to switch it on. See Setup and help.</p></div>") +
        "<div class='adm-row'><h2>Texts</h2><input id='tphone' type='tel' placeholder='Your mobile'><button class='btn btn-ghost btn-sm' id='ttest'>Text me a test</button></div>" +
        "<div class='adm-table'>" + (phones.length ? "<table><tr><th>Who</th><th>Last message</th><th>When</th></tr>" + phones.map(function (p) {
          var t = threads[p][0], who = threads[p].filter(function (x) { return x.n || x.e; })[0];
          return "<tr class='click' data-p='" + esc(p) + "'><td>" + esc(who ? who.n || who.e : p) + "<br><span class='muted small'>" + esc(p) + "</span></td><td>" + (t.dir === "in" ? "<b>" : "") + esc(t.b) + (t.dir === "in" ? "</b>" : "") + "</td><td>" + when(t.at) + "</td></tr>";
        }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No texts yet. Replies to your texts show up here, and you get an email for each one.</p>") + "</div>";
      $("#ttest").onclick = function () { api("test-sms", { phone: $("#tphone").value, text: "This is a test from your dashboard." }).then(function (r) { if (r.ok) flash("Test text sent."); }); };
      $$("tr.click", view).forEach(function (r) {
        r.onclick = function () {
          var p = r.dataset.p, msgs = threads[p].slice().reverse(), who = threads[p].filter(function (x) { return x.e; })[0];
          var b = dialog("<h2>" + esc(who ? (who.n || who.e) : p) + "</h2><p class='muted small'>" + esc(p) + "</p><div class='thread'>" +
            msgs.map(function (m) { return "<div class='bubble " + (m.dir === "in" ? "in" : "out") + "'>" + esc(m.b) + "<small>" + when(m.at) + (m.ok === 0 ? " · failed" : "") + "</small></div>"; }).join("") +
            "</div><label class='small muted' style='display:grid;gap:6px;margin-top:12px'>Reply<textarea id='rbody' class='short' maxlength='600'></textarea></label><div class='adm-row' style='margin-top:8px'><button class='btn btn-primary btn-sm' id='rsend'>Send reply</button><button class='btn btn-ghost btn-sm' data-close>Close</button></div>" +
            "<p class='muted small'>Replies to a man's own text are conversation, so they go out right away. Don't use replies for promotions.</p>");
          $(".thread", b).scrollTop = 1e6;
          fire("textReply", b);
          $("#rsend", b).onclick = function () { api("text-reply", { phone: p, email: who ? who.e : "", body: $("#rbody", b).value }).then(function (x) { if (x.ok) { flash("Sent."); $("#dlg").close(); VIEWS.texts(); } }); };
        };
      });
    });
  };

  // ---------- help ----------
  VIEWS.help = function () {
    api("overview").then(function (d) {
      var s = d.setup || {};
      var mark = function (on) { return "<span class='tag " + (on ? "ok" : "warn") + "'>" + (on ? "Done" : "To do") + "</span>"; };
      view.innerHTML = "<div class='help'>" +
        "<div class='adm-card'><div class='adm-row'><h2>1. Hourly scheduler</h2>" + mark(s.scheduler) + "</div><p>Emails still go out when people sign up or you open this dashboard. The scheduler makes timing exact.</p><ol>" +
        "<li>GitHub: Settings, General, Default branch: switch to <code>claude/sharp-sagan-jrcxxn</code>.</li><li>Make a long random password.</li>" +
        "<li>Cloudflare: Workers &amp; Pages, bethemansystem, Settings, Variables and Secrets, add <code>CRON_SECRET</code> (type Secret) with that password.</li>" +
        "<li>GitHub: Settings, Secrets and variables, Actions, add <code>CRON_SECRET</code> with the same password.</li><li>GitHub: Actions, Email scheduler, Run workflow. It should turn green.</li></ol></div>" +
        "<div class='adm-card'><div class='adm-row'><h2>2. Bounce and spam-complaint protection</h2>" + mark(s.bounces) + "</div><ol>" +
        "<li>Resend: Webhooks, Add endpoint: <code>https://bethemansystem.com/api/mail/webhook</code>, events <code>email.bounced</code> and <code>email.complained</code>.</li>" +
        "<li>Copy its signing secret (starts <code>whsec_</code>) into Cloudflare as <code>RESEND_WEBHOOK_SECRET</code> (type Secret).</li></ol><p>After that, a bad address or a spam report takes that person off the list automatically.</p></div>" +
        "<div class='adm-card'><div class='adm-row'><h2>3. Texts (Twilio)</h2>" + mark(s.texts) + "</div><ol>" +
        "<li>Create a Twilio account at twilio.com and buy a number. A toll-free number is usually the simplest for a small sender.</li>" +
        "<li>Get it approved for business texting. US carriers require this before texts are delivered: toll-free verification for a toll-free number, or A2P 10DLC brand and campaign registration for a local number. Use your Terms and Privacy pages and the consent text on your forms; both already include what carriers ask for. Approval usually takes days to a few weeks, and Twilio charges small fees; check current pricing.</li>" +
        "<li>Cloudflare: add <code>TWILIO_ACCOUNT_SID</code>, <code>TWILIO_AUTH_TOKEN</code> (type Secret) and <code>TWILIO_FROM</code> (your number, like +18885551234).</li>" +
        "<li>Twilio: your number, Messaging, \"A message comes in\": Webhook <code>https://bethemansystem.com/api/sms/inbound</code>, HTTP POST.</li>" +
        "<li>Come back to the Texts tab and send yourself a test.</li></ol></div>" +
        "<div class='adm-card'><h2>How it works</h2><ul>" +
        "<li><b>Contacts</b> come from your forms, the Step 1 page, the Low Seat Check, purchases, free calls, couples inquiries and the Club, each with a tag.</li>" +
        "<li><b>Email series</b> are fixed sequences. <b>Automations</b> are your own: a trigger, then steps.</li>" +
        "<li><b>Segments</b> are saved filters you can send a broadcast to.</li>" +
        "<li><b>Every list email</b> has an unsubscribe link, one-click unsubscribe, your mailing address and the ADHD disclaimer. Every list text starts \"Be The Man:\" and ends \"Reply STOP to opt out.\", goes only to men who checked the consent box, and only between 9 AM and 8 PM Central.</li>" +
        "<li><b>Limits:</b> " + (d.cap || 90) + " list emails a day (Resend's free plan allows 100), " + (d.smsCap || 50) + " texts a day. Set <code>MAIL_DAILY_CAP</code> or <code>SMS_DAILY_CAP</code> in Cloudflare to change them.</li>" +
        "<li><b>Never</b> add people who didn't ask to hear from you, and never mark someone as opted in to texts without his clear yes.</li></ul></div></div>";
    });
  };

  window.BTM = { $: $, $$: $$, esc: esc, day: day, when: when, api: api, flash: flash, dialog: dialog, view: view, VIEWS: VIEWS, show: show, tags: tags, after: after, S: S };
  document.addEventListener("DOMContentLoaded", function () {
    var first = (location.hash || "").slice(1) || "overview";
    show(first);
    if (first !== "overview") api("overview").then(function (d) { if (d.ok) $("#unread").hidden = !d.unreadTexts; });
  });
})();
