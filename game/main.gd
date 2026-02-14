extends Node2D

# === Game State Machine ===
var game_state: String = "level_select"  # "level_select" or "playing"
var current_mode: String = ""  # "neutral" or "ai"
var current_level: int = 0

const MAX_BUILDING_LEVEL: int = 4
const SCREEN_W := 800.0
const SCREEN_H := 600.0
const UNIT_SPEED := 150.0
const BASE_CAPACITY := 20
const FORGE_COST := 30
const BASE_BUILDING_RADIUS := 20.0
const BUILDING_RADIUS_PER_LEVEL := 5.0

# === Building Data ===
var buildings: Array = []
# Each building: {id, position, owner, units, level, max_capacity, gen_timer, upgrading, upgrade_progress, upgrade_duration}

# === Unit Groups ===
var unit_groups: Array = []
# Each group: {count, source_id, target_id, owner, progress, speed, start_pos, end_pos}

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

# === Level Select UI ===
var level_buttons: Array = []
# Each: {rect: Rect2, mode: String, level: int, label: String}

# === Sound Players ===
var sfx_click: AudioStreamPlayer
var sfx_whoosh: AudioStreamPlayer
var sfx_capture: AudioStreamPlayer
var sfx_upgrade: AudioStreamPlayer

func _ready() -> void:
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

func _create_sfx(duration_sec: float, generator: Callable) -> AudioStreamPlayer:
	var sample_rate := 22050
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	add_child(player)
	var num_samples := int(sample_rate * duration_sec)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(num_samples)
	generator.call(data, num_samples, sample_rate)
	wav.data = data
	player.stream = wav
	return player

func _init_sounds() -> void:
	# Click: soft sine pop 440Hz, ~100ms
	sfx_click = _create_sfx(0.10, func(data: PackedByteArray, num_samples: int, sample_rate: int) -> void:
		for i in range(num_samples):
			var t := float(i) / sample_rate
			var p := float(i) / num_samples
			var attack := minf(p / 0.05, 1.0)
			var env := attack * exp(-6.0 * p)
			var val := sin(TAU * 440.0 * t) * env * 0.7
			data[i] = int((val * 0.5 + 0.5) * 255.0)
	)

	# Whoosh: filtered noise, ~250ms
	sfx_whoosh = _create_sfx(0.25, func(data: PackedByteArray, num_samples: int, sample_rate: int) -> void:
		var prev_noise := 0.0
		for i in range(num_samples):
			var p := float(i) / num_samples
			var attack := minf(p / 0.1, 1.0)
			var env := attack * exp(-4.0 * p)
			var raw := randf_range(-1.0, 1.0)
			prev_noise = prev_noise * 0.7 + raw * 0.3
			data[i] = int((prev_noise * env * 0.5 * 0.5 + 0.5) * 255.0)
	)

	# Capture chime: two-tone C4->E4, ~350ms
	sfx_capture = _create_sfx(0.35, func(data: PackedByteArray, num_samples: int, sample_rate: int) -> void:
		for i in range(num_samples):
			var t := float(i) / sample_rate
			var p := float(i) / num_samples
			var attack := minf(p / 0.05, 1.0)
			var env := attack * exp(-3.0 * p)
			var blend := clampf((p - 0.4) / 0.2, 0.0, 1.0)
			var freq := lerpf(261.63, 329.63, blend)
			var val := sin(TAU * freq * t) * env * 0.7
			data[i] = int((val * 0.5 + 0.5) * 255.0)
	)

	# Upgrade ding: warm sine 600Hz, ~300ms
	sfx_upgrade = _create_sfx(0.3, func(data: PackedByteArray, num_samples: int, sample_rate: int) -> void:
		for i in range(num_samples):
			var t := float(i) / sample_rate
			var p := float(i) / num_samples
			var attack := minf(p / 0.05, 1.0)
			var env := attack * exp(-4.0 * p)
			var val := (sin(TAU * 600.0 * t) + 0.2 * sin(TAU * 1200.0 * t)) * env * 0.6
			data[i] = int((val * 0.5 + 0.5) * 255.0)
	)

# === Level Configurations ===

