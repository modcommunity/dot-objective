extends "res://examples/objective_selftest_part2.gd"

## The suite: runs every section from the parts above and checks the totals.

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

	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


# --- Areas -----------------------------------------------------------------


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

	_set_refusals(set_)


func _set_refusals(set_: DotObjectiveSet) -> void:
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

	_manager_wire(manager, [a, b] as Array[DotObjectiveDef])

	var lines := manager.describe_lines()
	_check(lines.size() > 2, "and it describes itself")
	manager.queue_free()


func _manager_wire(manager: DotObjectiveManager, defs: Array[DotObjectiveDef]) -> void:
	var mirror := DotObjectiveManager.new()
	mirror.authoritative = false
	add_child(mirror)
	var mres := mirror.setup(defs)
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
