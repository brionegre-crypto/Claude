# Free training video: "You meant it every time"

`../out/be-the-man-training.mp4` is 1920×1080, 5 min 50 s, narrated. It has 15 slides that build line by line as the narrator speaks.

- **Narration:** a stock text-to-speech voice (Piper "en-us-ryan-high"). The narrator speaks for Be The Man and never claims to be Brian.
- **Arc:** three moments you meant it, then "not a conviction problem, a Tuesday problem", then the three places promises die, then "a goal says what, a system says when", then the wife test, then the step before goals ("What type of man do you want to be?"), then four moves plus an example sentence, then the seven steps, then tonight's time, trigger and test. It ends with the free Step 1 worksheet, then the Club at $12 (founding), then the tagline.

## YouTube upload

**Title:** You meant it every time: why good men keep breaking the same promise

**Description:**
```
Men don't have a conviction problem. We have a Tuesday problem.

In six minutes: the three places every broken promise dies, the one test more honest than any habit tracker, and the question that has to come before your next goal.

Get the free Step 1 worksheet: https://go.bethemansystem.com/framework
Join the Be The Man Club (founding price, $12/month): https://go.bethemansystem.com/d6dd7931

0:00 You meant it every time
0:25 A Tuesday problem
0:55 Where promises die
1:32 A goal says what, a system says when
1:42 The wife test
2:06 The step before goals
2:44 Four moves to answer it
3:19 What a good sentence sounds like
3:42 The seven-step framework
4:32 Your assignment tonight
4:50 The free Step 1 worksheet
5:07 The Be The Man Club

Break the cycle. Build the system. Be the man.
```
Chapter times match the slide changes in the rendered file.

## Rebuild

```
pip install piper-tts imageio-ffmpeg
# voice: https://github.com/rhasspy/piper/releases/download/v0.0.2/voice-en-us-ryan-high.tar.gz
VOICE=/path/en-us-ryan-high.onnx python3 tts.py   # narration + timeline (edit script.py to change words)
node render.mjs --stills                            # one PNG per slide for checking
node render.mjs                                     # full video -> out/be-the-man-training.mp4
```
The on-screen text lives in `training.html`. Each element's `data-b` is the narration line (beat) it appears on.
