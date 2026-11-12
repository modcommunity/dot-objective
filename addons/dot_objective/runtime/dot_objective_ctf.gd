class_name DotObjectiveCtf
extends Node

## Capture the flag for any number of teams: one flag per team on its stand, every other team may take it and score it at their own stand.
##
## Owns a [DotObjectiveManager] holding the flags. The server calls [method advance] each tick and [method player_died] / [method player_left]; a client applies [method to_wire]. Scoring goes out through [signal captured] and the manager's `score_fn`; the match ends through [signal ended].

signal captured(team: int, by: String, total: int)
## taken, dropped, returned, captured: a HUD and an announcer listen here. `team` is the flag's own team.
signal flag_event(team: int, what: StringName, data: Dictionary)
## `winner` 0 is a draw; `reason` is capture_limit or time_limit.
signal ended(winner: int, reason: StringName)

@export var rules: DotObjectiveCtfRules = null
@export var authoritative: bool = true
var presence: DotObjectivePresence = null
var manager: DotObjectiveManager = null
var tick_rate: int = 64
## team -> captures this match.
var scores: Dictionary = {}
var winner: int = 0
var finished: bool = false
## Ticks the match has been live, which the time limit counts.
var live_ticks: int = 0


## Flag defs for [param bases] (team id -> Vector3), by the rules.
static func defs_for(
	bases: Dictionary, p_rules: DotObjectiveCtfRules, rate: int
) -> Array[DotObjectiveDef]:
	var out: Array[DotObjectiveDef] = []
	var teams: Array = bases.keys()
	teams.sort()
	for t: int in teams:
		var d := DotObjectiveDef.flag(
			StringName("flag_%d" % t),
			DotObjectiveArea.sphere(bases[t], p_rules.stand_radius), t
		)
		d.display_name = "Team %d Flag" % t
		d.label = str(t)
		d.flag_capture_at_own_stand = true
		d.flag_return_ticks = p_rules.return_sec * rate
		d.flag_pickup_delay_ticks = p_rules.drop_sec * rate
		d.flag_touch_returns = p_rules.friendly_return
		d.flag_requires_own_at_home = p_rules.require_home
		d.flag_touch_radius = p_rules.touch_radius
		d.score_points = 1
		d.player_points = 1
		out.append(d)
	return out


## Builds the flags. [param bases] is team id -> stand position; at least two teams.
func setup(bases: Dictionary, p_score_fn: Callable = Callable()) -> DotResult:
	if rules == null:
		rules = DotObjectiveCtfRules.new()
	var ok := rules.validate()
	if not ok.ok:
		return ok.wrap("ctf rules")
	if bases.size() < 2:
		return DotResult.fail(DotError.CODE_INVALID, "Capture the flag needs a base for at least two teams.")
	if manager == null:
		manager = DotObjectiveManager.new()
		manager.name = "FlagManager"
		add_child(manager)
		manager.objective_event.connect(_on_event)
	manager.authoritative = authoritative
	manager.presence = presence
	manager.score_fn = p_score_fn
	var res := manager.setup(defs_for(bases, rules, tick_rate))
	if not res.ok:
		return res.wrap("ctf flags")
	reset_match()
	return DotResult.success(null)


## A new match: scores, clock and flags back to the start.
func reset_match() -> void:
	scores.clear()
	for f in flags():
		scores[f.home_team()] = 0
	winner = 0
	finished = false
	live_ticks = 0
	if manager != null:
		manager.reset_round()


func flags() -> Array[DotObjectiveFlag]:
	if manager == null or manager.objectives == null:
		return []
	return manager.objectives.flags()


func flag_of(team: int) -> DotObjectiveFlag:
	for f in flags():
		if f.home_team() == team:
			return f
	return null


## The flag [param key] is carrying, or null.
func carried_by(key: String) -> DotObjectiveFlag:
	if manager == null or manager.objectives == null:
		return null
	# Walks the set in place: flags() allocates, and this runs per player per tick.
	for obj in manager.objectives.objectives:
		var f := obj as DotObjectiveFlag
		if f != null and f.state == DotObjectiveFlag.State.CARRIED and f.carrier == key:
			return f
	return null


## Movement multiplier for [param key]: the carrier speed while holding a flag, else 1.
func speed_scale(key: String) -> float:
	return rules.carrier_speed if carried_by(key) != null else 1.0


