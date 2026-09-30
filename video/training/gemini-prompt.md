# Gemini prompts: "You meant it every time" training video

Two ways to use these:

- **Option A:** paste the master prompt. Use it if Gemini can produce a long video in one go.
- **Option B:** paste the style block first, then one scene prompt at a time. Use it if Gemini makes short clips (usually around 8 seconds). Stitch the clips together in CapCut or YouTube's editor, in order.

Either way, the presenter is a fictional actor. Don't describe him as Brian, and don't upload photos of real people. The words match the narration in `script.py`.

---

## Option A: master prompt (paste as one message)

```
Create a 6-minute, 16:9, cinematic training video for Christian husbands and fathers called "You meant it every time." Brand: Be The Man. Tone: calm, direct, warm, anti-hype. A mechanism, not a mood. No music swells, no motivational-speaker energy.

PRESENTER: a fictional American man in his early 40s, short dark beard, plain charcoal henley, sleeves pushed up. Speaks slowly, low voice, like a friend across a kitchen table. He is an actor, not a real person. Keep his face, clothes and voice identical in every shot.

LOOK: dark, warm palette: near-black (#0B0B0C), charcoal, cream (#F2EEE6), amber accents (#E18B1F). Soft practical lighting (a single lamp, early-morning window light). 35mm film feel, shallow depth of field, slow push-ins, handheld only for B-roll. On-screen titles in a tall condensed sans-serif, all caps, cream with key words in amber, bottom-left, minimal.

STRUCTURE (presenter to camera, cut with quiet B-roll of ordinary family life; nobody's face lingers in B-roll):
1. Cold open (0:00): B-roll montage: New Year's fireworks seen through a window, a church parking lot on Sunday morning, a man alone in a parked car at night gripping the wheel. Presenter voiceover: "New Year's Day. A Sunday morning. The car, after the argument. You meant it every time. And by Wednesday, it was gone." Title: YOU MEANT IT EVERY TIME.
2. The Tuesday problem (0:25): presenter at a kitchen table. "You don't have a conviction problem. You have a Tuesday problem. What shows up on Tuesday at six fifteen, when you walk in tired and the house is loud, is whatever you built." B-roll: a man walking in a front door, kids' noise, phone in his hand.
3. Where promises die (0:55): three beats with titles 01 NO WHEN, 02 NO DEFINED MISS, 03 GRADED FROM MEMORY. "This week is not a time. If you never decided what counts as a miss, every bad week becomes a negotiation you win. And Sunday-night memory is a story, not evidence."
4. The line (1:32): title A GOAL SAYS WHAT. A SYSTEM SAYS WHEN.
5. The wife test (1:42): B-roll of a husband quietly doing dishes while his wife notices from the doorway. Presenter: "Would your wife be able to tell? Not because you announced it. At dinner. At bedtime. On an ordinary Tuesday."
6. The step before goals (2:06): "You can't build a system for a man you haven't described." Title: WHAT TYPE OF MAN DO YOU WANT TO BE?
7. Four moves (2:44): overhead shot of a man's hands writing in a notebook with a pen, phone face-down and pushed away. Titles appear one by one: 1 NAME THE ATTRIBUTES, 2 MAKE EACH ONE ORDINARY, 3 RUN THE HOUSE TEST, 4 WRITE THE SENTENCE.
8. The sentence (3:19): close-up of handwriting: "I am a man who is home when he is home, keeps his word to his wife, and lets his kids see him pray." Then a crossed-out line: "I want to be a better husband and father."
9. The framework (3:42): presenter lists the seven steps; the steps appear as a clean list: what type of man, goals, what stopped you, the laws of a system that holds, the four pillars, why you need a system, God at the center. Ends on a man praying quietly at dawn with coffee.
10. Tonight (4:32): three titles: THE TIME: tonight, twenty minutes. THE TRIGGER: the last light off, phone in another room. THE TEST: could someone in your house notice without being told?
11. Call to action (4:50): end card on black: GET THE STEP 1 WORKSHEET, FREE, go.bethemansystem.com/framework. Then: THE BE THE MAN CLUB. Founding members $12 a month.
12. Close (5:30): presenter, quiet: "You don't need more conviction. You meant it every time. Start with the sentence. Tonight, if you can." Final title: BREAK THE CYCLE. BUILD THE SYSTEM. BE THE MAN.

Audio: presenter's voice only, clean and close-miked, low room tone, a very sparse piano or ambient pad under the B-roll at low volume. No stock-music drama.
Avoid: logos of real companies, readable phone screens, crowds, preachy delivery, text errors (keep on-screen text short and exactly as written).
```

