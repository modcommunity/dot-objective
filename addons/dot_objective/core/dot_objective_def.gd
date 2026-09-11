@tool
class_name DotObjectiveDef
extends Resource

## What a round is about, as a document a server can check without loading anything.
##
## Same rule as [DotItem], [DotNpcDef] and [DotPropDef]: a definition is data, it
## validates against a schema before anything is built from it, and nothing in it
## names a scene. A server can therefore answer "is this map's objective layout legal"
## at boot, in a headless process, with no world loaded — which is the only moment
## anybody is watching.
##
## [b]Six kinds, and they are not arbitrary.[/b] They are what the round-based
## competitive shooters, the class-based objective shooters and the co-operative
## survival shooters between them ship, reduced to the smallest set that still tells
## the three of them apart:
##
## [codeblock]
## CAPTURE   a control point                cp_, koth_, dod_, dom_
## BOMB      plant it, defuse it            de_
## PAYLOAD   a cart pushed along a path     pl_, plr_
## FLAG      carry theirs to yours          ctf_
## RESCUE    escort somebody out            cs_, and every co-op finale
## HOLDOUT   own it, or survive, for N      koth_'s clock, and a finale's radio
## [/codeblock]
##
## A game with none of these is a deathmatch, which is what [DotMatch] alone already
## does. A game with two of them at once is a mode; that is [DotObjectiveSet]'s job,
## not this one's.

enum Kind {
	CAPTURE,
	BOMB,
	PAYLOAD,
	FLAG,
	RESCUE,
	HOLDOUT,
}

@export var id: StringName = &""

@export var kind: Kind = Kind.CAPTURE

## What a HUD calls it. "A", "Second", "The cart".
@export var display_name: String = ""

## A one-or-two character label, for a map overview that has no room for a name.
@export var label: String = ""

## Where it is. See [DotObjectiveArea] — no geometry, and 2D is the XZ plane.
@export var area: DotObjectiveArea = null

@export_group("Ownership")

## Who holds it when a round starts. Zero is neutral, and team ids start at 1 —
## dot-match's convention, and this addon does not import dot-match to learn it.
@export_range(0, 32, 1) var initial_team: int = 0

## Teams allowed to take it at all. Empty means every team.
##
## This is the difference between a control point and a bomb site: a bomb site only
## one side may plant in is the same object with one team named here.
@export var capturable_by: PackedInt32Array = PackedInt32Array()

## Points that a team must already own before it may act on this one.
##
## Keyed by team id, holding objective ids. This is the class-based objective shooters'
## previous-point link, and it is what makes a five-point map a tug of war
## rather than a race to the enemy's last point: red may only capture the middle while
## it owns its own second, so a lost point is a point you have to walk back to.
##
## [b]Stored as a Dictionary of Arrays and returned by value.[/b] A [Dictionary] is a
## reference in GDScript and this family has shipped that bug five times — a scoped
## board and its template ending up one object, a zone payload shared between two
## zones. [method requires_owned_for] duplicates.
@export var requires_owned: Dictionary = {}

@export_group("Scoring")

## Points handed to the team that completes it.
@export_range(0, 1000, 1) var score_points: int = 1

## Points handed to the player who completed it, on top of the team's.
@export_range(0, 1000, 1) var player_points: int = 0

## Completing it ends the round.
##
## Off for a control point in a five-point map and on for the last one, which is the
## whole difference between them.
@export var wins_round: bool = false

@export_group("Capture", "capture_")

## Ticks to take it with the minimum number of cappers.
##
## [b]Ticks, not seconds, everywhere in this addon.[/b] dot-timer's lesson: a float
## accumulator drifts, and a value in seconds on a server that runs at 64 and a client
## that runs at 128 is two different numbers for one thing. The rate comes from
## [code]Engine.physics_ticks_per_second[/code] at the edges and never from an export.
@export_range(1, 100000, 1) var capture_ticks: int = 480

