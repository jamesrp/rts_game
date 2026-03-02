class_name GameRoguelike
extends RefCounted

var main

func _init(main_node) -> void:
	main = main_node

func format_run_time() -> String:
	var total_sec: int = int(ceil(main.run_time_left))
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%d:%02d" % [mins, secs]

func start_run() -> void:
	main.run_time_left = 600.0
	main.run_act = 1
	main.run_gold = 90
	main.run_upgrades = {"speed": 0, "attack": 0, "defense": 0}
	main.run_current_row = 0
	main.run_last_node = -1
	main.run_overlay = ""
	main.run_relics = []
	main.run_hero_upgrades = []
	main.campfire_upgrade_choices = []
	main.merchant_relics = []
	main.merchant_relics_bought = []
	main.reward_relics = []
	main.treasure_relic = ""
	main.current_event = {}
	main.event_result_text = ""
	main.first_power_used = false
	main.drain_field_timer = 0.0
	main.hero.reset_battle_state()
	main.run_map = _generate_run_map()
	main.run_map_scroll = clampf(main.run_map[0][0]["position"].y - 480.0, -50.0, 400.0)
	main.run_map_scroll_manual = false
	main.game_state = "roguelike_map"

func _generate_run_map() -> Array:
	var map: Array = []
	var row_counts: Array = [3, 3, 3, 3, 3, 3, 4, 3, 3, 3, 3, 4, 3, 3, 3, 1]

	# Create nodes with random types based on act distribution
	for row_idx in range(row_counts.size()):
		var row: Array = []
		var count: int = row_counts[row_idx]
		for col_idx in range(count):
			var node_type: String
			if row_idx == 15:
				node_type = "boss"
			else:
				node_type = _roll_map_node_type(row_idx)
			var x: float = GameData.get_map_node_x(col_idx, count)
			var y: float = 830.0 - row_idx * 50.0
			row.append({
				"type": node_type,
				"completed": false,
				"position": Vector2(x, y),
				"next_edges": [],
			})
		map.append(row)

	# Generate edges between adjacent rows
	for row_idx in range(map.size() - 1):
		var cur_row: Array = map[row_idx]
		var nxt_row: Array = map[row_idx + 1]
		var incoming: Array = []
		incoming.resize(nxt_row.size())
		for i in range(nxt_row.size()):
			incoming[i] = false

		for col_idx in range(cur_row.size()):
			var natural: int = int(float(col_idx) / float(cur_row.size()) * float(nxt_row.size()))
			natural = clampi(natural, 0, nxt_row.size() - 1)
			cur_row[col_idx]["next_edges"].append(natural)
			incoming[natural] = true
			if randf() < 0.5:
				var alt: int = natural + (1 if randf() < 0.5 else -1)
				alt = clampi(alt, 0, nxt_row.size() - 1)
				if alt != natural and alt not in cur_row[col_idx]["next_edges"]:
					cur_row[col_idx]["next_edges"].append(alt)
					incoming[alt] = true

		for i in range(nxt_row.size()):
			if not incoming[i]:
				var closest: int = clampi(int(float(i) / float(nxt_row.size()) * float(cur_row.size())), 0, cur_row.size() - 1)
				if i not in cur_row[closest]["next_edges"]:
					cur_row[closest]["next_edges"].append(i)

	# Override Rule 1: Floor 1 (index 0) = all monsters
	for node in map[0]:
		node["type"] = "battle"
	# Override Rule 1: Floor 9 (index 8) = all treasure
	for node in map[8]:
		node["type"] = "treasure"
	# Override Rule 1: Floor 15 (index 14) = all rest sites
	for node in map[14]:
		node["type"] = "campfire"

	# Override Rule 3: No elite or rest sites below floor 6 (indices 0-4)
	for row_idx in range(5):
		for node in map[row_idx]:
			if node["type"] == "elite" or node["type"] == "campfire":
				node["type"] = "battle"

	# Override Rule 2: No consecutive elite, merchant, or campfire
	var restricted_types: Array = ["elite", "merchant", "campfire"]
	var protected_rows: Array = [0, 8, 14, 15]
	for _pass in range(10):
		var changed: bool = false
		for row_idx in range(map.size() - 1):
			for col_idx in range(map[row_idx].size()):
				var node: Dictionary = map[row_idx][col_idx]
				if node["type"] not in restricted_types:
					continue
				for next_col in node["next_edges"]:
					var next_node: Dictionary = map[row_idx + 1][next_col]
					if next_node["type"] not in restricted_types:
						continue
					if row_idx + 1 not in protected_rows:
						next_node["type"] = "battle"
						changed = true
					elif row_idx not in protected_rows:
						node["type"] = "battle"
						changed = true
		if not changed:
			break

	return map

