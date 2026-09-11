extends Node

## Exercises dot-objective with no other addon, no world and no transport.
##
## Every check here drives the objectives out of a dictionary of positions, which is
## exactly the seam a real game fills with its own roster — so what is being tested is
## what this addon promises: that a capture takes the time it says with the number of
## players it says, that the second capper is worth half a player and not a whole one,
## that a defuse a dead player is running stops, that a cart on a hill does not need
## anybody, and that a five-point map is a tug of war rather than a race.
##
## [codeblock]
## godot --headless --path . res://examples/objective_selftest.tscn
## [/codeblock]

const SECTIONS := 20

## 64 a second, which is what every "ticks" number below is quoted at.
const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0


## The game, in the smallest form that still answers every question a presence asks.
class World extends RefCounted:
	var positions: Dictionary = {}
	var teams: Dictionary = {}
	var alive: Dictionary = {}
	var values: Dictionary = {}
	var can_capture: Dictionary = {}

	func add(key: String, team: int, at: Vector3 = Vector3.ZERO) -> void:
		positions[key] = at
		teams[key] = team
		alive[key] = true

	func move(key: String, to: Vector3) -> void:
		positions[key] = to

	func kill(key: String) -> void:
		alive[key] = false

	func keys() -> PackedStringArray:
		var out := PackedStringArray()
		var ids: Array = positions.keys()
		ids.sort()
		for id: Variant in ids:
			out.append(str(id))
		return out

	func presence() -> DotObjectivePresence:
		var p := DotObjectivePresence.of(
			keys,
			func(key: String) -> Vector3: return positions.get(key, Vector3.ZERO),
			func(key: String) -> int: return int(teams.get(key, 0)),
			func(key: String) -> bool: return bool(alive.get(key, false))
		)
		p.capture_value_fn = func(key: String) -> int:
			return int(values.get(key, 1))
		p.may_capture_fn = func(key: String) -> bool:
			return bool(can_capture.get(key, true))
		return p


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-objective self-test")
	_line("")

	_test_area()
	_test_def_validation()
	_test_rules()
	_test_presence()
	_test_capture_basic()
	_test_capture_curve()
	_test_capture_blocking()
	_test_capture_decay()
	_test_capture_block_credit()
	_test_capture_recovery()
	_test_bomb_plant()
	_test_bomb_defuse()
	_test_bomb_carrying()
	_test_payload()
	_test_flag()
	_test_rescue()
	_test_holdout()
	_test_set_gating()
	_test_manager()
	_test_two_dimensions()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	# A script error inside a test aborts THAT test, not the run — a suite can report
	# "all passed" while quietly running fewer checks than it has.
	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


# --- Areas -----------------------------------------------------------------

func _test_area() -> void:
	_section("areas")

	var sphere := DotObjectiveArea.sphere(Vector3.ZERO, 5.0)
	_check(sphere.contains(Vector3(4.0, 0.0, 0.0)), "a sphere contains a near point")
	_check(
		sphere.contains(Vector3(0.0, 4.9, 0.0)),
		"and contains one directly above, which is what a sphere is for"
	)
	_check(not sphere.contains(Vector3(6.0, 0.0, 0.0)), "and not a far one")

	var cyl := DotObjectiveArea.cylinder(Vector3.ZERO, 5.0, 2.0)
	_check(cyl.contains(Vector3(4.0, 1.5, 0.0)), "a cylinder contains a near point")
	_check(
		not cyl.contains(Vector3(0.0, 8.0, 0.0)),
		"and refuses the player on the balcony, which is the whole reason it is not a sphere"
	)

	var box := DotObjectiveArea.box(Vector3(10, 0, 10), Vector3(2, 2, 2))
	_check(box.contains(Vector3(11, 1, 9)), "a box contains a point inside it")
	_check(not box.contains(Vector3(13, 0, 10)), "and not one outside it")

	_check(
		DotObjectiveArea.everywhere().contains(Vector3(1e6, -1e6, 0.0)),
		"everywhere contains everywhere"
	)

	var flat := DotObjectiveArea.of_2d(Vector2(3.0, 4.0), 2.0)
	_check(
		flat.contains_2d(Vector2(4.0, 4.0)),
		"a 2D area contains a 2D point, on the XZ plane dot-npc settled on"
	)
	_check(
		flat.centre_2d() == Vector2(3.0, 4.0),
		"and gives the centre back as a Vector2"
	)

	var moved := sphere.moved_to(Vector3(9, 0, 9))
	_check(
		sphere.centre == Vector3.ZERO and moved.centre == Vector3(9, 0, 9),
		"moved_to returns a new area rather than mutating the definition's"
	)


# --- Definitions -----------------------------------------------------------

func _test_def_validation() -> void:
	_section("definition validation")

	var ok := DotObjectiveDef.capture(&"mid", DotObjectiveArea.cylinder(Vector3.ZERO, 4.0))
	_check(ok.validate().ok, "a well-formed capture validates")

	var no_id := DotObjectiveDef.new()
	_check(not no_id.validate().ok, "one with no id does not")

	var no_area := DotObjectiveDef.new()
	no_area.id = &"x"
	_check(
		not no_area.validate().ok,
		"nor does one with nowhere to happen"
	)

	var bad_start := DotObjectiveDef.capture(&"a", DotObjectiveArea.sphere(Vector3.ZERO, 3.0))
	bad_start.capture_required_to_start = 3
	bad_start.capture_required = 1
	_check(
		not bad_start.validate().ok,
		"a point needing more to start than it is quoted for is refused"
	)

	var payload := DotObjectiveDef.payload(
		&"cart", PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)])
	)
	_check(payload.validate().ok, "a two-point payload validates")
	_check(is_equal_approx(payload.path_length(), 10.0), "and knows its length")

	payload.payload_checkpoints = PackedFloat32Array([50.0])
	_check(
		not payload.validate().ok,
		"a checkpoint past the end of the path is refused, because it can never latch"
	)

	var short_path := DotObjectiveDef.payload(&"c", PackedVector3Array([Vector3.ZERO]))
	_check(not short_path.validate().ok, "a one-point path is not a path")

	var flag := DotObjectiveDef.flag(&"f", DotObjectiveArea.sphere(Vector3.ZERO, 2.0), 0)
	_check(
		not flag.validate().ok,
		"a flag belonging to nobody is refused: nobody can steal it"
	)

	var rescue := DotObjectiveDef.rescue(
		&"h",
		PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)]),
		DotObjectiveArea.sphere(Vector3(20, 0, 0), 3.0)
	)
	_check(rescue.validate().ok, "a rescue with two followers validates")
	rescue.rescue_required = 5
	_check(
		not rescue.validate().ok,
		"and requiring more than exist is refused rather than being unwinnable"
	)

	var path := DotObjectiveDef.payload(
		&"p", PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)])
	)
	_check(
		path.point_at(15.0).is_equal_approx(Vector3(10, 0, 5)),
		"a distance along a path resolves to a point on the right segment"
	)
	path.payload_gradient = PackedInt32Array([0, -1])
	_check(path.gradient_at(15.0) == -1, "and the gradient of that segment")
	_check(path.gradient_at(2.0) == 0, "and of the first one")

	var duped := DotObjectiveDef.capture(&"g", DotObjectiveArea.sphere(Vector3.ZERO, 2.0))
	duped.requires_owned = {1: [&"first"]}
	var got := duped.requires_owned_for(1)
	got.append(&"injected")
	_check(
		duped.requires_owned_for(1).size() == 1,
		"requires_owned_for hands out a copy — a Dictionary is a reference and this "
		+ "family has shipped that bug five times"
	)


