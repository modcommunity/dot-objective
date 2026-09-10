class_name DotObjectiveFlag
extends DotObjective

## Carry theirs to yours. The intelligence, the flag, the briefcase.
##
## [member DotObjective.owner_team] is whose flag it is and never changes — a flag
## belongs to the team that defends it, and the team that scores with it is the other
## one. That is the opposite of a control point and getting it the wrong way round is
## the most common bug in a hand-written capture-the-flag mode: the capture is scored
## for the wrong side and nobody notices until the scoreboard is read.
##
## [member DotObjective.progress] is the carrier's journey home, 0 at the flag's own
## base and 1 at the capture point — which is the only number that means anything to
## a spectator, and is deliberately not "how long until it returns".
##
## [b]Three settings turn this into three different games.[/b]
## [member DotObjectiveDef.flag_touch_returns] is Counter-Strike-style instant return
## against Team Fortress 2's timer that both teams play around;
## [member DotObjectiveDef.flag_requires_own_at_home] is what stops a stalemate being
## two simultaneous captures; and
## [member DotObjectiveDef.flag_return_ticks] is how long a dropped flag is a decision
## rather than a formality.

enum State {
	HOME,     ## On its stand.
	CARRIED,  ## Somebody has it.
	DROPPED,  ## On the floor, counting down to going home.
}

var state: State = State.HOME

var carrier: String = ""

## Where it is when it is not on its stand or in somebody's hands.
var at: Vector3 = Vector3.ZERO

## Ticks until a dropped flag goes home by itself.
var return_left: int = 0

## How many times this flag has been carried in. A game shows it as the score.
var captures: int = 0

var _carrier_team: int = 0
var _home: Vector3 = Vector3.ZERO
var _last_fraction: float = -1.0


func _init(p_def: DotObjectiveDef = null) -> void:
	super(p_def)
	if p_def != null and p_def.area != null:
		_home = p_def.area.centre
		at = _home


## Whose flag it is. The team that defends it.
func home_team() -> int:
	return def.initial_team if def != null else 0


func capture_area() -> DotObjectiveArea:
	if def == null:
		return null
	return def.flag_capture_area if def.flag_capture_area != null else def.area


func is_home() -> bool:
	return state == State.HOME


func position() -> Vector3:
	return at


func progress() -> float:
	if state != State.CARRIED:
		return 0.0
	var target := capture_area()
	if target == null:
		return 0.0
	var total := _home.distance_to(target.centre)
	if total <= 0.0:
		return 0.0
	var left := at.distance_to(target.centre)
	return clampf(1.0 - (left / total), 0.0, 1.0)


func progressing_team() -> int:
	return _carrier_team


func _reset() -> void:
	state = State.HOME
	carrier = ""
	at = _home
	return_left = 0
	_carrier_team = 0
	_last_fraction = -1.0


## Somebody touched it. What happens depends on which side they are on, which is the
## whole of capture-the-flag in one function.
func touch(key: String, presence: DotObjectivePresence) -> DotResult:
	if is_finished():
		return DotResult.fail(DotError.CODE_STATE, "This flag is out of play.")
	if not presence.is_alive(key):
		return DotResult.fail(DotError.CODE_STATE, "A dead player touches nothing.")

	var team := presence.team_of(key)
	if team <= 0:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "No team, no flag.")

	var where := presence.position_of(key)
	if where.distance_to(at) > def.flag_touch_radius and state != State.CARRIED:
		return DotResult.fail(
			DotError.CODE_STATE,
			"Too far from the flag (%.1f > %.1f)."
				% [where.distance_to(at), def.flag_touch_radius]
		)

	if team == home_team():
		if state == State.DROPPED and def.flag_touch_returns:
			_send_home(key)
			return DotResult.success(&"returned")
		return DotResult.fail(
			DotError.CODE_STATE, "A team does not carry its own flag."
		)

	if state == State.CARRIED:
		return DotResult.fail(
			DotError.CODE_STATE, "%s already has it." % carrier
		)
	if locked or not team_allowed(team):
		return DotResult.fail(DotError.CODE_STATE, "This flag is not in play yet.")

	state = State.CARRIED
	carrier = key
	_carrier_team = team
	return_left = 0
	at = where
	phase = Phase.ACTIVE
	_last_fraction = -1.0
	started.emit(team, key)
	event.emit(&"taken", {"by": key, "team": team})
	return DotResult.success(&"taken")