## Cappers needed before a capture will start at all.
@export_range(1, 32, 1) var capture_required_to_start: int = 1

## Cappers the capture time is quoted for. More than this is faster; see
## [DotObjectiveCapture] for the diminishing-returns curve, which is the shipped one.
@export_range(1, 32, 1) var capture_required: int = 1

## Whether more cappers capture faster.
##
## On is the class-based objective shooters; off is the wartime objective shooters,
## where a point needs exactly N players and a sixth does nothing. Off also makes the
## point a [b]place a team must hold[/b] rather than a race, which is a different game.
@export var capture_scales_with_players: bool = true

@export_group("Bomb", "bomb_")

## Ticks the planter must stand still for.
@export_range(1, 100000, 1) var bomb_plant_ticks: int = 192

## Ticks from armed to detonation. The genre's is 45 seconds.
@export_range(1, 1000000, 1) var bomb_fuse_ticks: int = 2880

## Ticks to defuse bare-handed.
@export_range(1, 100000, 1) var bomb_defuse_ticks: int = 640

## Ticks to defuse with a kit. The genre's five against ten.
@export_range(1, 100000, 1) var bomb_defuse_kit_ticks: int = 320

## How close a defuser must be to the planted bomb.
@export_range(0.1, 100.0, 0.1, "or_greater") var bomb_defuse_radius: float = 2.0

## How close somebody must be to pick a dropped bomb up.
@export_range(0.1, 100.0, 0.1, "or_greater") var bomb_pickup_radius: float = 1.5

@export_group("Payload", "payload_")

## The path, in order. The cart starts at the first point and wins at the last.
@export var payload_path: PackedVector3Array = PackedVector3Array()

## Per-segment gradient: 0 level, 1 uphill, -1 downhill. Shorter than the path by one.
##
## An entry per segment rather than per node, because a gradient is a property of the
## track between two points and not of a point. A short list is padded with level.
@export var payload_gradient: PackedInt32Array = PackedInt32Array()

## Distances along the path at which the cart may no longer roll back.
@export var payload_checkpoints: PackedFloat32Array = PackedFloat32Array()

## Units per tick at full push.
@export_range(0.0001, 100.0, 0.0001, "or_greater") var payload_speed: float = 0.03

## How close a pusher must be to the cart.
@export_range(0.1, 100.0, 0.1, "or_greater") var payload_push_radius: float = 3.0

## Ticks with nobody pushing before the cart starts rolling back to the last
## checkpoint. The class-based objective shooters' thirty seconds; five in overtime.
@export_range(0, 1000000, 1) var payload_recede_ticks: int = 1920

@export_group("Flag", "flag_")

## Where carrying it to scores. Falls back to [member area] when unset, which is the
## symmetric case: a flag captured where it stands is a king-of-the-hill flag.
@export var flag_capture_area: DotObjectiveArea = null

## Ticks a dropped flag waits before going home by itself.
@export_range(0, 1000000, 1) var flag_return_ticks: int = 960

## A team-mate touching their own dropped flag sends it home immediately.
##
## On is the round-based-shooter style and off is the class-based one, where a dropped
## flag is a timer both teams play around. It changes the game more than it looks.
@export var flag_touch_returns: bool = true

## The flag must be at home before a carrier may capture with the enemy's.
##
## The rule that stops both teams scoring at once in a stalemate, and the reason a
## defended flag is worth defending.
@export var flag_requires_own_at_home: bool = false

## How close somebody must be to take or return it.
@export_range(0.1, 100.0, 0.1, "or_greater") var flag_touch_radius: float = 1.5

@export_group("Rescue", "rescue_")

## Ids of the things to be escorted. Hostages, survivors, a scientist.
@export var rescue_followers: Array[StringName] = []

## Where they start. One per follower; a short list repeats the last entry.
@export var rescue_starts: PackedVector3Array = PackedVector3Array()

## Where they have to end up.
@export var rescue_area: DotObjectiveArea = null

