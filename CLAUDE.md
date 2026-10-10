# dot-objective

What a round is **about**: control points, a bomb, a payload, a flag, a rescue and a holdout clock, as one document a server validates without loading anything, counted in ticks, and driven by one call.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to objectives.

**The distributable is `addons/dot_objective/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored). It does not import dot-match; game-arena is the game on it.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: why it exists, a rule about a place, what it is not, the capture curve, per-team locks, ticks, mirroring, interruption, what is not here |
| [docs/history.md](docs/history.md) | the three parse-clean bugs and the gate's reference cycle |

## Layout

| Path | What |
| --- | --- |
| `core/dot_objective_area.gd` | `DotObjectiveArea`: where. Sphere, cylinder, box, everywhere; 2D is the XZ plane |
| `core/dot_objective_def.gd` | `DotObjectiveDef`: the document. Six kinds, validated before anything is built |
| `core/dot_objective_rules.gd` | `DotObjectiveRules`: every cross-objective policy, a `DotConfig` |
| `core/dot_objective_presence.gd` | `DotObjectivePresence`: the whole coupling to a game, as callables (`participants_fn`, `position_fn`, `team_fn`, `alive_fn`, `capture_value_fn`, `may_capture_fn`, `may_block_fn`) |
| `core/dot_objective.gd` | `DotObjective`: the base. Phase, owner, the wire form, "complete exactly once" |
| `kinds/` | `DotObjectiveCapture`, `...Bomb` (plant, fuse, defuse, kit, drop, pick up), `...Payload` (three speeds, hills, checkpoints, receding), `...Flag`, `...Rescue`, `...Holdout` |
| `runtime/dot_objective_set.gd` | `DotObjectiveSet`: the ordered set, the round layout, the per-team gate |
| `runtime/dot_objective_manager.gd` | `DotObjectiveManager`: the one node a game holds; `score_fn`, `round_objective_met` |
| `examples/objective_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/dot_objective/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/objective_selftest.tscn`.

## Rules that bite

- An objective has no body, node or collision and never moves anything; keep one code path for headless, 2D and mirroring. [design](docs/design.md#an-objective-is-a-rule-about-a-place-and-nothing-else)
- No round loop, scoreboard, item system or navigation here; scoring goes out through `score_fn`. [design](docs/design.md#what-it-is-not)
- `capture_ticks` is the time for one capper; the total is `capture_ticks * H(capture_required)`, and the nth capper adds `1/n`. [design](docs/design.md#capture_ticks-means-what-it-says)
- Locks are per team (`requires_owned`, `team_gate`); a prerequisite not in the set refuses. [design](docs/design.md#locking-is-per-team)
- `team_gate` holds a `weakref` to its set; never capture the set in the lambda. [design](docs/design.md#the-gate-reaches-its-set-through-a-weak-reference)
- `advance(tick)` is the only thing that moves state; no wall clock. [design](docs/design.md#ticks-and-no-wall-clock-anywhere)
- With `authoritative = false`, `advance()` does nothing and only `apply_wire()` changes state; the wire form is the whole state. [design](docs/design.md#a-mirror-does-not-simulate)
- Interruption (plant, defuse, carrier, rescue leader) is re-tested every tick, not left to the game's cancel call. [design](docs/design.md#interruption-is-re-tested-every-tick-not-trusted)
- `may_block` never falls back to `may_capture`; a contested capture does not start; `_break` takes its recovery period from the caller. [design](docs/design.md#capture-details)

Deliberately not here: round layouts as a document, respawn-time changes, the overtime decision, art and pathing, an editor painter. [design](docs/design.md#deliberately-not-here)
