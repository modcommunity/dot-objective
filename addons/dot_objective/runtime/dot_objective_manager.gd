class_name DotObjectiveManager
extends Node

## What a round is about, running. The one node a game holds.
##
## [codeblock]
## var objectives := DotObjectiveManager.new()
## objectives.rules.live = false                 # warmup: nothing progresses
## objectives.presence = DotObjectivePresence.of(
##     roster.keys_fn, world.position_of, match_node.team_of, world.is_alive
## )
## var res := objectives.setup(map.objectives)
## add_child(objectives)
## # ... once per physics tick, from the game's own tick loop:
## objectives.advance(tick)
## [/codeblock]
##
## [b]No autoload, and two of these in one process is a supported arrangement.[/b] The
## family's usual reason and then one more: a server that runs a game and a client that
## mirrors it are two managers, and so is a suite that plays both halves of a capture
## in one run.
##
## [b]It never ends a round and never scores anything itself.[/b] It emits, and
## [member score_fn] hands a completion to whatever is keeping score —
## [method DotMatch.report_objective] in every game here. dot-objective does not import
## dot-match, because a control point is the same rule in a game that has no match loop
## at all, and a hard dependency would make it one that could not compile there.

## An objective was completed. [param id] is which, [param team] may be 0.
signal objective_completed(id: StringName, team: int, by: String)

## Somebody began making progress on one.
signal objective_started(id: StringName, team: int, by: String)

## Progress stopped. [param reason] is why: contested, decayed, dropped, receding.
signal objective_interrupted(id: StringName, team: int, reason: StringName)

## Somebody stopped somebody else's progress and earned credit for it.
signal objective_blocked(id: StringName, by: String, team: int)

## A fraction changed enough to redraw.
signal objective_progressed(id: StringName, fraction: float, team: int)

## Anything kind-specific: a plant, a defuse, a checkpoint, a rescue, a flag taken.
signal objective_event(id: StringName, what: StringName, data: Dictionary)

## Every objective in play is held by one team. The usual "all points captured".
signal all_captured(team: int)

## An objective that says it wins the round has been completed. A game connects this
## to whatever its round loop is, and this addon does nothing else about it.
signal round_objective_met(id: StringName, team: int, by: String)

@export var rules: DotObjectiveRules = null

## The objectives of the current map. Assigning this and calling [method setup] is the
## whole of loading a map's layout.
@export var defs: Array[DotObjectiveDef] = []

## Off on a client, which mirrors rather than simulating.
##
## The family's rule, and the specific bug it prevents: two machines both running a
## capture clock disagree by whatever their tick rates differ by, and the client's HUD
## then shows a point captured that the server has not captured.
@export var authoritative: bool = true

var presence: DotObjectivePresence = null

var objectives: DotObjectiveSet = null

## Where a completion goes to be scored.
## [code](id: StringName, team: int, by: String, team_points: int, player_points: int)[/code]
var score_fn: Callable = Callable()

var _tick: int = 0
var _announced_sweep: int = 0


func _init() -> void:
	if rules == null:
		rules = DotObjectiveRules.new()


func _ready() -> void:
	# A created DotNodeRef subsystem has already run _ready() by the time a host
	# assigns its config — this family lost dot-server's audit log to exactly that.
	# So _ready() builds nothing here; setup() is explicit and returns a DotResult.
	if rules == null:
		rules = DotObjectiveRules.new()


## Build the objectives for a map. Refuses rather than half-building.
func setup(p_defs: Array[DotObjectiveDef] = []) -> DotResult:
	if not p_defs.is_empty():
		defs = p_defs
	if rules == null:
		rules = DotObjectiveRules.new()

	var res := rules.validate()
	if not res.ok:
		return res.wrap("objective rules")

	var built := DotObjectiveSet.build(defs)
	if not built.ok:
		return built.wrap("objective set")

	_disconnect_all()
	objectives = built.value
	_connect_all()
	_announced_sweep = 0

	if authoritative and presence != null:
		var pres := presence.validate()
		if not pres.ok:
			return pres.wrap("objective presence")

	DotLog.info(
		"objective",
		"%d objectives ready" % objectives.objectives.size(),
		{"ids": str(objectives.ids())}
	)
	return DotResult.success(null)


func _connect_all() -> void:
	for obj in objectives.objectives:
		var id := obj.id()
		obj.completed.connect(func(team: int, by: String) -> void:
			_on_completed(id, obj, team, by))
		obj.started.connect(func(team: int, by: String) -> void:
			objective_started.emit(id, team, by))
		obj.interrupted.connect(func(team: int, reason: StringName) -> void:
			objective_interrupted.emit(id, team, reason))
		obj.blocked.connect(func(by: String, team: int) -> void:
			objective_blocked.emit(id, by, team))
		obj.progressed.connect(func(fraction: float, team: int) -> void:
			objective_progressed.emit(id, fraction, team))
		obj.event.connect(func(what: StringName, data: Dictionary) -> void:
			objective_event.emit(id, what, data))


