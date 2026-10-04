# Changelog

All notable changes to *UNDERCITY: RIPPER*. Versions follow the iOS
`short_version` in `export_presets.cfg`.

## 1.0.0 — Production pass (Step 3)

### Added
- **Onboarding:** a 10-step tutorial on a scripted first patient. Coach marks point at the control to use and never block input. It covers diagnosis, procedure, tools, surgery, installing, finishing, payment and upgrades, and can be skipped. HOW TO PLAY is always available from the clinic pause menu.
- **Settings screen**, stored separately from the save:
  - music / ambience / effects volume
  - haptics, screen shake
  - text speed (typewriter)
  - large text, high contrast, reduce motion
- **Haptic tiers:** UI, success, warning, mistake, critical and implant, each with its own strength.
- **Soundscape:**
  - three seamless music loops (clinic, surgery, black market)
  - four ambience layers (electrical hum, ventilation, CRT buzz, distant city) mixed per screen
  - random ambient one-shots: drips, sirens, trains, servos, beeps
  - 13 new effects: monitor beep, servo, cyberware activation, flatline, confirm/back/denied, unlock, purchase, heartbeat, spark, tutorial chime
- **Clinic environments:**
  - set dressing on every tier: power systems with breaker LEDs, vents, waste bins, graffiti, warning labels, blood stains, discarded implants, instrument carts, floor cables, drains, field repairs (tape), hidden stash compartments, diagnostic carts and foreground props
  - animated from generated anchors: blinking LEDs, monitor refresh lines, ECG traces, holo shimmer, spinning vent fans, steam, sparks, drips, and the customer breathing
- **Main menu key art:** a rain-soaked undercity alley at the global pixel density, replacing the 3-unit procedural skyline.
- **Animated cyberware icons:** emissive pulse, scan glint, optics refocus, neural data flicker, limb servo glint. **Portrait eye blinks** are skipped automatically when optics cover the eyes.
- **Surgery feel:**
  - minor mistakes read amber, major ones red; correct actions get a cyan confirmation pulse
  - critical failure gets a flatline tone, hard flash and the strongest haptic
  - lamps flicker on at surgery start
  - neural signals travel along exposed nerves, and the wound flushes with each heartbeat
- **Short-screen framing:** the surgical field frames each stage's region of interest on short phones.
- **Clinic "NEXT" line**, so the player always knows what to do next.
- **Game-feel moments:** one consistent celebration for purchases, black-market buys, tool upgrades, unlocks and clinic upgrades. Newly unlocked chrome tiers are announced on the report.
- **Post-op complications:** sloppy work or hidden conditions can bring a patient back (story event).
- **Pause-on-suspend:** the operation freezes when the app is backgrounded. Abort asks first and freezes vitals while it waits.
- **App icon:** redrawn on a 60 px grid, so iPhone icons are exact 2×/3× (and 17× for the App Store). The full iOS icon set, a launch-screen image, and nearest-neighbour icon export are configured.
- **Tests:**
  - balance simulator, run for 4 player profiles
  - stability suite: soak, monkey input fuzzing, rapid navigation, save fuzzing, leak checks
  - unit tests for settings, haptics, the learning curve, save checksums, temp-file recovery and migration
  - E2E covers the tutorial, pause and resume, abort cancel, pause menu and settings

### Changed
- **Difficulty curve:**
  - tolerance assist tapers from ×1.5 to ×1.0 over the first eight jobs
  - the tutorial job has no complications, and there is at most one until job 3
  - early customers are calm, stable (neural load ≤ 45%) and have no hidden conditions
  - no random events or post-op surprises while learning
  - most jobs match the tools you own
- **Pacing:**
  - tier-2 chrome at LV3, tier-3 at LV5, tier-4 at LV8
  - the black market (Wire) arrives after job 6 at rep 18
  - reputation gains diminish as you climb, and every finished job earns some rep
  - the first clinic upgrade needs rep 3
- **Economy:** black-market sell prices are capped at 80% of the buy price, which closes a buy-low/sell-high loop.
- **Save format v3:**
  - an MD5 checksum line detects tampering and truncation
  - an interrupted write recovers from the temp file
  - a failed write shows a toast
  - v2 saves migrate: settings leave the save, and the tutorial counts as done
- **UI:**
  - dialogs with more than two choices stack vertically
  - long dialog bodies scroll
  - status is never shown by colour alone (`!` markers, `+`/`x` checks)
  - StyleBoxFlat anti-aliasing is off everywhere
- **Engine/config:** version 1.0.0 (build 3). The results screen only opens from the operating table, never yanking the player off another screen.

### Fixed
- A delayed jump to the report could fire after a surgery that ended elsewhere (headless sessions, resumes).
- An empty tween error when switching music.
- An HBoxContainer orientation error when building 3+ button dialogs.
- A probabilistic unit test (post-op risk is capped below 100%).

## 0.2.0 — Core game (Step 2)

Procedural customers, eight cyberware categories (tiers 1–5), the neural-load system, upgradeable tools, factions and heat, the black market, the skill tree, six clinic tiers, events and rumours. A detailed pixel-art pipeline at one global density, eight surgeries, save format v2 (migrates v1), and a full E2E bot.

## 0.1.0 — Vertical slice (Step 1)

One complete neural-implant operation with eight touch stages, vitals, complications, scoring, saves, placeholder art and audio.
