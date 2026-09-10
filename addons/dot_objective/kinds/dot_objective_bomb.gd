class_name DotObjectiveBomb
extends DotObjective

## Plant it, defuse it. Counter-Strike's C4, without the weapon.
##
## [member DotObjective.progress] is the plant or the defuse while one is running, and
## the fuse burning down once it is armed — which is the number a HUD wants in all
## three cases and the reason they share one field.
##
## [b]The bomb is not an item and this addon does not know what one is.[/b] A game
## gives it to somebody with [method give_to], drops it with [method drop_at] when that
## player dies, and hands it back with [method try_pick_up]. Whether that is a
## [DotItem] in a [DotLoadout] slot, a prop, or a boolean on a player is the game's
## business; every one of those still needs the plant timer, the defuse race and the
## fuse, and none of them should be reimplementing it.
##
## [b]Interruption is checked here rather than trusted.[/b] The oldest bug in this
## mode is a defuse that finishes because nobody told the objective the defuser had
## died: every tick re-tests that the acting player is alive, on the right side, and
## still inside the radius, and a defuse that fails those is cancelled with a reason.
## A game that only calls [method cancel_defuse] on death has one path to get wrong;
## this has none.

enum State {
	HELD,      ## Somebody is carrying it.
	DROPPED,   ## It is on the floor.
	PLANTING,  ## Being armed.
	PLANTED,   ## Armed. The fuse is burning.
	DEFUSING,  ## Armed, and being cut.
	DEFUSED,   ## Over. The defenders won it.
	EXPLODED,  ## Over. The attackers won it.
}

var state: State = State.HELD

## Who has it, "" when nobody.
var carrier: String = ""

## Where it is when nobody has it, and where it was planted.
var at: Vector3 = Vector3.ZERO

var _actor: String = ""
var _actor_ticks: float = 0.0
var _actor_total: float = 1.0
var _fuse_left: float = 0.0
var _with_kit: bool = false
var _planted_by: String = ""
var _last_fraction: float = -1.0

## Stamped when a defuse starts rather than read when it finishes.
##
## By the time a ten-second defuse completes the player may have left, and a roster
## that no longer has them answers "team 0" — which is a legitimate answer for a
## spectator and would silently score the round for nobody.
var _defusing_team: int = 0


func _init(p_def: DotObjectiveDef = null) -> void:
	super(p_def)
	if p_def != null:
		_fuse_left = float(p_def.bomb_fuse_ticks)


## Whose bomb it is. Everybody else defuses.
func attacking_team() -> int:
	if def == null:
		return 0
	if not def.capturable_by.is_empty():
		return def.capturable_by[0]
	return def.initial_team


func is_armed() -> bool:
	return state == State.PLANTED or state == State.DEFUSING


## Ticks until it goes off. Meaningless before it is armed.
func fuse_remaining() -> float:
	return _fuse_left


func progress() -> float:
	match state:
		State.PLANTING, State.DEFUSING:
			return clampf(_actor_ticks / maxf(_actor_total, 1.0), 0.0, 1.0)
		State.PLANTED:
			var total := float(maxi(def.bomb_fuse_ticks, 1))
			return clampf(1.0 - (_fuse_left / total), 0.0, 1.0)
		_:
			return 0.0


func progressing_team() -> int:
	match state:
		State.PLANTING:
			return attacking_team()
		State.DEFUSING:
			return _defusing_team
		_:
			return 0


func _reset() -> void:
	state = State.HELD
	carrier = ""
	at = Vector3.ZERO
	_actor = ""
	_actor_ticks = 0.0
	_fuse_left = float(def.bomb_fuse_ticks) if def != null else 0.0
	_with_kit = false
	_planted_by = ""
	_defusing_team = 0
	_last_fraction = -1.0


## Hand it to a player.
func give_to(key: String) -> DotResult:
	if is_armed() or is_finished():
		return DotResult.fail(
			DotError.CODE_STATE, "The bomb is already armed; it cannot be carried."
		)
	carrier = key
	state = State.HELD
	_actor = ""
	_actor_ticks = 0.0
	event.emit(&"picked_up", {"by": key})
	return DotResult.success(null)