# --- Rules -----------------------------------------------------------------

func _test_rules() -> void:
	_section("rules")

	var rules := DotObjectiveRules.new()
	_check(rules.validate().ok, "the defaults validate")
	_check(not rules.live, "and are not live, because warmup is when everybody stands on everything")

	_check(is_equal_approx(rules.payload_fraction(1), 0.55), "one pusher is 0.55 of full speed")
	_check(is_equal_approx(rules.payload_fraction(2), 0.77), "two is 0.77")
	_check(is_equal_approx(rules.payload_fraction(3), 1.0), "three is full")
	_check(is_equal_approx(rules.payload_fraction(9), 1.0), "and nine is still full")
	_check(rules.payload_fraction(0) == 0.0, "nobody is nothing")

	var normal := rules.decay_per_tick(1000.0)
	rules.overtime = true
	var over := rules.decay_per_tick(1000.0)
	_check(
		is_equal_approx(over, normal * rules.overtime_decay_multiplier),
		"overtime decays six times faster, which is what overtime is for"
	)
	rules.overtime = false

	rules.payload_speed_two = 0.2
	_check(
		not rules.validate().ok,
		"a second pusher that slows the cart is refused"
	)


# --- Presence --------------------------------------------------------------

func _test_presence() -> void:
	_section("presence")

	var empty := DotObjectivePresence.new()
	var res := empty.validate()
	_check(not res.ok, "a presence with no callables is refused")
	_check(
		res.error.message.contains("participants_fn"),
		"and says which one is missing, because an unset Callable answers zero rather "
		+ "than failing"
	)

	var world := World.new()
	world.add("a", 1, Vector3(0, 0, 0))
	world.add("b", 1, Vector3(1, 0, 0))
	world.add("c", 2, Vector3(0.5, 0, 0))
	world.add("far", 1, Vector3(100, 0, 0))
	world.kill("b")

	var p := world.presence()
	_check(p.validate().ok, "a wired one is accepted")

	var area := DotObjectiveArea.cylinder(Vector3.ZERO, 5.0, 3.0)
	var counts := p.counts_in(area)
	_check(counts.size() == 2, "two teams are in the zone")
	_check(
		(counts[1] as DotObjectivePresence.Count).cappers == 1,
		"a dead player in the zone counts for nothing, which is the oldest bug in this genre"
	)
	_check(
		(counts[2] as DotObjectivePresence.Count).cappers == 1,
		"and the other team has its one"
	)
	_check(
		not counts.has(3),
		"a team with nobody in it is absent rather than present with zero"
	)

	world.values["a"] = 2
	counts = p.counts_in(area)
	_check(
		(counts[1] as DotObjectivePresence.Count).cappers == 2,
		"a capture value of two counts as two players"
	)
	world.values.erase("a")

	world.can_capture["a"] = false
	counts = p.counts_in(area)
	_check(
		(counts[1] as DotObjectivePresence.Count).cappers == 0
		and (counts[1] as DotObjectivePresence.Count).blockers == 1,
		"somebody who may not capture still blocks — Team Fortress 2's invulnerable player"
	)
	world.can_capture.erase("a")

	counts = p.counts_in(area, PackedInt32Array([1]))
	_check(counts.size() == 1, "an allowed-team filter excludes the other side entirely")

	_check(p.nearest(Vector3.ZERO) == "a", "the nearest alive participant is found")
	_check(p.nearest(Vector3.ZERO, 0.0, 2) == "c", "and can be restricted to a team")
	_check(p.nearest(Vector3(500, 0, 0), 1.0) == "", "and nobody is within a metre of nowhere")


# --- Capture ---------------------------------------------------------------

func _capture_world(radius: float = 5.0) -> Array:
	var world := World.new()
	var def := DotObjectiveDef.capture(
		&"mid", DotObjectiveArea.cylinder(Vector3.ZERO, radius, 3.0), 6 * RATE
	)
	var obj := DotObjectiveCapture.new(def)
	var rules := DotObjectiveRules.new()
	rules.live = true
	return [world, obj, rules]


func _test_capture_basic() -> void:
	_section("capture: the quoted time")

	var bits := _capture_world()
	var world: World = bits[0]
	var obj: DotObjectiveCapture = bits[1]
	var rules: DotObjectiveRules = bits[2]
	var p := world.presence()

	world.add("red", 1, Vector3(1, 0, 1))

	var started: Array[int] = []
	obj.started.connect(func(team: int, _by: String) -> void: started.append(team))

	var t := 0
	while not obj.is_finished() and obj.owner_team != 1 and t < 60 * RATE:
		t += 1
		obj.advance(t, p, rules)

	_check(obj.owner_team == 1, "one player on an empty point takes it")
	_check(started.size() == 1, "and the start was announced once")
	_check(
		absf(float(t) - float(6 * RATE)) <= 2.0,
		"and it took the quoted %d ticks, not Source's 2*T*R (took %d)" % [6 * RATE, t]
	)

	# The departure from Source is deliberate and this is the check that pins it: a
	# definition that says six seconds means six seconds with the quoted number of
	# cappers on it. Source's number would have been twelve.
	_check(
		absf(obj.ticks_for(1) - float(6 * RATE)) <= 1.0,
		"ticks_for agrees with the clock"
	)