---

## Option B: scene-by-scene (for short clip generators)

**Paste this style block before every scene** (or once, if Gemini keeps context in the chat):

```
Style for every clip: 16:9, cinematic, 35mm film look, shallow depth of field, dark warm palette (near-black, charcoal, cream, amber lamp light), slow camera moves. Presenter (when shown): the same fictional American man, early 40s, short dark beard, charcoal henley, calm low voice, speaking to camera at a wooden kitchen table lit by one warm lamp. No music unless stated, no on-screen text unless stated, no real brands or readable screens.
```

Then generate each clip (about 8 seconds):

1. **Cold open, fireworks.** Through a dark living-room window, distant New Year's fireworks; a man's silhouette watching, still. Voiceover (presenter): "New Year's Day."
2. **Church lot.** Sunday morning, a man sitting in his car in a church parking lot, engine off, looking ahead. Voiceover: "A Sunday morning, somewhere between the sermon and the parking lot."
3. **The car.** Night, a man alone in a parked car in a driveway, hands on the wheel, the house lights on behind him. Voiceover: "The car, after the argument. You meant it every time."
4. **Title card.** Black screen, tall condensed cream letters fade in: "YOU MEANT IT EVERY TIME." with "EVERY TIME" in amber. Silence, then a low room tone.
5. **The Tuesday problem.** Presenter at the kitchen table, slow push-in. He says: "You don't have a conviction problem. You have a Tuesday problem."
6. **Walking in.** A man walks through a front door at dusk, tired, phone in hand, kids' voices off-screen. Voiceover: "Tuesday at six fifteen. The house is loud. What shows up is whatever you built."
7. **No when.** Close-up of a wall calendar with a week that has nothing written in it; a pen hovers. Presenter voiceover: "'This week' is not a time."
8. **The wife test.** Warm kitchen, a husband quietly washing dishes; his wife pauses in the doorway and notices, a small smile. No dialogue. Presenter voiceover: "Would your wife be able to tell?"
9. **The question.** Presenter leans forward: "What type of man do you want to be? Not what you want to do. Who you want to be. On an ordinary Tuesday."
10. **Writing.** Overhead shot: a man's hands writing in a notebook with a pen, phone face-down pushed to the edge of the table, coffee mug. Soft lamp light. No voice.
11. **The sentence.** Macro close-up of handwriting appearing in the notebook: "I am a man who is home when he is home." Voiceover reads it slowly.
12. **Prayer at dawn.** A man sitting on a back porch at sunrise, head bowed, coffee beside him. Very sparse piano. Voiceover: "God at the center."
13. **The drawer.** A man puts his phone in a kitchen drawer and closes it, then turns toward his kids (backs to camera) at a dinner table. Voiceover: "Tonight. Twenty minutes. Phone in another room."
14. **Bedtime.** A father sitting on the edge of a child's bed in a dim room, lamp on, listening (child out of focus). No dialogue.
15. **Close.** Presenter, quiet, to camera: "You don't need more conviction. Start with the sentence. Tonight, if you can."
16. **End card.** Black screen, cream condensed text: "BREAK THE CYCLE. BUILD THE SYSTEM. BE THE MAN." with a thin amber line above it. Hold for 4 seconds.

**Put together:** clips 1–4 open the video. Then alternate presenter clips (5, 9, 15) with B-roll (6–8, 10–14). For the finished video, lay the existing narration (`out/narration.wav`, or your own recording) over the B-roll, and use the slides from `be-the-man-training.mp4` for the text-heavy parts (four moves, seven steps, links). AI video generators are unreliable with long on-screen text, so keep URLs and prices on the real slides.
