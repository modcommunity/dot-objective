extends "res://examples/objective_selftest_base.gd"

## First part of the self-test: areas, validation, presence and capture points.

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
		"somebody who may not capture still blocks — the invulnerable player"
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
		"and it took the quoted %d ticks, not the original 2*T*R (took %d)" % [6 * RATE, t]
	)

	# The departure from the original is deliberate and this is the check that pins it:
	# a definition that says six seconds means six seconds with the quoted number of
	# cappers on it. The original's number would have been twelve.
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

	# capture_recovery_ticks is the one rule here that the original does not have, and it is
	# the kind that is easy to declare and never wire: nothing errors when a capture
	# restarts immediately, because restarting immediately is what the original does.
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

	# Zero, the default, is the original: a break is over the moment it happens.
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
