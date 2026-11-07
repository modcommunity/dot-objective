@tool
class_name DotObjectiveCtfRules
extends DotConfig

## Every number capture-the-flag has, as one layered config (defaults < JSON < environment `DOT_CTF_*` < command line `--ctf-*`). A game maps its cvars onto these fields.

## Captures that win the match; 0 is no limit.
@export_range(0, 1000, 1) var capture_limit: int = 3

## Seconds the match lasts; 0 is no limit. Whoever has more captures wins, equal is a draw.
@export_range(0, 86400, 1) var time_limit_sec: int = 0

## Seconds a dropped flag waits before it goes home by itself.
@export_range(0, 3600, 1) var return_sec: int = 30

## Seconds after a drop during which the dropper cannot take the flag straight back.
@export_range(0, 600, 1) var drop_sec: int = 2

## Carrier speed as a fraction of normal.
@export_range(0.1, 2.0, 0.01) var carrier_speed: float = 0.9

## A flag's own team returns it at once by touching it while it lies dropped; off leaves only the timer.
@export var friendly_return: bool = true

## A carrier scores only while their own flag is on its stand.
@export var require_home: bool = true

## How many teams play; each has a flag and may take every other flag.
@export_range(2, 8, 1) var team_count: int = 2

## Metres within which a player takes or returns a flag.
@export_range(0.1, 100.0, 0.1, "or_greater") var touch_radius: float = 1.5

## Radius of a flag stand, which is also where its team scores.
@export_range(0.5, 100.0, 0.1, "or_greater") var stand_radius: float = 3.0


func env_prefix() -> String:
	return "DOT_CTF_"


func cli_prefix() -> String:
	return "--ctf-"


func validate() -> DotResult:
	if touch_radius > stand_radius * 2.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"touch_radius %.1f is wider than two stands; the flag would be taken from across the map." % touch_radius
		)
	return DotResult.success(null)
