# Architecture

How *UNDERCITY: RIPPER* is put together. The README has the player-facing
overview and build steps; this document is for whoever extends the game.

## Layers

```
data/*.json  ──►  DataLoader / typed Resources (scripts/data)
                         │
systems/ (autoloads) ◄───┘   game state + rules, no UI
   │  signals (EventBus, SurgeryManager)
   ▼
scripts/screens + scripts/components   presentation, input
   │
scripts/surgery (+ stages/)            the operation: site renderer, vitals, scoring
scripts/art                            runtime pixel-art helpers (PixelArt, CharacterArt)
tools/                                 offline generators (art, audio, theme)
tests/                                 unit tests, E2E bot, compile check, perf probe
```

Rules the code sticks to:
- **Screens never create screens.** They call `GameManager` (flow) and `UIManager` (presentation).
- **Systems never touch UI.** They change state and emit signals.
- **Stages never touch systems.** A `SurgeryStage` reads its params and context and then emits signals. `SurgeryScreen` routes them.
- **Tuning lives in data** (`data/*.json`) or in `GameConfig`. There are no magic numbers in screens.
- **Pure logic is node-free** (`SurgeryVitals`, `SurgeryScoring`, `NeuralLoad`, `CustomerGenerator`), so it can be unit-tested.

## Autoloads (load order matters)

| Autoload | Owns |
|---|---|
| `EventBus` | Cross-system signals |
| `CyberwareManager` | Catalogue, tier access (player level × clinic tier), validity checks, supply catalogue |
| `InventoryManager` | Tools (best per category), implant **instances**, supplies, parts, tokens, and the tool modifiers |
| `EconomyManager` | Money: the only place it changes |
| `ReputationManager` | Street rep and tiers |
| `ProgressionManager` | XP, levels, records; also grants skill points |
| `FactionManager` | Five faction standings and global **heat** |
| `SkillManager` | Skill ranks and points; contributes modifiers |
| `ClinicManager` | Clinic tier (0–5), upgrade costs and gates; contributes modifiers |
| `StoryManager` | Story flags, met characters, rumours |
| `EventManager` | Random and story events, choices, outcomes, timed modifiers, operation counter |
| `BlackMarketManager` | Stock rotation, hidden traits, buy/sell/study/modify/scrap, mystery cases |
| `ModifierManager` | Sums every modifier source into one key → value stack |
| `CustomerManager` | Story characters, archetypes, procedural generator, arrival queue, history, consequences |
| `SurgeryManager` | Runs one operation: stages, vitals, mistakes, complications, quick actions, result |
| `SaveManager` | Versioned JSON save with backup, migration and autosave |
| `AudioManager` | `play_sfx(id)` / `play_ambient(id)` hooks |
| `UIManager` | Screen navigation (also switches the audio profile), global hotkeys (ESC routing, I/B/J/M/C, F5/F9), TAB panel cycling, keyboard focus bootstrap, hover sound + cursor on every button, toasts, dialogs, modals, shake, flash, `celebrate(kind)` |
| `Settings` | Player preferences in `user://settings.cfg` (window mode, resolution, VSync, filtering, effects quality, volumes incl. master, key bindings, mouse sensitivity, shake, text speed, large text, high contrast, reduce motion); `apply_display()`; emits `changed` |
| `Controls` | InputMap actions with defaults (`ACTIONS`), rebinding with conflict swap, WASD on the ui_* actions, key names for on-screen hints |
| `TutorialManager` | First-shift coach marks; advances on screen, plan and stage-type contexts; saved with the game |
| `GameManager` | The loop: customer → diagnosis → plan → surgery → results, and applying rewards and consequences |

Each saveable system implements `get_save_data()`, `load_save_data(d)` and
`reset_state()`. `SaveManager.SAVEABLE_SYSTEMS` lists them.

## The game loop

```
Clinic ──SEE──► Customer file ──ACCEPT──► Diagnosis (scan regions, pick Dx)
   ▲                                          │
   │                                          ▼
Results ◄── SurgeryManager ◄──BEGIN── Operation plan (implant unit, tools, supplies, consent)
   │
   └─► rewards, faction/heat, neural-break roll, customer consequences
       (referral / return / regular / post-op complication / complaint),
       operation counter → events, black-market restock, rumours, autosave
```

`GameManager.get_surgery_readiness()` is the single gate for BEGIN. It returns:
- `missing_tools`, e.g. `"DRILL T1"`
- the implant source: stock, buy, or salvaged
- `supplies_ok`
- `invalid`: wrong category, or a tier the clinic can't handle
- `accepts`: whether the customer consents to a substitute or risky unit
- the neural load now and after the install

## Modifier keys

Every source adds plain deltas, and consumers use `ModifierManager.value(key)` (additive) or `.mult(key)` (1 + value). The sources are:
- skills: `data/skills.json` `effect_per_rank`
- clinic tiers: `data/clinic_tiers.json` `modifiers`
- owned tools: `data/tools.json` `modifiers`
- timed event effects: `EventManager.temp_modifiers`, which expire after N operations