## Put it on the floor. What a game calls when the carrier dies or drops it.
func drop_at(position: Vector3) -> DotResult:
	if is_armed() or is_finished():
		return DotResult.fail(
			DotError.CODE_STATE, "An armed bomb is not carried and cannot be dropped."
		)
	var was := carrier
	carrier = ""
	at = position
	if state == State.PLANTING:
		_cancel_actor(&"plant_cancelled", &"dropped")
	state = State.DROPPED
	event.emit(&"dropped", {"by": was, "at": position})
	return DotResult.success(null)


func try_pick_up(key: String, presence: DotObjectivePresence) -> DotResult:
	if state != State.DROPPED:
		return DotResult.fail(DotError.CODE_STATE, "The bomb is not on the floor.")
	if not presence.is_alive(key):
		return DotResult.fail(DotError.CODE_STATE, "A dead player picks nothing up.")
	if presence.team_of(key) != attacking_team():
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Only the planting side may carry the bomb."
		)
	if presence.position_of(key).distance_to(at) > def.bomb_pickup_radius:
		return DotResult.fail(
			DotError.CODE_STATE,
			"Too far from the bomb (%.1f > %.1f)."
				% [presence.position_of(key).distance_to(at), def.bomb_pickup_radius]
		)
	return give_to(key)


func begin_plant(key: String, presence: DotObjectivePresence) -> DotResult:
	if state != State.HELD:
		return DotResult.fail(DotError.CODE_STATE, "Nobody is carrying the bomb.")
	if carrier != key:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "%s is not carrying it." % key)
	if locked or not team_allowed(attacking_team()):
		return DotResult.fail(
			DotError.CODE_STATE, "This site is not in play this round."
		)
	if not presence.is_alive(key):
		return DotResult.fail(DotError.CODE_STATE, "A dead player plants nothing.")
	if not def.area.contains(presence.position_of(key)):
		return DotResult.fail(
			DotError.CODE_STATE, "Not inside bomb site '%s'." % def.id
		)

	state = State.PLANTING
	phase = Phase.ACTIVE
	_actor = key
	_actor_ticks = 0.0
	_actor_total = float(maxi(def.bomb_plant_ticks, 1))
	_last_fraction = -1.0
	started.emit(attacking_team(), key)
	event.emit(&"plant_started", {"by": key})
	return DotResult.success(null)


func cancel_plant() -> void:
	if state != State.PLANTING:
		return
	state = State.HELD
	_cancel_actor(&"plant_cancelled", &"cancelled")


func begin_defuse(
	key: String, presence: DotObjectivePresence, with_kit: bool = false
) -> DotResult:
	if not is_armed():
		return DotResult.fail(DotError.CODE_STATE, "The bomb is not armed.")
	if state == State.DEFUSING and _actor == key:
		return DotResult.success(null)
	if not presence.is_alive(key):
		return DotResult.fail(DotError.CODE_STATE, "A dead player defuses nothing.")
	if presence.team_of(key) == attacking_team():
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "The planting side does not defuse its own bomb."
		)
	if presence.position_of(key).distance_to(at) > def.bomb_defuse_radius:
		return DotResult.fail(
			DotError.CODE_STATE, "Too far from the bomb to defuse it."
		)

	state = State.DEFUSING
	phase = Phase.ACTIVE
	_defusing_team = presence.team_of(key)
	_actor = key
	_actor_ticks = 0.0
	_with_kit = with_kit
	_actor_total = float(
		maxi(def.bomb_defuse_kit_ticks if with_kit else def.bomb_defuse_ticks, 1)
	)
	_last_fraction = -1.0
	started.emit(presence.team_of(key), key)
	event.emit(&"defuse_started", {"by": key, "kit": with_kit})
	return DotResult.success(null)


func cancel_defuse() -> void:
	if state != State.DEFUSING:
		return
	state = State.PLANTED
	_cancel_actor(&"defuse_cancelled", &"cancelled")


