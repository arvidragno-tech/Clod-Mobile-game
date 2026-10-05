# Changelog

All notable changes to *UNDERCITY: RIPPER*. Versions follow
`application/config/version` in `project.godot` and the Windows file version
in `export_presets.cfg`.

## 3.1.0 — The world reacts

The clinic is no longer CUSTOMER → SURGERY → MONEY → NEXT. People remember
you, staff have lives, the clock moves, the city changes, and the black
market and the law push back. Nothing was rebuilt; every 3.0 system is
still there and now feeds into the rest.

### Living customers
- Everyone who walks in is kept as a person: traits (nervous, desperate, arrogant, paranoid, cyberware-dependent, greedy, loyal, distrustful, compassionate, aggressive, ashamed, proud), finances (desperate … wealthy, criminal or corporate money), relationship, visits, what they paid and owe, their chrome and who they know.
- They come back on their own schedule, changed: richer or poorer, a new scar, chrome from someone else, a new crew or job, the implant you put in. The customer file shows SINCE LAST TIME and THEY REMEMBER.
- Memory tags (saved me, refused me, overcharged me, gave me a discount, killed my friend, betrayed my crew, kept my secret, failed the operation...) shift relationships and five reputation dimensions, and come up in conversation.
- Payment terms: full price, discount, free, overcharge, pay later, backer pays. What they can't cover becomes a patient debt: demand, payment plan, write off, send a fixer, or trade for a favour (repaid with supplies, parts, cash or a supplier lead).
- Referrals link people; friends remember deaths; hostile patients warn others away; loyal ones bring friends (sometimes with crew colours).

### Staff lives
- Families, money troubles, fears and dreams; bonds between colleagues (friendly, professional, suspicious, competitive, resentful, loyal, fearful, respectful, involved).
- Life events in COMMS with choices: a sick father, a loan shark at the door, an ethical objection to unregistered chrome, a prototype they want in their own head, burnout, an argument, a rivalry, a romance and its end, a partner in corporate security, crew colours in the waiting room.
- Friends steady each other's hands, grudges cost focus; partners defend each other after a death; rivals resent raises.

### Time and day / night
- A clock from 09:00 to 04:00 moved by what happens (arrivals, 20-minute routine jobs to two-hour neural work, triage). Morning, day, evening, night and late night change who walks in, which incidents happen, supply and black-market prices, staff (night owls), the room's light and the ambience.
- Timed appointments: the supplier's van, an inspection when heat is up, a midnight deal, a 02:00 emergency. TODAY agenda and clock in the room; procedure durations on the customer file.

### The clinic, alive
- Waiting room: walk-ins sit down while you work, talk, complain, fall asleep, give up and leave (and remember); rival crews make a scene.
- Clinic life vignettes as the hours pass, some with small effects.
- The Clinic Wall: notes, photos of regulars, names of the dead, clippings, wanted notices, faction marks, pinned in the room and in the journal (WALL).

### The city
- Situations that last days: gang war, manufacturer recall (your patients come back), MedBoard inquiry, district takeover, a missing fixer, a port strike, a tram crash, a corporate program, blackouts, someone you know in trouble.
- A news ticker in the room and a NEWS tab; the wire reacts to the clinic (bodies piling up, clean hands, gang-linked clinic, sweeps, charity, price gouging) and to what the street calls you.

### High stakes
- Surgical dilemmas that stop the table: neural rejection, unknown firmware, internal bleeding, cyberware instability, unexpected nerve damage, foreign device. Push through, stop, change procedure, another tool, call a ripperdoc in, go experimental, or risk the patient, with odds and risk shown.
- Emergency triage with a countdown: stabilise, operate, call a specialist, experimental rig, premium chrome, refuse. Wait too long and they crash, then die.
- Cyberware dependency: feed it, profit from it, a safer unit, or stabilise without chrome; feeding it to the limit ends in a crisis.

