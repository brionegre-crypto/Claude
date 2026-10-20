// Prints a loudness-over-time strip so the sound can be checked against the picture.
import { readFileSync } from 'fs';
const b = readFileSync(process.argv[2] || 'assets/loop-sfx.wav'); const SR = 48000;
const n = (b.length - 44) / 4, win = SR / 20;   // 50 ms
let out = '';
for (let w = 0; w < n / win; w++) {
  let s = 0, pk = 0;
  for (let i = 0; i < win; i++) { const l = b.readInt16LE(44 + (w * win + i) * 4) / 32768; s += l * l; pk = Math.max(pk, Math.abs(l)); }
  const db = 20 * Math.log10(Math.sqrt(s / win) + 1e-9), bar = '#'.repeat(Math.max(0, Math.round((db + 60) / 1.6)));
  out += `${(w * 0.05).toFixed(2).padStart(5)}s ${db.toFixed(1).padStart(6)} dB pk ${(20 * Math.log10(pk + 1e-9)).toFixed(1).padStart(6)} ${bar}\n`;
}
console.log(out);