## The carrier died, disconnected, or dropped it deliberately.
func drop(position: Vector3) -> DotResult:
	if state != State.CARRIED:
		return DotResult.fail(DotError.CODE_STATE, "Nobody is carrying it.")
	var was := carrier
	var team := _carrier_team
	state = State.DROPPED
	carrier = ""
	_carrier_team = 0
	at = position
	return_left = def.flag_return_ticks
	phase = Phase.IDLE
	_last_fraction = -1.0
	interrupted.emit(team, &"dropped")
	event.emit(&"dropped", {"by": was, "at": position, "returns_in": return_left})
	return DotResult.success(null)


## Put it back on its stand, by hand.
func send_home(by: String = "") -> DotResult:
	if state == State.HOME:
		return DotResult.fail(DotError.CODE_STATE, "It is already home.")
	_send_home(by)
	return DotResult.success(null)


func _send_home(by: String) -> void:
	var was := carrier
	state = State.HOME
	carrier = ""
	_carrier_team = 0
	at = _home
	return_left = 0
	phase = Phase.IDLE
	_last_fraction = -1.0
	event.emit(&"returned", {"by": by, "from": was})


## Whether a carrier may score right now, and why not when they may not.
##
## Public because a HUD has to be able to say "your flag is not at home" — a carrier
## standing on their own capture point with nothing happening and no explanation is
## the single most confusing state this mode has.
func may_capture(other_flags: Array[DotObjectiveFlag]) -> DotResult:
	if state != State.CARRIED:
		return DotResult.fail(DotError.CODE_STATE, "Nobody is carrying it.")
	if not def.flag_requires_own_at_home:
		return DotResult.success(null)
	for flag in other_flags:
		if flag == null or flag == self:
			continue
		if flag.home_team() != _carrier_team:
			continue
		if not flag.is_home():
			return DotResult.fail(
				DotError.CODE_STATE,
				"Your own flag is not at home, so this one cannot be captured."
			)
	return DotResult.success(null)


func _advance(presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	match state:
		State.CARRIED:
			if not presence.is_alive(carrier):
				# The game is expected to call drop() on death, and this is the second
				# lock on that door: a carrier who is dead and still carrying is a flag
				# nobody can take and that never comes home.
				var _res := drop(at)
				return
			at = presence.position_of(carrier)
			_announce()

		State.DROPPED:
			return_left -= 1
			if return_left <= 0:
				_send_home("")

		_:
			pass


## Score it. The manager calls this when the carrier reaches the capture area and
## [method may_capture] agrees; it is separate so a game can add its own condition.
func capture(by: String) -> DotResult:
	if state != State.CARRIED:
		return DotResult.fail(DotError.CODE_STATE, "Nobody is carrying it.")
	var team := _carrier_team
	captures += 1
	event.emit(&"captured", {"by": by, "team": team, "total": captures})
	_send_home(by)
	if def.wins_round:
		_complete(team, by)
	else:
		completed.emit(team, by)
	return DotResult.success(team)


func _announce() -> void:
	var f := progress()
	if absf(f - _last_fraction) < 0.005:
		return
	_last_fraction = f
	progressed.emit(f, _carrier_team)


func _to_wire(out: Dictionary) -> void:
	out["s"] = int(state)
	out["c"] = carrier
	out["at"] = at
	out["rl"] = return_left
	out["ct"] = _carrier_team
	out["n"] = captures


func _apply_wire(w: Dictionary) -> void:
	state = int(w.get("s", int(state))) as State
	carrier = str(w.get("c", carrier))
	at = w.get("at", at)
	return_left = int(w.get("rl", return_left))
	_carrier_team = int(w.get("ct", _carrier_team))
	captures = int(w.get("n", captures))


func describe_lines() -> PackedStringArray:
	var out := super()
	out.append(
		"    %s home_team=%d carrier=%s returns_in=%d captures=%d"
			% [
				State.keys()[state], home_team(),
				carrier if carrier != "" else "-", return_left, captures,
			]
	)
	return out
