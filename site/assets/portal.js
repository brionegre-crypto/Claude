// The men's portal: one page, screens by #hash. Talks to /api/portal/*.
(function () {
  "use strict";
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var esc = function (v) { return String(v == null ? "" : v).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); };
  var AS = new URLSearchParams(location.search).get("as");
  var Q = AS ? "?as=" + encodeURIComponent(AS) : "";
  var S = null; // state from /api/portal/me
  var DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var DOWL = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  var PILLARS = { faith: "Faith", home: "Home", health: "Health", work: "Work" };
  var dayIdx = 2; // which of the three markable days is shown (2 = today)

  function api(route, body, opts) {
    opts = opts || {};
    var init = body === undefined ? { method: "GET" } : { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) };
    if (opts.form) init = { method: "POST", body: opts.form };
    return fetch("/api/portal/" + route + Q, init).then(function (r) {
      if (r.status === 401) { location.href = "/portal/login/?next=" + encodeURIComponent(location.pathname + location.hash); throw new Error("signed out"); }
      return r.json().then(function (d) { if (!d.ok) throw new Error(d.error || "Something went wrong."); return d; });
    });
  }
  function flash(msg, err) {
    var f = $("#flash"); f.textContent = msg; f.className = "pt-flash" + (err ? " err" : ""); f.hidden = false;
    clearTimeout(flash.t); flash.t = setTimeout(function () { f.hidden = true; }, err ? 6000 : 2600);
  }
  function crisis(d) { if (d && d.crisis) alert(d.crisis); }
  function fail(e) { if (e.message !== "signed out") flash(e.message, true); }
  function nice(d, long) { var x = new Date(d + "T12:00:00Z"); return x.toLocaleDateString("en-US", long ? { weekday: "long", month: "long", day: "numeric", timeZone: "UTC" } : { month: "short", day: "numeric", timeZone: "UTC" }); }
  function when(ms) { return new Date(ms).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }); }
  function cById(id) { return S.record.commitments.filter(function (c) { return c.id === id; })[0]; }
  function ro() { return S.coach || S.me.access === "readonly"; }

  // Lesson text: blank line = paragraph, "- " list, **bold**, [[Button|url]], [text](url).
  function md(src) {
    var inline = function (t) {
      return esc(t).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
        .replace(/\[\[([^|\]]+)\|([^\]]+)\]\]/g, function (_, l, u) { return '<a class="pb primary" href="' + local(u) + '">' + l + "</a>"; })
        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, function (_, l, u) { return '<a href="' + local(u) + '">' + l + "</a>"; });
    };
    return String(src || "").split(/\n\s*\n/).map(function (b) {
      var lines = b.split("\n");
      if (lines.every(function (l) { return /^\s*- /.test(l); })) return "<ul>" + lines.map(function (l) { return "<li>" + inline(l.replace(/^\s*- /, "")) + "</li>"; }).join("") + "</ul>";
      return "<p>" + lines.map(inline).join("<br>") + "</p>";
    }).join("");
  }
  function local(u) { return String(u).replace("https://bethemansystem.com/portal/", "/portal/" + (AS ? "?as=" + encodeURIComponent(AS) : "")); }
  function yt(u) {
    var m = String(u || "").match(/(?:youtu\.be\/|v=|embed\/|shorts\/)([\w-]{11})/);
    return m ? '<div class="video"><iframe src="https://www.youtube-nocookie.com/embed/' + m[1] + '" title="Video" allow="accelerometer; encrypted-media; picture-in-picture" allowfullscreen loading="lazy"></iframe></div>' : (u ? '<p><a href="' + esc(u) + '" target="_blank" rel="noopener">Watch the video</a></p>' : "");
  }
  function pill(st) {
    var m = { approved: ["ok", "Approved"], submitted: ["wait", "With Brian"], revisit: ["redo", "Revisit"], open: ["", "Open"], locked: ["", "Locked"] }[st] || ["", st];
    return '<span class="pill ' + m[0] + '">' + m[1] + "</span>";
  }

  function load() { return api("me").then(function (d) { S = d; document.getElementById("pt").classList.toggle("large", !!S.me.large); coachBar(); }); }
  function coachBar() {
    var b = $("#coachbar");
    if (S.coach) { b.hidden = false; b.innerHTML = "Coach view: " + esc(S.me.name || S.me.email) + ' · <a href="/admin/#man/' + encodeURIComponent(S.me.email) + '">Back</a>'; }
    else if (S.admin) { b.hidden = false; b.innerHTML = '<a href="/admin/">Coach dashboard</a>'; }
    else b.hidden = true;
  }

  var VIEWS = {};
  function route() {
    var h = (location.hash || "#today").slice(1), parts = h.split("/");
    var name = parts[0];
    if (/^step-\d$/.test(name)) { parts = ["step", name.slice(5)]; name = "step"; }
    var v = VIEWS[name] || VIEWS.today;
    $$(".pt-nav a").forEach(function (a) {
      var n = a.getAttribute("data-nav");
      a.classList.toggle("on", n === name || (n === "steps" && name === "step") || (n === "lessons" && name === "lesson") || (n === "ledger" && (name === "review" || name === "commitments")) || (n === "more" && ["messages", "settings", "partner"].indexOf(name) >= 0));
    });
    var view = $("#view");
    try { view.innerHTML = v.apply(null, parts.slice(1)); } catch (e) { view.innerHTML = '<p class="muted">Something went wrong. Pull down to refresh.</p>'; console.error(e); }
    if (v.after) v.after.apply(null, parts.slice(1));
    window.scrollTo(0, 0);
  }
  function rerender() { var y = window.scrollY; route(); window.scrollTo(0, y); }
  function refresh() { return load().then(rerender); }

  // ---------- Today ----------

  function markCard() {
    if (!S.scorecard) return "";
    var day = S.days[dayIdx];
    var tabs = S.days.map(function (d, i) { return '<button type="button" data-day="' + i + '" class="' + (i === dayIdx ? "on" : "") + '">' + (i === 2 ? "Today" : i === 1 ? "Yesterday" : DOW[d.dow]) + "</button>"; }).join("");
    var rows = day.items.length ? day.items.map(function (it) {
      var c = cById(it.id);
      var b = function (v, t) { return '<button type="button" data-mark="' + v + '" data-id="' + it.id + '" class="' + v + (it.v === v ? " on" : "") + '"' + (ro() ? " disabled" : "") + ">" + t + "</button>"; };
      return '<div class="mark"><div class="what">' + esc(c.what) + "</div>" + (S.hardWeek && c.floor ? '<div class="floor">This week: ' + esc(c.floor) + "</div>" : "") +
        '<div class="taps">' + b("k", "✓ Kept") + b("f", "↓ Floor") + b("m", "✕ Missed") + "</div></div>";
    }).join("") : '<p class="muted">Nothing scheduled on ' + DOWL[day.dow] + ". Rest is part of the plan.</p>";
    return '<section class="card"><div class="row between"><h2>' + nice(day.date, true) + '</h2><span class="dim">' + S.score.k + " of " + S.score.t + " this week</span></div>" +
      '<div class="daytabs">' + tabs + "</div>" + rows + '<p class="dim">Floor counts as kept. You can mark today and the two days before.</p></section>';
  }
  VIEWS.today = function () {
    var out = [];
    var hi = S.me.first ? "Brother " + esc(S.me.first) : "Welcome";
    out.push("<h1>" + hi + ".</h1>");
    if (S.me.access === "readonly" && !S.coach) out.push('<section class="card hi"><p>Your portal is read-only now. Everything you built is still here. <a href="/club/">Join the Club</a> to keep tracking with the brothers.</p></section>');
    if (S.hardWeek) out.push('<section class="card hi"><h2>Hard week</h2><p>Your commitments are on their floor versions until Sunday. Brian knows. Zero is the only real miss.</p></section>');
    var nexts = (S.record.next || []).filter(function (n) { return !n.done; });
    if (nexts.length) out.push('<section class="card hi"><h2>Your next step from Brian</h2>' + nexts.map(function (n) {
      return '<label class="check"><input type="checkbox" data-next="' + n.id + '"' + (ro() ? " disabled" : "") + "> <span>" + esc(n.text) + (n.due ? ' <span class="dim">by ' + nice(n.due) + "</span>" : "") + "</span></label>";
    }).join("") + "</section>");
    // Current step
    var cur = [1, 2, 3, 4].filter(function (n) { return S.steps[n].status !== "approved"; })[0];
    if (cur) {
      var st = S.steps[cur];
      var msg = st.status === "locked" ? (st.upgrade ? "Steps 2 to 4 are part of the Founding Cohort and the Club." : st.waitingOn ? "Opens once Brian approves Step " + st.waitingOn + "." : st.opens ? "Opens " + nice(st.opens) + "." : "") :
        st.status === "submitted" ? "Brian has it. You'll hear back soon." : st.status === "revisit" ? "Brian asked you to take another look." : "Open now.";
      out.push('<section class="card"><div class="row between"><h2>Step ' + cur + ": " + esc(S.stepNames[cur]) + "</h2>" + pill(st.status) + '</div><p class="muted">' + msg + "</p>" +
        (st.status === "open" || st.status === "revisit" ? '<a class="pb primary" href="#step-' + cur + '">Work on Step ' + cur + "</a>" : st.upgrade ? '<a class="pb" href="/cohort/">See the Founding Cohort</a>' : "") + "</section>");
    }
    out.push(markCard());
    if (S.scorecard) {
      var streak = S.streak ? "Weeks reported in a row: <strong>" + S.streak + "</strong>" : "New week, new count. Restart Monday.";
      out.push('<section class="card"><p>' + streak + "</p>" + (S.isSunday && !S.review ? '<a class="pb primary" href="#review">Do your Sunday review</a>' : S.isSunday ? '<p class="dim">Sunday review done. Well done.</p>' : "") + "</section>");
    }
    // Session
    if (S.nextSession && (S.me.role === "cohort" || S.me.role === "admin")) {
      var isToday = S.nextSession === S.today;
      out.push('<section class="card"><h2>' + (isToday ? "Tonight, 7 PM Central" : "Next session: " + nice(S.nextSession, true) + ", 7 PM Central") + "</h2>" +
        (S.checkIn ? (S.record.attendance[S.checkIn] ? '<p>You\'re checked in. Glad you\'re here.</p>' : '<button type="button" class="pb primary block" id="checkin"' + (ro() ? " disabled" : "") + ">I'm here</button>") : "") +
        (S.meet ? '<p><a class="pb" href="' + esc(S.meet) + '" target="_blank" rel="noopener">Join the call</a></p>' : "") +
        '<label for="prep">What do you want help with on this call?</label><textarea id="prep" placeholder="One thing you\'re stuck on, or a question for Brian."' + (ro() ? " disabled" : "") + ">" + esc(S.callPrep ? S.callPrep.text : "") + "</textarea>" +
        '<p><button type="button" class="pb small" id="saveprep"' + (ro() ? " disabled" : "") + ">Send to Brian</button> " + (S.callPrep ? '<span class="dim">Sent ' + when(S.callPrep.at) + "</span>" : "") + "</p></section>");
    }
    var shared = (S.record.shared || []).slice(0, 3);
    if (shared.length) out.push('<section class="card"><h2>Notes from Brian</h2>' + shared.map(function (n) { return "<p>" + esc(n.text) + ' <span class="dim">' + when(n.at) + "</span></p>"; }).join("") + "</section>");
    if (S.scorecard && !S.hardWeek && !ro()) out.push('<p class="center"><button type="button" class="pb small" id="hard">I\'m in a hard week</button></p>');
    return out.join("");
  };
  VIEWS.today.after = function () { bindMarks(); bindNext();
    var ci = $("#checkin"); if (ci) ci.onclick = function () { api("checkin", {}).then(function () { flash("Checked in."); return refresh(); }).catch(fail); };
    var sp = $("#saveprep"); if (sp) sp.onclick = function () { api("callprep", { text: $("#prep").value }).then(function (d) { crisis(d); flash("Sent to Brian."); return refresh(); }).catch(fail); };
    var h = $("#hard"); if (h) h.onclick = function () {
      var note = prompt("Your commitments will switch to their floor versions until Sunday, and Brian will know. Anything you want him to know? (optional)", "");
      if (note === null) return;
      api("hard", { on: true, note: note }).then(function (d) { crisis(d); flash("Floor week. Zero is the only real miss."); return refresh(); }).catch(fail);
    };
  };
  function bindMarks() {
    $$("[data-day]").forEach(function (b) { b.onclick = function () { dayIdx = Number(b.getAttribute("data-day")); rerender(); }; });
    $$("[data-mark]").forEach(function (b) {
      b.onclick = function () {
        var day = S.days[dayIdx], id = b.getAttribute("data-id"), v = b.getAttribute("data-mark");
        var it = day.items.filter(function (x) { return x.id === id; })[0];
        var nv = it.v === v ? "" : v;
        it.v = nv; rerender();
        api("mark", { date: day.date, id: id, v: nv }).then(function (d) { if (day.date > addDaysLocal(S.thisWeek, -7)) S.score = d.week; else S.lastScore = d.week; rerender(); }).catch(function (e) { fail(e); refresh(); });
      };
    });
  }
  function addDaysLocal(d, n) { var x = new Date(d + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); }
  function bindNext() {
    $$("[data-next]").forEach(function (b) { b.onchange = function () { api("next-done", { id: b.getAttribute("data-next"), done: b.checked }).then(function () { flash("Marked done. Well done."); return refresh(); }).catch(fail); }; });
  }

  // ---------- Steps ----------

  VIEWS.steps = function () {
    return "<h1>The four steps.</h1><p class=\"muted\">Each step opens when Brian approves the one before it. Prefer paper? Print the worksheet, then type it in here when you're ready.</p>" +
      '<section class="card steplist">' + [1, 2, 3, 4].map(function (n) {
        var st = S.steps[n];
        return '<a href="#step-' + n + '"><span><strong>Step ' + n + ":</strong> " + esc(S.stepNames[n]) + (st.status === "locked" && st.opens ? '<br><span class="dim">Opens ' + nice(st.opens) + "</span>" : "") + "</span>" + pill(st.status) + "</a>";
      }).join("") + "</section>" +
      '<section class="card"><h2>Printables</h2>' + S.materials.map(function (m) { return '<p><a href="' + esc(m.url) + '" target="_blank" rel="noopener">' + esc(m.title) + "</a></p>"; }).join("") + "</section>";
  };

  var ROLE_DEFAULTS = ["Son of God", "Husband", "Father", "Son", "Worker", "Brother"];
  function stepHead(n) {
    var st = S.steps[n], rec = S.record.steps[n] || {};
    return '<p class="dim"><a href="#steps">‹ All steps</a></p><div class="row between"><h1>Step ' + n + ": " + esc(S.stepNames[n]) + "</h1>" + pill(st.status) + "</div>" +
      (rec.note ? '<section class="card hi"><h2>From Brian</h2><p>' + esc(rec.note) + "</p></section>" : "") +
      (st.status === "submitted" ? '<p class="muted">Brian has this step. You can still make changes.</p>' : "") +
      (st.status === "approved" ? '<p class="muted">Approved. You can still update it.</p>' : "");
  }
  function lockedStep(n) {
    var st = S.steps[n];
    return stepHead(n) + '<section class="card"><p>' + (st.upgrade ? 'Steps 2 to 4 are part of the Founding Cohort and the Club. <a href="/cohort/">See the Founding Cohort</a>.' :
      st.waitingOn ? "This step opens once Brian approves Step " + st.waitingOn + "." : st.opens ? "This step opens " + nice(st.opens, true) + "." : "This step isn't open yet.") + "</p></section>";
  }
  function stepButtons(n) {
    if (ro()) return "";
    var st = S.steps[n].status;
    return '<div class="row" style="margin-top:16px"><button type="button" class="pb" id="save">Save</button>' +
      (st !== "approved" ? '<button type="button" class="pb primary" id="submit">' + (st === "submitted" ? "Send again" : "Send to Brian") + "</button>" : "") + "</div>";
  }
  function commitEditor(list, mode) {
    // mode 2: what/pillar/days/measure/miss. mode 3: time/place/trigger/breaks/floor. mode "all": both.
    var c2 = mode === 2 || mode === "all", c3 = mode === 3 || mode === "all";
    var rows = list.map(function (c, i) {
      var days = [1, 2, 3, 4, 5, 6, 0].map(function (d) { return '<label><input type="checkbox" data-f="day" value="' + d + '"' + (c.days.indexOf(d) >= 0 ? " checked" : "") + "><span>" + DOW[d] + "</span></label>"; }).join("");
      return '<section class="card" data-c="' + i + '" data-id="' + esc(c.id || "") + '"><div class="row between"><h2>Commitment ' + (i + 1) + "</h2>" + (c2 && !ro() ? '<button type="button" class="pb small" data-del="' + i + '">Remove</button>' : "") + "</div>" +
        (c2 ? '<label>What will you do? Make it checkable.</label><input type="text" data-f="what" value="' + esc(c.what) + '" placeholder="Phone in the drawer from 7:40 to 9 PM">' +
          '<label>Pillar</label><select data-f="pillar"><option value="">Choose…</option>' + Object.keys(PILLARS).map(function (p) { return '<option value="' + p + '"' + (c.pillar === p ? " selected" : "") + ">" + PILLARS[p] + "</option>"; }).join("") + "</select>" +
          '<label>Which days?</label><div class="days">' + days + "</div>" +
          '<label>How will you know you kept it?</label><input type="text" data-f="measure" value="' + esc(c.measure) + '" placeholder="Yes or no, with a number">' +
          '<label>What counts as a miss?</label><input type="text" data-f="miss" value="' + esc(c.miss) + '" placeholder="Decide now, so Sunday is counting, not arguing">'
          : "<p><strong>" + esc(c.what) + '</strong><br><span class="dim">' + (c.days.length ? c.days.slice().sort(function (a, b) { return ((a + 6) % 7) - ((b + 6) % 7); }).map(function (d) { return DOW[d]; }).join(", ") : "Every day") + "</span></p>") +
        (c3 ? '<div class="row"><div style="flex:1;min-width:130px"><label>Time</label><input type="time" data-f="time" value="' + esc(c.time) + '"></div><div style="flex:2;min-width:180px"><label>Place</label><input type="text" data-f="place" value="' + esc(c.place) + '" placeholder="Kitchen table"></div></div>' +
          '<label>Trigger: right after…</label><input type="text" data-f="trigger" value="' + esc(c.trigger) + '" placeholder="When I park at home">' +
          '<label>What usually breaks it?</label><input type="text" data-f="breaks" value="' + esc(c.breaks) + '"><div class="chips">' + (S.examples.breakers || []).map(function (b) { return '<button type="button" data-breaker="' + esc(b) + '">' + esc(b) + "</button>"; }).join("") + "</div>" +
          '<label>Bad-day version (two minutes)</label><input type="text" data-f="floor" value="' + esc(c.floor) + '" placeholder="Ten push-ups">' : "") +
        "</section>";
    }).join("");
    return rows;
  }
  function readCommitments(list) {
    return $$("[data-c]").map(function (card) {
      var i = Number(card.getAttribute("data-c")), c = JSON.parse(JSON.stringify(list[i] || {}));
      $$("[data-f]", card).forEach(function (el) {
        var f = el.getAttribute("data-f");
        if (f === "day") return;
        c[f] = el.value;
      });
      if ($("[data-f=day]", card)) c.days = $$("[data-f=day]", card).filter(function (x) { return x.checked; }).map(function (x) { return Number(x.value); });
      return c;
    });
  }
  var draft = null; // commitments being edited on a step screen
  function blankC() { return { id: "", what: "", pillar: "", days: [], measure: "", miss: "", time: "", place: "", trigger: "", breaks: "", floor: "", active: true }; }

  VIEWS.step = function (n) {
    n = Number(n);
    if (!S.steps[n]) return VIEWS.steps();
    if (S.steps[n].status === "locked") return lockedStep(n);
    var rec = S.record.steps[n] || {};
    if (n === 1) {
      var data = rec.data || {};
      var roles = data.roles && data.roles.length ? data.roles : ROLE_DEFAULTS.map(function (r) { return { role: r, expects: "", tuesday: "", bad: "" }; });
      return stepHead(1) + '<section class="card"><p>Who has God called you to be? Work through each role you carry. Skip any that aren\'t yours. Answer from Scripture, not from feelings.</p><p><a href="/downloads/step-1-the-calling.pdf" target="_blank" rel="noopener">Prefer paper? Print the worksheet.</a></p></section>' +
        roles.map(function (r, i) {
          return '<section class="card" data-role="' + i + '"><label>Role</label><input type="text" data-r="role" value="' + esc(r.role) + '">' +
            '<label>What does God expect of me here?</label><textarea data-r="expects">' + esc(r.expects) + "</textarea>" +
            '<label>What does faithful look like on a normal Tuesday?</label><textarea data-r="tuesday">' + esc(r.tuesday) + "</textarea>" +
            '<label>The smallest version on a bad day</label><input type="text" data-r="bad" value="' + esc(r.bad) + '"></section>';
        }).join("") + (ro() ? "" : '<p><button type="button" class="pb small" id="addrole">Add a role</button></p>') +
        '<section class="card hi"><h2>Your sentence</h2><p class="muted">"I am a man who ___, so that ___." Every part should be something someone in your house could notice.</p>' +
        '<textarea id="sentence" placeholder="I am a man who…">' + esc(data.sentence) + "</textarea>" +
        '<details><summary class="dim">See examples</summary>' + (S.examples.sentences || []).map(function (s) { return '<button type="button" class="ex" data-ex="' + esc(s) + '">' + esc(s) + "</button>"; }).join("") + "</details>" +
        '<label>A verse that anchors it (optional)</label><input type="text" id="scripture" value="' + esc(data.scripture) + '" placeholder="Habakkuk 2:2"></section>' + stepButtons(1);
    }
    if (n === 2 || n === 3) {
      draft = draft || JSON.parse(JSON.stringify(S.record.commitments));
      if (n === 2 && !draft.length) draft.push(blankC());
      var intro = n === 2 ? '<section class="card"><p>No more than three commitments a week. Each one is a yes or no with a number, answers to your sentence, and has a miss you decide on now.</p>' +
        (S.record.steps[1] && S.record.steps[1].data && S.record.steps[1].data.sentence ? '<p class="muted">Your sentence: "' + esc(S.record.steps[1].data.sentence) + '"</p>' : "") + "</section>"
        : '<section class="card"><p>Give each commitment an address: a time, a place and a trigger. Name what breaks it. Then write the two-minute version you\'ll still do on your worst day. A floor day counts as kept.</p></section>';
      if (n === 3 && !draft.length) return stepHead(3) + '<section class="card"><p>Add your commitments in <a href="#step-2">Step 2</a> first.</p></section>';
      return stepHead(n) + intro + commitEditor(draft, n) +
        (n === 2 && draft.length < 3 && !ro() ? '<p><button type="button" class="pb small" id="addc">Add a commitment</button></p>' : "") +
        (n === 2 ? '<details class="card"><summary>Starter examples</summary><p class="dim">Tap one to start from it, then make it yours.</p>' + (S.examples.commitments || []).map(function (c, i) { return '<button type="button" class="ex" data-exc="' + i + '"><strong>' + esc(PILLARS[c.pillar] || "") + ":</strong> " + esc(c.what) + "</button>"; }).join("") + "</details>" : "") +
        (n === 3 ? '<section class="card"><h2>Put it on your calendar</h2><p class="muted">Subscribe once and your commitments show up on your phone with a reminder ten minutes before. Changes you make here update it.</p><a class="pb" href="' + esc(S.calendar.replace(/^https:/, "webcal:")) + '">Add to my calendar</a> <button type="button" class="pb small" id="copycal">Copy the link</button></section>' : "") +
        stepButtons(n);
    }
    var d4 = rec.data || {};
    return stepHead(4) + '<section class="card"><p>The Ledger is how you count your week without shame. Tap each commitment every day. On Sunday, look at your number, answer four questions, report to your partner and reset.</p><p><a href="/downloads/the-ledger-weekly-scorecard.pdf" target="_blank" rel="noopener">Prefer paper? Print the Ledger.</a> You can report your number or upload a photo of it on Sunday.</p></section>' +
      '<section class="card"><label>When will you do your Sunday review?</label><input type="text" id="rt" value="' + esc(d4.reviewTime) + '" placeholder="Sunday after dinner">' +
      '<label>Who will you report your number to?</label><input type="text" id="rp" value="' + esc(d4.partner) + '" placeholder="Your partner, your wife, a brother">' +
      '<label>Where will you keep the Ledger?</label><input type="text" id="rw" value="' + esc(d4.where) + '" placeholder="This portal, the fridge, my truck"></section>' + stepButtons(4);
  };
  VIEWS.step.after = function (n) {
    n = Number(n);
    var go = function (submit) {
      var body = { n: n, submit: submit };
      if (n === 1) body.data = { roles: $$("[data-role]").map(function (s) { var o = {}; $$("[data-r]", s).forEach(function (el) { o[el.getAttribute("data-r")] = el.value; }); return o; }).filter(function (r) { return r.role.trim(); }), sentence: $("#sentence").value, scripture: $("#scripture").value };
      if (n === 2 || n === 3) { draft = readCommitments(draft); body.commitments = draft.filter(function (c) { return String(c.what || "").trim(); }); }
      if (n === 4) body.data = { reviewTime: $("#rt").value, partner: $("#rp").value, where: $("#rw").value };
      if (submit && !confirm("Send Step " + n + " to Brian? You can still make changes after.")) return;
      api("step", body).then(function (d) { crisis(d); draft = null; flash(submit ? "Sent to Brian." : "Saved."); return refresh(); }).catch(fail);
    };
    var s = $("#save"); if (s) s.onclick = function () { go(false); };
    var b = $("#submit"); if (b) b.onclick = function () { go(true); };
    var ar = $("#addrole"); if (ar) ar.onclick = function () {
      var div = document.createElement("section"); div.className = "card"; div.setAttribute("data-role", "x");
      div.innerHTML = '<label>Role</label><input type="text" data-r="role"><label>What does God expect of me here?</label><textarea data-r="expects"></textarea><label>What does faithful look like on a normal Tuesday?</label><textarea data-r="tuesday"></textarea><label>The smallest version on a bad day</label><input type="text" data-r="bad">';
      ar.parentNode.parentNode.insertBefore(div, ar.parentNode); $("input", div).focus();
    };
    $$("[data-ex]").forEach(function (x) { x.onclick = function () { $("#sentence").value = x.getAttribute("data-ex"); $("#sentence").focus(); }; });
    var ac = $("#addc"); if (ac) ac.onclick = function () { draft = readCommitments(draft); draft.push(blankC()); rerender(); };
    $$("[data-del]").forEach(function (x) { x.onclick = function () { draft = readCommitments(draft); draft.splice(Number(x.getAttribute("data-del")), 1); rerender(); }; });
    $$("[data-exc]").forEach(function (x) { x.onclick = function () {
      draft = readCommitments(draft).filter(function (c) { return String(c.what || "").trim(); });
      if (draft.length >= 3) { flash("Three at most. Remove one first.", true); return; }
      var e = S.examples.commitments[Number(x.getAttribute("data-exc"))], c = blankC();
      Object.keys(e).forEach(function (k) { c[k] = e[k]; }); draft.push(c); rerender();
    }; });
    $$("[data-breaker]").forEach(function (x) { x.onclick = function () { var inp = $("[data-f=breaks]", x.closest("[data-c]")); inp.value = inp.value ? inp.value + "; " + x.getAttribute("data-breaker") : x.getAttribute("data-breaker"); }; });
    var cc = $("#copycal"); if (cc) cc.onclick = function () { copy(S.calendar); };
    if (ro()) $$("#view input, #view textarea, #view select").forEach(function (el) { el.disabled = true; });
  };
  function copy(t) { (navigator.clipboard ? navigator.clipboard.writeText(t) : Promise.reject()).then(function () { flash("Copied."); }, function () { prompt("Copy this link:", t); }); }

  // Edit commitments any time (after Step 2).
  VIEWS.commitments = function () {
    draft = draft || JSON.parse(JSON.stringify(S.record.commitments));
    if (!draft.length) draft.push(blankC());
    var hist = (S.record.commitHistory || []).slice(0, 5);
    return '<p class="dim"><a href="#ledger">‹ The Ledger</a></p><h1>Your commitments.</h1><p class="muted">Change them any time. Every earlier version is kept, so you and Brian can see what changed.</p>' +
      commitEditor(draft, "all") + (draft.length < 3 && !ro() ? '<p><button type="button" class="pb small" id="addc">Add a commitment</button></p>' : "") +
      (ro() ? "" : '<p><button type="button" class="pb primary" id="savec">Save my commitments</button></p>') +
      (hist.length ? '<details class="card"><summary>Earlier versions</summary>' + hist.map(function (h) { return '<p class="dim">' + when(h.at) + (h.by === "brian" ? " (Brian)" : "") + "</p><ul>" + h.list.map(function (c) { return "<li>" + esc(c.what) + "</li>"; }).join("") + "</ul>"; }).join("") + "</details>" : "");
  };
  VIEWS.commitments.after = function () {
    var ac = $("#addc"); if (ac) ac.onclick = function () { draft = readCommitments(draft); draft.push(blankC()); rerender(); };
    $$("[data-del]").forEach(function (x) { x.onclick = function () { draft = readCommitments(draft); draft.splice(Number(x.getAttribute("data-del")), 1); rerender(); }; });
    $$("[data-breaker]").forEach(function (x) { x.onclick = function () { var inp = $("[data-f=breaks]", x.closest("[data-c]")); inp.value = inp.value ? inp.value + "; " + x.getAttribute("data-breaker") : x.getAttribute("data-breaker"); }; });
    var sv = $("#savec"); if (sv) sv.onclick = function () {
      draft = readCommitments(draft);
      api("commitments", { list: draft.filter(function (c) { return String(c.what || "").trim(); }) }).then(function () { draft = null; flash("Saved."); location.hash = "#ledger"; return refresh(); }).catch(fail);
    };
    if (ro()) $$("#view input, #view textarea, #view select").forEach(function (el) { el.disabled = true; });
  };

  // ---------- The Ledger ----------

  VIEWS.ledger = function () {
    var out = ["<h1>The Ledger.</h1>"];
    if (!S.scorecard) return out.join("") + '<section class="card"><p>Your scorecard starts once you have commitments. ' + (S.steps[2].status === "locked" ? "That's Step 2." : '<a href="#step-2">Write them in Step 2.</a>') + "</p></section>";
    out.push('<section class="card"><div class="row between"><div><div class="big">' + S.score.k + ' <span class="muted" style="font-size:22px">of ' + S.score.t + '</span></div><p class="dim">This week so far' + (S.score.floor ? ", " + S.score.floor + " on the floor" : "") + "</p></div>" +
      '<div style="text-align:right"><p class="dim">Weeks reported</p><div class="big" style="font-size:32px">' + S.streak + "</div></div></div>" +
      (S.isSunday ? (S.review ? '<p class="muted">Sunday review done: ' + S.review.k + " of " + S.review.t + ". <a href=\"#review\">Edit</a></p>" : '<a class="pb primary block" href="#review">Do your Sunday review</a>') : '<p class="dim">Your Sunday review opens on Sunday. Late? <a href="#review">Review last week</a>.</p>') + "</section>");
    // This week grid
    var days = [];
    for (var i = 6; i >= 0; i--) days.push(addDaysLocal(S.thisWeek, -i));
    var marks = S.record.marks || {};
    var sym = { k: "✓", f: "↓", m: "✕" };
    out.push('<section class="card"><h2>This week</h2><table class="grid"><tr><th></th>' + days.map(function (d) { return "<th>" + DOW[new Date(d + "T12:00:00Z").getUTCDay()] + "</th>"; }).join("") + "</tr>" +
      S.record.commitments.filter(function (c) { return c.active !== false; }).map(function (c) {
        return "<tr><td>" + esc(c.what.length > 26 ? c.what.slice(0, 25) + "…" : c.what) + "</td>" + days.map(function (d) {
          var on = c.days.length ? c.days.indexOf(new Date(d + "T12:00:00Z").getUTCDay()) >= 0 : true;
          var v = (marks[d] || {})[c.id];
          return "<td>" + (on ? (v ? sym[v] : d <= S.today ? '<span class="dim">·</span>' : "") : '<span class="dim">–</span>') + "</td>";
        }).join("") + "</tr>";
      }).join("") + '</table><p class="dim">✓ kept · ↓ floor · ✕ missed · – not scheduled. Mark days on <a href="#today">Today</a>.</p></section>');
    // History
    var max = 1;
    out.push('<section class="card"><h2>Your last eight weeks</h2><div class="bars">' + S.weeks.map(function (w) {
      var pct = w.t ? Math.round((100 * w.k) / w.t) : 0;
      return "<div>" + (w.t ? "<small>" + w.k + "/" + w.t + "</small>" : "") + '<i class="' + (w.t ? "" : "none") + '" style="height:' + (w.t ? Math.max(4, pct) : 3) + '%"></i><small>' + nice(w.week).replace(/ /, "&nbsp;") + "</small></div>";
    }).join("") + "</div>" + (S.group ? '<p class="dim">The cohort averaged ' + S.group.pct + "% last week. No names, just the number.</p>" : "") + "</section>");
    out.push('<section class="card"><div class="row"><a class="pb" href="#commitments">Edit my commitments</a>' + (S.hardWeek || ro() ? "" : '<button type="button" class="pb" id="hard2">I\'m in a hard week</button>') + (S.hardWeek && !ro() ? '<button type="button" class="pb" id="hardoff">End my hard week</button>' : "") + "</div></section>");
    return out.join("");
  };
  VIEWS.ledger.after = function () {
    var h = $("#hard2"); if (h) h.onclick = function () { var note = prompt("Your commitments will switch to their floor versions until Sunday, and Brian will know. Anything you want him to know? (optional)", ""); if (note === null) return; api("hard", { on: true, note: note }).then(function (d) { crisis(d); flash("Floor week. Zero is the only real miss."); return refresh(); }).catch(fail); };
    var o = $("#hardoff"); if (o) o.onclick = function () { api("hard", { on: false }).then(refresh).catch(fail); };
  };

  VIEWS.review = function () {
    var r = S.review || {};
    var auto = S.reviewWeek === S.thisWeek ? S.score : S.lastScore;
    return '<p class="dim"><a href="#ledger">‹ The Ledger</a></p><h1>Sunday review.</h1><p class="muted">Week ending ' + nice(S.reviewWeek, true) + ". Count it without shame. It's information, not a verdict.</p>" +
      '<section class="card"><h2>Your number</h2>' + (auto.t ? '<p>From your taps: <strong>' + auto.k + " of " + auto.t + "</strong></p>" : "") +
      '<label class="check"><input type="checkbox" id="paper"' + (r.paper || !auto.t ? " checked" : "") + "> I kept it on paper this week, so I'll type my number</label>" +
      '<div class="row" id="paperbox"' + (r.paper || !auto.t ? "" : " hidden") + '><div style="flex:1"><label>Kept</label><input type="number" id="k" min="0" value="' + (r.k != null ? r.k : auto.k) + '"></div><div style="flex:1"><label>Out of</label><input type="number" id="t" min="1" value="' + (r.t != null ? r.t : auto.t || "") + '"></div></div>' +
      '<label>Or upload a photo of your paper Ledger</label><input type="file" id="photo" accept="image/*" capture="environment"><button type="button" class="pb small" id="up" style="margin-top:8px">Upload photo</button>' +
      "</section>" +
      '<section class="card"><label>1. The miss that keeps coming back</label><textarea id="q1">' + esc(r.miss) + "</textarea>" +
      '<label>2. One change for Monday</label><textarea id="q2">' + esc(r.change) + "</textarea>" +
      '<label>3. A grace line to yourself</label><textarea id="q3" placeholder="What would you say to a brother who had your week?">' + esc(r.grace) + "</textarea>" +
      '<label>4. Who did you report to?</label><input type="text" id="q4" value="' + esc(r.reported) + '" placeholder="' + esc(S.partner ? S.partner.name : "Your partner") + '"></section>' +
      (ro() ? "" : '<button type="button" class="pb primary block" id="sendrev">Save my review</button>');
  };
  VIEWS.review.after = function () {
    var p = $("#paper"); p.onchange = function () { $("#paperbox").hidden = !p.checked; };
    var up = $("#up"); if (up) up.onclick = function () {
      var f = $("#photo").files[0]; if (!f) { flash("Choose a photo first.", true); return; }
      var fd = new FormData(); fd.append("photo", f);
      up.disabled = true; up.textContent = "Uploading…";
      api("upload", null, { form: fd }).then(function () { flash("Photo sent to Brian."); up.textContent = "Uploaded"; }).catch(function (e) { fail(e); up.disabled = false; up.textContent = "Upload photo"; });
    };
    var b = $("#sendrev"); if (b) b.onclick = function () {
      var body = { miss: $("#q1").value, change: $("#q2").value, grace: $("#q3").value, reported: $("#q4").value, paper: p.checked };
      if (p.checked) { body.k = Number($("#k").value); body.t = Number($("#t").value); }
      api("review", body).then(function (d) { crisis(d); flash("Review saved. Reset. New week Monday."); location.hash = "#ledger"; return refresh(); }).catch(fail);
    };
    if (ro()) $$("#view input, #view textarea").forEach(function (el) { el.disabled = true; });
  };

  // ---------- Lessons ----------

  VIEWS.lessons = function () {
    return "<h1>Lessons.</h1>" + '<section class="card steplist">' + S.lessons.map(function (l) {
      var done = l.mine && l.mine.done;
      return '<a href="' + (l.open ? "#lesson/" + l.id : "#lessons") + '"' + (l.open ? "" : ' aria-disabled="true"') + "><span><strong>Week " + l.week + ":</strong> " + esc(l.title) + (l.open ? "" : '<br><span class="dim">Opens ' + (l.date ? nice(l.date) : "later") + "</span>") + (l.missed && l.open ? '<br><span class="dim">Missed this one? There\'s a catch-up inside.</span>' : "") + "</span>" + (done ? '<span class="pill ok">Done</span>' : l.open ? '<span class="pill">Open</span>' : '<span class="pill">Locked</span>') + "</a>";
    }).join("") + "</section>" +
      '<section class="card"><h2>Printables</h2>' + S.materials.map(function (m) { return '<p><a href="' + esc(m.url) + '" target="_blank" rel="noopener">' + esc(m.title) + "</a></p>"; }).join("") + "</section>";
  };
  VIEWS.lesson = function (id) {
    var l = S.lessons.filter(function (x) { return x.id === id; })[0];
    if (!l || !l.open) return VIEWS.lessons();
    var mine = l.mine || {};
    return '<p class="dim"><a href="#lessons">‹ Lessons</a></p><p class="dim">Week ' + l.week + " · Step " + l.step + " · " + esc(l.scripture) + "</p><h1>" + esc(l.title) + "</h1>" +
      (l.missed ? '<section class="card hi"><h2>You missed this session</h2>' + (l.catchup ? "<p>" + esc(l.catchup) + "</p>" : "<p>Read the lesson and do the action. Bring questions Thursday.</p>") + "</section>" : "") +
      yt(l.video) + (l.recording ? "<h3>Session teaching</h3>" + yt(l.recording) : "") +
      '<article class="lesson">' + md(l.body) + "</article>" +
      '<section class="card hi"><h2>This week\'s action</h2><label class="check"><input type="checkbox" id="done"' + (mine.done ? " checked" : "") + (ro() ? " disabled" : "") + "> <span>" + esc(l.action) + "</span></label>" +
      "<label>" + esc(l.reflection) + '</label><textarea id="refl"' + (ro() ? " disabled" : "") + ">" + esc(mine.text) + "</textarea>" +
      (ro() ? "" : '<p><button type="button" class="pb primary" id="savel">Save</button></p>') + "</section>" +
      (l.pdf ? '<p><a href="' + esc(l.pdf) + '" target="_blank" rel="noopener">Download this lesson (PDF)</a></p>' : "");
  };
  VIEWS.lesson.after = function (id) {
    var b = $("#savel"); if (b) b.onclick = function () { api("reflect", { id: id, text: $("#refl").value, done: $("#done").checked }).then(function (d) { crisis(d); flash("Saved."); return refresh(); }).catch(fail); };
  };

  // ---------- More ----------

  VIEWS.more = function () {
    var unread = (S.messages || []).filter(function (m) { return m.from === "brian"; }).length;
    return "<h1>More.</h1>" + '<section class="card steplist">' +
      '<a href="#messages"><span><strong>Messages and prayer</strong><br><span class="dim">Private, between you and Brian</span></span>›</a>' +
      ((S.me.role === "cohort" || S.me.role === "admin" || S.me.role === "club") ? '<a href="#partner"><span><strong>Your partner</strong><br><span class="dim">' + (S.partner ? esc(S.partner.name) : "Brian will pair you") + "</span></span>›</a>" : "") +
      '<a href="#settings"><span><strong>Settings</strong><br><span class="dim">Reminders, large text, sharing, your data</span></span>›</a>' +
      "</section>" + (unread ? "" : "");
  };
  VIEWS.partner = function () {
    if (!S.partner) return '<p class="dim"><a href="#more">‹ More</a></p><h1>Your partner.</h1><section class="card"><p>Brian pairs each man with a partner. You\'ll see each other\'s weekly number and Sunday answers here. Nothing else.</p></section>';
    var p = S.partner;
    return '<p class="dim"><a href="#more">‹ More</a></p><h1>' + esc(p.name) + ".</h1><p class=\"muted\">Your partner. You see each other's weekly number and Sunday answers.</p>" +
      (p.phone ? '<p><a class="pb" href="sms:' + esc(p.phone) + '">Text ' + esc(p.name.split(" ")[0]) + "</a></p>" : "") +
      p.weeks.slice().reverse().map(function (w) {
        return '<section class="card"><div class="row between"><h2>Week ending ' + nice(w.week) + "</h2><strong>" + (w.t ? w.k + " of " + w.t : '<span class="dim">Not reported</span>') + "</strong></div>" +
          (w.review ? (w.review.miss ? "<p><span class=\"dim\">Miss that keeps coming back:</span> " + esc(w.review.miss) + "</p>" : "") + (w.review.change ? "<p><span class=\"dim\">Change for Monday:</span> " + esc(w.review.change) + "</p>" : "") + (w.review.grace ? "<p><span class=\"dim\">Grace:</span> " + esc(w.review.grace) + "</p>" : "") : "") + "</section>";
      }).join("");
  };
  VIEWS.messages = function () {
    var ms = S.messages || [];
    return '<p class="dim"><a href="#more">‹ More</a></p><h1>Messages.</h1><p class="muted">Private, between you and Brian. Nobody else in the cohort sees these.</p>' +
      '<section class="card">' + (ms.length ? ms.map(function (m) { return '<div class="msg ' + (m.from === "brian" ? "brian" : "him") + '">' + (m.type === "prayer" ? "<strong>Prayer request</strong>\n" : "") + esc(m.text) + "<small>" + (m.from === "brian" ? "Brian · " : "") + when(m.at) + "</small></div>"; }).join("") : '<p class="dim">No messages yet.</p>') + "</section>" +
      (S.coach ? "" : '<section class="card"><label for="mt">Write to Brian</label><textarea id="mt"></textarea><div class="row" style="margin-top:10px"><button type="button" class="pb primary" id="sendm">Send message</button><button type="button" class="pb" id="sendp">Send as a prayer request</button></div></section>') +
      '<p class="dim">If you are in crisis or thinking about ending your life, don\'t wait for a reply: call or text <a href="tel:988">988</a>, or call 911.</p>';
  };
  VIEWS.messages.after = function () {
    var send = function (type) { var t = $("#mt").value.trim(); if (!t) { flash("Write something first.", true); return; } api("message", { type: type, text: t }).then(function (d) { crisis(d); flash(type === "prayer" ? "Brian is praying with you." : "Sent to Brian."); return refresh(); }).catch(fail); };
    var a = $("#sendm"); if (a) a.onclick = function () { send("message"); };
    var b = $("#sendp"); if (b) b.onclick = function () { send("prayer"); };
  };
  VIEWS.settings = function () {
    var r = S.record.reminders || {};
    var hours = []; for (var h = 6; h <= 21; h++) hours.push('<option value="' + h + '"' + ((r.hour || 20) === h ? " selected" : "") + ">" + ((h % 12) || 12) + (h < 12 ? " AM" : " PM") + "</option>");
    var ios = /iphone|ipad/i.test(navigator.userAgent);
    return '<p class="dim"><a href="#more">‹ More</a></p><h1>Settings.</h1>' +
      '<section class="card"><label>Your name</label><input type="text" id="nm" value="' + esc(S.me.name) + '"><label class="check"><input type="checkbox" id="lg"' + (S.me.large ? " checked" : "") + "> Large text</label></section>" +
      '<section class="card"><h2>Daily reminder</h2><label class="check"><input type="checkbox" id="ron"' + (r.on ? " checked" : "") + '> Remind me to mark my day</label><label>At</label><select id="rh">' + hours.join("") + '</select><p class="dim">By email, Central time, and only on days something is still unmarked.</p></section>' +
      (S.coach ? "" : '<p><button type="button" class="pb primary" id="saves">Save settings</button></p>') +
      '<section class="card"><h2>Put the portal on your home screen</h2><p class="muted">' + (ios ? "In Safari, tap Share, then Add to Home Screen." : "In Chrome, tap the menu (⋮), then Add to Home screen or Install app.") + "</p></section>" +
      '<section class="card"><h2>Calendar</h2><p class="muted">Your commitments, with a reminder ten minutes before.</p><a class="pb" href="' + esc(S.calendar.replace(/^https:/, "webcal:")) + '">Add to my calendar</a> <button type="button" class="pb small" id="copycal">Copy the link</button></section>' +
      '<section class="card"><h2>Share a read-only link</h2><p class="muted">Off unless you turn it on. It shows your sentence, your commitments and your weekly numbers. Never your messages or answers.</p>' +
      '<label class="check"><input type="checkbox" id="sh"' + (S.share ? " checked" : "") + (ro() ? " disabled" : "") + "> Sharing is on</label>" + (S.share ? '<p><button type="button" class="pb small" id="copysh">Copy my link</button></p>' : "") + "</section>" +
      '<section class="card"><h2>Your data</h2><p><a class="pb small" href="/api/portal/export' + Q + '">Download my data</a></p>' + (S.coach ? "" : '<p><button type="button" class="pb small" id="del">Ask Brian to delete my data</button></p>') + "</section>" +
      (S.coach ? "" : '<p><button type="button" class="pb" id="out">Sign out</button></p>');
  };
  VIEWS.settings.after = function () {
    var s = $("#saves"); if (s) s.onclick = function () {
      api("profile", { name: $("#nm").value, large: $("#lg").checked, reminders: { on: $("#ron").checked, hour: Number($("#rh").value), channel: "email" } }).then(function () { flash("Saved."); return refresh(); }).catch(fail);
    };
    var cc = $("#copycal"); if (cc) cc.onclick = function () { copy(S.calendar); };
    var sh = $("#sh"); if (sh) sh.onchange = function () { api("share", { on: sh.checked }).then(function (d) { flash(d.on ? "Sharing is on." : "Sharing is off. The old link no longer works."); return refresh(); }).catch(fail); };
    var cs = $("#copysh"); if (cs) cs.onclick = function () { copy(S.share); };
    var del = $("#del"); if (del) del.onclick = function () { var why = prompt("Ask Brian to delete your portal data? Anything you want him to know? (optional)", ""); if (why === null) return; api("delete-request", { reason: why }).then(function (d) { alert(d.message); }).catch(fail); };
    var out = $("#out"); if (out) out.onclick = function () { api("logout", {}).then(function () { location.href = "/portal/login/"; }).catch(function () { location.href = "/portal/login/"; }); };
    if (S.coach) $$("#view input, #view select").forEach(function (el) { el.disabled = true; });
  };

  window.addEventListener("hashchange", function () { draft = null; route(); });
  load().then(route).catch(function (e) { if (e.message !== "signed out") $("#view").innerHTML = '<p class="muted">' + esc(e.message) + "</p>"; });
})();
