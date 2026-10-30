(function () {
  var L = window.WT, $ = function (id) { return document.getElementById(id); };
  (function drawMan() {
          var r = L.rng(21), cb = $("cBody").getContext("2d"), ch = $("mHead").getContext("2d"), cj = $("mJaw").getContext("2d");
          function lg(c, x0, y0, x1, y1, st) { var g = c.createLinearGradient(x0, y0, x1, y1); st.forEach(function (a) { g.addColorStop(a[0], a[1]); }); return g; }
          function rg(c, x, y, r0, r1, st) { var g = c.createRadialGradient(x, y, r0, x, y, r1); st.forEach(function (a) { g.addColorStop(a[0], a[1]); }); return g; }
          // --- torso: a charcoal hoodie, shoulders square to the screen
          var torso = new Path2D("M40 1000 C48 840 120 720 310 664 C400 636 470 612 506 584 L640 584 C700 618 800 640 930 668 C1080 706 1150 820 1170 1000 Z");
          cb.save(); cb.clip(torso);
          cb.fillStyle = lg(cb, 40, 0, 1170, 0, [[0, "#0d0e10"], [0.45, "#1a1c20"], [0.8, "#24272c"], [1, "#2e3238"]]); cb.fillRect(0, 560, 1500, 460);
          cb.fillStyle = rg(cb, 1100, 700, 20, 520, [[0, "rgba(255,206,150,0.30)"], [0.5, "rgba(255,190,120,0.08)"], [1, "rgba(0,0,0,0)"]]); cb.fillRect(0, 560, 1500, 460);
          for (var i = 0; i < 9000; i++) { var x = 40 + r() * 1130, y = 580 + r() * 420; cb.fillStyle = "rgba(" + (r() < 0.5 ? "255,255,255" : "0,0,0") + "," + (0.03 + r() * 0.05).toFixed(3) + ")"; cb.fillRect(x, y, 1.6, 1.6); }
          cb.lineCap = "round";
          [[330, 760, 360, 900, 0.22], [470, 780, 520, 960, 0.2], [760, 760, 800, 940, 0.2], [940, 760, 1010, 930, 0.18]].forEach(function (f) { cb.strokeStyle = "rgba(0,0,0," + f[4] + ")"; cb.lineWidth = 26; cb.beginPath(); cb.moveTo(f[0], f[1]); cb.quadraticCurveTo(f[0] + 20, (f[1] + f[3]) / 2, f[2], f[3]); cb.stroke(); cb.strokeStyle = "rgba(255,225,190,0.05)"; cb.lineWidth = 6; cb.beginPath(); cb.moveTo(f[0] + 18, f[1]); cb.quadraticCurveTo(f[0] + 38, (f[1] + f[3]) / 2, f[2] + 18, f[3]); cb.stroke(); });
          cb.restore();
          cb.save(); cb.lineWidth = 5; cb.strokeStyle = lg(cb, 640, 640, 1170, 800, [[0, "rgba(255,214,165,0.0)"], [0.5, "rgba(255,214,165,0.55)"], [1, "rgba(255,214,165,0.18)"]]); cb.stroke(new Path2D("M640 584 C700 618 800 640 930 668 C1080 706 1150 820 1170 1000")); cb.restore();
          // --- hood bunched at the back of the neck
          var hood = new Path2D("M360 640 C380 560 470 520 560 524 C660 526 740 570 760 650 C700 676 560 690 460 680 C410 676 372 662 360 640 Z");
          cb.save(); cb.clip(hood); cb.fillStyle = lg(cb, 360, 520, 760, 690, [[0, "#14161a"], [0.6, "#202328"], [1, "#2b2f35"]]); cb.fillRect(340, 500, 440, 220);
          for (var h = 0; h < 6; h++) { cb.strokeStyle = "rgba(0,0,0,0.10)"; cb.lineWidth = 10; cb.beginPath(); cb.moveTo(380 + h * 62, 560); cb.quadraticCurveTo(400 + h * 62, 620, 392 + h * 66, 690); cb.stroke(); }
          cb.restore();
          // --- neck: warm skin in deep shadow, lit along the right edge
          var neck = new Path2D("M480 420 L650 420 C666 500 690 560 700 616 C640 640 520 640 446 616 C462 560 474 500 480 420 Z");
          cb.save(); cb.clip(neck);
          cb.fillStyle = lg(cb, 450, 0, 700, 0, [[0, "#2a1912"], [0.55, "#4a2f21"], [1, "#7a4d33"]]); cb.fillRect(430, 400, 290, 260);
          cb.fillStyle = lg(cb, 0, 400, 0, 640, [[0, "rgba(0,0,0,0.85)"], [0.45, "rgba(0,0,0,0.25)"], [1, "rgba(0,0,0,0.55)"]]); cb.fillRect(430, 400, 290, 260);
          cb.fillStyle = "rgba(0,0,0,0.28)"; cb.beginPath(); cb.ellipse(565, 560, 22, 70, 0, 0, 6.3); cb.fill();       // spine ridge
          for (var n = 0; n < 1400; n++) { cb.fillStyle = "rgba(255,210,170," + (r() * 0.07).toFixed(3) + ")"; cb.fillRect(450 + r() * 250, 420 + r() * 220, 1.4, 1.4); }
          cb.restore();
          cb.strokeStyle = "rgba(255,214,165,0.5)"; cb.lineWidth = 3; cb.beginPath(); cb.moveTo(650, 430); cb.bezierCurveTo(668, 500, 690, 560, 700, 614); cb.stroke();

          // --- head (own canvas so it can lean and drop on its own): the back of the head, turned a little toward the screen
          var cx = 560, cy = 330, rx = 152, ry = 178; ch.save(); ch.translate(0, 46);
          cj.translate(0, 46);
          // the cheek and jaw, a sliver beyond the ear on the screen side
          var cheek = new Path2D("M690 290 C742 316 756 380 744 440 C736 478 712 506 676 520 L640 470 C664 420 676 350 690 290 Z");
          cj.save(); cj.clip(cheek); cj.fillStyle = lg(ch, 640, 0, 760, 0, [[0, "#4a2f21"], [0.5, "#8a5a3c"], [1, "#d29a6c"]]); cj.fillRect(620, 260, 160, 280);
          cj.fillStyle = rg(ch, 760, 410, 10, 150, [[0, "rgba(255,210,160,0.55)"], [1, "rgba(255,210,160,0)"]]); cj.fillRect(620, 260, 160, 280);
          for (var k = 0; k < 260; k++) { cj.fillStyle = "rgba(20,12,8," + (r() * 0.5).toFixed(2) + ")"; cj.fillRect(650 + r() * 100, 440 + r() * 80, 1.5, 1.5); }   // stubble along the jaw
          cj.restore();
          // the skull under the hair: skin, so the faded sides read as skin through short hair
          ch.beginPath(); ch.ellipse(cx, cy, rx, ry, 0, 0, 6.3); ch.fillStyle = lg(ch, cx - rx, 0, cx + rx, 0, [[0, "#1c100b"], [0.6, "#3e271a"], [1, "#7a5238"]]); ch.fill();
          // the ear
          ch.save(); ch.translate(694, 360); ch.rotate(0.12);
          ch.beginPath(); ch.ellipse(0, 0, 26, 50, 0, 0, 6.3); ch.fillStyle = lg(ch, -26, 0, 26, 0, [[0, "#6b4430"], [0.6, "#a57045"], [1, "#e0aa78"]]); ch.fill();
          ch.strokeStyle = "rgba(40,22,14,0.75)"; ch.lineWidth = 4; ch.beginPath(); ch.ellipse(2, 2, 11, 30, 0.1, -1.2, 2.6); ch.stroke();
          ch.strokeStyle = "rgba(40,22,14,0.5)"; ch.lineWidth = 3; ch.beginPath(); ch.arc(2, 12, 9, 3.4, 6.1); ch.stroke();
          ch.strokeStyle = "rgba(255,225,190,0.65)"; ch.lineWidth = 3; ch.beginPath(); ch.ellipse(0, 0, 25, 49, 0, -1.2, 1.1); ch.stroke();
          ch.restore();
          // hair: short, faded at the sides and the nape.  Strokes on their own layer, then masked by a vertical fade.
          var hl = document.createElement("canvas"); hl.width = 1500; hl.height = 1000; var hc = hl.getContext("2d");
          hc.beginPath(); hc.ellipse(cx, cy - 6, rx + 8, ry + 6, 0, 0, 6.3); hc.fillStyle = "#17100b"; hc.fill();
          hc.lineCap = "round";
          for (var q = 0; q < 5200; q++) {
            var ang = r() * 6.283, rad = Math.pow(r(), 0.62), px = cx + Math.cos(ang) * (rx + 6) * rad, py = cy - 8 + Math.sin(ang) * (ry + 4) * rad;
            var fl = Math.atan2(py - (cy - 120), px - (cx - 14)) + 0.5 * (r() - 0.5), len = 7 + r() * 11, lit = Math.max(0, (px - cx) / rx), v = r();
            hc.strokeStyle = v < 0.5 ? "rgba(8,5,3," + (0.35 + r() * 0.4).toFixed(2) + ")" : "rgba(" + (44 + 80 * lit) + "," + (30 + 54 * lit) + "," + (20 + 36 * lit) + "," + (0.16 + 0.34 * lit * r()).toFixed(2) + ")";
            hc.lineWidth = 1.3 + r() * 1.3; hc.beginPath(); hc.moveTo(px, py); hc.lineTo(px + Math.cos(fl) * len, py + Math.sin(fl) * len); hc.stroke();
          }
          hc.globalCompositeOperation = "destination-in";
          hc.fillStyle = lg(hc, 0, 0, 0, 1000, [[0, "#000"], [0.355, "#000"], [0.46, "rgba(0,0,0,0.55)"], [0.5, "rgba(0,0,0,0)"], [1, "rgba(0,0,0,0)"]]); hc.fillRect(0, 0, 1500, 1000);
          hc.globalCompositeOperation = "source-over";
          // the sides fade sooner than the back
          hc.globalCompositeOperation = "destination-out";
          [[cx + rx - 8, 330, 54, 120], [cx - rx + 8, 330, 54, 120]].forEach(function (e) { hc.fillStyle = rg(hc, e[0], e[1], 8, e[3], [[0, "rgba(0,0,0,0.9)"], [1, "rgba(0,0,0,0)"]]); hc.fillRect(e[0] - 140, e[1] - 140, 280, 280); });
          hc.globalCompositeOperation = "source-over";
          ch.drawImage(hl, 0, 0);
          // light from the screen across the crown and the right side of the head
          ch.save(); ch.globalCompositeOperation = "screen"; ch.fillStyle = rg(ch, 720, 300, 10, 230, [[0, "rgba(255,214,165,0.22)"], [0.5, "rgba(255,196,130,0.07)"], [1, "rgba(0,0,0,0)"]]); ch.fillRect(380, 120, 420, 420); ch.restore();
          ch.strokeStyle = "rgba(255,222,180,0.42)"; ch.lineWidth = 3.5; ch.beginPath(); ch.ellipse(cx, cy - 6, rx + 8, ry + 6, 0, -1.25, 0.45); ch.stroke(); ch.restore();
        })();
})();
