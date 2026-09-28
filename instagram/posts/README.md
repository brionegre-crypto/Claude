# @bethemansystem post images

Ready-to-upload PNGs are in `out/`, and `bethemansystem-posts.zip` has all of them in one download. The captions are in `../bethemansystem-playbook.md` under "Canva designs → Captions". Each post here uses the matching caption (same numbers).

| File | Size | Use |
|---|---|---|
| `01-step-1.png` | 1080×1350 | Feed; pin it |
| `02-meant-it.png` | 1080×1350 | Feed |
| `03-system-when.png` | 1080×1350 | Feed; pin it |
| `04-wife-test.png` | 1080×1350 | Feed |
| `05-club.png` | 1080×1350 | Feed; pin it |
| `carousel-1-cover.png` … `carousel-6-cta.png` | 1080×1350 | One carousel post, 6 slides, in order |
| `story-step-1.png` | 1080×1920 | Story. Add a link sticker to `go.bethemansystem.com/framework` in the empty space at the bottom |
| `highlight-*.png` | 1080×1920 | Story Highlight covers (Start, Free, System, Home, Club, Faith) |

**Carousel caption:**
```
How to stay disciplined when motivation runs out. 💾 Save this for Sunday.

1. Write the when. "This week" is not a time.
2. Define the miss before the week starts.
3. Log it the day it happens. Memory is a story, not evidence.
4. Run the wife test. Could she see it without you announcing it?

Missing once is not failure. One bad day shouldn't cost you a month.

👇 Comment "STEP1" and I'll send you the free worksheet.

#mensdiscipline #howtostaydisciplined #christianmen #godlyhusband #bethemansystem
```

To change any text, edit `build.mjs` and run `node build.mjs`. It needs Node and Playwright.

## Club portal promo video

Two 43-second, silent walkthroughs of the members' portal. A finger taps through Start here → the framework (Step 1 download) → the member library (marriage tools) → the brotherhood (writing a first post). Captions sell each benefit, and it ends on a $17/month call to action.

| File | Size | Use |
|---|---|---|
| `out/reel-club-portal.mp4` | 1080×1920 (9:16) | Instagram Reel / Story, YouTube Shorts, TikTok. Ends on "link in bio" |
| `out/youtube-club-portal.mp4` | 1920×1080 (16:9) | YouTube video, website embed. Ends on "link in the description" |

The phone screens recreate the real portal (same modules, lesson names and copy) in HTML; they are not a screen recording. Add music or a voiceover in Instagram, YouTube or CapCut.

Rebuild: `node reel.mjs` (9:16) or `node reel.mjs --yt` (16:9). The ffmpeg with H.264 comes from `pip install imageio-ffmpeg`. Pass seconds for stills to check (`node reel.mjs --yt 5 20`). The scene and timeline are in `reel-club-portal.html`.