func _get_neutral_level(level: int) -> Dictionary:
	# Level 1: original layout (9 buildings)
	# Levels 2-4: add more neutral buildings
	var positions: Array = [
		Vector2(120, 300),   # Player start
		Vector2(300, 100),
		Vector2(500, 90),
		Vector2(680, 200),
		Vector2(650, 420),
		Vector2(450, 500),
		Vector2(250, 480),
		Vector2(400, 280),
		Vector2(700, 530),
	]
	var neutral_units: Array = [5, 8, 12, 10, 15, 7, 5, 10, 12]

	# Extra buildings for higher levels
	var extra_positions: Array = [
		Vector2(160, 140),
		Vector2(560, 300),
		Vector2(340, 380),
		Vector2(730, 100),
		Vector2(100, 500),
		Vector2(550, 530),
		Vector2(200, 200),
		Vector2(720, 340),
		Vector2(400, 140),
	]
	var extra_units: Array = [6, 14, 9, 18, 8, 11, 7, 16, 13]

	var extra_count: int = (level - 1) * 3  # 0, 3, 6, 9 extra buildings
	extra_count = mini(extra_count, extra_positions.size())

	for i in range(extra_count):
		positions.append(extra_positions[i])
		neutral_units.append(extra_units[i])

	var forges: Array = []
	if level == 1:
		forges = [3, 6]
	elif level == 2:
		forges = [3, 6, 9]
	elif level == 3:
		forges = [3, 6, 9, 12]
	else:
		forges = [3, 6, 9, 12, 14]
	# Only include forge indices that exist
	var valid_forges: Array = []
	for fi in forges:
		if fi < positions.size():
			valid_forges.append(fi)

	# Tower indices (pick neutral buildings that aren't forges or player)
	var towers: Array = []
	if level == 1:
		towers = [2, 7]
	elif level == 2:
		towers = [2, 7, 10]
	elif level == 3:
		towers = [2, 7, 10, 13]
	else:
		towers = [2, 7, 10, 13, 16]
	var valid_towers: Array = []
	for ti in towers:
		if ti < positions.size() and ti != 0 and ti not in valid_forges:
			valid_towers.append(ti)

	# Assign varied levels to neutral buildings based on conquest level
	# Distribution: 40% level 1, 30% level 2, 20% level 3, 10% level 4
	# Only conquest level N allows neutrals up to building level N
	var upgrades: Dictionary = {}
	var neutral_indices: Array = []
	for i in range(positions.size()):
		if i != 0 and i not in valid_forges and i not in valid_towers:  # skip player start, forges, towers
			neutral_indices.append(i)
	neutral_indices.shuffle()
	var n: int = neutral_indices.size()
	# Cumulative thresholds: first 40% stay level 1, next 30% level 2, etc.
	var idx: int = 0
	var thresholds: Array = [0.4, 0.7, 0.9, 1.0]
	var bld_levels: Array = [1, 2, 3, 4]
	for ni in neutral_indices:
		var pct: float = float(idx) / float(n) if n > 0 else 0.0
		var assigned_level: int = 1
		for t in range(thresholds.size()):
			if pct < thresholds[t]:
				assigned_level = bld_levels[t]
				break
		# Cap building level by conquest level
		assigned_level = mini(assigned_level, level)
		if assigned_level > 1:
			upgrades[ni] = assigned_level
		idx += 1

	return {"positions": positions, "units": neutral_units, "player_indices": [0], "opponent_indices": [], "forges": valid_forges, "towers": valid_towers, "upgrades": upgrades}

func _get_ai_level(level: int) -> Dictionary:
	if level == 1:
		# Novice: symmetric, player bottom-left, opponent top-right
		var positions: Array = [
			Vector2(120, 450),   # Player start
			Vector2(680, 150),   # Opponent start
			Vector2(300, 150),
			Vector2(500, 100),
			Vector2(400, 300),
			Vector2(250, 300),
			Vector2(550, 300),
			Vector2(350, 480),
			Vector2(600, 450),
			Vector2(150, 200),
			Vector2(700, 400),
		]
		var units: Array = [20, 20, 10, 8, 12, 6, 6, 8, 10, 5, 5]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1], "forges": [4, 8], "towers": [5, 10]}
	elif level == 2:
		# Expander: more neutrals to contest, symmetric start
		var positions: Array = [
			Vector2(100, 500),   # Player start
			Vector2(700, 100),   # Opponent start
			Vector2(250, 400),   # Near player
			Vector2(550, 200),   # Near opponent
			Vector2(400, 300),   # Center
			Vector2(200, 200),
			Vector2(600, 400),
			Vector2(400, 120),
			Vector2(400, 480),
			Vector2(150, 300),
			Vector2(650, 300),
			Vector2(300, 150),
			Vector2(500, 450),
		]
		var units: Array = [20, 20, 5, 5, 15, 8, 8, 10, 10, 6, 6, 7, 7]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1], "forges": [4, 7, 12], "towers": [9, 11]}
	elif level == 3:
		# Aggressor: AI gets 2 starting buildings, closer neutrals on AI side
		var positions: Array = [
			Vector2(100, 480),   # Player start
			Vector2(700, 120),   # Opponent start 1
			Vector2(580, 200),   # Opponent start 2
			Vector2(500, 100),   # Neutral near AI
			Vector2(400, 280),   # Center
			Vector2(250, 350),   # Near player
			Vector2(600, 380),
			Vector2(300, 180),
			Vector2(450, 480),
			Vector2(150, 220),
			Vector2(700, 420),
			Vector2(350, 100),
		]
		var units: Array = [25, 15, 15, 5, 14, 8, 10, 10, 6, 7, 8, 12]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1, 2], "forges": [4, 7, 10], "towers": [5, 9]}
	else:
		# General: AI gets 2 buildings (one pre-upgraded), dense map
		var positions: Array = [
			Vector2(100, 500),   # Player start
			Vector2(700, 100),   # Opponent start 1
			Vector2(650, 250),   # Opponent start 2 (will be pre-upgraded)
			Vector2(550, 120),   # Neutral near AI
			Vector2(400, 300),   # Center (heavily defended)
			Vector2(200, 380),   # Near player
			Vector2(500, 400),
			Vector2(300, 200),
			Vector2(400, 480),
			Vector2(150, 200),
			Vector2(250, 500),
			Vector2(600, 450),
			Vector2(350, 120),
			Vector2(720, 380),
		]
		var units: Array = [20, 20, 15, 6, 20, 6, 12, 10, 8, 8, 5, 10, 12, 8]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1, 2],
			"upgrades": {2: 2}, "forges": [4, 8, 11, 13], "towers": [5, 9]}  # Building index 2 starts at level 2

func _start_level(mode: String, level: int) -> void:
	current_mode = mode
	current_level = level
	game_state = "playing"
	game_won = false
	game_lost = false
	game_time = 0.0
	ai_timer = 0.0
	buildings.clear()
	unit_groups.clear()
	visual_effects.clear()
	selected_building_id = -1
	is_dragging = false
	drag_source_id = -1
	send_ratio = 0.5
	context_menu_building_id = -1
	context_menu_options.clear()

	var config: Dictionary
	if mode == "neutral":
		config = _get_neutral_level(level)
	else:
		config = _get_ai_level(level)

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
			"max_capacity": BASE_CAPACITY * bld_level,
			"gen_timer": 0.0,
			"type": bld_type,
			"upgrading": false,
			"upgrade_progress": 0.0,
			"upgrade_duration": 0.0,
			"shoot_timer": 0.0,
		})

