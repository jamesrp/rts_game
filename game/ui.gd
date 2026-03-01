class_name GameUI
extends RefCounted

var main

func _init(main_node) -> void:
	main = main_node

func draw() -> void:
	if main.game_state == "level_select":
		draw_level_select()
		return
	if main.game_state == "hero_select":
		draw_hero_select()
		return
	if main.game_state == "roguelike_map":
		draw_roguelike_map()
		return
	draw_background()
	draw_dispatch_queue_lines()
	draw_drag_line()
	draw_buildings()
	draw_hero_effects()
	draw_moving_units()
	draw_visual_effects()
	draw_context_menu()
	draw_hud()

func draw_background() -> void:
	main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0.08, 0.08, 0.12))
	var grid_color := Color(0.14, 0.14, 0.2)
	for x in range(0, int(GameData.SCREEN_W) + 1, 40):
		main.draw_line(Vector2(x, 0), Vector2(x, GameData.SCREEN_H), grid_color)
	for y in range(0, int(GameData.SCREEN_H) + 1, 40):
		main.draw_line(Vector2(0, y), Vector2(GameData.SCREEN_W, y), grid_color)

func draw_buildings() -> void:
	for b in main.buildings:
		var pos: Vector2 = b["position"]
		var radius: float = GameData.BASE_BUILDING_RADIUS + b["level"] * GameData.BUILDING_RADIUS_PER_LEVEL
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

		draw_building_shape(b, pos, radius, fill_color, outline_color)

		if b["type"] == "normal" and not b["upgrading"] and b["owner"] == "player" and b["level"] < GameData.MAX_BUILDING_LEVEL and b["units"] >= GameData.get_upgrade_cost(b["level"]):
			var pulse_alpha: float = 0.4 + 0.4 * sin(main.game_time * 4.0)
			main.draw_arc(pos, radius + 6, 0, TAU, 48, Color(1.0, 0.85, 0.2, pulse_alpha), 2.0)
		elif is_tower and not b["upgrading"] and b["owner"] == "player" and b["level"] < GameData.MAX_BUILDING_LEVEL and b["units"] >= GameData.get_tower_upgrade_cost():
			var pulse_alpha: float = 0.4 + 0.4 * sin(main.game_time * 4.0)
			main.draw_arc(pos, radius + 6, 0, TAU, 48, Color(1.0, 0.85, 0.2, pulse_alpha), 2.0)

		if b["id"] == main.selected_building_id:
			if is_forge:
				var sel_r: float = radius + 4
				var sel_pts: PackedVector2Array = PackedVector2Array([
					pos + Vector2(0, -sel_r), pos + Vector2(sel_r, 0),
					pos + Vector2(0, sel_r), pos + Vector2(-sel_r, 0),
				])
				for di in range(4):
					main.draw_line(sel_pts[di], sel_pts[(di + 1) % 4], Color(1, 1, 0.3, 0.9), 3.0)
			elif is_tower:
				var sel_r: float = radius + 4
				var sel_pts: PackedVector2Array = PackedVector2Array([
					pos + Vector2(0, -sel_r),
					pos + Vector2(sel_r, sel_r * 0.7),
					pos + Vector2(-sel_r, sel_r * 0.7),
				])
				for di in range(3):
					main.draw_line(sel_pts[di], sel_pts[(di + 1) % 3], Color(1, 1, 0.3, 0.9), 3.0)
			else:
				main.draw_arc(pos, radius + 4, 0, TAU, 48, Color(1, 1, 0.3, 0.9), 3.0)

		if not is_forge:
			for lv in range(b["level"]):
				var angle: float = -PI / 2 + lv * (TAU / GameData.MAX_BUILDING_LEVEL)
				var dot_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * (radius + 10)
				main.draw_circle(dot_pos, 3.0, Color.WHITE)
			if b["upgrading"]:
				var next_lv: int = b["level"]
				var angle: float = -PI / 2 + next_lv * (TAU / GameData.MAX_BUILDING_LEVEL)
				var dot_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * (radius + 10)
				var pie_radius: float = 5.0
				main.draw_circle(dot_pos, pie_radius, Color(0.25, 0.25, 0.3))
				var fill_angle: float = b["upgrade_progress"] * TAU
				var start_angle: float = -PI / 2.0
				if fill_angle > 0.01:
					var segments: int = maxi(3, int(fill_angle / TAU * 32))
					var pie_pts: PackedVector2Array = PackedVector2Array()
					pie_pts.append(dot_pos)
					for seg in range(segments + 1):
						var seg_angle: float = start_angle + (float(seg) / segments) * fill_angle
						pie_pts.append(dot_pos + Vector2(cos(seg_angle), sin(seg_angle)) * pie_radius)
					main.draw_colored_polygon(pie_pts, Color(1.0, 0.85, 0.2))
				main.draw_arc(dot_pos, pie_radius, 0, TAU, 24, Color(0.8, 0.8, 0.8, 0.6), 1.0)

		var font := ThemeDB.fallback_font
		var text: String = str(b["units"])
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		main.draw_string(font, pos - Vector2(text_size.x / 2, -5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

		if main.in_roguelike_run and main.run_hero != "":
			var effect_icons: Array = []
			if main._has_hero_effect_on("fortify", b["id"]):
				effect_icons.append({"label": "F", "color": Color(0.3, 0.8, 1.0)})
				var pulse: float = 0.5 + 0.3 * sin(main.game_time * 3.0)
				main.draw_arc(pos, radius + 3, 0, TAU, 48, Color(0.3, 0.8, 1.0, pulse), 2.5)
			if main._has_hero_effect_on("entrench", b["id"]):
				effect_icons.append({"label": "E", "color": Color(0.2, 0.7, 0.9)})
			if main._has_hero_effect_on("citadel", b["id"]):
				effect_icons.append({"label": "C", "color": Color(0.2, 0.7, 0.9)})
				var pulse2: float = 0.4 + 0.3 * sin(main.game_time * 2.0)
				main.draw_arc(pos, radius + 5, 0, TAU, 48, Color(0.2, 0.7, 0.9, pulse2), 3.0)
			if main._has_hero_effect_on("sabotage", b["id"]):
				effect_icons.append({"label": "S", "color": Color(0.6, 0.2, 0.8)})
			if main._has_hero_effect_on("overclock", b["id"]):
				effect_icons.append({"label": "O", "color": Color(0.2, 0.8, 0.4)})
				var pulse3: float = 0.3 + 0.3 * sin(main.game_time * 5.0)
				main.draw_arc(pos, radius + 3, 0, TAU, 48, Color(0.2, 0.8, 0.4, pulse3), 2.0)
			for ei in range(effect_icons.size()):
				var icon_pos: Vector2 = pos + Vector2(-6 + ei * 12, -radius - 14)
				main.draw_string(font, icon_pos, effect_icons[ei]["label"],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, effect_icons[ei]["color"])


func draw_building_shape(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	if b["type"] == "tower":
		draw_building_triangle(b, pos, radius, fill_color, outline_color)
	elif b["type"] == "forge":
		draw_building_diamond(b, pos, radius, fill_color, outline_color)
	else:
		draw_building_circle(b, pos, radius, fill_color, outline_color)

func draw_building_triangle(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	var tri_pts: PackedVector2Array = PackedVector2Array([
		pos + Vector2(0, -radius),
		pos + Vector2(radius, radius * 0.7),
		pos + Vector2(-radius, radius * 0.7),
	])
	main.draw_colored_polygon(tri_pts, Color(0.1, 0.1, 0.15))
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
			main.draw_colored_polygon(fill_pts, fill_color)
	for di in range(3):
		main.draw_line(tri_pts[di], tri_pts[(di + 1) % 3], outline_color, 2.0)
	main.draw_circle(pos, 3.0, outline_color)
	main.draw_line(pos + Vector2(-5, 0), pos + Vector2(5, 0), outline_color, 1.5)
	main.draw_line(pos + Vector2(0, -5), pos + Vector2(0, 5), outline_color, 1.5)
	var shoot_r: float = GameData.get_tower_shoot_radius(b["level"])
	var range_col: Color = Color(outline_color.r, outline_color.g, outline_color.b, 0.75)
	var dot_count: int = 32
	for di in range(dot_count):
		var a1: float = float(di) / dot_count * TAU
		var a2: float = (float(di) + 0.5) / dot_count * TAU
		main.draw_arc(pos, shoot_r, a1, a2, 4, range_col, 2.5)

func draw_building_diamond(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	var diamond_pts: PackedVector2Array = PackedVector2Array([
		pos + Vector2(0, -radius),
		pos + Vector2(radius, 0),
		pos + Vector2(0, radius),
		pos + Vector2(-radius, 0),
	])
	main.draw_colored_polygon(diamond_pts, Color(0.1, 0.1, 0.15))
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
			main.draw_colored_polygon(fill_pts, fill_color)
	for di in range(4):
		main.draw_line(diamond_pts[di], diamond_pts[(di + 1) % 4], outline_color, 2.0)
	main.draw_line(pos + Vector2(-6, 2), pos + Vector2(6, 2), outline_color, 2.0)
	main.draw_line(pos + Vector2(-4, -3), pos + Vector2(-4, 2), outline_color, 1.5)
	main.draw_line(pos + Vector2(4, -3), pos + Vector2(4, 2), outline_color, 1.5)

func draw_building_circle(b: Dictionary, pos: Vector2, radius: float, fill_color: Color, outline_color: Color) -> void:
	main.draw_circle(pos, radius, Color(0.1, 0.1, 0.15))
	var max_cap: int = b["max_capacity"]
	if max_cap > 0:
		var fill_ratio: float = clampf(float(b["units"]) / max_cap, 0.0, 1.0)
		if fill_ratio > 0.0:
			var fill_angle: float = fill_ratio * TAU
			var start_angle: float = PI / 2.0
			main.draw_arc(pos, radius * 0.6, start_angle - fill_angle, start_angle, 48, fill_color, radius * 0.8)
	main.draw_arc(pos, radius, 0, TAU, 48, outline_color, 2.0)

func draw_drag_line() -> void:
	if not main.is_dragging or main.drag_source_id == -1:
		return
	var start: Vector2 = main.buildings[main.drag_source_id]["position"]
	var hover_id: int = main._get_building_at(main.drag_current_pos)
	var end: Vector2 = main.drag_current_pos
	var line_color := Color(0.4, 0.7, 1.0, 0.5)
	if hover_id != -1 and hover_id != main.drag_source_id:
		end = main.buildings[hover_id]["position"]
		line_color = Color(0.5, 0.9, 0.5, 0.7)
	main.draw_line(start, end, line_color, 2.0)

func draw_dispatch_queue_lines() -> void:
	for q in main.dispatch_queues:
		var start: Vector2 = q["start_pos"]
		var end_p: Vector2 = q["end_pos"]
		var line_color: Color
		if q["owner"] == "player":
			line_color = Color(0.3, 0.5, 1.0, 0.1)
		else:
			line_color = Color(1.0, 0.5, 0.2, 0.1)
		main.draw_line(start, end_p, line_color, 1.0)

func draw_moving_units() -> void:
	for u in main.moving_units:
		var center: Vector2 = GameData.get_unit_position(u)
		var dir: Vector2 = (u["end_pos"] - u["start_pos"]).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var tri_color: Color
		if u["owner"] == "player":
			tri_color = Color(0.3, 0.5, 1.0, 0.9)
		else:
			tri_color = Color(1.0, 0.55, 0.15, 0.9)
		var sz: float = GameData.UNIT_TRIANGLE_SIZE
		var tip: Vector2 = center + dir * sz * 1.5
		var left: Vector2 = center - dir * sz * 0.5 + perp * sz * 0.6
		var right: Vector2 = center - dir * sz * 0.5 - perp * sz * 0.6
		var pts: PackedVector2Array = PackedVector2Array([tip, left, right])
		main.draw_colored_polygon(pts, tri_color)

func draw_context_menu() -> void:
	if main.context_menu_building_id == -1 or main.context_menu_options.is_empty():
		return
	var font := ThemeDB.fallback_font
	for opt in main.context_menu_options:
		var r: Rect2 = opt["rect"]
		if opt["enabled"]:
			main.draw_rect(r, Color(0.15, 0.18, 0.28, 0.95))
		else:
			main.draw_rect(r, Color(0.12, 0.12, 0.16, 0.9))
		main.draw_rect(r, Color(0.35, 0.45, 0.7, 0.8), false, 1.0)
		var text_color: Color
		if opt["enabled"]:
			text_color = Color(0.9, 0.95, 1.0)
		else:
			text_color = Color(0.4, 0.4, 0.45)
		var label: String = opt["label"]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var tx: float = r.position.x + 8.0
		var ty: float = r.position.y + (r.size.y + text_size.y) / 2.0 - 2.0
		main.draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)

func draw_visual_effects() -> void:
	for fx in main.visual_effects:
		if fx["type"] == "capture_pop":
			var progress: float = fx["timer"] / fx["duration"]
			var ring_radius: float = 20.0 + 40.0 * progress
			var alpha: float = 1.0 - progress
			var col: Color = fx["color"]
			col.a = alpha * 0.8
			main.draw_arc(fx["position"], ring_radius, 0, TAU, 48, col, 3.0 * (1.0 - progress * 0.5))
		elif fx["type"] == "tower_shot":
			var progress: float = fx["timer"] / fx["duration"]
			var alpha: float = 1.0 - progress
			var col: Color = fx["color"]
			col.a = alpha * 0.9
			main.draw_line(fx["start"], fx["end"], col, 2.0 * (1.0 - progress * 0.5))
		elif fx["type"] == "power_flash":
			var progress: float = fx["timer"] / fx["duration"]
			var alpha: float = (1.0 - progress) * 0.3
			var col: Color = fx["color"]
			col.a = alpha
			main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, 4), col)

func draw_hero_effects() -> void:
	if not main.in_roguelike_run or main.run_hero == "":
		return
	var font := ThemeDB.fallback_font
	for fx in main.hero_active_effects:
		if fx["type"] == "minefield" and not fx.get("triggered", false):
			var mid: Vector2 = fx["mid_pos"]
			var pulse: float = 0.4 + 0.3 * sin(main.game_time * 4.0)
			main.draw_circle(mid, 6.0, Color(1.0, 0.3, 0.1, pulse))
			main.draw_arc(mid, 12.0, 0, TAU, 24, Color(1.0, 0.4, 0.2, pulse * 0.5), 1.5)
			main.draw_string(font, mid + Vector2(-4, -10), "M",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.5, 0.2, pulse))
		elif fx["type"] == "supply_line":
			var id_a: int = fx["node_a"]
			var id_b: int = fx["node_b"]
			if id_a >= 0 and id_a < main.buildings.size() and id_b >= 0 and id_b < main.buildings.size():
				var pa: Vector2 = main.buildings[id_a]["position"]
				var pb: Vector2 = main.buildings[id_b]["position"]
				var pulse2: float = 0.3 + 0.3 * sin(main.game_time * 3.0)
				main.draw_line(pa, pb, Color(0.2, 0.8, 0.4, pulse2), 2.0)
	var gfx_y: float = 72.0
	var hero_color: Color = GameData.HERO_DATA.get(main.run_hero, {}).get("color", Color.WHITE)
	for fx in main.hero_active_effects:
		var label: String = ""
		match fx["type"]:
			"forced_march": label = "Forced March"
			"blitz": label = "BLITZ"
			"blackout": label = "Blackout"
			"emp": label = "EMP"
			"nexus": label = "Nexus"
		if label != "":
			var remaining: float = fx["duration"] - fx["timer"]
			var full_str := "%s %.1fs" % [label, remaining]
			var str_size := font.get_string_size(full_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			main.draw_string(font, Vector2(GameData.SCREEN_W / 2 - str_size.x / 2, gfx_y), full_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hero_color)
			gfx_y += 14.0

# === Level Select Drawing ===

func draw_level_select() -> void:
	draw_background()
	var font := ThemeDB.fallback_font

	var title := "SELECT LEVEL"
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
	main.draw_string(font, Vector2(400 - title_size.x / 2, 80), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.9, 0.9, 0.95))

	var cx: float = 400.0
	var btn_w: float = 220.0
	var left_x: float = cx - btn_w - 30.0
	var right_x: float = cx + 30.0

	var header_neutral := "CONQUEST"
	var hn_size := font.get_string_size(header_neutral, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	main.draw_string(font, Vector2(left_x + (btn_w - hn_size.x) / 2, 145), header_neutral,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.6, 0.7))

	var sub_neutral := "Capture all neutral buildings"
	var sn_size := font.get_string_size(sub_neutral, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	main.draw_string(font, Vector2(left_x + (btn_w - sn_size.x) / 2, 165), sub_neutral,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.45, 0.55))

	var header_ai := "VS OPPONENT"
	var ha_size := font.get_string_size(header_ai, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	main.draw_string(font, Vector2(right_x + (btn_w - ha_size.x) / 2, 145), header_ai,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.65, 0.3))

	var sub_ai := "Defeat the AI opponent"
	var sa_size := font.get_string_size(sub_ai, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	main.draw_string(font, Vector2(right_x + (btn_w - sa_size.x) / 2, 165), sub_ai,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.45, 0.3))

	var header_rl := "ROGUELIKE"
	var hr_size := font.get_string_size(header_rl, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	var rl_header_y: float = 180.0 + 4.0 * (48.0 + 12.0) + 16.0
	main.draw_string(font, Vector2(400 - hr_size.x / 2, rl_header_y), header_rl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.4, 0.9, 0.5))

	for btn in main.level_buttons:
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

		main.draw_rect(r, bg_color)
		main.draw_rect(r, border_color, false, 2.0)

		var label: String = btn["label"]
		var font_size: int = 20 if is_roguelike else 18
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		main.draw_string(font, Vector2(r.position.x + (r.size.x - label_size.x) / 2,
			r.position.y + (r.size.y + label_size.y) / 2 - 2), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

# === Hero Select Screen ===

func draw_hero_select() -> void:
	draw_background()
	var font := ThemeDB.fallback_font

	var title := "CHOOSE YOUR HERO"
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
	main.draw_string(font, Vector2(400 - title_size.x / 2, 50), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.9, 0.9, 0.95))

	var heroes: Array = ["commander", "warden", "saboteur", "architect"]
	var card_w: float = 170.0
	var card_h: float = 420.0
	var gap: float = 12.0
	var total_w: float = card_w * 4 + gap * 3
	var start_x: float = (GameData.SCREEN_W - total_w) / 2.0
	var card_y: float = 70.0

	for i in range(4):
		var hero_key: String = heroes[i]
		var data: Dictionary = GameData.HERO_DATA[hero_key]
		var cx: float = start_x + i * (card_w + gap)
		var card_rect := Rect2(cx, card_y, card_w, card_h)
		var hovered: bool = card_rect.has_point(main.mouse_pos)

		var bg_col := Color(0.12, 0.12, 0.18) if not hovered else Color(0.18, 0.18, 0.26)
		main.draw_rect(card_rect, bg_col)
		main.draw_rect(card_rect, data["color"] if hovered else data["color"].darkened(0.4), false, 2.0)

		var name_str: String = data["name"]
		var name_size := font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		main.draw_string(font, Vector2(cx + (card_w - name_size.x) / 2, card_y + 28), name_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, data["color"])

		main.draw_rect(Rect2(cx + 10, card_y + 38, card_w - 20, 3), data["color"])

		var desc_str: String = data["desc"]
		var desc_y: float = card_y + 58
		var words: PackedStringArray = desc_str.split(" ")
		var line: String = ""
		for w in words:
			var test: String = line + ("" if line.is_empty() else " ") + w
			var tw: float = font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			if tw > card_w - 16 and not line.is_empty():
				main.draw_string(font, Vector2(cx + 8, desc_y), line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.7))
				desc_y += 14
				line = w
			else:
				line = test
		if not line.is_empty():
			main.draw_string(font, Vector2(cx + 8, desc_y), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.7))
			desc_y += 14

		var py: float = desc_y + 10
		main.draw_string(font, Vector2(cx + 8, py), "Powers:",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.85))
		py += 18
		for p_idx in range(4):
			var power: Dictionary = data["powers"][p_idx]
			var hotkey_str := "[%d] " % (p_idx + 1)
			var cost_str := " (%d)" % power["cost"]
			main.draw_string(font, Vector2(cx + 8, py), hotkey_str + power["name"] + cost_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.9))
			py += 16
			var pd_words: PackedStringArray = power["desc"].split(" ")
			var pd_line: String = ""
			for w in pd_words:
				var test2: String = pd_line + ("" if pd_line.is_empty() else " ") + w
				var tw2: float = font.get_string_size(test2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				if tw2 > card_w - 24 and not pd_line.is_empty():
					main.draw_string(font, Vector2(cx + 16, py), pd_line,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.6))
					py += 12
					pd_line = w
				else:
					pd_line = test2
			if not pd_line.is_empty():
				main.draw_string(font, Vector2(cx + 16, py), pd_line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.6))
				py += 16

		if hovered:
			var hint := "Click to select"
			var hint_size := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
			main.draw_string(font, Vector2(cx + (card_w - hint_size.x) / 2, card_y + card_h - 10), hint,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, data["color"])

	var back_str := "Press ESC to go back"
	var back_size := font.get_string_size(back_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
	main.draw_string(font, Vector2(400 - back_size.x / 2, 560), back_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.55))

