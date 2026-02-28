class_name GameData
extends RefCounted

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

static var HERO_DATA: Dictionary = {
	"commander": {
		"name": "Commander",
		"color": Color(0.9, 0.3, 0.2),
		"desc": "Offensive leader: rally troops, boost speed, conscript units",
		"powers": [
			{"name": "Rally Cry", "cost": 15, "cooldown": 3.0, "desc": "All nodes send 30% to target", "targeting": "any_node"},
			{"name": "Forced March", "cost": 15, "cooldown": 5.0, "desc": "Units move 2x speed for 8s", "targeting": "instant"},
			{"name": "Conscription", "cost": 35, "cooldown": 8.0, "desc": "All nodes gain bonus units", "targeting": "instant"},
			{"name": "Blitz", "cost": 60, "cooldown": 20.0, "desc": "2x attack + instant gen for 12s", "targeting": "instant"},
		]
	},
	"warden": {
		"name": "Warden",
		"color": Color(0.2, 0.7, 0.9),
		"desc": "Defensive guardian: fortify nodes, lay traps, build citadels",
		"powers": [
			{"name": "Fortify", "cost": 15, "cooldown": 5.0, "desc": "Node invulnerable 8s", "targeting": "friendly_node"},
			{"name": "Entrench", "cost": 15, "cooldown": 5.0, "desc": "Node +50% defense 15s", "targeting": "friendly_node"},
			{"name": "Minefield", "cost": 35, "cooldown": 10.0, "desc": "Enemies on path lose 40%", "targeting": "path"},
			{"name": "Citadel", "cost": 60, "cooldown": 25.0, "desc": "2x cap + 3x gen 20s", "targeting": "friendly_node"},
		]
	},
	"saboteur": {
		"name": "Saboteur",
		"color": Color(0.6, 0.2, 0.8),
		"desc": "Disruption specialist: sabotage, slow, convert enemy forces",
		"powers": [
			{"name": "Sabotage", "cost": 15, "cooldown": 5.0, "desc": "Enemy node stops gen 12s", "targeting": "enemy_node"},
			{"name": "Blackout", "cost": 15, "cooldown": 5.0, "desc": "Enemy transit slowed 50% 10s", "targeting": "instant"},
			{"name": "Turncoat", "cost": 35, "cooldown": 12.0, "desc": "Convert 30% of enemy units", "targeting": "enemy_node"},
			{"name": "EMP", "cost": 60, "cooldown": 25.0, "desc": "All enemy gen+transit stop 10s", "targeting": "instant"},
		]
	},
	"architect": {
		"name": "Architect",
		"color": Color(0.2, 0.8, 0.4),
		"desc": "Economy master: overclock production, upgrade, share resources",
		"powers": [
			{"name": "Overclock", "cost": 15, "cooldown": 5.0, "desc": "Node 3x gen for 12s", "targeting": "friendly_node"},
			{"name": "Supply Line", "cost": 15, "cooldown": 8.0, "desc": "Two nodes share units 15s", "targeting": "friendly_node_pair"},
			{"name": "Terraform", "cost": 35, "cooldown": 12.0, "desc": "Instantly upgrade node +2", "targeting": "friendly_node"},
			{"name": "Nexus", "cost": 60, "cooldown": 25.0, "desc": "All nodes gen at max level 15s", "targeting": "instant"},
		]
	},
}

# === Level Configurations ===

static func get_neutral_level(level: int) -> Dictionary:
	var positions: Array = [
		Vector2(120, 300),
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
	var extra_count: int = (level - 1) * 3
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
	var valid_forges: Array = []
	for fi in forges:
		if fi < positions.size():
			valid_forges.append(fi)
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
	var upgrades: Dictionary = {}
	var neutral_indices: Array = []
	for i in range(positions.size()):
		if i != 0 and i not in valid_forges and i not in valid_towers:
			neutral_indices.append(i)
	neutral_indices.shuffle()
	var n: int = neutral_indices.size()
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
		assigned_level = mini(assigned_level, level)
		if assigned_level > 1:
			upgrades[ni] = assigned_level
		idx += 1
	return {"positions": positions, "units": neutral_units, "player_indices": [0], "opponent_indices": [], "forges": valid_forges, "towers": valid_towers, "upgrades": upgrades}

static func get_ai_level(level: int) -> Dictionary:
	if level == 1:
		var positions: Array = [
			Vector2(120, 450), Vector2(680, 150),
			Vector2(300, 150), Vector2(500, 100),
			Vector2(400, 300), Vector2(250, 300),
			Vector2(550, 300), Vector2(350, 480),
			Vector2(600, 450), Vector2(150, 200),
			Vector2(700, 400),
		]
		var units: Array = [20, 20, 10, 8, 12, 6, 6, 8, 10, 5, 5]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1], "forges": [4, 8], "towers": [5, 10]}
	elif level == 2:
		var positions: Array = [
			Vector2(100, 500), Vector2(700, 100),
			Vector2(250, 400), Vector2(550, 200),
			Vector2(400, 300), Vector2(200, 200),
			Vector2(600, 400), Vector2(400, 120),
			Vector2(400, 480), Vector2(150, 300),
			Vector2(650, 300), Vector2(300, 150),
			Vector2(500, 450),
		]
		var units: Array = [20, 20, 5, 5, 15, 8, 8, 10, 10, 6, 6, 7, 7]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1], "forges": [4, 7, 12], "towers": [9, 11]}
	elif level == 3:
		var positions: Array = [
			Vector2(100, 480), Vector2(700, 120),
			Vector2(580, 200), Vector2(500, 100),
			Vector2(400, 280), Vector2(250, 350),
			Vector2(600, 380), Vector2(300, 180),
			Vector2(450, 480), Vector2(150, 220),
			Vector2(700, 420), Vector2(350, 100),
		]
		var units: Array = [25, 15, 15, 5, 14, 8, 10, 10, 6, 7, 8, 12]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1, 2], "forges": [4, 7, 10], "towers": [5, 9]}
	else:
		var positions: Array = [
			Vector2(100, 500), Vector2(700, 100),
			Vector2(650, 250), Vector2(550, 120),
			Vector2(400, 300), Vector2(200, 380),
			Vector2(500, 400), Vector2(300, 200),
			Vector2(400, 480), Vector2(150, 200),
			Vector2(250, 500), Vector2(600, 450),
			Vector2(350, 120), Vector2(720, 380),
		]
		var units: Array = [20, 20, 15, 6, 20, 6, 12, 10, 8, 8, 5, 10, 12, 8]
		return {"positions": positions, "units": units, "player_indices": [0], "opponent_indices": [1, 2],
			"upgrades": {2: 2}, "forges": [4, 8, 11, 13], "towers": [5, 9]}