func _return_to_menu() -> void:
	game_state = "level_select"
	buildings.clear()
	unit_groups.clear()
	visual_effects.clear()
	context_menu_building_id = -1
	context_menu_options.clear()

# === Main Loop ===

func _process(delta: float) -> void:
	if game_state == "level_select":
		queue_redraw()
		return

	game_time += delta
	if game_won or game_lost:
		queue_redraw()
		return

	_update_unit_generation(delta)
	_update_upgrades(delta)
	_update_towers(delta)
	_update_unit_groups(delta)
	_update_visual_effects(delta)
	if current_mode == "ai":
		_update_ai(delta)
	_check_win_condition()
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

func _update_unit_generation(delta: float) -> void:
	for b in buildings:
		if b["type"] == "forge" or b["type"] == "tower":
			continue
		var level: int = b["level"]
		var max_cap: int = BASE_CAPACITY * level
		b["max_capacity"] = max_cap
		if b["units"] >= max_cap:
			continue
		b["gen_timer"] += delta
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
			b["max_capacity"] = BASE_CAPACITY * b["level"]
			sfx_upgrade.play()

func _update_towers(delta: float) -> void:
	var groups_to_remove: Array = []
	for b in buildings:
		if b["type"] != "tower":
			continue
		b["shoot_timer"] += delta
		var interval: float = _get_tower_shoot_interval(b["level"])
		if b["shoot_timer"] < interval:
			continue
		b["shoot_timer"] -= interval
		# Find closest enemy unit group within range
		var shoot_radius: float = _get_tower_shoot_radius(b["level"])
		var best_idx: int = -1
		var best_dist: float = 99999.0
		for i in range(unit_groups.size()):
			var g: Dictionary = unit_groups[i]
			if g["owner"] == b["owner"]:
				continue
			if i in groups_to_remove:
				continue
			var t: float = g["progress"]
			var eased_t: float = _ease_out_cubic(t)
			var group_pos: Vector2 = g["start_pos"].lerp(g["end_pos"], eased_t)
			var dist: float = b["position"].distance_to(group_pos)
			if dist <= shoot_radius and dist < best_dist:
				best_dist = dist
				best_idx = i
		if best_idx != -1:
			var g: Dictionary = unit_groups[best_idx]
			g["count"] -= 1
			# Visual effect: shot line
			var t: float = g["progress"]
			var eased_t: float = _ease_out_cubic(t)
			var target_pos: Vector2 = g["start_pos"].lerp(g["end_pos"], eased_t)
			visual_effects.append({
				"type": "tower_shot",
				"start": b["position"],
				"end": target_pos,
				"timer": 0.0,
				"duration": 0.2,
				"color": _get_owner_color(b["owner"]),
			})
			if g["count"] <= 0:
				groups_to_remove.append(best_idx)
	# Remove destroyed groups (reverse order)
	groups_to_remove.sort()
	groups_to_remove.reverse()
	for idx in groups_to_remove:
		unit_groups.remove_at(idx)

func _update_unit_groups(delta: float) -> void:
	var resolved: Array = []
	for i in range(unit_groups.size()):
		var g: Dictionary = unit_groups[i]
		var dist: float = g["start_pos"].distance_to(g["end_pos"])
		if dist < 1.0:
			dist = 1.0
		g["progress"] += (UNIT_SPEED / dist) * delta
		if g["progress"] >= 1.0:
			_resolve_arrival(g)
			resolved.append(i)
	resolved.reverse()
	for idx in resolved:
		unit_groups.remove_at(idx)

func _resolve_arrival(group: Dictionary) -> void:
	var target: Dictionary = buildings[group["target_id"]]
	if target["owner"] == group["owner"]:
		# Reinforce
		target["units"] += group["count"]
	else:
		# Combat with multipliers
		var A: float = float(group["count"])
		var D: float = float(target["units"])
		var att_mult: float = _get_attacker_multiplier(group["owner"])
		var def_mult: float = _get_defender_multiplier(target)
		var attacker_losses: float = D * def_mult / att_mult
		var defender_losses: float = A * att_mult / def_mult
		var attacker_remaining: float = A - attacker_losses
		var defender_remaining: float = D - defender_losses

		if defender_remaining >= attacker_remaining:
			# Defender holds
			target["units"] = maxi(0, int(round(defender_remaining)))
		else:
			# Attacker captures
			target["units"] = maxi(1, int(round(attacker_remaining)))
			target["owner"] = group["owner"]
			if target["type"] != "forge" and target["type"] != "tower":
				target["level"] = 1
			target["gen_timer"] = 0.0
			target["upgrading"] = false
			target["upgrade_progress"] = 0.0
			target["upgrade_duration"] = 0.0
			sfx_capture.play()
			visual_effects.append({
				"type": "capture_pop",
				"position": target["position"],
				"timer": 0.0,
				"duration": 0.4,
				"color": _get_owner_color(group["owner"]),
			})

func _get_owner_color(owner: String) -> Color:
	if owner == "player":
		return Color(0.3, 0.5, 1.0)
	elif owner == "opponent":
		return Color(1.0, 0.6, 0.2)
	else:
		return Color(0.6, 0.6, 0.6)

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
# Simple: 30% upgrade, 70% attack weakest building

func _ai_novice(ai_buildings: Array) -> void:
	if randf() < 0.3:
		if _ai_do_upgrade(ai_buildings):
			return
	_ai_send_one(ai_buildings, _ai_find_weakest("opponent"))

