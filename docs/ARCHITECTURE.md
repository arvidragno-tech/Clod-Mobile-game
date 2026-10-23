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
| `EventManager` | Random and story events, choices, outcomes, timed modifiers, operation counter. One event is pending at a time; one that comes while another waits joins `waiting` (first come, first answered) instead of replacing it |
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
- clinics: `data/clinics.json` `modifiers` + installed upgrades (`data/clinic_upgrades.json`)
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
  - `anesthesia`, `incision`, `expose`, `remove_tissue`, `anchor_drill`, `install_implant`, `connect_interface`, `calibrate`, `close_incision`, `sequence` (points worked in one order), `hold_steady` (hold on a drifting ring until it sets)
  - A new surgery is a data entry that reuses these types with its own params.
  - Each implant category has its own sequence and a signature step (`docs/PROCEDURES.md`, checked by `tests/procedure_tests.gd`).
- **Site framing.** `SurgicalSiteView` renders the operating field at native art resolution inside a `SubViewport` whose container `stretch_shrink` is the field zoom (3×–6×, wheel / + −), so stage drawing is pixel-exact. `SurgeryScreen.field_to_screen()` converts field to screen coordinates at the current zoom; stages get `view_scale` for UI-sized hit radii.
- **Implant geometry and integration.** `SurgicalSiteView` is the one source of truth for implant placement, in field pixels: `socket_center()` / `implant_center()` are the anchor pixels, `implant_pivot()` is where the art turns, and the socket's key slot (`socket_key_pos()`) and the implant's notch (`implant_notch_pos()`) both sit `key_radius()` from the anchor, so the install stage's target and notch marks, its hit tests and the drawn socket always agree. A seated implant is composited into the body (`_rebuild_implant_layer()`, rebuilt only when the implant, wound or closure changes): it shows only inside the open wound, as a raised outline under intact skin, and under closed skin only within the surgery's `site.implant.exposed_radius` (the neural jack, the optic lens). Wiring and anchors are inside the body too. `tests/implant_placement_tests.gd` and `tests/implant_probe.tscn` cover it.
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

Version 5 (`GameConfig.SAVE_VERSION`, see 3.1 below for v4 → v5):
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

---

## 3.0: the underground (characters, clinics, staff, business, story)

### New autoloads

| Autoload | Owns | Saved |
|---|---|---|
| `CharacterAppearanceManager` | Appearance rules (`data/appearance_rules.json`): generation from occupation, faction, wealth, age, personality and installed chrome; v1→v2 migration; appearance events (`lose_eye`, `cyber_arm`, `upgrade_outfit:`, `faction:`, `expr:`...) | no (pure) |
| `CharacterManager` | Story cast (`data/cast.json`, `CharacterData`): relationship value and state (hostile … loyal, romantic), fear, met, appearance after events | yes |
| `CharacterPortraitManager` | "Who is this": cast, staff or customer → appearance, backdrop, animation profile, accent, relationship; pre-composites expressions before a conversation | no |
| `CharacterAnimationManager` | One ticker for blink, gaze, breath, tremor, idle actions and cyberware flicker on every registered view; redraws a view only when its state changed | no |
| `WorldManager` | Districts (`data/districts.json`), visited, influence; walk-in weights (archetype × district) and event weights (district events ×2) | yes |
| `BusinessManager` | Days, job capacity, categorised ledger (every `EconomyManager` movement carries a category and is emitted as `EventBus.transaction`), nightly settlement, debt and interest, day reports | yes |
| `StaffManager` (+ `EmployeeAI`) | Hiring board, employees, hire / fire / transfer / raises, assignment (`EmployeeAI.refusal`, `success_chance`, `perform`), nightly stress / loyalty / growth / secrets, staff-run clinics | yes |
| `CommsManager` | Inbox: message, call, email, encrypted, contract (actions with effects) from `data/comms.json` templates | yes |
| `QuestManager` | Quests (`data/quests.json`): start, objective evaluation, deadlines, rewards, states | yes |
| `DialogueManager` | Conversation graphs (`data/dialogues.json`): nodes, options, checks and odds, effects, choice log | yes (choices) |
| `StoryManager` (extended) | Acts, beats, delayed consequences, talk queue, endgame paths, counters, endings (`data/story.json`), plus flags and rumours as before | yes |

`ClinicManager` was rewritten around `data/clinics.json` (seven clinics,
owned + active index, per-clinic upgrades from `data/clinic_upgrades.json`,
overlay sprites from `data/clinic_overlays.json`) and keeps the old tier API
(`tier`, `get_next_tier`, `upgrade`, `get_tier_data`) so existing screens and
saves keep working.

### Flow

```
customer arrives (WorldManager weights the archetype by district)
 └─ customer file: PERFORM (surgery as before) | ASSIGN (StaffManager.assign → EmployeeAI)
                   | DEFER (queue with due_day) | REFUSE
      └─ job done → BusinessManager.record_job → StoryManager.check()
                     (beats → talk queue / comms / quests; act advance; QuestManager.check_all)
day full → CLOSE FOR THE NIGHT → BusinessManager.end_day
      → StaffManager.end_of_day (stress, loyalty, growth, secrets, other clinics)
      → rent / running / upkeep / salaries / interest → report → EventBus.day_ended
      → EventBus.day_started → StoryManager: due consequences → talks / events / comms
clinic screen: pending event (then each waiting one, in order) > queued talk (DialoguePanel) > customer
```