func _roll_map_node_type(floor_idx: int) -> String:
	var act: int = 1 + floor_idx / 5
	var roll: float = randf()
	if act == 1:
		# Elite 8%, Normal 53%, Event 22%, Campfire 12%, Merchant 5%
		if roll < 0.08: return "elite"
		roll -= 0.08
		if roll < 0.53: return "battle"
		roll -= 0.53
		if roll < 0.22: return "event"
		roll -= 0.22
		if roll < 0.12: return "campfire"
		return "merchant"
	else:
		# Elite 16%, Normal 45%, Event 22%, Campfire 12%, Merchant 5%
		if roll < 0.16: return "elite"
		roll -= 0.16
		if roll < 0.45: return "battle"
		roll -= 0.45
		if roll < 0.22: return "event"
		roll -= 0.22
		if roll < 0.12: return "campfire"
		return "merchant"

func _is_node_available(row: int, col: int) -> bool:
	if row != main.run_current_row:
		return false
	if main.run_map[row][col]["completed"]:
		return false
	if main.run_current_row == 0:
		return true
	# Check if any completed node in previous row connects here
	for prev_col in range(main.run_map[main.run_current_row - 1].size()):
		var prev_node: Dictionary = main.run_map[main.run_current_row - 1][prev_col]
		if prev_node["completed"] and col in prev_node["next_edges"]:
			return true
	return false

func start_battle(col: int) -> void:
	main.run_last_node = col
	var node_type: String = main.run_map[main.run_current_row][col]["type"]
	var is_elite: bool = node_type == "elite"
	var floor_idx: int = main.run_current_row  # 0-indexed
	var difficulty_factor: float = 1.0 + float(floor_idx) / 14.0  # 1.0 at floor 1, ~2.0 at floor 15
	var ai_level: int
	if node_type == "boss":
		ai_level = 4
	else:
		ai_level = 1 + floor_idx / 5  # 1 for floors 1-5, 2 for 6-10, 3 for 11-15
		ai_level = clampi(ai_level, 1, 4)
	main.in_roguelike_run = true
	main.is_elite_battle = is_elite
	var config: Dictionary = _generate_battle_map(ai_level, is_elite, difficulty_factor)
	main._start_level("ai", ai_level, config)

func return_from_battle() -> void:
	var won: bool = main.game_won
	main._reset_battle_state()
	main.hero.reset_battle_state()
	main.in_roguelike_run = false
	main.is_elite_battle = false

	if won:
		main.run_map[main.run_current_row][main.run_last_node]["completed"] = true
		var node_type_r: String = main.run_map[main.run_current_row][main.run_last_node]["type"]
		# Award gold based on node type
		match node_type_r:
			"boss": main.run_gold += randi_range(40, 60)
			"elite": main.run_gold += randi_range(25, 35)
			_: main.run_gold += randi_range(10, 20)
		# Gold Hoard: +5g per fight
		if main.has_relic("gold_hoard"):
			main.run_gold += 5
		var is_boss: bool = node_type_r == "boss"
		var is_elite: bool = node_type_r == "elite"
		if is_boss:
			main.reward_relics = GameRelics.get_boss_relics(main.run_relics)
			if main.reward_relics.size() > 0:
				main.run_overlay = "boss_reward"
			else:
				_advance_after_boss()
			main.game_state = "roguelike_map"
		elif is_elite:
			var elite_relic: String = GameRelics.get_elite_relic(main.run_hero, main.run_relics)
			if elite_relic != "":
				main.reward_relics = [elite_relic]
				main.run_overlay = "elite_reward"
			else:
				main.run_current_row += 1
			main.game_state = "roguelike_map"
		else:
			main.run_current_row += 1
			main.game_state = "roguelike_map"
	else:
		# Lost the battle — run is over
		main.run_overlay = "run_over"
		main.game_state = "roguelike_map"

func _advance_after_boss() -> void:
	main.run_overlay = "run_won"

