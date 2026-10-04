# Changelog

All notable changes to *UNDERCITY: RIPPER*. Versions follow
`application/config/version` in `project.godot` and the Windows file version
in `export_presets.cfg`.

## 2.0.0 — Windows PC conversion (1920×1080, mouse + keyboard)

The game is now a **Windows PC game** built for **1920×1080** with **mouse and
keyboard**. All gameplay, progression, content and systems are preserved;
the presentation, input and platform layers were rebuilt for desktop.

### Platform and display
- 1920×1080 design canvas (`canvas_items` stretch, `keep` aspect): 16:9 windows scale uniformly, other aspect ratios letterbox.
- One global pixel density: 1 art pixel = 3 canvas units. Integer-perfect at 1920×1080 (3×) and 1280×720 (2×); nearest sampling everywhere, no mipmaps.
- Window modes: windowed (1920×1080, 1600×900, 1366×768, 1280×720), borderless fullscreen and exclusive fullscreen; VSync toggle; nearest/linear filtering option; effects quality LOW/MEDIUM/HIGH.
- Pixel-art hardware cursors (arrow, pointing hand, crosshair, grab) and a Windows `.ico` app icon.
- Saves and settings go to `%APPDATA%\UndercityRipper\` (`config/use_custom_user_dir`), so no admin rights are needed.

### Desktop UI (workstation layout)
- **Workstation shell** on every hub screen: a top status bar (credits, level + XP, rep, heat, supplies, parts, tokens, jobs, MENU) and a left section nav (clinic, inventory, cyberware DB, supply, skills, facility, journal, black market, settings) with hotkeys.
- **Clinic:** a wide 400×224 room rendered at 3×, a customer card on the left, status / rumours / faction cards, and **clickable room props** (diagnostics terminal → database, operating table → facility, storage bench → inventory, supply cabinet → supply, records server → journal) with hover brackets.
- **Customer file:** a three-column dossier with expandable REQUEST, PAYMENT, RISK, MEDICAL HISTORY and **PREVIOUS OPERATIONS** sections, plus a NOW vs AFTER neural-load panel.
- **Diagnosis / plan:** scanner | findings | diagnosis, then summary and checks | implant units | begin.
- **Surgery workstation** (the centrepiece): patient, vitals, ECG and the procedure checklist on the left; a large zoomable operating field in the centre; an instrument rack (icon, name, hotkey, condition, precision/speed, description), emergency actions and the implant on the right; a key-hint bar at the bottom.
- **Results:** a three-panel debrief (grade, breakdown, payout).
- **Supply:** a two-column card grid with a detail panel and CURRENT vs NEW comparison, plus instrument servicing.
- **New: Inventory.** A grid inventory with CYBERWARE / TOOLS / MEDICAL SUPPLIES / COMPONENTS / BLACK MARKET tabs, sort, text filter, hover details, double-click inspect, drag & drop reordering and two COMPARE slots.
- **New: Cyberware database.** A searchable, filterable list of every known model with a full spec sheet (rarity, price, neural load, compatibility, difficulty, effects, risks, manufacturer, origin, stock condition) and a CURRENT vs NEW table tagged **▲ Better / ▼ Worse / ? Unknown / ✕ Incompatible**.
- **Black market:** its own corrupted terminal: magenta, a rolling session header, an encrypted feed that decrypts live, the vendor panel and a signal-tear shader.
- **Skills:** four category columns side by side. **Facility:** current → next with a horizontal tier ladder. **Journal:** card grids.
- **Main menu:** NEW GAME, CONTINUE, LOAD GAME, SETTINGS, CONTROLS, CREDITS, QUIT. A new 3-slot **load / new-game** screen and a credits screen.
- **Settings:** GRAPHICS, AUDIO (now with MASTER), CONTROLS (key rebinding with conflict swap, mouse sensitivity) and GAMEPLAY (text speed, shake, large text, high contrast, reduce motion) tabs.
- **Pause menu (ESC):** resume, save, load, settings, how to play, save & main menu, save & quit to desktop.

### Mouse and keyboard
- Hover highlight and a hover sound on every button, pointing-hand cursor, cyan keyboard focus frame, and tooltips throughout.
- Surgery: left-drag to cut / move, **right-click** puts the tool down (or returns a held implant), **wheel** zooms the field 3×–6× (or rotates the seated implant / tunes calibration), field hover reticle tinted by tool state and pulsing brackets on the nearest target.
- Default keys: ESC pause/back, TAB cycle panels, WASD/arrows navigate, E interact, SPACE contextual (hold to infuse, LOCK, SEAT), F inspect, Q/R previous/next tool, 1–9 tools, Z/X/V COAG/SEDATE/STABIL, , . rotate, + − zoom, I inventory, C customer, M facility, J journal, B database, F5 quick save, F9 quick load. All rebindable.

### Gameplay additions
- **Instrument condition:** tools wear 3% per operation and lose up to 8% precision when worn out; SERVICE ALL at Supply restores them. Saved with the inventory.
- **Save slots:** 3 slots (`saves/slot_N.json`) with summaries; the old single save migrates to slot 1. CONTINUE loads the most recent slot.

### Removed or converted mobile systems
- Portrait 360×640 viewport, safe-area handling (`SafeAreaUtil`), the bottom nav bar and the phone HUD (`NavBar`, `PlayerHud`), tap/swipe wording, oversized touch targets, the iOS export preset and the iOS icon set.
- Haptics stay in the code but are hidden on PC (shown only on touch devices).
- "Suspend" pause now triggers on window focus loss (Alt-Tab / minimise).

### Tests
- The end-to-end bot runs on the 1920×1080 canvas with mouse and keyboard events (hotkeys, ESC pause, F5, TAB, right-click compare, inventory and database screens).
- New `tests/display_probe.tscn` drives the real window through all resolutions, window modes and a 5:4 letterbox, screenshots each, and checks that no button is off-screen.
- The stability monkey also sends right-clicks, wheel and random hotkeys.

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
- **Detail zoom:** double-tap the clinic for a pixel-perfect 2× view (drag to pan, double-tap to reset).
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
