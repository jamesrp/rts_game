class_name GameHero
extends RefCounted

var main

# Effect lookup caches — rebuilt once per frame for O(1) lookups
var _effect_global_cache: Dictionary = {}  # {type: bool}
var _effect_cache: Dictionary = {}  # {"type:node_id": bool}

func _init(main_node) -> void:
	main = main_node

func rebuild_effect_cache() -> void:
	_effect_global_cache.clear()
	_effect_cache.clear()
	for fx in main.hero_active_effects:
		if fx["timer"] < fx["duration"]:
			_effect_global_cache[fx["type"]] = true
			var tid: int = fx.get("target_id", -1)
			if tid >= 0:
				_effect_cache[fx["type"] + ":" + str(tid)] = true

func update(delta: float) -> void:
	# Passive energy regen
	var energy_rate: float = main.hero_energy_rate
	if main.has_relic("capacitor"):
		energy_rate *= 1.25
	if main.has_relic("dynamo"):
		energy_rate *= 1.2
	if main.has_relic("overdrive"):
		energy_rate *= 1.5
	main.hero_energy = minf(main.hero_energy + energy_rate * delta, main.hero_max_energy)
	# Tick cooldowns
	for i in range(4):
		if main.hero_power_cooldowns[i] > 0.0:
			main.hero_power_cooldowns[i] = maxf(0.0, main.hero_power_cooldowns[i] - delta)
	# Update active effects - tick timers and apply periodic effects
	var effects_to_remove: Array = []
	for i in range(main.hero_active_effects.size()):
		var fx: Dictionary = main.hero_active_effects[i]
		fx["timer"] += delta
		# Supply Line periodic equalization
		if fx["type"] == "supply_line" and fx["timer"] < fx["duration"]:
			fx["equalize_timer"] = fx.get("equalize_timer", 0.0) + delta
			if fx["equalize_timer"] >= 2.0:
				fx["equalize_timer"] -= 2.0
				_apply_supply_line_equalize(fx)
		# Power Grid: each player node shares 10% garrison to weakest neighbor every 3s
		if fx["type"] == "nexus" and fx["timer"] < fx["duration"] and fx.get("power_grid", false):
			fx["grid_timer"] += delta
			if fx["grid_timer"] >= 3.0:
				fx["grid_timer"] -= 3.0
				for b in main.buildings:
					if b["owner"] == "player" and b["type"] != "forge" and b["type"] != "tower":
						var share: int = maxi(1, int(b["units"] * 0.1))
						if share > 0 and b["units"] > share:
							var weakest: Dictionary = {}
							var weakest_units: int = 999999
							for adj in main._get_adjacent_buildings(b["id"]):
								if adj["owner"] == "player" and adj["type"] != "forge" and adj["type"] != "tower" and adj["units"] < weakest_units:
									weakest_units = adj["units"]
									weakest = adj
							if not weakest.is_empty() and weakest["units"] < b["units"]:
								b["units"] -= share
								weakest["units"] += share
		# Sleeper Cell: convert 1 enemy unit every 3s
		if fx["type"] == "sleeper_cell" and fx["timer"] < fx["duration"]:
			fx["convert_timer"] += delta
			if fx["convert_timer"] >= 3.0:
				fx["convert_timer"] -= 3.0
				var tid: int = fx["target_id"]
				if tid >= 0 and tid < main.buildings.size() and main.buildings[tid]["owner"] == "opponent" and main.buildings[tid]["units"] > 0:
					main.buildings[tid]["units"] -= 1
					var nearest_id: int = -1
					var nearest_dist: float = INF
					for b in main.buildings:
						if b["owner"] == "player":
							var d: float = b["position"].distance_to(main.buildings[tid]["position"])
							if d < nearest_dist:
								nearest_dist = d
								nearest_id = b["id"]
					if nearest_id >= 0:
						main.moving_units.append({
							"source_id": tid,
							"target_id": nearest_id,
							"owner": "player",
							"progress": 0.0,
							"start_pos": main.buildings[tid]["position"],
							"end_pos": main.buildings[nearest_id]["position"],
							"lateral_offset": (randf() - 0.5) * 10.0,
						})
		if fx["timer"] >= fx["duration"]:
			effects_to_remove.append(i)
	GameData.remove_indices(main.hero_active_effects, effects_to_remove)

