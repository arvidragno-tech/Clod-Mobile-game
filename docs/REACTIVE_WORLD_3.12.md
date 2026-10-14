# 3.12: a world that reacts (narrative, reputation, a clearer clinic)

Audit, plan and results for the reactive story, consequence-based
reputation and UI pass. The architecture notes are in
`docs/ARCHITECTURE.md` (3.12).

## Audit (before)

**Narrative.** The engine was already rich:
- acts, beats and flags;
- delayed consequences that resolve to a conversation, an event or a message;
- seven story cases (3.11), each followed by a decision;
- dialogue variants on flags, Wall pins, the news wire and cutscenes.

The gap was in what decisions led to:
- Most case decisions echoed as flavour letters (Bram's note, Bed 14's postcard). They changed little you could *do* later.
- The cast reacted to choices made in conversations. The patients who carry the mystery never came back changed by what you chose.

**Reputation.** There are plenty of measures already:
- street rep;
- five reputation dimensions;
- five faction standings (plus Lyra);
- heat;
- the cast's relationships;
- people's memories;
- seven ending paths.

So 3.12 adds **no new variables**. The problems were in how these numbers were used:
- `factions.json` lists each faction's `rivals`, but no code read it, so siding with one group cost nothing with its enemies.
- Story and case conditions could only check `faction_min`, flags and simple counters. Nothing could check trust, a reputation type, or "not too friendly with X".
- Standing changed prices and who walks in, but rarely brought an offer or a complication you could see.

**UI** (measured with `tests/audit_probe.tscn`, screenshots read by hand).
Passes 3.7–3.10 had already cut the clinic loop hard (−54% labels). What
was left was duplication and unclear wording:
- The clock appeared twice on the clinic screen: in the status bar, cut off at "BACK-ALLEY RO…", and again over the room.
- A waiting decision was announced twice: on the NEXT line ("Someone is waiting: deal with the incident") and in the bar under the room ("ACTION REQUIRED"). Neither line opened it.
- CLOSE FOR THE NIGHT (ends the day) sat next to CLOSE DOORS (pauses arrivals).
- The plan had BACK and RE-DIAGNOSE, which did the same thing, plus CANCEL.
- The risk line read "The intake exam rates this patient's physiology as medium risk; the cause isn't identified".
- The plan's advice read "Doable. Watch the implant, risk."
- Missing tools read "DRILL, DRILL T1": the same drill twice.
- The patient summary's DETAILS repeated the door card's advice line word for word.
- A story patient's own words were only in the FULL FILE. A player who took the short path (door → summary → accept) never heard the case.
- Story decisions were headed "INCIDENT", like a random event.

## Plan

| Need | Where it lives (existing system) |
| --- | --- |
| Rivals react to the side you take | `FactionManager` (`rivals` from `factions.json`), called from `EventManager.apply_outcomes` and `StoryManager.apply_effects` |
| Show the reaction before you choose | `Standing.preview` (event choices) and `DialogueManager.known_effects` (conversations) |
| Story reads standing and trust | `StoryManager.cond` (+ `EventManager.conditions_met` via `story`) |
| Opportunities and complications | story cases (`data/cases.json`), decisions (`data/events.json`), messages (`data/comms.json`), consequences, suppliers (`SupplierManager.discover` / `change_trust`), quests, the Wall, memories |
| Who sent a patient, what they say | `CustomerData.referred_by` (already in the file), the door card and the summary |
| A waiting decision you can reopen | `Nav` link `{"answer": true}` → `ClinicScreen.resume_story()` |

New cases take a routine visit's place, as in 3.11, so the clinic gets no busier.

## What changed

### Rivals react

`FactionManager.change_by_choice(id, delta)` applies the change. If the gain is 3 or more, each rival listed in `factions.json` also loses 40% of it (at least 1, at most 5).

- It applies to decisions only: event choices, conversation lines and message replies.
- Paid operations and quest rewards still use `change()` and stay neutral.
- The Free Contractors have no rivals, so neutral work stays neutral.
- The previews add the rivals' share into the totals, so what you see is what happens. For example, choosing SELL HIM TO AEGIS shows: "Aegis Meridian Security +6, Rustline Crews −10, The Undermarket −2 (rivals)".
- The standing history records the reason: "you sided with Rustline Crews".

### Story conditions

`StoryManager.cond` gains these keys:

| Key | What it checks |
| --- | --- |
| `rel_min` / `rel_max` | a named character's trust |
| `dim_min` | a reputation type |
| `faction_max` | an upper limit on a faction's standing |
| `max_heat` | an upper limit on heat |
| `not_flag_any` | none of the listed flags is set |
| `any` | at least one of several conditions holds |

