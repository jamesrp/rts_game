extends Node2D

# === Game State Machine ===
var game_state: String = "level_select"  # "level_select" or "playing"
var current_mode: String = ""  # "neutral" or "ai"
var current_level: int = 0

# === Building Data ===
var buildings: Array = []
# Each building: {id, position, owner, units, level, max_capacity, gen_timer, upgrading, upgrade_progress, upgrade_duration, units_fractional, fractional_timestamp}

# === Dispatch Queues & Moving Units ===
var dispatch_queues: Array = []
# Each queue: {source_id, target_id, owner, remaining, wave_timer, start_pos, end_pos}
var moving_units: Array = []
# Each unit: {source_id, target_id, owner, progress, start_pos, end_pos}

# === Selection State ===
var selected_building_id: int = -1

# === Drag State ===
var is_dragging: bool = false
var drag_source_id: int = -1
var drag_current_pos: Vector2 = Vector2.ZERO

# === Send Ratio ===
var send_ratio: float = 0.5
var ratio_options: Array = [0.25, 0.5, 0.75, 1.0]
var ratio_labels: Array = ["25%", "50%", "75%", "100%"]

# === Context Menu State ===
var context_menu_building_id: int = -1
var context_menu_options: Array = []  # [{rect, label, action, enabled}]

# === Game State ===
var game_won: bool = false
var game_lost: bool = false
var game_time: float = 0.0

# === Visual Effects ===
var visual_effects: Array = []

# === AI State ===
var ai_timer: float = 0.0

# === Roguelike Run State ===
var in_roguelike_run: bool = false
var run_time_left: float = 600.0  # seconds; 10:00 starting total
var run_act: int = 1
var run_gold: int = 0
var run_upgrades: Dictionary = {"speed": 0, "attack": 0, "defense": 0}
var run_map: Array = []  # Array of rows, each row is array of node dicts
var run_current_row: int = 0
var run_last_node: int = -1  # Column index chosen in current row
var run_overlay: String = ""  # "", "run_over", "run_won", "merchant", "elite_reward", "boss_reward", "campfire"
var campfire_upgrade_choices: Array = []  # Array of upgrade dicts offered at campfire
var run_hero_upgrades: Array = []  # Upgrade IDs (names) acquired during run
var run_relics: Array = []
var merchant_relics: Array = []
var merchant_relics_bought: Array = []
var reward_relics: Array = []
var first_power_used: bool = false
var drain_field_timer: float = 0.0

# === Hero System ===
var run_hero: String = ""  # "commander", "warden", "saboteur", "architect"
var hero_energy: float = 0.0
var hero_max_energy: float = 100.0
var hero_energy_rate: float = 2.0  # per second passive
var hero_power_cooldowns: Array = [0.0, 0.0, 0.0, 0.0]
var hero_active_effects: Array = []  # [{type, timer, duration, ...}]
var hero_targeting_power: int = -1  # power index awaiting target click
var hero_supply_first_node: int = -1  # for Supply Line two-click targeting
var hero_minefield_source: int = -1  # for Minefield path targeting

# === Mouse State ===
var mouse_pos: Vector2 = Vector2.ZERO

# === Level Select UI ===
var level_buttons: Array = []
# Each: {rect: Rect2, mode: String, level: int, label: String}

# === Sound Players ===
var sfx_click: AudioStreamPlayer
var sfx_whoosh: AudioStreamPlayer
var sfx_capture: AudioStreamPlayer
var sfx_upgrade: AudioStreamPlayer
var sfx_merchant: Array[AudioStreamPlayer] = []

# === Module References ===
var combat: GameCombat
var ui: GameUI

func _ready() -> void:
	combat = GameCombat.new(self)
	ui = GameUI.new(self)
	_build_level_select_buttons()
	_init_sounds()

func _build_level_select_buttons() -> void:
	level_buttons.clear()
	var cx: float = 400.0
	var start_y: float = 180.0
	var btn_w: float = 220.0
	var btn_h: float = 48.0
	var gap: float = 12.0

	# Neutral mode column (left)
	var left_x: float = cx - btn_w - 30.0
	for i in range(4):
		level_buttons.append({
			"rect": Rect2(left_x, start_y + i * (btn_h + gap), btn_w, btn_h),
			"mode": "neutral",
			"level": i + 1,
			"label": "Level %d" % (i + 1),
		})

	# AI mode column (right)
	var right_x: float = cx + 30.0
	var ai_labels: Array = ["Level 1 - Novice", "Level 2 - Expander", "Level 3 - Aggressor", "Level 4 - General"]
	for i in range(4):
		level_buttons.append({
			"rect": Rect2(right_x, start_y + i * (btn_h + gap), btn_w, btn_h),
			"mode": "ai",
			"level": i + 1,
			"label": ai_labels[i],
		})

	# Roguelike button (centered below both columns)
	level_buttons.append({
		"rect": Rect2(cx - 120, start_y + 4 * (btn_h + gap) + 30, 240, 52),
		"mode": "roguelike",
		"level": 0,
		"label": "Start Run",
	})

