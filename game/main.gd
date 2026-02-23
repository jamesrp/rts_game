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
const MAX_ARMY_WIDTH: int = 5
const ARMY_WAVES_PER_SECOND: float = 3.0
const UNIT_TRIANGLE_SIZE: float = 3.0
const UNIT_FORMATION_SPACING: float = 7.0

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
var run_map: Array = []  # Array of rows, each row is array of node dicts
var run_current_row: int = 0
var run_last_node: int = -1  # Column index chosen in current row
var run_overlay: String = ""  # "", "run_over", "run_won", "merchant"
var home_base_id: int = -1

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

	# Roguelike button (centered below both columns)
	level_buttons.append({
		"rect": Rect2(cx - 120, start_y + 4 * (btn_h + gap) + 30, 240, 52),
		"mode": "roguelike",
		"level": 0,
		"label": "Start Run",
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

# === Roguelike Run ===

func _format_run_time() -> String:
	var total_sec: int = int(ceil(run_time_left))
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%d:%02d" % [mins, secs]

func _start_roguelike_run() -> void:
	run_time_left = 600.0
	run_act = 1
	run_gold = 0
	run_current_row = 0
	run_last_node = -1
	run_overlay = ""
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
			var x: float = _get_map_node_x(col_idx, count)
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

func _get_map_node_x(col: int, total: int) -> float:
	if total == 1:
		return 400.0
	var margin: float = 150.0
	var spacing: float = (800.0 - 2.0 * margin) / float(total - 1)
	return margin + col * spacing

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
		if is_elite:
			ai_level += 1
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
	context_menu_building_id = -1
	context_menu_options.clear()
	in_roguelike_run = false
	home_base_id = -1

	if won:
		run_map[run_current_row][run_last_node]["completed"] = true
		var node_type_r: String = run_map[run_current_row][run_last_node]["type"]
		# Award gold based on node type
		match node_type_r:
			"boss": run_gold += randi_range(40, 60)
			"elite": run_gold += randi_range(25, 35)
			_: run_gold += randi_range(10, 20)
		var is_boss: bool = node_type_r == "boss"
		if is_boss:
			if run_act >= 3:
				run_overlay = "run_won"
				game_state = "roguelike_map"
			else:
				run_act += 1
				run_map = _generate_run_map(run_act)
				run_current_row = 0
				run_last_node = -1
				game_state = "roguelike_map"
		else:
			run_current_row += 1
			game_state = "roguelike_map"
	else:
		# Lost the battle — run is over
		run_overlay = "run_over"
		game_state = "roguelike_map"

func _abandon_roguelike_run() -> void:
	game_state = "level_select"
	run_map.clear()

func _input_roguelike_map(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if run_overlay == "":
				_abandon_roguelike_run()
		return

	# Merchant overlay: handle shop button clicks
	if run_overlay == "merchant":
		var spend_rect := Rect2(280, 255, 240, 44)
		var leave_rect := Rect2(310, 315, 180, 40)
		if spend_rect.has_point(event.position) and run_gold >= 50:
			run_gold -= 50
			sfx_click.play()
		elif leave_rect.has_point(event.position):
			run_map[run_current_row][run_last_node]["completed"] = true
			run_current_row += 1
			run_overlay = ""
			sfx_click.play()
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
				run_overlay = "merchant"
			else:
				_start_roguelike_battle(col_idx)
			return

func _draw_roguelike_map() -> void:
	_draw_background()
	var font := ThemeDB.fallback_font

	# Title
	var title := "ACT %d" % run_act
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
	draw_string(font, Vector2(400 - title_size.x / 2, 40), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.9, 0.85, 0.6))

	# Gold counter
	var gold_text := "Gold: %d" % run_gold
	draw_string(font, Vector2(30, 40), gold_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.2))

	# Run time display (top-right)
	var time_str := _format_run_time()
	var time_col := Color(0.9, 0.9, 0.9)
	if run_time_left < 30.0:
		time_col = Color(1.0, 0.3, 0.3) if int(game_time * 2.0) % 2 == 0 else Color(0.8, 0.15, 0.15)
	elif run_time_left < 60.0:
		time_col = Color(1.0, 0.65, 0.2)
	var time_label := "Time: " + time_str
	var tl_size := font.get_string_size(time_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2(780 - tl_size.x, 40), time_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, time_col)
	var tbar_x: float = 780.0 - tl_size.x
	var tbar_y: float = 47.0
	var tbar_w: float = tl_size.x
	var tbar_h: float = 6.0
	draw_rect(Rect2(tbar_x, tbar_y, tbar_w, tbar_h), Color(0.12, 0.12, 0.15))
	var tbar_fill: float = tbar_w * clampf(run_time_left / 600.0, 0.0, 1.0)
	var tbar_col := Color(0.3, 0.8, 0.4) if run_time_left >= 60.0 else Color(0.9, 0.4, 0.1)
	draw_rect(Rect2(tbar_x, tbar_y, tbar_fill, tbar_h), tbar_col)

	# Draw edges
	for row_idx in range(run_map.size() - 1):
		for col_idx in range(run_map[row_idx].size()):
			var node: Dictionary = run_map[row_idx][col_idx]
			for next_col in node["next_edges"]:
				var next_node: Dictionary = run_map[row_idx + 1][next_col]
				var edge_color := Color(0.3, 0.3, 0.4)
				if node["completed"]:
					# Highlight the path taken
					if run_map[row_idx + 1][next_col]["completed"]:
						edge_color = Color(0.3, 0.5, 0.3, 0.7)
					else:
						edge_color = Color(0.25, 0.25, 0.3)
				elif row_idx == run_current_row and _is_node_available(row_idx, col_idx):
					edge_color = Color(0.4, 0.5, 0.7, 0.5)
				draw_line(node["position"], next_node["position"], edge_color, 2.0)

	# Draw nodes
	for row_idx in range(run_map.size()):
		for col_idx in range(run_map[row_idx].size()):
			var node: Dictionary = run_map[row_idx][col_idx]
			var pos: Vector2 = node["position"]
			var available: bool = _is_node_available(row_idx, col_idx)

			if node["completed"]:
				draw_circle(pos, 14.0, Color(0.2, 0.2, 0.25))
				draw_arc(pos, 14.0, 0, TAU, 32, Color(0.3, 0.3, 0.35), 2.0)
				draw_line(pos + Vector2(-5, 0), pos + Vector2(-1, 4), Color(0.4, 0.6, 0.4), 2.0)
				draw_line(pos + Vector2(-1, 4), pos + Vector2(5, -4), Color(0.4, 0.6, 0.4), 2.0)
			elif node["type"] == "boss":
				var boss_col := Color(0.9, 0.3, 0.2) if available else Color(0.5, 0.2, 0.15)
				draw_circle(pos, 18.0, Color(0.15, 0.05, 0.05))
				draw_arc(pos, 18.0, 0, TAU, 32, boss_col, 2.5)
				# Skull-like icon: eyes and mouth
				draw_circle(pos + Vector2(-4, -3), 2.0, boss_col)
				draw_circle(pos + Vector2(4, -3), 2.0, boss_col)
				draw_line(pos + Vector2(-3, 4), pos + Vector2(3, 4), boss_col, 1.5)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(game_time * 3.0)
					draw_arc(pos, 22.0, 0, TAU, 32, Color(0.9, 0.3, 0.2, pulse), 2.0)
			elif node["type"] == "elite":
				var elite_col := Color(1.0, 0.85, 0.2) if available else Color(0.6, 0.5, 0.15)
				draw_circle(pos, 16.0, Color(0.15, 0.12, 0.02))
				draw_arc(pos, 16.0, 0, TAU, 32, elite_col, 2.5)
				# Star icon (5-pointed)
				for si in range(5):
					var angle_a: float = -PI / 2.0 + si * TAU / 5.0
					var angle_b: float = -PI / 2.0 + (si + 2) * TAU / 5.0
					var pa: Vector2 = pos + Vector2(cos(angle_a), sin(angle_a)) * 8.0
					var pb: Vector2 = pos + Vector2(cos(angle_b), sin(angle_b)) * 8.0
					draw_line(pa, pb, elite_col, 1.5)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(game_time * 3.0)
					draw_arc(pos, 20.0, 0, TAU, 32, Color(1.0, 0.85, 0.2, pulse), 2.0)
			elif node["type"] == "merchant":
				var m_col := Color(0.9, 0.75, 0.15) if available else Color(0.45, 0.38, 0.08)
				draw_circle(pos, 15.0, Color(0.12, 0.1, 0.02))
				draw_arc(pos, 15.0, 0, TAU, 32, m_col, 2.5)
				# Coin icon: filled circle with inner ring
				draw_circle(pos, 7.0, m_col)
				draw_circle(pos, 4.5, Color(0.12, 0.1, 0.02))
				draw_arc(pos, 4.5, 0, TAU, 24, m_col, 1.0)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(game_time * 3.0)
					draw_arc(pos, 19.0, 0, TAU, 32, Color(1.0, 0.85, 0.2, pulse), 2.0)
			elif available:
				var pulse: float = 0.6 + 0.3 * sin(game_time * 3.0)
				draw_circle(pos, 14.0, Color(0.15, 0.2, 0.35))
				draw_arc(pos, 14.0, 0, TAU, 32, Color(0.4, 0.6, 1.0, pulse), 2.5)
				# Crossed swords icon
				draw_line(pos + Vector2(-5, -5), pos + Vector2(5, 5), Color(0.7, 0.8, 1.0), 2.0)
				draw_line(pos + Vector2(5, -5), pos + Vector2(-5, 5), Color(0.7, 0.8, 1.0), 2.0)
			else:
				draw_circle(pos, 12.0, Color(0.12, 0.12, 0.16))
				draw_arc(pos, 12.0, 0, TAU, 32, Color(0.25, 0.25, 0.3), 1.5)

	# Row labels
	var row_labels: Array = ["I", "II", "III", "IV", "BOSS"]
	for row_idx in range(run_map.size()):
		var y: float = run_map[row_idx][0]["position"].y + 5
		var lbl: String = row_labels[row_idx] if row_idx < row_labels.size() else str(row_idx + 1)
		draw_string(font, Vector2(30, y), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.35, 0.35, 0.4))

	# Instructions
	var help := "Click a glowing node to battle  |  ESC to abandon run"
	draw_string(font, Vector2(10, 590), help,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.55))

	# Overlays
	if run_overlay == "merchant":
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.7))
		var panel := Rect2(200, 160, 400, 210)
		draw_rect(panel, Color(0.1, 0.09, 0.02))
		draw_rect(panel, Color(0.7, 0.6, 0.15), false, 2.0)
		var m_title := "MERCHANT"
		var mt_size := font.get_string_size(m_title, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
		draw_string(font, Vector2(400 - mt_size.x / 2, 198), m_title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1.0, 0.85, 0.2))
		var gold_disp := "Your gold: %d" % run_gold
		var gd_size := font.get_string_size(gold_disp, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		draw_string(font, Vector2(400 - gd_size.x / 2, 228), gold_disp,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.9, 0.9))
		# Spend button
		var spend_rect := Rect2(280, 255, 240, 44)
		var can_spend := run_gold >= 50
		draw_rect(spend_rect, Color(0.16, 0.13, 0.04) if can_spend else Color(0.12, 0.12, 0.12))
		draw_rect(spend_rect, Color(0.7, 0.6, 0.15) if can_spend else Color(0.3, 0.3, 0.3), false, 1.5)
		var spend_label := "Spend 50g  [placeholder]"
		var sl_size := font.get_string_size(spend_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
		var sl_col := Color(0.95, 0.85, 0.3) if can_spend else Color(0.4, 0.4, 0.4)
		draw_string(font, Vector2(spend_rect.position.x + (spend_rect.size.x - sl_size.x) / 2, spend_rect.position.y + 28),
			spend_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, sl_col)
		if not can_spend:
			var no_gold := "(not enough gold)"
			var ng_size := font.get_string_size(no_gold, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			draw_string(font, Vector2(400 - ng_size.x / 2, 308), no_gold,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.4, 0.4))
		# Leave button
		var leave_rect := Rect2(310, 315, 180, 40)
		draw_rect(leave_rect, Color(0.12, 0.12, 0.18))
		draw_rect(leave_rect, Color(0.35, 0.35, 0.5), false, 1.5)
		var leave_label := "Leave Shop"
		var ll_size := font.get_string_size(leave_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, Vector2(leave_rect.position.x + (leave_rect.size.x - ll_size.x) / 2, leave_rect.position.y + 26),
			leave_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.85))
	elif run_overlay == "run_over":
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.6))
		var msg := "RUN OVER"
		var msg_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 36)
		draw_string(font, Vector2(400 - msg_size.x / 2, 270), msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1.0, 0.3, 0.3))
		var sub := "Act %d  |  Click to return" % run_act
		var sub_size := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		draw_string(font, Vector2(400 - sub_size.x / 2, 310), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.5, 0.5))
	elif run_overlay == "run_won":
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.6))
		var msg := "VICTORY!"
		var msg_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 36)
		draw_string(font, Vector2(400 - msg_size.x / 2, 270), msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1.0, 0.85, 0.2))
		var sub := "All 3 acts completed!  |  Click to return"
		var sub_size := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		draw_string(font, Vector2(400 - sub_size.x / 2, 310), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.75, 0.5))

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