func reset_battle_state() -> void:
	main.hero_energy = 0.0
	main.hero_power_cooldowns = [0.0, 0.0, 0.0, 0.0]
	main.hero_active_effects.clear()
	main.hero_targeting_power = -1
	main.hero_supply_first_node = -1
	main.hero_minefield_source = -1
	main.first_power_used = false

func _apply_supply_line_equalize(fx: Dictionary) -> void:
	# Wormhole: equalize across all player nodes
	if fx.get("wormhole", false):
		var player_nodes: Array = []
		for b in main.buildings:
			if b["owner"] == "player" and b["type"] != "forge" and b["type"] != "tower":
				player_nodes.append(b)
		if player_nodes.size() < 2:
			return
		var total: int = 0
		for b in player_nodes:
			total += b["units"]
		var per_node: int = total / player_nodes.size()
		var remainder: int = total % player_nodes.size()
		for i in range(player_nodes.size()):
			player_nodes[i]["units"] = per_node + (1 if i < remainder else 0)
		return
	var id_a: int = fx["node_a"]
	var id_b: int = fx["node_b"]
	if id_a < 0 or id_a >= main.buildings.size() or id_b < 0 or id_b >= main.buildings.size():
		return
	var a: Dictionary = main.buildings[id_a]
	var b: Dictionary = main.buildings[id_b]
	if a["owner"] != "player" or b["owner"] != "player":
		return
	var total: int = a["units"] + b["units"]
	var half: int = total / 2
	a["units"] = half
	b["units"] = total - half

func try_activate_power(index: int) -> void:
	if main.run_hero == "" or not GameData.HERO_DATA.has(main.run_hero):
		return
	var powers: Array = GameData.HERO_DATA[main.run_hero]["powers"]
	if index < 0 or index >= powers.size():
		return
	var power: Dictionary = powers[index]
	var effective_cost: float = power["cost"]
	if main.has_relic("free_opener") and not main.first_power_used:
		effective_cost = 0.0
	elif main.has_relic("efficiency_core"):
		effective_cost *= 0.8
	if main.hero_energy < effective_cost or main.hero_power_cooldowns[index] > 0.0:
		return
	var targeting: String = power["targeting"]
	if targeting == "instant":
		_activate_power(index, -1)
	else:
		# Enter targeting mode
		main.hero_targeting_power = index
		main.hero_supply_first_node = -1
		main.hero_minefield_source = -1

func handle_target_click(pos: Vector2) -> void:
	if main.hero_targeting_power < 0 or main.run_hero == "":
		return
	var powers: Array = GameData.HERO_DATA[main.run_hero]["powers"]
	var power: Dictionary = powers[main.hero_targeting_power]
	var targeting: String = power["targeting"]
	var clicked_id: int = main._get_building_at(pos)

	if targeting == "any_node":
		if clicked_id >= 0:
			_activate_power(main.hero_targeting_power, clicked_id)
			main.hero_targeting_power = -1
	elif targeting == "friendly_node":
		if clicked_id >= 0 and main.buildings[clicked_id]["owner"] == "player":
			_activate_power(main.hero_targeting_power, clicked_id)
			main.hero_targeting_power = -1
	elif targeting == "enemy_node":
		if clicked_id >= 0 and main.buildings[clicked_id]["owner"] == "opponent":
			_activate_power(main.hero_targeting_power, clicked_id)
			main.hero_targeting_power = -1
	elif targeting == "friendly_node_pair":
		# Two-click: first friendly, then second friendly
		if clicked_id >= 0 and main.buildings[clicked_id]["owner"] == "player":
			if main.hero_supply_first_node < 0:
				main.hero_supply_first_node = clicked_id
			elif clicked_id != main.hero_supply_first_node:
				_activate_power_pair(main.hero_targeting_power, main.hero_supply_first_node, clicked_id)
				main.hero_targeting_power = -1
				main.hero_supply_first_node = -1
	elif targeting == "path":
		# Minefield: click two nodes to define path
		if clicked_id >= 0:
			if main.hero_minefield_source < 0:
				main.hero_minefield_source = clicked_id
			elif clicked_id != main.hero_minefield_source:
				_activate_power_pair(main.hero_targeting_power, main.hero_minefield_source, clicked_id)
				main.hero_targeting_power = -1
				main.hero_minefield_source = -1

