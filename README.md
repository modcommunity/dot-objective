This is the **objective** asset for TMC's **Dot** collection. It adds the part of a multiplayer game that says what a round is *about*: control points, a bomb to plant and defuse, a payload to push, a flag to capture, somebody to escort out, and a clock to hold.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## What it does
An objective is what a team is trying to do in a round, other than kill the other team. There are six kinds:

| Kind | What it is |
| --- | --- |
| `CAPTURE` | A control point. Stand on it long enough and your team owns it |
| `BOMB` | Plant a bomb at a site, and the other team defuses it before the fuse runs out |
| `PAYLOAD` | A cart that moves along a path while the attacking team stands next to it |
| `FLAG` | Take the other team's flag back to your own base |
| `RESCUE` | Lead somebody (or several people) to an exit |
| `HOLDOUT` | Hold a point, or just survive, until a clock runs out |

The manager runs every objective on the map each tick: who is standing where, how far a capture or a cart has got, whether a defuse was interrupted. It tells your game when something is started, interrupted, blocked or completed. It never ends a round itself. A game with none of these is a deathmatch, which dot-match handles on its own.

The numbers follow what objective modes have settled on over the years:

- **More players capture faster, but each one adds less.** One player takes 480 ticks, two take 320, three take 263.
- **Both teams on a point pauses it.** A defender only gets credit for blocking if the capture was at least half done.
- **A capture left alone drains away over 90 seconds** and does not snap back, six times faster in overtime.
- **A cart moves at 0.55, 0.77 and 1.0** of full speed with one, two, and three or more pushers. A downhill part of the path rolls it with nobody pushing.

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The easiest way to get this addon and the ones it needs is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons into each one.

To add it to your own project by hand, copy `addons/dot_objective/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into it and enable dot-objective in **Project → Project Settings → Plugins**. dot-core is the only dependency.

## Using it

```gdscript
var objectives := DotObjectiveManager.new()
objectives.presence = DotObjectivePresence.of(
    roster.keys,          # () -> PackedStringArray
    world.position_of,    # (key) -> Vector3
    match_node.team_of,   # (key) -> int, teams start at 1
    world.is_alive        # (key) -> bool
)
objectives.score_fn = func(id, team, by, points, player_points):
    match_node.report_objective(by, id, tick, points)

var res := objectives.setup(map.objectives)   # an Array[DotObjectiveDef]
if not res.ok:
    push_error(res.error.message)
add_child(objectives)

objectives.set_live(true)    # when warmup or freeze time ends. Nothing moves until you do
objectives.advance(tick)     # once per tick
objectives.reset_round()     # between rounds
```

**Nothing makes progress until `set_live(true)`.** This is on purpose, because during warmup everybody is standing on everything. Turn it off again for freeze time and the end of a round.

An objective is a `DotObjectiveDef`, and each kind has a factory:

```gdscript
DotObjectiveDef.capture(&"mid", DotObjectiveArea.cylinder(Vector3.ZERO, 4.0))
DotObjectiveDef.bomb(&"site_a", DotObjectiveArea.box(site_centre, Vector3(4, 2, 4)))
DotObjectiveDef.payload(&"cart", path_points)   # then set capturable_by to the pushing team
DotObjectiveDef.flag(&"red_flag", DotObjectiveArea.sphere(red_base, 2.0), 1)
DotObjectiveDef.rescue(&"hostages", start_points, DotObjectiveArea.sphere(exit, 3.0))
DotObjectiveDef.holdout(&"radio", 10800)
```

Set `capturable_by` to limit which teams may act on an objective (a bomb site only one side plants at), `initial_team` for who owns it at the start, and `requires_owned` to make a point lockable until a team owns the one before it. **A payload must have a pushing team**, from `capturable_by` or `initial_team`, or nobody can push it.

Captures, carts and holdouts run on their own from where players stand. The other kinds need your game to say what a player did, because only it knows about items and buttons:

- **Bomb:** `give_to(key)`, `drop_at(position)` when the carrier dies, `try_pick_up(key, presence)`, `begin_plant(key, presence)` and `begin_defuse(...)`. A plant or defuse is cancelled by itself if the player dies, leaves the site or moves away.
- **Flag:** `touch(key, presence)` to pick it up or return it, `drop(position)`. A carrier reaching their own base scores.
- **Rescue:** `take(id, key, presence)`, `release(id)`, `lose(id)`.

Get the kind's object with `objectives.objective(&"site_a")`. Signals: `objective_started`, `objective_progressed`, `objective_interrupted`, `objective_blocked`, `objective_completed`, `objective_event`, `all_captured` and `round_objective_met`.

A client mirrors the server's state instead of running it:

```gdscript
mirror.authoritative = false
mirror.setup(map.objectives)
mirror.apply_wire(wire_from_the_server)   # the server sends objectives.to_wire()
```

## Settings
The rules live in a `DotObjectiveRules` resource, set on the manager's `rules` (it makes a default one if you do not). Like every Dot config it is layered: inspector defaults, then a JSON file, then the environment, then the command line. Call `load_layered()` on it before `setup()` to apply them:

```gdscript
var rules := DotObjectiveRules.new()
rules.load_layered("user://objectives.json")
objectives.rules = rules
```

```bash
DOT_OBJECTIVE_BLOCK_STYLE=0 godot --headless -- --objective-deteriorate-ticks=3840
```

| Setting | Default | What it does |
| --- | --- | --- |
| `block_style` | 1 | Both teams on a point: 0 resets the capture, 1 pauses it |
| `deteriorate_ticks` | 5760 | How long an abandoned capture takes to drain (90 seconds at 64 ticks) |
| `overtime_decay_multiplier` | 6.0 | How much faster it drains in overtime |
| `block_credit_fraction` | 0.5 | How far along a capture must be for a blocker to get credit |
| `capture_recovery_ticks` | 0 | Wait after a broken capture before it can start again |
| `payload_speed_one` / `_two` / `_three` | 0.55 / 0.77 / 1.0 | Cart speed for one, two, and three or more pushers |
| `payload_recede_speed` | 0.1 | How fast an idle cart rolls back |
| `payload_recede_overtime_ticks` | 320 | Idle time in overtime before it rolls back (5 seconds) |
| `payload_defenders_block` | true | A defender next to the cart stops it |
| `live` | false | Whether anything makes progress. Use `set_live()` |
| `overtime` | false | Overtime is on. Use `set_overtime()` |

Each objective's own timings (capture time, plant, fuse and defuse times, cart speed, flag return time, holdout length) are fields on its `DotObjectiveDef`.

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/objective_selftest.tscn
```

## License
MIT. See [LICENSE](LICENSE).
