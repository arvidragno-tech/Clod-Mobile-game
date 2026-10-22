# Surgical procedures

Each implant category has its own operation (`data/surgeries.json`). They share the clinic's basic moves (sedate, cut, clamp, seat, stitch) and differ in the rest: which steps they need, in what order, and one signature step no other category has. `tests/procedure_tests.gd` checks that no two categories share a sequence and that each signature step belongs to one category; the end-to-end bot plays every category through the real screens.

## The matrix

Numbers are the step's place in that operation.

| Category | Sedate | Cut | Clamp open | Burn tissue | Drill anchors | Ordered points | Seat implant | Hold steady | Splice wires | Calibrate | Stitch |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| neural (`install_basic_neural_implant`) | 1 | 2 | 3 | 4 |  | 6 **★** | 5 |  | 7 | 8 | 9 |
| spine (`install_spine`) | 1 | 2 | 3 |  | 4 | 5 **★** | 6 |  | 7 | 8 | 9 |
| arms (`install_arm`) | 1 | 2 | 3 | 4 | 5 |  | 6 | 7 **★** | 8 | 9 | 10 |
| legs (`install_leg`) | 1 | 2 | 3 |  | 4 |  | 5 | 7 **★** | 6 |  | 8 |
| eyes (`install_optic`) | 1 | 2 | 3 | 4 |  |  | 5 | 7 **★** | 6 | 8 | 9 |
| dermal (`install_dermal`) | 1 | 2 | 3 |  |  | 4 **★** | 5 |  |  |  | 6 |
| respiratory (`install_respiratory`) | 1 | 2 | 3 | 4 |  |  | 5 | 7 **★** | 6 |  | 8 |
| internal (`install_internal`) | 1 | 2 | 3 | 4 |  | 5 **★** | 6 |  | 7 | 8 | 9 |

★ marks the signature step.

## Signature steps

| Category | Step | Interaction | What goes wrong |
| --- | --- | --- | --- |
| neural | MAP THE CORTEX | `sequence` | `nerve_misfire`: The bridge listens before it speaks. Touch the live nodes in the order they light, or it learns the wrong map. |
| spine | THREAD THE SPINAL BUS | `sequence` | `cord_nick`: Feed the bus down the vertebrae, top to bottom. Skip one and you nick the cord. |
| arms | TENSION THE TENDONS | `hold_steady` | `tendon_slip`: Hold the tendon line taut while the actuators lock onto it. Let it pull you and it slips. |
| legs | LOAD TEST | `hold_steady` | `joint_buckle`: Put weight through the new joint. Follow the knee as it settles and keep it from buckling. |
| eyes | HOLD THE GAZE | `hold_steady` | `retina_scuff`: The eye drifts under sedation. Hold on the pupil ring and follow it until the lens fuses. |
| dermal | LAY THE PLATES | `sequence` | `plate_overlap`: Subdermal plates overlap like scales. Lay them in order or they ride up and cut. |
| respiratory | SEAL THE AIRWAY | `hold_steady` | `air_leak`: Pressure on. Hold the seal ring over the junction until the gasket sets. |
| internal | CLAMP THE VESSELS | `sequence` | `vessel_tear`: Clamp from the heart outwards. Close a downstream vessel first and the pressure tears it. |

## The two new interactions

- **`sequence`** (`scripts/surgery/stages/sequence_stage.gd`): points worked in one order. The next point pulses and is numbered; touching a later one first is the step's mistake. Neural maps cortex nodes, spine threads the bus down the vertebrae, dermal lays plates like scales, internal clamps vessels from the heart outwards.
- **`hold_steady`** (`scripts/surgery/stages/hold_steady_stage.gd`): hold on a ring that drifts with the patient until it sets. Slipping off while holding is the step's mistake (at most once a second); letting go only pauses. Better tools shrink the drift and shorten the hold. Eyes hold the gaze while the lens fuses, arms keep tendons taut, legs follow the knee through a load test, respiratory holds the airway seal.

Each signature step added 15 seconds to that operation's target time.

The diagnosis screen is unchanged: each operation keeps its own scan region, diagnosis options and findings.
