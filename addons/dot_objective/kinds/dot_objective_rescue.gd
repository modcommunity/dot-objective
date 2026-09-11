class_name DotObjectiveRescue
extends DotObjective

## Get somebody out. The round-based shooters' hostages, and every co-operative
## campaign's "escort the specialist to the lift".
##
## [member DotObjective.progress] is how many have been rescued out of how many are
## required, because that is the number on the HUD and the number the round ends on.
##
## [b]A follower's position is derived, never simulated.[/b] It trails its rescuer at
## [member DotObjectiveDef.rescue_follow_distance] and that is all. This addon does not
## own a navigation graph — dot-npc does — and an escort system that pathfinds is one
## that cannot run in a headless suite, cannot run in 2D, and has quietly become a
## second, worse dot-npc. A game that wants a hostage to walk round a corner properly
## gives the follower a [DotNpcInstance] and moves it itself; the state machine here is
## still the one that says who is following whom and when they are safe.
##
## [b]The states are what a rescue mode actually has.[/b] Waiting where they started,
## following somebody, safe, or dead — and "dead" is a state rather than a removal
## because a rescue that becomes impossible has to be able to say so rather than
## quietly requiring a number nobody can reach.

enum Follower {
	WAITING,    ## Where they were left.
	FOLLOWING,  ## Behind a rescuer.
	RESCUED,    ## In the rescue area. Counted.
	LOST,       ## Dead. Not coming.
}

## id -> {"state": Follower, "at": Vector3, "leader": String}
var followers: Dictionary = {}

var _rescued: int = 0
var _last_fraction: float = -1.0


func _init(p_def: DotObjectiveDef = null) -> void:
	super(p_def)
	if p_def == null:
		return
	for i in range(p_def.rescue_followers.size()):
		var start := Vector3.ZERO
		if p_def.rescue_starts.size() > 0:
			start = p_def.rescue_starts[mini(i, p_def.rescue_starts.size() - 1)]
		followers[p_def.rescue_followers[i]] = {
			"state": Follower.WAITING,
			"at": start,
			"leader": "",
		}


## How many have to arrive. Zero in the definition means all of them.
func required() -> int:
	if def == null:
		return 0
	if def.rescue_required > 0:
		return def.rescue_required
	return def.rescue_followers.size()


func rescued() -> int:
	return _rescued


## How many are still reachable. When this drops below [method required] the objective
## can never be completed, and something has to say so.
func remaining_possible() -> int:
	var n := 0
	for id: Variant in followers.keys():
		var state: int = int((followers[id] as Dictionary)["state"])
		if state != Follower.LOST:
			n += 1
	return n


func progress() -> float:
	var need := required()
	if need <= 0:
		return 0.0
	return clampf(float(_rescued) / float(need), 0.0, 1.0)


func progressing_team() -> int:
	if def == null:
		return 0
	if not def.capturable_by.is_empty():
		return def.capturable_by[0]
	return def.initial_team


func state_of(id: StringName) -> Follower:
	var f: Variant = followers.get(id, null)
	if f == null:
		return Follower.LOST
	return int((f as Dictionary)["state"]) as Follower


func position_of(id: StringName) -> Vector3:
	var f: Variant = followers.get(id, null)
	if f == null:
		return Vector3.ZERO
	return (f as Dictionary)["at"]


func leader_of(id: StringName) -> String:
	var f: Variant = followers.get(id, null)
	if f == null:
		return ""
	return str((f as Dictionary)["leader"])


func _reset() -> void:
	_rescued = 0
	_last_fraction = -1.0
	var i := 0
	for id: Variant in followers.keys():
		var start := Vector3.ZERO
		if def != null and def.rescue_starts.size() > 0:
			start = def.rescue_starts[mini(i, def.rescue_starts.size() - 1)]
		followers[id] = {"state": Follower.WAITING, "at": start, "leader": ""}
		i += 1


## Take one along. The rescuer has to be close enough, alive, and on the rescuing side.
func take(id: StringName, key: String, presence: DotObjectivePresence) -> DotResult:
	var f: Variant = followers.get(id, null)
	if f == null:
		return DotResult.fail(DotError.CODE_INVALID, "No follower '%s' here." % id)
	var entry := f as Dictionary
	var state: int = int(entry["state"])
	if state == Follower.RESCUED:
		return DotResult.fail(DotError.CODE_STATE, "'%s' is already safe." % id)
	if state == Follower.LOST:
		return DotResult.fail(DotError.CODE_STATE, "'%s' is not coming." % id)
	if locked or not team_allowed(presence.team_of(key)):
		return DotResult.fail(DotError.CODE_STATE, "This rescue is not in play yet.")
	if not presence.is_alive(key):
		return DotResult.fail(DotError.CODE_STATE, "A dead player rescues nobody.")

	var team := presence.team_of(key)
	var want := progressing_team()
	if want > 0 and team != want:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Only team %d may rescue here." % want
		)

	var where := presence.position_of(key)
	var at: Vector3 = entry["at"]
	if where.distance_to(at) > def.rescue_touch_radius:
		return DotResult.fail(
			DotError.CODE_STATE,
			"Too far from '%s' (%.1f > %.1f)."
				% [id, where.distance_to(at), def.rescue_touch_radius]
		)

	entry["state"] = Follower.FOLLOWING
	entry["leader"] = key
	if phase == Phase.IDLE:
		phase = Phase.ACTIVE
		started.emit(team, key)
	event.emit(&"following", {"follower": String(id), "by": key})
	return DotResult.success(null)