### The black market, deeper
- Six contacts you find through customers, staff, fixers, factions, quests and favours: a scavenger, a military quartermaster, a corporate leak, a street dealer, an experimental broker, a fixer.
- Ten categories (stolen, military surplus, experimental, restricted equipment, illegal pharmaceuticals, counterfeit, salvaged, prototype, rare tools, unknown tech) and seven grades, risks stated on every offer.
- Trust unlocks discounts, credit (pay after three jobs), emergency delivery at any hour, rare items and secret stock; suspicion and unpaid credit get you cut off. Favours: treat someone, hide a patient, deliver, store contraband, repair, keep a secret.
- Unidentified devices: install blind, analyse, sell, keep, or give to the Curator. Prices drift daily and bend with the hour, heat and the city.

### Threats
- Heat levels LOW / MEDIUM / HIGH / CRITICAL: surveillance, interrogation (cooperate, stay silent, bribe), confiscation orders (hand over, hide, bribe, become an informant). No combat.
- Night break-ins take real things (cash, chrome, supplies, parts, records, instruments). Cases: check the cameras, question staff, ask around, confront a suspect; the right one returns most of it, the wrong one remembers being accused. Staff thefts of chrome start the INSIDE JOB quest.

### Identity, audio, saves
- What the street calls you is inferred from what you do (the saint of the Sump, the gang doc, the chrome fence, the corporate contractor, the chrome shark, the clean surgeon, the butcher), and your reputations decide who comes and how much heat you draw.
- Reactive audio: the ambience shifts with the hour and with tension; the music closes in on quiet nights and opens up when things go wrong.
- Save format v5 (v4 saves load; old patients become people you've met).

## 3.0.0 — The Underground: characters, clinics, staff, story

A large continuation of the PC game. Nothing was rebuilt from scratch; the
surgery, cyberware, inventory, factions, black market and progression all
carry over and now sit inside a business, a city and a story.

### Visual identity: dark, grimy, underground
- Seven new clinic interiors (400×224, lit per pixel) with a grime pass: water streaks from leaking joints, rust runs, mould, scuffed paths to the table, trash, used syringes, bloody gauze, stained drapes, waste bags. Props: dead and dying CRT stacks, encrypted terminals, coolant leaks wrapped in tape, sharps boxes, stained mattresses, chain hoists, tarp walls, limb racks, caged sodium lamps, flickering fluorescent tubes.
- Far less neon: most light is dirty tungsten, sodium or cold fluorescent; signage is a single half-dead sign; cabinets and tanks dimmed.
- City map of Caldera: procedural rooftops per district palette, the ring wall, the canal and the drowned edge.

### Characters (primary pillar)
- New part-based character art: 96×112 layered portraits and 40×80 skeleton-based bodies (4 builds × 4 postures), 18 outfits, 14 hair styles, 18 face cyberware pieces, 19 accessories, scars, tattoos, piercings, makeup, expressions and gaze, palette-indexed materials (skin, synthetic skin, metal, leather, fabric, grime, blood).
- Appearance rules per occupation and faction with restrained group palettes (corporate, gang, workers, medical, black market, military); generated customers read as their job at a glance.
- Story cast of ten with background, motivation, arc, relationships, speech style, silhouette and cyberware; appearance changes persist (a lost eye becomes an optic, faction colours, wealth, skill).
- Animation: one ticker for blinking, gaze, breathing, tremor, smoking, checking cyberware, fidgeting, glancing and cyberware flicker on portraits and in-room bodies.

### Clinics, upgrades, business, districts
- Seven purchasable clinics, each with price, rent, running cost, customer pool (district), reputation, security, staff capacity, jobs per day, upgrade slots and Undermarket access. Own several, move between them, sell them.
- Six upgrade categories (surgery, diagnostics, security, black market, staff, customer facilities) × 3 levels; every level is a pre-lit overlay sprite that visibly changes the room and carries its own animation anchors.
- Business days: a job capacity per day, CLOSE FOR THE NIGHT, nightly rent / running costs / upkeep / salaries, debt with interest, a night report, and a BUSINESS screen (categorised ledger, profit chart, obligations, pay or borrow).
- Seven districts (Sump, Furnace Line, Glow Strip, Velvet Tier, Old Caldera, Meridian Heights, Lyra Exclusion Zone) shape who walks in and which incidents happen; CITY MAP screen.
- New faction: Lyra Biocomp.

### Staff
- Hiring board shaped by district; seven specializations; stats, salary, personality, ethics (no minors, no black-market chrome, no corporate work), visible and hidden traits (informants, gamblers, stim users, ambitious, loyal...), loyalty, stress, ambition and relationships.
- Customer file: PERFORM SURGERY YOURSELF / ASSIGN RIPPERDOC (live odds and refusals in their own words; insist at a loyalty cost) / DEFER / REFUSE.
- Nightly growth and wear: burnout, raise requests, quitting, informants caught on camera, theft from the till; staff run your other clinics; skill shows on their look (coat, loupe, precision optics). STAFF screen.

### Story
- Five acts (SURVIVAL, REPUTATION, POWER, CONSPIRACY, CONSEQUENCE) driven by beats, 23 branching conversations (138 nodes), persuade / intimidate / bribe / empathy / lie / negotiate / refuse checks with odds from who you are and who you're talking to.
- Dilemmas with consequences that land days later; seven endings (respected, kingpin, corporate, network, investigator, creator, feared).
- Dialogue panel: 5× animated portrait with name, occupation, faction and relationship status; expressions follow each line; voice blips; tagged choices.
- 21 quests across main, side, staff, customer, faction, black market and clinic; comms inbox with messages, calls, emails, encrypted drops and contracts. Journal: QUESTS, COMMS, PEOPLE, FACTIONS, RUMORS, PROGRESSION, STORY.

### Settings, controls, audio
- Graphics: frame-rate limit, integer or fit pixel scaling, CRT filter, scanlines, shake intensity, lighting and particle quality, glow, environment effects (plus window mode, resolution, VSync, filtering).
- Audio: six real buses (Master, Music, SFX, Ambient, Dialogue, UI); every slider drives its own bus. New darker industrial music, a pump-station ambience layer, a near-silent dialogue mix, voice blips and a comms chime.
- Controls: ten categories, two slots per action, keyboard and mouse-button bindings, context-aware conflict detection with SWAP / KEEP BOTH, reset per action and reset all; menus follow movement bindings.
- Gameplay: auto-advance dialogue, confirm dangerous actions, tutorial hints, tooltips, pause during dialogue, pause on focus loss, difficulty (STORY / STANDARD / BRUTAL), autosave (off / every job / every night), damage feedback.
- Accessibility: UI scale, text scale, colour-blind indicators, reduced shake, reduced flashing, reduced effects (plus high contrast and reduce motion).

### Saves
- Save format v4: clinics and upgrades, business days and debt, districts, characters (relationships and appearance changes), staff, story (acts, flags, pending consequences, paths, counters), quests, comms and dialogue choices. v1–v3 saves migrate (old tiers map onto the new clinics).

### QA
- Unit suite grew to 500+ checks (clinics, overlays, business, districts, staff, story content integrity, two full-campaign playthroughs reaching different endings, settings, buses, bindings, save v3→v4), the E2E bot plays conversations, hires staff, assigns a job, rebinds keys and visits every new screen; the compile check now fails on scripts that load but don't compile.

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
- The E2E suite runs rendered under Xvfb: headless Godot measures fonts taller than the renderer, so its layout checks were not representative.
- **Release smoke test:** `UndercityRipper.exe -- --smoke-test` starts a game in slot 3, opens every main screen, saves, reloads, verifies the save file and prints `SMOKE OK`. Verified on the exported .exe under Wine in a fresh profile.

### Build and packaging
- `export_presets.cfg` is now a **Windows Desktop** preset: x86_64, release, embedded .pck (single .exe), `.ico` icon and version resources (via rcedit), *Undercity: Ripper* 2.0.0.0.
- `tools/package_windows.sh` exports and zips `UndercityRipper-<version>-windows-x64.zip` (exe, README.txt, font licences).

### Performance
- The black-market glitch pass is skipped entirely when effects are LOW or reduce motion is on (its screen-sampling shader was the most expensive pass); the encrypted feed scrambles at 20 Hz instead of every frame; the field hover overlay only redraws while the cursor is over the field.
- Texture caches and custom cursors are released on exit.

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
