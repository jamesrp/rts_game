extends SceneTree

var pass_count: int = 0
var fail_count: int = 0
var game: Node2D

func _init() -> void:
	# Instantiate game
	var GameScript = load("res://main.gd")
	game = GameScript.new()
	root.add_child(game)
	# _ready() won't fire in _init, so manually init sounds
	game._init_sounds()

	# Run all tests
	_test_upgrade_cost()
	_test_upgrade_duration()
	_test_tower_upgrade_cost()
	_test_attacker_multiplier()
	_test_defender_multiplier()
	_test_defender_multiplier_tower()
	_test_resolve_arrival_attacker_wins()
	_test_resolve_arrival_defender_holds()
	_test_resolve_arrival_equal_forces()
	_test_resolve_arrival_zero_defenders()
	_test_resolve_arrival_capture_resets_level()
	_test_resolve_arrival_capture_keeps_forge_level()
	_test_resolve_arrival_capture_keeps_tower_level()
	_test_check_win_neutral_all_player()
	_test_check_win_neutral_not_all()
	_test_check_win_ai_opponent_gone()
	_test_check_win_ai_player_gone()
	_test_check_win_ai_opponent_inflight()
	_test_unit_generation_normal()
	_test_unit_generation_forge_no_gen()
	_test_unit_generation_tower_no_gen()
	_test_unit_generation_cap()
	_test_unit_generation_level_speed()
	_test_send_units_basic()
	_test_send_units_non_player()
	_test_send_units_zero()
	_test_ease_out_cubic()

	# Report
	print("")
	print("========================================")
	print("Results: %d passed, %d failed" % [pass_count, fail_count])
	print("========================================")
	if fail_count > 0:
		quit(1)
	else:
		quit(0)

func assert_eq(actual, expected, test_name: String) -> void:
	if actual == expected:
		pass_count += 1
		print("  PASS: %s" % test_name)
	else:
		fail_count += 1
		print("  FAIL: %s — expected %s, got %s" % [test_name, str(expected), str(actual)])

func assert_true(condition: bool, test_name: String) -> void:
	if condition:
		pass_count += 1
		print("  PASS: %s" % test_name)
	else:
		fail_count += 1
		print("  FAIL: %s — expected true" % test_name)

func assert_approx(actual: float, expected: float, test_name: String, epsilon: float = 0.01) -> void:
	if absf(actual - expected) < epsilon:
		pass_count += 1
		print("  PASS: %s" % test_name)
	else:
		fail_count += 1
		print("  FAIL: %s — expected ~%s, got %s" % [test_name, str(expected), str(actual)])

# --- Helper to create a minimal building ---
func _make_building(id: int, owner: String, units: int, level: int = 1, type: String = "normal") -> Dictionary:
	return {
		"id": id,
		"position": Vector2(100, 100),
		"owner": owner,
		"units": units,
		"level": level,
		"max_capacity": 20 * level,
		"gen_timer": 0.0,
		"type": type,
		"upgrading": false,
		"upgrade_progress": 0.0,
		"upgrade_duration": 0.0,
		"shoot_timer": 0.0,
	}

func _reset_game() -> void:
	game.buildings.clear()
	game.unit_groups.clear()
	game.visual_effects.clear()
	game.game_won = false
	game.game_lost = false

# === Upgrade Cost/Duration Tests ===

func _test_upgrade_cost() -> void:
	print("Upgrade cost:")
	assert_eq(game._get_upgrade_cost(1), 5, "level 1 cost = 5")
	assert_eq(game._get_upgrade_cost(2), 10, "level 2 cost = 10")
	assert_eq(game._get_upgrade_cost(3), 20, "level 3 cost = 20")
	assert_eq(game._get_upgrade_cost(4), 999, "level 4 cost = 999")