func claim_relic(relic_id: String) -> void:
	if relic_id == "" or relic_id in main.run_relics:
		return
	main.run_relics.append(relic_id)
	# Immediate effects
	if relic_id == "temporal_flux":
		main.run_time_left += 90.0
	elif relic_id == "gold_hoard":
		main.run_gold += 50
	main.sfx_merchant[randi() % main.sfx_merchant.size()].play()

func abandon_run() -> void:
	main.game_state = "level_select"
	main.run_map.clear()

func handle_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and main.run_overlay == "":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			main.run_map_scroll -= 40.0
			main.run_map_scroll = clampf(main.run_map_scroll, -50.0, 400.0)
			main.run_map_scroll_manual = true
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			main.run_map_scroll += 40.0
			main.run_map_scroll = clampf(main.run_map_scroll, -50.0, 400.0)
			main.run_map_scroll_manual = true
			return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if main.run_overlay == "":
				abandon_run()
		return

	# Campfire overlay: handle rest/train clicks
	if main.run_overlay == "campfire":
		if GameData.CAMPFIRE_REST_RECT.has_point(event.position):
			main.run_time_left += 180.0  # restore 3:00
			main.run_time_left = minf(main.run_time_left, 600.0)
			main.sfx_click.play()
			main.run_map[main.run_current_row][main.run_last_node]["completed"] = true
			main.run_current_row += 1
			main.run_overlay = ""
			return
		if GameData.CAMPFIRE_TRAIN_RECT.has_point(event.position):
			if main.campfire_upgrade_choices.size() > 0:
				main.run_overlay = "campfire_train"
				main.sfx_click.play()
			return
		return

	# Campfire train overlay: pick an upgrade
	if main.run_overlay == "campfire_train":
		for i in range(main.campfire_upgrade_choices.size()):
			if GameData.get_campfire_upgrade_card_rect(i).has_point(event.position):
				var upgrade: Dictionary = main.campfire_upgrade_choices[i]
				main.run_hero_upgrades.append(upgrade["name"])
				main.sfx_merchant[randi() % main.sfx_merchant.size()].play()
				main.campfire_upgrade_choices.clear()
				main.run_map[main.run_current_row][main.run_last_node]["completed"] = true
				main.run_current_row += 1
				main.run_overlay = ""
				return
		return

	# Event overlay: handle choice clicks or dismiss result
	if main.run_overlay == "event":
		if main.event_result_text != "":
			# Result is showing — click anywhere to dismiss
			if GameData.EVENT_DISMISS_RECT.has_point(event.position):
				main.run_map[main.run_current_row][main.run_last_node]["completed"] = true
				main.run_current_row += 1
				main.run_overlay = ""
				main.current_event = {}
				main.event_result_text = ""
				main.sfx_click.play()
			return
		# Show choices
		if main.current_event.has("choices"):
			for i in range(main.current_event["choices"].size()):
				if GameData.get_event_choice_rect(i).has_point(event.position):
					var choice: Dictionary = main.current_event["choices"][i]
					main.event_result_text = apply_event_choice(choice["callback_id"])
					main.sfx_merchant[randi() % main.sfx_merchant.size()].play()
					return
		return

	# Merchant overlay: handle shop button clicks
	if main.run_overlay == "merchant":
		var item_keys := ["speed", "attack", "defense"]
		for i in range(3):
			if GameData.MERCHANT_BUY_RECTS[i].has_point(event.position) and main.run_gold >= 80:
				main.run_gold -= 80
				main.run_upgrades[item_keys[i]] += 1
				main.sfx_merchant[randi() % main.sfx_merchant.size()].play()
				return
		# Relic buy buttons
		for i in range(main.merchant_relics.size()):
			if GameData.get_merchant_relic_buy_rect(i).has_point(event.position):
				var relic_id: String = main.merchant_relics[i]
				if relic_id not in main.merchant_relics_bought and relic_id not in main.run_relics:
					var relic_data: Dictionary = GameRelics.RELICS[relic_id]
					if main.run_gold >= relic_data["cost"]:
						main.run_gold -= relic_data["cost"]
						claim_relic(relic_id)
						main.merchant_relics_bought.append(relic_id)
						return
		if GameData.MERCHANT_LEAVE_RECT.has_point(event.position):
			main.run_map[main.run_current_row][main.run_last_node]["completed"] = true
			main.run_current_row += 1
			main.run_overlay = ""
			main.sfx_click.play()
		return

	# Treasure overlay: click to claim relic and advance
	if main.run_overlay == "treasure":
		if GameData.TREASURE_CLAIM_RECT.has_point(event.position):
			if main.treasure_relic != "":
				claim_relic(main.treasure_relic)
			main.treasure_relic = ""
			main.run_map[main.run_current_row][main.run_last_node]["completed"] = true
			main.run_current_row += 1
			main.run_overlay = ""
			main.sfx_click.play()
		return

	# Elite reward overlay: click to claim
	if main.run_overlay == "elite_reward":
		if main.reward_relics.size() > 0:
			if GameData.ELITE_REWARD_CLAIM_RECT.has_point(event.position):
				claim_relic(main.reward_relics[0])
				main.reward_relics.clear()
				main.run_overlay = ""
				main.run_current_row += 1
		return

	# Boss reward overlay: click one of 3
	if main.run_overlay == "boss_reward":
		for i in range(main.reward_relics.size()):
			if GameData.get_boss_reward_card_rect(i).has_point(event.position):
				claim_relic(main.reward_relics[i])
				main.reward_relics.clear()
				main.run_overlay = ""
				_advance_after_boss()
				return
		return

	# If overlay is showing, click dismisses it
	if main.run_overlay == "run_over" or main.run_overlay == "run_won":
		main.game_state = "level_select"
		main.run_map.clear()
		main.run_overlay = ""
		return

	# Check node clicks
	if main.run_current_row >= main.run_map.size():
		return
	for col_idx in range(main.run_map[main.run_current_row].size()):
		var node: Dictionary = main.run_map[main.run_current_row][col_idx]
		var screen_pos: Vector2 = node["position"] - Vector2(0, main.run_map_scroll)
		if screen_pos.distance_to(event.position) <= 22.0 and _is_node_available(main.run_current_row, col_idx):
			main.sfx_click.play()
			if node["type"] == "merchant":
				main.run_last_node = col_idx
				main.merchant_relics = GameRelics.get_shop_relics(main.run_hero, main.run_relics)
				main.merchant_relics_bought = []
				main.run_overlay = "merchant"
			elif node["type"] == "campfire":
				main.run_last_node = col_idx
				main.campfire_upgrade_choices = get_campfire_upgrades()
				main.run_overlay = "campfire"
			elif node["type"] == "event":
				main.run_last_node = col_idx
				main.current_event = GameEvents.get_random_event()
				main.event_result_text = ""
				main.run_overlay = "event"
			elif node["type"] == "treasure":
				main.run_last_node = col_idx
				main.treasure_relic = GameRelics.get_elite_relic(main.run_hero, main.run_relics)
				main.run_overlay = "treasure"
			else:
				start_battle(col_idx)
			return

