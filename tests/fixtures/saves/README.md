# Save fixtures

Each file here was written by the release it is named after, by that
release's own `SaveManager`, not by hand and not by the current code.

| File | Written by | Commit | Game state when saved |
| --- | --- | --- | --- |
| `save_3.10.0.json` | 3.10.0 | `ce0555c` | day 3, 7 operations, 2850 cr |
| `save_3.11.0.json` | 3.11.0 | `690eb1a` | day 3, 7 operations, 2056 cr |
| `save_3.12.0.json` | 3.12.0 | `de8d1da` | day 3, 7 operations, 2406 cr |

**How they were made.** These saves were not played by a person. A
script (`tools/save_fixtures/fixture_gen.gd`) started a new game in a
checkout of each release, played seven operations through that release's
real screens and systems (customer, diagnosis, surgery stages, results,
closing for the night), answered any event with its first open choice,
and saved with `SaveManager.save_game`. They hold no personal data: the
only paths in them are `user://` paths inside the game.

**What uses them.** `tests/save_fixture_tests.gd` loads each one with the
current game and checks that the money, day, operations and level come
back as they were saved, and that the loaded game saves and reloads.

**Regenerating one.**

```sh
git worktree add --detach /tmp/rel-3.12 de8d1da
cp tools/save_fixtures/fixture_gen.gd /tmp/rel-3.12/
cp tools/save_fixtures/fixture_gen.tscn.txt /tmp/rel-3.12/fixture_gen.tscn
godot --headless --path /tmp/rel-3.12 --import
godot --headless --path /tmp/rel-3.12 res://fixture_gen.tscn
# the save is <user data>/fixture_gen/fixture.json
```

A fixture for a new release is added the same way, from its release
commit. The table above is updated with what the script prints.