func _test_capture_curve() -> void:
	_section("capture: diminishing returns")

	_check(is_equal_approx(DotObjectiveCapture.rate_for(1), 1.0), "one capper is worth 1")
	_check(is_equal_approx(DotObjectiveCapture.rate_for(2), 1.5), "two are worth 1.5")
	_check(
		is_equal_approx(DotObjectiveCapture.rate_for(3), 1.0 + 0.5 + 1.0 / 3.0),
		"three are worth 1 + 1/2 + 1/3"
	)
	_check(DotObjectiveCapture.rate_for(0) == 0.0, "nobody is worth nothing")

	var one := _time_to_capture(1)
	var two := _time_to_capture(2)
	var four := _time_to_capture(4)

	_check(two < one, "two players capture faster than one")
	_check(
		two > one / 2,
		"and not twice as fast (%d against %d), which is the whole point of the curve"
			% [two, one]
	)
	_check(
		absf(float(two) - float(one) / 1.5) <= 2.0,
		"two are worth exactly 1.5 players"
	)
	_check(
		four > one / 3,
		"and a fourth player is worth a quarter of one rather than another whole one"
	)


func _time_to_capture(cappers: int) -> int:
	var bits := _capture_world()
	var world: World = bits[0]
	var obj: DotObjectiveCapture = bits[1]
	var rules: DotObjectiveRules = bits[2]
	for i in range(cappers):
		world.add("red%d" % i, 1, Vector3(float(i) * 0.5, 0, 0))
	var p := world.presence()
	var t := 0
	while obj.owner_team != 1 and t < 120 * RATE:
		t += 1
		obj.advance(t, p, rules)
	return t


func _test_capture_blocking() -> void:
	_section("capture: blocking")

	var bits := _capture_world()
	var world: World = bits[0]
	var obj: DotObjectiveCapture = bits[1]
	var rules: DotObjectiveRules = bits[2]
	world.add("red", 1, Vector3(1, 0, 0))
	world.add("blue", 2, Vector3(200, 0, 0))
	var p := world.presence()

	for t in range(1, RATE + 1):
		obj.advance(t, p, rules)
	var half := obj.progress()
	_check(half > 0.1, "a capture is under way")

	world.move("blue", Vector3(1, 0, 1))
	for t in range(RATE + 1, RATE * 3):
		obj.advance(t, p, rules)

	_check(obj.is_blocked(), "a defender in the zone blocks it")
	_check(
		absf(obj.progress() - half) < 0.02,
		"and with block_style 1 it is paused, not undone (%.3f against %.3f)"
			% [obj.progress(), half]
	)
	_check(obj.phase == DotObjective.Phase.CONTESTED, "the phase says contested")

	world.move("blue", Vector3(200, 0, 0))
	obj.advance(RATE * 3, p, rules)
	_check(not obj.is_blocked(), "and it resumes when they leave")

	# The other style, which is the older behaviour and what some modes want.
	var bits2 := _capture_world()
	var w2: World = bits2[0]
	var o2: DotObjectiveCapture = bits2[1]
	var r2: DotObjectiveRules = bits2[2]
	r2.block_style = 0
	w2.add("red", 1, Vector3(1, 0, 0))
	w2.add("blue", 2, Vector3(1, 0, 1))
	var p2 := w2.presence()
	for t in range(1, RATE):
		o2.advance(t, p2, r2)
	_check(
		o2.capturing_team() == 0,
		"with block_style 0 a contested capture is broken outright"
	)


func _test_capture_recovery() -> void:
	_section("capture: the recovery period after a failed push")

	# capture_recovery_ticks is the one rule here that Source does not have, and it is
	# the kind that is easy to declare and never wire: nothing errors when a capture
	# restarts immediately, because restarting immediately is what Source does.
	var bits := _capture_world()
	var world: World = bits[0]
	var obj: DotObjectiveCapture = bits[1]
	var rules: DotObjectiveRules = bits[2]
	rules.block_style = 0
	rules.capture_recovery_ticks = 3 * RATE

	world.add("red", 1, Vector3(1, 0, 0))
	world.add("blue", 2, Vector3(200, 0, 0))
	var p := world.presence()

	var t := 0
	while t < RATE:
		t += 1
		obj.advance(t, p, rules)
	_check(obj.capturing_team() == 1, "a push is under way")

	# Blue arrives, and with block_style 0 that breaks it outright.
	world.move("blue", Vector3(1, 0, 1))
	t += 1
	obj.advance(t, p, rules)
	_check(obj.capturing_team() == 0, "and the other team breaks it")
	var broke_at := t

	# Blue leaves again. Red is standing on the point on its own and may not start.
	world.move("blue", Vector3(200, 0, 0))
	for _i in range(RATE):
		t += 1
		obj.advance(t, p, rules)
	_check(
		obj.capturing_team() == 0,
		"a second later red is alone on the point and still may not start"
	)
	_check(
		is_equal_approx(obj.progress(), 0.0),
		"and no progress has been made in the meantime"
	)

	# And it may once the period is up.
	while t < broke_at + 3 * RATE:
		t += 1
		obj.advance(t, p, rules)
	t += 1
	obj.advance(t, p, rules)
	_check(obj.capturing_team() == 1, "and may once the recovery period is up")

	# Zero, the default, is Source: a break is over the moment it happens.
	var bits2 := _capture_world()
	var w2: World = bits2[0]
	var o2: DotObjectiveCapture = bits2[1]
	var r2: DotObjectiveRules = bits2[2]
	r2.block_style = 0
	w2.add("red", 1, Vector3(1, 0, 0))
	w2.add("blue", 2, Vector3(1, 0, 1))
	var p2 := w2.presence()
	o2.advance(1, p2, r2)
	_check(o2.capturing_team() == 0, "with recovery at zero the push is broken")
	w2.move("blue", Vector3(200, 0, 0))
	o2.advance(2, p2, r2)
	_check(o2.capturing_team() == 1, "and may start again on the very next tick")