func _pay_power_cost(index: int) -> void:
	var powers: Array = GameData.HERO_DATA[main.run_hero]["powers"]
	var power: Dictionary = powers[index]
	var actual_cost: float = power["cost"]
	if main.has_relic("free_opener") and not main.first_power_used:
		actual_cost = 0.0
		main.first_power_used = true
	elif main.has_relic("efficiency_core"):
		actual_cost *= 0.8
	main.hero_energy -= actual_cost
	if main.has_relic("feedback_loop") and actual_cost > 0:
		main.hero_energy = minf(main.hero_energy + actual_cost * 0.1, main.hero_max_energy)
	main.hero_power_cooldowns[index] = power["cooldown"]
	main.sfx_click.play()

	main.visual_effects.append({
		"type": "power_flash",
		"position": Vector2(GameData.SCREEN_W / 2, 40),
		"timer": 0.0,
		"duration": 0.5,
		"color": GameData.HERO_DATA[main.run_hero]["color"],
	})

func _activate_power(index: int, target_id: int) -> void:
	_pay_power_cost(index)

	match main.run_hero:
		"commander":
			match index:
				0: _power_rally_cry(target_id)
				1: _power_forced_march()
				2: _power_conscription()
				3: _power_blitz()
		"warden":
			match index:
				0: _power_fortify(target_id)
				1: _power_entrench(target_id)
				3: _power_citadel(target_id)
		"saboteur":
			match index:
				0: _power_sabotage(target_id)
				1: _power_blackout()
				2: _power_turncoat(target_id)
				3: _power_emp()
		"architect":
			match index:
				0: _power_overclock(target_id)
				2: _power_terraform(target_id)
				3: _power_nexus()

func _activate_power_pair(index: int, node_a: int, node_b: int) -> void:
	_pay_power_cost(index)

	match main.run_hero:
		"warden":
			if index == 2: _power_minefield(node_a, node_b)
		"architect":
			if index == 1: _power_supply_line(node_a, node_b)

# === Hero Power Implementations ===

# Commander powers
func _power_rally_cry(target_id: int) -> void:
	var rolling_thunder: bool = main.has_hero_upgrade("Rolling Thunder")
	for b in main.buildings:
		if b["owner"] == "player" and b["id"] != target_id and b["type"] != "forge" and b["type"] != "tower":
			var rally_pct: float = 0.5 if main.has_relic("warchief_banner") else 0.3
			var send_count: int = int(b["units"] * rally_pct)
			if send_count > 0:
				main.dispatch_queues.append({
					"source_id": b["id"],
					"target_id": target_id,
					"owner": "player",
					"remaining": send_count,
					"wave_timer": 0.0,
					"start_pos": b["position"],
					"end_pos": main.buildings[target_id]["position"],
				})
			# Rolling Thunder: second wave of 20%
			if rolling_thunder:
				var wave2: int = int(b["units"] * 0.2)
				if wave2 > 0:
					main.dispatch_queues.append({
						"source_id": b["id"],
						"target_id": target_id,
						"owner": "player",
						"remaining": wave2,
						"wave_timer": 2.0,
						"start_pos": b["position"],
						"end_pos": main.buildings[target_id]["position"],
					})

func _power_forced_march() -> void:
	main.hero_active_effects.append({
		"type": "forced_march",
		"timer": 0.0,
		"duration": 8.0,
		"double_time": main.has_hero_upgrade("Double Time"),
	})

