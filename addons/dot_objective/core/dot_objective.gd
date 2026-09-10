class_name DotObjective
extends RefCounted

## One objective, running. The definition is the document; this is what it is doing.
##
## [b]Counted in ticks and driven by one call.[/b] [method advance] is handed the
## current tick and a [DotObjectivePresence], exactly like [method DotMatch.advance] —
## no [code]_process[/code], no timers, no [SceneTree]. A [RefCounted] rather than a
## [Node] for the reason the family gives everywhere: a headless suite builds a
## hundred of these, a client mirrors them, and neither wants a scene tree.
##
## Subclasses override [method _advance] and nothing else structural. The phase, the
## owner, the announcements and the wire form are here so that six kinds of objective
## cannot disagree about what "complete" means.

## Emitted the moment this objective is finished with. [param team] may be 0.
signal completed(team: int, by: String)

## A team started making progress on it.
signal started(team: int, by: String)

## Progress stopped, either by being contested or by being abandoned.
signal interrupted(team: int, reason: StringName)

## Somebody stopped somebody else's progress and deserves credit for it.
signal blocked(by: String, team: int)

## The fraction changed enough to redraw. Rate-limited by the caller, not here.
signal progressed(fraction: float, team: int)

## Anything a kind wants to say that the five above do not cover. [param what] is a
## StringName the game switches on: [code]&"planted"[/code], [code]&"picked_up"[/code].
signal event(what: StringName, data: Dictionary)

enum Phase {
	LOCKED,     ## Not in play yet — another objective has to happen first.
	IDLE,       ## In play, nothing happening.
	ACTIVE,     ## Somebody is making progress.
	CONTESTED,  ## Two teams at once. Progress paused or breaking.
	COMPLETE,   ## Done. Nothing more happens to it this round.
	FAILED,     ## Done, badly. A bomb that went off on the defenders.
}

var def: DotObjectiveDef = null

var phase: Phase = Phase.IDLE

## Who holds it. 0 is neutral. What this means differs per kind and is documented on
## each: a captured point's owner, a flag's home team, a bomb's planting side.
var owner_team: int = 0

## The tick [method advance] was last given. Nothing here reads a wall clock.
var tick: int = 0

## Set by [DotObjectiveSet] when this objective is not in the round being played. A
## locked objective still advances — it has to, or a payload would keep the idle
## counter it should have stopped — but it refuses to start anything.
var locked: bool = false

## Whether one team may act on this right now. [code](team: int) -> bool[/code]
##
## [b]Locking is per team, and that is not a detail.[/b] Team Fortress 2's five-point
## map is a tug of war precisely because red may capture the middle only while it still
## owns its own second point — the same point, at the same moment, is available to one
## side and not the other. A single [member locked] boolean cannot say that, and a
## mode built on one is a race rather than a tug of war.
##
## [DotObjectiveSet] fills this in from [member DotObjectiveDef.requires_owned]. Unset
## means every team may act.
var team_gate: Callable = Callable()


func _init(p_def: DotObjectiveDef = null) -> void:
	def = p_def
	if def != null:
		owner_team = def.initial_team


## The id, for a caller holding the objective and not the definition.
func id() -> StringName:
	return def.id if def != null else &""


## Whether a team is allowed to act on this at all, gate and definition together.
func team_allowed(team: int) -> bool:
	if team <= 0:
		return false
	if def != null and not def.may_be_taken_by(team):
		return false
	if team_gate.is_valid() and not bool(team_gate.call(team)):
		return false
	return true


func kind() -> DotObjectiveDef.Kind:
	return def.kind if def != null else DotObjectiveDef.Kind.CAPTURE


## 0..1, for a HUD. What it measures differs per kind and every kind documents it.
func progress() -> float:
	return 0.0


## Which team the current progress belongs to, or 0.
func progressing_team() -> int:
	return 0


func is_finished() -> bool:
	return phase == Phase.COMPLETE or phase == Phase.FAILED


## One tick. Never call [method _advance] directly: this is where the finished check
## and the tick stamp live, and a kind that skipped them would keep running after it
## had been won.
func advance(p_tick: int, presence: DotObjectivePresence, rules: DotObjectiveRules) -> void:
	tick = p_tick
	if is_finished():
		return
	if not rules.live:
		_on_not_live(presence, rules)
		return
	_advance(presence, rules)


## Where a kind does its work.
func _advance(_presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	pass


## What happens while the round is not live — warmup, freeze time, round end.
##
## The default is to give up any partial progress, which is right for every kind here:
## a capture half-made during a freeze is one nobody was allowed to make. A kind that
## wants to keep something across the boundary says so.
func _on_not_live(_presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	pass


## Put it back to the start of a round.
func reset() -> void:
	phase = Phase.IDLE
	owner_team = def.initial_team if def != null else 0
	locked = false
	_reset()


func _reset() -> void:
	pass


## Mark it done and say so exactly once.
##
## Guarded because more than one path reaches it in most kinds — a bomb both explodes
## and runs out of fuse — and an objective that emits [signal completed] twice scores
## twice.
func _complete(team: int, by: String = "", failed: bool = false) -> void:
	if is_finished():
		return
	phase = Phase.FAILED if failed else Phase.COMPLETE
	if team > 0:
		owner_team = team
	completed.emit(team, by)


func to_wire() -> Dictionary:
	var out := {
		"id": String(id()),
		"k": int(kind()),
		"p": int(phase),
		"o": owner_team,
		"f": progress(),
		"t": progressing_team(),
		"l": locked,
	}
	_to_wire(out)
	return out


func _to_wire(_out: Dictionary) -> void:
	pass


## Apply a wire form from the authority. A mirror never simulates.
func apply_wire(w: Dictionary) -> void:
	phase = int(w.get("p", int(phase))) as Phase
	owner_team = int(w.get("o", owner_team))
	locked = bool(w.get("l", locked))
	_apply_wire(w)


func _apply_wire(_w: Dictionary) -> void:
	pass


func describe() -> Dictionary:
	return {
		"id": String(id()),
		"kind": DotObjectiveDef.Kind.keys()[kind()],
		"phase": Phase.keys()[phase],
		"owner": owner_team,
		"progress": progress(),
		"locked": locked,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(
		"%s [%s] %s owner=%d %.0f%%" % [
			id(),
			DotObjectiveDef.Kind.keys()[kind()],
			Phase.keys()[phase],
			owner_team,
			progress() * 100.0,
		]
	)
	return out


func _to_string() -> String:
	return "%s(%s %s)" % [
		get_script().get_global_name() if get_script() != null else "DotObjective",
		id(),
		Phase.keys()[phase],
	]