# === Roguelike Map Drawing ===

func draw_roguelike_map() -> void:
	draw_background()
	var font := ThemeDB.fallback_font

	var title := "ACT %d" % main.run_act
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
	main.draw_string(font, Vector2(400 - title_size.x / 2, 40), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.9, 0.85, 0.6))

	var gold_text := "Gold: %d" % main.run_gold
	main.draw_string(font, Vector2(30, 40), gold_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.2))
	draw_run_upgrade_icons(Vector2(30, 48), 14.0)

	var time_str: String = main._format_run_time()
	var time_col := Color(0.9, 0.9, 0.9)
	if main.run_time_left < 30.0:
		time_col = Color(1.0, 0.3, 0.3) if int(main.game_time * 2.0) % 2 == 0 else Color(0.8, 0.15, 0.15)
	elif main.run_time_left < 60.0:
		time_col = Color(1.0, 0.65, 0.2)
	var time_label: String = "Time: " + time_str
	var tl_size := font.get_string_size(time_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	main.draw_string(font, Vector2(780 - tl_size.x, 40), time_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, time_col)
	var tbar_x: float = 780.0 - tl_size.x
	var tbar_y: float = 47.0
	var tbar_w: float = tl_size.x
	var tbar_h: float = 6.0
	main.draw_rect(Rect2(tbar_x, tbar_y, tbar_w, tbar_h), Color(0.12, 0.12, 0.15))
	var tbar_fill: float = tbar_w * clampf(main.run_time_left / 600.0, 0.0, 1.0)
	var tbar_col := Color(0.3, 0.8, 0.4) if main.run_time_left >= 60.0 else Color(0.9, 0.4, 0.1)
	main.draw_rect(Rect2(tbar_x, tbar_y, tbar_fill, tbar_h), tbar_col)

	for row_idx in range(main.run_map.size() - 1):
		for col_idx in range(main.run_map[row_idx].size()):
			var node: Dictionary = main.run_map[row_idx][col_idx]
			for next_col in node["next_edges"]:
				var next_node: Dictionary = main.run_map[row_idx + 1][next_col]
				var edge_color := Color(0.3, 0.3, 0.4)
				if node["completed"]:
					if main.run_map[row_idx + 1][next_col]["completed"]:
						edge_color = Color(0.3, 0.5, 0.3, 0.7)
					else:
						edge_color = Color(0.25, 0.25, 0.3)
				elif row_idx == main.run_current_row and main._is_node_available(row_idx, col_idx):
					edge_color = Color(0.4, 0.5, 0.7, 0.5)
				main.draw_line(node["position"], next_node["position"], edge_color, 2.0)

	for row_idx in range(main.run_map.size()):
		for col_idx in range(main.run_map[row_idx].size()):
			var node: Dictionary = main.run_map[row_idx][col_idx]
			var pos: Vector2 = node["position"]
			var available: bool = main._is_node_available(row_idx, col_idx)

			if node["completed"]:
				main.draw_circle(pos, 14.0, Color(0.2, 0.2, 0.25))
				main.draw_arc(pos, 14.0, 0, TAU, 32, Color(0.3, 0.3, 0.35), 2.0)
				main.draw_line(pos + Vector2(-5, 0), pos + Vector2(-1, 4), Color(0.4, 0.6, 0.4), 2.0)
				main.draw_line(pos + Vector2(-1, 4), pos + Vector2(5, -4), Color(0.4, 0.6, 0.4), 2.0)
			elif node["type"] == "boss":
				var boss_col := Color(0.9, 0.3, 0.2) if available else Color(0.5, 0.2, 0.15)
				main.draw_circle(pos, 18.0, Color(0.15, 0.05, 0.05))
				main.draw_arc(pos, 18.0, 0, TAU, 32, boss_col, 2.5)
				main.draw_circle(pos + Vector2(-4, -3), 2.0, boss_col)
				main.draw_circle(pos + Vector2(4, -3), 2.0, boss_col)
				main.draw_line(pos + Vector2(-3, 4), pos + Vector2(3, 4), boss_col, 1.5)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(main.game_time * 3.0)
					main.draw_arc(pos, 22.0, 0, TAU, 32, Color(0.9, 0.3, 0.2, pulse), 2.0)
			elif node["type"] == "elite":
				var elite_col := Color(1.0, 0.85, 0.2) if available else Color(0.6, 0.5, 0.15)
				main.draw_circle(pos, 16.0, Color(0.15, 0.12, 0.02))
				main.draw_arc(pos, 16.0, 0, TAU, 32, elite_col, 2.5)
				for si in range(5):
					var angle_a: float = -PI / 2.0 + si * TAU / 5.0
					var angle_b: float = -PI / 2.0 + (si + 2) * TAU / 5.0
					var pa: Vector2 = pos + Vector2(cos(angle_a), sin(angle_a)) * 8.0
					var pb: Vector2 = pos + Vector2(cos(angle_b), sin(angle_b)) * 8.0
					main.draw_line(pa, pb, elite_col, 1.5)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(main.game_time * 3.0)
					main.draw_arc(pos, 20.0, 0, TAU, 32, Color(1.0, 0.85, 0.2, pulse), 2.0)
			elif node["type"] == "campfire":
				var cf_col := Color(1.0, 0.55, 0.15) if available else Color(0.5, 0.28, 0.08)
				main.draw_circle(pos, 15.0, Color(0.12, 0.06, 0.02))
				main.draw_arc(pos, 15.0, 0, TAU, 32, cf_col, 2.5)
				# Draw flame icon
				var flame_sway: float = sin(main.game_time * 4.0) * 1.5 if available else 0.0
				main.draw_line(pos + Vector2(-4, 5), pos + Vector2(-1 + flame_sway, -6), cf_col, 2.0)
				main.draw_line(pos + Vector2(4, 5), pos + Vector2(1 + flame_sway, -6), cf_col, 2.0)
				main.draw_line(pos + Vector2(0, 5), pos + Vector2(0 + flame_sway, -8), Color(1.0, 0.8, 0.2) if available else cf_col, 2.5)
				main.draw_line(pos + Vector2(-6, 6), pos + Vector2(6, 4), cf_col, 2.0)
				main.draw_line(pos + Vector2(-5, 4), pos + Vector2(5, 6), cf_col, 2.0)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(main.game_time * 3.0)
					main.draw_arc(pos, 19.0, 0, TAU, 32, Color(1.0, 0.55, 0.15, pulse), 2.0)
			elif node["type"] == "merchant":
				var m_col := Color(0.9, 0.75, 0.15) if available else Color(0.45, 0.38, 0.08)
				main.draw_circle(pos, 15.0, Color(0.12, 0.1, 0.02))
				main.draw_arc(pos, 15.0, 0, TAU, 32, m_col, 2.5)
				main.draw_circle(pos, 7.0, m_col)
				main.draw_circle(pos, 4.5, Color(0.12, 0.1, 0.02))
				main.draw_arc(pos, 4.5, 0, TAU, 24, m_col, 1.0)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(main.game_time * 3.0)
					main.draw_arc(pos, 19.0, 0, TAU, 32, Color(1.0, 0.85, 0.2, pulse), 2.0)
			elif node["type"] == "event":
				var ev_col := Color(0.5, 0.8, 1.0) if available else Color(0.25, 0.4, 0.5)
				main.draw_circle(pos, 15.0, Color(0.05, 0.1, 0.15))
				main.draw_arc(pos, 15.0, 0, TAU, 32, ev_col, 2.5)
				# Draw "?" symbol
				var q_size: int = 16
				var q_str := "?"
				var q_sz := font.get_string_size(q_str, HORIZONTAL_ALIGNMENT_CENTER, -1, q_size)
				main.draw_string(font, pos + Vector2(-q_sz.x / 2, q_size / 2.8), q_str,
					HORIZONTAL_ALIGNMENT_LEFT, -1, q_size, ev_col)
				if available:
					var pulse: float = 0.4 + 0.4 * sin(main.game_time * 3.0)
					main.draw_arc(pos, 19.0, 0, TAU, 32, Color(0.5, 0.8, 1.0, pulse), 2.0)
			elif available:
				var pulse: float = 0.6 + 0.3 * sin(main.game_time * 3.0)
				main.draw_circle(pos, 14.0, Color(0.15, 0.2, 0.35))
				main.draw_arc(pos, 14.0, 0, TAU, 32, Color(0.4, 0.6, 1.0, pulse), 2.5)
				main.draw_line(pos + Vector2(-5, -5), pos + Vector2(5, 5), Color(0.7, 0.8, 1.0), 2.0)
				main.draw_line(pos + Vector2(5, -5), pos + Vector2(-5, 5), Color(0.7, 0.8, 1.0), 2.0)
			else:
				main.draw_circle(pos, 12.0, Color(0.12, 0.12, 0.16))
				main.draw_arc(pos, 12.0, 0, TAU, 32, Color(0.25, 0.25, 0.3), 1.5)

	var row_labels: Array = ["I", "II", "III", "IV", "BOSS"]
	for row_idx in range(main.run_map.size()):
		var y: float = main.run_map[row_idx][0]["position"].y + 5
		var lbl: String = row_labels[row_idx] if row_idx < row_labels.size() else str(row_idx + 1)
		main.draw_string(font, Vector2(30, y), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.35, 0.35, 0.4))

	var help := "Click a glowing node to battle  |  ESC to abandon run"
	main.draw_string(font, Vector2(10, 590), help,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.55))

	if main.run_overlay == "merchant":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.72))
		var panel := Rect2(155, 100, 490, 450)
		main.draw_rect(panel, Color(0.09, 0.08, 0.02))
		main.draw_rect(panel, Color(0.7, 0.6, 0.15), false, 2.0)
		var m_title := "MERCHANT"
		var mt_sz := font.get_string_size(m_title, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
		main.draw_string(font, Vector2(400 - mt_sz.x / 2, 133), m_title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.85, 0.2))
		var gd_str := "Gold: %d" % main.run_gold
		var gd_sz := font.get_string_size(gd_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		main.draw_string(font, Vector2(400 - gd_sz.x / 2, 157), gd_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.2))
		main.draw_line(Vector2(165, 170), Vector2(635, 170), Color(0.5, 0.42, 0.1, 0.45), 1.0)
		main.draw_string(font, Vector2(175, 188), "UPGRADES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.6, 0.3))
		var item_keys   := ["speed",               "attack",              "defense"             ]
		var item_names  := ["Speed Boost",          "Attack Bonus",        "Defense Bonus"       ]
		var item_descs  := ["+10% movement speed",  "+10% attack power",   "+10% defense"        ]
		var item_colors := [Color(0.35, 0.75, 1.0), Color(1.0, 0.5, 0.25), Color(0.35, 0.9, 0.45)]
		var item_ys     := [200,                    255,                   310                   ]
		var buy_rects   := [Rect2(370, 199, 160, 32), Rect2(370, 254, 160, 32), Rect2(370, 309, 160, 32)]
		var can_buy: bool = main.run_gold >= 80
		for i in range(3):
			var lvl: int = main.run_upgrades.get(item_keys[i], 0)
			var col: Color = item_colors[i]
			var iy: int = item_ys[i]
			main.draw_rect(Rect2(175, iy, 18, 18), Color(0.1, 0.1, 0.14))
			main.draw_rect(Rect2(175, iy, 18, 18), col, false, 1.0)
			draw_upgrade_icon_symbol(item_keys[i], Vector2(184, iy + 9), 5.5, col)
			var name_str := "%s   Lv.%d" % [item_names[i], lvl]
			main.draw_string(font, Vector2(200, iy + 13), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
			var desc_str: String = item_descs[i]
			if lvl > 0:
				desc_str += "  (now +%d%%)" % (lvl * 10)
			main.draw_string(font, Vector2(200, iy + 27), desc_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.65, 0.72))
			var br: Rect2 = buy_rects[i]
			main.draw_rect(br, Color(0.16, 0.13, 0.04) if can_buy else Color(0.1, 0.1, 0.1))
			main.draw_rect(br, col if can_buy else Color(0.28, 0.28, 0.28), false, 1.5)
			var bl := "Buy  80g"
			var bl_sz := font.get_string_size(bl, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			main.draw_string(font, Vector2(br.position.x + (br.size.x - bl_sz.x) / 2, br.position.y + 22),
				bl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col if can_buy else Color(0.35, 0.35, 0.35))
		main.draw_line(Vector2(165, 350), Vector2(635, 350), Color(0.5, 0.42, 0.1, 0.45), 1.0)
		# Relics section
		main.draw_string(font, Vector2(175, 368), "RELICS",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.6, 0.3))
		for i in range(main.merchant_relics.size()):
			var relic_id: String = main.merchant_relics[i]
			var relic_data: Dictionary = GameRelics.RELICS[relic_id]
			var ry: int = 380 + i * 55
			var rcol: Color = relic_data["color"]
			var is_bought: bool = relic_id in main.merchant_relics_bought or relic_id in main.run_relics
			# Diamond icon
			_draw_relic_diamond(Vector2(184, ry + 9), 7.0, rcol if not is_bought else Color(0.3, 0.3, 0.35))
			main.draw_string(font, Vector2(200, ry + 13), relic_data["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, rcol if not is_bought else Color(0.4, 0.4, 0.45))
			main.draw_string(font, Vector2(200, ry + 27), relic_data["description"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.65, 0.72) if not is_bought else Color(0.35, 0.35, 0.4))
			var relic_buy_rect := Rect2(370, 389 + i * 55, 160, 32)
			if is_bought:
				var sold_sz := font.get_string_size("SOLD", HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
				main.draw_string(font, Vector2(relic_buy_rect.position.x + (relic_buy_rect.size.x - sold_sz.x) / 2, relic_buy_rect.position.y + 22),
					"SOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.4, 0.45))
			else:
				var relic_can_buy: bool = main.run_gold >= relic_data["cost"]
				main.draw_rect(relic_buy_rect, Color(0.16, 0.13, 0.04) if relic_can_buy else Color(0.1, 0.1, 0.1))
				main.draw_rect(relic_buy_rect, rcol if relic_can_buy else Color(0.28, 0.28, 0.28), false, 1.5)
				var rbl := "Buy  %dg" % relic_data["cost"]
				var rbl_sz := font.get_string_size(rbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
				main.draw_string(font, Vector2(relic_buy_rect.position.x + (relic_buy_rect.size.x - rbl_sz.x) / 2, relic_buy_rect.position.y + 22),
					rbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, rcol if relic_can_buy else Color(0.35, 0.35, 0.35))
		var leave_rect := Rect2(305, 506, 190, 34)
		main.draw_rect(leave_rect, Color(0.1, 0.1, 0.16))
		main.draw_rect(leave_rect, Color(0.3, 0.3, 0.45), false, 1.5)
		var ll := "Leave Shop"
		var ll_sz := font.get_string_size(ll, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
		main.draw_string(font, Vector2(400 - ll_sz.x / 2, leave_rect.position.y + 23),
			ll, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.75, 0.85))
	elif main.run_overlay == "campfire":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.72))
		var panel := Rect2(155, 120, 490, 280)
		main.draw_rect(panel, Color(0.1, 0.06, 0.02))
		main.draw_rect(panel, Color(1.0, 0.55, 0.15), false, 2.0)
		var cf_title := "CAMPFIRE"
		var cf_sz := font.get_string_size(cf_title, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
		main.draw_string(font, Vector2(400 - cf_sz.x / 2, 155), cf_title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.7, 0.3))
		var cf_sub := "Choose one:"
		var cs_sz := font.get_string_size(cf_sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		main.draw_string(font, Vector2(400 - cs_sz.x / 2, 178), cf_sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.6, 0.4))
		# Time display
		var cf_time_str: String = main._format_run_time()
		var time_info := "Current time: " + cf_time_str
		var ti_sz := font.get_string_size(time_info, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		main.draw_string(font, Vector2(400 - ti_sz.x / 2, 195), time_info,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.65))
		# Rest button
		var rest_rect := Rect2(220, 250, 160, 60)
		var rest_hovered: bool = rest_rect.has_point(main.mouse_pos)
		main.draw_rect(rest_rect, Color(0.12, 0.15, 0.1) if not rest_hovered else Color(0.18, 0.22, 0.15))
		main.draw_rect(rest_rect, Color(0.4, 0.8, 0.4), false, 1.5 if not rest_hovered else 2.5)
		var rest_label := "REST"
		var rl_sz := font.get_string_size(rest_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		main.draw_string(font, Vector2(300 - rl_sz.x / 2, 275), rest_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.9, 0.5))
		var rest_desc := "Restore 3:00"
		var rd_sz := font.get_string_size(rest_desc, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		main.draw_string(font, Vector2(300 - rd_sz.x / 2, 295), rest_desc,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.7, 0.6))
		# Train button
		var train_rect := Rect2(420, 250, 160, 60)
		var has_upgrades: bool = main.campfire_upgrade_choices.size() > 0
		var train_hovered: bool = train_rect.has_point(main.mouse_pos) and has_upgrades
		main.draw_rect(train_rect, Color(0.12, 0.1, 0.15) if not train_hovered else Color(0.18, 0.15, 0.22))
		var train_border := Color(0.7, 0.5, 1.0) if has_upgrades else Color(0.3, 0.3, 0.35)
		main.draw_rect(train_rect, train_border, false, 1.5 if not train_hovered else 2.5)
		var train_label := "TRAIN"
		var tl_sz2 := font.get_string_size(train_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		var train_text_col := Color(0.7, 0.5, 1.0) if has_upgrades else Color(0.4, 0.4, 0.45)
		main.draw_string(font, Vector2(500 - tl_sz2.x / 2, 275), train_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, train_text_col)
		var train_desc := "Hero power upgrade" if has_upgrades else "No upgrades left"
		var td_sz := font.get_string_size(train_desc, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		main.draw_string(font, Vector2(500 - td_sz.x / 2, 295), train_desc,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.55, 0.7) if has_upgrades else Color(0.4, 0.4, 0.45))
		# Show acquired upgrades
		if main.run_hero_upgrades.size() > 0:
			var ug_label := "Acquired: " + ", ".join(main.run_hero_upgrades)
			main.draw_string(font, Vector2(170, 370), ug_label,
				HORIZONTAL_ALIGNMENT_LEFT, 460, 11, Color(0.55, 0.55, 0.6))
	elif main.run_overlay == "campfire_train":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.72))
		var panel := Rect2(80, 170, 640, 240)
		main.draw_rect(panel, Color(0.08, 0.06, 0.12))
		main.draw_rect(panel, Color(0.7, 0.5, 1.0), false, 2.0)
		var tt := "TRAIN — Choose an Upgrade"
		var tt_sz := font.get_string_size(tt, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
		main.draw_string(font, Vector2(400 - tt_sz.x / 2, 202), tt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.6, 1.0))
		for i in range(main.campfire_upgrade_choices.size()):
			var upgrade: Dictionary = main.campfire_upgrade_choices[i]
			var cx: float = 115.0 + i * 200.0
			var card := Rect2(cx, 220, 170, 160)
			var hovered: bool = card.has_point(main.mouse_pos)
			main.draw_rect(card, Color(0.12, 0.1, 0.16) if not hovered else Color(0.18, 0.15, 0.22))
			main.draw_rect(card, Color(0.7, 0.5, 1.0) if hovered else Color(0.35, 0.35, 0.4), false, 1.5 if not hovered else 2.5)
			# Power name this upgrade applies to
			var hero_data: Dictionary = GameData.HERO_DATA[main.run_hero]
			var power_name: String = hero_data["powers"][upgrade["power_index"]]["name"]
			var pn_sz := font.get_string_size(power_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
			main.draw_string(font, Vector2(cx + 85 - pn_sz.x / 2, 242), power_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hero_data["color"].lerp(Color.WHITE, 0.3))
			# Upgrade name
			var un_sz := font.get_string_size(upgrade["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			main.draw_string(font, Vector2(cx + 85 - un_sz.x / 2, 270), upgrade["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.7, 1.0))
			# Description with word wrap
			main.draw_string(font, Vector2(cx + 10, 290), upgrade["desc"],
				HORIZONTAL_ALIGNMENT_LEFT, 150, 11, Color(0.7, 0.7, 0.75))
	elif main.run_overlay == "event":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.72))
		var panel := Rect2(130, 100, 540, 400)
		main.draw_rect(panel, Color(0.06, 0.09, 0.14))
		main.draw_rect(panel, Color(0.4, 0.7, 0.9), false, 2.0)
		if main.current_event.has("title"):
			var ev_title: String = main.current_event["title"]
			var et_sz := font.get_string_size(ev_title, HORIZONTAL_ALIGNMENT_CENTER, -1, 24)
			main.draw_string(font, Vector2(400 - et_sz.x / 2, 138), ev_title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.5, 0.85, 1.0))
			# "?" decoration
			main.draw_string(font, Vector2(148, 140), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.3, 0.55, 0.7))
			main.draw_string(font, Vector2(630, 140), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.3, 0.55, 0.7))
		if main.current_event.has("description"):
			var desc_lines: PackedStringArray = main.current_event["description"].split("\n")
			for dl in range(desc_lines.size()):
				var dline: String = desc_lines[dl]
				var dl_sz := font.get_string_size(dline, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
				main.draw_string(font, Vector2(400 - dl_sz.x / 2, 170 + dl * 18), dline,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.75))
		main.draw_line(Vector2(150, 220), Vector2(650, 220), Color(0.3, 0.5, 0.6, 0.4), 1.0)
		if main.event_result_text != "":
			# Show result
			var rt_sz := font.get_string_size(main.event_result_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
			main.draw_string(font, Vector2(400 - rt_sz.x / 2, 310), main.event_result_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.5))
			var cont_rect := Rect2(280, 370, 240, 40)
			var cont_hovered: bool = cont_rect.has_point(main.mouse_pos)
			main.draw_rect(cont_rect, Color(0.1, 0.14, 0.2) if not cont_hovered else Color(0.15, 0.2, 0.28))
			main.draw_rect(cont_rect, Color(0.4, 0.7, 0.9), false, 1.5 if not cont_hovered else 2.5)
			var cont_label := "Continue"
			var cl_sz := font.get_string_size(cont_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
			main.draw_string(font, Vector2(400 - cl_sz.x / 2, 396), cont_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.85, 1.0))
		elif main.current_event.has("choices"):
			# Show choice buttons
			var choices: Array = main.current_event["choices"]
			for i in range(choices.size()):
				var choice: Dictionary = choices[i]
				var choice_rect := Rect2(180, 240 + i * 60, 440, 50)
				var hovered: bool = choice_rect.has_point(main.mouse_pos)
				main.draw_rect(choice_rect, Color(0.08, 0.12, 0.18) if not hovered else Color(0.12, 0.18, 0.25))
				main.draw_rect(choice_rect, Color(0.35, 0.6, 0.8) if not hovered else Color(0.5, 0.8, 1.0), false, 1.5)
				main.draw_string(font, Vector2(195, 260 + i * 60), choice["label"],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.9, 1.0))
				main.draw_string(font, Vector2(195, 276 + i * 60), choice["description"],
					HORIZONTAL_ALIGNMENT_LEFT, 420, 11, Color(0.6, 0.6, 0.65))
	elif main.run_overlay == "run_over":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.6))
		var msg := "RUN OVER"
		var msg_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 36)
		main.draw_string(font, Vector2(400 - msg_size.x / 2, 270), msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1.0, 0.3, 0.3))
		var sub := "Act %d  |  Click to return" % main.run_act
		var sub_size := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		main.draw_string(font, Vector2(400 - sub_size.x / 2, 310), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.5, 0.5))
	elif main.run_overlay == "run_won":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.6))
		var msg := "VICTORY!"
		var msg_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 36)
		main.draw_string(font, Vector2(400 - msg_size.x / 2, 270), msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1.0, 0.85, 0.2))
		var sub := "All 3 acts completed!  |  Click to return"
		var sub_size := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		main.draw_string(font, Vector2(400 - sub_size.x / 2, 310), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.75, 0.5))
	elif main.run_overlay == "elite_reward":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.72))
		var ep := Rect2(200, 200, 400, 160)
		main.draw_rect(ep, Color(0.08, 0.06, 0.12))
		main.draw_rect(ep, Color(0.8, 0.5, 0.2), false, 2.0)
		var et := "ELITE REWARD"
		var et_sz := font.get_string_size(et, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
		main.draw_string(font, Vector2(400 - et_sz.x / 2, 232), et,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.7, 0.2))
		if main.reward_relics.size() > 0:
			var rid: String = main.reward_relics[0]
			var rd: Dictionary = GameRelics.RELICS[rid]
			_draw_relic_diamond(Vector2(260, 275), 10.0, rd["color"])
			main.draw_string(font, Vector2(280, 272), rd["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, rd["color"])
			main.draw_string(font, Vector2(280, 290), rd["description"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.75))
			var claim := "Click to claim"
			var cl_sz := font.get_string_size(claim, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			main.draw_string(font, Vector2(400 - cl_sz.x / 2, 340), claim,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.7))
	elif main.run_overlay == "boss_reward":
		main.draw_rect(Rect2(0, 0, GameData.SCREEN_W, GameData.SCREEN_H), Color(0, 0, 0, 0.72))
		var bp := Rect2(80, 170, 640, 240)
		main.draw_rect(bp, Color(0.08, 0.06, 0.12))
		main.draw_rect(bp, Color(0.9, 0.6, 0.1), false, 2.0)
		var bt := "BOSS REWARD — Choose One"
		var bt_sz := font.get_string_size(bt, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
		main.draw_string(font, Vector2(400 - bt_sz.x / 2, 202), bt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.2))
		for i in range(main.reward_relics.size()):
			var rid: String = main.reward_relics[i]
			var rd: Dictionary = GameRelics.RELICS[rid]
			var cx: float = 115.0 + i * 200.0
			var card := Rect2(cx, 220, 170, 160)
			var hovered: bool = card.has_point(main.mouse_pos)
			main.draw_rect(card, Color(0.12, 0.1, 0.16) if not hovered else Color(0.18, 0.15, 0.22))
			main.draw_rect(card, rd["color"] if hovered else Color(0.35, 0.35, 0.4), false, 1.5 if not hovered else 2.5)
			_draw_relic_diamond(Vector2(cx + 85, 255), 12.0, rd["color"])
			var rn_sz := font.get_string_size(rd["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			main.draw_string(font, Vector2(cx + 85 - rn_sz.x / 2, 290), rd["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, rd["color"])
			# Word wrap description
			main.draw_string(font, Vector2(cx + 10, 310), rd["description"],
				HORIZONTAL_ALIGNMENT_LEFT, 150, 11, Color(0.7, 0.7, 0.75))

	# Draw collected relic icons on the map
	if main.run_overlay == "" and main.run_relics.size() > 0:
		draw_relic_icons_map(font)

# === HUD Drawing ===

func _draw_relic_diamond(center: Vector2, size: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(size * 0.7, 0),
		center + Vector2(0, size),
		center + Vector2(-size * 0.7, 0),
	])
	main.draw_colored_polygon(pts, col.darkened(0.4))
	main.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.5)

func draw_relic_icons_map(font: Font) -> void:
	var origin := Vector2(20, 550)
	var spacing: float = 16.0
	for i in range(main.run_relics.size()):
		var rid: String = main.run_relics[i]
		var rd: Dictionary = GameRelics.RELICS[rid]
		var ix: float = origin.x + i * spacing
		var iy: float = origin.y
		_draw_relic_diamond(Vector2(ix, iy), 5.0, rd["color"])
		if Rect2(ix - 6, iy - 6, 12, 12).has_point(main.mouse_pos):
			var tip_w: float = 160.0
			var tip_h: float = 36.0
			var tip_x: float = clampf(ix - 8, 5, GameData.SCREEN_W - tip_w - 5)
			var tip_y: float = iy - tip_h - 4.0
			main.draw_rect(Rect2(tip_x, tip_y, tip_w, tip_h), Color(0.08, 0.08, 0.12, 0.97))
			main.draw_rect(Rect2(tip_x, tip_y, tip_w, tip_h), rd["color"], false, 1.0)
			main.draw_string(font, Vector2(tip_x + 6, tip_y + 14), rd["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, rd["color"])
			main.draw_string(font, Vector2(tip_x + 6, tip_y + 28), rd["description"],
				HORIZONTAL_ALIGNMENT_LEFT, 148, 10, Color(0.75, 0.75, 0.8))

func draw_relic_icons_battle(origin: Vector2) -> void:
	if not main.in_roguelike_run or main.run_relics.size() == 0:
		return
	var font := ThemeDB.fallback_font
	var spacing: float = 14.0
	for i in range(main.run_relics.size()):
		var rid: String = main.run_relics[i]
		var rd: Dictionary = GameRelics.RELICS[rid]
		var ix: float = origin.x + i * spacing
		var iy: float = origin.y
		_draw_relic_diamond(Vector2(ix, iy), 4.0, rd["color"])
		if Rect2(ix - 5, iy - 5, 10, 10).has_point(main.mouse_pos):
			var tip_w: float = 150.0
			var tip_h: float = 34.0
			var tip_x: float = clampf(ix - 8, 5, GameData.SCREEN_W - tip_w - 5)
			var tip_y: float = iy + 8
			main.draw_rect(Rect2(tip_x, tip_y, tip_w, tip_h), Color(0.08, 0.08, 0.12, 0.97))
			main.draw_rect(Rect2(tip_x, tip_y, tip_w, tip_h), rd["color"], false, 1.0)
			main.draw_string(font, Vector2(tip_x + 5, tip_y + 13), rd["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, rd["color"])
			main.draw_string(font, Vector2(tip_x + 5, tip_y + 26), rd["description"],
				HORIZONTAL_ALIGNMENT_LEFT, 140, 9, Color(0.75, 0.75, 0.8))

func draw_upgrade_icon_symbol(key: String, center: Vector2, size: float, col: Color) -> void:
	match key:
		"speed":
			var pts := PackedVector2Array([
				center + Vector2(size, 0),
				center + Vector2(-size * 0.6, -size * 0.75),
				center + Vector2(-size * 0.6, size * 0.75),
			])
			main.draw_colored_polygon(pts, col)
		"attack":
			var lw: float = maxf(1.5, size * 0.38)
			main.draw_line(center + Vector2(-size, -size), center + Vector2(size, size), col, lw)
			main.draw_line(center + Vector2(size, -size), center + Vector2(-size, size), col, lw)
		"defense":
			var lw: float = maxf(1.0, size * 0.32)
			main.draw_arc(center + Vector2(0, -size * 0.2), size * 0.9, PI, TAU, 12, col, lw)
			main.draw_line(center + Vector2(-size * 0.9, -size * 0.2), center + Vector2(0, size * 0.9), col, lw)
			main.draw_line(center + Vector2(size * 0.9, -size * 0.2), center + Vector2(0, size * 0.9), col, lw)

func draw_run_upgrade_icons(origin: Vector2, icon_size: float) -> void:
	if not main.in_roguelike_run:
		return
	var font := ThemeDB.fallback_font
	var keys   := ["speed",              "attack",             "defense"            ]
	var colors := [Color(0.35, 0.75, 1.0), Color(1.0, 0.5, 0.25), Color(0.35, 0.9, 0.45)]
	var tip_names := ["Speed Boost",  "Attack Bonus",  "Defense Bonus" ]
	var tip_descs := ["+10% movement speed per level", "+10% attack power per level", "+10% defense per level"]
	var spacing: float = icon_size + 4.0

	var hovered: int = -1
	for i in range(3):
		if Rect2(origin.x + i * spacing, origin.y, icon_size, icon_size).has_point(main.mouse_pos):
			hovered = i

	for i in range(3):
		var lvl: int = main.run_upgrades.get(keys[i], 0)
		var col: Color = colors[i] if lvl > 0 else Color(0.28, 0.28, 0.32)
		var border: Color = colors[i] if lvl > 0 else Color(0.3, 0.3, 0.35)
		var ix: float = origin.x + i * spacing
		var iy: float = origin.y
		main.draw_rect(Rect2(ix, iy, icon_size, icon_size), Color(0.1, 0.1, 0.14))
		main.draw_rect(Rect2(ix, iy, icon_size, icon_size), border, false, 1.0)
		draw_upgrade_icon_symbol(keys[i], Vector2(ix + icon_size * 0.5, iy + icon_size * 0.5), icon_size * 0.3, col)
		if lvl > 0:
			var lv_str := str(lvl)
			var lv_sz := font.get_string_size(lv_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
			main.draw_string(font, Vector2(ix + icon_size - lv_sz.x - 1, iy + icon_size - 1),
				lv_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 1.0, 1.0, 0.95))

	if hovered >= 0:
		var lvl: int = main.run_upgrades.get(keys[hovered], 0)
		var ix: float = origin.x + hovered * spacing
		var iy: float = origin.y
		var tip_w: float = 182.0
		var tip_h: float = 44.0
		var tip_x: float = clampf(ix - 8, 5, GameData.SCREEN_W - tip_w - 5)
		var tip_y: float = iy + icon_size + 3.0
		if tip_y + tip_h > GameData.SCREEN_H - 10:
			tip_y = iy - tip_h - 3.0
		main.draw_rect(Rect2(tip_x, tip_y, tip_w, tip_h), Color(0.08, 0.08, 0.12, 0.97))
		main.draw_rect(Rect2(tip_x, tip_y, tip_w, tip_h), colors[hovered], false, 1.0)
		main.draw_string(font, Vector2(tip_x + 6, tip_y + 14), tip_names[hovered],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colors[hovered])
		main.draw_string(font, Vector2(tip_x + 6, tip_y + 27), tip_descs[hovered],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.75, 0.8))
		var total_str := "Current: +" + str(lvl * 10) + "%"
		main.draw_string(font, Vector2(tip_x + 6, tip_y + 40), total_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.88, 0.55) if lvl > 0 else Color(0.45, 0.45, 0.5))

func draw_hud() -> void:
	var font := ThemeDB.fallback_font

	if main.current_mode == "neutral":
		var owned: int = 0
		for b in main.buildings:
			if b["owner"] == "player":
				owned += 1
		var hud_text: String = "Buildings: %d/%d" % [owned, main.buildings.size()]
		main.draw_string(font, Vector2(10, 24), hud_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.9))
	else:
		var player_count: int = 0
		var opponent_count: int = 0
		var neutral_count: int = 0
		for b in main.buildings:
			if b["owner"] == "player":
				player_count += 1
			elif b["owner"] == "opponent":
				opponent_count += 1
			else:
				neutral_count += 1
		var hud_text: String = "You: %d  |  Neutral: %d  |  AI: %d" % [player_count, neutral_count, opponent_count]
		main.draw_string(font, Vector2(10, 24), hud_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.9))

	if main.in_roguelike_run:
		var rbar_x: float = 620.0
		var rbar_y: float = 8.0
		var rbar_w: float = 150.0
		var rbar_h: float = 10.0
		var rt_col := Color(0.3, 0.8, 0.4) if main.run_time_left >= 60.0 else Color(0.9, 0.4, 0.1)
		main.draw_rect(Rect2(rbar_x, rbar_y, rbar_w, rbar_h), Color(0.1, 0.12, 0.1))
		var rfill: float = rbar_w * clampf(main.run_time_left / 600.0, 0.0, 1.0)
		main.draw_rect(Rect2(rbar_x, rbar_y, rfill, rbar_h), rt_col)
		var time_str: String = main._format_run_time()
		var rtxt_col := Color(0.85, 1.0, 0.85)
		if main.run_time_left < 30.0:
			rtxt_col = Color(1.0, 0.3, 0.3) if int(main.game_time * 2.0) % 2 == 0 else Color(0.7, 0.1, 0.1)
		elif main.run_time_left < 60.0:
			rtxt_col = Color(1.0, 0.7, 0.3)
		main.draw_string(font, Vector2(rbar_x + 4, rbar_y + 21), "Time: " + time_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, rtxt_col)
		var rgold_text := "Gold: %d" % main.run_gold
		main.draw_string(font, Vector2(rbar_x + 4, rbar_y + 33), rgold_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.2))
		draw_run_upgrade_icons(Vector2(rbar_x - 58, rbar_y + 4), 14.0)
		draw_relic_icons_battle(Vector2(rbar_x - 58, rbar_y + 22))

	if main.in_roguelike_run and main.run_hero != "":
		draw_hero_power_hud(font)

	var help_text: String = "Click: menu  |  Right-click: quick upgrade  |  Drag: send  |  Forges: +10% str  |  Towers: shoot enemies"
	main.draw_string(font, Vector2(10, 590), help_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6, 0.8))

	draw_ratio_bar()

	if main.game_won:
		var win_text: String = "VICTORY! All buildings captured!" if main.current_mode == "neutral" else "VICTORY! Opponent defeated!"
		draw_end_overlay(win_text, Color(1, 1, 0.3))

	if main.game_lost:
		var lost_text: String
		if main.in_roguelike_run and main.run_time_left <= 0.0:
			lost_text = "TIME'S UP! Run time expired."
		else:
			lost_text = "DEFEATED! All your buildings lost."
		draw_end_overlay(lost_text, Color(1.0, 0.3, 0.3))