## How close a rescuer must be to pick one up.
@export_range(0.1, 100.0, 0.1, "or_greater") var rescue_touch_radius: float = 2.0

## How far behind its rescuer a follower trails. Its position is derived, not
## simulated: this addon does not own a navigation graph and must not pretend to.
@export_range(0.0, 100.0, 0.1, "or_greater") var rescue_follow_distance: float = 2.0

## How many have to arrive. Zero means all of them.
@export_range(0, 64, 1) var rescue_required: int = 0

@export_group("Holdout", "holdout_")

## Ticks a team must hold it for.
@export_range(1, 10000000, 1) var holdout_ticks: int = 10800

## Only count while somebody is inside the area.
##
## On is a finale's radio: the clock runs while you are on the roof and stops when the
## last of you is dragged off it. Off is king of the hill's clock, which runs on
## ownership and does not care where anybody is standing.
@export var holdout_requires_presence: bool = false

## Another objective whose owner drives this clock. For king of the hill, where the
## point is a [constant Kind.CAPTURE] and the clock is this.
@export var holdout_owner_of: StringName = &""

## Both teams' clocks run at once rather than only the owner's.
@export var holdout_all_teams: bool = false


static func capture(
	p_id: StringName, p_area: DotObjectiveArea, p_ticks: int = 480
) -> DotObjectiveDef:
	var d := DotObjectiveDef.new()
	d.id = p_id
	d.kind = Kind.CAPTURE
	d.display_name = String(p_id)
	d.area = p_area
	d.capture_ticks = p_ticks
	return d


static func bomb(p_id: StringName, p_site: DotObjectiveArea) -> DotObjectiveDef:
	var d := DotObjectiveDef.new()
	d.id = p_id
	d.kind = Kind.BOMB
	d.display_name = String(p_id)
	d.area = p_site
	d.wins_round = true
	return d


static func payload(
	p_id: StringName, p_path: PackedVector3Array
) -> DotObjectiveDef:
	var d := DotObjectiveDef.new()
	d.id = p_id
	d.kind = Kind.PAYLOAD
	d.display_name = String(p_id)
	d.payload_path = p_path
	d.area = DotObjectiveArea.sphere(
		p_path[0] if p_path.size() > 0 else Vector3.ZERO, 3.0
	)
	d.wins_round = true
	return d


static func flag(
	p_id: StringName, p_home: DotObjectiveArea, p_team: int
) -> DotObjectiveDef:
	var d := DotObjectiveDef.new()
	d.id = p_id
	d.kind = Kind.FLAG
	d.display_name = String(p_id)
	d.area = p_home
	d.initial_team = p_team
	return d


static func rescue(
	p_id: StringName, p_starts: PackedVector3Array, p_to: DotObjectiveArea
) -> DotObjectiveDef:
	var d := DotObjectiveDef.new()
	d.id = p_id
	d.kind = Kind.RESCUE
	d.display_name = String(p_id)
	d.rescue_starts = p_starts
	d.rescue_area = p_to
	d.area = p_to
	var names: Array[StringName] = []
	for i in range(p_starts.size()):
		names.append(StringName("%s_%d" % [p_id, i + 1]))
	d.rescue_followers = names
	d.wins_round = true
	return d


static func holdout(p_id: StringName, p_ticks: int) -> DotObjectiveDef:
	var d := DotObjectiveDef.new()
	d.id = p_id
	d.kind = Kind.HOLDOUT
	d.display_name = String(p_id)
	d.holdout_ticks = p_ticks
	d.area = DotObjectiveArea.everywhere()
	d.wins_round = true
	return d


