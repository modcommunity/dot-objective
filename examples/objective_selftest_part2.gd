extends "res://examples/objective_selftest_part1.gd"

## Second part of the self-test: bomb, payload, flag, rescue and holdout.

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

	_payload_checkpoints()
	_payload_hills()


func _payload_checkpoints() -> void:
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



func _payload_hills() -> void:
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

	_rescue_losses(def, world, p, rules)


func _rescue_losses(
	def: DotObjectiveDef, world: World, p: DotObjectivePresence, rules: DotObjectiveRules
) -> void:
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