func _power_conscription() -> void:
	var war_economy: bool = main.has_hero_upgrade("War Economy")
	for b in main.buildings:
		if b["owner"] == "player" and b["type"] != "forge" and b["type"] != "tower":
			var bonus: int = b["level"] * 3
			if war_economy:
				bonus += b["level"] * 2
			b["units"] += bonus

func _power_blitz() -> void:
	var dur: float = 18.0 if main.has_relic("shock_doctrine") else 12.0
	main.hero_active_effects.append({
		"type": "blitz",
		"timer": 0.0,
		"duration": dur,
		"scorched_earth": main.has_hero_upgrade("Scorched Earth"),
	})

# Warden powers
func _power_fortify(target_id: int) -> void:
	var dur: float = 14.0 if main.has_relic("reinforced_walls") else 8.0
	main.hero_active_effects.append({
		"type": "fortify",
		"timer": 0.0,
		"duration": dur,
		"target_id": target_id,
		"reactive_armor": main.has_hero_upgrade("Reactive Armor"),
	})
	if main.has_relic("reinforced_walls") and target_id >= 0 and target_id < main.buildings.size():
		main.buildings[target_id]["units"] += 5

func _power_entrench(target_id: int) -> void:
	main.hero_active_effects.append({
		"type": "entrench",
		"timer": 0.0,
		"duration": 15.0,
		"target_id": target_id,
		"bunker_down": main.has_hero_upgrade("Bunker Down"),
	})

func _power_minefield(node_a: int, node_b: int) -> void:
	var pos_a: Vector2 = main.buildings[node_a]["position"]
	var pos_b: Vector2 = main.buildings[node_b]["position"]
	main.hero_active_effects.append({
		"type": "minefield",
		"timer": 0.0,
		"duration": 60.0,  # Long duration, but one-shot
		"node_a": node_a,
		"node_b": node_b,
		"mid_pos": (pos_a + pos_b) / 2.0,
		"triggered": false,
		"chain_mines": main.has_hero_upgrade("Chain Mines"),
	})

func _power_citadel(target_id: int) -> void:
	main.hero_active_effects.append({
		"type": "citadel",
		"timer": 0.0,
		"duration": 20.0,
		"target_id": target_id,
	})
	# Iron Curtain: spread citadel bonus to adjacent nodes at 50% (as citadel_spread)
	if main.has_hero_upgrade("Iron Curtain"):
		for adj in main._get_adjacent_buildings(target_id):
			if adj["owner"] == "player" and adj["type"] != "forge" and adj["type"] != "tower":
				main.hero_active_effects.append({
					"type": "citadel_spread",
					"timer": 0.0,
					"duration": 20.0,
					"target_id": adj["id"],
				})

# Saboteur powers
func _power_sabotage(target_id: int) -> void:
	var dur: float = 20.0 if main.has_relic("deep_cover") else 12.0
	main.hero_active_effects.append({
		"type": "sabotage",
		"timer": 0.0,
		"duration": dur,
		"target_id": target_id,
	})
	if main.has_relic("deep_cover") and target_id >= 0 and target_id < main.buildings.size():
		main.buildings[target_id]["units"] = main.buildings[target_id]["units"] / 2
	# Rolling Blackout: spread to 1 adjacent enemy node
	if main.has_hero_upgrade("Rolling Blackout"):
		var adj_enemies: Array = []
		for adj in main._get_adjacent_buildings(target_id):
			if adj["owner"] == "opponent" and adj["id"] != target_id:
				adj_enemies.append(adj)
		if adj_enemies.size() > 0:
			var spread_target: Dictionary = adj_enemies[randi() % adj_enemies.size()]
			main.hero_active_effects.append({
				"type": "sabotage",
				"timer": 0.0,
				"duration": dur * 0.5,
				"target_id": spread_target["id"],
			})

func _power_blackout() -> void:
	main.hero_active_effects.append({
		"type": "blackout",
		"timer": 0.0,
		"duration": 10.0,
		"quicksand": main.has_hero_upgrade("Quicksand"),
	})