## The ids this team must already own, by value.
func requires_owned_for(team: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var raw: Variant = requires_owned.get(team, null)
	if raw == null:
		return out
	for entry: Variant in (raw as Array):
		out.append(StringName(str(entry)))
	return out


func may_be_taken_by(team: int) -> bool:
	if capturable_by.is_empty():
		return team > 0
	return capturable_by.has(team)


## The gradient of the segment a distance falls in. 0 level, 1 up, -1 down.
func gradient_at(distance: float) -> int:
	if payload_path.size() < 2:
		return 0
	var travelled := 0.0
	for i in range(payload_path.size() - 1):
		var seg := payload_path[i].distance_to(payload_path[i + 1])
		if distance <= travelled + seg or i == payload_path.size() - 2:
			if i < payload_gradient.size():
				return signi(payload_gradient[i])
			return 0
		travelled += seg
	return 0


func path_length() -> float:
	var total := 0.0
	for i in range(payload_path.size() - 1):
		total += payload_path[i].distance_to(payload_path[i + 1])
	return total


## A point at a distance along the path, for a cart to be drawn at.
func point_at(distance: float) -> Vector3:
	if payload_path.is_empty():
		return Vector3.ZERO
	if payload_path.size() == 1:
		return payload_path[0]
	var left := maxf(distance, 0.0)
	for i in range(payload_path.size() - 1):
		var seg := payload_path[i].distance_to(payload_path[i + 1])
		if seg <= 0.0:
			continue
		if left <= seg:
			return payload_path[i].lerp(payload_path[i + 1], left / seg)
		left -= seg
	return payload_path[payload_path.size() - 1]


func validate() -> DotResult:
	if String(id).strip_edges() == "":
		return DotResult.fail(DotError.CODE_INVALID, "An objective needs an id.")

	if kind != Kind.PAYLOAD and kind != Kind.HOLDOUT and area == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Objective '%s' has no area, and a %s happens somewhere."
				% [id, Kind.keys()[kind]]
		)

	if area != null:
		var res := area.validate()
		if not res.ok:
			return res.wrap("objective '%s'" % id)

	if capture_required_to_start > capture_required and kind == Kind.CAPTURE:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Objective '%s' needs %d to start a capture it quotes for %d, so the "
				+ "capture can start and then never be at full rate."
			) % [id, capture_required_to_start, capture_required]
		)

	match kind:
		Kind.PAYLOAD:
			if payload_path.size() < 2:
				return DotResult.fail(
					DotError.CODE_INVALID,
					"Payload '%s' needs at least two path points." % id
				)
			if payload_speed <= 0.0:
				return DotResult.fail(
					DotError.CODE_INVALID, "Payload '%s' has no speed." % id
				)
			for d in payload_checkpoints:
				if d < 0.0 or d > path_length():
					return DotResult.fail(
						DotError.CODE_INVALID,
						(
							"Payload '%s' has a checkpoint at %.1f, and its path is "
							+ "%.1f long. A checkpoint past the end can never latch."
						) % [id, d, path_length()]
					)
		Kind.FLAG:
			if initial_team <= 0:
				return DotResult.fail(
					DotError.CODE_INVALID,
					(
						"Flag '%s' belongs to no team. A flag nobody owns is one "
						+ "nobody can steal."
					) % id
				)
		Kind.RESCUE:
			if rescue_followers.is_empty():
				return DotResult.fail(
					DotError.CODE_INVALID, "Rescue '%s' has nobody to rescue." % id
				)
			if rescue_area == null:
				return DotResult.fail(
					DotError.CODE_INVALID, "Rescue '%s' has nowhere to rescue to." % id
				)
			if rescue_required > rescue_followers.size():
				return DotResult.fail(
					DotError.CODE_INVALID,
					(
						"Rescue '%s' requires %d of %d followers, which can never be "
						+ "met."
					) % [id, rescue_required, rescue_followers.size()]
				)
		Kind.HOLDOUT:
			if holdout_ticks <= 0:
				return DotResult.fail(
					DotError.CODE_INVALID, "Holdout '%s' is over before it starts." % id
				)
		_:
			pass

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"id": String(id),
		"kind": Kind.keys()[kind],
		"name": display_name,
		"team": initial_team,
		"wins_round": wins_round,
		"area": area.describe() if area != null else {},
	}