func _generate_battle_map(ai_level: int, is_elite: bool, difficulty_factor: float = 1.0) -> Dictionary:
	var node_count: int = randi_range(10, 14) + ai_level
	node_count = mini(node_count, 18)

	# Pick a layout strategy
	var strategies: Array = ["corridor", "ring", "clusters", "scattered"]
	var strategy: String = strategies[randi() % strategies.size()]

	var positions: Array = []
	var min_spacing: float = 80.0

	match strategy:
		"corridor":
			positions = GameData.gen_corridor_layout(node_count, min_spacing)
		"ring":
			positions = GameData.gen_ring_layout(node_count, min_spacing)
		"clusters":
			positions = GameData.gen_clusters_layout(node_count, min_spacing)
		_:
			positions = GameData.gen_scattered_layout(node_count, min_spacing)

	# Sort by distance from bottom-left — index 0 = player, last = opponent area
	positions.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_to(Vector2(50, 550)) < b.distance_to(Vector2(50, 550))
	)

	# Player is index 0 (closest to bottom-left)
	var player_indices: Array = [0]
	# Opponent is the farthest from bottom-left (last index)
	var opponent_indices: Array = [positions.size() - 1]

	# More opponent starting buildings for higher ai_level
	if ai_level >= 3 and positions.size() > 4:
		# Find second-farthest from bottom-left for second opponent base
		opponent_indices.append(positions.size() - 2)

	# Assign units
	var units: Array = []
	for i in range(positions.size()):
		if i in player_indices:
			units.append(20)
		elif i in opponent_indices:
			units.append(int((10 + ai_level * 1.5) * difficulty_factor))
		else:
			units.append(randi_range(5, 15))

	# Assign forges (2-3 among neutral positions)
	var neutral_indices: Array = []
	for i in range(positions.size()):
		if i not in player_indices and i not in opponent_indices:
			neutral_indices.append(i)
	neutral_indices.shuffle()
	var forge_count: int = randi_range(2, 3)
	var forges: Array = []
	for i in range(mini(forge_count, neutral_indices.size())):
		forges.append(neutral_indices[i])

	# Assign towers (1-2 among remaining neutrals)
	var remaining_neutrals: Array = []
	for i in neutral_indices:
		if i not in forges:
			remaining_neutrals.append(i)
	remaining_neutrals.shuffle()
	var tower_count: int = randi_range(1, 2)
	var towers: Array = []
	for i in range(mini(tower_count, remaining_neutrals.size())):
		towers.append(remaining_neutrals[i])

	return {"positions": positions, "units": units, "player_indices": player_indices,
		"opponent_indices": opponent_indices, "forges": forges, "towers": towers, "upgrades": {}}