func _generate_roguelike_battle_map(ai_level: int, is_elite: bool) -> Dictionary:
	var node_count: int = randi_range(10, 14) + ai_level
	if is_elite:
		node_count += 2
	node_count = mini(node_count, 18)

	# Pick a layout strategy
	var strategies: Array = ["corridor", "ring", "clusters", "scattered"]
	var strategy: String = strategies[randi() % strategies.size()]

	var positions: Array = []
	var min_spacing: float = 80.0

	match strategy:
		"corridor":
			positions = _gen_corridor_layout(node_count, min_spacing)
		"ring":
			positions = _gen_ring_layout(node_count, min_spacing)
		"clusters":
			positions = _gen_clusters_layout(node_count, min_spacing)
		_:
			positions = _gen_scattered_layout(node_count, min_spacing)

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
			units.append(15 + ai_level * 2)
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
				upgrades[oi] = 2

	return {"positions": positions, "units": units, "player_indices": player_indices,
		"opponent_indices": opponent_indices, "forges": forges, "towers": towers, "upgrades": upgrades}

func _try_place_building(positions: Array, pos: Vector2, min_spacing: float) -> bool:
	# Clamp to playable area
	pos.x = clampf(pos.x, 60.0, 740.0)
	pos.y = clampf(pos.y, 60.0, 540.0)
	for existing in positions:
		if existing.distance_to(pos) < min_spacing:
			return false
	positions.append(pos)
	return true