func _cancel_actor(what: StringName, reason: StringName) -> void:
	var who := _actor
	_actor = ""
	_actor_ticks = 0.0
	_last_fraction = -1.0
	phase = Phase.IDLE
	event.emit(what, {"by": who, "reason": String(reason)})
	interrupted.emit(progressing_team(), reason)


func _on_not_live(_presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	# A fuse that keeps burning through a round end detonates a bomb in a round that is
	# already over, and scores it. It stops with everything else.
	if state == State.PLANTING:
		cancel_plant()
	elif state == State.DEFUSING:
		cancel_defuse()


func _advance(presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	match state:
		State.PLANTING:
			if not _actor_still_valid(presence, def.area, 0.0):
				state = State.HELD
				_cancel_actor(&"plant_cancelled", &"interrupted")
				return
			_actor_ticks += 1.0
			if _actor_ticks >= _actor_total:
				_arm()
			else:
				_announce()

		State.PLANTED:
			_burn()

		State.DEFUSING:
			if not _actor_still_valid(presence, null, def.bomb_defuse_radius):
				state = State.PLANTED
				_cancel_actor(&"defuse_cancelled", &"interrupted")
				_burn()
				return
			_actor_ticks += 1.0
			if _actor_ticks >= _actor_total:
				_defused()
				return
			_burn()

		_:
			pass


## Alive, on the same side, and still where they were. Every tick, deliberately.
func _actor_still_valid(
	presence: DotObjectivePresence, area: DotObjectiveArea, radius: float
) -> bool:
	if _actor == "":
		return false
	if not presence.is_alive(_actor):
		return false
	var pos := presence.position_of(_actor)
	if area != null and not area.contains(pos):
		return false
	if radius > 0.0 and pos.distance_to(at) > radius:
		return false
	return true


func _arm() -> void:
	at = def.area.centre
	_planted_by = _actor
	carrier = ""
	state = State.PLANTED
	phase = Phase.ACTIVE
	owner_team = attacking_team()
	_fuse_left = float(maxi(def.bomb_fuse_ticks, 1))
	_actor = ""
	_actor_ticks = 0.0
	_last_fraction = -1.0
	event.emit(&"planted", {"by": _planted_by, "at": at, "site": String(def.id)})


func _burn() -> void:
	_fuse_left -= 1.0
	if _fuse_left <= 0.0:
		_fuse_left = 0.0
		state = State.EXPLODED
		event.emit(&"exploded", {"at": at, "by": _planted_by})
		_complete(attacking_team(), _planted_by)
		return
	_announce()


func _defused() -> void:
	var who := _actor
	state = State.DEFUSED
	_actor = ""
	_actor_ticks = 0.0
	event.emit(&"defused", {"by": who, "kit": _with_kit})
	_complete(_defusing_team, who)


func _to_wire(out: Dictionary) -> void:
	out["s"] = int(state)
	out["c"] = carrier
	out["at"] = at
	out["fu"] = _fuse_left
	out["ac"] = _actor
	out["ap"] = _actor_ticks
	out["at2"] = _actor_total


func _apply_wire(w: Dictionary) -> void:
	state = int(w.get("s", int(state))) as State
	carrier = str(w.get("c", carrier))
	at = w.get("at", at)
	_fuse_left = float(w.get("fu", _fuse_left))
	_actor = str(w.get("ac", _actor))
	_actor_ticks = float(w.get("ap", _actor_ticks))
	_actor_total = float(w.get("at2", _actor_total))


func _announce() -> void:
	var f := progress()
	if absf(f - _last_fraction) < 0.005:
		return
	_last_fraction = f
	progressed.emit(f, progressing_team())


func describe_lines() -> PackedStringArray:
	var out := super()
	out.append(
		"    %s carrier=%s fuse=%d actor=%s %.0f%%"
			% [
				State.keys()[state],
				carrier if carrier != "" else "-",
				int(_fuse_left),
				_actor if _actor != "" else "-",
				progress() * 100.0,
			]
	)
	return out
