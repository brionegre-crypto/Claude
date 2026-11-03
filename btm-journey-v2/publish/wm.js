/* draws the real Be The Man wordmark (from the sting engine) into a canvas at a chosen width */
function drawWordmark(canvas, width) {
  var M = window.Motion, sc = M.create('orbit', { targetW: width, comp0: 0.05 }), big = document.createElement('canvas'); big.width = 1920; big.height = 1080;
  var c = big.getContext('2d'); M.drawScene(sc, c, M.T.still + 0.0);
  var h = Math.round(width * 0.13), y0 = Math.round(sc.bottom - h * 1.02), x0 = Math.round(960 - width / 2 - 14);
  canvas.width = width + 28; canvas.height = h + 6; canvas.getContext('2d').drawImage(big, x0, y0, width + 28, h + 6, 0, 0, width + 28, h + 6);
}