func _test_capture_decay() -> void:
	_section("capture: decay and the neutral tug of war")

	var bits := _capture_world()
	var world: World = bits[0]
	var obj: DotObjectiveCapture = bits[1]
	var rules: DotObjectiveRules = bits[2]
	world.add("red", 1, Vector3(1, 0, 0))
	var p := world.presence()

	for t in range(1, 2 * RATE):
		obj.advance(t, p, rules)
	var reached := obj.progress()
	_check(reached > 0.2, "a partial capture exists")

	world.move("red", Vector3(200, 0, 0))
	for t in range(2 * RATE, 4 * RATE):
		obj.advance(t, p, rules)
	_check(
		obj.progress() < reached and obj.progress() > 0.0,
		"an abandoned capture decays rather than snapping back (%.3f from %.3f)"
			% [obj.progress(), reached]
	)

	var slow := obj.progress()
	rules.overtime = true
	for t in range(4 * RATE, 4 * RATE + 30):
		obj.advance(t, p, rules)
	var fast_drop := slow - obj.progress()
	rules.overtime = false
	_check(fast_drop > 0.0, "and faster in overtime")

	# The neutral tug of war: a point nobody owns, being taken by red, with blue
	# standing on it, runs backwards rather than breaking.
	var bits2 := _capture_world()
	var w2: World = bits2[0]
	var o2: DotObjectiveCapture = bits2[1]
	var r2: DotObjectiveRules = bits2[2]
	r2.block_style = 1
	w2.add("red", 1, Vector3(1, 0, 0))
	var p2 := w2.presence()
	for t in range(1, 2 * RATE):
		o2.advance(t, p2, r2)
	var at := o2.progress()
	w2.move("red", Vector3(300, 0, 0))
	w2.add("blue", 2, Vector3(1, 0, 0))
	for t in range(2 * RATE, 2 * RATE + 20):
		o2.advance(t, p2, r2)
	_check(
		o2.progress() < at,
		"a neutral point with the other team on it runs backwards"
	)


func _test_capture_block_credit() -> void:
	_section("capture: block credit")

	var bits := _capture_world()
	var world: World = bits[0]
	var obj: DotObjectiveCapture = bits[1]
	var rules: DotObjectiveRules = bits[2]
	world.add("red", 1, Vector3(1, 0, 0))
	world.add("blue", 2, Vector3(400, 0, 0))
	var p := world.presence()

	var credits: Array[String] = []
	obj.blocked.connect(func(by: String, _team: int) -> void: credits.append(by))

	# Interfere immediately: the capture has barely started.
	world.move("blue", Vector3(1, 0, 0))
	for t in range(1, 20):
		obj.advance(t, p, rules)
	_check(
		credits.is_empty(),
		"standing on your own point at the start is not a block, and paying for it "
		+ "teaches players to stand on their own point"
	)

	world.move("blue", Vector3(400, 0, 0))
	for t in range(20, 20 + 5 * RATE):
		obj.advance(t, p, rules)
	_check(obj.progress() > rules.block_credit_fraction, "the capture is past half")

	world.move("blue", Vector3(1, 0, 0))
	for t in range(20 + 5 * RATE, 20 + 6 * RATE):
		obj.advance(t, p, rules)
	_check(credits.size() == 1, "blocking a capture past half is credited once")
	_check(credits[0] == "blue", "to the player who did it")


# --- Bomb ------------------------------------------------------------------

func _bomb_world() -> Array:
	var world := World.new()
	var def := DotObjectiveDef.bomb(
		&"site_a", DotObjectiveArea.cylinder(Vector3.ZERO, 6.0, 3.0)
	)
	def.initial_team = 1
	def.bomb_plant_ticks = 3 * RATE
	def.bomb_fuse_ticks = 45 * RATE
	def.bomb_defuse_ticks = 10 * RATE
	def.bomb_defuse_kit_ticks = 5 * RATE
	var obj := DotObjectiveBomb.new(def)
	var rules := DotObjectiveRules.new()
	rules.live = true
	return [world, obj, rules]


func _test_bomb_plant() -> void:
	_section("bomb: planting")

	var bits := _bomb_world()
	var world: World = bits[0]
	var obj: DotObjectiveBomb = bits[1]
	var rules: DotObjectiveRules = bits[2]
	world.add("t1", 1, Vector3(100, 0, 0))
	var p := world.presence()

	var events: Array[StringName] = []
	obj.event.connect(func(what: StringName, _d: Dictionary) -> void: events.append(what))

	var _give := obj.give_to("t1")
	var outside := obj.begin_plant("t1", p)
	_check(not outside.ok, "a plant outside the site is refused")
	_check(outside.code() == DotError.CODE_STATE, "with a state code")

	world.move("t1", Vector3(1, 0, 1))
	_check(obj.begin_plant("t1", p).ok, "and accepted inside it")
	_check(obj.state == DotObjectiveBomb.State.PLANTING, "the state says planting")

	for t in range(1, 2 * RATE):
		obj.advance(t, p, rules)
	_check(obj.state == DotObjectiveBomb.State.PLANTING, "still planting after two seconds")

	world.move("t1", Vector3(100, 0, 0))
	obj.advance(2 * RATE, p, rules)
	_check(
		obj.state == DotObjectiveBomb.State.HELD,
		"walking out of the site interrupts the plant, checked here rather than trusted"
	)

	world.move("t1", Vector3(1, 0, 1))
	var _again := obj.begin_plant("t1", p)
	for t in range(2 * RATE, 6 * RATE):
		obj.advance(t, p, rules)
	_check(obj.is_armed(), "a full plant arms it")
	_check(events.has(&"planted"), "and says so")
	_check(obj.owner_team == 1, "the planting side owns it")

	var start := obj.fuse_remaining()
	obj.advance(6 * RATE, p, rules)
	_check(obj.fuse_remaining() == start - 1, "the fuse burns one tick per tick")

	var t2 := 6 * RATE
	while not obj.is_finished() and t2 < 200 * RATE:
		t2 += 1
		obj.advance(t2, p, rules)
	_check(obj.state == DotObjectiveBomb.State.EXPLODED, "and it goes off")
	_check(obj.phase == DotObjective.Phase.COMPLETE, "which completes the objective")