func _test_upgrade_duration() -> void:
	print("Upgrade duration:")
	assert_approx(game._get_upgrade_duration(1), 5.0, "level 1 duration = 5.0")
	assert_approx(game._get_upgrade_duration(2), 10.0, "level 2 duration = 10.0")
	assert_approx(game._get_upgrade_duration(3), 15.0, "level 3 duration = 15.0")
	assert_approx(game._get_upgrade_duration(4), 999.0, "level 4 duration = 999.0")

func _test_tower_upgrade_cost() -> void:
	print("Tower upgrade cost:")
	assert_eq(game._get_tower_upgrade_cost(), 30, "tower cost = 30")

# === Multiplier Tests ===

func _test_attacker_multiplier() -> void:
	print("Attacker multiplier:")
	_reset_game()
	# No forges
	game.buildings.append(_make_building(0, "player", 10))
	assert_approx(game._get_attacker_multiplier("player"), 1.0, "0 forges = 1.0")

	# 1 forge
	game.buildings.append(_make_building(1, "player", 0, 1, "forge"))
	assert_approx(game._get_attacker_multiplier("player"), 1.1, "1 forge = 1.1")

	# 2 forges
	game.buildings.append(_make_building(2, "player", 0, 1, "forge"))
	assert_approx(game._get_attacker_multiplier("player"), 1.2, "2 forges = 1.2")

func _test_defender_multiplier() -> void:
	print("Defender multiplier (normal):")
	_reset_game()
	var b := _make_building(0, "player", 10, 1)
	game.buildings.append(b)
	# Normal level 1, 0 forges: (90 + 10 + 0) / 100 = 1.0
	assert_approx(game._get_defender_multiplier(b), 1.0, "level 1 no forge = 1.0")

	# Level 2, 0 forges: (90 + 20 + 0) / 100 = 1.1
	b["level"] = 2
	assert_approx(game._get_defender_multiplier(b), 1.1, "level 2 no forge = 1.1")

	# Level 2, 1 forge: (90 + 20 + 10) / 100 = 1.2
	game.buildings.append(_make_building(1, "player", 0, 1, "forge"))
	assert_approx(game._get_defender_multiplier(b), 1.2, "level 2 + 1 forge = 1.2")

func _test_defender_multiplier_tower() -> void:
	print("Defender multiplier (tower):")
	_reset_game()
	var b := _make_building(0, "player", 10, 1, "tower")
	game.buildings.append(b)
	assert_approx(game._get_defender_multiplier(b), 1.4, "tower level 1 = 1.4")
	b["level"] = 2
	assert_approx(game._get_defender_multiplier(b), 1.7, "tower level 2 = 1.7")
	b["level"] = 3
	assert_approx(game._get_defender_multiplier(b), 1.9, "tower level 3 = 1.9")
	b["level"] = 4
	assert_approx(game._get_defender_multiplier(b), 2.0, "tower level 4 = 2.0")

# === Combat Resolution Tests ===

func _test_resolve_arrival_attacker_wins() -> void:
	print("Combat - attacker wins:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 3))
	var group := {"count": 15, "source_id": 0, "target_id": 1, "owner": "player",
		"progress": 1.0, "speed": 150.0, "start_pos": Vector2(0, 0), "end_pos": Vector2(100, 100)}
	game._resolve_arrival(group)
	assert_eq(game.buildings[1]["owner"], "player", "target captured by attacker")
	assert_true(game.buildings[1]["units"] > 0, "attacker has remaining units")

func _test_resolve_arrival_defender_holds() -> void:
	print("Combat - defender holds:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 20))
	var group := {"count": 3, "source_id": 0, "target_id": 1, "owner": "player",
		"progress": 1.0, "speed": 150.0, "start_pos": Vector2(0, 0), "end_pos": Vector2(100, 100)}
	game._resolve_arrival(group)
	assert_eq(game.buildings[1]["owner"], "neutral", "defender keeps building")

func _test_resolve_arrival_equal_forces() -> void:
	print("Combat - equal forces (defender advantage):")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 10))
	var group := {"count": 10, "source_id": 0, "target_id": 1, "owner": "player",
		"progress": 1.0, "speed": 150.0, "start_pos": Vector2(0, 0), "end_pos": Vector2(100, 100)}
	game._resolve_arrival(group)
	assert_eq(game.buildings[1]["owner"], "neutral", "defender holds on equal forces")

