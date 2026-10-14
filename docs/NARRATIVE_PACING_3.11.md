# 3.11: the slow burn (story cases, pacing, seasons)

Audit, plan and results for the narrative, pacing and seasons pass. The
architecture notes are in `docs/ARCHITECTURE.md` (3.11).

## Audit (before)

**Pacing.**

- The next patient knocked 1.2 s after the last one left, all day, without
  limit. Only finished jobs counted against the day (`surgery_capacity`, 3 or
  4), so declining a patient brought the next one at once.
- Walk-ins took a seat at 0.35 per hour while you were busy, on top of the
  door queue.
- A random event could fire after every operation (`EVENT_CHANCE` 0.4), so
  a busy night could stack three or four incidents.
- There was no quiet time between the patients: nothing to set a story
  beat apart from routine work.

**Narrative.**

- The story (acts, beats, cast conversations, flags, consequences, comms,
  quests, the Wall) works, but the central mystery (THREAD, the Lyra trial,
  "static" patients) only appeared in act 3. Acts 1–2 had no thread to pull.
- Story patients didn't exist. Patients were generated; the cast came to
  talk, not to be treated, so the operating table never carried the plot.
- The game had no cutscenes. Act changes were a toast.

**Calendar.**

- `TimeManager` had days, hours and periods but no seasons.
- Rain was drawn only in lower-city street scenes, every day.
- Ambient audio had no weather layer.

**Economy.** `tests/economy_sim.gd` (5 strategies × 3 seeds × 20 days on
the real systems) met every target.

## Plan

Everything is built on the existing systems. No new managers, screens,
panels or notification streams.

| Need | Where it lives |
| --- | --- |
| A daily schedule and quiet periods | `CustomerManager` (the existing arrival timer) + `data/time.json` `pacing` |
| Fewer incidents | `EventManager` cap, `pacing.max_incidents_per_day` |
| Story patients | `data/cases.json`, read by `StoryManager`; a case is an ordinary generated patient with an authored name, line and scan clue |
| Decisions with later consequences | existing events (`data/events.json`), flags, comms, Wall pins, the news wire, dialogue variants (`world_cond` `flag`) |
| Cutscenes | `data/cutscenes.json`, `StoryManager` queue, one modal (`CutscenePlayer`) built from existing art |
| Seasons | `TimeManager` (season, blend, weather by day), drawn by `ClinicView` / `LocationView`, heard through `AudioManager`, told by `WorldEventManager` |

## What changed

### Pacing

- **A day has a visit budget**: surgery capacity + 2 spare visits
  (`pacing.spare_visits`). Every arrival counts: at the door, from the
  queue, or a walk-in. Declining still costs a visit, so the night ends.
  A finished budget means a quiet clinic: "Nobody else is expected today",
  and the business day counts as full.
- **Breathers between patients**, by who just left: 2.5 s after a routine
  patient, 4 s after someone you know, 7 s after a story case, 1.2 s for
  the first of the day.
- **Quiet after a story case**: no walk-ins for 60 in-game minutes.
- **At most 2 random incidents a day** (`max_incidents_per_day`). Forced
  and story events are not capped.
- **Story cases replace a routine visit** instead of adding one: the day's
  story slot falls between the first and the third-from-last visit, and
  the case is that visit. At most one case every 2 days
  (`story_case_gap_days`).

### Story

- **Seven story cases** (`data/cases.json`), from day 2 to act 4. They seed
  the Lyra / THREAD mystery from the first week:
  - **Crane** (act 1): a dock worker's arms carry a grey filament.
  - **Too calm** (act 1): a 17-year-old's eye implant has a second chip.
  - **Dial tone** (act 2): a netrunner's implant broadcasts on a Lyra
    frequency.
  - **Rustline runner** (act 2): a gang runner carries the same lattice.
  - **Board clerk** (act 2): a clerk has found files she shouldn't have.
  - **Bed 14** (act 3): a runaway trial subject.
  - **Crane returns** (act 4, only if you met him): the filament has grown.
- **Each case ends in a decision** (an event card), with lasting effects:
  flags, cash, reputation, faction standing, letters, Wall pins, news, a
  cutscene and changed cast lines. For example, keeping Crane's sample
  changes what Ilse says in act 4. Freeing Bed 14 changes Static's return.
- A declined case sets `<case>_declined`. A case missed while its act ran,
  or whose person died, is marked `missed`.
- Routine patients are unchanged: they remain the income.

