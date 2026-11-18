# unrealagency.ai — Home version 1 (Nami hero, approved by Gael on 2026-11-18)

This version of the Nami hero on the homepage is the reference: smooth on PC and phone, no flash, no ghost arm, no stop mid-kiss.
Saved on GitHub as the branch `home-v1` (never changed afterwards). To restore the hero: `git checkout origin/home-v1 -- index.html live/`.

## The files (all in `live/`)

| File | What it is |
|---|---|
| `nami_start.jpg` | Still shown while the page loads. It is the opening kiss's own first frame, colour-matched to how browsers draw the video. |
| `nami_kiss_auto.mp4` | Opening kiss (4.4 s, plays once by itself). Starts at 0.6 s of the original kiss, so it begins with a short still lead-in. |
| `nami_idle.mp4` | Breathing loop (9.5 s, loops forever). |
| `nami_kiss_btn.mp4` | "Blow a kiss" button: the full kiss (5.0 s). |
| `nami_hat_b.mp4` | "Construction la semaine" button: captain hat, brightened to the loop's exposure. |
| `nami_under.jpg` | Still of the breathing pose kept under the videos, so the page never shows through. |
| `nami_kiss.mp4`, `nami_hat.mp4` | Originals the clips above were made from (not used by the homepage). |

## How it plays

1. The page head starts downloading the opening kiss as one whole file (phones do not pre-load video and would stop mid-kiss).
2. When it is downloaded, the kiss fades in over `nami_start.jpg` during its own still lead-in (same picture, so nothing jumps).
3. The breathing loop downloads during the kiss and waits paused at the hand-back point.
4. Every action clip ends with a built-in blend into the first frames of the breathing loop (8 frames for the kisses, 10 for the hat).
   The loop resumes from exactly that frame: no seek at the hand-back (a seek can draw an empty frame = colour flash).
5. Button clips download whole 6 s after the page opens. A button press fades the clip in over the loop (0.42 s), never during a blink.

## Rules that keep it perfect (for any new button)

- A new action clip must end with the same blend into `nami_idle.mp4` frames 0..N, and get its `HAND` value (N/24 s) in `index.html`.
- Encode like the others: H.264 High, 1080x1440, 24 fps, `-crf 21 -tune film -g 24 -movflags +faststart`, no audio track.
  Blend in YUV (not RGB) so the colours stay identical.
- Check its colour against the loop (wall and skin) and correct it if it is darker or warmer, like the hat.
- The soft edges (light mode) are cut once on `.head`, never on the photo or the videos themselves (that showed a ghost arm).
- Keep the still under the videos and the videos on their own layers (`will-change`).

---

# Home version 1.1 (approved by Gael on 2026-11-18) — current reference

Saved on GitHub as the branch `home-v1.1` (never changed afterwards). To restore the hero: `git checkout origin/home-v1.1 -- index.html live/`.
Everything above still applies, plus:

- **Keeps breathing after leaving and coming back** (Safari iPhone, Chrome): a watchdog every 0.8 s restarts a paused loop,
  reloads a frozen one at the same spot, resumes a clip paused mid-way, and hands back to the loop if an action is stuck > 20 s.
- **PC only (mouse + hover): one canvas.** The videos are drawn into a single canvas (`.nvc`), so Mac Chrome/Safari never switch
  colour path between photo and video (that was the tiny colour flash on open and sometimes at the end of the kiss).
  On PC the still photo is not shown: Nami fades in on the kiss clip's own first frame. The canvas is never cleared, so a missing
  video frame keeps the last good picture. If nothing can be drawn after 5 s, the photo is shown. `?mode=video` turns the canvas off.
- **Phones are unchanged** (plain videos, as in v1).