func _gen_corridor_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	# Player bottom-left, opponent top-right, diagonal corridor with branches
	positions.append(Vector2(100, 480))  # Player
	positions.append(Vector2(700, 120))  # Opponent
	var attempts: int = 0
	while positions.size() < count and attempts < 200:
		attempts += 1
		# Points along diagonal with random offset
		var t: float = randf()
		var base_x: float = lerpf(100.0, 700.0, t)
		var base_y: float = lerpf(480.0, 120.0, t)
		var offset_x: float = randf_range(-120.0, 120.0)
		var offset_y: float = randf_range(-80.0, 80.0)
		var pos := Vector2(base_x + offset_x, base_y + offset_y)
		_try_place_building(positions, pos, min_spacing)
	return positions

func _gen_ring_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	positions.append(Vector2(120, 460))  # Player
	positions.append(Vector2(680, 140))  # Opponent
	var center := Vector2(400, 300)
	# Place buildings in an oval ring
	var ring_count: int = mini(count - 2, 10)
	for i in range(ring_count):
		var angle: float = TAU * float(i) / float(ring_count)
		var rx: float = 250.0 + randf_range(-30.0, 30.0)
		var ry: float = 170.0 + randf_range(-20.0, 20.0)
		var pos := center + Vector2(cos(angle) * rx, sin(angle) * ry)
		_try_place_building(positions, pos, min_spacing)
	# Fill remaining with center-area buildings
	var attempts: int = 0
	while positions.size() < count and attempts < 100:
		attempts += 1
		var pos := center + Vector2(randf_range(-80.0, 80.0), randf_range(-60.0, 60.0))
		_try_place_building(positions, pos, min_spacing)
	return positions