During an operation, `SurgeryManager.mod()` adds that session's own modifiers on top (for example, operating with no supplies).

| Key | Kind | Read by |
|---|---|---|
| `surgery.precision` | mult | Tool precision passed to stages (tolerances, hit radii) |
| `surgery.speed` | mult | Hold and burn durations, drill speed |
| `surgery.bleed` | mult | Bleeding added by mistakes |
| `surgery.pain` | mult | Pain added by mistakes |
| `surgery.alignment` | mult | Implant alignment tolerance |
| `neural.splice_penalty` | mult | Neural damage from bad splices |
| `neural.load` | mult | Neural load an implant adds |
| `calibrate.range` | mult | Calibration sync window |
| `complication.chance` | add | Chance of a second complication |
| `complication.time` | mult | Complication countdown |
| `quick.cooldown` | mult | COAG / SEDATE / STABIL cooldowns |
| `coag.heal` | absolute | Health restored per COAG |
| `diagnosis.reveal` | add | Chance a scan reveals a hidden condition |
| `pay` | mult | Operation payout |
| `xp` | mult | XP earned |
| `price.buy` | mult | Supply terminal prices |
| `bm.price` | mult | Black-market prices |
| `bm.modify` | mult | Study / modify cost |
| `bm.stock` | absolute | Extra black-market offers |
| `faction.gain` | mult | Positive faction changes |
| `heat.gain` | mult | Heat gained |
| `supplies.use` | mult | Supplies consumed per operation |
| `post_op.risk` | add | Chance a successful op fails after the patient leaves |
| `customer.quality` | absolute | Wealth roll for generated customers |

`UIKit.MODIFIER_LABELS` holds the player-facing name of every key. **Add a new key there** when you introduce one.

## Neural load

`NeuralLoad.compute(customer)` adds up the load of all installed chrome, the
customer's base load and any hidden-condition modifiers.
`projected(customer, implant)` adds the unit being installed, scaled by the
`neural.load` modifier.

Effects scale continuously with the load L. The bands are what the player sees:

| Band | Range | What happens |
|---|---|---|
| Stable | 0–50 | Nothing |
| Minor symptoms | 50–70 | Neural drain during surgery ×(1 + (L−50)/40) and +(L−50)% complication chance. From 55 the `neural_feedback` complication can appear. Above 60, customers mention symptoms in dialogue and scans show "running hot" chrome |
| Instability | 70–85 | Patient starts the operation with −(L−60)×0.5 neural stability, and the calibration window narrows by up to 50% |
| Severe | 85–95 | Customer consent needs risk tolerance ≥ 0.45 |
| Critical | 95+ | Consent needs risk tolerance ≥ 0.75. From 90, a post-op **neural break** chance of (L−90)/40 queues the `static_fever` event, with rep and heat fallout |

The plan screen shows a before → after load meter, and the consent line reads "REFUSES: LOAD TOO HIGH" when a customer backs out. Black-market units and substitute units also need nerve (`GameManager.customer_accepts`).

## Surgery

`SurgeryManager.start_session(surgery, customer, diagnosis_ok, quality, seed, implant, session_mods)`.
- **Stages** are registered by `type` in `surgery_stage_registry.gd`:
  - `anesthesia`, `incision`, `expose`, `remove_tissue`, `anchor_drill`, `install_implant`, `connect_interface`, `calibrate`, `close_incision`
  - A new surgery is a data entry that reuses these types with its own params.
- **Site framing.** `SurgicalSiteView` renders the operating field at native art resolution inside a `SubViewport` whose container `stretch_shrink` is the field zoom (3×–6×, wheel / + −), so stage drawing is pixel-exact. `SurgeryScreen.field_to_screen()` converts field to screen coordinates at the current zoom; stages get `view_scale` for UI-sized hit radii.
- **PC input on stages.** `SurgeryStage` adds `hover_pos` (drives the `FieldHover` reticle and target brackets), `key_action(action, pressed)` (SPACE/E hold-to-infuse, LOCK, SEAT, rotate, nudge), `wheel_steps()` (rotate / tune instead of zoom) and `cancel()` (right-click returns a held implant). `SurgeryScreen` routes 1–9 / Q / R to the instrument rack and Z / X / V to the emergency actions.
  - Stages work in normalised field coordinates and convert with `to_local_pos()` / `to_norm()`.
  - The field can move when the layout changes, so stages must not cache local positions without re-syncing.
- **Context.** `SurgeryManager.get_stage_context()` passes difficulty, neural load, alignment and sync multipliers, and the implant icon to every stage.
- **Complications** are filtered for eligibility:
  - which stages allow them
  - neural-load minimum
  - required hidden condition, e.g. `rejection_spasm` needs `rejection_prone`

## Customers

