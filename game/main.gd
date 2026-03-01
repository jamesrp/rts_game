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
var run_map_scroll: float = 0.0
var run_map_scroll_manual: bool = false
var run_current_row: int = 0
var run_last_node: int = -1  # Column index chosen in current row
var run_overlay: String = ""  # "", "run_over", "run_won", "merchant", "elite_reward", "boss_reward", "campfire", "event", "treasure"
var current_event: Dictionary = {}  # Current event data from GameEvents
var event_result_text: String = ""  # Shown after choosing
var campfire_upgrade_choices: Array = []  # Array of upgrade dicts offered at campfire
var run_hero_upgrades: Array = []  # Upgrade IDs (names) acquired during run
var run_relics: Array = []
var merchant_relics: Array = []
var merchant_relics_bought: Array = []
var reward_relics: Array = []
var treasure_relic: String = ""
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
var ai: GameAI
var hero: GameHero
var roguelike: GameRoguelike

func _ready() -> void:
	combat = GameCombat.new(self)
	ui = GameUI.new(self)
	ai = GameAI.new(self)
	hero = GameHero.new(self)
	roguelike = GameRoguelike.new(self)
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


# === Level Start ===

func _start_level(mode: String, level: int, config_override: Dictionary = {}) -> void:
	current_mode = mode
	current_level = level
	game_state = "playing"
	game_won = false
	game_lost = false
	game_time = 0.0
	ai_timer = 0.0
	_reset_battle_state()
	hero.reset_battle_state()
	selected_building_id = -1
	is_dragging = false
	drag_source_id = -1
	send_ratio = 0.5

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

func _reset_battle_state() -> void:
	buildings.clear()
	dispatch_queues.clear()
	moving_units.clear()
	visual_effects.clear()
	context_menu_building_id = -1
	context_menu_options.clear()

func _return_to_menu() -> void:
	game_state = "level_select"
	_reset_battle_state()

# === Main Loop ===

func _process(delta: float) -> void:
	if game_state == "level_select" or game_state == "hero_select":
		queue_redraw()
		return
	if game_state == "roguelike_map":
		game_time += delta
		if run_current_row < run_map.size():
			var target_y: float = run_map[run_current_row][0]["position"].y
			var scroll_target: float = target_y - 480.0
			scroll_target = clampf(scroll_target, -50.0, 400.0)
			if not run_map_scroll_manual:
				run_map_scroll = lerpf(run_map_scroll, scroll_target, minf(delta * 5.0, 1.0))
			elif absf(run_map_scroll - scroll_target) < 5.0:
				run_map_scroll_manual = false
		queue_redraw()
		return

	game_time += delta
	if in_roguelike_run and not game_won and not game_lost:
		run_time_left = maxf(0.0, run_time_left - delta)
	if game_won or game_lost:
		queue_redraw()
		return

	hero.rebuild_effect_cache()
	_update_unit_generation(delta)
	_update_upgrades(delta)
	combat.update_towers(delta)
	_update_dispatch_queues(delta)
	_update_moving_units(delta)
	_update_visual_effects(delta)
	if in_roguelike_run and run_hero != "":
		hero.update(delta)
	if current_mode == "ai":
		ai.update(delta)
	combat.check_win_condition()
	queue_redraw()

func _update_visual_effects(delta: float) -> void:
	var to_remove: Array = []
	for i in range(visual_effects.size()):
		visual_effects[i]["timer"] += delta
		if visual_effects[i]["timer"] >= visual_effects[i]["duration"]:
			to_remove.append(i)
	GameData.remove_indices(visual_effects, to_remove)


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



func _update_unit_generation(delta: float) -> void:
	# Find highest player node level for Nexus effect
	var nexus_active: bool = hero.has_effect("nexus")
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
			if hero.has_effect_on("sabotage", b["id"]) or hero.has_effect("emp"):
				continue
		var level: int = b["level"]
		# Nexus: player nodes gen at highest level
		if nexus_active and b["owner"] == "player":
			level = highest_level
		var gen_mult: float = 1.0
		# Overclock: 3x gen rate
		if b["owner"] == "player" and hero.has_effect_on("overclock", b["id"]):
			gen_mult *= 3.0
		# Overdrive: overclock spread gives 1.5x gen
		elif b["owner"] == "player" and hero.has_effect_on("overclock_spread", b["id"]):
			gen_mult *= 1.5
		# Citadel: 3x gen rate and 2x cap
		if b["owner"] == "player" and hero.has_effect_on("citadel", b["id"]):
			gen_mult *= 3.0
		# Iron Curtain: citadel spread gives 1.5x gen
		elif b["owner"] == "player" and hero.has_effect_on("citadel_spread", b["id"]):
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
		if b["owner"] == "player" and hero.has_effect_on("citadel", b["id"]):
			max_cap *= 2
		elif b["owner"] == "player" and hero.has_effect_on("citadel_spread", b["id"]):
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
	GameData.remove_indices(dispatch_queues, to_remove)

func _update_moving_units(delta: float) -> void:
	var forced_march: bool = hero.has_effect("forced_march")
	var blackout: bool = hero.has_effect("blackout")
	var emp: bool = hero.has_effect("emp")

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
	GameData.remove_indices(moving_units, resolved)

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
		roguelike.handle_map_input(event)
		return

	if game_won or game_lost:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if in_roguelike_run:
				roguelike.return_from_battle()
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
			hero.try_activate_power(key_index)
			return

	# Hero power targeting click
	if hero_targeting_power >= 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hero.handle_target_click(event.position)
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
				roguelike.start_run()
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

