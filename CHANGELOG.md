# Changelog

All notable changes to *UNDERCITY: RIPPER*. Versions follow
`application/config/version` in `project.godot` and the Windows file version
in `export_presets.cfg`.

## Unreleased

- **A conversation open when the game closes is no longer lost.** Closing
  the window (or losing focus, which saves) during a story conversation
  used to drop it for good; Voss's ultimatum could leave act IV with no
  way out. After a reload it waits again and picks up on the line it was
  on, without anything it already did happening twice.
- **Decisions and incidents no longer replace each other.** When two came
  at once (consequences due the same morning, a story case's decision and
  other news, a patient coming back after an appointment arrived during
  the operation), only the last one was kept. Now each waits its turn and
  is answered in the order it came, and the line survives a reload.
- **Appointments are no longer missed while a decision waits.** The
  supplier's van, an inspection, the midnight deal and the late emergency
  used to be skipped for the day if anything else was waiting for an
  answer. They still come at their time (and only if they make sense
  then), once each; their decision now waits in line behind the other.
- `tests/run_tests.sh` fails on unexpected engine errors (a missing
  resource, `push_error`) and reports skipped suites as skipped.

## 3.12.0 — A world that reacts

Details, audit and numbers: `docs/REACTIVE_WORLD_3.12.md`.

- **Taking a side has a price.** When a decision wins you standing with a
  faction, its rivals lose some. The choice shows it before you pick.
  Paid work stays neutral.
- **Your standing and choices bring people to the door.**
  - The Crews or Aegis: a well-paid job from whichever side trusts you,
    then a request to sell out the other. You can't have both.
  - An independent courier if you stay neutral, or turn down a
    profitable side deal.
  - Bed 14 returns as a friend or as Lyra's liaison.
  - Pike returns for his grudge or offers a favour.
  - The clerk tips you off, or disappears.

  Favours, reprisals, audits and introductions to suppliers follow days
  later. None of it blocks the story.
- **A clearer clinic.**
  - One clock.
  - A waiting decision is named in NEXT, and a click brings it back.
  - PAUSE ARRIVALS instead of CLOSE DOORS.
  - One way back from the plan.
  - Risk and advice in plain words.
  - "DRILL T1" once.
  - Story patients speak in the summary, with who sent them.
  - Story decisions are headed DECISION.
- Saves from 3.11 load unchanged.

## 3.11.0 — The slow burn: story cases, pacing and seasons

Details, audit and numbers: `docs/NARRATIVE_PACING_3.11.md`.

- **A calmer day.**
  - Each day has a set number of visits (surgery capacity + 2). Declined
    patients and walk-ins count.
  - When they're used up the clinic goes quiet and you close when you're
    ready.
  - Patients knock after a short pause, longer after someone you know and
    longest after a story patient.
  - Nobody walks in for an hour after a story case.
  - At most 2 random incidents a day.
- **Story patients.** Seven cases from day 2 to act 4 bring the Lyra /
  THREAD mystery onto the operating table, a clue at a time. Each one:
  - takes the place of a routine patient, never adds one;
  - ends in a decision whose effects come back days or acts later, in
    letters, the Wall, the news and what the cast says.

  Routine patients are unchanged and still pay the rent.
- **Short cutscenes**: the opening, Mother's arrival, each new act and the
  end of Bed 14's story.
  - They are built from the key art, the clinic, the streets and the cast
    portraits.
  - Each plays once. ESC skips, and Settings → STORY CUTSCENES turns them
    off.
- **Seasons.** Every 7 days the season turns: autumn, winter, spring,
  summer.
  - Weather on every street: rain and leaves, sleet and snow, thaw rain,
    heat haze.
  - A seasonal tint and drips, steam and dust in the clinic.
  - A rain bed in the ambience.
  - The season in the status stamp, and a few seasonal news items and
    greetings.
  - Transitions blend over two days.
- Saves from 3.10 load unchanged: the new state is optional, and weather
  is worked out from the day.

## 3.10.0 — What the scan found, fairer jobs, selling from storage

- **CONDITION FOUND now says what it means.** The scan used to show the
  condition's name and the scan's evidence ("Abnormal platelet count…"),
  but not what it changes. Every condition already changes the operation
  through its own modifiers (bleeding, sedation, neural sync, complications,
  health drain, post-op risk, neural load), applied when the patient is
  generated, found or not. A finding now reads, for example:
  "! CLOTTING DISORDER: Bleeds heavily. Bleeds faster during surgery: keep
  COAG ready." Rejection-prone patients also name the REJECTION SPASM only
  they can get (counter: SEDATE). Conditions the odds estimate counts once
  found (complication risk, neural load) say so. The evidence moved to the
  tooltip.
  - The operation plan's FOUND row names each condition and what it
    affects ("Clotting disorder (bleeding)"), marked "!" as a caution,
    instead of "x 1 condition(s): see the patient's risks", which read as a
    blocker.
  - The patient's risk factors show the same explanation (one helper,
    `IntakeRecord.condition_effects`). OVERALL RISK stops saying the cause
    is unidentified once the scan has found one.
  - No new conditions or effects, no value changes: revealing still only
    changes what the doctor sees. Unrevealed conditions stay unnamed.
