class_name GameCombat
extends RefCounted

var main

func _init(main_node) -> void:
	main = main_node

func resolve_arrival(unit_data: Dictionary) -> void:
	var target: Dictionary = main.buildings[unit_data["target_id"]]
	if target["owner"] == unit_data["owner"]:
		target["units"] += 1
	else:
		if main._has_hero_effect_on("fortify", unit_data["target_id"]) and target["owner"] == "player":
			return

		var A: float = 1.0
		var D: float = float(target["units"]) + get_fractional(target)
		var att_mult: float = get_attacker_multiplier(unit_data["owner"])
		var def_mult: float = get_defender_multiplier(target)
		var attacker_losses: float = D * def_mult / att_mult
		var defender_losses: float = A * att_mult / def_mult
		var attacker_remaining: float = A - attacker_losses
		var defender_remaining: float = D - defender_losses

		if defender_remaining >= attacker_remaining:
			var prev_units: int = target["units"]
			target["units"] = maxi(0, int(floor(defender_remaining)))
			target["units_fractional"] = defender_remaining - float(target["units"])
			target["fractional_timestamp"] = main.game_time
			if main.in_roguelike_run and unit_data["owner"] == "player":
				var killed: int = prev_units - target["units"]
				if killed > 0:
					main.hero_energy = minf(main.hero_energy + killed, main.hero_max_energy)
		else:
			target["units"] = maxi(1, int(floor(attacker_remaining)))
			target["units_fractional"] = attacker_remaining - float(target["units"])
			target["fractional_timestamp"] = main.game_time
			var old_owner: String = target["owner"]
			target["owner"] = unit_data["owner"]
			if target["type"] != "forge" and target["type"] != "tower":
				target["level"] = 1
			target["gen_timer"] = 0.0
			target["upgrading"] = false
			target["upgrade_progress"] = 0.0
			target["upgrade_duration"] = 0.0
			main.sfx_capture.play()
			if main.in_roguelike_run and unit_data["owner"] == "player" and old_owner != "player":
				main.hero_energy = minf(main.hero_energy + 8.0, main.hero_max_energy)
			main.visual_effects.append({
				"type": "capture_pop",
				"position": target["position"],
				"timer": 0.0,
				"duration": 0.4,
				"color": GameData.get_owner_color(unit_data["owner"]),
			})

func update_towers(delta: float) -> void:
	var units_to_remove: Array = []
	for b in main.buildings:
		if b["type"] != "tower":
			continue
		b["shoot_timer"] += delta
		var interval: float = GameData.get_tower_shoot_interval(b["level"])
		if b["shoot_timer"] < interval:
			continue
		b["shoot_timer"] -= interval
		var shoot_radius: float = GameData.get_tower_shoot_radius(b["level"])
		var best_idx: int = -1
		var best_dist: float = 99999.0
		for i in range(main.moving_units.size()):
			var u: Dictionary = main.moving_units[i]
			if u["owner"] == b["owner"]:
				continue
			if i in units_to_remove:
				continue
			var unit_pos: Vector2 = GameData.get_unit_position(u)
			var dist: float = b["position"].distance_to(unit_pos)
			if dist <= shoot_radius and dist < best_dist:
				best_dist = dist
				best_idx = i
		if best_idx != -1:
			var u: Dictionary = main.moving_units[best_idx]
			var target_pos: Vector2 = GameData.get_unit_position(u)
			main.visual_effects.append({
				"type": "tower_shot",
				"start": b["position"],
				"end": target_pos,
				"timer": 0.0,
				"duration": 0.2,
				"color": GameData.get_owner_color(b["owner"]),
			})
			units_to_remove.append(best_idx)
	units_to_remove.sort()
	units_to_remove.reverse()
	for idx in units_to_remove:
		main.moving_units.remove_at(idx)

func check_minefields() -> void:
	for fx in main.hero_active_effects:
		if fx["type"] != "minefield" or fx.get("triggered", false):
			continue
		var mid: Vector2 = fx["mid_pos"]
		var mine_radius: float = 40.0
		var units_to_remove: Array = []
		for i in range(main.moving_units.size()):
			var u: Dictionary = main.moving_units[i]
			if u["owner"] != "opponent":
				continue
			var unit_pos: Vector2 = u["start_pos"].lerp(u["end_pos"], u["progress"])
			if unit_pos.distance_to(mid) <= mine_radius:
				units_to_remove.append(i)
		if units_to_remove.size() > 0:
			fx["triggered"] = true
			var kill_count: int = maxi(1, int(units_to_remove.size() * 0.4))
			units_to_remove.shuffle()
			var killed: Array = units_to_remove.slice(0, kill_count)
			killed.sort()
			killed.reverse()
			for idx in killed:
				main.moving_units.remove_at(idx)
			main.visual_effects.append({
				"type": "capture_pop",
				"position": mid,
				"timer": 0.0,
				"duration": 0.6,
				"color": Color(1.0, 0.3, 0.1),
			})

func get_fractional(building: Dictionary) -> float:
	if main.game_time - building["fractional_timestamp"] >= 10.0:
		building["units_fractional"] = 0.0
		return 0.0
	return building["units_fractional"]

func count_forges_for_owner(owner: String) -> int:
	var count: int = 0
	for b in main.buildings:
		if b["type"] == "forge" and b["owner"] == owner:
			count += 1
	return count

func get_defender_multiplier(building: Dictionary) -> float:
	if building["type"] == "tower":
		return GameData.get_tower_defense_multiplier(building["level"])
	var forge_count: int = count_forges_for_owner(building["owner"])
	var defense_bonus: float = 0.0
	if main.in_roguelike_run and building["owner"] == "player":
		defense_bonus = 10.0 * main.run_upgrades.get("defense", 0)
	var base: float = (90.0 + building["level"] * 10.0 + forge_count * 10.0 + defense_bonus) / 100.0
	if building["owner"] == "player" and main._has_hero_effect_on("entrench", building["id"]):
		base *= 1.5
	return base

func get_attacker_multiplier(owner: String) -> float:
	var forge_count: int = count_forges_for_owner(owner)
	var attack_bonus: float = 0.0
	if main.in_roguelike_run and owner == "player":
		attack_bonus = 10.0 * main.run_upgrades.get("attack", 0)
	var base: float = (100.0 + forge_count * 10.0 + attack_bonus) / 100.0
	if owner == "player" and main._has_hero_effect("blitz"):
		base *= 2.0
	return base

func check_win_condition() -> void:
	if main.current_mode == "neutral":
		for b in main.buildings:
			if b["owner"] != "player":
				return
		main.game_won = true
	else:
		var has_player: bool = false
		var has_opponent: bool = false
		for b in main.buildings:
			if b["owner"] == "player":
				has_player = true
			elif b["owner"] == "opponent":
				has_opponent = true
		for u in main.moving_units:
			if u["owner"] == "player":
				has_player = true
			elif u["owner"] == "opponent":
				has_opponent = true
		for q in main.dispatch_queues:
			if q["owner"] == "player":
				has_player = true
			elif q["owner"] == "opponent":
				has_opponent = true
		if not has_opponent:
			main.game_won = true
		elif main.in_roguelike_run:
			if main.run_time_left <= 0.0 or not has_player:
				main.game_lost = true
		elif not has_player:
			main.game_lost = true
