# Design

Why dot-objective is shaped the way it is, and why the obvious alternative is wrong in each case.

## Why this exists

[dot-match](../../dot-match) has the round loop: warmup, countdown, rounds, scoring, teams, spawning, respawning. It has `report_objective(key, counter, tick, points)` (a *number* a game increments) and nothing that decides when to increment it. So every game that wanted a mode wrote its own capture clock, its own plant timer, its own flag rules, and every one of them got the same four things wrong:

- **The capture rate.** One player, two players, five players. Every hand-written version is linear, which makes a point a headcount and a mode a race to bring more people.
- **Blocking.** Two teams on one point either has to pause the clock or break it, and the version that does neither is the one where the losing team cannot defend.
- **Decay.** A capture that snaps back to zero the instant the last attacker steps off is a different game from one that decays over ninety seconds, and only one of them makes the second push worth making.
- **Interruption.** A defuse that finishes because nobody told it the defuser had died.

Those are solved problems with twenty years of play behind them. This addon is the established reference implementations of the class-based objective shooters and the round-based bomb shooters, read and rewritten: the area-capture trigger for the point, the train watcher for the cart, the game rules for the bomb.

## An objective is a rule about a place, and nothing else

It has no body, no collision shape, no node, and it never moves anything. A `DotObjectiveArea` is a centre, a size and a `contains()`; a payload has a *distance* along a path and `position()` turns that into a point for the game to draw a cart at.

That is what lets the whole addon run in a headless suite with a dictionary of positions in it, in a 2D game on the XZ plane, and in a client that is mirroring rather than simulating: three deployment shapes, no second code path, and by this family's own repeated lesson three shapes is where the bugs would otherwise be.

## What it is not

- **Not a round loop.** It emits `round_objective_met`; dot-match ends rounds. This addon does not import dot-match and could not, because a control point is the same rule in a game with no match loop at all.
- **Not a scoreboard.** `score_fn` is one callable; game-arena's calls `DotMatch.report_objective`.
- **Not an item system.** The bomb is not an item; a game hands it to somebody with `give_to` and drops it with `drop_at`. Whether that is a loadout slot, a prop or a boolean is the game's business, and every one of those still needs the plant timer.
- **Not a navigation system.** A rescue follower *trails* its rescuer. An escort that pathfinds is one that cannot run headless, cannot run in 2D, and has quietly become a second and worse [dot-npc](../../dot-npc).

## `capture_ticks` means what it says

The reference implementation's total capture time is `capTime * 2 * requiredPlayers`. A point whose map file says ten seconds takes **twenty** with one player, and twenty-seven if two are required. That is a trap in a field a mapper reads: the number in the document is not the number on the clock.

Here the total is `capture_ticks * H(capture_required)`, where H is the harmonic number, so a point quoted at six seconds for one capper takes six seconds with one capper, and the *curve* is unchanged, because the curve is the part worth keeping. The suite pins both halves: the quoted count takes the quoted time, and two cappers are worth exactly 1.5 players rather than 2.

## Diminishing returns, not linear

The nth capper adds `1/n`. Two players are worth 1.5, three are worth 1.83, five are worth 2.28. This is the single most important number in the addon: linear makes a point a headcount, and this makes the second player worth bringing and the fifth worth sending somewhere else.

## Locking is per team

`DotObjectiveDef.requires_owned` is keyed by team id, and `DotObjective.team_gate` answers per team. A five-point map is a tug of war rather than a race precisely because the same point, at the same instant, is available to one side and forbidden to the other. A single `locked` boolean cannot say that; every mode built on one lets a losing team run past everything and win at the far end.

A prerequisite naming an objective that is not in the set **refuses**, loudly. Allowing it is the failure mode this gate exists to prevent.

### The gate reaches its set through a weak reference

`DotObjectiveSet._wire` hands every objective a `team_gate` lambda that asks the set `owns_all`. A lambda that calls a method on the set captures the set, the objective holds the lambda and the set holds the objective: two `RefCounted`s pointing at each other, which GDScript never frees. The lambda holds a `weakref` to the set instead, and an objective that outlives its set (one nobody is playing) has an open gate.

## Ticks, and no wall clock anywhere

dot-timer's lesson. A float accumulator drifts, and a value in seconds on a server at 64 and a client at 128 is two different numbers for one thing. `advance(tick)` is the only thing that moves anything here.

## A mirror does not simulate

`authoritative = false` makes `advance()` a no-op and `apply_wire()` the only way state changes. Two machines running a capture clock disagree by whatever their tick rates differ by, and the client's HUD then shows a point captured that the server has not captured: game-g2gfast's 128-against-60 bug in a different subsystem.

The wire form is the whole state as one dictionary rather than a delta. Twenty objectives is a few hundred bytes a few times a second; a delta scheme here would be a second replication system beside dot-net's for no measurable gain.

## Interruption is re-tested every tick, not trusted

A bomb being defused re-checks every tick that the defuser is alive, on the right side and still within the radius. A game that only calls `cancel_defuse()` on death has one path to get wrong; this has none. Same for a plant, a flag carrier and a rescue leader.

## Capture details

- **`may_block` falls back independently of `may_capture`.** The invulnerable player may not *capture* and must still *stop* a capture: that is the entire reason there are two questions rather than one ([history](history.md#may_block-defaulted-to-may_capture)).
- **A contested capture does not start.** Starting one whenever a team is in the zone and breaking it on the next tick if another team is as well gives two signals a tick for ever and makes `block_style 0` unobservable ([history](history.md#a-contested-capture-started-and-broke-every-tick)).
- **`capture_recovery_ticks`** is the one capture rule the reference does not have: a capture may not start again for this many ticks after being broken. `_break` takes the period from its caller, because the three callers do not mean the same thing: a break because the round went non-live is freeze time or a round end, not a failed push, and starting a recovery there would delay the first capture of the next round by the whole period.

## Deliberately not here

- **No round layouts as a document.** `DotObjectiveSet.set_round()` takes ids and owners; a map that wants five different round configurations declares them in its own file. A schema for that is a schema for one game's idea of a round.
- **No respawn-time adjustment on capture.** The class-based objective shooters shorten the defenders' wave when a point falls. That is dot-match's respawn queue and belongs there.
- **No overtime decision.** `rules.overtime` is a switch a game sets; deciding when a round is in overtime needs the round clock, which is dot-match's.
- **No hostage pathing, no cart model, no capture-point prop.** Art and navigation.
- **No area entity in the editor.** dot-timer ships `DotTimerZonePainter` because a speedrun zone is drawn by a mapper on a surface; an objective area is three numbers in a map's own definition file, and a painter for it would be a fourth way to write them.