func _load_sfx(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	player.stream = load(path)
	add_child(player)
	return player

func _init_sounds() -> void:
	sfx_click   = _load_sfx("res://sounds/788611__el_boss__ui-button-press.wav")
	sfx_whoosh  = _load_sfx("res://sounds/840717__nomagician__sword-swing-3.mp3")
	sfx_capture = _load_sfx("res://sounds/843251__qubodup__explosion-5-burning-car-rec-by-nado.wav")
	sfx_upgrade = _load_sfx("res://sounds/732254__waveadventurer__positive-warbly-ascending-thingy.wav")
	sfx_merchant.append(_load_sfx("res://sounds/665183__el_boss__item-or-material-pickup-pop-1-of-3.wav"))
	sfx_merchant.append(_load_sfx("res://sounds/665182__el_boss__item-or-material-pickup-pop-2-of-3.wav"))
	sfx_merchant.append(_load_sfx("res://sounds/665181__el_boss__item-or-material-pickup-pop-3-of-3.wav"))

# === Roguelike Run ===

func _format_run_time() -> String:
	var total_sec: int = int(ceil(run_time_left))
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%d:%02d" % [mins, secs]

func _start_roguelike_run() -> void:
	run_time_left = 600.0
	run_act = 1
	run_gold = 90
	run_upgrades = {"speed": 0, "attack": 0, "defense": 0}
	run_current_row = 0
	run_last_node = -1
	run_overlay = ""
	run_relics = []
	run_hero_upgrades = []
	campfire_upgrade_choices = []
	merchant_relics = []
	merchant_relics_bought = []
	reward_relics = []
	first_power_used = false
	drain_field_timer = 0.0
	_reset_hero_battle_state()
	run_map = _generate_run_map(run_act)
	game_state = "roguelike_map"

func _generate_run_map(act: int) -> Array:
	var map: Array = []
	var row_counts: Array = [3, 3, 4, 3, 1]

	for row_idx in range(row_counts.size()):
		var row: Array = []
		var count: int = row_counts[row_idx]
		for col_idx in range(count):
			var node_type: String
			if row_idx == row_counts.size() - 1:
				node_type = "boss"
			else:
				node_type = "battle"
			var x: float = GameData.get_map_node_x(col_idx, count)
			var y: float = 500.0 - row_idx * 95.0
			row.append({
				"type": node_type,
				"completed": false,
				"position": Vector2(x, y),
				"next_edges": [],
			})
		map.append(row)

	# Assign 1-2 elite nodes in middle rows (rows 1-2, i.e. map rows II-III)
	var elite_candidates: Array = []  # [row_idx, col_idx] pairs
	for row_idx in [1, 2]:
		if row_idx < map.size():
			for col_idx in range(map[row_idx].size()):
				if map[row_idx][col_idx]["type"] == "battle":
					elite_candidates.append([row_idx, col_idx])
	elite_candidates.shuffle()
	var elite_count: int = 1 + (randi() % 2)  # 1 or 2
	for i in range(mini(elite_count, elite_candidates.size())):
		var rc: Array = elite_candidates[i]
		map[rc[0]][rc[1]]["type"] = "elite"

	# Assign 1 merchant node in a middle row (rows 1-3, not row 0 or boss row)
	var merchant_candidates: Array = []
	for row_idx in [1, 2, 3]:
		if row_idx < map.size() - 1:  # not boss row
			for col_idx in range(map[row_idx].size()):
				if map[row_idx][col_idx]["type"] == "battle":
					merchant_candidates.append([row_idx, col_idx])
	merchant_candidates.shuffle()
	if merchant_candidates.size() > 0:
		var mc: Array = merchant_candidates[0]
		map[mc[0]][mc[1]]["type"] = "merchant"

	# Assign 1 campfire node in middle rows (rows 1-3, not row 0 or boss row)
	var campfire_candidates: Array = []
	for row_idx in [1, 2, 3]:
		if row_idx < map.size() - 1:
			for col_idx in range(map[row_idx].size()):
				if map[row_idx][col_idx]["type"] == "battle":
					campfire_candidates.append([row_idx, col_idx])
	campfire_candidates.shuffle()
	if campfire_candidates.size() > 0:
		var cc: Array = campfire_candidates[0]
		map[cc[0]][cc[1]]["type"] = "campfire"

	# Generate edges between adjacent rows
	for row_idx in range(map.size() - 1):
		var cur_row: Array = map[row_idx]
		var nxt_row: Array = map[row_idx + 1]
		var incoming: Array = []
		incoming.resize(nxt_row.size())
		for i in range(nxt_row.size()):
			incoming[i] = false

		for col_idx in range(cur_row.size()):
			# Natural mapping based on position ratio
			var natural: int = int(float(col_idx) / float(cur_row.size()) * float(nxt_row.size()))
			natural = clampi(natural, 0, nxt_row.size() - 1)
			cur_row[col_idx]["next_edges"].append(natural)
			incoming[natural] = true
			# 50% chance to also connect to an adjacent node
			if randf() < 0.5:
				var alt: int = natural + (1 if randf() < 0.5 else -1)
				alt = clampi(alt, 0, nxt_row.size() - 1)
				if alt != natural and alt not in cur_row[col_idx]["next_edges"]:
					cur_row[col_idx]["next_edges"].append(alt)
					incoming[alt] = true

		# Ensure every next-row node has at least one incoming edge
		for i in range(nxt_row.size()):
			if not incoming[i]:
				var closest: int = clampi(int(float(i) / float(nxt_row.size()) * float(cur_row.size())), 0, cur_row.size() - 1)
				if i not in cur_row[closest]["next_edges"]:
					cur_row[closest]["next_edges"].append(i)

	return map

func _is_node_available(row: int, col: int) -> bool:
	if row != run_current_row:
		return false
	if run_map[row][col]["completed"]:
		return false
	if run_current_row == 0:
		return true
	# Check if any completed node in previous row connects here
	for prev_col in range(run_map[run_current_row - 1].size()):
		var prev_node: Dictionary = run_map[run_current_row - 1][prev_col]
		if prev_node["completed"] and col in prev_node["next_edges"]:
			return true
	return false

func _start_roguelike_battle(col: int) -> void:
	run_last_node = col
	var node_type: String = run_map[run_current_row][col]["type"]
	var is_elite: bool = node_type == "elite"
	var ai_level: int
	if node_type == "boss":
		ai_level = clampi(run_act + 1, 2, 4)
	else:
		match run_act:
			1: ai_level = 1 + (randi() % 2)
			2: ai_level = 2 + (randi() % 2)
			_: ai_level = 3 + (randi() % 2)
		# Later rows within an act push toward higher difficulty
		ai_level += run_current_row / 2
		ai_level = clampi(ai_level, 1, 4)
	in_roguelike_run = true
	var config: Dictionary = _generate_roguelike_battle_map(ai_level, is_elite)
	_start_level("ai", ai_level, config)

func _return_from_roguelike_battle() -> void:
	var won: bool = game_won
	# Clean up battle state
	buildings.clear()
	dispatch_queues.clear()
	moving_units.clear()
	visual_effects.clear()
	hero_active_effects.clear()
	hero_targeting_power = -1
	hero_supply_first_node = -1
	hero_minefield_source = -1
	context_menu_building_id = -1
	context_menu_options.clear()
	in_roguelike_run = false

	if won:
		run_map[run_current_row][run_last_node]["completed"] = true
		var node_type_r: String = run_map[run_current_row][run_last_node]["type"]
		# Award gold based on node type
		match node_type_r:
			"boss": run_gold += randi_range(40, 60)
			"elite": run_gold += randi_range(25, 35)
			_: run_gold += randi_range(10, 20)
		# Gold Hoard: +5g per fight
		if has_relic("gold_hoard"):
			run_gold += 5
		var is_boss: bool = node_type_r == "boss"
		var is_elite: bool = node_type_r == "elite"
		if is_boss:
			reward_relics = GameRelics.get_boss_relics(run_relics)
			if reward_relics.size() > 0:
				run_overlay = "boss_reward"
			else:
				_advance_after_boss()
			game_state = "roguelike_map"
		elif is_elite:
			var elite_relic: String = GameRelics.get_elite_relic(run_hero, run_relics)
			if elite_relic != "":
				reward_relics = [elite_relic]
				run_overlay = "elite_reward"
			else:
				run_current_row += 1
			game_state = "roguelike_map"
		else:
			run_current_row += 1
			game_state = "roguelike_map"
	else:
		# Lost the battle — run is over
		run_overlay = "run_over"
		game_state = "roguelike_map"

func _advance_after_boss() -> void:
	if run_act >= 3:
		run_overlay = "run_won"
	else:
		run_act += 1
		run_time_left = 600.0
		run_map = _generate_run_map(run_act)
		run_current_row = 0
		run_last_node = -1

func _claim_relic(relic_id: String) -> void:
	if relic_id == "" or relic_id in run_relics:
		return
	run_relics.append(relic_id)
	# Immediate effects
	if relic_id == "temporal_flux":
		run_time_left += 90.0
	elif relic_id == "gold_hoard":
		run_gold += 50
	sfx_merchant[randi() % sfx_merchant.size()].play()

func _abandon_roguelike_run() -> void:
	game_state = "level_select"
	run_map.clear()

func _input_roguelike_map(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if run_overlay == "":
				_abandon_roguelike_run()
		return

	# Campfire overlay: handle rest/train clicks
	if run_overlay == "campfire":
		var rest_rect := Rect2(220, 250, 160, 60)
		var train_rect := Rect2(420, 250, 160, 60)
		if rest_rect.has_point(event.position):
			run_time_left += 180.0  # restore 3:00
			run_time_left = minf(run_time_left, 600.0)
			sfx_click.play()
			run_map[run_current_row][run_last_node]["completed"] = true
			run_current_row += 1
			run_overlay = ""
			return
		if train_rect.has_point(event.position):
			if campfire_upgrade_choices.size() > 0:
				run_overlay = "campfire_train"
				sfx_click.play()
			return
		return

	# Campfire train overlay: pick an upgrade
	if run_overlay == "campfire_train":
		for i in range(campfire_upgrade_choices.size()):
			var card_x: float = 115.0 + i * 200.0
			var card_rect := Rect2(card_x, 220, 170, 160)
			if card_rect.has_point(event.position):
				var upgrade: Dictionary = campfire_upgrade_choices[i]
				run_hero_upgrades.append(upgrade["name"])
				sfx_merchant[randi() % sfx_merchant.size()].play()
				campfire_upgrade_choices.clear()
				run_map[run_current_row][run_last_node]["completed"] = true
				run_current_row += 1
				run_overlay = ""
				return
		return

	# Merchant overlay: handle shop button clicks
	if run_overlay == "merchant":
		var item_keys := ["speed", "attack", "defense"]
		var buy_rects := [Rect2(370, 214, 160, 32), Rect2(370, 269, 160, 32), Rect2(370, 324, 160, 32)]
		for i in range(3):
			if buy_rects[i].has_point(event.position) and run_gold >= 80:
				run_gold -= 80
				run_upgrades[item_keys[i]] += 1
				sfx_merchant[randi() % sfx_merchant.size()].play()
				return
		# Relic buy buttons
		for i in range(merchant_relics.size()):
			var relic_buy_rect := Rect2(370, 389 + i * 55, 160, 32)
			if relic_buy_rect.has_point(event.position):
				var relic_id: String = merchant_relics[i]
				if relic_id not in merchant_relics_bought and relic_id not in run_relics:
					var relic_data: Dictionary = GameRelics.RELICS[relic_id]
					if run_gold >= relic_data["cost"]:
						run_gold -= relic_data["cost"]
						_claim_relic(relic_id)
						merchant_relics_bought.append(relic_id)
						return
		var leave_rect := Rect2(305, 506, 190, 34)
		if leave_rect.has_point(event.position):
			run_map[run_current_row][run_last_node]["completed"] = true
			run_current_row += 1
			run_overlay = ""
			sfx_click.play()
		return

	# Elite reward overlay: click to claim
	if run_overlay == "elite_reward":
		if reward_relics.size() > 0:
			var claim_rect := Rect2(250, 260, 300, 80)
			if claim_rect.has_point(event.position):
				_claim_relic(reward_relics[0])
				reward_relics.clear()
				run_overlay = ""
				run_current_row += 1
		return

	# Boss reward overlay: click one of 3
	if run_overlay == "boss_reward":
		for i in range(reward_relics.size()):
			var card_x: float = 115.0 + i * 200.0
			var card_rect := Rect2(card_x, 220, 170, 160)
			if card_rect.has_point(event.position):
				_claim_relic(reward_relics[i])
				reward_relics.clear()
				run_overlay = ""
				_advance_after_boss()
				return
		return

	# If overlay is showing, click dismisses it
	if run_overlay == "run_over" or run_overlay == "run_won":
		game_state = "level_select"
		run_map.clear()
		run_overlay = ""
		return

	# Check node clicks
	if run_current_row >= run_map.size():
		return
	for col_idx in range(run_map[run_current_row].size()):
		var node: Dictionary = run_map[run_current_row][col_idx]
		if node["position"].distance_to(event.position) <= 22.0 and _is_node_available(run_current_row, col_idx):
			sfx_click.play()
			if node["type"] == "merchant":
				run_last_node = col_idx
				merchant_relics = GameRelics.get_shop_relics(run_hero, run_relics)
				merchant_relics_bought = []
				run_overlay = "merchant"
			elif node["type"] == "campfire":
				run_last_node = col_idx
				campfire_upgrade_choices = _get_campfire_upgrades()
				run_overlay = "campfire"
			else:
				_start_roguelike_battle(col_idx)
			return

func _generate_roguelike_battle_map(ai_level: int, is_elite: bool) -> Dictionary:
	var node_count: int = randi_range(10, 14) + ai_level
	if is_elite:
		node_count += 1
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

	# Elite: add another opponent starting building
	if is_elite and positions.size() > 5:
		var next_opp: int = positions.size() - opponent_indices.size() - 1
		if next_opp > 0 and next_opp not in opponent_indices and next_opp not in player_indices:
			opponent_indices.append(next_opp)

	# Assign units
	var units: Array = []
	for i in range(positions.size()):
		if i in player_indices:
			units.append(20)
		elif i in opponent_indices:
			units.append(10 + ai_level * 2)
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

	# Elite modifier: pre-upgrade some enemy buildings
	var upgrades: Dictionary = {}
	if is_elite:
		for oi in opponent_indices:
			if oi != opponent_indices[0]:
				upgrades[oi] = 1

	return {"positions": positions, "units": units, "player_indices": player_indices,
		"opponent_indices": opponent_indices, "forges": forges, "towers": towers, "upgrades": upgrades}

# === Level Start ===

func _start_level(mode: String, level: int, config_override: Dictionary = {}) -> void:
	current_mode = mode
	current_level = level
	game_state = "playing"
	game_won = false
	game_lost = false
	game_time = 0.0
	ai_timer = 0.0
	buildings.clear()
	dispatch_queues.clear()
	moving_units.clear()
	visual_effects.clear()
	_reset_hero_battle_state()
	selected_building_id = -1
	is_dragging = false
	drag_source_id = -1
	send_ratio = 0.5
	context_menu_building_id = -1
	context_menu_options.clear()

	var config: Dictionary
	if not config_override.is_empty():
		config = config_override
	elif mode == "neutral":
		config = GameData.get_neutral_level(level)
	else:
		config = GameData.get_ai_level(level)

	var positions: Array = config["positions"]
	var units: Array = config["units"]
	var player_indices: Array = config["player_indices"]
	var opponent_indices: Array = config["opponent_indices"]

	var upgrades: Dictionary = config.get("upgrades", {})

	var forge_indices: Array = config.get("forges", [])
	var tower_indices: Array = config.get("towers", [])

	for i in range(positions.size()):
		var owner: String
		if i in player_indices:
			owner = "player"
		elif i in opponent_indices:
			owner = "opponent"
		else:
			owner = "neutral"
		var bld_level: int = upgrades.get(i, 1)
		var bld_type: String = "forge" if i in forge_indices else ("tower" if i in tower_indices else "normal")
		buildings.append({
			"id": i,
			"position": positions[i],
			"owner": owner,
			"units": units[i],
			"level": bld_level,
			"max_capacity": GameData.BASE_CAPACITY * bld_level,
			"gen_timer": 0.0,
			"type": bld_type,
			"upgrading": false,
			"upgrade_progress": 0.0,
			"upgrade_duration": 0.0,
			"shoot_timer": 0.0,
			"units_fractional": 0.0,
			"fractional_timestamp": 0.0,
		})

func _return_to_menu() -> void:
	game_state = "level_select"
	buildings.clear()
	dispatch_queues.clear()
	moving_units.clear()
	visual_effects.clear()
	context_menu_building_id = -1
	context_menu_options.clear()

# === Main Loop ===

func _process(delta: float) -> void:
	if game_state == "level_select" or game_state == "hero_select":
		queue_redraw()
		return
	if game_state == "roguelike_map":
		game_time += delta
		queue_redraw()
		return

	game_time += delta
	if in_roguelike_run and not game_won and not game_lost:
		run_time_left = maxf(0.0, run_time_left - delta)
	if game_won or game_lost:
		queue_redraw()
		return

	_update_unit_generation(delta)
	_update_upgrades(delta)
	combat.update_towers(delta)
	_update_dispatch_queues(delta)
	_update_moving_units(delta)
	_update_visual_effects(delta)
	if in_roguelike_run and run_hero != "":
		_update_hero_system(delta)
	if current_mode == "ai":
		_update_ai(delta)
	combat.check_win_condition()
	queue_redraw()

func _update_visual_effects(delta: float) -> void:
	var to_remove: Array = []
	for i in range(visual_effects.size()):
		visual_effects[i]["timer"] += delta
		if visual_effects[i]["timer"] >= visual_effects[i]["duration"]:
			to_remove.append(i)
	to_remove.reverse()
	for idx in to_remove:
		visual_effects.remove_at(idx)

func _update_hero_system(delta: float) -> void:
	# Passive energy regen
	var energy_rate: float = hero_energy_rate
	if has_relic("capacitor"):
		energy_rate *= 1.25
	if has_relic("dynamo"):
		energy_rate *= 1.2
	if has_relic("overdrive"):
		energy_rate *= 1.5
	hero_energy = minf(hero_energy + energy_rate * delta, hero_max_energy)
	# Tick cooldowns
	for i in range(4):
		if hero_power_cooldowns[i] > 0.0:
			hero_power_cooldowns[i] = maxf(0.0, hero_power_cooldowns[i] - delta)
	# Update active effects - tick timers and apply periodic effects
	var effects_to_remove: Array = []
	for i in range(hero_active_effects.size()):
		var fx: Dictionary = hero_active_effects[i]
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
				for b in buildings:
					if b["owner"] == "player" and b["type"] != "forge" and b["type"] != "tower":
						var share: int = maxi(1, int(b["units"] * 0.1))
						if share > 0 and b["units"] > share:
							var weakest: Dictionary = {}
							var weakest_units: int = 999999
							for adj in _get_adjacent_buildings(b["id"]):
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
				if tid >= 0 and tid < buildings.size() and buildings[tid]["owner"] == "opponent" and buildings[tid]["units"] > 0:
					buildings[tid]["units"] -= 1
					var nearest_id: int = -1
					var nearest_dist: float = INF
					for b in buildings:
						if b["owner"] == "player":
							var d: float = b["position"].distance_to(buildings[tid]["position"])
							if d < nearest_dist:
								nearest_dist = d
								nearest_id = b["id"]
					if nearest_id >= 0:
						moving_units.append({
							"source_id": tid,
							"target_id": nearest_id,
							"owner": "player",
							"progress": 0.0,
							"start_pos": buildings[tid]["position"],
							"end_pos": buildings[nearest_id]["position"],
							"lateral_offset": (randf() - 0.5) * 10.0,
						})
		if fx["timer"] >= fx["duration"]:
			effects_to_remove.append(i)
	effects_to_remove.reverse()
	for idx in effects_to_remove:
		hero_active_effects.remove_at(idx)

func _reset_hero_battle_state() -> void:
	hero_energy = 0.0
	hero_power_cooldowns = [0.0, 0.0, 0.0, 0.0]
	hero_active_effects.clear()
	hero_targeting_power = -1
	hero_supply_first_node = -1
	hero_minefield_source = -1
	first_power_used = false

func _apply_supply_line_equalize(fx: Dictionary) -> void:
	# Wormhole: equalize across all player nodes
	if fx.get("wormhole", false):
		var player_nodes: Array = []
		for b in buildings:
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
	if id_a < 0 or id_a >= buildings.size() or id_b < 0 or id_b >= buildings.size():
		return
	var a: Dictionary = buildings[id_a]
	var b: Dictionary = buildings[id_b]
	if a["owner"] != "player" or b["owner"] != "player":
		return
	var total: int = a["units"] + b["units"]
	var half: int = total / 2
	a["units"] = half
	b["units"] = total - half

func _try_activate_hero_power(index: int) -> void:
	if run_hero == "" or not GameData.HERO_DATA.has(run_hero):
		return
	var powers: Array = GameData.HERO_DATA[run_hero]["powers"]
	if index < 0 or index >= powers.size():
		return
	var power: Dictionary = powers[index]
	var effective_cost: float = power["cost"]
	if has_relic("free_opener") and not first_power_used:
		effective_cost = 0.0
	elif has_relic("efficiency_core"):
		effective_cost *= 0.8
	if hero_energy < effective_cost or hero_power_cooldowns[index] > 0.0:
		return
	var targeting: String = power["targeting"]
	if targeting == "instant":
		_activate_hero_power(index, -1)
	else:
		# Enter targeting mode
		hero_targeting_power = index
		hero_supply_first_node = -1
		hero_minefield_source = -1

func _handle_hero_target_click(pos: Vector2) -> void:
	if hero_targeting_power < 0 or run_hero == "":
		return
	var powers: Array = GameData.HERO_DATA[run_hero]["powers"]
	var power: Dictionary = powers[hero_targeting_power]
	var targeting: String = power["targeting"]
	var clicked_id: int = _get_building_at(pos)

	if targeting == "any_node":
		if clicked_id >= 0:
			_activate_hero_power(hero_targeting_power, clicked_id)
			hero_targeting_power = -1
	elif targeting == "friendly_node":
		if clicked_id >= 0 and buildings[clicked_id]["owner"] == "player":
			_activate_hero_power(hero_targeting_power, clicked_id)
			hero_targeting_power = -1
	elif targeting == "enemy_node":
		if clicked_id >= 0 and buildings[clicked_id]["owner"] == "opponent":
			_activate_hero_power(hero_targeting_power, clicked_id)
			hero_targeting_power = -1
	elif targeting == "friendly_node_pair":
		# Two-click: first friendly, then second friendly
		if clicked_id >= 0 and buildings[clicked_id]["owner"] == "player":
			if hero_supply_first_node < 0:
				hero_supply_first_node = clicked_id
			elif clicked_id != hero_supply_first_node:
				_activate_hero_power_pair(hero_targeting_power, hero_supply_first_node, clicked_id)
				hero_targeting_power = -1
				hero_supply_first_node = -1
	elif targeting == "path":
		# Minefield: click two nodes to define path
		if clicked_id >= 0:
			if hero_minefield_source < 0:
				hero_minefield_source = clicked_id
			elif clicked_id != hero_minefield_source:
				_activate_hero_power_pair(hero_targeting_power, hero_minefield_source, clicked_id)
				hero_targeting_power = -1
				hero_minefield_source = -1

func _activate_hero_power(index: int, target_id: int) -> void:
	var powers: Array = GameData.HERO_DATA[run_hero]["powers"]
	var power: Dictionary = powers[index]
	var actual_cost: float = power["cost"]
	if has_relic("free_opener") and not first_power_used:
		actual_cost = 0.0
		first_power_used = true
	elif has_relic("efficiency_core"):
		actual_cost *= 0.8
	hero_energy -= actual_cost
	if has_relic("feedback_loop") and actual_cost > 0:
		hero_energy = minf(hero_energy + actual_cost * 0.1, hero_max_energy)
	hero_power_cooldowns[index] = power["cooldown"]
	sfx_click.play()

	# Add visual flash
	visual_effects.append({
		"type": "power_flash",
		"position": Vector2(GameData.SCREEN_W / 2, 40),
		"timer": 0.0,
		"duration": 0.5,
		"color": GameData.HERO_DATA[run_hero]["color"],
	})

	match run_hero:
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

func _activate_hero_power_pair(index: int, node_a: int, node_b: int) -> void:
	var powers: Array = GameData.HERO_DATA[run_hero]["powers"]
	var power: Dictionary = powers[index]
	var actual_cost: float = power["cost"]
	if has_relic("free_opener") and not first_power_used:
		actual_cost = 0.0
		first_power_used = true
	elif has_relic("efficiency_core"):
		actual_cost *= 0.8
	hero_energy -= actual_cost
	if has_relic("feedback_loop") and actual_cost > 0:
		hero_energy = minf(hero_energy + actual_cost * 0.1, hero_max_energy)
	hero_power_cooldowns[index] = power["cooldown"]
	sfx_click.play()

	visual_effects.append({
		"type": "power_flash",
		"position": Vector2(GameData.SCREEN_W / 2, 40),
		"timer": 0.0,
		"duration": 0.5,
		"color": GameData.HERO_DATA[run_hero]["color"],
	})

	match run_hero:
		"warden":
			if index == 2: _power_minefield(node_a, node_b)
		"architect":
			if index == 1: _power_supply_line(node_a, node_b)

# === Hero Power Implementations ===

# Commander powers
func _power_rally_cry(target_id: int) -> void:
	var rolling_thunder: bool = has_hero_upgrade("Rolling Thunder")
	for b in buildings:
		if b["owner"] == "player" and b["id"] != target_id and b["type"] != "forge" and b["type"] != "tower":
			var rally_pct: float = 0.5 if has_relic("warchief_banner") else 0.3
			var send_count: int = int(b["units"] * rally_pct)
			if send_count > 0:
				dispatch_queues.append({
					"source_id": b["id"],
					"target_id": target_id,
					"owner": "player",
					"remaining": send_count,
					"wave_timer": 0.0,
					"start_pos": b["position"],
					"end_pos": buildings[target_id]["position"],
				})
			# Rolling Thunder: second wave of 20%
			if rolling_thunder:
				var wave2: int = int(b["units"] * 0.2)
				if wave2 > 0:
					dispatch_queues.append({
						"source_id": b["id"],
						"target_id": target_id,
						"owner": "player",
						"remaining": wave2,
						"wave_timer": 2.0,
						"start_pos": b["position"],
						"end_pos": buildings[target_id]["position"],
					})

func _power_forced_march() -> void:
	hero_active_effects.append({
		"type": "forced_march",
		"timer": 0.0,
		"duration": 8.0,
		"double_time": has_hero_upgrade("Double Time"),
	})

func _power_conscription() -> void:
	var war_economy: bool = has_hero_upgrade("War Economy")
	for b in buildings:
		if b["owner"] == "player" and b["type"] != "forge" and b["type"] != "tower":
			var bonus: int = b["level"] * 3
			if war_economy:
				bonus += b["level"] * 2
			b["units"] += bonus

func _power_blitz() -> void:
	var dur: float = 18.0 if has_relic("shock_doctrine") else 12.0
	hero_active_effects.append({
		"type": "blitz",
		"timer": 0.0,
		"duration": dur,
		"scorched_earth": has_hero_upgrade("Scorched Earth"),
	})

# Warden powers
func _power_fortify(target_id: int) -> void:
	var dur: float = 14.0 if has_relic("reinforced_walls") else 8.0
	hero_active_effects.append({
		"type": "fortify",
		"timer": 0.0,
		"duration": dur,
		"target_id": target_id,
		"reactive_armor": has_hero_upgrade("Reactive Armor"),
	})
	if has_relic("reinforced_walls") and target_id >= 0 and target_id < buildings.size():
		buildings[target_id]["units"] += 5

func _power_entrench(target_id: int) -> void:
	hero_active_effects.append({
		"type": "entrench",
		"timer": 0.0,
		"duration": 15.0,
		"target_id": target_id,
		"bunker_down": has_hero_upgrade("Bunker Down"),
	})

func _power_minefield(node_a: int, node_b: int) -> void:
	var pos_a: Vector2 = buildings[node_a]["position"]
	var pos_b: Vector2 = buildings[node_b]["position"]
	hero_active_effects.append({
		"type": "minefield",
		"timer": 0.0,
		"duration": 60.0,  # Long duration, but one-shot
		"node_a": node_a,
		"node_b": node_b,
		"mid_pos": (pos_a + pos_b) / 2.0,
		"triggered": false,
		"chain_mines": has_hero_upgrade("Chain Mines"),
	})

func _power_citadel(target_id: int) -> void:
	hero_active_effects.append({
		"type": "citadel",
		"timer": 0.0,
		"duration": 20.0,
		"target_id": target_id,
	})
	# Iron Curtain: spread citadel bonus to adjacent nodes at 50% (as citadel_spread)
	if has_hero_upgrade("Iron Curtain"):
		for adj in _get_adjacent_buildings(target_id):
			if adj["owner"] == "player" and adj["type"] != "forge" and adj["type"] != "tower":
				hero_active_effects.append({
					"type": "citadel_spread",
					"timer": 0.0,
					"duration": 20.0,
					"target_id": adj["id"],
				})

# Saboteur powers
func _power_sabotage(target_id: int) -> void:
	var dur: float = 20.0 if has_relic("deep_cover") else 12.0
	hero_active_effects.append({
		"type": "sabotage",
		"timer": 0.0,
		"duration": dur,
		"target_id": target_id,
	})
	if has_relic("deep_cover") and target_id >= 0 and target_id < buildings.size():
		buildings[target_id]["units"] = buildings[target_id]["units"] / 2
	# Rolling Blackout: spread to 1 adjacent enemy node
	if has_hero_upgrade("Rolling Blackout"):
		var adj_enemies: Array = []
		for adj in _get_adjacent_buildings(target_id):
			if adj["owner"] == "opponent" and adj["id"] != target_id:
				adj_enemies.append(adj)
		if adj_enemies.size() > 0:
			var spread_target: Dictionary = adj_enemies[randi() % adj_enemies.size()]
			hero_active_effects.append({
				"type": "sabotage",
				"timer": 0.0,
				"duration": dur * 0.5,
				"target_id": spread_target["id"],
			})

func _power_blackout() -> void:
	hero_active_effects.append({
		"type": "blackout",
		"timer": 0.0,
		"duration": 10.0,
		"quicksand": has_hero_upgrade("Quicksand"),
	})

func _power_turncoat(target_id: int) -> void:
	var target: Dictionary = buildings[target_id]
	var convert_pct: float = 0.5 if has_relic("double_agent") else 0.3
	var convert_count: int = int(target["units"] * convert_pct)
	if convert_count > 0:
		target["units"] -= convert_count
		# Send converted units to nearest player building
		var nearest_id: int = -1
		var nearest_dist: float = INF
		for b in buildings:
			if b["owner"] == "player":
				var d: float = b["position"].distance_to(target["position"])
				if d < nearest_dist:
					nearest_dist = d
					nearest_id = b["id"]
		if nearest_id >= 0:
			for _i in range(convert_count):
				moving_units.append({
					"source_id": target_id,
					"target_id": nearest_id,
					"owner": "player",
					"progress": 0.0,
					"start_pos": target["position"],
					"end_pos": buildings[nearest_id]["position"],
					"lateral_offset": (randf() - 0.5) * 10.0,
				})
	# Sleeper Cell: keep converting 1 unit every 3s for 15s
	if has_hero_upgrade("Sleeper Cell") and target["owner"] == "opponent":
		hero_active_effects.append({
			"type": "sleeper_cell",
			"timer": 0.0,
			"duration": 15.0,
			"target_id": target_id,
			"convert_timer": 0.0,
		})

func _power_emp() -> void:
	hero_active_effects.append({
		"type": "emp",
		"timer": 0.0,
		"duration": 10.0,
		"total_shutdown": has_hero_upgrade("Total Shutdown"),
	})
	# Total Shutdown: also drain 30% of all enemy garrisons
	if has_hero_upgrade("Total Shutdown"):
		for b in buildings:
			if b["owner"] == "opponent" and b["type"] != "forge" and b["type"] != "tower":
				b["units"] = maxi(0, b["units"] - int(b["units"] * 0.3))

# Architect powers
func _power_overclock(target_id: int) -> void:
	hero_active_effects.append({
		"type": "overclock",
		"timer": 0.0,
		"duration": 12.0,
		"target_id": target_id,
	})
	# Overdrive: spread overclock to adjacent nodes at 50% (1.5x gen)
	if has_hero_upgrade("Overdrive"):
		for adj in _get_adjacent_buildings(target_id):
			if adj["owner"] == "player" and adj["type"] != "forge" and adj["type"] != "tower":
				hero_active_effects.append({
					"type": "overclock_spread",
					"timer": 0.0,
					"duration": 12.0,
					"target_id": adj["id"],
				})

func _power_supply_line(node_a: int, node_b: int) -> void:
	var dur: float = 25.0 if has_relic("grid_link") else 15.0
	hero_active_effects.append({
		"type": "supply_line",
		"timer": 0.0,
		"duration": dur,
		"node_a": node_a,
		"node_b": node_b,
		"equalize_timer": 0.0,
		"wormhole": has_hero_upgrade("Wormhole"),
	})

func _power_terraform(target_id: int) -> void:
	var b: Dictionary = buildings[target_id]
	if b["type"] != "forge" and b["type"] != "tower":
		var tf_amount: int = 3 if has_relic("rapid_expansion") else 2
		b["level"] = mini(b["level"] + tf_amount, GameData.MAX_BUILDING_LEVEL)
		b["max_capacity"] = GameData.BASE_CAPACITY * b["level"]
		# Deep Foundations: mark node so it keeps +1 level even if captured and recaptured
		if has_hero_upgrade("Deep Foundations"):
			b["deep_foundations"] = true
			b["min_level"] = maxi(b.get("min_level", 1), mini(b["level"], 2))
		sfx_upgrade.play()

func _power_nexus() -> void:
	hero_active_effects.append({
		"type": "nexus",
		"timer": 0.0,
		"duration": 15.0,
		"power_grid": has_hero_upgrade("Power Grid"),
		"grid_timer": 0.0,
	})

func has_relic(id: String) -> bool:
	return id in run_relics

func has_hero_upgrade(name: String) -> bool:
	return name in run_hero_upgrades

func _get_adjacent_buildings(node_id: int, max_dist: float = 160.0) -> Array:
	var result: Array = []
	var origin: Vector2 = buildings[node_id]["position"]
	for b in buildings:
		if b["id"] != node_id and origin.distance_to(b["position"]) <= max_dist:
			result.append(b)
	return result

func _get_campfire_upgrades() -> Array:
	if run_hero == "" or not GameData.HERO_UPGRADES.has(run_hero):
		return []
	var all_upgrades: Array = GameData.HERO_UPGRADES[run_hero]
	var available: Array = []
	for u in all_upgrades:
		if u["name"] not in run_hero_upgrades:
			available.append(u)
	available.shuffle()
	var count: int = mini(3, available.size())
	return available.slice(0, count)

func _has_hero_effect(effect_type: String) -> bool:
	for fx in hero_active_effects:
		if fx["type"] == effect_type and fx["timer"] < fx["duration"]:
			return true
	return false

func _has_hero_effect_on(effect_type: String, node_id: int) -> bool:
	for fx in hero_active_effects:
		if fx["type"] == effect_type and fx.get("target_id", -1) == node_id and fx["timer"] < fx["duration"]:
			return true
	return false

func _update_unit_generation(delta: float) -> void:
	# Find highest player node level for Nexus effect
	var nexus_active: bool = _has_hero_effect("nexus")
	var highest_level: int = 1
	if nexus_active:
		for b in buildings:
			if b["owner"] == "player" and b["type"] != "forge" and b["type"] != "tower":
				highest_level = maxi(highest_level, b["level"])

	for b in buildings:
		if b["type"] == "forge" or b["type"] == "tower":
			continue
		# Check Sabotage / EMP: skip generation for affected enemy nodes
		if b["owner"] == "opponent":
			if _has_hero_effect_on("sabotage", b["id"]) or _has_hero_effect("emp"):
				continue
		var level: int = b["level"]
		# Nexus: player nodes gen at highest level
		if nexus_active and b["owner"] == "player":
			level = highest_level
		var gen_mult: float = 1.0
		# Overclock: 3x gen rate
		if b["owner"] == "player" and _has_hero_effect_on("overclock", b["id"]):
			gen_mult *= 3.0
		# Overdrive: overclock spread gives 1.5x gen
		elif b["owner"] == "player" and _has_hero_effect_on("overclock_spread", b["id"]):
			gen_mult *= 1.5
		# Citadel: 3x gen rate and 2x cap
		if b["owner"] == "player" and _has_hero_effect_on("citadel", b["id"]):
			gen_mult *= 3.0
		# Iron Curtain: citadel spread gives 1.5x gen
		elif b["owner"] == "player" and _has_hero_effect_on("citadel_spread", b["id"]):
			gen_mult *= 1.5
		# Bunker Down: entrench also boosts generation +50%
		if b["owner"] == "player":
			for fx in hero_active_effects:
				if fx["type"] == "entrench" and fx.get("target_id", -1) == b["id"] and fx["timer"] < fx["duration"] and fx.get("bunker_down", false):
					gen_mult *= 1.5
					break
		# Relic: gen_boost +15% gen for player
		if b["owner"] == "player" and has_relic("gen_boost"):
			gen_mult *= 1.15
		# Relic: titan_form +15% gen for player
		if b["owner"] == "player" and has_relic("titan_form"):
			gen_mult *= 1.15
		var max_cap: int = GameData.BASE_CAPACITY * level
		if b["owner"] == "player" and _has_hero_effect_on("citadel", b["id"]):
			max_cap *= 2
		elif b["owner"] == "player" and _has_hero_effect_on("citadel_spread", b["id"]):
			max_cap = int(max_cap * 1.5)
		# Relic: deep_reserves +25% capacity for player
		if b["owner"] == "player" and has_relic("deep_reserves"):
			max_cap = int(max_cap * 1.25)
		# Relic: titan_form +40% capacity for player
		if b["owner"] == "player" and has_relic("titan_form"):
			max_cap = int(max_cap * 1.4)
		b["max_capacity"] = max_cap
		if b["units"] >= max_cap:
			continue
		b["gen_timer"] += delta * gen_mult
		var interval: float = 2.0 / level
		while b["gen_timer"] >= interval and b["units"] < max_cap:
			b["gen_timer"] -= interval
			b["units"] += 1

func _update_upgrades(delta: float) -> void:
	for b in buildings:
		if not b["upgrading"]:
			continue
		b["upgrade_progress"] += delta / b["upgrade_duration"]
		if b["upgrade_progress"] >= 1.0:
			b["upgrading"] = false
			b["upgrade_progress"] = 0.0
			b["upgrade_duration"] = 0.0
			b["level"] += 1
			b["max_capacity"] = GameData.BASE_CAPACITY * b["level"]
			sfx_upgrade.play()

func _update_dispatch_queues(delta: float) -> void:
	var to_remove: Array = []
	for i in range(dispatch_queues.size()):
		var q: Dictionary = dispatch_queues[i]
		var source: Dictionary = buildings[q["source_id"]]
		# Cancel queue if building changed owner
		if source["owner"] != q["owner"]:
			to_remove.append(i)
			continue
		q["wave_timer"] += delta
		var interval: float = 1.0 / GameData.ARMY_WAVES_PER_SECOND
		while q["wave_timer"] >= interval and q["remaining"] > 0:
			q["wave_timer"] -= interval
			var wave_size: int = mini(GameData.MAX_ARMY_WIDTH, q["remaining"])
			# Cap to available units in the building
			wave_size = mini(wave_size, source["units"])
			if wave_size <= 0:
				q["remaining"] = 0
				break
			source["units"] -= wave_size
			q["remaining"] -= wave_size
			for _j in range(wave_size):
				var lateral: float = (float(_j) - float(wave_size - 1) / 2.0) * GameData.UNIT_FORMATION_SPACING
				moving_units.append({
					"source_id": q["source_id"],
					"target_id": q["target_id"],
					"owner": q["owner"],
					"progress": 0.0,
					"start_pos": q["start_pos"],
					"end_pos": q["end_pos"],
					"lateral_offset": lateral,
				})
		if q["remaining"] <= 0:
			to_remove.append(i)
	to_remove.reverse()
	for idx in to_remove:
		dispatch_queues.remove_at(idx)

func _update_moving_units(delta: float) -> void:
	var forced_march: bool = _has_hero_effect("forced_march")
	var blackout: bool = _has_hero_effect("blackout")
	var emp: bool = _has_hero_effect("emp")

	# Check minefields against enemy units
	combat.check_minefields()

	var resolved: Array = []
	for i in range(moving_units.size()):
		var u: Dictionary = moving_units[i]
		var dist: float = u["start_pos"].distance_to(u["end_pos"])
		if dist < 1.0:
			dist = 1.0
		var speed: float = GameData.UNIT_SPEED
		if in_roguelike_run and u["owner"] == "player":
			speed *= 1.0 + 0.1 * run_upgrades.get("speed", 0)
		# Relic: swift_legs +20% speed for player
		if has_relic("swift_legs") and u["owner"] == "player":
			speed *= 1.2
		# Forced March: player units move 2x
		if forced_march and u["owner"] == "player":
			speed *= 2.0
		# Concertina wire: slow enemies near triggered minefields
		if u["owner"] == "opponent":
			for fx in hero_active_effects:
				if fx["type"] == "minefield_slow" and fx["timer"] < fx["duration"]:
					var unit_pos: Vector2 = u["start_pos"].lerp(u["end_pos"], u["progress"])
					if unit_pos.distance_to(fx["position"]) <= 60.0:
						speed *= 0.4
						break
		# Blackout: enemy transit slowed 50%
		if blackout and u["owner"] == "opponent":
			speed *= 0.5
		# EMP: enemy transit frozen
		if emp and u["owner"] == "opponent":
			speed = 0.0
		u["progress"] += (speed / dist) * delta
		if u["progress"] >= 1.0:
			combat.resolve_arrival(u)
			resolved.append(i)
	resolved.reverse()
	for idx in resolved:
		moving_units.remove_at(idx)

# === Context Menu ===

func _open_context_menu(building_id: int) -> void:
	var b: Dictionary = buildings[building_id]
	context_menu_building_id = building_id
	selected_building_id = building_id
	context_menu_options.clear()

	var menu_w: float = 130.0
	var option_h: float = 30.0
	var menu_x: float = b["position"].x + 30.0
	var menu_y: float = b["position"].y - 15.0

	# Clamp to screen bounds
	if menu_x + menu_w > 790.0:
		menu_x = b["position"].x - menu_w - 30.0
	if menu_y < 10.0:
		menu_y = 10.0

	var y_offset: int = 0

	# Option 1: Level Up (for normal buildings, not max level, not upgrading)
	if b["type"] == "normal" and b["level"] < GameData.MAX_BUILDING_LEVEL and not b["upgrading"]:
		var cost: int = GameData.get_upgrade_cost(b["level"])
		var enabled: bool = b["units"] >= cost
		context_menu_options.append({
			"rect": Rect2(menu_x, menu_y + y_offset * option_h, menu_w, option_h),
			"label": "Level Up (%d)" % cost,
			"action": "level_up",
			"enabled": enabled,
		})
		y_offset += 1

	# Tower Level Up option
	if b["type"] == "tower" and b["level"] < GameData.MAX_BUILDING_LEVEL and not b["upgrading"]:
		var cost: int = GameData.get_tower_upgrade_cost()
		var enabled: bool = b["units"] >= cost
		context_menu_options.append({
			"rect": Rect2(menu_x, menu_y + y_offset * option_h, menu_w, option_h),
			"label": "Level Up (%d)" % cost,
			"action": "tower_level_up",
			"enabled": enabled,
		})
		y_offset += 1

	# Option 2: Upgrade to Forge (only for normal buildings)
	if b["type"] == "normal":
		var forge_cost: int = GameData.FORGE_COST
		var enabled: bool = b["units"] >= forge_cost
		context_menu_options.append({
			"rect": Rect2(menu_x, menu_y + y_offset * option_h, menu_w, option_h),
			"label": "To Forge (%d)" % GameData.FORGE_COST,
			"action": "to_forge",
			"enabled": enabled,
		})
		y_offset += 1

	# If no options available (e.g., a forge), just select without menu
	if context_menu_options.is_empty():
		context_menu_building_id = -1

func _close_context_menu() -> void:
	context_menu_building_id = -1
	context_menu_options.clear()

func _upgrade_to_forge(b: Dictionary) -> void:
	b["units"] -= GameData.FORGE_COST
	b["type"] = "forge"
	b["level"] = 1
	b["max_capacity"] = GameData.BASE_CAPACITY
	b["upgrading"] = false
	b["upgrade_progress"] = 0.0
	b["upgrade_duration"] = 0.0
	b["gen_timer"] = 0.0
	sfx_upgrade.play()

func _start_building_upgrade(b: Dictionary, cost: int, duration: float) -> void:
	b["units"] -= cost
	b["upgrading"] = true
	b["upgrade_progress"] = 0.0
	b["upgrade_duration"] = duration

# === Input ===

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = event.position
	if game_state == "level_select":
		_input_level_select(event)
		return
	if game_state == "hero_select":
		_input_hero_select(event)
		return
	if game_state == "roguelike_map":
		_input_roguelike_map(event)
		return

	if game_won or game_lost:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if in_roguelike_run:
				_return_from_roguelike_battle()
			else:
				_return_to_menu()
		return

	# Hero power hotkeys (1-4) and targeting
	if in_roguelike_run and run_hero != "" and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and hero_targeting_power >= 0:
			hero_targeting_power = -1
			hero_supply_first_node = -1
			hero_minefield_source = -1
			return
		var key_index: int = -1
		if event.keycode == KEY_1: key_index = 0
		elif event.keycode == KEY_2: key_index = 1
		elif event.keycode == KEY_3: key_index = 2
		elif event.keycode == KEY_4: key_index = 3
		if key_index >= 0:
			_try_activate_hero_power(key_index)
			return

	# Hero power targeting click
	if hero_targeting_power >= 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_hero_target_click(event.position)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_left_press(event.position)
		else:
			_handle_left_release(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if hero_targeting_power >= 0:
			hero_targeting_power = -1
			hero_supply_first_node = -1
			hero_minefield_source = -1
		else:
			_handle_right_click(event.position)
	elif event is InputEventMouseMotion and is_dragging:
		drag_current_pos = event.position

func _input_level_select(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for btn in level_buttons:
			if btn["rect"].has_point(event.position):
				sfx_click.play()
				if btn["mode"] == "roguelike":
					game_state = "hero_select"
				else:
					_start_level(btn["mode"], btn["level"])
				return

func _input_hero_select(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		game_state = "level_select"
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var heroes: Array = ["commander", "warden", "saboteur", "architect"]
		var card_w: float = 170.0
		var card_h: float = 420.0
		var gap: float = 12.0
		var total_w: float = card_w * 4 + gap * 3
		var start_x: float = (GameData.SCREEN_W - total_w) / 2.0
		var card_y: float = 70.0
		for i in range(4):
			var cx: float = start_x + i * (card_w + gap)
			var card_rect := Rect2(cx, card_y, card_w, card_h)
			if card_rect.has_point(event.position):
				sfx_click.play()
				run_hero = heroes[i]
				_start_roguelike_run()
				return

func _handle_left_press(pos: Vector2) -> void:
	if _handle_ratio_click(pos):
		return

	var clicked_id: int = _get_building_at(pos)

	# If context menu is open, check menu clicks first
	if context_menu_building_id != -1:
		for opt in context_menu_options:
			if opt["rect"].has_point(pos):
				if opt["enabled"]:
					var b: Dictionary = buildings[context_menu_building_id]
					if opt["action"] == "level_up":
						_start_building_upgrade(b, GameData.get_upgrade_cost(b["level"]), GameData.get_upgrade_duration(b["level"]))
						sfx_click.play()
					elif opt["action"] == "tower_level_up":
						_start_building_upgrade(b, GameData.get_tower_upgrade_cost(), GameData.get_upgrade_duration(b["level"]))
						sfx_click.play()
					elif opt["action"] == "to_forge":
						_upgrade_to_forge(b)
				_close_context_menu()
				selected_building_id = -1
				return
		# Click on a different building while menu is open → send units
		if clicked_id != -1 and clicked_id != context_menu_building_id:
			_send_units(context_menu_building_id, clicked_id)
			_close_context_menu()
			selected_building_id = -1
			return
		# Click on empty space or same building → close menu
		_close_context_menu()
		selected_building_id = -1
		return

	# No context menu open
	if selected_building_id == -1:
		if clicked_id != -1 and buildings[clicked_id]["owner"] == "player":
			is_dragging = true
			drag_source_id = clicked_id
			drag_current_pos = pos
			sfx_click.play()
	else:
		if clicked_id == -1 or clicked_id == selected_building_id:
			selected_building_id = -1
		elif clicked_id != selected_building_id:
			_send_units(selected_building_id, clicked_id)
			selected_building_id = -1

func _handle_left_release(pos: Vector2) -> void:
	if not is_dragging:
		return
	var release_id: int = _get_building_at(pos)
	if release_id != -1 and release_id != drag_source_id:
		_send_units(drag_source_id, release_id)
		selected_building_id = -1
	else:
		# Released on empty space or same building → open context menu
		_open_context_menu(drag_source_id)
		sfx_click.play()
	is_dragging = false
	drag_source_id = -1

func _handle_right_click(pos: Vector2) -> void:
	_close_context_menu()
	var clicked_id: int = _get_building_at(pos)
	if clicked_id != -1 and buildings[clicked_id]["owner"] == "player":
		var b: Dictionary = buildings[clicked_id]
		if b["type"] == "forge" or b["upgrading"]:
			selected_building_id = -1
			return
		var cost: int = GameData.get_tower_upgrade_cost() if b["type"] == "tower" else GameData.get_upgrade_cost(b["level"])
		if b["level"] < GameData.MAX_BUILDING_LEVEL and b["units"] >= cost:
			_start_building_upgrade(b, cost, GameData.get_upgrade_duration(b["level"]))
			sfx_click.play()
			selected_building_id = -1
			return
	selected_building_id = -1

func _handle_ratio_click(pos: Vector2) -> bool:
	var bar_x: float = 8.0
	var bar_w: float = 36.0
	var bar_y: float = 80.0
	var section_h: float = 50.0
	if pos.x < bar_x or pos.x > bar_x + bar_w:
		return false
	if pos.y < bar_y or pos.y > bar_y + section_h * 4:
		return false
	var index: int = int((pos.y - bar_y) / section_h)
	index = clampi(index, 0, 3)
	send_ratio = ratio_options[3 - index]
	return true

func _get_building_at(pos: Vector2) -> int:
	for b in buildings:
		var radius: float = GameData.BASE_BUILDING_RADIUS + b["level"] * GameData.BUILDING_RADIUS_PER_LEVEL
		if pos.distance_to(b["position"]) <= radius + 5.0:
			return b["id"]
	return -1

func _send_units(source_id: int, target_id: int) -> void:
	var source: Dictionary = buildings[source_id]
	if source["owner"] != "player":
		return
	var send_count: int = int(source["units"] * send_ratio)
	if send_count <= 0:
		return
	sfx_whoosh.play()
	dispatch_queues.append({
		"source_id": source_id,
		"target_id": target_id,
		"owner": "player",
		"remaining": send_count,
		"wave_timer": 0.0,
		"start_pos": source["position"],
		"end_pos": buildings[target_id]["position"],
	})

# === Drawing ===

func _draw() -> void:
	ui.draw()

# === AI Logic ===

func _ai_get_interval() -> float:
	match current_level:
		1: return 5.0
		2: return 3.5
		3: return 2.5
		_: return 2.0

func _ai_get_send_ratio() -> float:
	match current_level:
		1: return 0.6
		2: return 0.6
		3: return 0.7
		_: return 0.8

func _update_ai(delta: float) -> void:
	ai_timer += delta
	var interval: float = _ai_get_interval()
	if ai_timer < interval:
		return
	ai_timer -= interval

	# Total Shutdown: EMP completely blocks AI actions
	for fx in hero_active_effects:
		if fx["type"] == "emp" and fx["timer"] < fx["duration"] and fx.get("total_shutdown", false):
			return

	var ai_buildings: Array = []
	for b in buildings:
		if b["owner"] == "opponent":
			ai_buildings.append(b)
	if ai_buildings.is_empty():
		return

	match current_level:
		1: _ai_novice(ai_buildings)
		2: _ai_expander(ai_buildings)
		3: _ai_aggressor(ai_buildings)
		_: _ai_general(ai_buildings)

# --- Level 1: Novice ---
func _ai_novice(ai_buildings: Array) -> void:
	if randf() < 0.3:
		if _ai_do_upgrade(ai_buildings):
			return
	_ai_send_one(ai_buildings, _ai_find_weakest("opponent"))

# --- Level 2: Expander ---
func _ai_expander(ai_buildings: Array) -> void:
	if randf() < 0.2:
		if _ai_do_upgrade(ai_buildings):
			return

	var target: Dictionary = _ai_find_weakest_by_owner("neutral")
	if target.is_empty():
		target = _ai_find_weakest_by_owner("player")
	if target.is_empty():
		return

	var sorted_sources: Array = _ai_sort_by_units(ai_buildings)
	var sends: int = 0
	for source in sorted_sources:
		if sends >= 2:
			break
		if _ai_do_send(source, target):
			sends += 1

# --- Level 3: Aggressor ---
func _ai_aggressor(ai_buildings: Array) -> void:
	if randf() < 0.15:
		if _ai_do_upgrade(ai_buildings):
			return

	var target: Dictionary = _ai_find_weakest_by_owner("player")
	if target.is_empty():
		target = _ai_find_weakest_by_owner("neutral")
	if target.is_empty():
		return

	var sorted_sources: Array = _ai_sort_by_units(ai_buildings)
	var sends: int = 0
	for source in sorted_sources:
		if sends >= 3:
			break
		if _ai_do_send(source, target):
			sends += 1

# --- Level 4: General ---
func _ai_general(ai_buildings: Array) -> void:
	var ai_count: int = ai_buildings.size()
	var total_ai_units: int = 0
	var max_level: int = 0
	for b in ai_buildings:
		total_ai_units += b["units"]
		if b["level"] > max_level:
			max_level = b["level"]

	var neutral_count: int = 0
	for b in buildings:
		if b["owner"] == "neutral":
			neutral_count += 1

	# Phase 1: Expand — grab nearby neutrals first
	if neutral_count > 0 and ai_count < 4:
		var target: Dictionary = _ai_find_closest_neutral(ai_buildings)
		if not target.is_empty():
			var closest_source: Dictionary = _ai_find_closest_source(ai_buildings, target)
			if not closest_source.is_empty():
				_ai_do_send(closest_source, target)
				return

	# Phase 2: Upgrade
	var upgradable: int = 0
	for b in ai_buildings:
		if b["level"] < GameData.MAX_BUILDING_LEVEL:
			upgradable += 1
	if upgradable > 0 and randf() < 0.5:
		if _ai_do_upgrade(ai_buildings):
			return

	# Phase 3: Attack
	var target: Dictionary = _ai_find_beatable_target(ai_buildings, total_ai_units)
	if target.is_empty():
		_ai_do_upgrade(ai_buildings)
		return

	var sorted_sources: Array = _ai_sort_by_units(ai_buildings)
	for source in sorted_sources:
		_ai_do_send(source, target)

# === AI Helpers ===

func _ai_do_upgrade(ai_buildings: Array) -> bool:
	var sorted: Array = _ai_sort_by_units(ai_buildings)
	for b in sorted:
		if b["type"] == "forge" or b["upgrading"]:
			continue
		var cost: int = GameData.get_tower_upgrade_cost() if b["type"] == "tower" else GameData.get_upgrade_cost(b["level"])
		if b["level"] < GameData.MAX_BUILDING_LEVEL and b["units"] >= cost:
			_start_building_upgrade(b, cost, GameData.get_upgrade_duration(b["level"]))
			return true
	return false

func _ai_do_send(source: Dictionary, target: Dictionary) -> bool:
	var send_count: int = int(source["units"] * _ai_get_send_ratio())
	if send_count <= 2:
		return false
	dispatch_queues.append({
		"source_id": source["id"],
		"target_id": target["id"],
		"owner": "opponent",
		"remaining": send_count,
		"wave_timer": 0.0,
		"start_pos": source["position"],
		"end_pos": target["position"],
	})
	return true

func _ai_send_one(ai_buildings: Array, target: Dictionary) -> void:
	if target.is_empty():
		return
	var best_source: Dictionary = {}
	var best_units: int = 0
	for b in ai_buildings:
		if b["units"] > best_units:
			best_units = b["units"]
			best_source = b
	if not best_source.is_empty():
		_ai_do_send(best_source, target)

func _ai_sort_by_units(ai_buildings: Array) -> Array:
	var sorted: Array = ai_buildings.duplicate()
	sorted.sort_custom(func(a, b): return a["units"] > b["units"])
	return sorted

func _ai_find_weakest(exclude_owner: String = "") -> Dictionary:
	var best: Dictionary = {}
	var lowest: int = 9999
	for b in buildings:
		if b["owner"] == exclude_owner:
			continue
		if b["units"] < lowest:
			lowest = b["units"]
			best = b
	return best

func _ai_find_weakest_by_owner(owner: String) -> Dictionary:
	var best: Dictionary = {}
	var lowest: int = 9999
	for b in buildings:
		if b["owner"] != owner:
			continue
		if b["units"] < lowest:
			lowest = b["units"]
			best = b
	return best

func _ai_find_closest_neutral(ai_buildings: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = 99999.0
	for b in buildings:
		if b["owner"] != "neutral":
			continue
		for ab in ai_buildings:
			var dist: float = ab["position"].distance_to(b["position"])
			if dist < best_dist:
				best_dist = dist
				best = b
	return best

func _ai_find_closest_source(ai_buildings: Array, target: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = 99999.0
	for b in ai_buildings:
		if b["units"] < 3:
			continue
		var dist: float = b["position"].distance_to(target["position"])
		if dist < best_dist:
			best_dist = dist
			best = b
	return best

func _ai_find_beatable_target(ai_buildings: Array, total_ai_units: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1.0
	for b in buildings:
		if b["owner"] == "opponent":
			continue
		var defenders: int = b["units"]
		if defenders <= 0:
			defenders = 1
		var sendable: int = int(total_ai_units * _ai_get_send_ratio())
		var ratio: float = float(sendable) / float(defenders)
		if ratio < 1.5:
			continue
		var min_dist: float = 99999.0
		for ab in ai_buildings:
			var dist: float = ab["position"].distance_to(b["position"])
			if dist < min_dist:
				min_dist = dist
		var score: float = ratio / (min_dist + 50.0) * 1000.0
		if score > best_score:
			best_score = score
			best = b
	return best