# --- Level 2: Expander ---
# Prioritize neutrals. Can send from 2 buildings per turn.

func _ai_expander(ai_buildings: Array) -> void:
	if randf() < 0.2:
		if _ai_do_upgrade(ai_buildings):
			return

	# Prefer neutral targets; fall back to player targets
	var target: Dictionary = _ai_find_weakest_by_owner("neutral")
	if target.is_empty():
		target = _ai_find_weakest_by_owner("player")
	if target.is_empty():
		return

	# Send from up to 2 buildings toward the same target
	var sorted_sources: Array = _ai_sort_by_units(ai_buildings)
	var sends: int = 0
	for source in sorted_sources:
		if sends >= 2:
			break
		if _ai_do_send(source, target):
			sends += 1

# --- Level 3: Aggressor ---
# Targets the player's weakest building. Coordinates multi-source attacks.

func _ai_aggressor(ai_buildings: Array) -> void:
	if randf() < 0.15:
		if _ai_do_upgrade(ai_buildings):
			return

	# Always target the player's weakest building
	var target: Dictionary = _ai_find_weakest_by_owner("player")
	if target.is_empty():
		target = _ai_find_weakest_by_owner("neutral")
	if target.is_empty():
		return

	# Coordinate: send from up to 3 buildings at the same target
	var sorted_sources: Array = _ai_sort_by_units(ai_buildings)
	var sends: int = 0
	for source in sorted_sources:
		if sends >= 3:
			break
		if _ai_do_send(source, target):
			sends += 1

# --- Level 4: General ---
# Phased: expand early, upgrade mid, overwhelm late.
# Smart targeting — only attacks buildings it can beat numerically.

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
			# Send from closest AI building to that neutral
			var closest_source: Dictionary = _ai_find_closest_source(ai_buildings, target)
			if not closest_source.is_empty():
				_ai_do_send(closest_source, target)
				return

	# Phase 2: Upgrade — get buildings to level 3 before pushing
	var upgradable: int = 0
	for b in ai_buildings:
		if b["level"] < MAX_BUILDING_LEVEL:
			upgradable += 1
	if upgradable > 0 and randf() < 0.5:
		if _ai_do_upgrade(ai_buildings):
			return

	# Phase 3: Attack — only pick fights we can win
	var target: Dictionary = _ai_find_beatable_target(ai_buildings, total_ai_units)
	if target.is_empty():
		# Nothing beatable, upgrade or wait
		_ai_do_upgrade(ai_buildings)
		return

	# All-in: send from all buildings with units
	var sorted_sources: Array = _ai_sort_by_units(ai_buildings)
	for source in sorted_sources:
		_ai_do_send(source, target)

# === Utility Helpers ===

func _ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

# === Upgrade Helpers ===

func _get_upgrade_cost(level: int) -> int:
	match level:
		1: return 5
		2: return 10
		3: return 20
		_: return 999

func _get_upgrade_duration(level: int) -> float:
	# Duration to upgrade FROM this level to the next
	match level:
		1: return 5.0
		2: return 10.0
		3: return 15.0
		_: return 999.0

# === Tower Helpers ===

func _get_tower_upgrade_cost() -> int:
	return FORGE_COST

func _start_building_upgrade(b: Dictionary, cost: int, duration: float) -> void:
	b["units"] -= cost
	b["upgrading"] = true
	b["upgrade_progress"] = 0.0
	b["upgrade_duration"] = duration

func _get_tower_defense_multiplier(level: int) -> float:
	match level:
		1: return 1.4
		2: return 1.7
		3: return 1.9
		_: return 2.0

func _get_tower_shoot_interval(level: int) -> float:
	match level:
		1: return 60.0 / 90.0
		2: return 60.0 / 120.0
		3: return 60.0 / 150.0
		_: return 60.0 / 180.0

func _get_tower_shoot_radius(level: int) -> float:
	var base: float = 150.0
	match level:
		1: return base * 1.0
		2: return base * 1.1
		3: return base * 1.25
		_: return base * 1.4

# === AI Helpers ===

func _ai_do_upgrade(ai_buildings: Array) -> bool:
	# Upgrade the building with the most units first (better investment)
	var sorted: Array = _ai_sort_by_units(ai_buildings)
	for b in sorted:
		if b["type"] == "forge" or b["upgrading"]:
			continue
		var cost: int = _get_tower_upgrade_cost() if b["type"] == "tower" else _get_upgrade_cost(b["level"])
		if b["level"] < MAX_BUILDING_LEVEL and b["units"] >= cost:
			_start_building_upgrade(b, cost, _get_upgrade_duration(b["level"]))
			return true
	return false

