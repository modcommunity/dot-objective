@tool
class_name DotObjectiveRules
extends DotConfig

## Every policy that is about objectives in general rather than about one of them.
##
## Layered like every [DotConfig] here — exported defaults, then a JSON file, then the
## environment, then the command line — so a server can run a slower capture without an
## export, and a test can set one field and leave the other twenty alone.
##
## [b]The numbers are Source's, and each one is a decision somebody else already made
## badly once.[/b] Where a default came from a shipped game it says so, because the
## next reader's instinct will be to round it and the roundest values here are the
## wrong ones.

@export_group("Capture")

## What two teams in one zone does: 0 breaks the capture, 1 pauses it.
##
## Pausing is Team Fortress 2's [code]mp_blockstyle 1[/code] and is what a modern
## player expects — a defender who steps on the point stops the clock and does not
## undo the last twenty seconds of it. Breaking is the older behaviour and is brutal
## on the attackers, which some modes want.
@export_enum("break", "pause") var block_style: int = 1

## Ticks an unattended partial capture takes to run all the way back down.
##
## Source's [code]mp_capdeteriorate_time[/code], 90 seconds, and it is why a point you
## nearly took is still nearly taken when you come back with a friend. Independent of
## the capture time on purpose: a long capture that decays in its own duration would
## be untakeable at any player count.
@export_range(1, 1000000, 1) var deteriorate_ticks: int = 5760

## How much faster progress decays in overtime.
##
## Six, from Source. Overtime exists to end the game, and a partial capture that takes
## its full time to decay is a way to keep it going.
@export_range(1.0, 100.0, 0.1) var overtime_decay_multiplier: float = 6.0

## A blocker only gets credit when the capture was at least this far along.
##
## Half, from Source. Standing on your own point as the round starts is not a block,
## and rewarding it teaches players to stand on their own point.
@export_range(0.0, 1.0, 0.01) var block_credit_fraction: float = 0.5

## A capture may not start again for this many ticks after being broken.
##
## Zero, which is Source. Present because a mode that wants to punish a failed push
## has nowhere else to say so.
@export_range(0, 100000, 1) var capture_recovery_ticks: int = 0

@export_group("Payload")

## Cart speed as a fraction of full, for one, two, and three-or-more pushers.
##
## 0.55, 0.77, 1.0 — Team Fortress 2's exactly. Not a curve: they are hand-picked so
## that a second pusher is worth having and a fourth is worth sending somewhere else,
## which no formula this simple produces.
@export_range(0.0, 1.0, 0.01) var payload_speed_one: float = 0.55
@export_range(0.0, 1.0, 0.01) var payload_speed_two: float = 0.77
@export_range(0.0, 1.0, 0.01) var payload_speed_three: float = 1.0

## How fast the cart rolls back when it has been idle too long, as a fraction.
@export_range(0.0, 1.0, 0.01) var payload_recede_speed: float = 0.1

## Ticks of nobody pushing before it recedes, in overtime. Five seconds in TF2.
@export_range(0, 1000000, 1) var payload_recede_overtime_ticks: int = 320

## A defender standing on the cart stops it.
@export var payload_defenders_block: bool = true

@export_group("Round")

## Objectives make no progress at all until this is set.
##
## The switch a warmup, a freeze time and a round-end period all need, and Source's
## [code]PointsMayBeCaptured[/code]. Off by default, because a manager that started
## capturing the moment it was built would capture during warmup — and warmup is the
## one period in which everybody is standing on everything.
@export var live: bool = false

## Overtime, which changes the two decay numbers above.
@export var overtime: bool = false

## Completing an objective that says it wins the round emits rather than deciding.
##
## There is no other option and the setting is here to say so: this addon never ends a
## round. [DotMatch] does, and it does not import this one either.
@export var announce_only: bool = true


func env_prefix() -> String:
	return "DOT_OBJECTIVE_"


func cli_prefix() -> String:
	return "objective-"


func validate() -> DotResult:
	if payload_speed_one > payload_speed_two or payload_speed_two > payload_speed_three:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Payload speeds must not decrease with more pushers (%.2f, %.2f, "
				+ "%.2f): a second pusher that slows the cart is a mode nobody asked "
				+ "for."
			) % [payload_speed_one, payload_speed_two, payload_speed_three]
		)
	return DotResult.success(null)


## The tick cost of one tick of decay, given the total capture time.
func decay_per_tick(total_ticks: float) -> float:
	var scale := float(maxi(deteriorate_ticks, 1))
	var per := total_ticks / scale
	if overtime:
		per *= overtime_decay_multiplier
	return per


## The cart's speed fraction for a number of pushers.
func payload_fraction(pushers: int) -> float:
	if pushers <= 0:
		return 0.0
	if pushers == 1:
		return payload_speed_one
	if pushers == 2:
		return payload_speed_two
	return payload_speed_three