func _gen_clusters_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	positions.append(Vector2(110, 470))  # Player
	positions.append(Vector2(690, 130))  # Opponent
	# Player-side cluster
	var player_center := Vector2(200, 400)
	var opp_center := Vector2(600, 200)
	var mid_center := Vector2(400, 300)
	var per_cluster: int = (count - 2) / 3
	var centers: Array = [player_center, opp_center, mid_center]
	for ci in range(3):
		var c: Vector2 = centers[ci]
		var to_place: int = per_cluster if ci < 2 else (count - positions.size())
		var attempts: int = 0
		while to_place > 0 and attempts < 80:
			attempts += 1
			var pos := c + Vector2(randf_range(-100.0, 100.0), randf_range(-80.0, 80.0))
			if _try_place_building(positions, pos, min_spacing):
				to_place -= 1
	# Fill any remaining
	var attempts: int = 0
	while positions.size() < count and attempts < 100:
		attempts += 1
		var pos := Vector2(randf_range(80.0, 720.0), randf_range(80.0, 520.0))
		_try_place_building(positions, pos, min_spacing)
	return positions

func _gen_scattered_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	positions.append(Vector2(100 + randf_range(0, 40), 460 + randf_range(-20, 20)))  # Player
	positions.append(Vector2(680 + randf_range(-20, 20), 120 + randf_range(-20, 20)))  # Opponent
	var attempts: int = 0
	while positions.size() < count and attempts < 300:
		attempts += 1
		var pos := Vector2(randf_range(80.0, 720.0), randf_range(80.0, 520.0))
		_try_place_building(positions, pos, min_spacing)
	return positions

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
			"units_fractional": 0.0,
			"fractional_timestamp": 0.0,
		})

	# Set home base to rearmost player building in roguelike runs
	if in_roguelike_run:
		var best_y: float = -1.0
		home_base_id = -1
		for b in buildings:
			if b["owner"] == "player" and b["position"].y > best_y:
				best_y = b["position"].y
				home_base_id = b["id"]