func get_campfire_upgrades() -> Array:
	if main.run_hero == "" or not GameData.HERO_UPGRADES.has(main.run_hero):
		return []
	var all_upgrades: Array = GameData.HERO_UPGRADES[main.run_hero]
	var available: Array = []
	for u in all_upgrades:
		if u["name"] not in main.run_hero_upgrades:
			available.append(u)
	available.shuffle()
	var count: int = mini(3, available.size())
	return available.slice(0, count)

func apply_event_choice(callback_id: String) -> String:
	match callback_id:
		"nothing":
			return "You move on."
		"shrine_gamble":
			if randf() < 0.5:
				var relic_id: String = GameRelics.get_elite_relic(main.run_hero, main.run_relics)
				if relic_id != "":
					claim_relic(relic_id)
					var relic_name: String = GameRelics.RELICS[relic_id]["name"]
					return "The shrine glows! You found: " + relic_name
				else:
					main.run_gold += 80
					return "The shrine glows! You found 80 gold."
			else:
				main.run_time_left = maxf(0.0, main.run_time_left - 90.0)
				return "The shrine crumbles! You lost 1:30."
		"sell_time_60":
			main.run_time_left = maxf(0.0, main.run_time_left - 60.0)
			main.run_gold += 60
			return "You traded 1:00 for 60 gold."
		"sell_time_120":
			main.run_time_left = maxf(0.0, main.run_time_left - 120.0)
			main.run_gold += 130
			return "You traded 2:00 for 130 gold."
		"cache_gold":
			main.run_gold += 40
			return "You pocket the gold. +40 gold."
		"cache_time":
			main.run_time_left = minf(main.run_time_left + 60.0, 600.0)
			return "Supplies restored 1:00 of time."
		"collector_buy":
			if main.run_gold < 100:
				return "You don't have enough gold!"
			main.run_gold -= 100
			var relic_id: String = GameRelics.get_elite_relic(main.run_hero, main.run_relics)
			if relic_id != "":
				claim_relic(relic_id)
				var relic_name: String = GameRelics.RELICS[relic_id]["name"]
				return "You acquired: " + relic_name
			else:
				main.run_gold += 50
				return "Nothing good left... refunded 50 gold."
		"train_speed":
			main.run_upgrades["speed"] += 1
			return "Speed upgrade +1!"
		"train_attack":
			main.run_upgrades["attack"] += 1
			return "Attack upgrade +1!"
		"train_defense":
			main.run_upgrades["defense"] += 1
			return "Defense upgrade +1!"
		"blood_altar":
			main.run_time_left = maxf(0.0, main.run_time_left - 90.0)
			main.run_gold += 30
			var relic_id: String = GameRelics.get_elite_relic(main.run_hero, main.run_relics)
			if relic_id != "":
				claim_relic(relic_id)
				var relic_name: String = GameRelics.RELICS[relic_id]["name"]
				return "The altar accepts! " + relic_name + " + 30 gold."
			else:
				main.run_gold += 50
				return "The altar accepts! +80 gold total."
		_:
			return "Nothing happens."
