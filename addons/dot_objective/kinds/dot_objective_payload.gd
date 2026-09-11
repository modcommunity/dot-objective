class_name DotObjectivePayload
extends DotObjective

## A cart pushed along a path. The class-based objective shooters' cart watcher,
## reduced to the part that is a rule rather than a brush entity.
##
## [member DotObjective.progress] is the fraction of the path travelled, which is what
## every payload HUD ever drawn shows.
##
## [b]The cart has no body and nothing here moves a node.[/b] It has a distance along
## [member DotObjectiveDef.payload_path], and [method position] turns that into a
## point. A game draws whatever it likes there — an [AnimatableBody3D] on a path, a
## sprite, nothing at all in a headless test. The alternative, owning a physics object,
## would make this addon untestable and would put the authority for where the cart is
## in a place two machines disagree about.
##
## [b]A shipped speed table, not a formula.[/b] One pusher moves it at 0.55 of full
## speed, two at 0.77, three or more at 1.0. Those are hand-picked so a second pusher
## is clearly worth having and a fourth is clearly worth sending somewhere else; no
## smooth curve produces that shape, which is why the numbers are three exported
## fields rather than an expression. See [DotObjectiveRules].
##
## [b]Three things move it besides pushing, and they are what make a payload map.[/b]
## A downhill segment rolls it forward on its own at full speed, so a defender who
## stops pushing at the top of a hill has still lost the hill. An uphill segment rolls
## it backwards when nobody is on it. And after
## [member DotObjectiveDef.payload_recede_ticks] of nobody at all it starts receding
## anywhere, back to the last checkpoint it latched, which is what stops a stalemate
## being a draw.

## Distance travelled along the path.
var distance: float = 0.0

## Where it may not roll back past. Raised by a checkpoint, never lowered.
var floor_distance: float = 0.0

## -1 rolling back, 0 stopped, 1/2/3 the three push speeds. What a HUD draws arrows
## for, and the reason it is a level rather than a speed: a player cannot see 0.77.
var speed_level: int = 0

var _idle_ticks: int = 0
var _receding: bool = false
var _pushers: int = 0
var _pushing_team: int = 0
var _blocked: bool = false
var _latched: Dictionary = {}
var _last_fraction: float = -1.0
var _total: float = 1.0


func _init(p_def: DotObjectiveDef = null) -> void:
	super(p_def)
	if p_def != null:
		_total = maxf(p_def.path_length(), 0.0001)


## Which team pushes it. Everybody else defends.
func pushing_team() -> int:
	if def == null:
		return 0
	if not def.capturable_by.is_empty():
		return def.capturable_by[0]
	return def.initial_team


func position() -> Vector3:
	return def.point_at(distance) if def != null else Vector3.ZERO


func position_2d() -> Vector2:
	var p := position()
	return Vector2(p.x, p.z)


func progress() -> float:
	return clampf(distance / _total, 0.0, 1.0)


func progressing_team() -> int:
	return _pushing_team


func pushers() -> int:
	return _pushers


func is_receding() -> bool:
	return _receding


## Ticks of nobody pushing before it will start rolling back. Negative once it is.
func idle_remaining(rules: DotObjectiveRules) -> int:
	var limit := def.payload_recede_ticks
	if rules.overtime:
		limit = rules.payload_recede_overtime_ticks
	return limit - _idle_ticks


func _reset() -> void:
	distance = 0.0
	floor_distance = 0.0
	speed_level = 0
	_idle_ticks = 0
	_receding = false
	_pushers = 0
	_pushing_team = 0
	_blocked = false
	_latched.clear()
	_last_fraction = -1.0