- **Fewer losing jobs.** Doable offers that cost more than they pay, from
  2,000 generated offers per stage (`tests/offer_sim.gd`), before → after:
  early 0% → 0%, street 12% → 5%, established 22% → 4%, late 7% → 1%.
  If 15% of operations failed, the share that would lose money is 28/42/36%
  → 19/22/11%. (Generation isn't fully seeded, so reruns vary by about a
  point.) The causes were:
  - Poor patients asked for top-tier chrome as often as rich ones, while
    the part is billed at their means. Requests now follow means: wealth
    0–1 patients mostly ask for tiers up to wealth + 2, and 25% still reach
    above it. Those are the deliberate bad deals.
  - The service fee ignored difficulty: an NX-1 and a Mnemos core billed the
    same. It now grows 10% per difficulty step above 1, like XP does.
  - The fee estimate billed the part at today's shop price while the payout
    bills the list price, so price swings made the estimate wrong.
  - "You keep" left out what the patient pays later on an instalment plan,
    so many paying jobs looked like losses. It is now the direct margin: the
    whole fee minus the implant and supplies. CASH TODAY in the details
    shows what lands now when part of the fee is owed.
  - Economy simulation, 14 seeds × 20 days: median profit a day is
    specialist 1427 → 1788, black market 1905 → 2300, mixed 532 → 797,
    investment 752 → 757, conservative 1467 → 1416. No run goes bankrupt,
    and the best clinic is still a goal.
- **Sell from storage.** Select an implant, tool or medical supplies in
  INVENTORY. The detail panel shows SELL with the name, how many you have,
  the price each, a quantity for supplies, and the total on the button.
  A confirmation shows your cash before and after.
  - Prices follow the black market's existing resale rule: 45% of the list
    price × condition, and never more than 80% of today's buy price, so
    there's no buy-and-sell loop. Implant units use the market's own
    `sell_value`, and black-market units still earn their token.
  - Not sellable: basic kit (no resale value), unidentified devices (they
    have their own routes), parts (the scrap stalls) and tokens. Also
    anything the operation you're planning needs: its implant unit,
    instruments and supplies.
  - Money goes through `EconomyManager` and is booked against the matching
    spending in the ledger. Saves need no new fields.
- **Tests:** `tests/clinic_310_tests.gd` (unit), `tests/clinic_310_probe.gd`
  (real clicks: scan → plan, sell a tool, sell 3 supplies with a double
  click on the confirm), `tests/offer_sim.gd` (offer distribution, in
  `run_tests.sh` with targets). The economy simulation's money target now
  also counts the resale value of clinics a strategy has moved out of: the
  investment strategy had passed it by 52 cr on 3.9.1, and sometimes buys
  its next clinic on the last night.

## 3.9.1 — The file, the scan, and why it went wrong

- **The patient's full file** shows the essentials open and the rest
  folded. Measured over the whole page (same seeded patient, before → after):
  labels 98 → 46, buttons 29 → 22. It now nearly fits one screen.
  - **Shown:** who they are (faction, traits, money), the procedure,
    difficulty and where the implant comes from, the fee, what they can pay,
    and the terms.
  - **Only when they apply:** missing tools, a backer, an existing debt.
  - **Folded:** standing, temper, street rep, risk, medical history,
    previous operations (hidden when there are none).
  - **In tooltips:** implant class and maker, implant value, the pay bonus.
  - **Removed duplicates:** AT A GLANCE lists only what needs attention plus
    the pay. The neural-load card is the meter, plus a line only when the
    job changes the band.
- **The scan:** one instruction instead of two, and plain rows instead of
  five cards (panels 10 → 5). A scanned region's SCAN button gives way to
  its finding, marked SCANNED or CONDITION FOUND. Diagnosis descriptions
  appear when the scans unlock the choice.
