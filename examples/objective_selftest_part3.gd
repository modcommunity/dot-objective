extends "res://examples/objective_selftest_part2.gd"

## Capture the flag as a mechanic: flow, drop and return, limits, three teams, replication.

var _tick := 0


func _ctf(world: World, rules: DotObjectiveCtfRules, bases: Dictionary) -> DotObjectiveCtf:
	var c := DotObjectiveCtf.new()
	c.rules = rules
	c.presence = world.presence()
	c.tick_rate = RATE
	add_child(c)
	var res := c.setup(bases)
	_check(res.ok, "ctf sets up")
	_tick = 0
	return c


func _run_ticks(c: DotObjectiveCtf, n: int) -> void:
	for i in n:
		_tick += 1
		c.advance(_tick)


func _two_bases() -> Dictionary:
	return {1: Vector3(-50, 0, 0), 2: Vector3(50, 0, 0)}


func _test_ctf_flow() -> void:
	_section("ctf: take theirs, bring it home, score")
	var w := World.new()
	w.add("a", 1, Vector3(-50, 0, 0))
	w.add("b", 2, Vector3(50, 0, 0))
	var c := _ctf(w, DotObjectiveCtfRules.new(), _two_bases())
	var seen: Array = []
	c.captured.connect(func(t: int, by: String, total: int) -> void: seen.append([t, by, total]))
	_run_ticks(c, 2)
	_check(c.flags().size() == 2 and c.flag_of(1).is_home(), "one flag per team, both at home")
	w.move("a", Vector3(50, 0, 0))
	_run_ticks(c, 2)
	_check(c.carried_by("a") == c.flag_of(2), "a takes team 2's flag by standing on it")
	_check(is_equal_approx(c.speed_scale("a"), 0.9) and c.speed_scale("b") == 1.0, "the carrier is slowed, nobody else")
	w.move("a", Vector3(0, 0, 0))
	_run_ticks(c, 2)
	_check(c.carried_by("a") != null and seen.is_empty(), "carrying across the middle scores nothing")
	w.move("a", Vector3(-50, 0, 0))
	_run_ticks(c, 2)
	_check(seen == [[1, "a", 1]] and c.scores[1] == 1 and c.flag_of(2).is_home(), "arriving at their own stand with theirs home scores and returns the flag")
	_check(c.speed_scale("a") == 1.0, "and the slowdown ends")

	# The own-flag-at-home rule.
	w.move("b", Vector3(-50, 0, 0))
	_run_ticks(c, 2)
	_check(c.carried_by("b") == c.flag_of(1), "b takes team 1's flag")
	w.move("a", Vector3(50, 0, 0))
	_run_ticks(c, 2)
	_check(c.carried_by("a") == c.flag_of(2), "while a takes theirs")
	w.add("d", 1, Vector3(-80, 0, 60))
	w.move("a", Vector3(-48, 0, 0))
	w.move("b", Vector3(50, 0, 0))
	_run_ticks(c, 2)
	_check(c.scores[2] == 0 and c.scores[1] == 1, "both at their stands, both flags out: neither scores (the stalemate rule)")
	w.kill("b")
	c.player_died("b")
	_run_ticks(c, 2)
	_check(c.scores[1] == 1 and c.flag_of(1).state == DotObjectiveFlag.State.DROPPED, "b dies and drops team 1's flag; a still cannot score")
	w.move("d", c.flag_of(1).at)
	_run_ticks(c, 2)
	_check(c.flag_of(1).is_home(), "a team-mate returns it")
	_run_ticks(c, 2)
	_check(c.scores[1] == 2, "and now a's capture goes through")
	c.queue_free()

	var rules := DotObjectiveCtfRules.new()
	rules.require_home = false
	var w2 := World.new()
	w2.add("a", 1, Vector3(50, 0, 0))
	w2.add("b", 2, Vector3(-50, 0, 0))
	var c2 := _ctf(w2, rules, _two_bases())
	_run_ticks(c2, 2)
	w2.move("a", Vector3(-50, 0, 0))
	w2.move("b", Vector3(50, 0, 0))
	_run_ticks(c2, 2)
	_check(c2.scores[1] == 1 and c2.scores[2] == 1, "with require_home off both teams capture at once")
	c2.queue_free()