func draw_hero_power_hud(font: Font) -> void:
	var hero_data: Dictionary = GameData.HERO_DATA[main.run_hero]
	var hero_color: Color = hero_data["color"]
	var powers: Array = hero_data["powers"]

	var ebar_w: float = 200.0
	var ebar_h: float = 8.0
	var ebar_x: float = (GameData.SCREEN_W - ebar_w) / 2.0
	var ebar_y: float = 4.0
	main.draw_rect(Rect2(ebar_x - 1, ebar_y - 1, ebar_w + 2, ebar_h + 2), Color(0.2, 0.2, 0.25))
	main.draw_rect(Rect2(ebar_x, ebar_y, ebar_w, ebar_h), Color(0.08, 0.08, 0.12))
	var fill_w: float = ebar_w * clampf(main.hero_energy / main.hero_max_energy, 0.0, 1.0)
	var energy_col := hero_color.lerp(Color(1, 1, 0.5), 0.3)
	main.draw_rect(Rect2(ebar_x, ebar_y, fill_w, ebar_h), energy_col)
	var energy_str := "%d/%d" % [int(main.hero_energy), int(main.hero_max_energy)]
	var estr_size := font.get_string_size(energy_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	main.draw_string(font, Vector2(GameData.SCREEN_W / 2 - estr_size.x / 2, ebar_y + ebar_h + 11), energy_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.85))

	var btn_w: float = 80.0
	var btn_h: float = 36.0
	var btn_gap: float = 6.0
	var total_btn_w: float = btn_w * 4 + btn_gap * 3
	var btn_start_x: float = (GameData.SCREEN_W - total_btn_w) / 2.0
	var btn_y: float = ebar_y + ebar_h + 16.0

	var hovered_power: int = -1
	for i in range(4):
		var bx: float = btn_start_x + i * (btn_w + btn_gap)
		var power: Dictionary = powers[i]
		if Rect2(bx, btn_y, btn_w, btn_h).has_point(main.mouse_pos):
			hovered_power = i
		var affordable: bool = main.hero_energy >= power["cost"]
		var on_cooldown: bool = main.hero_power_cooldowns[i] > 0.0
		var is_targeting: bool = main.hero_targeting_power == i
		var usable: bool = affordable and not on_cooldown

		var bg: Color
		if is_targeting:
			bg = hero_color.darkened(0.5)
		elif usable:
			bg = Color(0.14, 0.14, 0.2)
		else:
			bg = Color(0.08, 0.08, 0.1)
		main.draw_rect(Rect2(bx, btn_y, btn_w, btn_h), bg)

		var border_col: Color
		if is_targeting:
			border_col = hero_color
		elif usable:
			border_col = hero_color.darkened(0.3)
		else:
			border_col = Color(0.25, 0.25, 0.3)
		main.draw_rect(Rect2(bx, btn_y, btn_w, btn_h), border_col, false, 1.0)

		if on_cooldown:
			var cd_frac: float = main.hero_power_cooldowns[i] / power["cooldown"]
			main.draw_rect(Rect2(bx, btn_y, btn_w * cd_frac, btn_h), Color(0.1, 0.1, 0.15, 0.7))

		var text_col: Color = Color(0.9, 0.9, 0.95) if usable else Color(0.4, 0.4, 0.45)
		main.draw_string(font, Vector2(bx + 3, btn_y + 12), str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hero_color if usable else Color(0.35, 0.35, 0.4))

		var pname: String = power["name"]
		if pname.length() > 10:
			pname = pname.left(9) + "."
		main.draw_string(font, Vector2(bx + 14, btn_y + 12), pname,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_col)

		var cost_str := "%d" % power["cost"]
		var cost_col: Color = Color(0.9, 0.85, 0.3) if affordable else Color(0.5, 0.3, 0.3)
		main.draw_string(font, Vector2(bx + 3, btn_y + 26), cost_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cost_col)

		if on_cooldown:
			var cd_str := "%.1fs" % main.hero_power_cooldowns[i]
			main.draw_string(font, Vector2(bx + 30, btn_y + 26), cd_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.4, 0.4))

	if hovered_power >= 0 and main.hero_targeting_power < 0:
		var hp: Dictionary = powers[hovered_power]
		var tip: String = hp["name"] + " — " + hp["desc"]
		var tip_size := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
		var tip_x: float = GameData.SCREEN_W / 2 - tip_size.x / 2
		var tip_y: float = btn_y + btn_h + 4
		main.draw_rect(Rect2(tip_x - 4, tip_y - 1, tip_size.x + 8, 16), Color(0.05, 0.05, 0.1, 0.9))
		main.draw_string(font, Vector2(tip_x, tip_y + 11), tip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.85, 0.9))

	if main.hero_targeting_power >= 0:
		var target_text: String = "Select target..."
		var targeting: String = powers[main.hero_targeting_power]["targeting"]
		if targeting == "friendly_node":
			target_text = "Click a friendly node"
		elif targeting == "enemy_node":
			target_text = "Click an enemy node"
		elif targeting == "any_node":
			target_text = "Click any node"
		elif targeting == "friendly_node_pair":
			if main.hero_supply_first_node < 0:
				target_text = "Click first friendly node"
			else:
				target_text = "Click second friendly node"
		elif targeting == "path":
			if main.hero_minefield_source < 0:
				target_text = "Click first node (path start)"
			else:
				target_text = "Click second node (path end)"
		var tt_size := font.get_string_size(target_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		main.draw_string(font, Vector2(GameData.SCREEN_W / 2 - tt_size.x / 2, btn_y + btn_h + 14), target_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hero_color)

func draw_end_overlay(text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
	main.draw_string(font, Vector2(GameData.SCREEN_W / 2.0 - text_size.x / 2, 280),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, color)
	var click_text := "Click anywhere to return to menu"
	var ct_size := font.get_string_size(click_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	main.draw_string(font, Vector2(GameData.SCREEN_W / 2.0 - ct_size.x / 2, 320),
		click_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.7))

func draw_ratio_bar() -> void:
	var font := ThemeDB.fallback_font
	var bar_x: float = 8.0
	var bar_w: float = 36.0
	var bar_y: float = 80.0
	var section_h: float = 50.0
	var display_labels: Array = ["100%", "75%", "50%", "25%"]
	var display_ratios: Array = [1.0, 0.75, 0.5, 0.25]

	main.draw_rect(Rect2(bar_x, bar_y, bar_w, section_h * 4), Color(0.1, 0.1, 0.15, 0.9))

	for i in range(4):
		var sy: float = bar_y + i * section_h
		var is_selected: bool = absf(main.send_ratio - display_ratios[i]) < 0.01

		if is_selected:
			main.draw_rect(Rect2(bar_x, sy, bar_w, section_h), Color(0.2, 0.4, 0.9, 0.7))

		if i > 0:
			main.draw_line(Vector2(bar_x, sy), Vector2(bar_x + bar_w, sy), Color(0.3, 0.3, 0.4), 1.0)

		var label: String = display_labels[i]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		var tx: float = bar_x + (bar_w - text_size.x) / 2.0
		var ty: float = sy + (section_h + text_size.y) / 2.0 - 2.0
		var text_color := Color(1, 1, 1) if is_selected else Color(0.6, 0.6, 0.6)
		main.draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_color)

	main.draw_rect(Rect2(bar_x, bar_y, bar_w, section_h * 4), Color(0.4, 0.4, 0.5), false, 1.0)
