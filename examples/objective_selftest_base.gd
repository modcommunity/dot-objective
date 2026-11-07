extends Node

## Exercises dot-objective with no other addon, no world and no transport: every check
## drives the objectives out of a dictionary of positions, the seam a real game fills with
## its roster.

const SECTIONS := 25
const CHECKS := 254

## 64 a second, which is what every "ticks" number below is quoted at.
const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0


## The game, in the smallest form that still answers every question a presence asks.
class World extends RefCounted:
	var positions: Dictionary = {}
	var teams: Dictionary = {}
	var alive: Dictionary = {}
	var values: Dictionary = {}
	var can_capture: Dictionary = {}

	func add(key: String, team: int, at: Vector3 = Vector3.ZERO) -> void:
		positions[key] = at
		teams[key] = team
		alive[key] = true

	func move(key: String, to: Vector3) -> void:
		positions[key] = to

	func kill(key: String) -> void:
		alive[key] = false

	func keys() -> PackedStringArray:
		var out := PackedStringArray()
		var ids: Array = positions.keys()
		ids.sort()
		for id: Variant in ids:
			out.append(str(id))
		return out

	func presence() -> DotObjectivePresence:
		var p := DotObjectivePresence.of(
			keys,
			func(key: String) -> Vector3: return positions.get(key, Vector3.ZERO),
			func(key: String) -> int: return int(teams.get(key, 0)),
			func(key: String) -> bool: return bool(alive.get(key, false))
		)
		p.capture_value_fn = func(key: String) -> int:
			return int(values.get(key, 1))
		p.may_capture_fn = func(key: String) -> bool:
			return bool(can_capture.get(key, true))
		return p


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