`CustomerGenerator` builds a customer from an archetype (`data/archetypes.json`):
- a faction, and a name and alias (`names.json`)
- age, occupation, personality and finances
- patience, pain tolerance and risk tolerance
- existing chrome and a request filtered by tier access
- **hidden conditions** (`conditions.json`): revealed by scans, or by `diagnosis.reveal`
- a true diagnosis, scan findings and dialogue
- a palette-indexed appearance

Story characters (`characters.json`) use fixed appearances and dialogue, and arrive through events.

## Learning curve

`scripts/core/difficulty.gd` is the single place for early-game help. It keys
off `EventManager.operations` and controls:
- the tolerance assist (multiplies tool precision)
- the complication cap and timer
- the event gate and hidden-condition gate
- the neural-load cap for generated customers

`CustomerGenerator` also steers most requests toward jobs the clinic can do
(`GameConfig.FEASIBLE_REQUEST_SHARE`). The numbers are validated by
`tests/balance_sim.tscn`.

## Save format

Version 3 (`GameConfig.SAVE_VERSION`):
- Every file ends with `#md5:<hash of the JSON text>`. A mismatch rejects the file, and the loader then tries `.bak`, then `.tmp` (to recover from a kill between write and swap).
- v2 → v3: settings move out of the save, and the tutorial is marked done for existing players.
- `SaveManager._migrate()` upgrades v1 saves:
  - implant stock becomes instances
  - clinic tier 1 for veterans
  - the operation counter is derived from records
  - the current customer is preserved
- Writes go to a temp file and then swap in, with a `.bak` fallback.
- Saves never happen mid-surgery.

## Adding content

| Want | Do |
|---|---|
| Implant | Add to `data/cyberware.json` (category, tier, load, tools, risk...). The icon comes from `assets/sprites/cyberware/{category}_t{tier}.png`, or set `icon` |
| Tool | Add to `data/tools.json`, then add a sprite mapping in `tools/art/tools_art.py` `TOOLS` and regenerate |
| Surgery | Add to `data/surgeries.json` with `site`, `scan_region`, stage list and params. Link it via the implant's `surgery` id |
| Event | Add to `data/events.json`: `conditions`, `weight`, `cooldown`, and `choices` with `requires` / `outcomes` |
| Hidden condition | Add to `data/conditions.json` with `modifiers`, `hint` and `reveal_regions` |
| Archetype | Add to `data/archetypes.json` with outfits, factions, request categories and wealth |
| Modifier key | Read it with `ModifierManager`, add a label in `UIKit.MODIFIER_LABELS`, and list it above |

## Desktop UI (PC)

- **Canvas.** `project.godot` sets a 1920×1080 viewport with `canvas_items` stretch and `keep` aspect. Every screen is laid out for that canvas; window size only changes the uniform scale (and letterbox bars).
- **Workstation shell.** `UIKit.workstation(screen, nav_id)` builds the shared frame for hub screens: `StatusBar` (top: credits, level, rep, heat, resources, MENU) + `SideNav` (left: sections with hotkeys and badges) + a content column. Sub-screens (customer, diagnosis) keep the shell so the player never loses context; full-screen states (main menu, settings, results, surgery, black market) draw their own layout.
- **Panels.** Screens return their main panels from `get_panels()`; TAB (`UIManager.cycle_panels`) focuses the first control of the next panel and flashes its frame.
- **Escape routing.** `UIManager._on_escape`: an open dialog gets `on_escape()` (presses its first, safe button), else the screen's `on_escape()` (surgery pauses, settings cancels a pending rebind, main menu asks to quit), else its `BackButton`, else the pause menu.
- **Keyboard focus.** Buttons are focusable and show a cyan frame; the first arrow/WASD press focuses the control with meta `default`. Screens that use the arrows for gameplay set `keyboard_nav = false` (surgery).
- **Comparisons.** `Compare` builds CURRENT vs NEW tables for cyberware (tier, performance, neural load, difficulty, risk, condition, price) and tools; rows are tagged BETTER / WORSE / SAME / UNKNOWN (hidden traits) / INCOMPATIBLE (different body slot), each with a symbol.
- **Inventory grid.** `ItemSlot` is a drawn 112 px cell supporting hover, click, double-click (inspect → database), right-click (set CURRENT) and Godot drag & drop (`_get_drag_data` / `_drop_data`): dropping on another slot swaps storage order (saved), dropping on a COMPARE slot loads the comparison.
- **Save slots.** `SaveManager.save_dir` + `slot_path(n)`; `use_slot(n)` switches the active file and remembers it in `Settings.last_slot`; `get_slot_info(n)` reads the `meta` summary without loading the slot.
- **Instrument wear.** `InventoryManager.tool_condition` (0–100 per tool id, saved), `wear_tools()` after each operation, `tool_condition_factor()` feeds `SurgeryManager.get_tool_precision()`, `service_tools()` restores everything for credits.