## Leave one where they are.
func release(id: StringName) -> DotResult:
	var f: Variant = followers.get(id, null)
	if f == null:
		return DotResult.fail(DotError.CODE_INVALID, "No follower '%s' here." % id)
	var entry := f as Dictionary
	if int(entry["state"]) != Follower.FOLLOWING:
		return DotResult.fail(DotError.CODE_STATE, "'%s' is not following." % id)
	entry["state"] = Follower.WAITING
	entry["leader"] = ""
	event.emit(&"released", {"follower": String(id)})
	return DotResult.success(null)


## One is dead.
func lose(id: StringName, by: String = "") -> DotResult:
	var f: Variant = followers.get(id, null)
	if f == null:
		return DotResult.fail(DotError.CODE_INVALID, "No follower '%s' here." % id)
	var entry := f as Dictionary
	if int(entry["state"]) == Follower.RESCUED:
		return DotResult.fail(DotError.CODE_STATE, "'%s' is already safe." % id)
	entry["state"] = Follower.LOST
	entry["leader"] = ""
	event.emit(&"lost", {"follower": String(id), "by": by})

	if remaining_possible() < required():
		# It can no longer be done. Saying so is the whole reason LOST is a state: a
		# round that silently waits for a number nobody can reach is one that runs to
		# its time limit with nothing happening and no explanation.
		event.emit(&"impossible", {"remaining": remaining_possible()})
		_complete(0, "", true)
	return DotResult.success(null)


func _advance(presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	for id: Variant in followers.keys():
		var entry := followers[id] as Dictionary
		if int(entry["state"]) != Follower.FOLLOWING:
			continue

		var leader := str(entry["leader"])
		if leader == "" or not presence.is_alive(leader):
			entry["state"] = Follower.WAITING
			entry["leader"] = ""
			event.emit(&"released", {"follower": String(id), "reason": "leader_gone"})
			continue

		# Trail the leader. Derived rather than simulated — see the class note.
		var lead_at := presence.position_of(leader)
		var here: Vector3 = entry["at"]
		var gap := def.rescue_follow_distance
		var away := here - lead_at
		if away.length() > gap:
			entry["at"] = lead_at + away.normalized() * gap
		else:
			entry["at"] = here

		if def.rescue_area != null and def.rescue_area.contains(entry["at"]):
			entry["state"] = Follower.RESCUED
			entry["leader"] = ""
			_rescued += 1
			event.emit(
				&"rescued",
				{"follower": String(id), "by": leader, "total": _rescued}
			)
			if _rescued >= required():
				_complete(presence.team_of(leader), leader)
				return

	_announce()


func _announce() -> void:
	var f := progress()
	if absf(f - _last_fraction) < 0.005:
		return
	_last_fraction = f
	progressed.emit(f, progressing_team())


func _to_wire(out: Dictionary) -> void:
	var packed: Dictionary = {}
	for id: Variant in followers.keys():
		var entry := followers[id] as Dictionary
		packed[String(id)] = [int(entry["state"]), entry["at"], str(entry["leader"])]
	out["fw"] = packed
	out["rn"] = _rescued


func _apply_wire(w: Dictionary) -> void:
	_rescued = int(w.get("rn", _rescued))
	var packed: Dictionary = w.get("fw", {})
	for id: Variant in packed.keys():
		var row: Array = packed[id]
		followers[StringName(str(id))] = {
			"state": int(row[0]),
			"at": row[1],
			"leader": str(row[2]),
		}


func describe_lines() -> PackedStringArray:
	var out := super()
	out.append("    %d of %d rescued, %d still possible"
		% [_rescued, required(), remaining_possible()])
	for id: Variant in followers.keys():
		var entry := followers[id] as Dictionary
		out.append(
			"      %s %s%s" % [
				id,
				Follower.keys()[int(entry["state"])],
				(" behind %s" % entry["leader"]) if str(entry["leader"]) != "" else "",
			]
		)
	return out