func _on_not_live(_presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	# It stops. It does not recede: a cart that rolls backwards through a round end has
	# lost ground nobody was allowed to take, and the idle counter would have been
	# running through a freeze time nobody could push in.
	speed_level = 0
	_pushers = 0
	_idle_ticks = 0
	_receding = false


func _advance(presence: DotObjectivePresence, rules: DotObjectiveRules) -> void:
	var here := def.area.moved_to(position())
	here.radius = def.payload_push_radius
	var counts := presence.counts_in(here)

	var team := pushing_team()
	var pushing: DotObjectivePresence.Count = counts.get(team, null)
	_pushers = pushing.cappers if pushing != null else 0
	_pushing_team = team if _pushers > 0 else 0

	_blocked = false
	if rules.payload_defenders_block:
		for other_id: Variant in counts.keys():
			if int(other_id) == team:
				continue
			var c: DotObjectivePresence.Count = counts[other_id]
			if c.cappers > 0 or c.blockers > 0:
				_blocked = true
				break

	var gradient := def.gradient_at(distance)
	var step := 0.0

	if locked:
		# A locked stage is one whose turn has not come. It holds still rather than
		# receding: rolling backwards through a stage you have not started is a loss of
		# ground nobody could have defended.
		speed_level = 0
		_announce()
		return

	if _pushers > 0 and not _blocked:
		_idle_ticks = 0
		_receding = false
		var fraction := 1.0 if gradient < 0 else rules.payload_fraction(_pushers)
		step = def.payload_speed * fraction
		speed_level = mini(_pushers, 3)
		if phase != Phase.ACTIVE:
			phase = Phase.ACTIVE
			started.emit(team, pushing.first if pushing != null else "")
	elif _blocked:
		# Blocked and on a downhill still rolls: the hill is doing the work, and a
		# defender standing in front of a cart on a slope is the genre's deliberate
		# exception. Everywhere else a blocked cart is a stopped cart.
		_idle_ticks = 0
		if gradient < 0:
			step = def.payload_speed
			speed_level = 3
		else:
			speed_level = 0
			if phase == Phase.ACTIVE:
				phase = Phase.CONTESTED
				interrupted.emit(team, &"blocked")
	else:
		_idle_ticks += 1
		if gradient < 0:
			step = def.payload_speed
			speed_level = 3
		elif gradient > 0:
			step = -def.payload_speed
			speed_level = -1
		elif idle_remaining(rules) <= 0:
			if not _receding:
				_receding = true
				interrupted.emit(team, &"receding")
			step = -def.payload_speed * rules.payload_recede_speed
			speed_level = -1
		else:
			speed_level = 0

	if step != 0.0:
		distance = clampf(distance + step, floor_distance, _total)
		_latch()

	if distance >= _total:
		var by := ""
		if pushing != null:
			by = pushing.first
		speed_level = 0
		_complete(team, by)
		return

	_announce()


## Raise the floor past any checkpoint we have crossed, once each.
func _latch() -> void:
	for d in def.payload_checkpoints:
		if distance < d:
			continue
		var key := "%.4f" % d
		if _latched.has(key):
			continue
		_latched[key] = true
		floor_distance = maxf(floor_distance, d)
		event.emit(
			&"checkpoint",
			{"at": d, "fraction": d / _total, "team": pushing_team()}
		)


func _announce() -> void:
	var f := progress()
	if absf(f - _last_fraction) < 0.002:
		return
	_last_fraction = f
	progressed.emit(f, _pushing_team)


func _to_wire(out: Dictionary) -> void:
	out["d"] = distance
	out["fd"] = floor_distance
	out["sl"] = speed_level
	out["pu"] = _pushers
	out["rc"] = _receding


func _apply_wire(w: Dictionary) -> void:
	distance = float(w.get("d", distance))
	floor_distance = float(w.get("fd", floor_distance))
	speed_level = int(w.get("sl", speed_level))
	_pushers = int(w.get("pu", _pushers))
	_receding = bool(w.get("rc", _receding))


func describe_lines() -> PackedStringArray:
	var out := super()
	out.append(
		"    %.1f of %.1f (%.0f%%) level=%d pushers=%d%s%s floor=%.1f"
			% [
				distance, _total, progress() * 100.0, speed_level, _pushers,
				" BLOCKED" if _blocked else "",
				" RECEDING" if _receding else "",
				floor_distance,
			]
	)
	return out
