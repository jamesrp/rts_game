extends Node2D

# === Game State Machine ===
var game_state: String = "level_select"  # "level_select" or "playing"
var current_mode: String = ""  # "neutral" or "ai"
var current_level: int = 0

const MAX_BUILDING_LEVEL: int = 4

# === Building Data ===
var buildings: Array = []
# Each building: {id, position, owner, units, level, max_capacity, gen_timer}

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

func _init_sounds() -> void:
	var sample_rate := 22050
	# Click: soft sine pop 440Hz, ~100ms, exponential decay with fade-in
	sfx_click = AudioStreamPlayer.new()
	sfx_click.bus = "Master"
	add_child(sfx_click)
	var click_samples := int(sample_rate * 0.10)
	var click_wav := AudioStreamWAV.new()
	click_wav.format = AudioStreamWAV.FORMAT_8_BITS
	click_wav.mix_rate = sample_rate
	click_wav.stereo = false
	var click_data := PackedByteArray()
	click_data.resize(click_samples)
	for i in range(click_samples):
		var t := float(i) / sample_rate
		var p := float(i) / click_samples
		var attack := minf(p / 0.05, 1.0)
		var env := attack * exp(-6.0 * p)
		var val := sin(TAU * 440.0 * t) * env * 0.7
		click_data[i] = int((val * 0.5 + 0.5) * 255.0)
	click_wav.data = click_data
	sfx_click.stream = click_wav

	# Whoosh: filtered noise with smooth envelope, ~250ms
	sfx_whoosh = AudioStreamPlayer.new()
	sfx_whoosh.bus = "Master"
	add_child(sfx_whoosh)
	var whoosh_samples := int(sample_rate * 0.25)
	var whoosh_wav := AudioStreamWAV.new()
	whoosh_wav.format = AudioStreamWAV.FORMAT_8_BITS
	whoosh_wav.mix_rate = sample_rate
	whoosh_wav.stereo = false
	var whoosh_data := PackedByteArray()
	whoosh_data.resize(whoosh_samples)
	var prev_noise := 0.0
	for i in range(whoosh_samples):
		var p := float(i) / whoosh_samples
		var attack := minf(p / 0.1, 1.0)
		var env := attack * exp(-4.0 * p)
		var raw := randf_range(-1.0, 1.0)
		prev_noise = prev_noise * 0.7 + raw * 0.3
		whoosh_data[i] = int((prev_noise * env * 0.5 * 0.5 + 0.5) * 255.0)
	whoosh_wav.data = whoosh_data
	sfx_whoosh.stream = whoosh_wav

	# Capture chime: two-tone ascending C4->E4, ~350ms, smooth crossfade
	sfx_capture = AudioStreamPlayer.new()
	sfx_capture.bus = "Master"
	add_child(sfx_capture)
	var cap_samples := int(sample_rate * 0.35)
	var cap_wav := AudioStreamWAV.new()
	cap_wav.format = AudioStreamWAV.FORMAT_8_BITS
	cap_wav.mix_rate = sample_rate
	cap_wav.stereo = false
	var cap_data := PackedByteArray()
	cap_data.resize(cap_samples)
	for i in range(cap_samples):
		var t := float(i) / sample_rate
		var p := float(i) / cap_samples
		var attack := minf(p / 0.05, 1.0)
		var env := attack * exp(-3.0 * p)
		var blend := clampf((p - 0.4) / 0.2, 0.0, 1.0)
		var freq := lerpf(261.63, 329.63, blend)
		var val := sin(TAU * freq * t) * env * 0.7
		cap_data[i] = int((val * 0.5 + 0.5) * 255.0)
	cap_wav.data = cap_data
	sfx_capture.stream = cap_wav

	# Upgrade ding: warm sine 600Hz, gentle harmonic, ~300ms
	sfx_upgrade = AudioStreamPlayer.new()
	sfx_upgrade.bus = "Master"
	add_child(sfx_upgrade)
	var ding_samples := int(sample_rate * 0.3)
	var ding_wav := AudioStreamWAV.new()
	ding_wav.format = AudioStreamWAV.FORMAT_8_BITS
	ding_wav.mix_rate = sample_rate
	ding_wav.stereo = false
	var ding_data := PackedByteArray()
	ding_data.resize(ding_samples)
	for i in range(ding_samples):
		var t := float(i) / sample_rate
		var p := float(i) / ding_samples
		var attack := minf(p / 0.05, 1.0)
		var env := attack * exp(-4.0 * p)
		var val := (sin(TAU * 600.0 * t) + 0.2 * sin(TAU * 1200.0 * t)) * env * 0.6
		ding_data[i] = int((val * 0.5 + 0.5) * 255.0)
	ding_wav.data = ding_data
	sfx_upgrade.stream = ding_wav

# === Level Configurations ===

