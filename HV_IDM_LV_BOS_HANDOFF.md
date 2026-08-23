# HV/IDM/LV/BOS Indicator — Handoff / Continuation Prompt

Paste this whole document as your first message to a new Claude Code session
(same repo, same branch) to resume this work without re-deriving everything
from scratch. Written because the previous session ran out of usage limit
mid-fix.

## Project context

`fx-mt5-ai-onnx-ea` — MT5 AI-assisted EA project. See root `CLAUDE.md` for
the full project charter. Hard rule for this specific task: **no halu**.
Every rule below must be verified against the real CSV data
(`test-data/XAUUSDm_M5_20260820-21.csv`, XAUUSDm M5, 20-21 Aug 2026, 384
candles) with a throwaway Python script *before* touching the `.mq5` file.
Do not guess and push — the user has burned a lot of turns on fixes that
looked right in isolation but broke a different, already-validated point
elsewhere. Verify against the full ground-truth table below every time.

Repo: `ayahucubo/fx-mt5-ai-onnx-ea`. Branch: `claude/m5-data-august-20-21-yq8yoq`
(already has commits — do not create a new branch). Indicator file:
`HV_IDM_LV_BOS.mq5` at repo root. **The user wants every change PR'd and
merged immediately (not just pushed)** — they said explicitly "PR Merge
jangan hanya push, karena ini hanya kita saja yg pakai" (only the two of
you use this repo, so skip waiting for review).

There is also `MQL5/Indicators/SMC_MarketStructure.mq5` — an OLDER,
different attempt the user explicitly said was **wrong** (built without
real sample data to check against) and should be ignored/left alone.
`HV_IDM_LV_BOS.mq5` is the one being worked on.

## The concept (bullish bias; bearish is the mirror image)

- **candidate** (internal only, never drawn) — simply the running highest
  high since the current leg started. It extends on *any* bar whose high
  exceeds it. **It does NOT need to be a fractal-confirmed peak** — this
  was tried (requiring the candidate itself to survive an N-bar-forward
  fractal check) and it broke real cases where a genuine turning point was
  beaten by a hair (0.03–0.4 points) a few candles later after a clear
  pullback had already happened in between. Confirmed by the user: the
  candidate should just keep extending; only the IDM side needs fractal
  filtering.
- **IDM (Inducement)** — the lowest **fractal-confirmed** swing low since
  the candidate's last update. Shown "live" the moment a genuine pullback
  low forms (before knowing whether it'll get swept). It gets **locked in**
  (replacing whatever was locked before — older ones stop mattering
  instantly) the moment the candidate ticks to a new higher high. The
  fractal check's backward-looking side must be clipped so it never
  crosses before the bar where the *current* leg's candidate tracking
  started (`candidate.idx` at the time, which moves forward every time the
  candidate updates) — otherwise a pivot check reaches into an unrelated
  older leg's price action and gets wrongly disqualified, or a real peak
  from way earlier lets a shallow neighbor pass as "genuine." This part
  (`IsPivotLowClipped` in the current file) was validated repeatedly and
  should very likely stay as-is — the candidate side is what kept needing
  rework.
- **HV (High Valid)** — confirmed the instant any candle's LOW wicks below
  the currently *locked* IDM (wick only, no close needed). HV's price is
  the candidate's price at that moment (which may have been set several
  candles earlier — the candidate keeps running silently until the swap
  happens, sometimes for hours, e.g. leg 2 below).
- **LV (Low Valid)** — after HV confirms, track the running lowest LOW
  since HV; a reference level starts at HV's own price. Any candle whose
  HIGH wicks above the reference without closing above it **raises** the
  reference to that wick's high (a "swap" — this is a real, confirmed
  mechanic, not a guess). The first candle whose CLOSE closes above the
  (possibly raised) reference confirms BOS; LV = the lowest low reached
  since HV up to that point. **Crucially: once HV is confirmed, do NOT
  keep tracking new "candidate" highs or new IDM locks during this
  phase** — any higher wick here is purely a rejected annotation (see BCH
  below) that only matters for ratcheting the BOS reference, nothing else.