### Story data

- **Conversation** (`dialogues.json`): `{character, title, act, start, nodes}`; a node has `speaker`, `expr` (portrait expression), `text`, optional `effects` on entry, and `options` or `next`. An option has `kind` (plain, refuse, persuade, intimidate, bribe, empathy, lie, negotiate), `mod`, `requires` (`flag`, `flag_any`, `rel_min`, `ending`), `cost`, `effects` / `fail_effects`, `next` / `fail_next`.
- **Effects** (`StoryManager.apply_effects`): `rel`, `fear`, `rel_other`, `flag` (one or a list), `money` (negative beyond your cash becomes debt), `debt`, `rep`, `faction`, `heat`, `path`, `quest`, `consequence {id, days}`, `appearance_char {id, event}`, `supplies`, `ending`.
- **Beats** (`story.json`): `{act, when, do}`; `when` uses `StoryManager.cond` (`min_day`, `min_day_in_act`, `min_ops`, `min_rep`, `min_heat`, `flag`, `not_flag`, `flag_any`, `clinics`, `staff`, `staff_skill`, `faction_min`); `do` queues talks, sends comms, starts quests, sets flags. Each act has an `advance` condition.
- **Consequences:** `schedule_consequence(id, days)`; on the due day the id resolves to a conversation, an event or a comms template, in that order.
- **Endings:** available when their `requires` hold and you walked that path (path score > 0; "feared" is always open). The finale offers only the available ones.

### Checks

