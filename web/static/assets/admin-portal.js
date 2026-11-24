/* Be The Man dashboard, part 3: the men's portal. Men (list, a page per man, call sheet,
   insights, inbox, backup), Library (lessons and materials) and Sessions (recordings, catch-up notes). */
(function () {
  "use strict";
  var B = window.BTM; if (!B) return;
  var $ = B.$, $$ = B.$$, esc = B.esc, when = B.when, api = B.api, flash = B.flash, dialog = B.dialog, view = B.view, VIEWS = B.VIEWS;
  var nice = function (d, long) { return d ? new Date(d + "T12:00:00Z").toLocaleDateString("en-US", long ? { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" } : { month: "short", day: "numeric", timeZone: "UTC" }) : ""; };
  var ROLES = { cohort: "Founding Cohort", club: "Club", step1: "Step 1 only", admin: "You" };
  var DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  function stTag(s) { var m = { approved: "ok", submitted: "warn", revisit: "bad" }; return "<span class='tag " + (m[s.status] || "") + "'>" + ({ approved: "Approved", submitted: "To approve", revisit: "Revisit", open: "Open", locked: "Locked" }[s.status] || s.status) + "</span>"; }
  function curStep(steps) { var n = [1, 2, 3, 4].filter(function (k) { return steps[k].status !== "approved"; })[0]; return n ? "Step " + n + " " + stTag(steps[n]) : "<span class='tag ok'>All four approved</span>"; }
  function ago(t) { if (!t) return "Never"; var d = Math.floor((Date.now() - t) / 86400000); return d <= 0 ? "Today" : d === 1 ? "Yesterday" : d + " days ago"; }
  function bars(weeks) {
    return "<div class='man-bars'>" + weeks.map(function (w) { var p = w.t ? Math.round((100 * w.k) / w.t) : 0; return "<div>" + (w.t ? "<small>" + w.k + "/" + w.t + "</small>" : "") + "<i class='" + (w.t ? "" : "none") + "' style='height:" + (w.t ? Math.max(3, p) : 2) + "%'></i><small>" + nice(w.week) + "</small></div>"; }).join("") + "</div>";
  }

  window.addEventListener("hashchange", function () { var h = location.hash.slice(1); if (h) B.show(h); });
  B.after && B.after("overview", function () {});
  // Unread portal messages dot.
  api("overview").then(function (d) { var u = document.getElementById("unreadp"); if (u && d.ok) u.hidden = !d.unreadPortal; });

  // ---------- Men ----------
  VIEWS.men = function () {
    api("men").then(function (d) {
      if (!d.ok) return;
      var men = d.men.filter(function (m) { return m.role !== "admin"; });
      var waiting = men.filter(function (m) { return [1, 2, 3, 4].some(function (n) { return m.steps[n].status === "submitted"; }); }).length;
      var flagged = men.filter(function (m) { return m.flags.length; }).length;
      view.innerHTML = "<div class='adm-row'><h2>Men</h2><span class='muted'>" + men.length + " portals</span></div>" +
        "<div class='adm-row'><button class='btn btn-primary btn-sm' id='madd'>Add a man</button><button class='btn btn-ghost btn-sm' id='msheet'>Call sheet</button><button class='btn btn-ghost btn-sm' id='mins'>Cohort insights</button><button class='btn btn-ghost btn-sm' id='minbox'>Messages</button><a class='btn btn-ghost btn-sm' href='/api/admin/backup'>Download backup</a><a class='btn btn-ghost btn-sm' href='/portal/'>My system</a></div>" +
        "<div class='adm-stats'><div class='adm-stat'><b>" + waiting + "</b><span>Steps waiting for your approval</span></div><div class='adm-stat'><b>" + flagged + "</b><span>Men with a flag</span></div><div class='adm-stat'><b>" + men.filter(function (m) { return m.unread; }).length + "</b><span>Unread messages</span></div></div>" +
        "<div class='adm-table'>" + (men.length ? "<table><tr><th>Man</th><th>Where he is</th><th>Last week</th><th>This week</th><th>Last in</th><th>Flags</th></tr>" + men.map(function (m, i) {
          return "<tr class='click' data-i='" + i + "'><td><b>" + esc(m.name || m.email) + "</b>" + (m.unread ? " <span class='tag warn'>" + m.unread + " new</span>" : "") + "<br><span class='muted small'>" + esc(ROLES[m.role] || m.role) + (m.access === "readonly" ? " · read-only" : "") + (m.pace !== "cohort" ? " · " + esc(m.pace) + " pace" : "") + (m.graduated ? " · graduate" : "") + "</span></td>" +
            "<td>" + curStep(m.steps) + "</td><td>" + (m.last && m.last.t ? m.last.k + "/" + m.last.t : "–") + "</td><td>" + (m.now && m.now.t ? m.now.k + "/" + m.now.t : "–") + "</td><td>" + ago(m.lastActive) + "</td>" +
            "<td>" + m.flags.map(function (f) { return "<span class='tag " + (/Safety|delete/.test(f) ? "bad" : "warn") + "'>" + esc(f) + "</span>"; }).join("") + "</td></tr>";
        }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No portals yet. A man gets one when he buys the Founding Cohort, joins the Club, or signs up for Step 1. You can also add one.</p>") + "</div>" +
        "<p class='muted small'>Each man signs in at bethemansystem.com/portal with an emailed link or a text code. Click a man for his page.</p>";
      $$("tr[data-i]", view).forEach(function (row) { row.onclick = function () { location.hash = "#man/" + encodeURIComponent(men[+row.dataset.i].email); }; });
      $("#madd").onclick = function () {
        var b = dialog("<div class='adm-card' style='margin:0'><h2>Add a man</h2><label>Email<input id='ae' type='email'></label><label>Name<input id='an'></label><label>Portal<select id='ar'><option value='cohort'>Founding Cohort</option><option value='club'>Club</option><option value='step1'>Step 1 only</option></select></label><label class='inline'><input type='checkbox' id='ai' checked> Email him a sign-in link now</label><div class='adm-row'><button class='btn btn-primary btn-sm' id='ago'>Add</button><button class='btn btn-ghost btn-sm' data-close>Cancel</button></div></div>");
        $("#ago", b).onclick = function () { api("man-create", { email: $("#ae", b).value, name: $("#an", b).value, role: $("#ar", b).value, invite: $("#ai", b).checked }).then(function (r) { if (r.ok) { $("#dlg").close(); flash(r.created ? "Portal created." : "He already had a portal; updated."); VIEWS.men(); } }); };
      };
      $("#msheet").onclick = function () { callSheet(); };
      $("#mins").onclick = function () { cohortInsights(); };
      $("#minbox").onclick = function () { portalInbox(); };
    });
  };

  function callSheet(date) {
    api("callsheet" + (date ? "?date=" + date : "")).then(function (d) {
      if (!d.ok) return;
      view.innerHTML = "<div class='adm-row'><h2>Call sheet: " + nice(d.date, true) + "</h2><button class='btn btn-ghost btn-sm' onclick='print()'>Print</button><button class='btn btn-ghost btn-sm' id='back'>Back to Men</button></div>" +
        "<p class='muted'>What each man asked for help with, his last number and anything to watch. Men who wrote a note come first.</p>" +
        d.rows.map(function (r) {
          return "<div class='adm-card'><div class='adm-row'><h2><a href='#man/" + encodeURIComponent(r.email) + "'>" + esc(r.name) + "</a></h2>" + (r.last && r.last.t ? "<b>" + r.last.k + "/" + r.last.t + "</b>" : "<span class='muted'>No number</span>") + (r.here ? " <span class='tag ok'>Here</span>" : "") + (r.hard ? " <span class='tag warn'>Hard week</span>" : "") + "</div>" +
            (r.prep ? "<p><b>Wants help with:</b> " + esc(r.prep.text) + "</p>" : "<p class='muted'>No note.</p>") +
            (r.review && r.review.miss ? "<p class='small'><b>Miss that keeps coming back:</b> " + esc(r.review.miss) + "</p>" : "") +
            (r.mostMissed ? "<p class='small'><b>Most missed (4 weeks):</b> " + esc(r.mostMissed.what) + " (" + r.mostMissed.count + ")</p>" : "") +
            (r.flags.length ? "<p>" + r.flags.map(function (f) { return "<span class='tag warn'>" + esc(f) + "</span>"; }).join("") + "</p>" : "") + "</div>";
        }).join("") + (d.rows.length ? "" : "<p class='muted'>No Founding Cohort portals yet.</p>");
      $("#back").onclick = function () { VIEWS.men(); };
    });
  }

  function cohortInsights() {
    api("portal-insights").then(function (d) {
      if (!d.ok) return;
      var ws = Object.keys(d.weeks).sort().slice(-8);
      view.innerHTML = "<div class='adm-row'><h2>Cohort insights</h2><button class='btn btn-ghost btn-sm' id='back'>Back to Men</button></div>" +
        "<div class='adm-stats'><div class='adm-stat'><b>" + d.men + "</b><span>Founding Cohort portals</span></div><div class='adm-stat'><b>" + d.active7 + "</b><span>Signed in this week</span></div><div class='adm-stat'><b>" + d.flagged + "</b><span>With a flag</span></div></div>" +
        "<div class='adm-card'><h2>Group kept, by week</h2>" + bars(ws.map(function (w) { var x = d.weeks[w]; return { week: w, k: Math.round((100 * x.k) / x.t), t: 100 }; })).replace(/(\d+)\/100/g, "$1%") +
        "<p class='muted small'>" + ws.map(function (w) { return nice(w) + ": " + d.weeks[w].reviewed + " of " + d.weeks[w].men + " reviewed"; }).join(" · ") + "</p></div>" +
        "<div class='man-grid'><div class='adm-card'><h2>Steps</h2><div class='adm-table'><table><tr><th>Step</th><th>Approved</th><th>To approve</th><th>Revisit</th><th>Open</th><th>Locked</th></tr>" + [1, 2, 3, 4].map(function (n) { var s = d.steps[n]; return "<tr><td>" + n + "</td><td>" + (s.approved || 0) + "</td><td>" + (s.submitted || 0) + "</td><td>" + (s.revisit || 0) + "</td><td>" + (s.open || 0) + "</td><td>" + (s.locked || 0) + "</td></tr>"; }).join("") + "</table></div></div>" +
        "<div class='adm-card'><h2>Attendance</h2>" + d.sessions.map(function (s) { return "<p class='small'>" + nice(s, true) + ": <b>" + (d.attendance[s] || 0) + "</b> of " + d.men + "</p>"; }).join("") + "</div></div>" +
        "<div class='adm-card'><h2>What the men keep missing</h2><p class='muted small'>From their Sunday reviews, newest first. Look for themes to teach on.</p>" + (d.misses.length ? d.misses.map(function (m) { return "<p class='small'>" + (m.week ? "<span class='muted'>" + nice(m.week) + "</span> " : "") + esc(m.text) + "</p>"; }).join("") : "<p class='muted'>Nothing yet.</p>") + "</div>";
      $("#back").onclick = function () { VIEWS.men(); };
    });
  }

  function portalInbox() {
    api("portal-inbox").then(function (d) {
      if (!d.ok) return;
      view.innerHTML = "<div class='adm-row'><h2>Portal messages</h2><button class='btn btn-ghost btn-sm' id='back'>Back to Men</button></div>" +
        "<div class='adm-table'>" + (d.inbox.length ? "<table><tr><th>Man</th><th>Last message</th><th>When</th></tr>" + d.inbox.map(function (m, i) {
          return "<tr class='click' data-i='" + i + "'><td><b>" + esc(m.name || m.email) + "</b></td><td>" + (m.type === "prayer" ? "<span class='tag'>Prayer</span> " : "") + (m.from === "brian" ? "<span class='muted'>You:</span> " : "") + esc(m.preview) + "</td><td>" + when(m.last) + "</td></tr>";
        }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No messages yet.</p>") + "</div>";
      $$("tr[data-i]", view).forEach(function (row) { row.onclick = function () { location.hash = "#man/" + encodeURIComponent(d.inbox[+row.dataset.i].email); }; });
      $("#back").onclick = function () { VIEWS.men(); };
    });
  }

  // ---------- one man ----------
  VIEWS.man = function (email) {
    if (!email) return VIEWS.men();
    api("man?email=" + encodeURIComponent(email)).then(function (d) {
      if (!d.ok) return;
      var pd = d.record, c = d.contact, ins = d.insights, name = c.name || c.email;
      var up = function (op, extra) { return api("man-update", Object.assign({ email: email, op: op }, extra || {})).then(function (r) { if (r.ok) { flash(r.message || "Saved."); VIEWS.man(email); } return r; }); };
      var stepCard = function (n) {
        var s = d.steps[n], rec = pd.steps[n] || {};
        var body = "";
        if (n === 1 && rec.data) {
          body = (rec.data.sentence ? "<p><b>Sentence:</b> \"" + esc(rec.data.sentence) + "\"</p>" : "") + (rec.data.scripture ? "<p class='small'>Verse: " + esc(rec.data.scripture) + "</p>" : "") +
            "<details><summary class='small'>His roles</summary>" + (rec.data.roles || []).map(function (r) { return "<p class='small'><b>" + esc(r.role) + "</b><br>Expects: " + esc(r.expects) + "<br>Tuesday: " + esc(r.tuesday) + "<br>Bad day: " + esc(r.bad) + "</p>"; }).join("") + "</details>";
        }
        if (n === 2 || n === 3) body = pd.commitments.map(function (x) {
          return "<p class='small'><b>" + esc(x.what) + "</b>" + (x.pillar ? " <span class='tag'>" + esc(x.pillar) + "</span>" : "") + "<br>" + (x.days.length ? x.days.map(function (k) { return DOW[k]; }).join(", ") : "Every day") +
            (n === 2 ? (x.measure ? "<br>Kept means: " + esc(x.measure) : "") + (x.miss ? "<br>Miss means: " + esc(x.miss) : "") :
              "<br>" + esc(x.time || "no time") + (x.place ? " · " + esc(x.place) : "") + (x.trigger ? "<br>Trigger: " + esc(x.trigger) : "") + (x.breaks ? "<br>Breaks it: " + esc(x.breaks) : "") + (x.floor ? "<br>Floor: " + esc(x.floor) : "")) + "</p>";
        }).join("") || "<p class='muted small'>No commitments yet.</p>";
        if (n === 4 && rec.data) body = "<p class='small'>Review: " + esc(rec.data.reviewTime) + "<br>Reports to: " + esc(rec.data.partner) + "<br>Keeps it: " + esc(rec.data.where) + "</p>";
        return "<div class='adm-card sub'><div class='adm-row'><h2>Step " + n + ": " + esc(d.stepNames[n]) + "</h2>" + stTag(s) + "</div>" + body +
          (rec.note ? "<p class='small'><b>Your revisit note:</b> " + esc(rec.note) + "</p>" : "") + (s.opens && s.status === "locked" ? "<p class='muted small'>Opens " + nice(s.opens) + "</p>" : "") +
          "<div class='adm-row'>" + (s.status !== "approved" ? "<button class='btn btn-primary btn-sm' data-ap='" + n + "'>Approve</button>" : "") + (s.status === "submitted" || s.status === "approved" ? "<button class='btn btn-ghost btn-sm' data-rv='" + n + "'>Revisit</button>" : "") +
          (s.status === "locked" ? "<button class='btn btn-ghost btn-sm' data-open='" + n + "'>Open it now</button>" : "") + "</div></div>";
      };
      var revs = Object.keys(pd.reviews).sort().reverse().slice(0, 6);
      var refl = d.lessons.filter(function (l) { return pd.reflections[l.id]; });
      view.innerHTML =
        "<p class='small'><a href='#men'>‹ Men</a></p><div class='adm-row'><h2>" + esc(name) + "</h2><span class='muted'>" + esc(c.email) + (c.phone ? " · " + esc(c.phone) : "") + "</span>" +
        "<a class='btn btn-primary btn-sm' href='/portal/?as=" + encodeURIComponent(email) + "'>Coach view</a><button class='btn btn-ghost btn-sm' id='inv'>Send sign-in link</button></div>" +
        (ins.flags.length || (pd.flags && pd.flags.safety) ? "<div class='adm-card' style='border-color:#7a2a1a'>" + (pd.flags && pd.flags.safety ? "<p><span class='tag bad'>Safety alert " + when(pd.flags.safety) + "</span> He wrote something that may mean self-harm. Reach him today. If he's in danger, call 911.</p>" : "") + ins.flags.map(function (f) { return "<span class='tag warn'>" + esc(f) + "</span>"; }).join("") + (pd.deleteRequested ? "<p><span class='tag bad'>Asked to delete his data " + when(pd.deleteRequested) + "</span></p>" : "") + "</div>" : "") +
        "<div class='adm-stats'><div class='adm-stat'><b>" + ins.streak + "</b><span>Weeks reported in a row</span></div><div class='adm-stat'><b>" + (ins.mostMissed ? esc(ins.mostMissed.count) : "–") + "</b><span>" + (ins.mostMissed ? "Misses: " + esc(ins.mostMissed.what) : "Most-missed commitment") + "</span></div>" +
        "<div class='adm-stat'><b>" + ins.attendance.filter(function (a) { return a.here; }).length + " of " + ins.attendance.filter(function (a) { return a.past; }).length + "</b><span>Sessions attended</span></div><div class='adm-stat'><b>" + ago(pd.lastActive) + "</b><span>Last signed in</span></div></div>" +
        "<div class='adm-card'><h2>Weekly numbers</h2>" + bars(ins.weeks) + "</div>" +
        "<div class='man-grid'><div>" + [1, 2, 3, 4].map(stepCard).join("") + "</div><div>" +
        // Messages
        "<div class='adm-card'><h2>Messages</h2><div style='max-height:340px;overflow:auto'>" + (d.messages.length ? d.messages.map(function (m) { return "<div class='man-msg " + m.from + "'>" + (m.type === "prayer" ? "<b>Prayer request</b>\n" : "") + esc(m.text) + "<small>" + when(m.at) + "</small></div>"; }).join("") : "<p class='muted small'>No messages.</p>") + "</div>" +
        "<textarea id='rmsg' placeholder='Reply to " + esc(name.split(" ")[0]) + "'></textarea><div class='adm-row'><button class='btn btn-primary btn-sm' id='rsend'>Send</button>" + (pd.unreadBrian ? "<button class='btn btn-ghost btn-sm' id='rread'>Mark read</button>" : "") + "</div></div>" +
        // Next steps
        "<div class='adm-card'><h2>Next steps for him</h2>" + (pd.next.length ? pd.next.map(function (x) { return "<p class='small'>" + (x.done ? "✓ " : "○ ") + esc(x.text) + (x.due ? " <span class='muted'>by " + nice(x.due) + "</span>" : "") + " <button class='btn btn-ghost btn-sm' data-nd='" + x.id + "'>Remove</button></p>"; }).join("") : "<p class='muted small'>None.</p>") +
        "<div class='adm-row'><input id='ntext' placeholder='One clear next step' style='flex:1'><input id='ndue' type='date'><button class='btn btn-primary btn-sm' id='nadd'>Assign</button></div><p class='muted small'>He gets an email and sees it at the top of Today.</p></div>" +
        // Notes
        "<div class='adm-card'><h2>Notes he sees</h2>" + (pd.shared.length ? pd.shared.slice(0, 8).map(function (x) { return "<p class='small'>" + esc(x.text) + " <span class='muted'>" + when(x.at) + "</span> <button class='btn btn-ghost btn-sm' data-sd='" + x.at + "'>Remove</button></p>"; }).join("") : "<p class='muted small'>None.</p>") +
        "<textarea id='stext'></textarea><div class='adm-row'><label class='inline small'><input type='checkbox' id='stell'> Email it to him too</label><button class='btn btn-primary btn-sm' id='sadd'>Add note</button></div></div>" +
        "<div class='adm-card'><h2>Private notes</h2><p class='muted small'>Only you see these.</p>" + (d.notes.length ? d.notes.slice(0, 10).map(function (x) { return "<p class='small'>" + esc(x.text) + " <span class='muted'>" + when(x.at) + "</span> <button class='btn btn-ghost btn-sm' data-pd='" + x.at + "'>Remove</button></p>"; }).join("") : "") +
        "<textarea id='ptext'></textarea><div class='adm-row'><button class='btn btn-primary btn-sm' id='padd'>Save private note</button></div></div>" +
        "</div></div>" +
        // Reviews, reflections, uploads
        "<div class='man-grid'><div class='adm-card'><h2>Sunday reviews</h2>" + (revs.length ? revs.map(function (w) { var r = pd.reviews[w]; return "<p class='small'><b>" + nice(w) + ": " + r.k + "/" + r.t + "</b>" + (r.paper ? " (paper)" : "") + "<br>Miss: " + esc(r.miss) + "<br>Change: " + esc(r.change) + "<br>Grace: " + esc(r.grace) + "<br>Reported to: " + esc(r.reported) + "</p>"; }).join("") : "<p class='muted small'>None yet.</p>") +
        (Object.keys(pd.callPrep).length ? "<h2>Call notes</h2>" + Object.keys(pd.callPrep).sort().reverse().map(function (k) { return "<p class='small'><b>" + nice(k) + ":</b> " + esc(pd.callPrep[k].text) + "</p>"; }).join("") : "") + "</div>" +
        "<div class='adm-card'><h2>Lesson reflections</h2>" + (refl.length ? refl.map(function (l) { var r = pd.reflections[l.id]; return "<p class='small'><b>Week " + l.week + ":</b> " + (r.done ? "✓ action done" : "action not done") + "<br><span class='muted'>" + esc(l.reflection) + "</span><br>" + esc(r.text) + "</p>"; }).join("") : "<p class='muted small'>None yet.</p>") + "</div>" +
        "<div class='adm-card'><h2>Paper Ledger photos</h2>" + (pd.uploads.length ? pd.uploads.slice(0, 6).map(function (u) { return "<p class='small'>Week of " + nice(u.week) + " · " + when(u.at) + "</p><a href='/api/admin/man-upload?email=" + encodeURIComponent(email) + "&id=" + u.id + "' target='_blank'><img class='man-photo' loading='lazy' alt='Paper Ledger' src='/api/admin/man-upload?email=" + encodeURIComponent(email) + "&id=" + u.id + "'></a>"; }).join("") : "<p class='muted small'>None.</p>") + "</div></div>" +
        // Settings
        "<div class='adm-card'><h2>His portal</h2><div class='man-grid'>" +
        "<label>Portal<select id='srole'>" + Object.keys(ROLES).map(function (k) { return "<option value='" + k + "'" + (pd.role === k ? " selected" : "") + ">" + ROLES[k] + "</option>"; }).join("") + "</select></label>" +
        "<label>Access<select id='sacc'><option value='full'>Full</option><option value='readonly'" + (pd.access === "readonly" ? " selected" : "") + ">Read-only</option></select></label>" +
        "<label>Pace<select id='space'><option value='cohort'>With the cohort (week by week)</option><option value='self'" + (pd.pace.mode === "self" ? " selected" : "") + ">His own pace (opens when you approve)</option><option value='custom'" + (pd.pace.mode === "custom" ? " selected" : "") + ">Custom dates</option></select></label>" +
        "<label>Partner<select id='spart'><option value=''>None</option>" + d.men.map(function (e) { return "<option value='" + esc(e) + "'" + (pd.partner === e ? " selected" : "") + ">" + esc(e) + "</option>"; }).join("") + "</select></label></div>" +
        "<div class='adm-row' id='cdates'" + (pd.pace.mode === "custom" ? "" : " hidden") + ">" + [2, 3, 4].map(function (n) { return "<label>Step " + n + " opens<input type='date' data-cd='" + n + "' value='" + esc((pd.pace.dates || {})[n] || "") + "'></label>"; }).join("") + "</div>" +
        "<div class='adm-row'><button class='btn btn-primary btn-sm' id='ssave'>Save</button>" + (!pd.graduated ? "<button class='btn btn-ghost btn-sm' id='grad'>Graduate him</button>" : "<span class='tag ok'>Graduate</span>") + (pd.share.on ? "<button class='btn btn-ghost btn-sm' id='shoff'>Turn off his share link</button>" : "") + "<button class='btn btn-ghost btn-sm' id='pdel'>Delete portal</button></div>" +
        (pd.commitHistory.length ? "<details><summary class='small'>Earlier commitment versions (" + pd.commitHistory.length + ")</summary>" + pd.commitHistory.map(function (h) { return "<p class='small'><span class='muted'>" + when(h.at) + (h.by === "brian" ? " (you)" : "") + "</span><br>" + h.list.map(function (x) { return esc(x.what); }).join("<br>") + "</p>"; }).join("") + "</details>" : "") + "</div>";

      $$("[data-ap]", view).forEach(function (b) { b.onclick = function () { var n = +b.dataset.ap; var x = dialog("<div class='adm-card' style='margin:0'><h2>Approve Step " + n + "</h2><label>A note for him (optional)<textarea id='an'></textarea></label><label class='inline'><input type='checkbox' id='at' checked> Email him</label><div class='adm-row'><button class='btn btn-primary btn-sm' id='ago'>Approve</button><button class='btn btn-ghost btn-sm' data-close>Cancel</button></div></div>"); $("#ago", x).onclick = function () { $("#dlg").close(); up("approve", { n: n, note: $("#an", x).value, tell: $("#at", x).checked }); }; }; });
      $$("[data-rv]", view).forEach(function (b) { b.onclick = function () { var n = +b.dataset.rv; var x = dialog("<div class='adm-card' style='margin:0'><h2>Revisit Step " + n + "</h2><label>What should he look at again?<textarea id='rn'></textarea></label><div class='adm-row'><button class='btn btn-primary btn-sm' id='rgo'>Send back</button><button class='btn btn-ghost btn-sm' data-close>Cancel</button></div></div>"); $("#rgo", x).onclick = function () { if (!$("#rn", x).value.trim()) return flash("Write a note so he knows what to change."); $("#dlg").close(); up("revisit", { n: n, note: $("#rn", x).value }); }; }; });
      $$("[data-open]", view).forEach(function (b) { b.onclick = function () { up("open-step", { n: +b.dataset.open, on: true }); }; });
      $$("[data-nd]", view).forEach(function (b) { b.onclick = function () { up("next-delete", { id: b.dataset.nd }); }; });
      $$("[data-sd]", view).forEach(function (b) { b.onclick = function () { up("shared-delete", { at: +b.dataset.sd }); }; });
      $$("[data-pd]", view).forEach(function (b) { b.onclick = function () { up("private-delete", { at: +b.dataset.pd }); }; });
      $("#inv").onclick = function () { up("invite"); };
      $("#rsend").onclick = function () { up("message", { text: $("#rmsg").value }); };
      var rr = $("#rread"); if (rr) rr.onclick = function () { up("read"); };
      $("#nadd").onclick = function () { up("next", { text: $("#ntext").value, due: $("#ndue").value }); };
      $("#sadd").onclick = function () { up("shared-note", { text: $("#stext").value, tell: $("#stell").checked }); };
      $("#padd").onclick = function () { up("private-note", { text: $("#ptext").value }); };
      $("#space").onchange = function () { $("#cdates").hidden = this.value !== "custom"; };
      $("#ssave").onclick = function () {
        var dates = {}; $$("[data-cd]", view).forEach(function (i) { dates[i.dataset.cd] = i.value; });
        Promise.all([
          api("man-update", { email: email, op: "role", role: $("#srole").value, access: $("#sacc").value }),
          api("man-update", { email: email, op: "pace", mode: $("#space").value, dates: dates }),
          $("#spart").value !== (pd.partner || "") ? api("man-update", { email: email, op: "partner", partner: $("#spart").value }) : Promise.resolve({ ok: true }),
        ]).then(function () { flash("Saved."); VIEWS.man(email); });
      };
      var g = $("#grad"); if (g) g.onclick = function () { if (confirm("Graduate " + name + "? He gets the graduate badge and an email. If he isn't in the Club, his portal becomes read-only.")) up("graduate"); };
      var so = $("#shoff"); if (so) so.onclick = function () { up("share-off"); };
      $("#pdel").onclick = function () { if (confirm("Delete " + name + "'s portal, messages, notes and photos? This can't be undone. His contact record stays.")) api("man-update", { email: email, op: "delete", tell: !!pd.deleteRequested }).then(function (r) { if (r.ok) { flash("Portal deleted."); location.hash = "#men"; } }); };
      if (pd.unreadBrian) api("man-update", { email: email, op: "read" });
    });
  };

  // ---------- Library ----------
  VIEWS.library = function () {
    api("library").then(function (d) {
      if (!d.ok) return;
      var L = d.lessons, M = d.materials;
      function render() {
        view.innerHTML = "<div class='adm-row'><h2>Library</h2><span class='muted'>" + (d.edited ? "Edited " + when(d.edited) : "The drafted lessons") + "</span><button class='btn btn-primary btn-sm' id='lsave'>Save</button><button class='btn btn-ghost btn-sm' id='lreset'>Restore the drafts</button></div>" +
          "<p class='muted'>Six lessons, one per week. Each opens on its session date for men on the cohort pace, or when you open the matching step for men on their own pace. Text is required; video is optional (paste a YouTube link). Body format: a blank line starts a paragraph, <code>**bold**</code>, lines starting <code>- </code> are a list, <code>[[Button|link]]</code> is a button.</p>" +
          L.map(function (l, i) {
            return "<div class='adm-card' data-l='" + i + "'><div class='adm-row'><h2>Week " + l.week + "</h2><button class='btn btn-ghost btn-sm' data-ldel='" + i + "'>Remove</button></div>" +
              "<div class='man-grid'><label>Title<input data-k='title' value='" + esc(l.title) + "'></label><label>Scripture<input data-k='scripture' value='" + esc(l.scripture) + "'></label><label>Week<input data-k='week' type='number' min='1' max='6' value='" + l.week + "'></label><label>Step<input data-k='step' type='number' min='1' max='4' value='" + l.step + "'></label></div>" +
              "<label>Video (YouTube link, optional)<input data-k='video' value='" + esc(l.video) + "'></label><label>Lesson<textarea data-k='body' style='min-height:240px'>" + esc(l.body) + "</textarea></label>" +
              "<label>Action (checkbox)<input data-k='action' value='" + esc(l.action) + "'></label><label>Reflection question<input data-k='reflection' value='" + esc(l.reflection) + "'></label><label>PDF link (optional)<input data-k='pdf' value='" + esc(l.pdf || "") + "'></label></div>";
          }).join("") + "<p><button class='btn btn-ghost btn-sm' id='ladd'>Add a lesson</button></p>" +
          "<div class='adm-card'><h2>Materials</h2><p class='muted small'>Printables and links every man sees.</p>" + M.map(function (m, i) { return "<div class='adm-row' data-m='" + i + "'><input data-k='title' value='" + esc(m.title) + "' style='flex:2' aria-label='Title'><input data-k='url' value='" + esc(m.url) + "' style='flex:2' aria-label='Link'><select data-k='kind'><option value='pdf'>PDF</option><option value='link'" + (m.kind === "link" ? " selected" : "") + ">Link</option></select><button class='btn btn-ghost btn-sm' data-mdel='" + i + "'>Remove</button></div>"; }).join("") +
          "<p><button class='btn btn-ghost btn-sm' id='madd'>Add material</button></p></div>";
        $$("[data-ldel]", view).forEach(function (b) { b.onclick = function () { collect(); L.splice(+b.dataset.ldel, 1); render(); }; });
        $$("[data-mdel]", view).forEach(function (b) { b.onclick = function () { collect(); M.splice(+b.dataset.mdel, 1); render(); }; });
        $("#ladd").onclick = function () { collect(); L.push({ id: "", week: L.length + 1, step: 1, title: "New lesson", scripture: "", video: "", body: "", action: "", reflection: "", pdf: "" }); render(); };
        $("#madd").onclick = function () { collect(); M.push({ id: "", title: "", url: "", kind: "pdf" }); render(); };
        $("#lsave").onclick = function () { collect(); api("library", { lessons: L, materials: M }).then(function (r) { if (r.ok) { flash("Library saved. The men see it now."); VIEWS.library(); } }); };
        $("#lreset").onclick = function () { if (confirm("Throw away your edits and restore the drafted lessons?")) api("library-reset", {}).then(function () { flash("Restored."); VIEWS.library(); }); };
      }
      function collect() {
        $$("[data-l]", view).forEach(function (card) { var l = L[+card.dataset.l]; $$("[data-k]", card).forEach(function (el) { l[el.dataset.k] = el.type === "number" ? Number(el.value) : el.value; }); });
        $$("[data-m]", view).forEach(function (row) { var m = M[+row.dataset.m]; $$("[data-k]", row).forEach(function (el) { m[el.dataset.k] = el.value; }); });
      }
      render();
    });
  };

  // ---------- Sessions ----------
  VIEWS.sessions = function () {
    api("sessions").then(function (d) {
      if (!d.ok) return;
      view.innerHTML = "<div class='adm-row'><h2>Sessions</h2><button class='btn btn-primary btn-sm' id='ssave2'>Save</button><button class='btn btn-ghost btn-sm' id='sheet'>Next call sheet</button></div>" +
        "<p class='muted'>For each Thursday: paste the YouTube link to the teaching part only (keep the men's sharing private), and a short catch-up note for men who missed it. Men see the recording in that week's lesson; the catch-up note shows only to men who missed.</p>" +
        d.dates.map(function (dt, i) { var s = d.sessions[dt] || {}; return "<div class='adm-card' data-s='" + dt + "'><h2>Week " + (i + 1) + ": " + nice(dt, true) + "</h2><label>Teaching recording (YouTube link)<input data-k='video' value='" + esc(s.video || "") + "'></label><label>Catch-up note for men who missed<textarea data-k='note'>" + esc(s.note || "") + "</textarea></label><p><button class='btn btn-ghost btn-sm' data-cs='" + dt + "'>Call sheet</button></p></div>"; }).join("");
      $("#ssave2").onclick = function () { var out = {}; $$("[data-s]", view).forEach(function (c) { out[c.dataset.s] = { video: $("[data-k=video]", c).value, note: $("[data-k=note]", c).value }; }); api("sessions", { sessions: out }).then(function (r) { if (r.ok) flash("Sessions saved."); }); };
      $("#sheet").onclick = function () { callSheet(); };
      $$("[data-cs]", view).forEach(function (b) { b.onclick = function () { callSheet(b.dataset.cs); }; });
    });
  };
})();
