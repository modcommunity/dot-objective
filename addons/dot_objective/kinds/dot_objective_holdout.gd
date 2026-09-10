class_name DotObjectiveHoldout
extends DotObjective

## Hold it, or survive it, for a length of time.
##
## Two very different-looking modes are the same clock, which is why they are one kind:
##
## - [b]King of the hill.[/b] One point, two clocks; the owning team's runs down and
##   the other team's is frozen where it stopped. Set
##   [member DotObjectiveDef.holdout_owner_of] to a [DotObjectiveCapture]'s id and this
##   reads its owner every tick. The point is the capture; the clock is this.
## - [b]A finale.[/b] Turn on the radio and stay alive for four minutes with something
##   coming at you. Set [member DotObjectiveDef.holdout_requires_presence] and the
##   clock only counts while somebody is still standing in the area, so being dragged
##   off the roof stops it rather than losing it.
##
## [member DotObjective.progress] is the leading team's fraction of the way there.
##
## [b]A frozen clock keeps its value.[/b] That is the whole of king of the hill and it
## is the thing a naive implementation gets wrong: resetting the other team's clock on
## a capture makes every fight for the point worth the same, and the mode's entire
## tension is that the team at four seconds only has to hold it once more.

## team id -> ticks still to hold.
var clocks: Dictionary = {}

## When [member DotObjectiveDef.holdout_owner_of] is set, the objective it reads.
## Wired by [DotObjectiveSet] at build time, because an objective does not get to go
## looking for another one.
var linked: DotObjective = null

var _last_fraction: float = -1.0
var _leader: int = 0


func _init(p_def: DotObjectiveDef = null) -> void:
	super(p_def)
	if p_def != null and p_def.initial_team > 0:
		clocks[p_def.initial_team] = p_def.holdout_ticks


## Ticks left for a team. The full duration for one that has never held it.
func remaining_for(team: int) -> int:
	if not clocks.has(team):
		return def.holdout_ticks if def != null else 0
	return int(clocks[team])


## Which team is closest to winning it.
func leader() -> int:
	return _leader


func progress() -> float:
	if def == null or def.holdout_ticks <= 0:
		return 0.0
	var best := 0.0
	var who := 0
	for team: Variant in clocks.keys():
		var left := float(clocks[team])
		var f := clampf(1.0 - (left / float(def.holdout_ticks)), 0.0, 1.0)
		if f > best:
			best = f
			who = int(team)
	_leader = who
	return best


func progressing_team() -> int:
	var _f := progress()
	return _leader


func _reset() -> void:
	clocks.clear()
	if def != null and def.initial_team > 0:
		clocks[def.initial_team] = def.holdout_ticks
	_leader = 0
	_last_fraction = -1.0


func _advance(presence: DotObjectivePresence, _rules: DotObjectiveRules) -> void:
	var running := _teams_running(presence)

	if running.is_empty():
		if phase == Phase.ACTIVE:
			phase = Phase.IDLE
			interrupted.emit(_leader, &"stopped")
		return

	if phase != Phase.ACTIVE:
		phase = Phase.ACTIVE
		started.emit(running[0], "")

	for team in running:
		var left := remaining_for(team) - 1
		clocks[team] = left
		if left <= 0:
			clocks[team] = 0
			var by := ""
			if def.area != null:
				by = presence.nearest(def.area.centre, 0.0, team)
			_complete(team, by)
			return

	_announce()


## Whose clocks run this tick.
func _teams_running(presence: DotObjectivePresence) -> PackedInt32Array:
	var out := PackedInt32Array()
	if locked:
		return out

	var owner := owner_team
	if def.holdout_owner_of != &"" and linked != null:
		owner = linked.owner_team

	if def.holdout_all_teams:
		var counts := presence.counts_in(def.area, def.capturable_by)
		var ids: Array = counts.keys()
		ids.sort()
		for team_id: Variant in ids:
			var c: DotObjectivePresence.Count = counts[team_id]
			if c.cappers > 0:
				out.append(int(team_id))
		return out

	if owner <= 0:
		return out
	if not def.holdout_requires_presence:
		out.append(owner)
		return out

	var here := presence.counts_in(def.area, PackedInt32Array([owner]))
	var mine: DotObjectivePresence.Count = here.get(owner, null)
	if mine != null and mine.cappers > 0:
		out.append(owner)
	return out


func _announce() -> void:
	var f := progress()
	if absf(f - _last_fraction) < 0.002:
		return
	_last_fraction = f
	progressed.emit(f, _leader)


func _to_wire(out: Dictionary) -> void:
	var packed: Dictionary = {}
	for team: Variant in clocks.keys():
		packed[str(team)] = int(clocks[team])
	out["cl"] = packed


func _apply_wire(w: Dictionary) -> void:
	var packed: Dictionary = w.get("cl", {})
	clocks.clear()
	for team: Variant in packed.keys():
		clocks[int(str(team))] = int(packed[team])


func describe_lines() -> PackedStringArray:
	var out := super()
	var ids: Array = clocks.keys()
	ids.sort()
	for team: Variant in ids:
		out.append("      team %d: %d ticks left" % [int(team), int(clocks[team])])
	return out