func _test_bomb_defuse() -> void:
	_section("bomb: defusing")

	var bits := _bomb_world()
	var world: World = bits[0]
	var obj: DotObjectiveBomb = bits[1]
	var rules: DotObjectiveRules = bits[2]
	world.add("t1", 1, Vector3(1, 0, 0))
	world.add("ct1", 2, Vector3(1, 0, 0))
	var p := world.presence()

	var _g := obj.give_to("t1")
	var _b := obj.begin_plant("t1", p)
	for t in range(1, 4 * RATE):
		obj.advance(t, p, rules)
	_check(obj.is_armed(), "the bomb is armed")

	_check(
		not obj.begin_defuse("t1", p).ok,
		"the planting side does not defuse its own bomb"
	)

	_check(obj.begin_defuse("ct1", p).ok, "a defender may")
	for t in range(4 * RATE, 8 * RATE):
		obj.advance(t, p, rules)
	_check(obj.state == DotObjectiveBomb.State.DEFUSING, "and is still at it")
	_check(obj.fuse_remaining() < 45 * RATE, "while the fuse keeps burning")

	world.kill("ct1")
	obj.advance(8 * RATE, p, rules)
	_check(
		obj.state == DotObjectiveBomb.State.PLANTED,
		"a defuser who dies stops defusing, which is the bug this mode ships once"
	)

	world.alive["ct1"] = true
	var kit := obj.begin_defuse("ct1", p, true)
	_check(kit.ok, "a kit defuse starts")
	var t := 8 * RATE
	while not obj.is_finished() and t < 60 * RATE:
		t += 1
		obj.advance(t, p, rules)
	_check(obj.state == DotObjectiveBomb.State.DEFUSED, "and finishes in time")
	_check(
		obj.owner_team == 2,
		"scored for the defending side — the team stamped when the defuse began, "
		+ "not looked up after it ended"
	)

	# Not live: a fuse that keeps burning through a round end detonates in a round
	# that is already over.
	var bits2 := _bomb_world()
	var w2: World = bits2[0]
	var o2: DotObjectiveBomb = bits2[1]
	var r2: DotObjectiveRules = bits2[2]
	w2.add("t1", 1, Vector3(1, 0, 0))
	var p2 := w2.presence()
	var _g2 := o2.give_to("t1")
	var _b2 := o2.begin_plant("t1", p2)
	r2.live = false
	o2.advance(1, p2, r2)
	_check(
		o2.state == DotObjectiveBomb.State.HELD,
		"a plant in progress is cancelled when the round stops being live"
	)


func _test_bomb_carrying() -> void:
	_section("bomb: carrying")

	var bits := _bomb_world()
	var world: World = bits[0]
	var obj: DotObjectiveBomb = bits[1]
	world.add("t1", 1, Vector3(20, 0, 0))
	world.add("t2", 1, Vector3(20.5, 0, 0))
	world.add("ct1", 2, Vector3(20, 0, 0))
	var p := world.presence()

	var _g := obj.give_to("t1")
	_check(obj.carrier == "t1", "somebody is carrying it")

	var _d := obj.drop_at(Vector3(20, 0, 0))
	_check(obj.state == DotObjectiveBomb.State.DROPPED, "and drops it")
	_check(obj.carrier == "", "so nobody is carrying it")

	_check(
		not obj.try_pick_up("ct1", p).ok,
		"the defending side may not carry the bomb"
	)
	world.move("t2", Vector3(80, 0, 0))
	_check(not obj.try_pick_up("t2", p).ok, "nor may somebody standing too far away")
	world.move("t2", Vector3(20.5, 0, 0))
	_check(obj.try_pick_up("t2", p).ok, "a team-mate beside it may")
	_check(obj.carrier == "t2", "and now has it")

	world.kill("t2")
	var _d2 := obj.drop_at(Vector3(20, 0, 0))
	_check(not obj.try_pick_up("t2", p).ok, "a dead player picks nothing up")


# --- Payload ---------------------------------------------------------------

func _payload_world(gradient: PackedInt32Array = PackedInt32Array()) -> Array:
	var world := World.new()
	var def := DotObjectiveDef.payload(
		&"cart",
		PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0), Vector3(200, 0, 0)])
	)
	def.initial_team = 1
	def.payload_speed = 0.1
	def.payload_push_radius = 4.0
	def.payload_gradient = gradient
	def.payload_checkpoints = PackedFloat32Array([100.0])
	def.payload_recede_ticks = 2 * RATE
	var obj := DotObjectivePayload.new(def)
	var rules := DotObjectiveRules.new()
	rules.live = true
	return [world, obj, rules]


func _test_payload() -> void:
	_section("payload")

	var bits := _payload_world()
	var world: World = bits[0]
	var obj: DotObjectivePayload = bits[1]
	var rules: DotObjectiveRules = bits[2]
	world.add("red", 1, Vector3(1, 0, 0))
	var p := world.presence()

	obj.advance(1, p, rules)
	var one_step := obj.distance
	_check(
		is_equal_approx(one_step, 0.1 * 0.55),
		"one pusher moves it at 0.55 of full speed"
	)

	world.add("red2", 1, Vector3(1, 0, 1))
	obj.advance(2, p, rules)
	_check(
		is_equal_approx(obj.distance - one_step, 0.1 * 0.77),
		"a second makes it 0.77"
	)
	world.add("red3", 1, Vector3(1, 0, 2))
	var before := obj.distance
	obj.advance(3, p, rules)
	_check(is_equal_approx(obj.distance - before, 0.1), "a third makes it full speed")
	_check(obj.speed_level == 3, "and the speed level says so")

	world.add("blue", 2, Vector3(1, 0, 0))
	before = obj.distance
	obj.advance(4, p, rules)
	_check(is_equal_approx(obj.distance, before), "a defender on the cart stops it")
	_check(obj.speed_level == 0, "at speed level zero")
	world.positions.erase("blue")
	world.teams.erase("blue")
	world.alive.erase("blue")

	# Nobody pushing, level ground: it waits, then recedes.
	world.move("red", Vector3(500, 0, 0))
	world.move("red2", Vector3(500, 0, 0))
	world.move("red3", Vector3(500, 0, 0))
	before = obj.distance
	obj.advance(5, p, rules)
	_check(is_equal_approx(obj.distance, before), "with nobody on it, it holds")
	for t in range(6, 6 + 3 * RATE):
		obj.advance(t, p, rules)
	_check(obj.is_receding(), "and after the idle time it starts rolling back")
	_check(obj.distance < before, "losing ground")

	# A checkpoint is a floor it cannot roll back past.
	var bits2 := _payload_world()
	var w2: World = bits2[0]
	var o2: DotObjectivePayload = bits2[1]
	var r2: DotObjectiveRules = bits2[2]
	w2.add("red", 1, Vector3(1, 0, 0))
	var p2 := w2.presence()
	var events: Array[StringName] = []
	o2.event.connect(func(what: StringName, _d: Dictionary) -> void: events.append(what))
	var t2 := 0
	while o2.distance < 110.0 and t2 < 100000:
		t2 += 1
		w2.move("red", o2.position() + Vector3(0.5, 0, 0))
		o2.advance(t2, p2, r2)
	_check(events.has(&"checkpoint"), "crossing a checkpoint announces it")
	_check(is_equal_approx(o2.floor_distance, 100.0), "and raises the floor")
	w2.move("red", Vector3(-500, 0, 0))
	for t in range(t2, t2 + 20 * RATE):
		o2.advance(t, p2, r2)
	_check(
		o2.distance >= 100.0,
		"and the cart cannot roll back past it (%.2f)" % o2.distance
	)

	# A hill does the work.
	var bits3 := _payload_world(PackedInt32Array([-1, 0]))
	var w3: World = bits3[0]
	var o3: DotObjectivePayload = bits3[1]
	var r3: DotObjectiveRules = bits3[2]
	w3.add("nobody", 1, Vector3(9999, 0, 0))
	var p3 := w3.presence()
	o3.advance(1, p3, r3)
	_check(
		is_equal_approx(o3.distance, 0.1),
		"a downhill segment rolls the cart at full speed with nobody on it"
	)

	var bits4 := _payload_world(PackedInt32Array([1, 0]))
	var w4: World = bits4[0]
	var o4: DotObjectivePayload = bits4[1]
	var r4: DotObjectiveRules = bits4[2]
	w4.add("nobody", 1, Vector3(9999, 0, 0))
	var p4 := w4.presence()
	o4.distance = 50.0
	o4.advance(1, p4, r4)
	_check(
		o4.distance < 50.0,
		"and an uphill one rolls it backwards immediately, without waiting to recede"
	)