# === Layout Generators ===

static func get_map_node_x(col: int, total: int) -> float:
	if total == 1:
		return 400.0
	var margin: float = 150.0
	var spacing: float = (800.0 - 2.0 * margin) / float(total - 1)
	return margin + col * spacing

static func try_place_building(positions: Array, pos: Vector2, min_spacing: float) -> bool:
	pos.x = clampf(pos.x, 60.0, 740.0)
	pos.y = clampf(pos.y, 60.0, 540.0)
	for existing in positions:
		if existing.distance_to(pos) < min_spacing:
			return false
	positions.append(pos)
	return true

static func gen_corridor_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	positions.append(Vector2(100, 480))
	positions.append(Vector2(700, 120))
	var attempts: int = 0
	while positions.size() < count and attempts < 200:
		attempts += 1
		var t: float = randf()
		var base_x: float = lerpf(100.0, 700.0, t)
		var base_y: float = lerpf(480.0, 120.0, t)
		var offset_x: float = randf_range(-120.0, 120.0)
		var offset_y: float = randf_range(-80.0, 80.0)
		var pos := Vector2(base_x + offset_x, base_y + offset_y)
		try_place_building(positions, pos, min_spacing)
	return positions

static func gen_ring_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	positions.append(Vector2(120, 460))
	positions.append(Vector2(680, 140))
	var center := Vector2(400, 300)
	var ring_count: int = mini(count - 2, 10)
	for i in range(ring_count):
		var angle: float = TAU * float(i) / float(ring_count)
		var rx: float = 250.0 + randf_range(-30.0, 30.0)
		var ry: float = 170.0 + randf_range(-20.0, 20.0)
		var pos := center + Vector2(cos(angle) * rx, sin(angle) * ry)
		try_place_building(positions, pos, min_spacing)
	var attempts: int = 0
	while positions.size() < count and attempts < 100:
		attempts += 1
		var pos := center + Vector2(randf_range(-80.0, 80.0), randf_range(-60.0, 60.0))
		try_place_building(positions, pos, min_spacing)
	return positions

static func gen_clusters_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	positions.append(Vector2(110, 470))
	positions.append(Vector2(690, 130))
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
			if try_place_building(positions, pos, min_spacing):
				to_place -= 1
	var attempts: int = 0
	while positions.size() < count and attempts < 100:
		attempts += 1
		var pos := Vector2(randf_range(80.0, 720.0), randf_range(80.0, 520.0))
		try_place_building(positions, pos, min_spacing)
	return positions

static func gen_scattered_layout(count: int, min_spacing: float) -> Array:
	var positions: Array = []
	positions.append(Vector2(100 + randf_range(0, 40), 460 + randf_range(-20, 20)))
	positions.append(Vector2(680 + randf_range(-20, 20), 120 + randf_range(-20, 20)))
	var attempts: int = 0
	while positions.size() < count and attempts < 300:
		attempts += 1
		var pos := Vector2(randf_range(80.0, 720.0), randf_range(80.0, 520.0))
		try_place_building(positions, pos, min_spacing)
	return positions

# === Upgrade & Tower Helpers ===

static func get_upgrade_cost(level: int) -> int:
	match level:
		1: return 5
		2: return 10
		3: return 20
		_: return 999

static func get_upgrade_duration(level: int) -> float:
	match level:
		1: return 5.0
		2: return 10.0
		3: return 15.0
		_: return 999.0

static func get_tower_upgrade_cost() -> int:
	return FORGE_COST

static func get_tower_defense_multiplier(level: int) -> float:
	match level:
		1: return 1.4
		2: return 1.7
		3: return 1.9
		_: return 2.0

static func get_tower_shoot_interval(level: int) -> float:
	match level:
		1: return 60.0 / 90.0
		2: return 60.0 / 120.0
		3: return 60.0 / 150.0
		_: return 60.0 / 180.0

static func get_tower_shoot_radius(level: int) -> float:
	var base: float = 150.0
	match level:
		1: return base * 1.0
		2: return base * 1.1
		3: return base * 1.25
		_: return base * 1.4

# === Utility Helpers ===

static func get_owner_color(owner: String) -> Color:
	if owner == "player":
		return Color(0.3, 0.5, 1.0)
	elif owner == "opponent":
		return Color(1.0, 0.6, 0.2)
	else:
		return Color(0.6, 0.6, 0.6)

static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

static func get_unit_position(u: Dictionary) -> Vector2:
	var eased_t: float = ease_out_cubic(u["progress"])
	var center: Vector2 = u["start_pos"].lerp(u["end_pos"], eased_t)
	var dir: Vector2 = (u["end_pos"] - u["start_pos"]).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	return center + perp * u.get("lateral_offset", 0.0)