func _power_turncoat(target_id: int) -> void:
	var target: Dictionary = main.buildings[target_id]
	var convert_pct: float = 0.5 if main.has_relic("double_agent") else 0.3
	var convert_count: int = int(target["units"] * convert_pct)
	if convert_count > 0:
		target["units"] -= convert_count
		# Send converted units to nearest player building
		var nearest_id: int = -1
		var nearest_dist: float = INF
		for b in main.buildings:
			if b["owner"] == "player":
				var d: float = b["position"].distance_to(target["position"])
				if d < nearest_dist:
					nearest_dist = d
					nearest_id = b["id"]
		if nearest_id >= 0:
			for _i in range(convert_count):
				main.moving_units.append({
					"source_id": target_id,
					"target_id": nearest_id,
					"owner": "player",
					"progress": 0.0,
					"start_pos": target["position"],
					"end_pos": main.buildings[nearest_id]["position"],
					"lateral_offset": (randf() - 0.5) * 10.0,
				})
	# Sleeper Cell: keep converting 1 unit every 3s for 15s
	if main.has_hero_upgrade("Sleeper Cell") and target["owner"] == "opponent":
		main.hero_active_effects.append({
			"type": "sleeper_cell",
			"timer": 0.0,
			"duration": 15.0,
			"target_id": target_id,
			"convert_timer": 0.0,
		})

func _power_emp() -> void:
	main.hero_active_effects.append({
		"type": "emp",
		"timer": 0.0,
		"duration": 10.0,
		"total_shutdown": main.has_hero_upgrade("Total Shutdown"),
	})
	# Total Shutdown: also drain 30% of all enemy garrisons
	if main.has_hero_upgrade("Total Shutdown"):
		for b in main.buildings:
			if b["owner"] == "opponent" and b["type"] != "forge" and b["type"] != "tower":
				b["units"] = maxi(0, b["units"] - int(b["units"] * 0.3))

# Architect powers
func _power_overclock(target_id: int) -> void:
	main.hero_active_effects.append({
		"type": "overclock",
		"timer": 0.0,
		"duration": 12.0,
		"target_id": target_id,
	})
	# Overdrive: spread overclock to adjacent nodes at 50% (1.5x gen)
	if main.has_hero_upgrade("Overdrive"):
		for adj in main._get_adjacent_buildings(target_id):
			if adj["owner"] == "player" and adj["type"] != "forge" and adj["type"] != "tower":
				main.hero_active_effects.append({
					"type": "overclock_spread",
					"timer": 0.0,
					"duration": 12.0,
					"target_id": adj["id"],
				})

func _power_supply_line(node_a: int, node_b: int) -> void:
	var dur: float = 25.0 if main.has_relic("grid_link") else 15.0
	main.hero_active_effects.append({
		"type": "supply_line",
		"timer": 0.0,
		"duration": dur,
		"node_a": node_a,
		"node_b": node_b,
		"equalize_timer": 0.0,
		"wormhole": main.has_hero_upgrade("Wormhole"),
	})

func _power_terraform(target_id: int) -> void:
	var b: Dictionary = main.buildings[target_id]
	if b["type"] != "forge" and b["type"] != "tower":
		var tf_amount: int = 3 if main.has_relic("rapid_expansion") else 2
		b["level"] = mini(b["level"] + tf_amount, GameData.MAX_BUILDING_LEVEL)
		b["max_capacity"] = GameData.BASE_CAPACITY * b["level"]
		# Deep Foundations: mark node so it keeps +1 level even if captured and recaptured
		if main.has_hero_upgrade("Deep Foundations"):
			b["deep_foundations"] = true
			b["min_level"] = maxi(b.get("min_level", 1), mini(b["level"], 2))
		main.sfx_upgrade.play()

func _power_nexus() -> void:
	main.hero_active_effects.append({
		"type": "nexus",
		"timer": 0.0,
		"duration": 15.0,
		"power_grid": main.has_hero_upgrade("Power Grid"),
		"grid_timer": 0.0,
	})

func has_effect(effect_type: String) -> bool:
	return _effect_global_cache.has(effect_type)

func has_effect_on(effect_type: String, node_id: int) -> bool:
	return _effect_cache.has(effect_type + ":" + str(node_id))
