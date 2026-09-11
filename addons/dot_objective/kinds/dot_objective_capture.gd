class_name DotObjectiveCapture
extends DotObjective

## A control point. [member DotObjective.progress] is how far the current capture is.
##
## This is the long-standing capture-area think rewritten in ticks — the shape of it,
## and every one of its decisions, because between the class-based objective shooters,
## the wartime ones and the domination modes there are twenty years of play behind
## them:
##
## - [b]More cappers capture faster, with diminishing returns.[/b] The nth player adds
##   [code]1/n[/code] of a player's worth, so the rate for n is the harmonic number
##   H(n) = 1 + 1/2 + 1/3 … A second player is worth half a player, and a fifth is
##   worth a fifth, which is what stops a point being a headcount.
## - [b]Two teams at once pauses it[/b] (or breaks it — see
##   [member DotObjectiveRules.block_style]), and the defender who did it gets credit
##   only if the capture was at least half done.
## - [b]An abandoned capture decays[/b] rather than snapping back, over
##   [member DotObjectiveRules.deteriorate_ticks], six times faster in overtime.
## - [b]A neutral point being taken by the wrong team runs backwards[/b], which is what
##   makes a contested neutral point a tug of war rather than a coin flip.
##
## [b]One deliberate departure from the original, and it is the exported field.[/b] Its
## total capture time is [code]capTime * 2 * requiredPlayers[/code], so a point whose
## map file says ten seconds takes twenty with one player and twenty-seven with two
## required. That is a trap in a field a mapper reads: the number in the document is
## not the number on the clock. Here [member DotObjectiveDef.capture_ticks] means what
## it says — the time with [member DotObjectiveDef.capture_required] cappers on it —
## and the total is scaled by H(required) so the curve above is unchanged. The suite
## checks both halves of that: the quoted count takes the quoted time, and each extra
## capper is worth 1/n.

## Ticks of capture still to do. Counted down, so 0 is captured.
var _remaining: float = 0.0

## Total for this attempt. Depends on the capping team's required count.
var _total: float = 1.0

var _capturing_team: int = 0

## Bumped every time a capture starts, so a blocker cannot be credited twice for one
## attempt. The original keeps the same counter for the same reason.
var _attempt: int = 0

var _blocked: bool = false

## key -> the attempt number they were last credited a block for.
var _block_credit: Dictionary = {}

## No capture may start before this tick. Zero when there is no recovery period.
var _recovery_until: int = 0

var _last_fraction: float = -1.0


func _init(p_def: DotObjectiveDef = null) -> void:
	super(p_def)
	_total = float(maxi(p_def.capture_ticks, 1)) if p_def != null else 1.0
	_remaining = _total


## The harmonic number H(n) — the rate n cappers make progress at, in players.
##
## Static and public because it is the whole curve: a game that wants to show "this
## point will take 12 seconds with the three of you" asks here rather than guessing.
static func rate_for(cappers: int) -> float:
	if cappers <= 0:
		return 0.0
	var sum := 0.0
	for i in range(1, cappers + 1):
		sum += 1.0 / float(i)
	return sum


func progress() -> float:
	if _capturing_team <= 0:
		return 0.0
	return clampf(1.0 - (_remaining / maxf(_total, 1.0)), 0.0, 1.0)


func progressing_team() -> int:
	return _capturing_team


func is_blocked() -> bool:
	return _blocked


func capturing_team() -> int:
	return _capturing_team


## Ticks this capture would take from scratch, for a given number of cappers.
func ticks_for(cappers: int, team: int = 0) -> float:
	var required := def.capture_required if def != null else 1
	var quoted := float(maxi(def.capture_ticks, 1)) if def != null else 1.0
	if def != null and not def.capture_scales_with_players:
		return quoted
	var total := quoted * rate_for(required)
	var rate := rate_for(cappers)
	if rate <= 0.0:
		return INF
	var _unused := team
	return total / rate


func _reset() -> void:
	_capturing_team = 0
	_remaining = _total
	_blocked = false
	_block_credit.clear()
	_recovery_until = 0
	_last_fraction = -1.0


