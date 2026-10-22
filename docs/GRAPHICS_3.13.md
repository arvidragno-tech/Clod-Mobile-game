# Graphics pass 3.13: the operating field and the body scan

![Before (top) and after (bottom) of the five surgical regions, and the
old and new body scan](screenshots/surgical_field_3.13.png)

In game: [surgery at 1080p](screenshots/surgery_3.13.png) (compare the
older [surgery_1080p.png](screenshots/surgery_1080p.png)).

## What changed

**The surgical regions** (`assets/sprites/surgery/regions/*.png`, all five).
Before, each region was bare skin on a dark table. Now each one is a
prepared operating field:

- a sterile drape (new `drape` material ramp) with folds lit by the lamp,
  a shadow where it tucks under and a lit hem;
- an opening in the drape shaped to the site: an irregular oval on the
  back of the neck, chest and face, and an opening that follows the limb's
  taper on the forearm and thigh;
- an iodine prep band on the skin round the opening (new `iodine` ramp),
  laid in brush strokes;
- towel clamps holding the drape, and a few wet glints on it.

**The diagnosis body scan** (`assets/sprites/surgery/scan_hologram.png`).
Before, it was a filled silhouette with a few rib marks and a heart square.
Now it reads as a scan: skull and jaw, vertebrae, clavicles, ribs that
curve down, pelvis, the long bones of each limb, lungs, liver, stomach,
gut, a folded brain and dotted nerve trunks. The heart is still the one
warm colour. The silhouette is exactly the old one, pixel for pixel,
so the scan regions in `ScanView.REGIONS` are unchanged.

## Provenance

Everything here is drawn by this repository's own procedural scripts
(`tools/art/regions.py`, ramps in `tools/art/palette.py`). Run
`python3 tools/generate_art.py palette regions` to regenerate it; the
output is deterministic. No image was traced, upscaled, filtered or
taken from another game or franchise. The look follows ordinary
operating-room practice (green-blue drapes, iodine prep, towel clamps)
and the project's own [art bible](ART_BIBLE.md); it is not modelled on
any other game's art.

## Checks

- `tests/procedure_tests.gd` checks every point a surgery step asks you
  to touch (84 of them) against the region image, and fails if one lands
  on the drape. It also confirms it can see the drape at all (each region's
  corner is draped). The first limb drafts failed this check, so the limb
  openings were widened.
- The diagnosis screen was checked in the running game (`tests/ui_tour`,
  shots `04_diagnosis` and `04b_diagnosis_scanned`): the regions still
  scan by click and by button, and the labels sit where they did.
- The full rendered e2e run plays every category's operation on the new
  art.

## Gaps

This pass covers the surgery and diagnosis screens only. Not changed:

- characters and portraits, the clinic rooms, streets, the city map,
  cyberware and tool icons, and UI frames;
- the three surgery backdrops behind the field (mostly hidden by it);
- the on-field drawing of the step interactions (incision lines, rings,
  numbered points), which is code-drawn in `scripts/surgery/stages/`.

All art is still procedural pixel art. There is no hand-painted art.
