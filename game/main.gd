extends Node2D

# === Game State Machine ===
var game_state: String = "level_select"  # "level_select" or "playing"
var current_mode: String = ""  # "neutral" or "ai"
var current_level: int = 0

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
const AI_INTERVAL: float = 5.0
const AI_SEND_RATIO: float = 0.6

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
	level_buttons.append({
		"rect": Rect2(right_x, start_y, btn_w, btn_h),
		"mode": "ai",
		"level": 1,
		"label": "Level 1",
	})

func _init_sounds() -> void:
	var sample_rate := 22050
	# Click: short sine blip 800Hz, ~80ms
	sfx_click = AudioStreamPlayer.new()
	sfx_click.bus = "Master"
	add_child(sfx_click)
	var click_samples := int(sample_rate * 0.08)
	var click_wav := AudioStreamWAV.new()
	click_wav.format = AudioStreamWAV.FORMAT_8_BITS
	click_wav.mix_rate = sample_rate
	click_wav.stereo = false
	var click_data := PackedByteArray()
	click_data.resize(click_samples)
	for i in range(click_samples):
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / click_samples
		var val := sin(TAU * 800.0 * t) * env
		click_data[i] = int((val * 0.5 + 0.5) * 255.0)
	click_wav.data = click_data
	sfx_click.stream = click_wav

	# Whoosh: noise sweep with fade, ~200ms
	sfx_whoosh = AudioStreamPlayer.new()
	sfx_whoosh.bus = "Master"
	add_child(sfx_whoosh)
	var whoosh_samples := int(sample_rate * 0.2)
	var whoosh_wav := AudioStreamWAV.new()
	whoosh_wav.format = AudioStreamWAV.FORMAT_8_BITS
	whoosh_wav.mix_rate = sample_rate
	whoosh_wav.stereo = false
	var whoosh_data := PackedByteArray()
	whoosh_data.resize(whoosh_samples)
	for i in range(whoosh_samples):
		var progress := float(i) / whoosh_samples
		var env := 1.0 - progress
		env *= env
		var noise := randf_range(-1.0, 1.0) * env
		whoosh_data[i] = int((noise * 0.5 + 0.5) * 255.0)
	whoosh_wav.data = whoosh_data
	sfx_whoosh.stream = whoosh_wav

	# Capture chime: two-tone ascending C5->E5, ~250ms
	sfx_capture = AudioStreamPlayer.new()
	sfx_capture.bus = "Master"
	add_child(sfx_capture)
	var cap_samples := int(sample_rate * 0.25)
	var cap_wav := AudioStreamWAV.new()
	cap_wav.format = AudioStreamWAV.FORMAT_8_BITS
	cap_wav.mix_rate = sample_rate
	cap_wav.stereo = false
	var cap_data := PackedByteArray()
	cap_data.resize(cap_samples)
	for i in range(cap_samples):
		var t := float(i) / sample_rate
		var p := float(i) / cap_samples
		var env := 1.0 - p
		var freq := 523.25 if p < 0.5 else 659.25
		var val := sin(TAU * freq * t) * env
		cap_data[i] = int((val * 0.5 + 0.5) * 255.0)
	cap_wav.data = cap_data
	sfx_capture.stream = cap_wav

	# Upgrade ding: bright sine with harmonics, 1200Hz, ~200ms
	sfx_upgrade = AudioStreamPlayer.new()
	sfx_upgrade.bus = "Master"
	add_child(sfx_upgrade)
	var ding_samples := int(sample_rate * 0.2)
	var ding_wav := AudioStreamWAV.new()
	ding_wav.format = AudioStreamWAV.FORMAT_8_BITS
	ding_wav.mix_rate = sample_rate
	ding_wav.stereo = false
	var ding_data := PackedByteArray()
	ding_data.resize(ding_samples)
	for i in range(ding_samples):
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / ding_samples
		var val := (sin(TAU * 1200.0 * t) + 0.5 * sin(TAU * 2400.0 * t)) * env / 1.5
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
	var neutral_units: Array = [0, 8, 12, 10, 15, 7, 5, 10, 12]

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

	return {"positions": positions, "units": neutral_units, "player_indices": [0], "opponent_indices": []}