func _ai_do_send(source: Dictionary, target: Dictionary) -> bool:
	var send_count: int = int(source["units"] * _ai_get_send_ratio())
	if send_count <= 2:
		return false
	source["units"] -= send_count
	unit_groups.append({
		"count": send_count,
		"source_id": source["id"],
		"target_id": target["id"],
		"owner": "opponent",
		"progress": 0.0,
		"speed": UNIT_SPEED,
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
	# Find a non-opponent building we can overwhelm
	# Prefer targets where we have > 1.5x the defenders
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
		# Score: prefer weaker targets that are closer to AI buildings
		var min_dist: float = 99999.0
		for ab in ai_buildings:
			var dist: float = ab["position"].distance_to(b["position"])
			if dist < min_dist:
				min_dist = dist
		# Higher score = better target (low defenders, close distance)
		var score: float = ratio / (min_dist + 50.0) * 1000.0
		if score > best_score:
			best_score = score
			best = b
	return best

# === Combat Multipliers ===

func _count_forges_for_owner(owner: String) -> int:
	var count: int = 0
	for b in buildings:
		if b["type"] == "forge" and b["owner"] == owner:
			count += 1
	return count

func _get_defender_multiplier(building: Dictionary) -> float:
	if building["type"] == "tower":
		return _get_tower_defense_multiplier(building["level"])
	var forge_count: int = _count_forges_for_owner(building["owner"])
	return (90.0 + building["level"] * 10.0 + forge_count * 10.0) / 100.0

func _get_attacker_multiplier(owner: String) -> float:
	var forge_count: int = _count_forges_for_owner(owner)
	return (100.0 + forge_count * 10.0) / 100.0

# === Win/Lose Conditions ===

func _check_win_condition() -> void:
	if current_mode == "neutral":
		for b in buildings:
			if b["owner"] != "player":
				return
		game_won = true
	else:
		# AI mode: win if no opponent buildings left, lose if no player buildings left
		var has_player: bool = false
		var has_opponent: bool = false
		for b in buildings:
			if b["owner"] == "player":
				has_player = true
			elif b["owner"] == "opponent":
				has_opponent = true
		# Also check in-flight groups
		for g in unit_groups:
			if g["owner"] == "player":
				has_player = true
			elif g["owner"] == "opponent":
				has_opponent = true
		if not has_opponent:
			game_won = true
		elif not has_player:
			game_lost = true

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
	if b["type"] == "normal" and b["level"] < MAX_BUILDING_LEVEL and not b["upgrading"]:
		var cost: int = _get_upgrade_cost(b["level"])
		var enabled: bool = b["units"] >= cost
		context_menu_options.append({
			"rect": Rect2(menu_x, menu_y + y_offset * option_h, menu_w, option_h),
			"label": "Level Up (%d)" % cost,
			"action": "level_up",
			"enabled": enabled,
		})
		y_offset += 1

	# Tower Level Up option
	if b["type"] == "tower" and b["level"] < MAX_BUILDING_LEVEL and not b["upgrading"]:
		var cost: int = _get_tower_upgrade_cost()
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
		var forge_cost: int = FORGE_COST
		var enabled: bool = b["units"] >= forge_cost
		context_menu_options.append({
			"rect": Rect2(menu_x, menu_y + y_offset * option_h, menu_w, option_h),
			"label": "To Forge (%d)" % FORGE_COST,
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
	b["units"] -= FORGE_COST
	b["type"] = "forge"
	b["level"] = 1
	b["max_capacity"] = BASE_CAPACITY
	b["upgrading"] = false
	b["upgrade_progress"] = 0.0
	b["upgrade_duration"] = 0.0
	b["gen_timer"] = 0.0
	sfx_upgrade.play()

# === Input ===

func _input(event: InputEvent) -> void:
	if game_state == "level_select":
		_input_level_select(event)
		return

	if game_won or game_lost:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_return_to_menu()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_left_press(event.position)
		else:
			_handle_left_release(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_handle_right_click(event.position)
	elif event is InputEventMouseMotion and is_dragging:
		drag_current_pos = event.position

func _input_level_select(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for btn in level_buttons:
			if btn["rect"].has_point(event.position):
				sfx_click.play()
				_start_level(btn["mode"], btn["level"])
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
						_start_building_upgrade(b, _get_upgrade_cost(b["level"]), _get_upgrade_duration(b["level"]))
						sfx_click.play()
					elif opt["action"] == "tower_level_up":
						_start_building_upgrade(b, _get_tower_upgrade_cost(), _get_upgrade_duration(b["level"]))
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
		var cost: int = _get_tower_upgrade_cost() if b["type"] == "tower" else _get_upgrade_cost(b["level"])
		if b["level"] < MAX_BUILDING_LEVEL and b["units"] >= cost:
			_start_building_upgrade(b, cost, _get_upgrade_duration(b["level"]))
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
		var radius: float = BASE_BUILDING_RADIUS + b["level"] * BUILDING_RADIUS_PER_LEVEL
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
	source["units"] -= send_count
	sfx_whoosh.play()
	unit_groups.append({
		"count": send_count,
		"source_id": source_id,
		"target_id": target_id,
		"owner": "player",
		"progress": 0.0,
		"speed": UNIT_SPEED,
		"start_pos": source["position"],
		"end_pos": buildings[target_id]["position"],
	})

# === Drawing ===

func _draw() -> void:
	if game_state == "level_select":
		_draw_level_select()
		return
	_draw_background()
	_draw_unit_group_lines()
	_draw_drag_line()
	_draw_buildings()
	_draw_unit_groups()
	_draw_visual_effects()
	_draw_context_menu()
	_draw_hud()

# === Level Select Drawing ===

func _draw_level_select() -> void:
	_draw_background()
	var font := ThemeDB.fallback_font

	# Title
	var title := "SELECT LEVEL"
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
	draw_string(font, Vector2(400 - title_size.x / 2, 80), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.9, 0.9, 0.95))

	# Mode headers
	var cx: float = 400.0
	var btn_w: float = 220.0
	var left_x: float = cx - btn_w - 30.0
	var right_x: float = cx + 30.0

	var header_neutral := "CONQUEST"
	var hn_size := font.get_string_size(header_neutral, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	draw_string(font, Vector2(left_x + (btn_w - hn_size.x) / 2, 145), header_neutral,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.6, 0.7))

	var sub_neutral := "Capture all neutral buildings"
	var sn_size := font.get_string_size(sub_neutral, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font, Vector2(left_x + (btn_w - sn_size.x) / 2, 165), sub_neutral,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.45, 0.55))

	var header_ai := "VS OPPONENT"
	var ha_size := font.get_string_size(header_ai, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	draw_string(font, Vector2(right_x + (btn_w - ha_size.x) / 2, 145), header_ai,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.65, 0.3))

	var sub_ai := "Defeat the AI opponent"
	var sa_size := font.get_string_size(sub_ai, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font, Vector2(right_x + (btn_w - sa_size.x) / 2, 165), sub_ai,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.45, 0.3))

	# Buttons
	for btn in level_buttons:
		var r: Rect2 = btn["rect"]
		var is_ai: bool = btn["mode"] == "ai"
		var bg_color := Color(0.15, 0.15, 0.22)
		var border_color := Color(0.3, 0.4, 0.7) if not is_ai else Color(0.7, 0.45, 0.2)
		var text_color := Color(0.8, 0.85, 1.0) if not is_ai else Color(1.0, 0.75, 0.4)

		draw_rect(r, bg_color)
		draw_rect(r, border_color, false, 2.0)

		var label: String = btn["label"]
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		draw_string(font, Vector2(r.position.x + (r.size.x - label_size.x) / 2,
			r.position.y + (r.size.y + label_size.y) / 2 - 2), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, text_color)

func _draw_visual_effects() -> void:
	for fx in visual_effects:
		if fx["type"] == "capture_pop":
			var progress: float = fx["timer"] / fx["duration"]
			var ring_radius: float = 20.0 + 40.0 * progress
			var alpha: float = 1.0 - progress
			var col: Color = fx["color"]
			col.a = alpha * 0.8
			draw_arc(fx["position"], ring_radius, 0, TAU, 48, col, 3.0 * (1.0 - progress * 0.5))
		elif fx["type"] == "tower_shot":
			var progress: float = fx["timer"] / fx["duration"]
			var alpha: float = 1.0 - progress
			var col: Color = fx["color"]
			col.a = alpha * 0.9
			draw_line(fx["start"], fx["end"], col, 2.0 * (1.0 - progress * 0.5))

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0.08, 0.08, 0.12))
	var grid_color := Color(0.14, 0.14, 0.2)
	for x in range(0, int(SCREEN_W) + 1, 40):
		draw_line(Vector2(x, 0), Vector2(x, SCREEN_H), grid_color)
	for y in range(0, int(SCREEN_H) + 1, 40):
		draw_line(Vector2(0, y), Vector2(SCREEN_W, y), grid_color)

func _draw_buildings() -> void:
	for b in buildings:
		var pos: Vector2 = b["position"]
		var radius: float = BASE_BUILDING_RADIUS + b["level"] * BUILDING_RADIUS_PER_LEVEL
		var fill_color: Color
		var outline_color: Color

		if b["owner"] == "player":
			fill_color = Color(0.2, 0.4, 0.9, 0.85)
			outline_color = Color(0.4, 0.6, 1.0)
		elif b["owner"] == "opponent":
			fill_color = Color(0.9, 0.5, 0.1, 0.85)
			outline_color = Color(1.0, 0.65, 0.3)
		else:
			fill_color = Color(0.4, 0.4, 0.4, 0.85)
			outline_color = Color(0.6, 0.6, 0.6)

		var is_forge: bool = b["type"] == "forge"
		var is_tower: bool = b["type"] == "tower"

		_draw_building_shape(b, pos, radius, fill_color, outline_color)

		# Upgrade ready indicator — pulsing gold ring (player only, not forges, not already upgrading)
		if b["type"] == "normal" and not b["upgrading"] and b["owner"] == "player" and b["level"] < MAX_BUILDING_LEVEL and b["units"] >= _get_upgrade_cost(b["level"]):
			var pulse_alpha: float = 0.4 + 0.4 * sin(game_time * 4.0)
			draw_arc(pos, radius + 6, 0, TAU, 48, Color(1.0, 0.85, 0.2, pulse_alpha), 2.0)
		elif is_tower and not b["upgrading"] and b["owner"] == "player" and b["level"] < MAX_BUILDING_LEVEL and b["units"] >= _get_tower_upgrade_cost():
			var pulse_alpha: float = 0.4 + 0.4 * sin(game_time * 4.0)
			draw_arc(pos, radius + 6, 0, TAU, 48, Color(1.0, 0.85, 0.2, pulse_alpha), 2.0)

		# Selection highlight
		if b["id"] == selected_building_id:
			if is_forge:
				var sel_r: float = radius + 4
				var sel_pts: PackedVector2Array = PackedVector2Array([
					pos + Vector2(0, -sel_r), pos + Vector2(sel_r, 0),
					pos + Vector2(0, sel_r), pos + Vector2(-sel_r, 0),
				])
				for di in range(4):
					draw_line(sel_pts[di], sel_pts[(di + 1) % 4], Color(1, 1, 0.3, 0.9), 3.0)
			elif is_tower:
				var sel_r: float = radius + 4
				var sel_pts: PackedVector2Array = PackedVector2Array([
					pos + Vector2(0, -sel_r),
					pos + Vector2(sel_r, sel_r * 0.7),
					pos + Vector2(-sel_r, sel_r * 0.7),
				])
				for di in range(3):
					draw_line(sel_pts[di], sel_pts[(di + 1) % 3], Color(1, 1, 0.3, 0.9), 3.0)
			else:
				draw_arc(pos, radius + 4, 0, TAU, 48, Color(1, 1, 0.3, 0.9), 3.0)

		# Level indicator — small dots around the building (skip for forges)
		if not is_forge:
			for lv in range(b["level"]):
				var angle: float = -PI / 2 + lv * (TAU / MAX_BUILDING_LEVEL)
				var dot_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * (radius + 10)
				draw_circle(dot_pos, 3.0, Color.WHITE)
			# Upgrade-in-progress: show pie chart on the next level dot
			if b["upgrading"]:
				var next_lv: int = b["level"]
				var angle: float = -PI / 2 + next_lv * (TAU / MAX_BUILDING_LEVEL)
				var dot_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * (radius + 10)
				var pie_radius: float = 5.0
				# Background circle (dark)
				draw_circle(dot_pos, pie_radius, Color(0.25, 0.25, 0.3))
				# Pie fill arc
				var fill_angle: float = b["upgrade_progress"] * TAU
				var start_angle: float = -PI / 2.0
				if fill_angle > 0.01:
					# Draw filled pie wedge using polygon segments
					var segments: int = maxi(3, int(fill_angle / TAU * 32))
					var pie_pts: PackedVector2Array = PackedVector2Array()
					pie_pts.append(dot_pos)
					for seg in range(segments + 1):
						var seg_angle: float = start_angle + (float(seg) / segments) * fill_angle
						pie_pts.append(dot_pos + Vector2(cos(seg_angle), sin(seg_angle)) * pie_radius)
					draw_colored_polygon(pie_pts, Color(1.0, 0.85, 0.2))
				# Outline
				draw_arc(dot_pos, pie_radius, 0, TAU, 24, Color(0.8, 0.8, 0.8, 0.6), 1.0)

		# Unit count text
		var font := ThemeDB.fallback_font
		var text: String = str(b["units"])
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, pos - Vector2(text_size.x / 2, -5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _draw_building_shape(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	if b["type"] == "tower":
		_draw_building_triangle(b, pos, radius, fill_color, outline_color)
	elif b["type"] == "forge":
		_draw_building_diamond(b, pos, radius, fill_color, outline_color)
	else:
		_draw_building_circle(b, pos, radius, fill_color, outline_color)

func _draw_building_triangle(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	var tri_pts: PackedVector2Array = PackedVector2Array([
		pos + Vector2(0, -radius),
		pos + Vector2(radius, radius * 0.7),
		pos + Vector2(-radius, radius * 0.7),
	])
	draw_colored_polygon(tri_pts, Color(0.1, 0.1, 0.15))
	var max_cap: int = b["max_capacity"]
	if max_cap > 0:
		var fill_ratio: float = clampf(float(b["units"]) / max_cap, 0.0, 1.0)
		if fill_ratio > 0.0:
			var inner_r: float = radius * 0.7 * fill_ratio
			var fill_pts: PackedVector2Array = PackedVector2Array([
				pos + Vector2(0, -inner_r),
				pos + Vector2(inner_r, inner_r * 0.7),
				pos + Vector2(-inner_r, inner_r * 0.7),
			])
			draw_colored_polygon(fill_pts, fill_color)
	for di in range(3):
		draw_line(tri_pts[di], tri_pts[(di + 1) % 3], outline_color, 2.0)
	draw_circle(pos, 3.0, outline_color)
	draw_line(pos + Vector2(-5, 0), pos + Vector2(5, 0), outline_color, 1.5)
	draw_line(pos + Vector2(0, -5), pos + Vector2(0, 5), outline_color, 1.5)
	var shoot_r: float = _get_tower_shoot_radius(b["level"])
	var range_col: Color = Color(outline_color.r, outline_color.g, outline_color.b, 0.75)
	var dot_count: int = 32
	for di in range(dot_count):
		var a1: float = float(di) / dot_count * TAU
		var a2: float = (float(di) + 0.5) / dot_count * TAU
		draw_arc(pos, shoot_r, a1, a2, 4, range_col, 2.5)

func _draw_building_diamond(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	var diamond_pts: PackedVector2Array = PackedVector2Array([
		pos + Vector2(0, -radius),
		pos + Vector2(radius, 0),
		pos + Vector2(0, radius),
		pos + Vector2(-radius, 0),
	])
	draw_colored_polygon(diamond_pts, Color(0.1, 0.1, 0.15))
	var max_cap: int = b["max_capacity"]
	if max_cap > 0:
		var fill_ratio: float = clampf(float(b["units"]) / max_cap, 0.0, 1.0)
		if fill_ratio > 0.0:
			var inner_r: float = radius * 0.7 * fill_ratio
			var fill_pts: PackedVector2Array = PackedVector2Array([
				pos + Vector2(0, -inner_r),
				pos + Vector2(inner_r, 0),
				pos + Vector2(0, inner_r),
				pos + Vector2(-inner_r, 0),
			])
			draw_colored_polygon(fill_pts, fill_color)
	for di in range(4):
		draw_line(diamond_pts[di], diamond_pts[(di + 1) % 4], outline_color, 2.0)
	draw_line(pos + Vector2(-6, 2), pos + Vector2(6, 2), outline_color, 2.0)
	draw_line(pos + Vector2(-4, -3), pos + Vector2(-4, 2), outline_color, 1.5)
	draw_line(pos + Vector2(4, -3), pos + Vector2(4, 2), outline_color, 1.5)

func _draw_building_circle(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	draw_circle(pos, radius, Color(0.1, 0.1, 0.15))
	var max_cap: int = b["max_capacity"]
	if max_cap > 0:
		var fill_ratio: float = clampf(float(b["units"]) / max_cap, 0.0, 1.0)
		if fill_ratio > 0.0:
			var fill_angle: float = fill_ratio * TAU
			var start_angle: float = PI / 2.0
			draw_arc(pos, radius * 0.6, start_angle - fill_angle, start_angle, 48, fill_color, radius * 0.8)
	draw_arc(pos, radius, 0, TAU, 48, outline_color, 2.0)

func _draw_drag_line() -> void:
	if not is_dragging or drag_source_id == -1:
		return
	var start: Vector2 = buildings[drag_source_id]["position"]
	var hover_id: int = _get_building_at(drag_current_pos)
	var end: Vector2 = drag_current_pos
	var line_color := Color(0.4, 0.7, 1.0, 0.5)
	if hover_id != -1 and hover_id != drag_source_id:
		end = buildings[hover_id]["position"]
		line_color = Color(0.5, 0.9, 0.5, 0.7)
	draw_line(start, end, line_color, 2.0)

func _draw_unit_group_lines() -> void:
	for g in unit_groups:
		var start: Vector2 = g["start_pos"]
		var end_p: Vector2 = g["end_pos"]
		var line_color: Color
		if g["owner"] == "player":
			line_color = Color(0.3, 0.5, 1.0, 0.15)
		else:
			line_color = Color(1.0, 0.5, 0.2, 0.15)
		draw_line(start, end_p, line_color, 1.0)

func _draw_unit_groups() -> void:
	for g in unit_groups:
		var start: Vector2 = g["start_pos"]
		var end_p: Vector2 = g["end_pos"]
		var t: float = g["progress"]
		var eased_t: float = _ease_out_cubic(t)
		var current: Vector2 = start.lerp(end_p, eased_t)
		var dot_color: Color
		var text_color: Color
		if g["owner"] == "player":
			dot_color = Color(0.3, 0.5, 1.0, 0.9)
			text_color = Color(0.8, 0.9, 1.0)
		else:
			dot_color = Color(1.0, 0.55, 0.15, 0.9)
			text_color = Color(1.0, 0.8, 0.6)
		draw_circle(current, 6.0, dot_color)
		var font := ThemeDB.fallback_font
		var text: String = str(g["count"])
		draw_string(font, current + Vector2(8, -4),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)

func _draw_context_menu() -> void:
	if context_menu_building_id == -1 or context_menu_options.is_empty():
		return
	var font := ThemeDB.fallback_font
	for opt in context_menu_options:
		var r: Rect2 = opt["rect"]
		# Background
		if opt["enabled"]:
			draw_rect(r, Color(0.15, 0.18, 0.28, 0.95))
		else:
			draw_rect(r, Color(0.12, 0.12, 0.16, 0.9))
		# Border
		draw_rect(r, Color(0.35, 0.45, 0.7, 0.8), false, 1.0)
		# Text
		var text_color: Color
		if opt["enabled"]:
			text_color = Color(0.9, 0.95, 1.0)
		else:
			text_color = Color(0.4, 0.4, 0.45)
		var label: String = opt["label"]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var tx: float = r.position.x + 8.0
		var ty: float = r.position.y + (r.size.y + text_size.y) / 2.0 - 2.0
		draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)

func _draw_hud() -> void:
	var font := ThemeDB.fallback_font

	if current_mode == "neutral":
		var owned: int = 0
		for b in buildings:
			if b["owner"] == "player":
				owned += 1
		var hud_text: String = "Buildings: %d/%d" % [owned, buildings.size()]
		draw_string(font, Vector2(10, 24), hud_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.9))
	else:
		# AI mode: show player vs opponent counts
		var player_count: int = 0
		var opponent_count: int = 0
		var neutral_count: int = 0
		for b in buildings:
			if b["owner"] == "player":
				player_count += 1
			elif b["owner"] == "opponent":
				opponent_count += 1
			else:
				neutral_count += 1
		var hud_text: String = "You: %d  |  Neutral: %d  |  AI: %d" % [player_count, neutral_count, opponent_count]
		draw_string(font, Vector2(10, 24), hud_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.9))

	# Instructions
	var help_text: String = "Click: menu  |  Right-click: quick upgrade  |  Drag: send  |  Forges: +10% str  |  Towers: shoot enemies"
	draw_string(font, Vector2(10, 590), help_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6, 0.8))

	# Send ratio bar
	_draw_ratio_bar()

	if game_won:
		var win_text: String = "VICTORY! All buildings captured!" if current_mode == "neutral" else "VICTORY! Opponent defeated!"
		_draw_end_overlay(win_text, Color(1, 1, 0.3))

	if game_lost:
		_draw_end_overlay("DEFEATED! All your buildings lost.", Color(1.0, 0.3, 0.3))

func _draw_end_overlay(text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
	draw_string(font, Vector2(SCREEN_W / 2.0 - text_size.x / 2, 280),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, color)
	var click_text := "Click anywhere to return to menu"
	var ct_size := font.get_string_size(click_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	draw_string(font, Vector2(SCREEN_W / 2.0 - ct_size.x / 2, 320),
		click_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.7))

func _draw_ratio_bar() -> void:
	var font := ThemeDB.fallback_font
	var bar_x: float = 8.0
	var bar_w: float = 36.0
	var bar_y: float = 80.0
	var section_h: float = 50.0
	var display_labels: Array = ["100%", "75%", "50%", "25%"]
	var display_ratios: Array = [1.0, 0.75, 0.5, 0.25]

	draw_rect(Rect2(bar_x, bar_y, bar_w, section_h * 4), Color(0.1, 0.1, 0.15, 0.9))

	for i in range(4):
		var sy: float = bar_y + i * section_h
		var is_selected: bool = absf(send_ratio - display_ratios[i]) < 0.01

		if is_selected:
			draw_rect(Rect2(bar_x, sy, bar_w, section_h), Color(0.2, 0.4, 0.9, 0.7))

		if i > 0:
			draw_line(Vector2(bar_x, sy), Vector2(bar_x + bar_w, sy), Color(0.3, 0.3, 0.4), 1.0)

		var label: String = display_labels[i]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		var tx: float = bar_x + (bar_w - text_size.x) / 2.0
		var ty: float = sy + (section_h + text_size.y) / 2.0 - 2.0
		var text_color := Color(1, 1, 1) if is_selected else Color(0.6, 0.6, 0.6)
		draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_color)

	draw_rect(Rect2(bar_x, bar_y, bar_w, section_h * 4), Color(0.4, 0.4, 0.5), false, 1.0)