func _get_neutral_level(level: int) -> Dictionary:
	# Level 1: original layout (9 buildings)
	# Levels 2-4: add more neutral buildings
	var positions: Array = [
		Vector2(120, 300),   # Player start
		Vector2(300, 100),
		Vector2(500, 80),
		Vector2(680, 200),
		Vector2(650, 420),
		Vector2(450, 500),
		Vector2(250, 480),
		Vector2(400, 280),
		Vector2(700, 550),
	]
	var neutral_units: Array = [5, 8, 12, 10, 15, 7, 5, 10, 12]

	# Extra buildings for higher levels
	var extra_positions: Array = [
		Vector2(160, 140),
		Vector2(560, 300),
		Vector2(340, 380),
		Vector2(750, 100),
		Vector2(100, 500),
		Vector2(550, 550),
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
	return {"positions": positions, "units": neutral_units, "player_indices": [0], "opponent_indices": [], "forges": valid_forges}

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
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1], "forges": [4, 8]}
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
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1], "forges": [4, 7, 12]}
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
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1, 2], "forges": [4, 7, 10]}
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
			"upgrades": {2: 2}, "forges": [4, 8, 11, 13]}  # Building index 2 starts at level 2

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

	for i in range(positions.size()):
		var owner: String
		if i in player_indices:
			owner = "player"
		elif i in opponent_indices:
			owner = "opponent"
		else:
			owner = "neutral"
		var bld_level: int = upgrades.get(i, 1)
		var bld_type: String = "forge" if i in forge_indices else "normal"
		buildings.append({
			"id": i,
			"position": positions[i],
			"owner": owner,
			"units": units[i],
			"level": bld_level,
			"max_capacity": 20 * bld_level,
			"gen_timer": 0.0,
			"type": bld_type,
		})

func _return_to_menu() -> void:
	game_state = "level_select"
	buildings.clear()
	unit_groups.clear()
	visual_effects.clear()

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
		if b["owner"] == "neutral":
			continue
		if b["type"] == "forge":
			continue
		var level: int = b["level"]
		var max_cap: int = 20 * level
		b["max_capacity"] = max_cap
		if b["units"] >= max_cap:
			continue
		b["gen_timer"] += delta
		var interval: float = 2.0 / level
		while b["gen_timer"] >= interval and b["units"] < max_cap:
			b["gen_timer"] -= interval
			b["units"] += 1

func _update_unit_groups(delta: float) -> void:
	var resolved: Array = []
	for i in range(unit_groups.size()):
		var g: Dictionary = unit_groups[i]
		var dist: float = g["start_pos"].distance_to(g["end_pos"])
		if dist < 1.0:
			dist = 1.0
		g["progress"] += (150.0 / dist) * delta
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
			if target["type"] != "forge":
				target["level"] = 1
			target["gen_timer"] = 0.0
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
	_ai_send_one(ai_buildings, _ai_find_weakest_any(ai_buildings))

# --- Level 2: Expander ---
# Prioritize neutrals. Can send from 2 buildings per turn.

func _ai_expander(ai_buildings: Array) -> void:
	if randf() < 0.2:
		if _ai_do_upgrade(ai_buildings):
			return

	# Prefer neutral targets; fall back to player targets
	var target: Dictionary = _ai_find_weakest_neutral(ai_buildings)
	if target.is_empty():
		target = _ai_find_weakest_player(ai_buildings)
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
	var target: Dictionary = _ai_find_weakest_player(ai_buildings)
	if target.is_empty():
		target = _ai_find_weakest_neutral(ai_buildings)
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

# === Upgrade Helpers ===

func _get_upgrade_cost(level: int) -> int:
	match level:
		1: return 5
		2: return 10
		3: return 20
		_: return 999

# === AI Helpers ===

func _ai_do_upgrade(ai_buildings: Array) -> bool:
	# Upgrade the building with the most units first (better investment)
	var sorted: Array = _ai_sort_by_units(ai_buildings)
	for b in sorted:
		if b["type"] == "forge":
			continue
		var cost: int = _get_upgrade_cost(b["level"])
		if b["level"] < MAX_BUILDING_LEVEL and b["units"] >= cost:
			b["units"] -= cost
			b["level"] += 1
			b["max_capacity"] = 20 * b["level"]
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
		"speed": 150.0,
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

func _ai_find_weakest_any(ai_buildings: Array) -> Dictionary:
	var best: Dictionary = {}
	var lowest: int = 9999
	for b in buildings:
		if b["owner"] == "opponent":
			continue
		if b["units"] < lowest:
			lowest = b["units"]
			best = b
	return best

func _ai_find_weakest_neutral(_ai_buildings: Array) -> Dictionary:
	var best: Dictionary = {}
	var lowest: int = 9999
	for b in buildings:
		if b["owner"] != "neutral":
			continue
		if b["units"] < lowest:
			lowest = b["units"]
			best = b
	return best

func _ai_find_weakest_player(_ai_buildings: Array) -> Dictionary:
	var best: Dictionary = {}
	var lowest: int = 9999
	for b in buildings:
		if b["owner"] != "player":
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
		selected_building_id = drag_source_id
		sfx_click.play()
	is_dragging = false
	drag_source_id = -1