# --- Flag ------------------------------------------------------------------

func _test_flag() -> void:
	_section("capture the flag")

	var world := World.new()
	var red_def := DotObjectiveDef.flag(
		&"red_flag", DotObjectiveArea.sphere(Vector3.ZERO, 2.0), 1
	)
	red_def.flag_capture_area = DotObjectiveArea.sphere(Vector3(100, 0, 0), 3.0)
	red_def.flag_return_ticks = 2 * RATE
	var blue_def := DotObjectiveDef.flag(
		&"blue_flag", DotObjectiveArea.sphere(Vector3(100, 0, 0), 2.0), 2
	)
	blue_def.flag_capture_area = DotObjectiveArea.sphere(Vector3.ZERO, 3.0)
	blue_def.flag_requires_own_at_home = true

	var red := DotObjectiveFlag.new(red_def)
	var blue := DotObjectiveFlag.new(blue_def)
	var rules := DotObjectiveRules.new()
	rules.live = true

	world.add("r1", 1, Vector3(0, 0, 0))
	world.add("b1", 2, Vector3(0, 0, 0))
	var p := world.presence()

	_check(
		not red.touch("r1", p).ok,
		"a team does not carry its own flag"
	)
	_check(red.touch("b1", p).ok, "the other side does")
	_check(red.carrier == "b1", "and is carrying it")
	_check(red.home_team() == 1, "the flag still belongs to red — owner is who defends it")

	world.move("b1", Vector3(50, 0, 0))
	red.advance(1, p, rules)
	_check(red.at.distance_to(Vector3(50, 0, 0)) < 0.01, "the flag follows the carrier")
	_check(red.progress() > 0.4, "and the progress is the journey home")

	var _d := red.drop(Vector3(50, 0, 0))
	_check(red.state == DotObjectiveFlag.State.DROPPED, "killing the carrier drops it")
	world.move("r1", Vector3(50, 0, 0))
	_check(red.touch("r1", p).ok, "and a team-mate touching it sends it home")
	_check(red.is_home(), "which it does")

	# The timer, when nobody touches it.
	var _t := red.touch("b1", p)
	var _d2 := red.drop(Vector3(60, 0, 0))
	for t in range(1, 3 * RATE):
		red.advance(t, p, rules)
	_check(red.is_home(), "and a dropped flag goes home by itself after its timer")

	# The rule that stops two simultaneous captures.
	world.move("b1", Vector3(0, 0, 0))
	var _tt := red.touch("b1", p)
	world.move("r1", Vector3(100, 0, 0))
	var _tb := blue.touch("r1", p)
	_check(blue.carrier == "r1", "red has blue's flag")
	var refused := blue.may_capture([red, blue] as Array[DotObjectiveFlag])
	_check(
		not refused.ok,
		"and cannot capture while their own flag is out — the stalemate rule"
	)
	var _home := red.send_home("")
	_check(
		blue.may_capture([red, blue] as Array[DotObjectiveFlag]).ok,
		"and can once it is back"
	)

	var scored := blue.capture("r1")
	_check(scored.ok, "the capture scores")
	_check(blue.captures == 1, "and is counted")
	_check(blue.is_home(), "and the flag goes home")

	_check(
		not red.touch("b1", p).ok or red.carrier == "b1",
		"a flag out of reach cannot be taken"
	)


# --- Rescue ----------------------------------------------------------------

func _test_rescue() -> void:
	_section("rescue")

	var world := World.new()
	var def := DotObjectiveDef.rescue(
		&"hostages",
		PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0), Vector3(4, 0, 0)]),
		DotObjectiveArea.sphere(Vector3(100, 0, 0), 5.0)
	)
	def.initial_team = 2
	def.capturable_by = PackedInt32Array([2])
	def.rescue_required = 2
	def.rescue_follow_distance = 1.5
	var obj := DotObjectiveRescue.new(def)
	var rules := DotObjectiveRules.new()
	rules.live = true

	world.add("ct", 2, Vector3(0.5, 0, 0))
	world.add("t", 1, Vector3(0.5, 0, 0))
	var p := world.presence()

	_check(obj.required() == 2, "two of three are needed")
	_check(
		not obj.take(&"hostages_1", "t", p).ok,
		"the other side may not rescue"
	)
	_check(obj.take(&"hostages_1", "ct", p).ok, "the rescuing side may")
	_check(
		obj.state_of(&"hostages_1") == DotObjectiveRescue.Follower.FOLLOWING,
		"and it follows"
	)
	_check(
		not obj.take(&"hostages_3", "ct", p).ok,
		"and one too far away is refused"
	)

	world.move("ct", Vector3(50, 0, 0))
	for t in range(1, 5):
		obj.advance(t, p, rules)
	_check(
		obj.position_of(&"hostages_1").distance_to(Vector3(50, 0, 0)) <= 1.6,
		"a follower trails its rescuer at the follow distance"
	)

	world.move("ct", Vector3(100, 0, 0))
	for t in range(5, 40):
		obj.advance(t, p, rules)
	_check(obj.rescued() == 1, "reaching the rescue area rescues it")

	world.move("ct", Vector3(4, 0, 0))
	_check(obj.take(&"hostages_3", "ct", p).ok, "a second is picked up")
	world.move("ct", Vector3(100, 0, 0))
	for t in range(40, 90):
		obj.advance(t, p, rules)
	_check(obj.rescued() == 2, "and rescued")
	_check(obj.phase == DotObjective.Phase.COMPLETE, "which completes the objective")

	# The impossible case.
	var obj2 := DotObjectiveRescue.new(def)
	var events: Array[StringName] = []
	obj2.event.connect(func(what: StringName, _d: Dictionary) -> void: events.append(what))
	var _l1 := obj2.lose(&"hostages_1")
	_check(obj2.remaining_possible() == 2, "one lost leaves two possible")
	_check(not events.has(&"impossible"), "which is still enough")
	var _l2 := obj2.lose(&"hostages_2")
	_check(
		events.has(&"impossible"),
		"losing one too many says so rather than waiting for a number nobody can reach"
	)
	_check(obj2.phase == DotObjective.Phase.FAILED, "and the objective fails")

	var dropped := DotObjectiveRescue.new(def)
	var _t3 := dropped.take(&"hostages_1", "ct", p)
	world.kill("ct")
	dropped.advance(1, p, rules)
	_check(
		dropped.state_of(&"hostages_1") == DotObjectiveRescue.Follower.WAITING,
		"a rescuer who dies leaves their follower where it stands"
	)


