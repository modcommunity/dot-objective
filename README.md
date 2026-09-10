This is the **objective** asset for TMC's **Dot** collection. It adds the part of a
multiplayer game that says what a round is *about*: control points, a bomb to plant and
defuse, a payload to push, a flag to capture, somebody to escort out, and a clock to hold.

This collection of assets provides modular building blocks for creating games and
applications within the TMC ecosystem, ensuring consistency and interoperability across
all `dot-*` assets. This includes core functionality, networking, authentication, cloud
integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute
them under the terms of the MIT license. The only thing not open source is the back-end
web infrastructure. So if you opt into using your own authentication backend instead of
integrating with TMC, you will need to build and integrate your own back-end
infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will
continue to be maintained and extended using it. This is because I (`gamemann`) cannot
build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and
those suites pass, but very little of this has been in front of real players yet. Expect
rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're
interested in helping out, please let me know!

## Six kinds, and they are not arbitrary

They are what Counter-Strike, Team Fortress 2 and Left 4 Dead 2 between them ship, reduced
to the smallest set that still tells the three of them apart:

| | |
| --- | --- |
| `CAPTURE` | A control point. `cp_`, `koth_`, `dod_`, `dom_`. |
| `BOMB` | Plant it, defuse it. `de_`. |
| `PAYLOAD` | A cart pushed along a path. `pl_`, `plr_`. |
| `FLAG` | Carry theirs to yours. `ctf_`. |
| `RESCUE` | Escort somebody out. `cs_`, and every co-operative finale. |
| `HOLDOUT` | Own it, or survive, for N. `koth_`'s clock, and a finale's radio. |

A game with none of these is a deathmatch, which `dot-match` alone already does.

## Why not write it yourself

Because the numbers are the whole thing, and they are twenty years old:

- **More cappers capture faster, with diminishing returns.** The nth player adds `1/n`.
  Linear makes a point a headcount.
- **Two teams at once pauses the capture**, and the defender gets credit only if the
  attackers had got at least half way — because rewarding a player for standing on their
  own point teaches players to stand on their own point.
- **An abandoned capture decays** over ninety seconds rather than snapping back, six times
  faster in overtime.
- **A cart moves at 0.55, 0.77 and 1.0** of full speed for one, two and three-or-more
  pushers. Not a curve: hand-picked so a second pusher is worth having and a fourth is
  worth sending somewhere else.
- **A hill does the work.** A downhill segment rolls the cart with nobody on it, so a
  defender who stops pushing at the top of a hill has still lost the hill.

## Installing

Copy `addons/dot_objective/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s
`addons/dot_core/` into your project and enable dot-objective in
**Project → Project Settings → Plugins**.

## Using it

```gdscript
var objectives := DotObjectiveManager.new()
objectives.presence = DotObjectivePresence.of(
    roster.keys, world.position_of, match_node.team_of, world.is_alive
)
objectives.score_fn = func(id, team, by, points, player_points):
    match_node.report_objective(by, id, tick, points)

var res := objectives.setup(map.objectives)
if not res.ok:
    push_error(res.error.message)
add_child(objectives)

# ... once per physics tick, from the game's own tick loop:
objectives.advance(tick)
```

A client mirrors instead:

```gdscript
mirror.authoritative = false
mirror.setup(map.objectives)
mirror.apply_wire(wire_from_the_server)
```

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else — not dot-match, not
dot-combat, not dot-net. The coupling to a game is six callables on
`DotObjectivePresence`.

## License

MIT.