func _disconnect_all() -> void:
	if objectives == null:
		return
	for obj in objectives.objectives:
		for sig in [
			obj.completed, obj.started, obj.interrupted,
			obj.blocked, obj.progressed, obj.event,
		]:
			for connection in (sig as Signal).get_connections():
				(sig as Signal).disconnect(connection["callable"])


func _on_completed(id: StringName, obj: DotObjective, team: int, by: String) -> void:
	objective_completed.emit(id, team, by)

	if score_fn.is_valid() and team > 0:
		score_fn.call(id, team, by, obj.def.score_points, obj.def.player_points)

	if obj.def.wins_round and obj.phase == DotObjective.Phase.COMPLETE:
		round_objective_met.emit(id, team, by)

	_check_sweep(team)


func _check_sweep(team: int) -> void:
	if team <= 0 or objectives == null:
		return
	if not objectives.owns_everything(team):
		return
	# Once per sweep. A capture that changes hands and comes back would otherwise
	# announce a second time and a mode scored on it would score twice — the family's
	# "announce exactly once" bug, which dot-vote's play history hit last.
	if _announced_sweep == team:
		return
	_announced_sweep = team
	all_captured.emit(team)


## One tick. The only thing that moves anything here.
func advance(tick: int) -> void:
	_tick = tick
	if objectives == null:
		return
	if not authoritative:
		return
	if presence == null:
		return

	for obj in objectives.objectives:
		obj.advance(tick, presence, rules)

	_check_flag_captures()

	if _announced_sweep != 0 and not objectives.owns_everything(_announced_sweep):
		_announced_sweep = 0


## A carrier standing on their capture point scores. Checked here rather than in
## [DotObjectiveFlag] because the rule needs the other flags, and an objective that
## goes looking for its siblings is one that cannot be tested on its own.
func _check_flag_captures() -> void:
	var flags := objectives.flags()
	if flags.is_empty():
		return
	for flag in flags:
		if flag.state != DotObjectiveFlag.State.CARRIED:
			continue
		var target := flag.capture_area()
		if target == null:
			continue
		if not target.contains(presence.position_of(flag.carrier)):
			continue
		var allowed := flag.may_capture(flags)
		if not allowed.ok:
			continue
		var _res := flag.capture(flag.carrier)


## Put every objective back to the start of a round.
func reset_round() -> void:
	if objectives == null:
		return
	objectives.reset()
	_announced_sweep = 0


func objective(id: StringName) -> DotObjective:
	return objectives.objective(id) if objectives != null else null


## Whether anything is in play. A game with no objectives is a deathmatch, and asking
## is cheaper than every caller checking for a null manager.
func has_objectives() -> bool:
	return objectives != null and not objectives.objectives.is_empty()


func set_live(live: bool) -> void:
	if rules != null:
		rules.live = live


func set_overtime(overtime: bool) -> void:
	if rules != null:
		rules.overtime = overtime


# --- The wire ---------------------------------------------------------------

## Everything a client needs to draw the objectives, as one dictionary.
##
## Sent whole rather than as deltas, deliberately: the whole of a map's objective state
## is a few hundred bytes at twenty entities, it is sent a few times a second at most,
## and a delta scheme here would be a second replication system beside dot-net's for no
## measurable gain. A game that wants it in a [DotNetVar] can put this in one.
func to_wire() -> Dictionary:
	var out := {"t": _tick, "o": []}
	if objectives == null:
		return out
	var rows: Array = []
	for obj in objectives.objectives:
		rows.append(obj.to_wire())
	out["o"] = rows
	return out


func apply_wire(w: Dictionary) -> void:
	if objectives == null:
		return
	_tick = int(w.get("t", _tick))
	var rows: Array = w.get("o", [])
	for row: Variant in rows:
		var entry := row as Dictionary
		var obj := objectives.objective(StringName(str(entry.get("id", ""))))
		if obj == null:
			continue
		obj.apply_wire(entry)


func describe() -> Dictionary:
	return {
		"authoritative": authoritative,
		"live": rules.live if rules != null else false,
		"overtime": rules.overtime if rules != null else false,
		"tick": _tick,
		"count": objectives.objectives.size() if objectives != null else 0,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(
		"DotObjectiveManager %s tick=%d live=%s%s"
			% [
				"authoritative" if authoritative else "mirroring",
				_tick,
				"yes" if (rules != null and rules.live) else "no",
				" OVERTIME" if (rules != null and rules.overtime) else "",
			]
	)
	if objectives != null:
		for line in objectives.describe_lines():
			out.append("  " + line)
	return out