func _handle_right_click(pos: Vector2) -> void:
	var clicked_id: int = _get_building_at(pos)
	if clicked_id != -1 and buildings[clicked_id]["owner"] == "player":
		var b: Dictionary = buildings[clicked_id]
		if b["type"] == "forge":
			selected_building_id = -1
			return
		var cost: int = _get_upgrade_cost(b["level"])
		if b["level"] < MAX_BUILDING_LEVEL and b["units"] >= cost:
			b["units"] -= cost
			b["level"] += 1
			b["max_capacity"] = 20 * b["level"]
			sfx_upgrade.play()
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
		var radius: float = 20.0 + b["level"] * 5.0
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
		"speed": 150.0,
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

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 800, 600), Color(0.08, 0.08, 0.12))
	var grid_color := Color(0.14, 0.14, 0.2)
	for x in range(0, 801, 40):
		draw_line(Vector2(x, 0), Vector2(x, 600), grid_color)
	for y in range(0, 601, 40):
		draw_line(Vector2(0, y), Vector2(800, y), grid_color)

func _draw_buildings() -> void:
	for b in buildings:
		var pos: Vector2 = b["position"]
		var radius: float = 20.0 + b["level"] * 5.0
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

		if is_forge:
			# Draw forge as diamond shape
			var diamond_pts: PackedVector2Array = PackedVector2Array([
				pos + Vector2(0, -radius),       # top
				pos + Vector2(radius, 0),        # right
				pos + Vector2(0, radius),        # bottom
				pos + Vector2(-radius, 0),       # left
			])
			# Background
			var bg_pts: PackedVector2Array = PackedVector2Array([
				pos + Vector2(0, -radius),
				pos + Vector2(radius, 0),
				pos + Vector2(0, radius),
				pos + Vector2(-radius, 0),
			])
			draw_colored_polygon(bg_pts, Color(0.1, 0.1, 0.15))
			# Fill based on capacity
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
			# Diamond outline
			for di in range(4):
				draw_line(diamond_pts[di], diamond_pts[(di + 1) % 4], outline_color, 2.0)
			# Small anvil-like mark inside (horizontal line with two short verticals)
			draw_line(pos + Vector2(-6, 2), pos + Vector2(6, 2), outline_color, 2.0)
			draw_line(pos + Vector2(-4, -3), pos + Vector2(-4, 2), outline_color, 1.5)
			draw_line(pos + Vector2(4, -3), pos + Vector2(4, 2), outline_color, 1.5)
		else:
			# Draw normal building as circle
			draw_circle(pos, radius, Color(0.1, 0.1, 0.15))

			# Draw capacity fill arc (from bottom, clockwise)
			var max_cap: int = b["max_capacity"]
			if max_cap > 0:
				var fill_ratio: float = clampf(float(b["units"]) / max_cap, 0.0, 1.0)
				if fill_ratio > 0.0:
					var fill_angle: float = fill_ratio * TAU
					var start_angle: float = PI / 2.0
					draw_arc(pos, radius * 0.6, start_angle - fill_angle, start_angle, 48, fill_color, radius * 0.8)

			# Outline
			draw_arc(pos, radius, 0, TAU, 48, outline_color, 2.0)

		# Upgrade ready indicator — pulsing gold ring (player only, not forges)
		if not is_forge and b["owner"] == "player" and b["level"] < MAX_BUILDING_LEVEL and b["units"] >= _get_upgrade_cost(b["level"]):
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
			else:
				draw_arc(pos, radius + 4, 0, TAU, 48, Color(1, 1, 0.3, 0.9), 3.0)

		# Level indicator — small dots around the building (skip for forges)
		if not is_forge:
			for lv in range(b["level"]):
				var angle: float = -PI / 2 + lv * (TAU / MAX_BUILDING_LEVEL)
				var dot_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * (radius + 10)
				draw_circle(dot_pos, 3.0, Color.WHITE)

		# Unit count text
		var font := ThemeDB.fallback_font
		var text: String = str(b["units"])
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, pos - Vector2(text_size.x / 2, -5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

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
		var eased_t: float = 1.0 - pow(1.0 - t, 3.0)
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
	var help_text: String = "Drag or click-click: send units  |  Right-click: upgrade  |  Forges buff army strength (+10% each)"
	draw_string(font, Vector2(10, 590), help_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6, 0.8))

	# Send ratio bar
	_draw_ratio_bar()

	if game_won:
		var win_text: String = "VICTORY!"
		if current_mode == "neutral":
			win_text = "VICTORY! All buildings captured!"
		else:
			win_text = "VICTORY! Opponent defeated!"
		var win_size := font.get_string_size(win_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		draw_string(font, Vector2(400 - win_size.x / 2, 280),
			win_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 1, 0.3))
		var click_text := "Click anywhere to return to menu"
		var ct_size := font.get_string_size(click_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, Vector2(400 - ct_size.x / 2, 320),
			click_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.7))

	if game_lost:
		var lose_text: String = "DEFEATED! All your buildings lost."
		var lose_size := font.get_string_size(lose_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		draw_string(font, Vector2(400 - lose_size.x / 2, 280),
			lose_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0, 0.3, 0.3))
		var click_text := "Click anywhere to return to menu"
		var ct_size := font.get_string_size(click_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, Vector2(400 - ct_size.x / 2, 320),
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