## One server tick while the match is [param live].
func advance(tick: int, live: bool = true) -> void:
	if manager == null or not authoritative or finished:
		return
	manager.set_live(live)
	if not live:
		manager.advance(tick)
		return
	live_ticks += 1
	_touch()
	manager.advance(tick)
	if rules.time_limit_sec > 0 and live_ticks >= rules.time_limit_sec * tick_rate:
		_finish(_leader(), &"time_limit")


## Takes or returns every flag a living player stands on; a carrier takes no second flag.
func _touch() -> void:
	var keys := presence.participants()
	for f in flags():
		for key in keys:
			if not presence.is_alive(key) or carried_by(key) != null:
				continue
			if presence.position_of(key).distance_to(f.at) > f.def.flag_touch_radius:
				continue
			if f.touch(key, presence).ok:
				break


## Drops whatever [param key] carried where they fell.
func player_died(key: String) -> void:
	var f := carried_by(key)
	if f != null:
		var _res := f.drop(f.at)


## A leaver drops the flag too.
func player_left(key: String) -> void:
	player_died(key)


func _on_event(id: StringName, what: StringName, data: Dictionary) -> void:
	var f: DotObjectiveFlag = manager.objectives.objective(id) as DotObjectiveFlag
	if f == null:
		return
	flag_event.emit(f.home_team(), what, data)
	if what != &"captured" or not authoritative:
		return
	var team := int(data.get("team", 0))
	scores[team] = int(scores.get(team, 0)) + 1
	captured.emit(team, str(data.get("by", "")), int(scores[team]))
	if rules.capture_limit > 0 and int(scores[team]) >= rules.capture_limit and not finished:
		_finish(team, &"capture_limit")


func _leader() -> int:
	var best := 0
	var best_n := -1
	var tie := false
	for t: int in scores:
		var n := int(scores[t])
		if n > best_n:
			best = t
			best_n = n
			tie = false
		elif n == best_n:
			tie = true
	return 0 if tie else best


func _finish(team: int, reason: StringName) -> void:
	finished = true
	winner = team
	if manager != null:
		manager.set_live(false)
	ended.emit(team, reason)


## Seconds left on the time limit, or -1 for no limit.
func time_left_sec() -> float:
	if rules.time_limit_sec <= 0:
		return -1.0
	return maxf(float(rules.time_limit_sec) - float(live_ticks) / float(tick_rate), 0.0)


## What a HUD draws: per team the flag state, carrier, seconds to auto-return, captures.
func hud_state() -> Dictionary:
	var teams := {}
	for f in flags():
		teams[f.home_team()] = {
			"state": DotObjectiveFlag.State.keys()[f.state],
			"carrier": f.carrier,
			"returns_in": float(f.return_left) / float(tick_rate),
			"captures": int(scores.get(f.home_team(), 0)),
		}
	return {"teams": teams, "time_left": time_left_sec(), "winner": winner, "finished": finished}


## The whole replicated state; a client calls [method apply_wire] with it.
func to_wire() -> Dictionary:
	var sc := {}
	for t: int in scores:
		sc[str(t)] = scores[t]
	var out := manager.to_wire() if manager != null else {}
	out["ctf"] = {"s": sc, "w": winner, "f": finished, "lt": live_ticks}
	return out


## [method to_wire] with every Vector3 as a three-number array, so it survives JSON.
func to_json_wire() -> Dictionary:
	return _plain(to_wire())


static func _plain(v: Variant) -> Variant:
	if v is Vector3:
		return [v.x, v.y, v.z]
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = _plain(v[k])
		return d
	if v is Array:
		var a := []
		for x: Variant in v:
			a.append(_plain(x))
		return a
	return v


func apply_wire(w: Dictionary) -> void:
	if manager == null:
		return
	manager.apply_wire(w)
	var c: Dictionary = w.get("ctf", {})
	scores.clear()
	for k: Variant in c.get("s", {}):
		scores[int(str(k))] = int((c["s"] as Dictionary)[k])
	winner = int(c.get("w", winner))
	finished = bool(c.get("f", finished))
	live_ticks = int(c.get("lt", live_ticks))


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("DotObjectiveCtf scores=%s winner=%d finished=%s" % [scores, winner, finished])
	if manager != null:
		out.append_array(manager.describe_lines())
	return out