- **BCH / BIDM** ("Bukan CH" / "Bukan IDM") — cosmetic-only rejected-point
  annotations the user's own reference chart shows, confirmed **not** to
  affect the state machine:
  - During the seek-HV phase: a fractal high that doesn't exceed the
    current candidate is BCH; a fractal low that isn't deeper than the
    current live shadow is BIDM. Neither needs to be drawn by the
    indicator (current file doesn't draw them) — they're just noise the
    user's manual reference marks for clarity.
  - During the seek-LV phase (after HV confirmed, before BOS): **any**
    higher high or lower low here is BCH/BIDM too — explicitly confirmed
    by the user: "Nah sebelum 08:15 ini ada candle BCH 07:20 yg lebih
    tinggi dari HV01... Abaikan semua karena belum ada Low Valid." I.e.
    don't let these create a new candidate/IDM pair; they're irrelevant
    until BOS actually fires.
- **Display rule (confirmed, already implemented and should stay)**: only
  draw the *latest* state — live IDM (as a line extending to the current
  bar, plus a text label, no ordinal number since it can still move before
  locking), the last **fully closed** HV+LV+BOS as one matched triplet
  (never show a brand-new HV next to a stale LV from a different,
  already-closed leg), and if the very latest HV has already been
  confirmed via IDM sweep but its own LV/BOS hasn't happened yet, draw it
  separately as "HV (pending)" in a distinct color so it's visible without
  being falsely paired.
- **Bias**: `InpBias` input (Bullish/Bearish), implemented via a sign-flip
  transform (`Hi = bull ? High : -Low`, `Lo = bull ? Low : -High`, `Cl =
  bull ? Close : -Close`) so one code path serves both directions — this
  part is solid, don't rewrite it.
- **CHoCH** (automatic bias flip on a body-close through the opposite
  structure) is explicitly **not implemented yet** — the user deferred it
  on purpose to get the fixed-bias version right first. Do not add it
  unless asked.

## Ground truth (verify every change against ALL of these, not just the one you're fixing)

All times are 21 Aug 2026, XAUUSDm M5. This table is the *latest, corrected*
version after several rounds of the user re-checking their own hand-drawn
reference against real price (earlier rounds had OCR/eyeballing slips —
e.g. "CH02 04:40" was actually 04:30, "CH03 05:05" was actually 05:55 —
trust the price values over any time label if they ever conflict, then
double-check against the CSV directly).

| Point | Time | Price | Note |
|---|---|---|---|
| CH01 | 01:35 | 4543.936 | first candidate seed |
| IDM01 | 02:10 | 4518.101 | |
| CH02 | 04:30 | 4548.160 | |
| IDM02 | 05:30 | 4529.256 | |
| CH03 | 05:55 | 4556.374 | |
| IDM03 | 06:10 | 4545.375 | |
| IDM03B | 06:40 | 4560.305 | pullback during the climb from IDM03 toward the eventual HV01 peak |
| **HV01** | **06:55** | **4567.784** | confirmed via IDM03B (06:40) getting swept |
| **LV01** | **07:10** | **4558.344** | this same candle's low is what sweeps IDM03B, confirming HV01 AND starting LV tracking in one move |
| (rejected, ignore) | 07:20 | 4567.963 | BCH — higher than HV01 but no LV yet, doesn't matter |
| (rejected, ignore) | 07:35 | 4559.995 | BIDM01A |
| (rejected, ignore) | 07:45 | 4568.229 | BCH |
| (rejected, ignore) | 08:05 | 4559.006 | BIDM01B |
| BOS1 | 08:15 | close 4572.440 | body close > HV01 (4567.784) |
| IDM (leg2) | 08:35 | 4576.557 | |
| **HV02** | **11:35** | **4604.593** | candidate silently climbed here from ~09:15 with no new locked IDM in between; confirmed via a swap much later |
| **LV02** | **12:40** | **4563.321** | |
| BOS2 | 15:40 | close ≈4609.429 (reference may have ratcheted higher first) | |
| IDM (leg3) | 16:05 | 4609.101 | |
| IDM (leg3, later) | 16:25 | 4610.440 | forms after a higher candidate at 16:20 (4620.953) even though 16:35 (4620.988) is marginally higher still — the candidate just keeps running, per the "no fractal gate on candidate" rule |
| **HV03** | **17:05** | **4632.130** | confirmed later (a candle around 20:45 finally dips below the leg-3 IDM) — **still pending (no LV3/BOS3) within this dataset**, should show as "HV (pending)" |

**⚠️ STATUS AS OF HANDOFF: the user said "masih salah" (still wrong) after
the fix that made HV01/LV01/IDM(16:25) above all match.** The previous
session ran out of quota before getting a fresh screenshot of what's
*still* incorrect. **Your first move should be asking the user for a new
screenshot of the live MT5 chart (with the current commit compiled) and/or
which specific point is now wrong** — don't guess blindly again. Given the
history below, plausible remaining suspects: something in leg 2 or leg 3's
intermediate IDM handling, the BOS2 ratchet level, the "pending HV3" not
displaying/positioned correctly, or a compile/attachment issue unrelated to
logic (worth ruling out first — ask what indicator name shows in the
chart's top-left corner and whether it matches `HV/IDM/LV/BOS (bull)`).

## Dead ends already tried — don't repeat these

1. **Fixed N-bar fractal gate on the candidate itself** (N=2 or N=3,
   symmetric or leg-aware-backward-clipped) — always breaks *some* region:
   too narrow lets noise through (e.g. 08:40 in an earlier, now-superseded
   version of the reference), wide enough to filter that rejects genuine
   peaks beaten by a hair later (16:20 vs 16:35, 06:55 vs 07:20).
2. **Continuous candidate + shadow backward-clip tied to the *last locked
   IDM's* index** (instead of `candidate.idx`) — fixes leg-boundary
   contamination in some spots but then a stale, very-low leg-start/BOS
   candle can block genuine nearby pivots from ever registering (seen with
   15:40's low blocking 16:05 in leg 3), and legs can get completely stuck
   with no IDM ever locking.
3. **The currently-deployed model** (continuous candidate, no fractal
   gate; shadow fractal-confirmed with backward clip tied to `candidate.idx`,
   which moves every candidate tick) is the one that matches the full
   ground-truth table above **except for whatever the user is now saying
   is still wrong** — this is the strongest baseline so far, don't revert
   past it without a documented reason.

## Recommended workflow for the next session

1. Read this file, then read `HV_IDM_LV_BOS.mq5` and `test-data/XAUUSDm_M5_20260820-21.csv`.
2. Ask the user what's currently wrong (fresh screenshot + which label).
3. Reproduce the state machine in a throwaway Python script (there's
   precedent for this pattern in the git history / this doc's ground-truth
   table) reading the CSV directly, and check it against every row in the
   ground-truth table above before touching the `.mq5` file.
4. Only port a change to MQL5 once the Python version matches 100% of the
   table (or the user has explicitly told you a table row was wrong and
   given the correct value).
5. Commit, push, then use the GitHub MCP tools to open a PR against `main`
   and merge it immediately (per the user's standing instruction — no need
   to wait for review on this repo).
6. Tell the user plainly what changed and ask them to recompile in
   MetaEditor and re-check the live chart — you cannot compile/run MQL5
   yourself in this environment.
