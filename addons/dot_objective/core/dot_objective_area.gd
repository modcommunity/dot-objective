@tool
class_name DotObjectiveArea
extends Resource

## Where an objective happens, without any geometry.
##
## An objective is a rule about a place, and the place is the one part of it a mapper
## draws. Every other addon in this family that needed one of these reached for a
## physics body and then could not run headless; dot-timer's zones are the exception
## and they are the shape that survived. So this is a centre, a size and a test —
## nothing is added to the scene tree, nothing collides, and a suite with no world in
## it can drive a whole capture.
##
## [b]A 2D world is the XZ plane.[/b] dot-npc settled that and everything downstream of
## it — senses, steering, navigation — ran unchanged as a result: a 3D distance on a
## plane where one component never moves is the 2D distance. [method of_2d] builds the
## same area from a [Vector2], and [method point_2d] converts back for a caller holding
## one.
##
## [b]A capture zone is a cylinder, not a sphere.[/b] The difference is the balcony: a
## player standing eight metres above the point is inside a sphere of radius ten and
## has no business capturing anything. Source's trigger is a brush and its height is
## deliberate; a sphere is the shape that quietly rewards the wrong player.

enum Shape {
	SPHERE,      ## A ball. For a pickup radius, where height genuinely does not matter.
	CYLINDER,    ## A disc with a height. What a capture zone actually is.
	BOX,         ## Axis-aligned. What a mapper's brush usually is.
	EVERYWHERE,  ## No test at all. For an objective the whole map is part of.
}

@export var shape: Shape = Shape.CYLINDER

@export var centre: Vector3 = Vector3.ZERO

## Radius for [constant Shape.SPHERE] and [constant Shape.CYLINDER].
@export_range(0.0, 4096.0, 0.01, "or_greater") var radius: float = 4.0

## Half the height of a [constant Shape.CYLINDER], measured from [member centre].
##
## Generous by default and deliberately so: a capture zone that a jumping player
## leaves is one that reports a broken capture every time somebody jumps on it, and
## "it stopped capturing and I never moved" is the bug report you get.
@export_range(0.0, 4096.0, 0.01, "or_greater") var half_height: float = 2.5

## Half extents for [constant Shape.BOX].
@export var half_extents: Vector3 = Vector3(4.0, 2.5, 4.0)


static func sphere(p_centre: Vector3, p_radius: float) -> DotObjectiveArea:
	var a := DotObjectiveArea.new()
	a.shape = Shape.SPHERE
	a.centre = p_centre
	a.radius = p_radius
	return a


static func cylinder(
	p_centre: Vector3, p_radius: float, p_half_height: float = 2.5
) -> DotObjectiveArea:
	var a := DotObjectiveArea.new()
	a.shape = Shape.CYLINDER
	a.centre = p_centre
	a.radius = p_radius
	a.half_height = p_half_height
	return a


static func box(p_centre: Vector3, p_half_extents: Vector3) -> DotObjectiveArea:
	var a := DotObjectiveArea.new()
	a.shape = Shape.BOX
	a.centre = p_centre
	a.half_extents = p_half_extents
	return a


static func everywhere() -> DotObjectiveArea:
	var a := DotObjectiveArea.new()
	a.shape = Shape.EVERYWHERE
	return a


## The same area in a 2D world, which is the XZ plane.
##
## The height test is switched off rather than made huge, because "huge" is a number
## somebody eventually exceeds: a 2D game with a camera height, a parallax layer or a
## y of anything but zero would silently stop capturing.
static func of_2d(p_centre: Vector2, p_radius: float) -> DotObjectiveArea:
	var a := DotObjectiveArea.new()
	a.shape = Shape.SPHERE
	a.centre = Vector3(p_centre.x, 0.0, p_centre.y)
	a.radius = p_radius
	return a


## A [Vector2] in the XZ plane, for a 2D caller.
static func point_2d(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


func centre_2d() -> Vector2:
	return Vector2(centre.x, centre.z)


func contains(point: Vector3) -> bool:
	match shape:
		Shape.EVERYWHERE:
			return true
		Shape.SPHERE:
			return point.distance_squared_to(centre) <= radius * radius
		Shape.CYLINDER:
			if absf(point.y - centre.y) > half_height:
				return false
			var dx := point.x - centre.x
			var dz := point.z - centre.z
			return dx * dx + dz * dz <= radius * radius
		Shape.BOX:
			var d := point - centre
			return (
				absf(d.x) <= half_extents.x
				and absf(d.y) <= half_extents.y
				and absf(d.z) <= half_extents.z
			)
	return false


func contains_2d(point: Vector2) -> bool:
	return contains(point_2d(point))


## Moved to a new centre, keeping every other field.
##
## A payload's push area follows the cart, and a caller that mutated [member centre]
## in place would be mutating a [Resource] the definition still holds — the aliasing
## this family has now found in five places. This returns a new one.
func moved_to(p_centre: Vector3) -> DotObjectiveArea:
	var a := duplicate() as DotObjectiveArea
	a.centre = p_centre
	return a


func validate() -> DotResult:
	match shape:
		Shape.SPHERE, Shape.CYLINDER:
			if radius <= 0.0:
				return DotResult.fail(
					DotError.CODE_INVALID, "An area with no radius contains nobody."
				)
		Shape.BOX:
			if half_extents.x <= 0.0 or half_extents.y <= 0.0 or half_extents.z <= 0.0:
				return DotResult.fail(
					DotError.CODE_INVALID, "A box with a zero extent contains nobody."
				)
		_:
			pass
	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"shape": Shape.keys()[shape],
		"centre": centre,
		"radius": radius,
		"half_height": half_height,
		"half_extents": half_extents,
	}


func _to_string() -> String:
	return "DotObjectiveArea(%s @ %v)" % [Shape.keys()[shape], centre]