- **Surgery feedback:**
  - The first time a kind of mistake happens in an operation, a toast says
    what it cost (from the game's own effects) and what to do differently.
  - OK / ROUGH stages say how many mistakes they had.
  - A complication handled too late names the button that counters it.
- **Fixed: a mistake that took neural sync to 0 could fail to collapse the
  link.** The frame applied recovery before checking for failure, so a calm
  patient was lifted back to 0.03. The failure check now also runs before
  recovery, so the existing rule (neural ≤ 0 → collapse) always holds. This
  is the one gameplay-visible change. It surfaced as an end-to-end failure
  on a slower machine, and failed identically on 3.9.0.
- **Audit probe:** seeded, so before and after compare the same patients. It
  also counts the whole page, scrolled or not, since a shorter page can show
  more on screen at once.

## 3.9.0 — Less on screen

Every element now has to earn its place. Measured on the core loop
(`tests/audit_probe`): labels 542 → 248 (−54%), buttons 138 → 97 (−30%),
panels 79 → 60 (−24%). Details: `docs/UI_SIMPLIFICATION_3.9.md`.

- **The patient** opens on four things: what they want, one risk sentence,
  the money (pays ≈ X, you keep ≈ ±Y before rent) and ACCEPT JOB / DETAILS /
  DECLINE. DETAILS adds the odds, costs and every risk factor. The intake
  form and the full file sit one click further.
- **The clinic** keeps one objective (NEXT), SEE PATIENT and one status line.
  WHAT MATTERS NOW and the CLINIC STATUS card are merged into that line.
- **Status bar:** level, rep, jobs, heat and black-market currencies appear
  only once they mean something.
- **Plan, surgery and supply** show what you need to decide now. Specs and
  breakdowns are under DETAILS or in tooltips.
- **Results:** at most two new items in AFTERMATH, so CONTINUE always fits.
- **Tutorial:**
  - one short step at a time, on the real control: clinic → patient → scan
    → plan → sedate / cut / install / close → result → skills;
  - new sections are introduced the same way, "NEW · SECTION" on their
    button. The intro cards are gone; the field guide can replay any of them.
- **Sections appear when they matter:** SKILLS after the first job; SUPPLY
  when you're short (or the second job); INVENTORY and JOURNAL at the second
  job; BUSINESS on day 2; DATABASE, STAFF and FACILITY at the third job; the
  CITY at the fourth (or when a lead points there). Hidden sections can't be
  opened by hotkey or link early. Old saves keep everything they had.
- **One setting:** TUTORIAL & GUIDANCE (GUIDED / BRIEF / OFF) replaces
  three.
- No changes to generation, surgery, odds, economy, reputation,
  progression or the save format.

## 3.8.0 — The intake form

- **Patient intake form.** The patient summary now shows each patient's record as an in-world document: SUMP CLINIC // PATIENT INTAKE, with a document number, a timestamp and a RECEIVED stamp. It has four sections:
  - **1 · Patient:** who they are, affiliation, debts, patience.
  - **2 · Requested procedure:** implant, procedure, difficulty, instruments, added load, chrome already in the slot.
  - **3 · Complications & risk factors:** each with what it is, why it matters and what it affects.
  - **4 · History & disclosures:** statement, history, installed chrome, past jobs, findings, and what is still unknown.
- Every line says where it comes from: **REPORTED**, **ON FILE**, **CONFIRMED**, **SUSPECTED** or **UNKNOWN**. Emphasis comes from the game's existing bands, with a mark and a word.
- Presentation only: no new attributes, rolls, checks or calculations. Conditions the scan hasn't found are never named or counted, and scan findings stay on the scan table.
- Fixed: the summary and the odds estimate could hint that a patient had a hidden condition (via the true neural load and the complication risk). They now use what the doctor can see. The surgery's real roll is unchanged.
- The side bar's long labels trim instead of widening the bar.
- Details: `docs/INTAKE_FORM.md`.

## 3.7.0 — Easy to learn, still deep

The clinic now grows with you: new sections appear when they become useful,
every patient opens on a one-screen summary, and the clinic says in one line
what needs you. Audit, plan and results: `docs/UX_OVERHAUL_3.7.md`.

### The patient summary
- Clicking a patient (the room, SEE PATIENT, or the customer key) opens a **PATIENT SUMMARY**, not the full file. It has four blocks:
  - **REQUEST:** the implant, what it does, the procedure and known conditions.
  - **OPERATION:** difficulty in words, **your odds** as an estimate with what it's based on, what can go wrong, and anything missing, with a button to fix it.
  - **FINANCES:** what the patient pays, the implant and supplies, and the **direct margin** (labelled as before rent and wages). It adds cash in hand when the implant comes from stock.
  - **DECISION:** ACCEPT JOB, DECLINE (its real cost shown) and MORE DETAILS (the full file).
- Every number comes from the game's own rules (`JobEstimate`, `Recommend`, the operation's readiness checks). ACCEPT JOB waits while tools or supplies are missing.
- The patient's own words are shown as flavor: quoted, slanted and dim.