### Cutscenes

Eight short scenes (2–4 shots, about 3–6 s each):

- the opening;
- Mother's arrival;
- acts II–V (act III introduces Voss, act IV Ilse);
- the two endings of Bed 14.

The backdrops are art the game already has: the title key art, the clinic at
this hour, and the street scenes with today's weather. The faces are cast
portraits.

Each scene:

- plays once per save, in the clinic, before any queued conversation;
- moves on by itself; a click or SPACE moves on sooner;
- ends on ESC or SKIP;
- can be turned off in Settings (STORY CUTSCENES).

No patient knocks during a scene, and toasts wait underneath.

### Seasons

- **A year of four seasons** of 7 days each, in this order: autumn (day 1),
  winter, spring, summer, then around again. The last 2 days of a season
  blend into the next.
- **Weather by day**, deterministic per day (saves need nothing new):
  - autumn: rain and falling leaves;
  - winter: sleet and snow, with a snow line on the ground;
  - spring: thaw rain;
  - summer: heat haze and the odd storm.

  Some days are dry. Weather now falls on every street (lighter away from
  the lower city).
- **The clinic**: a faint seasonal tint. Drips from the ceiling are faster
  in the wet seasons. Steam rises more in winter and dust hangs in summer.
- **Sound**: a rain bed (`audio/ambient/rain.ogg`, generated by
  `tools/generate_audio.py`). It is quieter on dry days and indoors, and
  muffled in surgery.
- **Words**: the status stamp reads "DAY 8 · WINTER · 21:40 · NIGHT". The
  news wire marks the season's turn and mixes in seasonal items. Patients'
  greetings sometimes mention the weather.

## Results

Tests run on Godot 4.3, headless and under xvfb at 1920×1080.

**Full suite** (`tests/run_tests.sh godot`): the compile check, the balance
simulation (4 seeds), the economy simulation, job offers, stability, unit
and end-to-end tests, and the display, living world, city, UI, UI
stability, UX, onboarding, 3.10 and **3.11 narrative** probes.

**New unit tests** (`tests/narrative_tests.gd`, in the main runner) cover:

- season calendar, blend and weather;
- visit budget, story slot, breathers, quiet periods and walk-ins;
- the incident cap;
- save and load of every new key, and old saves without them;
- cases: due rules, arrival, the clue in the scan, success, failure,
  death, decline and missed;
- every decision and its echoes (letters, Wall, flags, dialogue);
- cutscene queueing, once per save, and the setting.

**New rendered probe** (`tests/narrative_probe.gd`) checks, with real
clicks and keys:

- the opening plays and nobody knocks;
- a chapter card ends on its own;
- SKIP and ESC end a scene, and a queued conversation follows;
- a story case at the door leads to its decision and its cutscene;
- the breathers, measured in real time;
- the clinic and a street in each season.

**Economy**: the same simulation before and after, median final money
after 20 days:

| Strategy | Before | After |
| --- | --- | --- |
| conservative | 10,292 | 9,799 |
| specialist | 6,809 | 5,682 |
| black market | 10,075 | 9,609 |
| investment | 851 | 2,587 |
| mixed | 1,480 | 1,576 |

Every target is still met (ECONOMY OK). Jobs per run are within a few of
before. The shifts are within the run-to-run spread. The simulation doesn't
make case decisions; their money is small (+120 to +600 once, against
1,000–2,000 cr profit a day).

## Performance

- Weather particles are capped at 70 per street view and skipped with
  Reduce Motion or with environment effects off.
- Weather is computed from the day number. Nothing new runs per frame in
  the managers.
- A cutscene holds one backdrop at a time and frees it on the next shot.
- The rain layer is one more looping stream in the existing mixer.

## Known limitations

- Acts 3–5 were exercised by unit tests and the probe, not by a full manual
  playthrough.
- Story patients look generated (portrait and body come from the patient
  generator). Only their name, words and clue are authored.
- The economy simulation doesn't play the case decisions.
- The status-bar stamp is longer and is cut off sooner on narrow windows.
- The existing dialogue panel logs a harmless `grab_focus` error when a
  conversation is closed within a frame of opening (only the probe does
  that).

## Decisions for the owner

- Season length (7 days) and the start season (autumn).
- The visit budget (capacity + 2), the breather lengths and the cap of 2
  incidents a day.
- One story case every 2 days at most, starting on day 2.
- Cutscenes on by default (Settings → STORY CUTSCENES turns them off).