func _test_ctf_drop_and_return() -> void:
	_section("ctf: dropping, picking up, returning")
	var rules := DotObjectiveCtfRules.new()
	rules.return_sec = 5
	rules.drop_sec = 1
	var w := World.new()
	w.add("a", 1, Vector3(50, 0, 0))
	w.add("b", 2, Vector3(0, 0, 90))
	w.add("c", 1, Vector3(0, 0, -90))
	var c := _ctf(w, rules, _two_bases())
	_run_ticks(c, 2)
	_check(c.carried_by("a") != null, "a takes the flag")
	w.move("a", Vector3(20, 0, 0))
	_run_ticks(c, 2)
	w.kill("a")
	c.player_died("a")
	var f := c.flag_of(2)
	_check(f.state == DotObjectiveFlag.State.DROPPED and f.at.distance_to(Vector3(20, 0, 0)) < 1.0, "a carrier who dies drops it where they stood")
	w.alive["a"] = true
	_run_ticks(c, 2)
	_check(f.state == DotObjectiveFlag.State.DROPPED, "the dropper cannot take it straight back")
	_run_ticks(c, RATE)
	_check(f.state == DotObjectiveFlag.State.CARRIED and f.carrier == "a", "after the drop delay they can")
	w.move("a", Vector3(10, 0, 0))
	_run_ticks(c, 2)
	c.player_left("a")
	w.kill("a")
	w.move("c", Vector3(10, 0, 0))
	_run_ticks(c, 2)
	_check(f.carrier == "c", "a team-mate of the dropper picks it up at once")
	c.player_died("c")
	w.kill("c")
	w.move("b", f.at)
	_run_ticks(c, 2)
	_check(f.is_home(), "the flag's own team touching it returns it on the spot")
	c.queue_free()

	rules.friendly_return = false
	var w2 := World.new()
	w2.add("a", 1, Vector3(50, 0, 0))
	w2.add("b", 2, Vector3(0, 0, 90))
	var c2 := _ctf(w2, rules, _two_bases())
	_run_ticks(c2, 2)
	w2.move("a", Vector3(20, 0, 0))
	_run_ticks(c2, 2)
	c2.player_died("a")
	w2.kill("a")
	var f2 := c2.flag_of(2)
	w2.move("b", f2.at)
	_run_ticks(c2, 2)
	_check(f2.state == DotObjectiveFlag.State.DROPPED, "with friendly_return off, touching changes nothing")
	_run_ticks(c2, 5 * RATE)
	_check(f2.is_home(), "and the timer sends it home after return_sec")
	c2.queue_free()


func _test_ctf_limits() -> void:
	_section("ctf: capture limit and time limit")
	var rules := DotObjectiveCtfRules.new()
	rules.capture_limit = 2
	var w := World.new()
	w.add("a", 1, Vector3(50, 0, 0))
	var c := _ctf(w, rules, _two_bases())
	var ends: Array = []
	c.ended.connect(func(team: int, why: StringName) -> void: ends.append([team, why]))
	for round in 2:
		w.move("a", Vector3(50, 0, 0))
		_run_ticks(c, 2)
		w.move("a", Vector3(-50, 0, 0))
		_run_ticks(c, 2)
	_check(c.scores[1] == 2 and ends == [[1, &"capture_limit"]] and c.finished and c.winner == 1, "the second capture ends the match for team 1, once")
	w.move("a", Vector3(50, 0, 0))
	_run_ticks(c, 4)
	w.move("a", Vector3(-50, 0, 0))
	_run_ticks(c, 4)
	_check(c.scores[1] == 2 and ends.size() == 1, "nothing counts after the end")
	c.reset_match()
	_check(c.scores[1] == 0 and not c.finished and c.winner == 0, "reset_match starts afresh")
	c.queue_free()

	var timed := DotObjectiveCtfRules.new()
	timed.capture_limit = 0
	timed.time_limit_sec = 2
	var w2 := World.new()
	w2.add("a", 1, Vector3(50, 0, 0))
	var c2 := _ctf(w2, timed, _two_bases())
	var ends2: Array = []
	c2.ended.connect(func(team: int, why: StringName) -> void: ends2.append([team, why]))
	_run_ticks(c2, 2)
	w2.move("a", Vector3(-50, 0, 0))
	_run_ticks(c2, 2)
	_check(c2.scores[1] == 1 and c2.time_left_sec() > 0.0, "no capture limit: the match goes on")
	_run_ticks(c2, 2 * RATE)
	_check(ends2 == [[1, &"time_limit"]], "the time limit ends it with the leader winning")
	c2.reset_match()
	_run_ticks(c2, 2 * RATE + 2)
	_check(ends2.size() == 2 and ends2[1] == [0, &"time_limit"], "level scores at the time limit are a draw")
	var before := c2.live_ticks
	c2.advance(_tick + 1, false)
	_check(c2.live_ticks == before, "the clock does not run while not live")
	c2.queue_free()
	_check(not DotObjectiveCtfRules.new().validate().ok == false, "default rules validate")
	var bad := DotObjectiveCtfRules.new()
	bad.touch_radius = 90.0
	_check(not bad.validate().ok, "an absurd touch radius is refused")
	var lone := DotObjectiveCtf.new()
	_check(not lone.setup({1: Vector3.ZERO}).ok, "one team is refused")
	lone.free()