### Clinic status
- CLINIC STATUS is one headline (READY FOR PATIENTS, DOORS CLOSED, CAN'T OPERATE: NO SUPPLIES, PATIENT WAITING: MISSING TOOLS, FINANCIAL CONCERN, ACTION REQUIRED, DAY'S WORK DONE) with why it matters, plus up to three issues that need you. Each line is clickable.
- During the first patient it shows only the headline. WHAT MATTERS NOW no longer repeats the dashboard (supplies, money, heat, doors, staff).
- The NEXT line says why each step matters, and marks optional steps "WHEN YOU'RE READY".
- The door card is short: who, what, roughly what it pays and one line of advice.

### Sections appear when they're useful
- A new game starts with the clinic, settings and the field guide.
- After the first job: SKILLS, SUPPLY, INVENTORY, BUSINESS and the JOURNAL (a message can bring the journal sooner).
- After the second job: CYBERWARE DB.
- Three jobs in: STAFF and FACILITY.
- Four jobs in, or when a lead points into the city: the CITY MAP.
- The black market keeps its own rule.
- There are no padlocks. Each new section arrives with a card (WHAT / WHY / HOW / COST, OPEN, MORE) and is marked NEW in the side bar for a day. A hidden section's key says when it opens.
- Saves from before 3.7 keep every section. **INTRODUCE FEATURES GRADUALLY** (Settings > Gameplay) turns this off.

### Before you pay
- **BEFORE YOU PAY** in SUPPLY (implants and tools) shows:
  - the cost and your cash now → after;
  - the stock you'd have;
  - what it's for and its limits;
  - a warning when it leaves less than tonight's bill.
- FACILITY upgrades show the same, plus the new nightly upkeep.
- Buying a clinic asks first, with the cost, cash after and how the nightly rent and jobs change.
- Hiring shows cash after and the nightly wage.
- Black-market and supplier buys show the same facts, plus the heat and standing they cost.
- Conversation choices show their **known** public consequences (faction standing, street rep, heat, money). How a person feels about it stays hidden.

### The field guide
- Categories match the game: GETTING STARTED, PATIENTS & IMPLANTS, SURGERY, BUSINESS, REPUTATION & RELATIONSHIPS, CITY & LOCATIONS, CLINIC & STAFF, TUTORIALS, CONTROLS.
- Entries for sections you haven't met yet wait (with a count). Newly opened ones are marked NEW.
- Core entries add WHY IT MATTERS and WHERE. SEE ALSO links related entries, and BACK returns.
- **TUTORIALS** lists every card you've seen, with SHOW AGAIN.
- New entries: your odds (success estimate) and direct margin.

### Consistency
- One word per action: SEE PATIENT, ACCEPT JOB, DECLINE, MORE DETAILS.
- Declining's costs (`DECLINE_FACTION_PENALTY`) and black-market purchase effects (`BUY_HEAT`, `BUY_STANDING`) are shared constants, used by both the rule and its preview.

## 3.6.0 — Steadier, fairer, clearer

A quality pass. The game has the same systems; what changed is how they hold
together. Root causes and the numbers behind each fix are in
`docs/QUALITY_PASS_3.6.md`.

### Close the doors
- **CLOSE DOORS / OPEN DOORS** in the clinic's TODAY card stops walk-ins and keeps the waiting room empty. You get time to read, shop, level up and plan. Whoever is already in the chair stays. The clock and the bills keep running, and the doors open again every morning. WHAT MATTERS NOW reminds you while they're shut.

### Menus, clicks and scaling
- Shop and black-market BUY buttons no longer move under the cursor. The detail panel has a fixed width and keeps the item you were looking at across refreshes.
- A double-click buys once. Black-market buys find the offer by its id, not its place in the list.
- A click during a screen fade is queued, not dropped. The field guide closes on an outside click without eating it.
- There is one source of scaling, the window. UI SCALE is folded into TEXT SCALE. The text slider applies on release. Settings writes no longer re-theme the screen. Window changes keep your window size.
- Layouts fit at TEXT SCALE 1.4 with LARGE TEXT: the status bar, clinic, facility, inventory, map, database compare and diagnosis plan scroll or wrap instead of pushing buttons off-screen.