`DialogueManager.chance` (clamped 5–95%):
- persuade 0.35 + rep/200 + relationship/250 + level×0.01
- intimidate 0.3 + heat/200 + fear/200 + gangs/300 + feared path ×0.03
- bribe 0.8 − relationship/400 (and it costs money)
- empathy 0.45 + relationship/200 + respected path ×0.02
- lie 0.4 + level×0.015 (−0.15 if they're suspicious)
- negotiate 0.4 + level×0.02 + rep/300 + kingpin path ×0.02

### Staff odds

`EmployeeAI.success_chance` = 0.58 + 0.1 × (skill − difficulty) + precision / reliability terms, +0.12 when the implant category is in the specialization, + trait and clinic (`staff.skill`) modifiers, − 0.25 × stress, − hidden conditions, − 0.1 at critical projected neural load. Refusals come from ethics (minors, black-market chrome, corporate clients), traits (money first) and shift limits; hard refusals can be overridden with INSIST (loyalty and stress cost, remembered by the story).

### Settings → effects

`Settings.apply_runtime()` sets `Engine.max_fps`, the root's stretch mode (integer / fractional), content scale (UI scale, fit only), filtering and the tooltip delay. `Accessibility.apply` scales theme fonts by text scale. Consumers query `shake_scale()`, `flashing_allowed()`, `effects_level()`, `crt_enabled()`, `glow`, `environment_effects`, `lighting_quality`, `damage_feedback`, `confirm_dangerous` (`UIManager.guard`), `pause_dialogue` / `pause_focus_loss` (customer arrivals, surgery pause), `difficulty` (`Difficulty.assist`, `complication_time`, `cost_mult`) and `autosave` (`SaveManager.save_game(reason)`).

### Controls

`Controls.ACTIONS` lists every action with a category; categories map to contexts (global, surgery, dialogue) and only actions sharing a context can clash. A binding code is a keycode (> 0) or a negated mouse button (< 0); each action has two slots. Movement bindings are mirrored onto `ui_up` / `ui_down` / `ui_left` / `ui_right` so menus follow the layout.

## 3.1: the world reacts (living world)

Nothing from 3.0 was removed. Eleven systems were added as autoloads (all
saved, all `reset_state` / `get_save_data` / `load_save_data`), and the
existing managers call into them at a handful of points.

| Autoload / class | Owns | Data |
|---|---|---|
| `MemoryManager` | What people remember about you: tags such as `PLAYER_SAVED_ME`, `PLAYER_OVERCHARGED_ME`, `PLAYER_KILLED_FRIEND`, `PLAYER_BETRAYED_FACTION`. A memory moves the relationship once (cast → `CharacterManager`, patients → `PeopleManager`, staff → loyalty) and the reputation dimensions, and gives them something to say (`recall_line`, ~60% of visits) | `data/memories.json` |
| `PeopleManager` | Everyone who walked in, as people: identity, traits, finances, relationship (stranger … loyal / hostile), visits, money paid, chrome, links (friend, family, crew), history. After a visit they may come back days later, changed (`_evolve`: wealth, scars, chrome from elsewhere, a new crew or job; appearance events persist). Referrals, payment terms (`settle`), patient debts (demand, plan, write off, fixer, favour), cyberware dependency (0–4) | `data/patients.json` |
| `StaffLifeManager` | Employee lives (family, money, fear, dream), bonds between colleagues (friendly, professional, suspicious, competitive, resentful, loyal, fearful, respectful, involved), life events as COMMS choices, reactions (defend after a death, resent a forced job, envy a raise); `team_modifier` feeds `EmployeeAI.success_chance` | `data/staff_life.json` |
| `TimeManager` | The clinic clock (09:00–04:00), moved by arrivals (`arrival_gap` spreads the day's jobs), operations (20 min … 2 h by difficulty), triage and talk. Five periods weight archetypes, incidents, prices (`get_modifiers`), black-market prices, staff (`staff_modifier`), room tint and ambience; daily appointments become incidents at their time (once each; behind any decision already waiting, never dropped for it) | `data/time.json` |
| `ClinicLifeManager` | Waiting room (seats walk-ins while you work; patience runs out; rival factions make a scene), hourly vignettes with small effects, the Clinic Wall (pins for milestones, losses, regulars, wanted notices, faction marks, clippings) | `data/clinic_life.json` |
| `WorldEventManager` | City situations lasting days (gang war, recall, inquiry, takeover, missing fixer, port strike, mass casualty, neural program, blackout, someone you know in trouble) as weights and modifiers; the news wire (situations, reactions to the clinic, filler, your street identity) | `data/world_events.json` |
| `SurgicalDilemmas` (class) + `SurgeryManager` hooks | Decision complications that freeze the table (`dilemma_started`, `resolve_dilemma`), with odds from patient, chrome, tools, skill, staff | `data/dilemmas.json` |
| `SupplierManager` | Six black-market contacts: discovery, trust / suspicion / debt / favours, unlocks (discount, credit, rush, rare, secret), daily inventory shaped by hour / district / heat / world / reputation, grades, unidentified devices, cut-offs, contraband | `data/suppliers.json` |
| `SecurityManager` | Heat levels (LOW … CRITICAL) and their COMMS pressure (surveillance, interrogation, confiscation, informant), night thefts with real losses, cases with cameras / questioning / asking around / confronting | `data/security.json` |

`ReputationManager` gained five dimensions (civilian, criminal, medical,
corporate, black market), `identity()` (what the street calls you, inferred
from behaviour), `archetype_weight()` and `heat_gain_mult()` (trade-offs).
`AudioManager` gained a reactive mix (`set_mix_mod(source, layers)`, used by
the clock and by `update_tension()`) and a low-pass on the Music bus that
closes in on quiet nights and opens with danger.

### Where the world bends the loop

```
walk-in archetype weight = archetype × district × hour × situations × your reputations
customer: traits, finances, budget (share of the expected fee), memories, changes since last visit
intake: payment terms · emergency triage (countdown) · dependency care
operation: maybe a surgical dilemma → choice → odds → vitals / performance / pay / finds
payment: PeopleManager.settle → paid now + debt → MemoryManager (discount, overcharge, free)
after: PeopleManager.after_visit → memory, relationship, maybe return later, referrals
clock: TimeManager.advance → period change (tint, mix, modifiers) → appointments
       → ClinicLifeManager (walk-ins, patience, vignettes)
night: BusinessManager.end_day → day_ended: SecurityManager (theft, pressure) and
       WorldEventManager (reactive news, identity) add to the report
dawn:  day_started → situations tick / start, supplier stock, staff life events, debts
```

COMMS actions carry their own effect blocks: `effects` (StoryManager),
`staff` (StaffLifeManager), `person` (WorldEventManager), `supplier_favor`
(SupplierManager), `security` (SecurityManager).

### Save v5

v4 → v5: the new systems start from defaults, and patients from the old
clinic log become people you've met (`SaveManager._migrate`).

### Tests

- `tests/living_world_tests.gd` (part of the unit run): every system above,
  save / load and the v4 → v5 migration.
- `tests/living_probe.tscn`: the rendered game at 1920×1080, 1600×900,
  1366×768 and 1280×720 with screenshots of every new screen state and
  on-screen checks.
- The E2E harness resolves timed incidents and surgical dilemmas; scripted
  runs switch random dilemmas off, unit runs switch random world / security
  rolls off for determinism.

### 3.1.1 notes

- Emergency countdown: `CustomerManager._process` counts the waiting
  emergency down (stored in `CustomerData.emergency_deadline`, ms left), so
  it survives screen changes and saves; it stops during surgery, modals and
  paused arrivals, and `Settings.time_pressure` scales or disables it. The
  customer screen only displays it and listens to `emergency_crashed`.
- Supplier orders: cash and credit orders go to `SupplierManager.deliveries`
  and arrive at the next `day_started`; RUSH calls `_deliver` immediately.
  Night stock is topped up on `period_changed` → night.
- Surgical dilemmas leave the table paused after `resolve_dilemma`; the
  `DilemmaPanel` resumes on exit. Aborts before the `install_implant` stage
  return the unit to stock (`SurgeryManager.implant_installed`,
  `GameManager._implant_returnable`).
- Dialogue: nodes may carry `variants` ([{if, text}]) and options a
  `requires` with `identity`, `memory`, `not_memory`, `dim_min`
  (`DialogueManager.world_cond`); `reputation_mod` adjusts check odds.
- Clinics (`data/clinics.json`) define `wall` {x, y, cols} and
  `waiting_feet` for the room overlays.
- Music: `clinic_night` and `clinic_tension` (tools/generate_audio.py
  `music_reactive`), chosen by `AudioManager._score_for`.

## 3.2: the living city (locations)

Few places, each with a job: DISTRICT → LOCATION → PEOPLE → FUNCTION →
EVENTS. The seven districts of `WorldManager` stay as they are; twelve
places live inside them (`data/locations.json`), one of each kind and two
bars, two residential blocks and two restricted sites. Two autoloads and one
helper class were added; nothing was removed and no existing system was
duplicated: shops are the supply terminal, the Undermarket is
`BlackMarketManager` + `SupplierManager`, hires go on `StaffManager`'s
candidate list, people sent to your clinic go into `CustomerManager.queue`,
event outcomes reuse `EventManager.apply_outcomes` and
`StoryManager.apply_effects`, prices go through `ModifierManager`.

| Autoload / class | Owns |
|---|---|
| `LocationManager` | The registry, discovery (`discover(id, how)`, `check_discovery()`, `reveal_random()`), where the player is (`player_location`, `is_away()`), opening hours on the 06:00–30:00 dial (`is_open`, `hours_text`), access (`access_block`, Exclusion Zone access: route / forged / pass, or a practice inside the Zone), travel (`trip`, `trips`, `best_trip`, `leave_block`, `travel`, `return_to_clinic`, `spend_minutes`), the place's price modifiers while you're there (`get_modifiers`), metro pass, nights away (theft risk). Saved |
| `WorldSimulationManager` | What a place is like now (`state(id)`: activity, danger, police, faction presence, dominant faction, flags closed / after_hours / busy / quiet / dangerous / police / monitored / controlled / unwelcome / restricted / bm_active / event / lead; `state_label`, `price_mult`), who is where (`cast_at`, `patients_at`, `staff_at`, `suppliers_at`, `people_at`, `person_place`, `ensure_routine`, `residents`), talking (`talk`, `can_talk`), ambient events (`roll_events`, `start_event`, `event_at`, `resolve_event`, `apply`), travel encounters (`roll_encounter`, `resolve_encounter`), the missing-patient chain (`start_missing`, `missing_at`, `act_missing`), faction presence shifts, closures, the street feed. Saved |
| `LocationServices` (class) | What you can do at a place: 22 services (`list`, `block`, `cost`, `perform`), most once a day per place |

### How it simulates (cheaply)

Nothing walks around frame by frame. Every answer is computed from the
clock when asked and cached until the clock moves (`refresh()` on
`time_changed`):
- **Patients** get `home`, `work` and `social` place ids the first time
  they're needed (stored on the person, so saved with `PeopleManager`).
  A routine (default or night shift) maps the period to a slot
  (home → work → transit → bar → home); 15% of the time they skip it.
  Closed places fall back to home.
- **Cast** haunts are rolled per day and period from a hash, so nobody
  flickers; unmet cast and cast who are gone (`unless` flags) are nowhere.
- **Staff** take one break a night at their bar (on call).
- **Suppliers** keep tables at their haunt; unknown ones are strangers you
  can introduce yourself to.

### Where the city bends the loop

```
travel: LocationManager.travel → cost, TimeManager.advance(minutes) (periods, appointments,
        waiting-room patience), maybe an encounter (risk × danger × night)
away:   no arrivals (CustomerManager gates the timer); whoever was at the door sits on the
        bench or leaves; walk-ins still sit down; night minutes raise theft_chance
place:  an event (choices with requires / minutes / outcomes), people (talk: relationship,
        loyalty, trust, leads, queued story conversations), services
out:    patients → CustomerManager.queue (emergencies first); candidates → StaffManager;
        leads → SupplierManager / LocationManager; zone access; faction presence shifts
back:   GameManager.go_to_clinic goes to the place you're at while away; the clinic
        screen brings you home (with the trip's time) if you get there any other way
dawn:   everyone starts at the clinic; closures lift; presence drifts back; a patient with
        risky chrome may go missing; missing deadlines
```

Event outcome keys on top of the incident vocabulary: `effects`
(StoryManager), `patient` {archetype, emergency, category, pay, line},
`lead`, `candidate`, `zone`, `close`, `staff_loyalty` / `person_rel` /
`person_visit` (with the event's vars). `StoryManager.apply_effects` gained
`discover` (reveal places from conversations and quests) and `counters`.

### UI

- `CityMapView` draws the known places (type colour, state ring, events
  and leads blink, a dashed route, YOU) and emits `location_clicked`.
- The map screen's side panel shows a place: state, presence, people you
  know there, what you can do, and one button per way to get there
  (`Travel_walk` / `Travel_metro` / `Travel_taxi`, time · cost, risk).
- `location_screen.gd` (`UIManager.SCREEN_LOCATION`): `LocationView` (the
  street, drawn from the district palette and the place's kind, with the
  hour's tint, activity, police lights, rain), state, the event / missing
  trail, the street feed, people (TALK), services, RETURN TO CLINIC.
- `TravelFlow` (travel → encounter modal → destination) and `ChoicePanel`
  (a decision modal).

### Tests

- `tests/living_city_tests.gd` (unit run, ~200 checks): registry integrity,
  discovery, hours and states, travel (modes, costs, blocks, the clock,
  always home), being away, routines, cast and staff presence, events,
  factions, the Undermarket in person, services, the Exclusion Zone, the
  missing chain, encounters, talk, save / load and old saves, and a
  week-long soak.
- `tests/city_probe.tscn` (rendered): M opens the map, a mouse click on a
  marker, travel, the location screen, an event, a service, TAB, an
  encounter, ESC, GO IN, RETURN TO CLINIC, every place at two hours, F5 /
  F9 while out; 1920×1080, 1600×900, 1366×768, 1280×720 windowed, plus
  borderless and fullscreen.
- `tests/stability_test.tscn` makes a city outing every other shift and
  checks the player is never stranded.

## 3.3: a clearer UI

- **Glossary** (`scripts/ui/glossary.gd`, `data/glossary.json`): terms
  {topic, title, short, text} and topics. `short()` feeds tooltips,
  `show(term)` opens a card by the mouse, `open_guide(topic, term)` the
  FIELD GUIDE. Both are built in a `HelpHost` control at the end of the
  overlay layer (above modals, so a conversation underneath is never
  closed; not OS popups, so window focus can't close them). ESC
  (`UIManager._on_escape`) and a click outside close them. `CAPTIONS` maps
  stat captions to terms for `UIKit.caption`.
- **UIKit:** `section_head(title, hint, term, color)` (bar + title + "?" +
  rule; `section()` uses it), `info(term)` ("?" chip), `caption(text)`
  (help cursor, tooltip, click to explain).
- **JobVerdict** (`scripts/ui/job_verdict.gd`): `checks(c)` and
  `advice(c)` from `GameManager.get_surgery_readiness`, so the door card,
  the customer file and the plan always agree; `build(parent, c, compact)`.
- **Theme** (`tools/build_theme.gd`): one bold body face on every button
  variation, `InfoButton`, `SectionLabel`, `HintLabel`, `ValueLabel`;
  frames (`tools/art/ui_art.py`) lit from above with an inner line.
  `Accessibility.SCALED_TYPES` includes the new variations.
- **Room light:** `Settings.room_material()` (shader
  `assets/shaders/room_light.gdshader`, `lift` = `Settings.brightness`)
  on `ClinicView` and `LocationView`. In Godot 4 a canvas shader's
  `COLOR` already includes the texture.
- **Character art** (v2 then; HD since 3.4, `tools/art/hdc_face.py`): `draw_eyes` (almond,
  iris rim, pupil, catch-light, crease), `_hair_px` (strands),
  `draw_body_base` face details, body accessories `mask` and `eyewear`;
  `CharacterArt.PORTRAIT_TO_BODY` mirrors face/head accessories onto the
  body sprite. Regenerate with `python3 tools/generate_art.py chars`,
  then reimport.

## 3.4: the HD art style

- **Two densities.** `GameConfig.PIXEL_SCALE` (3) stays for UI sprites,
  icons and the surgical field; `GameConfig.ART_SCALE` (2) is for the world
  art, which is drawn at 1.5x the resolution. ClinicView, ClinicPreview,
  PixelPortrait, LocationView and CityBackdrop draw at ART_SCALE.
- **Clinic rooms** are 600x336 (`tools/art/rooms_hd.py` on the numpy kit
  `tools/art/hd.py`: albedo + emissive + gloss buffers, banded lights, haze,
  bloom, floor reflections, ordered-dither posterise). Every coordinate
  around them (hotspots, customer foot, waiting spots and wall pins in
  `data/clinics.json`, fx anchors in `data/clinic_fx.json`, overlay offsets)
  is in HD art px.
- **Characters** are 144x168 portraits and 60x120 bodies. The generator keeps
  the v2 design grid as logical coordinates (`hdc_core.HDCanvas`: shaded
  primitives and `grid()` area loops are evaluated per HD pixel) and draws
  the fine features on the HD grid (`P/HL/VL/LN`). `ClinicView.body_scale()`
  sizes a body by `GameConfig.BODY_ART_W`, so a body atlas of any resolution
  keeps its place in the room. `PixelPortrait` framings stay in the 96x112
  layout units and are scaled to the atlas.
- **Streets**: one 520x150 scene per location and hour (night/day) in
  `assets/sprites/streets/`; LocationView draws it and adds walkers, police
  lights, rain and the hour's tint (the old procedural street is the
  fallback). The title key art (960x540) and the black-market banner
  (900x111) come from the same module.
- **Type**: Chakra Petch (medium/semibold/bold) and Share Tech Mono with a
  DejaVu Sans fallback, wrapped in FontVariations by `tools/build_theme.gd`;
  the title face is imported as MSDF.

## 3.5: guidance and custom controls

Complex systems underneath, simple decisions on screen. Everything here reads
the live state of the existing managers and stores as little as possible.

- **Input.** `Controls` (autoload) owns the actions: two slots each, a code
  per slot (a keycode OR-ed with `KEY_MASK_CTRL/SHIFT/ALT/META`, a negative
  mouse button, or 0 for unassigned), categories, presets, search, conflict
  checks and `fill()` for `{action}` tokens in on-screen text. Actions match
  exactly (`event.is_action(a, true)`), so CTRL+S never fires S. `CRITICAL`
  actions (pause, dialogue continue, contextual) always keep one key.
  `InputContext` decides who owns the keyboard, in priority order: rebinding
  > a focused text field > the field guide / help overlays > a conversation >
  a modal > the screen's own context (`SCREEN_CONTEXTS`). `UIManager` routes
  every hotkey through it (`ROUTES`), and ESC closes the topmost thing first.
- **ChangeLog** (autoload, saved): listens to EventBus (factions, heat,
  reputation, money, levels, places, news, supplies, leads, upgrades,
  quests, staff, relationships, comms, emergencies) and keeps merged,
  categorised entries `{seq, cat, subject, text, level, link, delta, day,
  minute}`. `mark()` / `since(seq, cats)` power the results screen's "NEW"
  lines; `ChangesPanel` shows the list (G).
- **Follows** (autoload, saved): followed quests, people, cast, places,
  returns, deliveries and appointments. `live()` resolves each against the
  current state (where, when, soon) and drops finished ones.
- **Guidance** builds WHAT MATTERS NOW (`items()`), ranked critical >
  important > info; **ClinicStatus** gives the six status rows and
  `most_important()`; **Recommend** ranks staff by `EmployeeAI.success_chance`,
  estimates your own odds from your record and level, and mirrors
  `SurgeryManager.get_extra_complication_chance` for the preview.
- **Consequence**: `snapshot()` before a decision, `show(headline, before)`
  after it; the card lists the real deltas and never blocks input.
- **Hints**: first-time cards (`Hints.first(id)`), remembered in the
  settings (`seen_hints`), gated on TUTORIAL HINTS and the tutorial; test
  harnesses set `Hints.enabled = false`.
- **Nav**: every guidance line, change, follow and result link is a small
  Dictionary (`{screen, params}`, `{location}`, `{customer}`, `{term}`,
  `{panel}`); `Nav.open()` follows it and ignores stale links.
- **Pause rule:** `UIManager.is_reading()` (reading screens, the field guide,
  a modal) stops the emergency countdown in `CustomerManager`; the field
  guide also pauses `SurgeryManager`.
- **Journal tabs** are addressed by name (`tab_name`, `view`, `focus`); the
  old integer tabs are mapped (`LEGACY`) so existing links keep working.


## 3.6: quality pass

Fixes go to the existing systems; no new managers. Root causes and
numbers are in `docs/QUALITY_PASS_3.6.md`.

- **One scale authority.** `Settings._apply_stretch` sets the
  `canvas_items` stretch (FIT, or INTEGER only when the window is at least
  the 1920×1080 canvas) on every `root.size_changed`;
  `content_scale_factor` is always 1. `ui_scale` survives only as a legacy
  key folded into `text_scale`. `apply_display(force)` touches the window
  only when the display settings changed, and `main.gd` re-themes only when
  theme keys change.
- **Purchases.** `UIKit.debounce(key)` guards every BUY. Shop and black
  market rebuilds are deferred (`_queue_rebuild`) and keep the shown item and
  the scroll position. `BlackMarketManager.index_of(uid)` resolves an offer
  at click time. `UIManager.go_to` queues one `_pending_nav` during a fade.
- **Doors.** `BusinessManager.doors_open` (saved, reopened in `end_day`,
  `doors_changed` signal). `CustomerManager` and `ClinicLifeManager` skip
  arrivals and walk-ins while closed.
- **Money.** `JobEstimate.for_customer(c, readiness)` is the one estimate
  used by the file, the plan, the door card and the simulator.
  `SurgeryResult.finance` carries the real breakdown that the results
  screen's THE MONEY shows. `BusinessManager.outlook(days)` projects
  revenue, direct and recurring costs and names the main cause of a loss.
  `PeopleManager` turns any shortfall into a plan.
- **Standing history.** `ChangeLog.push_cause / pop_cause` wrap every
  entry point that can change standing (events, dialogue, comms, world
  actions, quests, security, staff, suppliers, the black market, the night
  report, location services, operations, triage). `record_standing(group,
  …)` stores `{group, label, delta, value, reason, day, minute}`. Groups are
  `rep`, `dim:<d>`, `faction:<id>`, `heat` and `person:<id>`. Repeats are
  batched and the list holds at most 200 entries. `standing_trend(group,
  days)` feeds the ▲/▼ marks. The managers' change functions take an
  optional `reason`. `Standing` (scripts/ui) builds the journal's STANDING
  rows, thresholds and the exact previews on event choices.
- **Guidance level.** `Settings.guidance_level` (0 minimal, 1 standard,
  2 detailed) is read only by presentation: `Guidance.for_player()`,
  `ClinicStatus.visible_rows()`, `Hints.first` and the DETAILED toasts in
  `ChangeLog.add`. `Hints` and non-critical toasts wait while
  `SurgeryManager.is_active` or `DialogueManager.is_active()`.
  `UIManager.show_toast` drops an exact repeat of a live toast.
- **Surgery.** `ToolTray.select_category` auto-selects the stage's tool.
  `SurgeryStage._hint_limited` gives rate-limited feedback for near misses.
  `SurgeryData.for_diagnosis` drops the duplicate debridement after a
  correct clean-site diagnosis.
- **Tests.** `tests/quality_tests.gd` (in the unit run),
  `tests/ui_stability_probe.tscn` (real mouse events at four resolutions and
  three window modes), and `tests/economy_sim.tscn` (five strategies on the
  real systems with fixed seeds, `--check` against the targets).


## 3.7: progressive onboarding and the patient summary

No new managers: the state lives in the existing saved `TutorialManager`, and
every view reads the existing rules. Audit and results:
`docs/UX_OVERHAUL_3.7.md`.

- **Features** (`scripts/ui/features.gd`, static) defines each side-bar
  section: title, screen, stage, WHAT / WHY / HOW / COST, and its handbook
  term.
  - `relevant(id)` reads existing state: `Difficulty.ops()`, comms, staff,
    clinic tier, `LocationManager.is_away()` and
    `BlackMarketManager.is_unlocked()`.
  - `refresh()` introduces what has become relevant and queues its intro
    card. It is called from `_begin_play`, the clinic's status refresh and
    `TutorialManager.load_save_data`.
  - `TutorialManager.introduced` (`id -> day`) and `intro_pending` are saved.
    `start()` clears them for a new game; `reset_state()` and saves without
    the key introduce everything.
  - Gates:
    - `SideNav` hides the button, and a group header hides when all its
      items are hidden;
    - `GameManager.navigate` (side bar and room props) and
      `UIManager._route` (hotkeys) call `Features.not_yet()` instead;
    - `Nav.open` introduces the target, because a link means it's relevant.
  - `Settings.progressive_features` turns the gating off. The black market
    keeps its own unlock rule.
- **PatientBrief** (`scripts/ui/patient_brief.gd`) holds the summary's facts.
  - Money comes from `JobEstimate.for_customer`, odds from
    `Recommend.self_estimate`, and missing requirements from
    `JobVerdict.checks` filtered to `BLOCKING`, each with a `Nav` link that
    fixes it.
  - `recommendation()` is a neutral line built from those numbers.
- **PatientSummary** (`scripts/components/patient_summary.gd`) is a modal.
  `GameManager.show_patient_summary()` opens it from SEE PATIENT, the room
  and the customer key; `open_customer()` still opens the full file (MORE
  DETAILS, staff hand-off, tests).
  - The tutorial's intake step uses the "summary" context, and `CoachMark`
    looks inside the top modal first.
- **Dashboard**: `ClinicStatus.dashboard()` returns `{headline, issues}`,
  derived from `rows()`, the door patient's blocking checks and the
  business. `Guidance.for_player()` drops `ClinicStatus.DASHBOARD_IDS` and
  lines that link into sections not introduced yet.
  `GameManager.get_next_objective()` adds `why` and `optional`.
- **DecisionPreview** (`scripts/ui/decision_preview.gd`):
  - `facts(cost, recurring)` gives cash now and after, tonight's bill
    (`BusinessManager.projected_total`) and short / below-bill flags;
  - `summary()` is the one-line form;
  - `build()` makes the BEFORE YOU PAY box.

  It is used by SUPPLY, FACILITY, clinic purchases, hiring, the black market
  and suppliers. It never projects income.
- **Known consequences**: `DialogueManager.known_effects(option)` reads the
  option's faction, rep, heat and money through `Standing.preview`.
  Relationship and fear are never shown.
- **Handbook**: glossary entries may carry:
  - `feature` (hidden until it is introduced; counted by `hidden_in`);
  - `why` and `where`;
  - `see` (related entries).

  The field guide keeps a back stack, and its TUTORIALS section re-shows
  `Features.show_intro` and `Hints.show_again`.
- **UIKit.flavor(text)** styles atmosphere (quoted, slanted, dim) so it
  never reads like a requirement.

## 3.11: story cases, pacing and seasons

No new managers or screens. Audit, plan and results are in
`docs/NARRATIVE_PACING_3.11.md`.

- **Pacing** (`data/time.json` `pacing`; `CustomerManager`):
  - `visit_budget()` is surgery capacity + `spare_visits`. `count_visit()`
    is called for every arrival (`next_visit()`, a seated walk-in).
  - `request_next_customer()` waits `breather()` seconds, by the
    `kind_of()` the last patient was (routine, character, story).
  - `day_is_quiet()` (budget spent, nobody due) makes
    `BusinessManager.is_day_full()` true.
  - `walk_ins_allowed()` gates the hourly walk-in roll in
    `ClinicLifeManager`, also during `quiet_until`, which is set after a
    story case. `can_seat()` is unchanged, so a door patient can still wait
    when you go out.
  - The schedule (`schedule_day`, `visits_today`, `story_slot`,
    `quiet_until`) is saved under `"schedule"`. An old save counts
    `jobs_today` as visits used.
  - `EventManager` caps random incidents with `max_incidents_per_day`
    (forced events are not counted); `incident_day` and `incidents_today`
    are saved.
- **Story cases** (`data/cases.json`, `StoryManager`):
  - `due_case()` picks the first open case whose act window, `min_day`,
    `min_ops`, `min_day_in_act` and `cond` match, at most one every
    `story_case_gap_days`.
  - `CustomerManager._next_customer` swaps it in for the routine visit at
    `story_slot` (`make_case_customer`): a generated patient with the case's
    name, words, history and scan clue, and `CustomerData.case_id`.
  - `case_arrived` / `case_finished` / `case_declined` apply the case's
    `on_<outcome>` effects and queue its `after` event.
  - Case decisions are ordinary events (`data/events.json`, weight 0, once).
    Outcomes may carry `effects` (the `StoryManager.apply_effects`
    vocabulary, now with `wall`, `news` and `cutscene`).
  - Echoes use the existing systems: comms, Wall pins, and dialogue
    variants with `world_cond` `flag` / `not_flag`.
  - Save keys: `cases`, `last_case_day`.
- **Cutscenes** (`data/cutscenes.json`, `scripts/components/cutscene_player.gd`):
  - `StoryManager.queue_cutscene(id)` (once per save; dropped when
    `Settings.story_cutscenes` is off). Act changes queue `cs_act_<n>`;
    beats and effects can queue `{"cutscene": id}`.
  - `ClinicScreen` plays them as a modal, after a pending event and before
    a conversation.
  - `CutscenePlayer` pauses arrivals, hides toasts and the consequence card
    (`UIManager.set_feedback_hidden`) and routes ESC to `skip_scene`.
  - Save keys: `cutscenes`, `seen_cutscenes`. Harnesses set
    `CutscenePlayer.enabled = false`.
  - Length: left alone, a scene runs at least `MIN_SCENE_SEC` (30 s) at
    every text speed. `CutscenePlayer.estimate_seconds(shots, cps)` is
    the same timing the player uses (fade, typing, `hold_for`);
    `narrative_tests` checks every scene with it, and
    `narrative_probe -- --all-cutscenes` times each one in the game.
  - Skipping marks the scene seen once: `pop_cutscene` marks it when it
    starts, and `_close` runs once however often SKIP / ESC are pressed.
- **Seasons** (`data/time.json` `seasons`, `TimeManager`):
  - Calendar: `season(day)`, `season_blend(day)`, `season_value(section,
    key)`, `season_tint()`.
  - `weather(day)` is seeded from the day number, so it needs no save
    data. It returns `{kind, next, mix, second, density}`.
  - `EventBus.season_changed` fires on the first day of a season
    (`WorldEventManager` posts the turn).
  - `ClinicView` scales drip, steam and dust by the season. `LocationView`
    draws rain, sleet, snow, leaves or haze (at most 70 particles; none
    with Reduce Motion).
  - `AudioManager` has a `rain` layer; the season sets a `season` mix
    modifier.

## 3.12: a world that reacts

No new managers, screens or save keys. Audit, plan and results are in
`docs/REACTIVE_WORLD_3.12.md`.

- **Rivals**:
  - `FactionManager.change_by_choice(id, delta)` is used by `EventManager.apply_outcomes` and `StoryManager.apply_effects`. It applies the change, and on a gain of `RIVAL_MIN_GAIN` or more, each faction in `factions.json` `rivals` loses `RIVAL_SHARE` of it (at least 1, at most `RIVAL_MAX_LOSS`).
  - `rival_losses()` is pure; `Standing.preview` folds it into the totals it shows.
  - Previews use the managers' own rules: `preview_by_choice()` and `preview_heat()` run the same `scaled_change()` (Faction Relations) and `scaled_heat()` (heat modifiers, criminal / corporate street reputation) as `change()` and `add_heat()`, and the same caps; street reputation uses `ReputationManager.applied_change()`, the diminishing returns and cap `change()` applies. Rivals lose a share of the gain actually made, after scaling.
  - Paid work and quest rewards use `change()` and stay neutral.
- **Conditions**:
  - `StoryManager.cond` adds `rel_min` / `rel_max` (cast trust), `dim_min`, `faction_max`, `max_heat`, `not_flag_any` and `any` (a list of conditions, any of which may hold).
  - `EventManager.conditions_met` accepts `story: {cond}`.
- **Effects**: `remember: {who: TAG}` (`MemoryManager`), `supplier: {id: trust}` (`SupplierManager.discover` + `change_trust`).
- **Cases**: `patient.referred_by` (shown on the door card, in the summary and in the file) and `patient.pay` (fee multiplier; the budget covers the fee).
- **Nav**: `{"answer": true}` brings back what's waiting (decision > scene > conversation) through `ClinicScreen.resume_story()`. The NEXT line and `Guidance` use it.
- **Tests**: `tests/reactive_tests.gd` (unit run) and `tests/narrative_probe.gd` `_reactive_case`.

## After 3.12: stabilization

- **Costs and requirements.** `EventManager.choice_costs(choice)` reads
  what a choice spends for certain (money, supplies, parts, tokens in
  event `outcomes` and their `effects`, COMMS `effects`, `security` fx,
  `supplier_favor` fx; risk branches are consequences, not prices).
  `get_choice_block_reason` treats those as requirements, so an event,
  street encounter, place event or COMMS reply (`CommsManager.block_reason`,
  checked in `act` and shown on the COMMS screen) can't be taken without
  them. Tested by `tests/resource_cost_tests.gd`.
- **Forced costs.** `BusinessManager.charge(category, amount)` is the one
  way to take a cost the player can't refuse (bills, fines, a crew's cut,
  severance): cash pays what it can, the rest becomes debt, and the whole
  amount lands in the day's ledger. `EventManager.apply_outcomes`,
  `StoryManager.apply_effects` and `StaffManager.fire` use it
  (`tests/payment_tests.gd`).
- **Ownership.** Only `BusinessManager` writes its debt, day and ledger,
  only `EconomyManager` the cash, only `CustomerManager` who is at the
  door and its schedule. Others call `add_debt`, `charge`, `spend` /
  `add_money`, `take_from_door`, `quiet_for`. `tests/ownership_tests.gd`
  scans the scripts for direct writes.
- **Surgery endings.** `SurgeryManager._finish` clears any open dilemma.
- **Save fixtures.** `tests/fixtures/saves` holds saves written by
  3.10.0, 3.11.0 and 3.12.0 (provenance in its README);
  `tests/save_fixture_tests.gd` loads them.
- **CI.** `.github/workflows/tests.yml` runs `tests/run_tests.sh` with
  Godot 4.3 under Xvfb on every push and pull request; only
  `ALL SUITES PASSED` passes it.
- **Deferred focus.** `UIManager.focus_later(control)` focuses a control
  at the end of the frame only if it is still in the tree and visible;
  screens and panels use it instead of `grab_focus.call_deferred()`.
- **Conversations open in the city.** A city talk comes off the shared
  story queue (`WorldSimulationManager._talk_for`), so one open at save
  time goes back on that queue like any other: after a reload you can
  pick it up from the same person at that place, or they come by the
  clinic. `dialogue_save_tests` covers it.
- **Art.** The surgical regions and the scan hologram come from
  `tools/art/regions.py` (drape and iodine ramps 12 and 13).
  `procedure_tests` fails if a step's point lands on the drape.
