# Generates the narration with Piper (voice: en-us-ryan-high) and writes
# out/narration.wav plus out/timeline.json (start time of every beat).
# Usage: VOICE=/path/en-us-ryan-high.onnx python3 tts.py
import json, os, subprocess, sys, wave
sys.path.insert(0, os.path.dirname(__file__))
from script import SLIDES

VOICE = os.environ["VOICE"]
OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(os.path.join(OUT, "beats"), exist_ok=True)
LEAD, BEAT_GAP, SLIDE_GAP, TAIL = 1.2, 0.5, 1.1, 3.0

frames, rate, t, timeline = [], None, LEAD, []
def silence(sec):
    return b"\x00\x00" * int(rate * sec)

for si, slide in enumerate(SLIDES):
    beats = []
    for bi, text in enumerate(slide["beats"]):
        path = os.path.join(OUT, "beats", f"{si:02d}-{bi}.wav")
        if not os.path.exists(path):
            subprocess.run([sys.executable, "-m", "piper", "-m", VOICE, "-f", path,
                            "--length-scale", "1.15", "--sentence-silence", "0.35"],
                           input=text.encode(), check=True, capture_output=True)
        with wave.open(path) as w:
            rate = rate or w.getframerate()
            data = w.readframes(w.getnframes())
            dur = w.getnframes() / w.getframerate()
        beats.append({"start": round(t, 3), "dur": round(dur, 3)})
        frames.append((t, data))
        t += dur + BEAT_GAP
    t += SLIDE_GAP - BEAT_GAP
    timeline.append({"layout": slide["layout"], "start": beats[0]["start"], "beats": beats})
total = t + TAIL

# lay beats onto one silent track
buf = bytearray(silence(total))
for start, data in frames:
    i = int(start * rate) * 2
    buf[i:i + len(data)] = data
with wave.open(os.path.join(OUT, "narration.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(bytes(buf))
json.dump({"total": round(total, 3), "slides": timeline}, open(os.path.join(OUT, "timeline.json"), "w"), indent=1)
print(f"{len(frames)} beats, {total/60:.1f} min")