### Surgery
- The stage's instrument is picked for you. Near misses, wrong order, a wire dropped off a terminal, SEAT before PLACE and quick actions on cooldown all say what happened instead of doing nothing.
- Keyboard rotation steps fit the implant's tolerance, and dragging rotates 1:1. Anesthesia can be topped up (at a small quality cost). The cautery ring shows its real reach.
- Each procedure family has its own instructions and feel: eyes are fine and precise, dermal is forgiving, limbs are heavy, spine needs a careful drill, neural has more calibration rounds. A correct clean-site diagnosis skips the duplicate debridement step.
- Shorter waits between stages and before the results. The results count-up can be skipped. **THE MONEY** shows the fee, the patience cut, what was paid and what is owed, the implant and supplies used, and the net.

### Economy
- Parts are paid back at 90 % of their price (capped by the district's pay), so jobs with a bought implant no longer lose money by design.
- A black-market part has no paperwork, so patients pay 80 % of the usual part price for it. Cheap off-the-books chrome is a saving, not free money.
- A patient's shortfall becomes an instalment plan automatically. Staff jobs use the implant and supplies they need. Mothballed clinics pay half rent and no running costs. Your own debt's interest is 4 %/day (was 8 %).
- Before a job, the customer file and the plan show **PAYMENT**, **USES UP** and **YOU KEEP**. BUSINESS has an **OUTLOOK** for the next three days. If it projects a loss it says why and what to do.
- `tests/economy_sim.tscn` plays five strategies (conservative, specialist, black market, investment, mixed) on the real systems. Each seed gives exactly the same run, and the sim checks progression targets.

### Standing
- The journal's **STANDING** tab (was FACTIONS) keeps reputation, faction standing, personal relationships, trust and authority heat apart. Each shows its value, trend, what it does now, the next threshold and its own history.
- Every change records its real cause, written down when it happens (an operation and its grade, "Turned away <name>", "Bought from <supplier>", "Closing for the night", "Event: <title>"). Repeats with the same cause batch, and the history is bounded (200 entries) and saved.
- Choices in events show exactly what they'll change in standing, or "Risky (x%)" when it depends on a roll.
- Heat uses one set of thresholds everywhere (MEDIUM 25, HIGH 50, CRITICAL 75). The reputation ladder gains "Distrusted" before "Butcher".

### Less to read
- The side bar is grouped into four places: **CLINIC**, **BUSINESS**, **CITY**, **MESSAGES & JOURNAL**.
- **GUIDANCE** (Settings > Gameplay): MINIMAL shows only critical and important lines, only the status rows that aren't fine, and no first-time cards. STANDARD is the default. DETAILED shows more lines, the numbers behind each status row, and a notice for important changes. Presentation only: the rules don't change.
- First-time cards wait until you're not operating or talking. Only critical changes interrupt, and the same notice never stacks twice.
- New field-guide entries: closing the doors, standing, the outlook, the money on a job, guidance.

## 3.5.0 — The game tells you what matters

### What should I do?
- **WHAT MATTERS NOW** on the clinic screen: everything that needs you, read from the live game (an emergency, a patient at the door, supplies out, heat, debt, people waiting to talk, messages to answer, quest deadlines, returning patients, deliveries, staff close to breaking, skill points, new leads), ranked ■ critical, ▲ important, · info. Click a line to go straight there. The NEXT line is clickable too.
- **CLINIC STATUS:** money, reputation, staff, supplies, authority heat and the black market, one word each with ✓ / ! / ✕, plus the one thing that matters most and what to do about it.
- **Recommendations:** the customer file says who should operate and why; the ASSIGN list ranks your ripperdocs by their real odds and marks the best ★ RECOMMENDED with a reason; inventory picks the best unit in stock.

### Before and after a decision
- **SURGERY PREVIEW** replaces the plan's ready panel: patient, procedure, difficulty, patient risk, time, cost, pay, complication odds and which ones could happen, your odds (from your record and level) and who's recommended, with CHANGE SURGEON, RE-DIAGNOSE and CANCEL.
- **Consequences:** big decisions (conversations, events, black-market deals, services, handing a job to staff, answering comms) show what actually changed (credits, reputation, each faction, heat, supplies) with ▲ / ▼, and say when something was set in motion.
- **Results** list what the job opened up (leads, places, quests, messages, news) with VIEW PATIENT and VIEW NEW LEAD.
- **RECENT CHANGES (G):** what moved while you were busy, merged by subject, newest first, with NEW marks and links; critical ones also toast.

### Finding your way
- **☆ FOLLOW** quests, people, patients and places; the journal's MAIN page keeps them up to date with where and when, and the map stars followed places.
- **The journal** is reorganised into MAIN, MESSAGES, PEOPLE, PATIENTS (filters), FACTIONS, BUSINESS and DISCOVERIES (story, news, places, the wall).
- **Smart filters:** inventory by category plus "fits this patient", "low risk", "good condition", "known traits"; staff by availability, stress and specialty.
- **The map** lists who's at a place and their role, with FOLLOW.
- **Learn as you go:** the first time a system shows up (neural load, the preview, priorities, heat, the map, follow, the black market, staff, emergencies, changes, the journal, consequences), a small card explains it in two sentences with MORE for the field guide. It never blocks; TUTORIAL HINTS in Gameplay turns them off and RESET HINTS shows them again.
- **The pause rule:** reading screens, the field guide and dialogs stop an emergency's countdown; the field guide also pauses an operation.

### Custom controls
- Every action has a primary and a secondary key; modifiers (CTRL / SHIFT / ALT) and mouse buttons can be bound; a search box filters actions; categories each have RESET CATEGORY; each action has ↺ and there's RESET ALL CONTROLS (with a confirmation).
- Conflicts open a dialog: REPLACE (the other action is left unassigned), SWAP, or CANCEL. Pause, dialogue continue and the contextual action always keep a key.
- Presets DEFAULT, WASD and LEFT-HANDED; changing a key makes the layout CUSTOM. A first launch offers DEFAULT or CUSTOMIZE.
- Input is context-aware and central: typing in a text field, the field guide, dialogs, conversations and rebinding each own the keyboard, and ESC closes the topmost thing first.
- Every on-screen key hint (sidebar, coach marks, help, dialogs, the field guide) shows your current key. New actions: back to the clinic (H) and recent changes (G).
- The keybind table scrolls on its own, so PRESET and MOUSE stay in view.

### Under the hood
- New: `InputContext`, `ChangeLog` and `Follows` (both saved), `Guidance`, `ClinicStatus`, `Recommend`, `Consequence`, `Hints`, `Nav`, `ChangesPanel`.
- Tests: `tests/ux_tests.gd` (controls, persistence, contexts, change log, follows, guidance, recommendations, consequences, hints, navigation) and the rendered `tests/ux_probe.tscn` early-game probe at four resolutions and three window modes.

## 3.4.0 — New art style: more pixels, more detail, readable type

### Readable type
- Every text in the game uses two straight, readable cyberpunk faces: **Chakra Petch** (body, buttons, headers, titles) and **Share Tech Mono** (numbers, terminals, logs), with DejaVu Sans as the glyph fallback. The old pixel fonts are gone. The title face is rendered as a signed-distance font so it stays crisp at any size.

### Twice the detail
- **World art density:** rooms, characters and street scenes are drawn at 1.5x the resolution and shown at 2 screen pixels per art pixel (was 3), so the same screen area holds more than twice the pixels.
- **Clinic rooms (600x336):** rebuilt with a new lit-scene renderer in the style of a dense cyberpunk workshop: pipes, conduit, breaker boxes, AC units and cable bundles on the walls; barred windows onto a neon street; catwalks; consoles with lit keys and live screens; a surgical lamp that lights the table; wet floors that mirror the room; floor cables, a drain and foreground silhouettes. All 126 upgrade props are redrawn too.
- **Characters:** portraits are 144x168 and in-room bodies 60x120. Faces have lidded almond eyes with a limbal ring and two catch-lights, lips with a cupid's bow, nostrils, ear folds and finer brows; hair is drawn in fine strands; outfits get stitching, zips, buttons, buckles and screws; stubble and shaved sides use an ordered stipple instead of noise. In-room bodies get real faces, laces, cuffs and finger shading.
- **Street views:** every city location has its own HD street scene, night and day: layered hazy skylines with lit floors and holo ads, the place's own front (tenement balconies and laundry, the bar's lit interior, lantern-lit market stalls, the flood-tunnel bazaar, furnace bays, the transit arch, plaza towers, the checkpoint), lamps, cables and reflections. People, police lights, rain and the hour's light move on top.
- **Title screen:** a new neon-alley key art (960x540) with the clinic door under its cross sign. The black-market banner is redrawn at HD.