func _return_to_menu() -> void:
	game_state = "level_select"
	buildings.clear()
	dispatch_queues.clear()
	moving_units.clear()
	visual_effects.clear()
	context_menu_building_id = -1
	context_menu_options.clear()
	home_base_id = -1

# === Main Loop ===

func _process(delta: float) -> void:
	if game_state == "level_select":
		queue_redraw()
		return
	if game_state == "roguelike_map":
		game_time += delta
		queue_redraw()
		return

	game_time += delta
	if in_roguelike_run:
		run_time_left = maxf(0.0, run_time_left - delta)
	if game_won or game_lost:
		queue_redraw()
		return

	_update_unit_generation(delta)
	_update_upgrades(delta)
	_update_towers(delta)
	_update_dispatch_queues(delta)
	_update_moving_units(delta)
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
	var units_to_remove: Array = []
	for b in buildings:
		if b["type"] != "tower":
			continue
		b["shoot_timer"] += delta
		var interval: float = _get_tower_shoot_interval(b["level"])
		if b["shoot_timer"] < interval:
			continue
		b["shoot_timer"] -= interval
		# Find closest enemy moving unit within range
		var shoot_radius: float = _get_tower_shoot_radius(b["level"])
		var best_idx: int = -1
		var best_dist: float = 99999.0
		for i in range(moving_units.size()):
			var u: Dictionary = moving_units[i]
			if u["owner"] == b["owner"]:
				continue
			if i in units_to_remove:
				continue
			var unit_pos: Vector2 = _get_unit_position(u)
			var dist: float = b["position"].distance_to(unit_pos)
			if dist <= shoot_radius and dist < best_dist:
				best_dist = dist
				best_idx = i
		if best_idx != -1:
			var u: Dictionary = moving_units[best_idx]
			# Visual effect: shot line
			var target_pos: Vector2 = _get_unit_position(u)
			visual_effects.append({
				"type": "tower_shot",
				"start": b["position"],
				"end": target_pos,
				"timer": 0.0,
				"duration": 0.2,
				"color": _get_owner_color(b["owner"]),
			})
			units_to_remove.append(best_idx)
	# Remove destroyed units (reverse order)
	units_to_remove.sort()
	units_to_remove.reverse()
	for idx in units_to_remove:
		moving_units.remove_at(idx)

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
		var interval: float = 1.0 / ARMY_WAVES_PER_SECOND
		while q["wave_timer"] >= interval and q["remaining"] > 0:
			q["wave_timer"] -= interval
			var wave_size: int = mini(MAX_ARMY_WIDTH, q["remaining"])
			# Cap to available units in the building
			wave_size = mini(wave_size, source["units"])
			if wave_size <= 0:
				q["remaining"] = 0
				break
			source["units"] -= wave_size
			q["remaining"] -= wave_size
			for _j in range(wave_size):
				var lateral: float = (float(_j) - float(wave_size - 1) / 2.0) * UNIT_FORMATION_SPACING
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
	var resolved: Array = []
	for i in range(moving_units.size()):
		var u: Dictionary = moving_units[i]
		var dist: float = u["start_pos"].distance_to(u["end_pos"])
		if dist < 1.0:
			dist = 1.0
		u["progress"] += (UNIT_SPEED / dist) * delta
		if u["progress"] >= 1.0:
			_resolve_arrival(u)
			resolved.append(i)
	resolved.reverse()
	for idx in resolved:
		moving_units.remove_at(idx)