func _get_ai_level(level: int) -> Dictionary:
	# AI level 1: player bottom-left, opponent top-right, neutrals in between
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
	return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1]}

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

	for i in range(positions.size()):
		var owner: String
		if i in player_indices:
			owner = "player"
		elif i in opponent_indices:
			owner = "opponent"
		else:
			owner = "neutral"
		buildings.append({
			"id": i,
			"position": positions[i],
			"owner": owner,
			"units": units[i],
			"level": 1,
			"max_capacity": 10,
			"gen_timer": 0.0,
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
		var level: int = b["level"]
		var max_cap: int = 10 * level
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
		# Combat
		var defenders: int = target["units"]
		var attackers: int = group["count"]
		if attackers >= defenders:
			# Capture
			target["units"] = attackers - defenders
			target["owner"] = group["owner"]
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
		else:
			target["units"] = defenders - attackers

func _get_owner_color(owner: String) -> Color:
	if owner == "player":
		return Color(0.3, 0.5, 1.0)
	elif owner == "opponent":
		return Color(1.0, 0.6, 0.2)
	else:
		return Color(0.6, 0.6, 0.6)

# === AI Logic ===

func _update_ai(delta: float) -> void:
	ai_timer += delta
	if ai_timer < AI_INTERVAL:
		return
	ai_timer -= AI_INTERVAL

	# Gather AI buildings
	var ai_buildings: Array = []
	for b in buildings:
		if b["owner"] == "opponent":
			ai_buildings.append(b)
	if ai_buildings.is_empty():
		return

	# Weighted action selection: upgrade=30, attack=70
	var roll: float = randf() * 100.0

	if roll < 30.0:
		_ai_try_upgrade(ai_buildings)
	else:
		_ai_try_attack(ai_buildings)

func _ai_try_upgrade(ai_buildings: Array) -> void:
	for b in ai_buildings:
		if b["level"] < 3 and b["units"] >= 10:
			b["units"] -= 10
			b["level"] += 1
			b["max_capacity"] = 10 * b["level"]
			return
	# Can't upgrade, attack instead
	_ai_try_attack(ai_buildings)

func _ai_try_attack(ai_buildings: Array) -> void:
	# Find best source (most units)
	var best_source: Dictionary = {}
	var best_units: int = 0
	for b in ai_buildings:
		if b["units"] > best_units:
			best_units = b["units"]
			best_source = b
	if best_source.is_empty() or best_units < 3:
		return

	# Find weakest non-opponent building
	var best_target: Dictionary = {}
	var lowest_units: int = 9999
	for b in buildings:
		if b["owner"] == "opponent":
			continue
		# Prefer buildings close to AI buildings
		if b["units"] < lowest_units:
			lowest_units = b["units"]
			best_target = b
	if best_target.is_empty():
		return

	# Send units
	var send_count: int = int(best_source["units"] * AI_SEND_RATIO)
	if send_count <= 0:
		return
	best_source["units"] -= send_count
	unit_groups.append({
		"count": send_count,
		"source_id": best_source["id"],
		"target_id": best_target["id"],
		"owner": "opponent",
		"progress": 0.0,
		"speed": 150.0,
		"start_pos": best_source["position"],
		"end_pos": best_target["position"],
	})

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
		if b["level"] < 3 and b["units"] >= 10:
			b["units"] -= 10
			b["level"] += 1
			b["max_capacity"] = 10 * b["level"]
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

		# Draw building background (dark)
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

		# Upgrade ready indicator — pulsing gold ring (player only)
		if b["owner"] == "player" and b["level"] < 3 and b["units"] >= 10:
			var pulse_alpha: float = 0.4 + 0.4 * sin(game_time * 4.0)
			draw_arc(pos, radius + 6, 0, TAU, 48, Color(1.0, 0.85, 0.2, pulse_alpha), 2.0)

		# Selection highlight
		if b["id"] == selected_building_id:
			draw_arc(pos, radius + 4, 0, TAU, 48, Color(1, 1, 0.3, 0.9), 3.0)

		# Level indicator — small dots around the building
		for lv in range(b["level"]):
			var angle: float = -PI / 2 + lv * (TAU / 3.0)
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
	var help_text: String = "Drag or click-click: send units  |  Right-click: upgrade"
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
