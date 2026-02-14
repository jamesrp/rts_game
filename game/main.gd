extends Node2D

# === Building Data ===
var buildings: Array = []
# Each building: {id, position, owner, units, level, max_capacity, gen_timer}

# === Unit Groups ===
var unit_groups: Array = []
# Each group: {count, source_id, target_id, owner, progress, speed, start_pos, end_pos}

# === Selection State ===
var selected_building_id: int = -1

# === Game State ===
var game_won: bool = false

func _ready() -> void:
	_init_buildings()

func _init_buildings() -> void:
	var positions := [
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
	var neutral_units := [0, 8, 12, 10, 15, 7, 5, 10, 12]

	for i in range(positions.size()):
		var owner: String
		var units: int
		if i == 0:
			owner = "player"
			units = 20
		else:
			owner = "neutral"
			units = neutral_units[i]
		buildings.append({
			"id": i,
			"position": positions[i],
			"owner": owner,
			"units": units,
			"level": 1,
			"max_capacity": 10,
			"gen_timer": 0.0,
		})

func _process(delta: float) -> void:
	if game_won:
		queue_redraw()
		return

	_update_unit_generation(delta)
	_update_unit_groups(delta)
	_check_win_condition()
	queue_redraw()

func _update_unit_generation(delta: float) -> void:
	for b in buildings:
		if b["owner"] != "player":
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
	# Remove resolved groups in reverse order
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
		else:
			target["units"] = defenders - attackers

func _check_win_condition() -> void:
	for b in buildings:
		if b["owner"] != "player":
			return
	game_won = true

func _input(event: InputEvent) -> void:
	if game_won:
		return
	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(pos)

func _handle_left_click(pos: Vector2) -> void:
	var clicked_id: int = _get_building_at(pos)

	if selected_building_id == -1:
		# Nothing selected — try to select a player building
		if clicked_id != -1 and buildings[clicked_id]["owner"] == "player":
			selected_building_id = clicked_id
	else:
		if clicked_id == -1 or clicked_id == selected_building_id:
			# Clicked empty space or same building — deselect
			selected_building_id = -1
		elif clicked_id != selected_building_id:
			# Send units to target
			_send_units(selected_building_id, clicked_id)
			selected_building_id = -1

func _handle_right_click(pos: Vector2) -> void:
	var clicked_id: int = _get_building_at(pos)
	if clicked_id != -1 and buildings[clicked_id]["owner"] == "player":
		# Try to upgrade
		var b: Dictionary = buildings[clicked_id]
		if b["level"] < 3 and b["units"] >= 10:
			b["units"] -= 10
			b["level"] += 1
			b["max_capacity"] = 10 * b["level"]
			selected_building_id = -1
			return
	selected_building_id = -1

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
	var send_count: int = source["units"] / 2
	if send_count <= 0:
		return
	source["units"] -= send_count
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
	_draw_background()
	_draw_unit_group_lines()
	_draw_buildings()
	_draw_unit_groups()
	_draw_hud()

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
		else:
			fill_color = Color(0.4, 0.4, 0.4, 0.85)
			outline_color = Color(0.6, 0.6, 0.6)

		# Draw building circle
		draw_circle(pos, radius, fill_color)
		# Outline
		draw_arc(pos, radius, 0, TAU, 48, outline_color, 2.0)

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

func _draw_unit_group_lines() -> void:
	for g in unit_groups:
		var start: Vector2 = g["start_pos"]
		var end_p: Vector2 = g["end_pos"]
		draw_line(start, end_p, Color(0.3, 0.5, 1.0, 0.15), 1.0)

func _draw_unit_groups() -> void:
	for g in unit_groups:
		var start: Vector2 = g["start_pos"]
		var end_p: Vector2 = g["end_pos"]
		var current: Vector2 = start.lerp(end_p, g["progress"])
		# Draw group dot
		draw_circle(current, 6.0, Color(0.3, 0.5, 1.0, 0.9))
		# Draw count
		var font := ThemeDB.fallback_font
		var text: String = str(g["count"])
		draw_string(font, current + Vector2(8, -4),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.9, 1.0))

func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var owned: int = 0
	for b in buildings:
		if b["owner"] == "player":
			owned += 1
	var hud_text: String = "Buildings: %d/%d" % [owned, buildings.size()]
	draw_string(font, Vector2(10, 24), hud_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.9))

	# Instructions
	var help_text: String = "Left-click: select/send  |  Right-click: upgrade/deselect"
	draw_string(font, Vector2(10, 590), help_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6, 0.8))

	if game_won:
		var win_text: String = "VICTORY! All buildings captured!"
		var win_size := font.get_string_size(win_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		draw_string(font, Vector2(400 - win_size.x / 2, 300),
			win_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 1, 0.3))