func _get_fractional(building: Dictionary) -> float:
	if game_time - building["fractional_timestamp"] >= 10.0:
		building["units_fractional"] = 0.0
		return 0.0
	return building["units_fractional"]

func _resolve_arrival(unit_data: Dictionary) -> void:
	var target: Dictionary = buildings[unit_data["target_id"]]
	if target["owner"] == unit_data["owner"]:
		# Reinforce
		target["units"] += 1
	else:
		# Combat with multipliers — single unit arriving
		var A: float = 1.0
		var D: float = float(target["units"]) + _get_fractional(target)
		var att_mult: float = _get_attacker_multiplier(unit_data["owner"])
		var def_mult: float = _get_defender_multiplier(target)
		var attacker_losses: float = D * def_mult / att_mult
		var defender_losses: float = A * att_mult / def_mult
		var attacker_remaining: float = A - attacker_losses
		var defender_remaining: float = D - defender_losses

		if defender_remaining >= attacker_remaining:
			# Defender holds
			target["units"] = maxi(0, int(floor(defender_remaining)))
			target["units_fractional"] = defender_remaining - float(target["units"])
			target["fractional_timestamp"] = game_time
		else:
			# Attacker captures
			target["units"] = maxi(1, int(floor(attacker_remaining)))
			target["units_fractional"] = attacker_remaining - float(target["units"])
			target["fractional_timestamp"] = game_time
			target["owner"] = unit_data["owner"]
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
				"color": _get_owner_color(unit_data["owner"]),
			})
			# Home base captured — immediate battle loss
			if in_roguelike_run and target["id"] == home_base_id:
				game_lost = true

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

func _get_unit_position(u: Dictionary) -> Vector2:
	var eased_t: float = _ease_out_cubic(u["progress"])
	var center: Vector2 = u["start_pos"].lerp(u["end_pos"], eased_t)
	var dir: Vector2 = (u["end_pos"] - u["start_pos"]).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	return center + perp * u.get("lateral_offset", 0.0)

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
		# Also check in-flight units and dispatch queues
		for u in moving_units:
			if u["owner"] == "player":
				has_player = true
			elif u["owner"] == "opponent":
				has_opponent = true
		for q in dispatch_queues:
			if q["owner"] == "player":
				has_player = true
			elif q["owner"] == "opponent":
				has_opponent = true
		if not has_opponent:
			game_won = true
		elif in_roguelike_run:
			# In roguelike: lose if time expired or home base is captured
			if run_time_left <= 0.0:
				game_lost = true
			elif home_base_id >= 0 and buildings[home_base_id]["owner"] != "player":
				game_lost = true
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
				if btn["mode"] == "roguelike":
					_start_roguelike_run()
				else:
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
	if game_state == "level_select":
		_draw_level_select()
		return
	if game_state == "roguelike_map":
		_draw_roguelike_map()
		return
	_draw_background()
	_draw_dispatch_queue_lines()
	_draw_drag_line()
	_draw_buildings()
	_draw_moving_units()
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

	# Roguelike header (centered below both columns)
	var header_rl := "ROGUELIKE"
	var hr_size := font.get_string_size(header_rl, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	var rl_header_y: float = 180.0 + 4.0 * (48.0 + 12.0) + 16.0
	draw_string(font, Vector2(400 - hr_size.x / 2, rl_header_y), header_rl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.4, 0.9, 0.5))

	# Buttons
	for btn in level_buttons:
		var r: Rect2 = btn["rect"]
		var is_roguelike: bool = btn["mode"] == "roguelike"
		var is_ai: bool = btn["mode"] == "ai"
		var bg_color := Color(0.15, 0.15, 0.22)
		var border_color: Color
		var text_color: Color
		if is_roguelike:
			border_color = Color(0.3, 0.7, 0.4)
			text_color = Color(0.6, 1.0, 0.7)
		elif is_ai:
			border_color = Color(0.7, 0.45, 0.2)
			text_color = Color(1.0, 0.75, 0.4)
		else:
			border_color = Color(0.3, 0.4, 0.7)
			text_color = Color(0.8, 0.85, 1.0)

		draw_rect(r, bg_color)
		draw_rect(r, border_color, false, 2.0)

		var label: String = btn["label"]
		var font_size: int = 20 if is_roguelike else 18
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(r.position.x + (r.size.x - label_size.x) / 2,
			r.position.y + (r.size.y + label_size.y) / 2 - 2), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

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

		# Home base visual distinction: pulsing gold/white shield ring
		if in_roguelike_run and b["id"] == home_base_id and b["owner"] == "player":
			radius += 4.0
			var shield_alpha: float = 0.5 + 0.3 * sin(game_time * 3.0)
			draw_arc(pos, radius + 6, 0, TAU, 48, Color(1.0, 0.9, 0.4, shield_alpha), 3.0)
			draw_arc(pos, radius + 9, 0, TAU, 48, Color(1.0, 1.0, 1.0, shield_alpha * 0.4), 1.5)

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

