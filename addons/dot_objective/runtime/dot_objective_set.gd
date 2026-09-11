class_name DotObjectiveSet
extends RefCounted

## The objectives of one map, in order, and the rules about which of them are in play.
##
## This is the class-based objective shooters' control-point master and its per-round
## point set, which are two entities doing three jobs: hold the ordered list, decide
## which subset is being played this round, and answer "may this team touch that point
## yet".
##
## [b]The third job is the one worth having.[/b] A five-point map is a tug of war and
## not a race because red may capture the middle only while red still owns its own
## second point — so the same objective, at the same instant, is available to one side
## and forbidden to the other. That cannot be expressed as a flag on the objective, and
## every implementation that tries ends up with a mode where a losing team can run past
## everything and win at the far end.

var objectives: Array[DotObjective] = []

var _by_id: Dictionary = {}

## Ids being played this round. Empty means all of them.
var _round: Array[StringName] = []


static func build(defs: Array[DotObjectiveDef]) -> DotResult:
	var built := DotObjectiveSet.new()
	var res := built.rebuild(defs)
	if not res.ok:
		return res
	return DotResult.success(built)


func rebuild(defs: Array[DotObjectiveDef]) -> DotResult:
	objectives.clear()
	_by_id.clear()
	_round.clear()

	for def in defs:
		if def == null:
			return DotResult.fail(
				DotError.CODE_INVALID, "A null definition is in the objective list."
			)
		var res := def.validate()
		if not res.ok:
			return res
		if _by_id.has(def.id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				(
					"Two objectives are called '%s'. Ids are how a game, a HUD and a "
					+ "wire form all refer to one thing, so a duplicate silently makes "
					+ "two of them into one."
				) % def.id
			)

		var made := _make(def)
		if made == null:
			return DotResult.fail(
				DotError.CODE_INTERNAL,
				"No implementation for objective kind %s." % def.kind
			)
		objectives.append(made)
		_by_id[def.id] = made

	_wire()
	return DotResult.success(null)


func _make(def: DotObjectiveDef) -> DotObjective:
	match def.kind:
		DotObjectiveDef.Kind.CAPTURE:
			return DotObjectiveCapture.new(def)
		DotObjectiveDef.Kind.BOMB:
			return DotObjectiveBomb.new(def)
		DotObjectiveDef.Kind.PAYLOAD:
			return DotObjectivePayload.new(def)
		DotObjectiveDef.Kind.FLAG:
			return DotObjectiveFlag.new(def)
		DotObjectiveDef.Kind.RESCUE:
			return DotObjectiveRescue.new(def)
		DotObjectiveDef.Kind.HOLDOUT:
			return DotObjectiveHoldout.new(def)
	return null


## Hand every objective the gate it needs, and point every holdout at its point.
func _wire() -> void:
	for obj in objectives:
		var def := obj.def
		obj.team_gate = func(team: int) -> bool:
			return owns_all(team, def.requires_owned_for(team))

		if obj is DotObjectiveHoldout:
			var holdout := obj as DotObjectiveHoldout
			if def.holdout_owner_of != &"":
				holdout.linked = objective(def.holdout_owner_of)
				if holdout.linked == null:
					DotLog.warn(
						"objective",
						(
							"Holdout '%s' reads the owner of '%s', which is not in "
							+ "this set — its clock will never run."
						) % [def.id, def.holdout_owner_of]
					)


## Deliberately NOT called `get`.
##
## [method Object.get] exists on everything, takes a property name, and is called by
## the engine and by any code that reflects over an object. A script that overrides it
## with a different signature has broken every one of those callers, quietly, and the
## symptom appears somewhere else entirely.
func objective(id: StringName) -> DotObjective:
	return _by_id.get(id, null)


func has(id: StringName) -> bool:
	return _by_id.has(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for obj in objectives:
		out.append(obj.id())
	return out


func of_kind(kind: DotObjectiveDef.Kind) -> Array[DotObjective]:
	var out: Array[DotObjective] = []
	for obj in objectives:
		if obj.kind() == kind:
			out.append(obj)
	return out


func flags() -> Array[DotObjectiveFlag]:
	var out: Array[DotObjectiveFlag] = []
	for obj in objectives:
		if obj is DotObjectiveFlag:
			out.append(obj as DotObjectiveFlag)
	return out


func owner_of(id: StringName) -> int:
	var obj := get(id)
	return obj.owner_team if obj != null else 0


func owns_all(team: int, required: Array[StringName]) -> bool:
	for id in required:
		var obj := objective(id)
		if obj == null:
			# A prerequisite that is not in the set is one nobody can satisfy. Refusing
			# is the safe answer and the warning is where it is noticed: silently
			# allowing it turns a tug of war back into a race, which is exactly the
			# failure this gate exists to prevent.
			DotLog.warn(
				"objective",
				"Prerequisite '%s' is not in this set; team %d is refused." % [id, team]
			)
			return false
		if obj.owner_team != team:
			return false
	return true


## How many of these a team owns. What a "you are winning" HUD counts.
func owned_by(team: int) -> int:
	var n := 0
	for obj in objectives:
		if obj.owner_team == team and not obj.locked:
			n += 1
	return n


## Whether one team owns every unlocked objective — the usual "all points captured"
## win condition, which this addon reports and does not act on.
func owns_everything(team: int) -> bool:
	var any := false
	for obj in objectives:
		if obj.locked:
			continue
		any = true
		if obj.owner_team != team:
			return false
	return any


## Play only these this round, in this state. Everything else is locked out.
##
## [param owners] pre-sets who holds what, which is what a round layout is for: the
## second round of a five-point map starts with each team already holding two.
func set_round(ids: Array[StringName], owners: Dictionary = {}) -> DotResult:
	for id in ids:
		if not has(id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Round layout names '%s', which is not in this set." % id
			)
	_round = ids.duplicate()
	for obj in objectives:
		obj.locked = not (_round.is_empty() or _round.has(obj.id()))
	for id: Variant in owners.keys():
		var obj := objective(StringName(str(id)))
		if obj != null:
			obj.owner_team = int(owners[id])
	return DotResult.success(null)


func round_ids() -> Array[StringName]:
	return _round.duplicate()


## Back to the start of a round. Keeps the round layout; a caller changing rounds
## calls [method set_round] again afterwards.
func reset() -> void:
	for obj in objectives:
		obj.reset()
	for obj in objectives:
		obj.locked = not (_round.is_empty() or _round.has(obj.id()))


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("objectives: %d%s" % [
		objectives.size(),
		"" if _round.is_empty() else (", round of %d" % _round.size()),
	])
	for obj in objectives:
		for line in obj.describe_lines():
			out.append("  " + line)
	return out