# --- Holdout ---------------------------------------------------------------

func _test_holdout() -> void:
	_section("holdout")

	# King of the hill: a point, and a clock that reads its owner.
	var point_def := DotObjectiveDef.capture(
		&"hill", DotObjectiveArea.cylinder(Vector3.ZERO, 5.0, 3.0), RATE
	)
	var clock_def := DotObjectiveDef.holdout(&"koth", 5 * RATE)
	clock_def.holdout_owner_of = &"hill"
	clock_def.area = DotObjectiveArea.cylinder(Vector3.ZERO, 5.0, 3.0)

	var defs: Array[DotObjectiveDef] = [point_def, clock_def]
	var built := DotObjectiveSet.build(defs)
	_check(built.ok, "a king-of-the-hill set builds")
	var set_: DotObjectiveSet = built.value
	var point := set_.objective(&"hill") as DotObjectiveCapture
	var clock := set_.objective(&"koth") as DotObjectiveHoldout
	_check(clock.linked == point, "the clock is pointed at the point")

	var world := World.new()
	world.add("red", 1, Vector3(1, 0, 0))
	var p := world.presence()
	var rules := DotObjectiveRules.new()
	rules.live = true

	for t in range(1, 3 * RATE):
		point.advance(t, p, rules)
		clock.advance(t, p, rules)
	_check(point.owner_team == 1, "red owns the point")
	_check(clock.remaining_for(1) < 5 * RATE, "and red's clock is running")

	world.move("red", Vector3(400, 0, 0))
	world.add("blue", 2, Vector3(1, 0, 0))
	# Sampled at the tick the point changes hands rather than before it: red's clock
	# legitimately keeps running for the second blue spends capturing, and a sample
	# taken early measures that instead of the freeze.
	var red_left := 0
	for t in range(3 * RATE, 6 * RATE):
		point.advance(t, p, rules)
		clock.advance(t, p, rules)
		if point.owner_team == 2 and red_left == 0:
			red_left = clock.remaining_for(1)
	_check(point.owner_team == 2, "blue takes it")
	_check(
		clock.remaining_for(1) == red_left,
		"and red's clock is frozen where it stopped, not reset — which is the whole "
		+ "tension of the mode"
	)
	_check(clock.remaining_for(2) < 5 * RATE, "while blue's runs")

	# A finale: the clock only counts while somebody is still standing there.
	var finale_def := DotObjectiveDef.holdout(&"finale", 3 * RATE)
	finale_def.area = DotObjectiveArea.cylinder(Vector3(50, 0, 0), 6.0, 4.0)
	finale_def.initial_team = 1
	finale_def.holdout_requires_presence = true
	var finale := DotObjectiveHoldout.new(finale_def)

	var w2 := World.new()
	w2.add("a", 1, Vector3(400, 0, 0))
	var p2 := w2.presence()
	for t in range(1, RATE):
		finale.advance(t, p2, rules)
	_check(
		finale.remaining_for(1) == 3 * RATE,
		"a presence-gated clock does not run with nobody there"
	)
	w2.move("a", Vector3(50, 0, 0))
	for t in range(RATE, 2 * RATE):
		finale.advance(t, p2, rules)
	_check(finale.remaining_for(1) < 3 * RATE, "and does once somebody is")

	var t3 := 2 * RATE
	while not finale.is_finished() and t3 < 100 * RATE:
		t3 += 1
		finale.advance(t3, p2, rules)
	_check(finale.phase == DotObjective.Phase.COMPLETE, "holding it out wins it")


# --- The set ---------------------------------------------------------------

func _test_set_gating() -> void:
	_section("the set: a tug of war rather than a race")

	# A three-point map: red's, the middle, blue's. Neither side may reach the far
	# point without owning the middle.
	var red_pt := DotObjectiveDef.capture(
		&"red_point", DotObjectiveArea.cylinder(Vector3(-50, 0, 0), 5.0), RATE
	)
	red_pt.initial_team = 1
	var mid := DotObjectiveDef.capture(
		&"mid", DotObjectiveArea.cylinder(Vector3.ZERO, 5.0), RATE
	)
	var blue_pt := DotObjectiveDef.capture(
		&"blue_point", DotObjectiveArea.cylinder(Vector3(50, 0, 0), 5.0), RATE
	)
	blue_pt.initial_team = 2
	blue_pt.requires_owned = {1: [&"mid"]}
	red_pt.requires_owned = {2: [&"mid"]}

	var defs: Array[DotObjectiveDef] = [red_pt, mid, blue_pt]
	var built := DotObjectiveSet.build(defs)
	_check(built.ok, "the set builds")
	var set_: DotObjectiveSet = built.value

	var world := World.new()
	world.add("red", 1, Vector3(50, 0, 0))
	var p := world.presence()
	var rules := DotObjectiveRules.new()
	rules.live = true

	var blue_point := set_.objective(&"blue_point") as DotObjectiveCapture
	for t in range(1, 4 * RATE):
		blue_point.advance(t, p, rules)
	_check(
		blue_point.owner_team == 2,
		"red standing on blue's last point captures nothing while blue holds the middle"
	)

	world.move("red", Vector3.ZERO)
	var middle := set_.objective(&"mid") as DotObjectiveCapture
	for t in range(1, 4 * RATE):
		middle.advance(t, p, rules)
	_check(middle.owner_team == 1, "red takes the middle")

	world.move("red", Vector3(50, 0, 0))
	for t in range(1, 4 * RATE):
		blue_point.advance(t, p, rules)
	_check(blue_point.owner_team == 1, "and now the last point is available")

	_check(set_.owned_by(1) == 3, "red owns all three")
	_check(set_.owns_everything(1), "which is the sweep")
	_check(not set_.owns_everything(2), "and blue does not")

	var missing := DotObjectiveDef.capture(
		&"lonely", DotObjectiveArea.sphere(Vector3.ZERO, 2.0)
	)
	missing.requires_owned = {1: [&"nowhere"]}
	var built2 := DotObjectiveSet.build([missing] as Array[DotObjectiveDef])
	var set2: DotObjectiveSet = built2.value
	_check(
		not set2.objective(&"lonely").team_allowed(1),
		"a prerequisite that is not in the set refuses rather than silently allowing, "
		+ "because allowing turns a tug of war back into a race"
	)

	var dup := DotObjectiveDef.capture(&"same", DotObjectiveArea.sphere(Vector3.ZERO, 2.0))
	var dup2 := DotObjectiveDef.capture(&"same", DotObjectiveArea.sphere(Vector3.ZERO, 2.0))
	_check(
		not DotObjectiveSet.build([dup, dup2] as Array[DotObjectiveDef]).ok,
		"two objectives with one id are refused"
	)

	var round_res := set_.set_round([&"mid"] as Array[StringName], {&"mid": 2})
	_check(round_res.ok, "a round layout is accepted")
	_check(set_.objective(&"red_point").locked, "and locks what is not in it")
	_check(not set_.objective(&"mid").locked, "and does not lock what is")
	_check(set_.objective(&"mid").owner_team == 2, "and pre-sets the owner")
	_check(
		not set_.set_round([&"nothing_here"] as Array[StringName]).ok,
		"a layout naming something that does not exist is refused"
	)