func _test_resolve_arrival_zero_defenders() -> void:
	print("Combat - zero defenders:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 0))
	var group := {"count": 5, "source_id": 0, "target_id": 1, "owner": "player",
		"progress": 1.0, "speed": 150.0, "start_pos": Vector2(0, 0), "end_pos": Vector2(100, 100)}
	game._resolve_arrival(group)
	assert_eq(game.buildings[1]["owner"], "player", "attacker captures empty building")

func _test_resolve_arrival_capture_resets_level() -> void:
	print("Combat - capture resets level for normal:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 1, 3))
	var group := {"count": 20, "source_id": 0, "target_id": 1, "owner": "player",
		"progress": 1.0, "speed": 150.0, "start_pos": Vector2(0, 0), "end_pos": Vector2(100, 100)}
	game._resolve_arrival(group)
	assert_eq(game.buildings[1]["level"], 1, "normal building level reset to 1")

func _test_resolve_arrival_capture_keeps_forge_level() -> void:
	print("Combat - capture keeps forge level:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 1, 2, "forge"))
	var group := {"count": 20, "source_id": 0, "target_id": 1, "owner": "player",
		"progress": 1.0, "speed": 150.0, "start_pos": Vector2(0, 0), "end_pos": Vector2(100, 100)}
	game._resolve_arrival(group)
	assert_eq(game.buildings[1]["level"], 2, "forge level preserved on capture")

func _test_resolve_arrival_capture_keeps_tower_level() -> void:
	print("Combat - capture keeps tower level:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 1, 3, "tower"))
	var group := {"count": 20, "source_id": 0, "target_id": 1, "owner": "player",
		"progress": 1.0, "speed": 150.0, "start_pos": Vector2(0, 0), "end_pos": Vector2(100, 100)}
	game._resolve_arrival(group)
	assert_eq(game.buildings[1]["level"], 3, "tower level preserved on capture")

# === Win Condition Tests ===

func _test_check_win_neutral_all_player() -> void:
	print("Win condition - neutral all player:")
	_reset_game()
	game.current_mode = "neutral"
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "player", 5))
	game._check_win_condition()
	assert_true(game.game_won, "all player buildings = win")

func _test_check_win_neutral_not_all() -> void:
	print("Win condition - neutral not all:")
	_reset_game()
	game.current_mode = "neutral"
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 5))
	game._check_win_condition()
	assert_true(not game.game_won, "neutral building remaining = no win")

func _test_check_win_ai_opponent_gone() -> void:
	print("Win condition - AI opponent gone:")
	_reset_game()
	game.current_mode = "ai"
	game.buildings.append(_make_building(0, "player", 10))
	game.buildings.append(_make_building(1, "neutral", 5))
	game._check_win_condition()
	assert_true(game.game_won, "no opponent = win")

func _test_check_win_ai_player_gone() -> void:
	print("Win condition - AI player gone:")
	_reset_game()
	game.current_mode = "ai"
	game.buildings.append(_make_building(0, "opponent", 10))
	game._check_win_condition()
	assert_true(game.game_lost, "no player = lose")

func _test_check_win_ai_opponent_inflight() -> void:
	print("Win condition - AI opponent in-flight:")
	_reset_game()
	game.current_mode = "ai"
	game.buildings.append(_make_building(0, "player", 10))
	game.unit_groups.append({"owner": "opponent", "count": 5, "source_id": 0, "target_id": 0,
		"progress": 0.5, "speed": 150.0, "start_pos": Vector2.ZERO, "end_pos": Vector2(100, 100)})
	game._check_win_condition()
	assert_true(not game.game_won, "opponent in-flight = no win yet")