func _test_ctf_three_teams() -> void:
	_section("ctf: three teams")
	var rules := DotObjectiveCtfRules.new()
	rules.team_count = 3
	rules.capture_limit = 2
	var bases := {1: Vector3(-50, 0, 0), 2: Vector3(50, 0, 0), 3: Vector3(0, 0, 80)}
	var w := World.new()
	w.add("a", 1, Vector3(-50, 0, 0))
	w.add("b", 2, Vector3(50, 0, 0))
	w.add("c", 3, Vector3(0, 0, 80))
	var c := _ctf(w, rules, bases)
	_check(c.flags().size() == 3, "three flags")
	w.move("a", bases[3])
	_run_ticks(c, 2)
	_check(c.carried_by("a") == c.flag_of(3), "team 1 takes team 3's flag")
	w.move("b", bases[3])
	_run_ticks(c, 2)
	_check(c.carried_by("b") == null, "a flag is carried by one player at a time")
	w.move("b", Vector3(0, 0, 40))
	w.move("a", bases[1])
	_run_ticks(c, 2)
	_check(c.scores[1] == 1 and c.scores[2] == 0 and c.scores[3] == 0, "scored at team 1's own stand")
	w.move("b", bases[1])
	_run_ticks(c, 2)
	_check(c.carried_by("b") == c.flag_of(1), "team 2 takes team 1's flag too")
	w.move("c", bases[1])
	_run_ticks(c, 2)
	_check(c.carried_by("c") == null, "team 3 cannot take a flag already carried")
	w.move("b", bases[2])
	_run_ticks(c, 2)
	_check(c.scores[2] == 1, "team 2 scores it at its stand")
	w.move("c", bases[2])
	_run_ticks(c, 2)
	w.move("c", bases[3])
	_run_ticks(c, 2)
	_check(c.scores[3] == 1 and c.winner == 0, "team 3 captures too; no limit reached yet")
	w.move("a", bases[2])
	_run_ticks(c, 2)
	w.move("a", bases[1])
	_run_ticks(c, 2)
	_check(c.winner == 1 and c.finished, "team 1's second capture wins a three-team match")
	var st := c.hud_state()
	_check((st["teams"] as Dictionary).size() == 3 and st["winner"] == 1, "the HUD state covers every team")
	c.queue_free()


func _test_ctf_wire() -> void:
	_section("ctf: server authority and replication")
	var rules := DotObjectiveCtfRules.new()
	var w := World.new()
	w.add("a", 1, Vector3(50, 0, 0))
	var server := _ctf(w, rules, _two_bases())
	var mirror := DotObjectiveCtf.new()
	mirror.rules = rules
	mirror.authoritative = false
	mirror.presence = w.presence()
	mirror.tick_rate = RATE
	add_child(mirror)
	_check(mirror.setup(_two_bases()).ok, "a mirror builds the same flags")
	_run_ticks(server, 2)
	mirror.apply_wire(server.to_wire())
	_check(mirror.flag_of(2).state == DotObjectiveFlag.State.CARRIED and mirror.flag_of(2).carrier == "a", "the mirror shows the carrier")
	var events: Array = []
	mirror.flag_event.connect(func(t: int, what: StringName, _d: Dictionary) -> void: events.append([t, what]))
	w.move("a", Vector3(-50, 0, 0))
	_run_ticks(server, 2)
	mirror.apply_wire(server.to_wire())
	_check(mirror.scores[1] == 1 and mirror.flag_of(2).is_home(), "and the capture, through the wire")
	w.move("a", Vector3(50, 0, 0))
	for i in 5:
		mirror.advance(_tick + i)
	_check(mirror.flag_of(2).state == DotObjectiveFlag.State.HOME or mirror.carried_by("a") == null, "a mirror never simulates a touch")
	_check(events.is_empty(), "and raises no events of its own")
	server.queue_free()
	mirror.queue_free()