# --- The manager -----------------------------------------------------------

func _test_manager() -> void:
	_section("the manager")

	var manager := DotObjectiveManager.new()
	add_child(manager)

	var world := World.new()
	world.add("red", 1, Vector3(1, 0, 0))
	manager.presence = world.presence()

	var a := DotObjectiveDef.capture(&"a", DotObjectiveArea.cylinder(Vector3.ZERO, 5.0), RATE)
	var b := DotObjectiveDef.capture(&"b", DotObjectiveArea.cylinder(Vector3(50, 0, 0), 5.0), RATE)
	var res := manager.setup([a, b] as Array[DotObjectiveDef])
	_check(res.ok, "it sets up")
	_check(manager.has_objectives(), "and has objectives")

	var scored: Array[Dictionary] = []
	manager.score_fn = func(
		id: StringName, team: int, by: String, points: int, player_points: int
	) -> void:
		scored.append({
			"id": id, "team": team, "by": by, "pts": points, "ppts": player_points,
		})

	var sweeps: Array[int] = []
	manager.all_captured.connect(func(team: int) -> void: sweeps.append(team))
	var completions: Array[StringName] = []
	manager.objective_completed.connect(
		func(id: StringName, _team: int, _by: String) -> void: completions.append(id))

	for t in range(1, 4 * RATE):
		manager.advance(t)
	_check(
		manager.objective(&"a").owner_team == 0,
		"nothing happens while the rules are not live, which is what warmup is"
	)

	manager.set_live(true)
	for t in range(1, 4 * RATE):
		manager.advance(t)
	_check(manager.objective(&"a").owner_team == 1, "and it captures once live")
	_check(completions.has(&"a"), "the manager relays the completion with its id")
	_check(scored.size() == 1, "and hands it to the score function")
	_check(scored[0]["team"] == 1 and scored[0]["by"] == "red", "with the team and the player")
	_check(sweeps.is_empty(), "one of two points is not a sweep")

	world.move("red", Vector3(50, 0, 0))
	for t in range(4 * RATE, 8 * RATE):
		manager.advance(t)
	_check(sweeps.size() == 1, "taking both is")
	for t in range(8 * RATE, 9 * RATE):
		manager.advance(t)
	_check(sweeps.size() == 1, "and it is announced exactly once")

	# The wire.
	var mirror := DotObjectiveManager.new()
	mirror.authoritative = false
	add_child(mirror)
	var mres := mirror.setup([a, b] as Array[DotObjectiveDef])
	_check(mres.ok, "a mirror sets up with no presence at all")
	mirror.apply_wire(manager.to_wire())
	_check(
		mirror.objective(&"a").owner_team == 1
		and mirror.objective(&"b").owner_team == 1,
		"and the wire form carries the owners across"
	)

	var before := mirror.objective(&"b").owner_team
	mirror.advance(999)
	_check(
		mirror.objective(&"b").owner_team == before,
		"a mirror does not simulate — two clocks on two machines is two answers"
	)

	manager.reset_round()
	_check(manager.objective(&"a").owner_team == 0, "a reset puts the owners back")

	var lines := manager.describe_lines()
	_check(lines.size() > 2, "and it describes itself")

	manager.queue_free()
	mirror.queue_free()


# --- Two dimensions --------------------------------------------------------

func _test_two_dimensions() -> void:
	_section("the same rule in 2D")

	# A 2D world is the XZ plane, which is the decision dot-npc made and everything
	# downstream of it inherited. The check that matters is that nothing here needed a
	# second code path to run there.
	var world := World.new()
	var here := Vector2(30.0, -12.0)
	var def := DotObjectiveDef.capture(&"flat", DotObjectiveArea.of_2d(here, 4.0), RATE)
	var obj := DotObjectiveCapture.new(def)
	var rules := DotObjectiveRules.new()
	rules.live = true

	world.add("a", 1, DotObjectiveArea.point_2d(here + Vector2(1.0, 1.0)))
	var p := world.presence()

	var t := 0
	while obj.owner_team != 1 and t < 10 * RATE:
		t += 1
		obj.advance(t, p, rules)
	_check(obj.owner_team == 1, "a 2D capture captures")
	_check(
		absf(float(t) - float(RATE)) <= 2.0,
		"in the same number of ticks as the 3D one"
	)

	var cart_def := DotObjectiveDef.payload(
		&"flat_cart",
		PackedVector3Array([
			DotObjectiveArea.point_2d(Vector2.ZERO),
			DotObjectiveArea.point_2d(Vector2(20.0, 0.0)),
		])
	)
	cart_def.initial_team = 1
	cart_def.payload_speed = 0.5
	var cart := DotObjectivePayload.new(cart_def)
	var w2 := World.new()
	w2.add("a", 1, DotObjectiveArea.point_2d(Vector2(0.5, 0.0)))
	var p2 := w2.presence()
	cart.advance(1, p2, rules)
	_check(cart.distance > 0.0, "and a 2D cart rolls")
	_check(
		cart.position_2d().y == 0.0,
		"with a position a 2D game can read straight off"
	)


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
