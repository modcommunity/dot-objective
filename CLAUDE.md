# dot-objective

What a round is **about**. Control points, a bomb, a payload, a flag, an escort and a
holdout clock — as one document a server validates without loading anything, counted in
ticks, and driven by one call.

**The distributable is `addons/dot_objective/`.** It requires [dot-core](../dot-core), a
separate repository, and nothing else.

```bash
# Local development setup — the symlink is gitignored on purpose.
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

## Why this exists

[dot-match](../dot-match) has the round loop: warmup, countdown, rounds, scoring, teams,
spawning, respawning. It has `report_objective(key, counter, tick, points)` — a *number*
a game increments — and nothing that decides when to increment it. So every game that
wanted a mode wrote its own capture clock, its own plant timer, its own flag rules, and
every one of them got the same four things wrong:

- **The capture rate.** One player, two players, five players. Every hand-written version
  is linear, which makes a point a headcount and a mode a race to bring more people.
- **Blocking.** Two teams on one point either has to pause the clock or break it, and
  the version that does neither is the one where the losing team cannot defend.
- **Decay.** A capture that snaps back to zero the instant the last attacker steps off is
  a different game from one that decays over ninety seconds, and only one of them makes
  the second push worth making.
- **Interruption.** A defuse that finishes because nobody told it the defuser had died.

Those are solved problems with twenty years of play behind them, and the solutions are in
`external-study/game-dev/engines/source-engine`. This addon is that code read and
rewritten: `trigger_area_capture.cpp` for the point, `team_train_watcher.cpp` for the
cart, `cs_gamerules.cpp` for the bomb.

## The one idea: an objective is a rule about a place, and nothing else

It has no body, no collision shape, no node, and it never moves anything. A
`DotObjectiveArea` is a centre, a size and a `contains()`; a payload has a *distance*
along a path and `position()` turns that into a point for the game to draw a cart at.

That is what lets the whole addon run in a headless suite with a dictionary of positions
in it, in a 2D game on the XZ plane, and in a client that is mirroring rather than
simulating — three deployment shapes, no second code path, and by this family's own
repeated lesson three shapes is where the bugs would otherwise be.

## What it is not

- **Not a round loop.** It emits `round_objective_met`; dot-match ends rounds. This addon
  does not import dot-match and could not, because a control point is the same rule in a
  game with no match loop at all.
- **Not a scoreboard.** `score_fn` is one callable, and in every game here it points at
  `DotMatch.report_objective`.
- **Not an item system.** The bomb is not a `DotItem`; a game hands it to somebody with
  `give_to` and drops it with `drop_at`. Whether that is a loadout slot, a prop or a
  boolean is the game's business, and every one of those still needs the plant timer.
- **Not a navigation system.** A rescue follower *trails* its rescuer. An escort that
  pathfinds is one that cannot run headless, cannot run in 2D, and has quietly become a
  second and worse [dot-npc](../dot-npc).

## The pieces

| | |
| --- | --- |
| `DotObjectiveArea` | Where. Sphere, cylinder, box, everywhere. 2D is the XZ plane. |
| `DotObjectiveDef` | The document. Six kinds, validated before anything is built. |
| `DotObjectiveRules` | Every cross-objective policy, layered like every `DotConfig`. |
| `DotObjectivePresence` | The whole coupling to a game: six callables. |
| `DotObjective` | The base. Phase, owner, the wire form, "complete exactly once". |
| `DotObjectiveCapture` | A control point, with Source's curve. |
| `DotObjectiveBomb` | Plant, fuse, defuse, kit, drop, pick up. |
| `DotObjectivePayload` | A cart, three speeds, hills, checkpoints, receding. |
| `DotObjectiveFlag` | Capture the flag, and the three settings that make it three games. |
| `DotObjectiveRescue` | Hostages, survivors, and the case where it becomes impossible. |
| `DotObjectiveHoldout` | King of the hill's clock, and a finale's. |
| `DotObjectiveSet` | The ordered set, the round layout, and the per-team gate. |
| `DotObjectiveManager` | The one node a game holds. |

## Decisions

### 1. `capture_ticks` means what it says, and Source's does not

Source's total capture time is `capTime * 2 * requiredPlayers`. A point whose map file
says ten seconds takes **twenty** with one player, and twenty-seven if two are required.
That is a trap in a field a mapper reads: the number in the document is not the number on
the clock.

Here the total is `capture_ticks * H(capture_required)`, where H is the harmonic number,
so a point quoted at six seconds for one capper takes six seconds with one capper — and
the *curve* is unchanged, because the curve is the part worth keeping. The suite pins both
halves: the quoted count takes the quoted time, and two cappers are worth exactly 1.5
players rather than 2.

### 2. Diminishing returns, not a formula, and not linear

The nth capper adds `1/n`. Two players are worth 1.5, three are worth 1.83, five are worth
2.28. This is the single most important number in the addon: linear makes a point a
headcount, and this makes the second player worth bringing and the fifth worth sending
somewhere else.

### 3. Locking is per team

`DotObjectiveDef.requires_owned` is keyed by team id, and `DotObjective.team_gate` answers
per team. A five-point map is a tug of war rather than a race precisely because the same
point, at the same instant, is available to one side and forbidden to the other. A single
`locked` boolean cannot say that; every mode built on one lets a losing team run past
everything and win at the far end.

A prerequisite naming an objective that is not in the set **refuses**, loudly. Allowing it
is the failure mode this gate exists to prevent.

### 4. Ticks, and no wall clock anywhere

dot-timer's lesson. A float accumulator drifts, and a value in seconds on a server at 64
and a client at 128 is two different numbers for one thing. `advance(tick)` is the only
thing that moves anything here.

### 5. A mirror does not simulate

`authoritative = false` makes `advance()` a no-op and `apply_wire()` the only way state
changes. Two machines running a capture clock disagree by whatever their tick rates
differ by, and the client's HUD then shows a point captured that the server has not
captured — which is g2gfast's 128-against-60 bug in a different subsystem.

The wire form is the whole state as one dictionary rather than a delta. Twenty objectives
is a few hundred bytes a few times a second; a delta scheme here would be a second
replication system beside dot-net's for no measurable gain.

### 6. Interruption is re-tested every tick, not trusted

A bomb being defused re-checks every tick that the defuser is alive, on the right side and
still within the radius. A game that only calls `cancel_defuse()` on death has one path to
get wrong; this has none. Same for a plant, a flag carrier and a rescue leader.

## Two bugs found by running it, both parse-clean

- **`may_block` defaulted to `may_capture`, which excludes the one player the pair exists
  for.** Team Fortress 2's invulnerable player may not *capture* and must still *stop* a
  capture — that is the entire reason there are two questions rather than one. Chaining
  the fallback to `may_capture` made the invulnerable player the one player the
  distinction did not apply to. Nothing errored: "the point kept capturing" is a
  legitimate thing for a point to do.

- **A capture that starts contested starts and breaks on every tick, for ever.** Source
  does this too — `CaptureThink` starts a capture whenever a team is in the zone and
  breaks it on the next think if another team is as well — and at 64 Hz that is 128
  signals a second, a kill feed full of nothing, and `block_style 0` being
  *unobservable*, because the capture is always either just-started or just-broken. This
  refuses to start a contested capture at all. It is the rarer shape in this family's
  notes: not a value nobody consumes, but a value produced far too often.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/objective_selftest.tscn   # 193 checks
```

## Things deliberately not here

- **No round layouts as a document.** `DotObjectiveSet.set_round()` takes ids and owners;
  a map that wants five different round configurations declares them in its own file.
  A schema for that is a schema for one game's idea of a round.
- **No respawn-time adjustment on capture.** Team Fortress 2 shortens the defenders' wave
  when a point falls. That is dot-match's respawn queue and belongs there.
- **No overtime decision.** `rules.overtime` is a switch a game sets; deciding when a
  round is in overtime needs the round clock, which is dot-match's.
- **No hostage pathing, no cart model, no capture-point prop.** Art and navigation.
- **No area entity in the editor.** dot-timer ships `DotTimerZonePainter` because a
  speedrun zone is drawn by a mapper on a surface; an objective area is three numbers in a
  map's own definition file, and a painter for it would be a fourth way to write them.