Events can use the same conditions through a `story` block in their `conditions`.

### Effects

`StoryManager.apply_effects` gains two keys:
- `remember: {who: TAG}`: a cast member or a patient remembers what you did (`MemoryManager`).
- `supplier: {id: trust}`: an introduction to a supplier, plus that much trust.

Case patients gain two fields:
- `referred_by`: shown on the door card, in the summary and in the file.
- `pay`: a better fee, with a budget that can cover it.

### Branches (six cases, eleven decisions and echoes)

| Branch | Comes when | Opportunity | Complication |
| --- | --- | --- | --- |
| **Rook's lieutenant** (act II–IV) | Crews ≥ 15 and Aegis ≤ 10, or you warned the crews (3.11) and Crews ≥ 8 | A 1.6× fee. KEEP HIM HIDDEN → Rook remembers you kept a secret; 3 days later he asks a favour (2 supplies) that introduces Sallow, with credit from day one | SELL HIM TO AEGIS (+800 cr, labelled "Rook will find out") → Rook turns hostile and remembers the betrayal; 2 days later he comes to collect (600 cr, or 3 crates) |
| **Aegis retainer** (act II–IV) | Aegis ≥ 15 and Crews ≤ 10, or you called Aegis (act I) | A 1.6× fee. SIGN AND SEND THE NAMES → +500 cr, −10 heat, an introduction to Glass | 4 days later Rook asks about the fresh stitches. SIGN, SEND NOTHING → 5 days later Sato audits the blank reports (send names, pay it back, or tear up the card: −10 Aegis, +8 heat) |
| **The courier** (act II–IV) | You've sided with no one and neither Crews nor Aegis is above 14, **or** you refused Aegis's retainer, **or** you patched Rook's man without picking a side | An introduction to Okafor that costs nobody's goodwill (the neutral path stays viable) | None |
| **Bed 14 returns** (act IV–V) | You freed her (3.11) | She introduces the Curator (rare chrome at once). Her trial chart: keep it for Moor (Moor's evidence line changes), sell it to Wire (+900), or burn it | None |
| **Bed 14, Lyra's liaison** (act IV–V) | You sold her (3.11) | Lyra's stabiliser contract (an existing quest) | Refusing draws Lyra's attention (+5 heat) |
| **Pike's grudge** (act III–IV) | You sold his log (3.11) | Give him Wire's money back (he remembers) | Or tell him it was business: 3 days later your face is on every board (+10 heat or −300 cr) |

Echoes of earlier 3.11 decisions:
- **Pike, log copied:** 4 days later he offers a route into Lyra's annex (it appears on your map).
- **The clerk, files taken:** 6 days later she tips you off about an inspection (−12 heat, or pass the roster to the Crews).
- **The clerk, told to stop:** 5 days later she has been transferred and her files are gone.

Rules all branches keep:
- **Mutually exclusive:** once you've sided with the Crews or Aegis, the other never makes its offer, and the courier doesn't come either. Being trusted by both means neither asks you to choose.
- **Nothing blocks progress:** no act's advance condition reads a reactive flag (tested). Missing a case only means it doesn't happen.
- **Once each:** every new decision is weight 0 and `once`, and every case comes at most once.
- **Telegraphed:** the cost is visible before you choose: the betrayal says "Rook will find out", and the previews show standing and rivals. Relationships stay hidden, as in 3.7. You learn how someone took it by what they do next.

### Clinic UI

| Before | After |
| --- | --- |
| Clock in the status bar (cut off) and again over the room | Status bar: "DAY 1 · AUTUMN · 14:00 · DAY". Over the room: "BACK-ALLEY ROOM · THE SUMP" |
| "NEXT > SOMEONE IS WAITING: DEAL WITH THE INCIDENT" + "! ACTION REQUIRED · Someone is waiting for your answer." | "NEXT > DECIDE: THE BOUNTY", once. Clicking it reopens the decision if it isn't on screen. The bar under the room shows today's progress instead |
| CLOSE FOR THE NIGHT · CLOSE DOORS / OPEN DOORS | CLOSE FOR THE NIGHT · PAUSE ARRIVALS / LET PATIENTS IN (the field guide explains the difference) |
| Plan: BACK, RE-DIAGNOSE, CANCEL | BACK (to the scan) and BACK TO THE PATIENT |
| "The intake exam rates this patient's physiology as medium risk; the cause isn't identified. A scan can reveal conditions." | "Something in their body makes this harder than usual. A scan may show what." |
| "Doable. Watch the implant, risk." | "Doable, but you'll have to buy the implant and the patient is medium risk." |
| "Missing DRILL, DRILL T1" | "Missing DRILL T1" |
| Summary DETAILS repeated the door card's advice | Removed (the door card is right behind the summary) |
| Story patient's words only in FULL FILE | Their words in the summary, under "Sent by Rook Varga" when someone sent them |
| Story decisions headed INCIDENT | Headed DECISION (random incidents keep INCIDENT) |
| A story patient at the door: "Jobs are how you earn…" | "There's more to this one than the job. What you decide may come back." |

### Guidance

- The NEXT line names what's waiting and leads to it. The Guidance list does the same (`{"answer": true}`).
- A story patient's door line says the decision matters later, without saying how.
- There are no new hints, markers or notifications. The new messages are ordinary inbox items, one per consequence.

## Measured

`tests/audit_probe.tscn`: same seed, same flow, on screen at 1920×1080.

| Screen | Panels | Labels | Buttons |
| --- | --- | --- | --- |
| 1 Clinic | 5 → 5 | 18 → 18 | 6 → 6 |
| 2 Patient (click) | 6 → 6 | 25 → 25 | 10 → 10 |
| 2b Patient details | 6 → 6 | 32 → 31 | 12 → 12 |
| 3 Full file | 12 → 12 | 49 → 49 | 22 → 22 |
| 4 Scan | 5 → 5 | 19 → 19 | 16 → 16 |
| 5 Plan | 7 → 7 | 28 → 28 | 10 → 9 |
| 6 Surgery | 8 → 8 | 30 → 30 | 12 → 12 |
| 7 Clinic after job 1 | 5 → 5 | 25 → 25 | 9 → 9 |
| 8 Supply | 10 → 10 | 45 → 45 | 16 → 16 |

The counts barely move, and that's honest: 3.9 already removed the panels and buttons (−24% panels, −54% labels, −30% buttons). This pass fixed what the counts can't see:
- Text that said the same thing twice: the clock, the waiting decision, the advice line, the drill.
- A dead click: the "incident" line led nowhere.
- Two buttons with near-identical names and opposite meanings.
- Two buttons that did the same thing.
- Jargon.

Steps to answer a decision that isn't on screen: before, there was no way (you had to leave the screen and come back). Now it's one click on NEXT.

## Tests

- **Unit** (`tests/reactive_tests.gd`, in the main runner, 93 checks):
  - rivals: decisions vs paid work, no-rival factions, the cap;
  - previews match the real change, in events and conversations;
  - every new condition key;
  - data integrity: every echo, supplier and quest exists; decisions are weight 0 and once; no act depends on a branch;
  - each branch end to end, with delayed echoes landing on the right day, not before;
  - mutual exclusion, including after a reload;
  - no repeated decisions or favours;
  - old 3.11 saves (no new flags → no reactive case fires);
  - the NEXT link, the plain risk line, the advice phrases.
- **Rendered** (`tests/narrative_probe.tscn`, new section, real clicks):
  - "Sent by Rook Varga" on the door card;
  - his words in the summary;
  - THE BOUNTY headed DECISION, with rivals shown and the betrayal labelled;
  - with the decision closed: NEXT names it, the bar doesn't repeat it, and a click on NEXT brings it back;
  - choosing sides with the Crews.
- **Updated:**
  - `living_probe` (the clock is in the status bar, the room names the place);
  - `onboarding_tests` (ARRIVALS PAUSED);
  - the E2E bot (BACK instead of RE-DIAGNOSE).
- **Full suite** (`tests/run_tests.sh`): results are in the PR.

## Known limitations

- The new cases were played through unit tests and the probe, not a full manual playthrough of acts II–V.
- Case patients still look generated (as in 3.11). Only their name, words, referrer and clue are authored.
- The economy simulation doesn't make story decisions, so the new money (+500 to +900 once, −250 to −600 once) isn't in its numbers.
- Rival losses apply to dialogue choices written before 3.12, too. For example, giving Moor the evidence (+20 Board) now also costs the Undermarket 5. That is intended (taking a side has a price), but those numbers weren't retuned.
- The scan screen keeps one SCAN button per region. They are the keyboard path to a specific region, so I left them.

## Decisions for the owner

- The rival rule: 40% of the gain, from +3, at most −5 per rival.
- The thresholds for the Crews and Aegis offers (15, with the other side ≤ 10).
- The names PAUSE ARRIVALS and LET PATIENTS IN.