# === Unit Generation Tests ===

func _test_unit_generation_normal() -> void:
	print("Unit generation - normal:")
	_reset_game()
	var b := _make_building(0, "player", 5, 1)
	game.buildings.append(b)
	# Level 1: interval = 2.0s. After 2.1s should have gained 1 unit
	game._update_unit_generation(2.1)
	assert_eq(game.buildings[0]["units"], 6, "gained 1 unit after 2.1s at level 1")

func _test_unit_generation_forge_no_gen() -> void:
	print("Unit generation - forge no gen:")
	_reset_game()
	var b := _make_building(0, "player", 5, 1, "forge")
	game.buildings.append(b)
	game._update_unit_generation(10.0)
	assert_eq(game.buildings[0]["units"], 5, "forge does not generate")

func _test_unit_generation_tower_no_gen() -> void:
	print("Unit generation - tower no gen:")
	_reset_game()
	var b := _make_building(0, "player", 5, 1, "tower")
	game.buildings.append(b)
	game._update_unit_generation(10.0)
	assert_eq(game.buildings[0]["units"], 5, "tower does not generate")

func _test_unit_generation_cap() -> void:
	print("Unit generation - cap:")
	_reset_game()
	var b := _make_building(0, "player", 19, 1)
	game.buildings.append(b)
	# Level 1 cap = 20. After a long time, should cap at 20
	game._update_unit_generation(100.0)
	assert_eq(game.buildings[0]["units"], 20, "units capped at max_capacity")

func _test_unit_generation_level_speed() -> void:
	print("Unit generation - level speed:")
	_reset_game()
	var b1 := _make_building(0, "player", 0, 1)
	var b2 := _make_building(1, "player", 0, 2)
	game.buildings.append(b1)
	game.buildings.append(b2)
	# After 4.0s: level 1 interval=2.0 → 2 units, level 2 interval=1.0 → 4 units
	game._update_unit_generation(4.0)
	assert_eq(game.buildings[0]["units"], 2, "level 1: 2 units in 4s")
	assert_eq(game.buildings[1]["units"], 4, "level 2: 4 units in 4s")

# === Send Units Tests ===

func _test_send_units_basic() -> void:
	print("Send units - basic:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 20))
	game.buildings.append(_make_building(1, "neutral", 5))
	game.send_ratio = 0.5
	game._send_units(0, 1)
	assert_eq(game.buildings[0]["units"], 10, "source lost half units")
	assert_eq(game.unit_groups.size(), 1, "one unit group created")
	assert_eq(game.unit_groups[0]["count"], 10, "group has 10 units")

func _test_send_units_non_player() -> void:
	print("Send units - non-player rejected:")
	_reset_game()
	game.buildings.append(_make_building(0, "neutral", 20))
	game.buildings.append(_make_building(1, "player", 5))
	game.send_ratio = 0.5
	game._send_units(0, 1)
	assert_eq(game.buildings[0]["units"], 20, "neutral source unchanged")
	assert_eq(game.unit_groups.size(), 0, "no unit group created")

func _test_send_units_zero() -> void:
	print("Send units - zero count:")
	_reset_game()
	game.buildings.append(_make_building(0, "player", 1))
	game.buildings.append(_make_building(1, "neutral", 5))
	game.send_ratio = 0.25
	game._send_units(0, 1)
	# int(1 * 0.25) = 0, so nothing should happen
	assert_eq(game.buildings[0]["units"], 1, "source unchanged with zero send")
	assert_eq(game.unit_groups.size(), 0, "no unit group for zero send")

# === Utility Tests ===

func _test_ease_out_cubic() -> void:
	print("Ease out cubic:")
	assert_approx(game._ease_out_cubic(0.0), 0.0, "t=0 → 0")
	assert_approx(game._ease_out_cubic(1.0), 1.0, "t=1 → 1")
	assert_approx(game._ease_out_cubic(0.5), 0.875, "t=0.5 → 0.875")