func _on_not_live(_presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	# A capture made while the round was not live is one nobody was allowed to make,
	# and freeze time is exactly when everybody is standing on everything.
	if _capturing_team > 0:
		_break(&"not_live")


func _advance(presence: DotObjectivePresence, rules: DotObjectiveRules) -> void:
	var allowed := def.capturable_by
	var counts := presence.counts_in(def.area, allowed)

	# Who is here, and is anybody contesting? A team with only blockers in it counts
	# as present for contest purposes and cannot start anything — the invulnerable
	# player, who stops a capture without helping one.
	var teams_present := 0
	var team_in_zone := 0
	for team_id: Variant in counts.keys():
		var c: DotObjectivePresence.Count = counts[team_id]
		if c.cappers > 0 or c.blockers > 0:
			teams_present += 1
			team_in_zone = int(team_id)
	if teams_present != 1:
		team_in_zone = 0

	if _capturing_team <= 0:
		_maybe_start(counts, rules, teams_present)
		_announce()
		return

	var contested := teams_present > 1

	if contested:
		_handle_contest(counts, rules)
		_announce()
		return

	if _blocked:
		_blocked = false
		phase = Phase.ACTIVE

	if team_in_zone == _capturing_team:
		var count: DotObjectivePresence.Count = counts[team_in_zone]
		_remaining -= rate_for(count.cappers)
	elif owner_team == 0 and team_in_zone > 0:
		# A neutral point, and the team in the zone is not the one capturing it. The
		# original runs the clock backwards rather than breaking, which is what makes a
		# contested neutral point a tug of war: whoever is standing there is winning.
		var other: DotObjectivePresence.Count = counts[team_in_zone]
		_remaining += rate_for(other.cappers)
	else:
		_remaining += rules.decay_per_tick(_total)

	if _remaining <= 0.0:
		var by := ""
		if counts.has(_capturing_team):
			by = (counts[_capturing_team] as DotObjectivePresence.Count).first
		var team := _capturing_team
		_capturing_team = 0
		_remaining = _total
		owner_team = team
		_last_fraction = -1.0
		if def.wins_round:
			_complete(team, by)
		else:
			phase = Phase.IDLE
			completed.emit(team, by)
		return

	if _remaining >= _total:
		_break(&"decayed", rules.capture_recovery_ticks)

	_announce()


func _maybe_start(
	counts: Dictionary, rules: DotObjectiveRules, teams_present: int
) -> void:
	if locked:
		return

	# A capture does not START contested. The original does not check this — it starts one
	# and breaks it on the next think — and the result is a start and an interrupt
	# every tick for as long as two teams stand on a point, which at 64 Hz is 128
	# signals a second and a kill feed full of nothing. It also makes block_style 0
	# unobservable, because the capture is always either just-started or just-broken.
	if teams_present > 1:
		return
	if _recovery_until > 0 and tick < _recovery_until:
		return

	var ids: Array = counts.keys()
	ids.sort()
	for team_id: Variant in ids:
		var team := int(team_id)
		if team == owner_team:
			continue
		if not team_allowed(team):
			continue

		var c: DotObjectivePresence.Count = counts[team]
		if c.cappers <= 0:
			continue
		if c.cappers < def.capture_required_to_start:
			continue
		if not def.capture_scales_with_players and c.cappers < def.capture_required:
			continue

		_capturing_team = team
		_attempt += 1
		_total = _total_for(team)
		_remaining = _total
		_blocked = false
		phase = Phase.ACTIVE
		_last_fraction = -1.0
		var _unused := rules
		started.emit(team, c.first)
		return


func _total_for(_team: int) -> float:
	var quoted := float(maxi(def.capture_ticks, 1))
	if not def.capture_scales_with_players:
		return quoted
	return quoted * rate_for(def.capture_required)


func _handle_contest(counts: Dictionary, rules: DotObjectiveRules) -> void:
	if not _blocked:
		_blocked = true
		phase = Phase.CONTESTED
		interrupted.emit(_capturing_team, &"contested")

	# Credit the block, once per attempt per player, and only if the attackers had got
	# somewhere. Standing on your own point as the round starts is not a block, and
	# paying for it teaches players to stand on their own point.
	if progress() >= rules.block_credit_fraction:
		var ids: Array = counts.keys()
		ids.sort()
		for team_id: Variant in ids:
			var team := int(team_id)
			if team == _capturing_team:
				continue
			var c: DotObjectivePresence.Count = counts[team]
			if c.first == "":
				continue
			if int(_block_credit.get(c.first, -1)) == _attempt:
				continue
			_block_credit[c.first] = _attempt
			blocked.emit(c.first, team)
			break

	if rules.block_style == 0:
		_break(&"blocked", rules.capture_recovery_ticks)


## End the current capture. [param recovery] is the period a failed push is made to
## wait, and is zero for a break that is not one.
##
## [b]not_live does not start a recovery period.[/b] The recovery is there to punish a
## push that was stopped by the other team; a round going non-live is freeze time or a
## round end, which is not a failed push and would otherwise delay the first capture of
## the next round by the whole period.
func _break(reason: StringName, recovery: int = 0) -> void:
	var team := _capturing_team
	_capturing_team = 0
	_remaining = _total
	_blocked = false
	phase = Phase.IDLE
	_last_fraction = -1.0
	if recovery > 0:
		_recovery_until = tick + recovery
	if team > 0:
		interrupted.emit(team, reason)


func _announce() -> void:
	var f := progress()
	if absf(f - _last_fraction) < 0.005:
		return
	_last_fraction = f
	progressed.emit(f, _capturing_team)


func _to_wire(out: Dictionary) -> void:
	out["c"] = _capturing_team
	out["b"] = _blocked
	out["r"] = _remaining
	out["tt"] = _total


func _apply_wire(w: Dictionary) -> void:
	_capturing_team = int(w.get("c", _capturing_team))
	_blocked = bool(w.get("b", _blocked))
	_remaining = float(w.get("r", _remaining))
	_total = float(w.get("tt", _total))


func describe_lines() -> PackedStringArray:
	var out := super()
	if _capturing_team > 0:
		out.append(
			"    capturing by team %d, %.0f%%%s, %d ticks left of %d"
				% [
					_capturing_team,
					progress() * 100.0,
					" (BLOCKED)" if _blocked else "",
					int(_remaining),
					int(_total),
				]
		)
	return out