func _draw_dispatch_queue_lines() -> void:
	for q in dispatch_queues:
		var start: Vector2 = q["start_pos"]
		var end_p: Vector2 = q["end_pos"]
		var line_color: Color
		if q["owner"] == "player":
			line_color = Color(0.3, 0.5, 1.0, 0.1)
		else:
			line_color = Color(1.0, 0.5, 0.2, 0.1)
		draw_line(start, end_p, line_color, 1.0)

func _draw_moving_units() -> void:
	for u in moving_units:
		var center: Vector2 = _get_unit_position(u)
		var dir: Vector2 = (u["end_pos"] - u["start_pos"]).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var tri_color: Color
		if u["owner"] == "player":
			tri_color = Color(0.3, 0.5, 1.0, 0.9)
		else:
			tri_color = Color(1.0, 0.55, 0.15, 0.9)
		var sz: float = UNIT_TRIANGLE_SIZE
		var tip: Vector2 = center + dir * sz * 1.5
		var left: Vector2 = center - dir * sz * 0.5 + perp * sz * 0.6
		var right: Vector2 = center - dir * sz * 0.5 - perp * sz * 0.6
		var pts: PackedVector2Array = PackedVector2Array([tip, left, right])
		draw_colored_polygon(pts, tri_color)

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

	# Run time bar during roguelike battles
	if in_roguelike_run:
		var rbar_x: float = 620.0
		var rbar_y: float = 8.0
		var rbar_w: float = 150.0
		var rbar_h: float = 10.0
		var rt_col := Color(0.3, 0.8, 0.4) if run_time_left >= 60.0 else Color(0.9, 0.4, 0.1)
		draw_rect(Rect2(rbar_x, rbar_y, rbar_w, rbar_h), Color(0.1, 0.12, 0.1))
		var rfill: float = rbar_w * clampf(run_time_left / 600.0, 0.0, 1.0)
		draw_rect(Rect2(rbar_x, rbar_y, rfill, rbar_h), rt_col)
		var time_str := _format_run_time()
		var rtxt_col := Color(0.85, 1.0, 0.85)
		if run_time_left < 30.0:
			rtxt_col = Color(1.0, 0.3, 0.3) if int(game_time * 2.0) % 2 == 0 else Color(0.7, 0.1, 0.1)
		elif run_time_left < 60.0:
			rtxt_col = Color(1.0, 0.7, 0.3)
		draw_string(font, Vector2(rbar_x + 4, rbar_y + 21), "Time: " + time_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, rtxt_col)
		var rgold_text := "Gold: %d" % run_gold
		draw_string(font, Vector2(rbar_x + 4, rbar_y + 33), rgold_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.2))

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
		var lost_text: String
		if in_roguelike_run and run_time_left <= 0.0:
			lost_text = "TIME'S UP! Run time expired."
		else:
			lost_text = "DEFEATED! All your buildings lost."
		_draw_end_overlay(lost_text, Color(1.0, 0.3, 0.3))

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
