/* Be The Man dashboard, part 2: Cohort, Calls, Money, Settings, and additions to
   Overview, Contacts and Texts. Loaded after admin.js, which exposes window.BTM. */
(function () {
  "use strict";
  var B = window.BTM; if (!B) return;
  var $ = B.$, $$ = B.$$, esc = B.esc, day = B.day, when = B.when, api = B.api, flash = B.flash, dialog = B.dialog, view = B.view, VIEWS = B.VIEWS;
  var money = function (n) { return "$" + (Number(n) || 0).toFixed(2); };
  var wk = function (w) { return new Date(w + "T12:00:00-06:00").toLocaleDateString(undefined, { month: "short", day: "numeric" }); };
  var SNIPS = null;
  function snippets() { return SNIPS ? Promise.resolve(SNIPS) : api("snippets").then(function (d) { SNIPS = d.snippets || []; return SNIPS; }); }
  function snipPicker(target) {
    return snippets().then(function (list) {
      if (!list.length) return "";
      var id = "sp" + Math.random().toString(36).slice(2, 7);
      setTimeout(function () { var s = document.getElementById(id); if (s) s.onchange = function () { var x = list.filter(function (n) { return n.id === s.value; })[0]; if (x) { var t = typeof target === "function" ? target() : target; t.value = (t.value ? t.value + "\n\n" : "") + x.text; } s.value = ""; }; }, 0);
      return "<select id='" + id + "'><option value=''>Insert a saved reply…</option>" + list.map(function (n) { return "<option value='" + esc(n.id) + "'>" + esc(n.name) + "</option>"; }).join("") + "</select>";
    });
  }

  // ---------- Cohort ----------
  VIEWS.cohort = function () {
    api("cohort").then(function (d) {
      if (!d.ok) return;
      var weeks = {}; d.members.forEach(function (m) { Object.keys(m.ledger || {}).forEach(function (w) { weeks[w] = 1; }); }); weeks[d.week] = 1;
      weeks = Object.keys(weeks).sort().slice(-8);
      var reported = d.members.filter(function (m) { return m.ledger && m.ledger[d.week]; }).length;
      var st = d.status || {};
      var avg = function (w) { var xs = d.members.map(function (m) { return m.ledger && m.ledger[w]; }).filter(Boolean); if (!xs.length) return "–"; var k = 0, t = 0; xs.forEach(function (x) { k += x.k; t += x.t; }); return Math.round((100 * k) / t) + "%"; };
      view.innerHTML =
        "<div class='adm-row'><h2>Cohort roster</h2><span class='muted'>Tag: " + esc(d.tag) + " · " + d.members.length + " men" + (st.sold != null ? " · " + st.sold + " of " + st.limit + " seats sold" : "") + "</span></div>" +
        "<div class='adm-row'><button class='btn btn-primary btn-sm' id='ctext'>Text the cohort</button><button class='btn btn-ghost btn-sm' id='cmail'>Email the cohort</button><button class='btn btn-ghost btn-sm' id='cres'>Ask for results</button></div>" +
        "<div class='adm-stats'><div class='adm-stat'><b>" + reported + " of " + d.members.length + "</b><span>Reported for the week of " + wk(d.week) + "</span></div>" +
        "<div class='adm-stat'><b>" + avg(d.week) + "</b><span>Group kept this week</span></div><div class='adm-stat'><b>" + (d.settings.ledger.on ? "On" : "Off") + "</b><span>Ledger texts (Sunday 6 PM, nudge Monday noon)</span></div></div>" +
        "<div class='adm-table'><table><tr><th>Man</th><th>Step 1</th>" + d.sessions.map(function (s) { return "<th title='Attended'>" + wk(s) + "</th>"; }).join("") + weeks.map(function (w) { return "<th>Ledger " + wk(w) + "</th>"; }).join("") + "<th></th></tr>" +
        d.members.map(function (m, i) {
          var att = (m.cohort && m.cohort.att) || {};
          return "<tr data-i='" + i + "'><td><b>" + esc(m.name || m.email) + "</b><br><span class='muted small'>" + esc(m.phone || m.email) + (m.texts ? " · texts" : "") + "</span></td>" +
            "<td><input type='checkbox' class='c-s1'" + (m.cohort && m.cohort.step1 ? " checked" : "") + " aria-label='Step 1 done'></td>" +
            d.sessions.map(function (s) { return "<td><input type='checkbox' class='c-att' data-d='" + s + "'" + (att[s] ? " checked" : "") + " aria-label='Attended " + s + "'></td>"; }).join("") +
            weeks.map(function (w) { var l = m.ledger && m.ledger[w]; return "<td><button class='btn btn-ghost btn-sm c-l' data-w='" + w + "' title='" + esc(l && l.miss ? "Miss: " + l.miss : "") + "'>" + (l ? l.k + "/" + l.t : (w === d.week ? "<span class='fail'>none</span>" : "–")) + "</button></td>"; }).join("") +
            "<td><button class='btn btn-ghost btn-sm c-n'>Notes</button></td></tr>";
        }).join("") + "</table></div>" +
        "<p class='muted small'>Tick Step 1 and attendance as you go. Click a Ledger cell to add or fix a number. Men report by replying to the Sunday text with a number like 13/15, or through the link in the Sunday email.</p>" +
        "<h2 style='margin-top:10px'>Results</h2><p class='muted'>Shared by the men through the results form. Nothing appears on the home page unless he gave permission and you approve it.</p>" +
        "<div class='adm-table'>" + (d.results.length ? "<table><tr><th>Name</th><th>Numbers</th><th>In his words</th><th>Permission</th><th></th></tr>" + d.results.map(function (r, i) {
          return "<tr data-r='" + i + "'><td>" + esc(r.name) + "<br><span class='muted small'>" + esc(r.email) + "</span></td><td>" + esc(r.before) + " → " + esc(r.after) + "</td><td>" + esc(r.quote) + "</td><td>" + (r.permission ? "<span class='tag ok'>Yes</span>" : "<span class='tag'>Private</span>") + "</td><td>" +
            (r.permission ? "<button class='btn btn-" + (r.approved ? "ghost" : "primary") + " btn-sm r-ap'>" + (r.approved ? "Unpublish" : "Approve for the site") + "</button>" : "") + "<button class='btn btn-ghost btn-sm r-del'>Delete</button></td></tr>";
        }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No results yet. In week 6, press Ask for results.</p>") + "</div>";
      $$("tr[data-i]", view).forEach(function (row) {
        var m = d.members[+row.dataset.i];
        $(".c-s1", row).onchange = function () { api("cohort-update", { email: m.email, step1: this.checked }); };
        $$(".c-att", row).forEach(function (cb) { cb.onchange = function () { var a = {}; a[cb.dataset.d] = cb.checked; api("cohort-update", { email: m.email, att: a }); }; });
        $$(".c-l", row).forEach(function (btn) {
          btn.onclick = function () {
            var w = btn.dataset.w, l = (m.ledger || {})[w] || {};
            var b = dialog("<div class='adm-card' style='margin:0'><h2>" + esc(m.name || m.email) + ", week of " + wk(w) + "</h2>" +
              (l.miss ? "<p class='small'>Miss: " + esc(l.miss) + "</p>" : "") + (l.change ? "<p class='small'>Change: " + esc(l.change) + "</p>" : "") + (l.via ? "<p class='muted small'>From " + esc(l.via) + " " + when(l.at) + "</p>" : "") +
              "<div class='adm-row'><input id='lk' type='number' min='0' value='" + (l.k != null ? l.k : "") + "' style='width:90px' aria-label='Kept'> of <input id='lt' type='number' min='1' value='" + (l.t || "") + "' style='width:90px' aria-label='Total'></div>" +
              "<div class='adm-row'><button class='btn btn-primary btn-sm' id='lsave'>Save</button>" + (l.k != null ? "<button class='btn btn-ghost btn-sm' id='lclear'>Clear</button>" : "") + "<button class='btn btn-ghost btn-sm' id='llink'>Copy his report link</button><button class='btn btn-ghost btn-sm' data-close>Close</button></div></div>");
            $("#lsave", b).onclick = function () { api("cohort-update", { email: m.email, ledger: { week: w, k: $("#lk", b).value, t: $("#lt", b).value } }).then(function (r) { if (r.ok) { $("#dlg").close(); VIEWS.cohort(); } }); };
            var cl = $("#lclear", b); if (cl) cl.onclick = function () { api("cohort-update", { email: m.email, ledger: { week: w, clear: true } }).then(function () { $("#dlg").close(); VIEWS.cohort(); }); };
            $("#llink", b).onclick = function () { api("ledger-ask", { email: m.email }).then(function (r) { if (r.ok) { navigator.clipboard && navigator.clipboard.writeText(r.link); flash("Link copied. It works for 60 days."); } }); };
          };
        });
        $(".c-n", row).onclick = function () {
          var b = dialog("<div class='adm-card' style='margin:0'><h2>Notes: " + esc(m.name || m.email) + "</h2><textarea id='cnotes'>" + esc((m.cohort && m.cohort.notes) || "") + "</textarea><div class='adm-row'><button class='btn btn-primary btn-sm' id='nsave'>Save</button><button class='btn btn-ghost btn-sm' data-close>Close</button></div></div>");
          $("#nsave", b).onclick = function () { api("cohort-update", { email: m.email, notes: $("#cnotes", b).value }).then(function (r) { if (r.ok) { flash("Notes saved."); $("#dlg").close(); VIEWS.cohort(); } }); };
        };
      });
      $$("tr[data-r]", view).forEach(function (row) {
        var r = d.results[+row.dataset.r];
        var ap = $(".r-ap", row); if (ap) ap.onclick = function () { api("result-approve", { email: r.email, approved: !r.approved }).then(function (x) { if (x.ok) { flash(r.approved ? "Taken off the site." : "Approved. It shows on the home page within a few minutes."); VIEWS.cohort(); } }); };
        $(".r-del", row).onclick = function () { if (confirm("Delete this result?")) api("result-delete", { email: r.email }).then(function () { VIEWS.cohort(); }); };
      });
      function quick(channel) {
        B.show("broadcasts");
        setTimeout(function () { var btn = document.getElementById(channel === "sms" ? "news" : "newe"); if (btn) btn.click(); setTimeout(function () { var s = document.getElementById("baud"); if (s) { s.value = "tag:" + d.tag; s.dispatchEvent(new Event("change")); } }, 300); }, 600);
      }
      $("#ctext").onclick = function () { quick("sms"); };
      $("#cmail").onclick = function () { quick("email"); };
      $("#cres").onclick = function () { if (confirm("Email every active man tagged \"" + d.tag + "\" a link to share his result?")) api("results-request", { tag: d.tag }).then(function (r) { if (r.ok) flash("Sent to " + r.sent + " men."); }); };
    });
  };

  // ---------- Calls ----------
  VIEWS.calls = function () {
    api("calls").then(function (d) {
      if (!d.ok) return;
      var nowT = Date.now(), up = d.calls.filter(function (c) { return Date.parse(c.start) >= nowT - 3600000; }), past = d.calls.filter(function (c) { return Date.parse(c.start) < nowT - 3600000; }).reverse();
      var LBL = { joined: "Joined", notnow: "Not now", followup: "Follow up", noshow: "No show" };
      var rows = function (list, isPast) {
        return list.length ? "<table><tr><th>When</th><th>Who</th><th>On his mind</th><th>Outcome</th></tr>" + list.map(function (c, i) {
          return "<tr><td>" + when(Date.parse(c.start)) + "</td><td><b>" + esc(c.name) + "</b><br><a class='textlink' href='tel:" + esc(c.phone) + "'>" + esc(c.phone) + "</a><br><span class='muted small'>" + esc(c.email) + "</span></td><td>" + esc(c.note || "") + "</td><td>" +
            (c.outcome ? "<span class='tag'>" + esc(LBL[c.outcome.outcome] || c.outcome.outcome) + "</span>" + (c.outcome.followUp ? " " + esc(c.outcome.followUp) : "") + "<br>" : "") +
            (isPast ? "<button class='btn btn-ghost btn-sm k-out' data-k='" + esc(c.start) + "'>" + (c.outcome ? "Change" : "Record outcome") + "</button>" : "") + "</td></tr>";
        }).join("") + "</table>" : "<p class='muted' style='padding:14px'>None.</p>";
      };
      view.innerHTML = "<h2>Upcoming free calls</h2><div class='adm-table'>" + rows(up, false) + "</div><h2 style='margin-top:10px'>Past calls</h2><div class='adm-table'>" + rows(past, true) + "</div>" +
        "<p class='muted small'>Recording an outcome tags the man (for example \"Call: follow up\"), adds your note to his record, and a follow-up date emails you a reminder that morning at 9.</p>";
      $$(".k-out", view).forEach(function (btn) {
        btn.onclick = function () {
          var c = d.calls.filter(function (x) { return x.start === btn.dataset.k; })[0], o = c.outcome || {};
          var b = dialog("<div class='adm-card' style='margin:0'><h2>" + esc(c.name) + "</h2><label>Outcome<select id='ko'><option value='joined'>Joined</option><option value='notnow'>Not now</option><option value='followup'>Follow up</option><option value='noshow'>No show</option></select></label>" +
            "<label>Note<textarea id='kn' class='short'>" + esc(o.note || "") + "</textarea></label><label id='kfw'>Follow up on<input type='date' id='kf' value='" + esc(o.followUp || "") + "'></label>" +
            "<div class='adm-row'><button class='btn btn-primary btn-sm' id='ksave'>Save</button><button class='btn btn-ghost btn-sm' data-close>Close</button></div></div>");
          $("#ko", b).value = o.outcome || "followup";
          var sync = function () { $("#kfw", b).hidden = $("#ko", b).value !== "followup"; }; $("#ko", b).onchange = sync; sync();
          $("#ksave", b).onclick = function () { api("call-outcome", { start: c.start, name: c.name, email: c.email, phone: c.phone, outcome: $("#ko", b).value, note: $("#kn", b).value, followUp: $("#kf", b).value }).then(function (r) { if (r.ok) { flash("Saved."); $("#dlg").close(); VIEWS.calls(); } }); };
        };
      });
    });
  };

  // ---------- Money ----------
  VIEWS.money = function () {
    api("money").then(function (d) {
      if (!d.ok) { view.innerHTML = "<p class='muted'>" + esc(d.error || "Couldn't reach Stripe.") + "</p>"; return; }
      var f = d.funnel, pc = function (a, b) { return b ? Math.round((100 * a) / b) + "%" : "–"; };
      var prod = Object.keys(d.byProduct).sort(function (a, b) { return d.byProduct[b].amount - d.byProduct[a].amount; });
      var src = Object.keys(d.sources).sort(function (a, b) { return d.sources[b].signups - d.sources[a].signups; });
      view.innerHTML = "<div class='adm-stats'><div class='adm-stat'><b>" + money(d.totalMonth) + "</b><span>This month</span></div><div class='adm-stat'><b>" + money(d.total30) + "</b><span>Last 30 days</span></div>" +
        "<div class='adm-stat'><b>" + d.club.members + "</b><span>Club members (" + money(d.club.mrr) + " a month)</span></div><div class='adm-stat'><b>" + d.refunds.count + "</b><span>Refunds, 30 days (" + money(d.refunds.amount) + ")</span></div></div>" +
        "<div class='adm-card'><h3>From Step 1 to buyer, last 30 days</h3><div class='adm-stats'><div class='adm-stat'><b>" + f.signedUp + "</b><span>Signed up for Step 1</span></div><div class='adm-stat'><b>" + f.opened + "</b><span>Opened an email (" + pc(f.opened, f.signedUp) + ")</span></div>" +
        "<div class='adm-stat'><b>" + f.clicked + "</b><span>Clicked a link (" + pc(f.clicked, f.signedUp) + ")</span></div><div class='adm-stat'><b>" + f.bought + "</b><span>Bought (" + pc(f.bought, f.signedUp) + ")</span></div></div></div>" +
        "<div class='adm-card'><h3>By product, last 30 days</h3><div class='adm-table'>" + (prod.length ? "<table><tr><th>Product</th><th>Sales</th><th>Revenue</th></tr>" + prod.map(function (p) { return "<tr><td>" + esc(p) + "</td><td>" + d.byProduct[p].count + "</td><td>" + money(d.byProduct[p].amount) + "</td></tr>"; }).join("") + "</table>" : "<p class='muted' style='padding:14px'>No sales in the last 30 days.</p>") + "</div></div>" +
        "<div class='adm-card'><h3>Where people come from (all time)</h3><div class='adm-table'><table><tr><th>Source</th><th>Sign-ups</th><th>Buyers</th><th>Revenue, 30 days</th></tr>" + src.map(function (s) { return "<tr><td>" + esc(s) + "</td><td>" + d.sources[s].signups + "</td><td>" + d.sources[s].buyers + "</td><td>" + money(d.bySourceRevenue[s] || 0) + "</td></tr>"; }).join("") + "</table></div>" +
        "<p class='muted small'>Sources come from your short links (bethemansystem.com/yt, /ig, /fb, /tt, /sub, /pod, /dm), from ?src= on any link, and from the site a visitor came from. Referral links count as \"referral\".</p></div>" +
        "<div class='adm-card'><h3>Recent sales</h3><div class='adm-table'>" + (d.recent.length ? "<table>" + d.recent.map(function (r) { return "<tr><td>" + when(r.at) + "</td><td>" + esc(r.name) + "</td><td>" + esc(r.email) + "</td><td>" + money(r.amount) + "</td></tr>"; }).join("") + "</table>" : "<p class='muted' style='padding:14px'>None yet.</p>") + "</div></div>";
    });
  };

  // ---------- Settings ----------
  VIEWS.settings = function () {
    Promise.all([api("settings"), api("snippets"), api("segments")]).then(function (res) {
      var s = res[0].settings, rss = res[0].rss || {}, segs = res[2].segments || [];
      SNIPS = res[1].snippets || [];
      view.innerHTML =
        "<div class='adm-card'><h2>The Ledger by text</h2><p class='muted'>Every Sunday at 6 PM Central, each man with the tag below gets a text (or an email if he isn't on texts) asking for his number. He replies like 13/15 and it's saved to the Cohort tab. Monday at noon, anyone who hasn't reported gets one nudge and you get the list.</p>" +
        "<div class='adm-row'><label class='inline'><input type='checkbox' id='lon'" + (s.ledger.on ? " checked" : "") + "> On</label><label class='inline'>Tag<input id='ltag' value='" + esc(s.ledger.tag) + "'></label></div></div>" +
        "<div class='adm-card'><h2>Substack to email</h2><p class='muted'>Checks " + esc(s.rss.url) + " every hour. When you publish, it makes an email with the title, an excerpt and a \"Read it on Substack\" button.</p>" +
        "<div class='adm-row'><label class='inline'>When I publish<select id='rmode'><option value='off'>Do nothing</option><option value='draft'>Make a draft and email me</option><option value='send'>Send it to the list</option></select></label>" +
        "<label class='inline'>To<select id='raud'><option value='all:'>Everyone active</option>" + B.tags().map(function (t) { return "<option value='tag:" + esc(t) + "'>Tag: " + esc(t) + "</option>"; }).join("") + segs.map(function (g) { return "<option value='segment:" + esc(g.id) + "'>Segment: " + esc(g.name) + "</option>"; }).join("") + "</select></label>" +
        "<button class='btn btn-ghost btn-sm' id='rcheck'>Check now</button></div>" + (rss.checked ? "<p class='muted small'>Last checked " + when(rss.checked) + ". Posts already published before you turned this on are not sent.</p>" : "") + "</div>" +
        "<div class='adm-card'><h2>Monday report</h2><p class='muted'>A one-page email to you every Monday at 8 AM Central: new sign-ups and where they came from, cohort seats, revenue, Ledger reports, and anything that failed.</p><div class='adm-row'><label class='inline'><input type='checkbox' id='ron'" + (s.report.on ? " checked" : "") + "> On</label><button class='btn btn-ghost btn-sm' id='rprev'>Preview this week's</button></div></div>" +
        "<div class='adm-row'><button class='btn btn-primary btn-sm' id='ssave'>Save settings</button></div>" +
        "<div class='adm-card'><div class='adm-row'><h2>Saved replies</h2><button class='btn btn-ghost btn-sm' id='nadd'>Add one</button><button class='btn btn-primary btn-sm' id='nsave'>Save replies</button></div><p class='muted'>Use them in the text inbox and in \"Email him\" on a contact.</p><div id='snips'></div></div>";
      $("#rmode").value = s.rss.mode; $("#raud").value = (s.rss.audience.type || "all") + ":" + (s.rss.audience.value || "");
      function drawSnips() {
        $("#snips").innerHTML = SNIPS.map(function (n, i) { return "<div class='adm-card sub' data-n='" + i + "'><div class='adm-row'><input class='n-name adm-grow' value='" + esc(n.name) + "' aria-label='Name'><button class='btn btn-ghost btn-sm n-del'>Delete</button></div><textarea class='n-text short'>" + esc(n.text) + "</textarea></div>"; }).join("") || "<p class='muted'>None yet. Ideas: \"Here's the Meet link\", \"Here's Step 1\", \"I'll call you this week\".</p>";
        $$("[data-n]").forEach(function (el) { $(".n-del", el).onclick = function () { collect(); SNIPS.splice(+el.dataset.n, 1); drawSnips(); }; });
      }
      function collect() { $$("[data-n]").forEach(function (el) { var n = SNIPS[+el.dataset.n]; n.name = $(".n-name", el).value; n.text = $(".n-text", el).value; }); }
      drawSnips();
      $("#nadd").onclick = function () { collect(); SNIPS.push({ name: "New reply", text: "" }); drawSnips(); };
      $("#nsave").onclick = function () { collect(); api("snippets", { snippets: SNIPS }).then(function (r) { if (r.ok) { SNIPS = r.snippets; flash("Saved replies saved."); drawSnips(); } }); };
      $("#ssave").onclick = function () {
        var a = $("#raud").value, i = a.indexOf(":");
        api("settings", { ledger: { on: $("#lon").checked, tag: $("#ltag").value }, rss: { mode: $("#rmode").value, url: s.rss.url, audience: { type: a.slice(0, i), value: a.slice(i + 1) } }, report: { on: $("#ron").checked } })
          .then(function (r) { if (r.ok) flash("Settings saved."); });
      };
      $("#rcheck").onclick = function () { api("rss-check", {}).then(function (r) { if (r.ok) flash("Found " + ((r.result && r.result.found) || 0) + " posts; " + ((r.result && r.result.created) || 0) + " new."); }); };
      $("#rprev").onclick = function () { api("report-preview", {}).then(function (r) { var b = dialog("<h2 style='margin-bottom:10px'>Your Monday report</h2><iframe></iframe><div class='adm-row' style='margin-top:12px'><button class='btn btn-ghost btn-sm' data-close>Close</button></div>"); $("iframe", b).srcdoc = r.html; }); };
    });
  };

  // ---------- additions to existing screens ----------
  B.after("overview", function (d) {
    if (!d || !d.ok) return;
    var src = Object.keys(d.sources || {}).sort(function (a, b) { return d.sources[b] - d.sources[a]; });
    var el = document.createElement("div");
    el.className = "adm-card";
    el.innerHTML = "<h3>Where people come from</h3><div>" + (src.map(function (s) { return "<span class='tag'>" + esc(s) + " · " + d.sources[s] + "</span>"; }).join("") || "<span class='muted'>No data yet.</span>") + "</div>" +
      ((d.referrers || []).length ? "<h3 style='margin-top:8px'>Top referrers</h3><div>" + d.referrers.map(function (r) { return "<span class='tag'>" + esc(r.n || r.email) + " · " + r.rc + "</span>"; }).join("") + "</div>" : "") +
      "<p class='muted small'>Use your short links so every post is counted: bethemansystem.com/yt, /ig, /fb, /tt, /sub, /pod, /dm. See the Money tab for buyers by source.</p>";
    var stats = $(".adm-stats", view); if (stats) stats.insertAdjacentElement("afterend", el);
  });

  B.after("contact", function (c, box) {
    var info = document.createElement("div");
    info.innerHTML = "<p class='small'>" + (c.src ? "Came from <b>" + esc(c.src) + "</b>. " : "") + (c.referredBy ? "Referred by " + esc(c.referredBy) + ". " : "") +
      (c.ref ? "His referral link: <code>bethemansystem.com/r/" + esc(c.ref) + "</code>" + (c.refCount ? " (" + c.refCount + " sign-ups)" : "") : "") + "</p>" +
      "<div class='adm-row'><button class='btn btn-ghost btn-sm' id='cemail'>Email him</button></div>";
    var first = $(".adm-card", box); if (first) first.insertBefore(info, first.children[2] || null);
    $("#cemail", box).onclick = function () {
      var b = dialog("<div class='adm-card' style='margin:0'><h2>Email " + esc(c.name || c.email) + "</h2><p class='muted small'>A personal email from you (not a list email).</p><label>Subject<input id='pes'></label><label>Message<textarea id='peb'></textarea></label><div class='adm-row' id='pesn'></div><div class='adm-row'><button class='btn btn-primary btn-sm' id='pego'>Send</button><button class='btn btn-ghost btn-sm' data-close>Cancel</button></div></div>");
      snipPicker(function () { return $("#peb", b); }).then(function (h) { $("#pesn", b).innerHTML = h; });
      $("#pego", b).onclick = function () { api("email-contact", { email: c.email, subject: $("#pes", b).value, body: $("#peb", b).value }).then(function (r) { if (r.ok) { flash("Sent."); $("#dlg").close(); } }); };
    };
  });

  B.after("textReply", function (box) {
    var t = $("#rbody", box); if (!t) return;
    snipPicker(function () { return t; }).then(function (h) { if (h) { var d = document.createElement("div"); d.className = "adm-row"; d.style.marginTop = "8px"; d.innerHTML = h; t.parentNode.insertAdjacentElement("afterend", d); } });
  });
})();