### Under the hood
- `GameConfig.ART_SCALE` (2) for world art; `GameConfig.BODY_ART_W` lets bodies of any resolution keep their size in the room.
- New generators: `tools/art/hd.py` (numpy lit-scene kit), `rooms_hd.py`, `streets_hd.py`, `characters_hd.py` with `hdc_*.py`; `python3 tools/generate_art.py rooms streets chars` (needs Pillow and numpy). The v2 character and clinic generators are removed.
- Clinic layout data (wall pins, waiting spots, hotspots, animation anchors) is in HD art pixels; `PixelPortrait` keeps its layout framings and scales them to the atlas.

## 3.3.0 — Clearer, better-looking UI

### Easier to understand
- **FIELD GUIDE (F1, also in the sidebar and the pause menu):** every number and word in the game explained in plain language, by topic (basics, patients, surgery, money, street and factions, the city, staff, controls) and searchable.
- **Explanations where you need them:** hover any status-bar value (credits, level, reputation, heat, supplies, parts, tokens, today's jobs) for what it means plus the live details; click it for the full explanation. Stat captions across the inventory, shop, database, customer file, plan and staff screens do the same (help cursor), and section headers carry a "?" chip. Sidebar sections say what they're for on hover.
- **AT A GLANCE:** the customer file and the door card now say whether you can do the job right now (implant, tools, supplies, difficulty and time, neural load, risk, pay) with ✓ / ! / ✕ marks and one line of advice ("You're missing tools: buy them in SUPPLY first, or defer"). The door card and the customer file use the same fee and risk.
- **The body scan, redesigned:** a bigger scanner with readable labels beside the body, a findings list with one row per region (status, what the scan found, conditions in red) and a SCAN button for each (keyboard-friendly), and each diagnosis shows its description.
- **The operation plan** says why BEGIN OPERATION is blocked, or that you're ready.
- **TODAY on the clinic screen:** four labelled meters (night left, jobs and tonight's bill, supplies and implants, heat) instead of lines of text; the status bar's JOBS is now today's jobs out of what the clinic can take.
- **Waiting** tells you what to do meanwhile, and what to do when the day's work is done.

### Better looking
- One readable bold face on every button (the wide pixel title font stays for titles), larger tooltips, section headers with a coloured bar and a rule, panels lit from above with a soft inner line.
- **Character art:** new eyes (almond shape, round iris with a dark rim, pupil, catch-light, lid crease and lash line; fear, anger, sadness and pain change them), hair drawn in strands instead of speckle, cleaner portraits (no scanlines over faces). In-room bodies get a nose, mouth and cheek shading and now wear what the portrait wears on the face and head (masks, scarves, eyewear, caps, hoods, helmets).
- **ROOM BRIGHTNESS** (Settings > Graphics): the clinic and the street views lift their shadows (a little brighter by default) without washing out the light.

### Under the hood
- `Glossary` (data/glossary.json), `JobVerdict`, `UIKit.section_head / info / caption`, `assets/shaders/room_light.gdshader`, `Settings.brightness`, the `help` action (F1).
- Tests: `tests/ui_overhaul_tests.gd` in the unit run; `tests/ui_probe.tscn` (rendered, mouse + keyboard, 4 resolutions, 3 window modes); `tests/ui_tour.tscn` and `tests/portrait_sheet.tscn` for screenshots.

## 3.2.0 — The living city

Caldera has places now: few of them, each with a job, people and things
that happen. DISTRICT → LOCATION → PEOPLE → FUNCTION → EVENTS.

### Places
- Twelve places in the seven districts: your clinic, the Pipeworks Tenements and Caldera Stacks (residential), the Rusty Valve and the Orchid Room (bars), the Flood Tunnels (the Undermarket in person), Furnace Line Works (industrial), the Glow Strip Night Market, Spindle Interchange (transit), Meridian Medical Plaza (corporate), and in the Lyra Exclusion Zone, Checkpoint 9 and the Research Annex.
- Each place has opening hours, activity by hour, danger, police, faction presence, a street view drawn from its district's palette and its kind, and a state: busy, quiet, dangerous, police presence, monitored, someone's turf, unwelcome, black market active, closed, something happening, a lead.
- What you can do there (22 services): visit your patients at home, ask around, buy a round and listen, look for staff, hand out cards (someone comes to your clinic), work the room, meet a fixer, the Undermarket in person (10% cheaper) and walking the stalls (new stock, maybe a new supplier), a forged badge, salvage, a cheap tool service, market-price supplies (cheaper after dark), fencing parts, courier jobs, a metro pass, a licensed shift, certified stock, a contractor pass, the checkpoint (bribe or fence), the annex's cold storage and records.

### Getting around
- The city map shows the places you know, their state, where you are and where something is happening. Click a place: what it's like, who's there, what you can do, and how to get there.
- Walk (free, slow, risky after dark in the lower city), metro (cheap, 06:00–01:00, down in a blackout, never into the Zone) or cab (fast, dearer at night). The clock moves with every trip. Things can happen on the way (a mugging, a checkpoint, a wounded stranger, a courier offer).
- Out of the clinic, nobody new walks in; whoever was at the door sits down if there's room; you can't walk out on an emergency; nights out make break-ins likelier. RETURN TO CLINIC is always one click.

### People
- Your patients live somewhere, work somewhere and drink somewhere, and follow a routine through the day (home → work → the interchange → the bar → home; night workers the other way round). You can find them, check on them (the shaky ones come in), and they tell you about places.
- The story cast keep haunts (Rook at the Valve, Wire in the Orchid Room and the tunnels, Voss and Moor at the Plaza...), and a conversation waiting for you can happen where you find them. Staff take a break at their bar. Suppliers keep tables at their haunts; strangers with sample cases become contacts.
- A patient with risky chrome can go missing: their family writes, their home has a clue, the clue leads somewhere, and what you do there decides whether they live.

### Events and factions
- Forty ambient events at places: bar fights, fixer meetings, raids, accidents on Line 3, stings in the tunnels, inspections, cover-ups, an extraction in the Plaza, a strike, and in the annex, bed 14. Many send someone to your clinic.
- Faction presence is physical: news of a takeover or a gang war puts that faction on the street; what you do at a place shifts who feels at home there (and it drifts back). Hostile to whoever runs a place: unwelcome, services closed, prices up. Friends get a discount.
- Discovery: start near the clinic; more opens with your level, black-market contacts and the story; patients, the cast, fixers, rumours and suppliers tell you about the rest. The Exclusion Zone opens through a contractor pass, a forged badge, a bribe, the fence, or a scavenger's route.

### Under the hood
- New: `LocationManager`, `WorldSimulationManager` (both saved), `LocationServices`, `TravelFlow`, `ChoicePanel`, `LocationView`, the location screen, `data/locations.json`. Old saves load with the places they should know.
- The journal shows where your patients live and work and where they are now, and where the cast are right now.
- Tests: `tests/living_city_tests.gd` in the unit run, `tests/city_probe.tscn` (rendered, mouse + keyboard, 4 resolutions, 3 window modes), city outings in the stability soak, a place in the release smoke test.

## 3.1.1 — Follow-ups and audit fixes

### Follow-ups
- Unidentified devices stay unidentified everywhere (inventory, operation plan, surgery): no name, grade, condition or properties until analysed. Installing one blind reveals what it was; cautious patients refuse to take one.
- Each clinic defines its own wall space for the Clinic Wall and its own waiting spots, placed clear of that room's props; the Wall's hotspot follows.
- New setting: GAMEPLAY > EMERGENCY COUNTDOWN (normal, relaxed ×2, off).
- The hour's colour is now a colour multiply on the room (no extra full-screen pass) and the Wall is pre-rendered. Measured against 3.0 on the same machine, the clinic costs the same.
- Two new score pieces: a sparse night variant and a tense variant (pressing double kick, heartbeat). The clinic switches between them with the hour and the tension, with hysteresis so it doesn't flap.
- Conversations react to who you've become and what people remember: line variants and options by street identity, reputation and memories in six conversations (Mother, Inspector Moor, Voss, Teo, Wire, the Landlord). Identity and memories also move check odds (a remembered lie makes the next one harder; the saint is better at empathy; the gang doc at intimidation).

### Fixes
- Payment-terms memories are only recorded when treatment was actually paid for (FREE + REFUSE/DEFER no longer farm reputation).
- A patient who dies has their debts closed: no more instalments from the dead.
- A specialist save is remembered once, not twice.
- First-time patients remember what happened in a surgical dilemma (they are registered before the memory).
- The emergency countdown lives on the patient: reopening the file no longer resets it and walking away no longer pauses it (it still stops during surgery, dialogs and pauses, and respects the new setting).
- A waiting-room complaint now shortens patience instead of lengthening it.
- Staff rivalry XP is granted.
- Firing a disloyal employee can now really come back to bite you (their grudge arrives in COMMS).
- Trimming old people never forgets someone who owes you a favour or is due back, and removes the memories of people it forgets.
- Crew or corporate money stays that way when a patient's wealth changes (BACKER PAYS doesn't vanish).
- The table stays frozen while you read a dilemma's outcome; it resumes when you go back to it.
- A dilemma choice with no failure outcome can't "go wrong".
- Stopping an operation before the implant goes in returns the unit to stock.
- Confiscation takes every black-market unit (it skipped some); thefts no longer re-sort your stash.
- You can't buy a tool you already own from a supplier.
- Contacts bring out more stock after dark (night multipliers now apply).
- RUSH means something: ordinary supplier orders arrive at opening the next morning; RUSH delivers now.
- Two quick music changes can no longer leave the score silent.
- Teo caught stealing is gone from the story for good.
- "Fight back" in the crew raid now really hurts you (shaky hands for three jobs).
- TO THE CURATOR is disabled when the Curator has cut you off, and says so.
- Accusing a suspect is a two-click confirm inside the SECURITY panel (cancelling no longer closes the panel).
- The status bar's location and clock line is clipped with a tooltip, so long clinic names can't push MENU off-screen.

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
