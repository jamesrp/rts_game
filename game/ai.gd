class_name GameAI
extends RefCounted

var main

func _init(main_node) -> void:
	main = main_node

func get_interval() -> float:
	match main.current_level:
		1: return 5.0
		2: return 3.5
		3: return 2.5
		_: return 2.0

func get_send_ratio() -> float:
	match main.current_level:
		1: return 0.6
		2: return 0.6
		3: return 0.7
		_: return 0.8

func update(delta: float) -> void:
	main.ai_timer += delta
	var interval: float = get_interval()
	if main.ai_timer < interval:
		return
	main.ai_timer -= interval

	# Total Shutdown: EMP completely blocks AI actions
	for fx in main.hero_active_effects:
		if fx["type"] == "emp" and fx["timer"] < fx["duration"] and fx.get("total_shutdown", false):
			return

	var ai_buildings: Array = []
	for b in main.buildings:
		if b["owner"] == "opponent":
			ai_buildings.append(b)
	if ai_buildings.is_empty():
		return

	match main.current_level:
		1: _novice(ai_buildings)
		2: _expander(ai_buildings)
		3: _aggressor(ai_buildings)
		_: _general(ai_buildings)

# --- Level 1: Novice ---
func _novice(ai_buildings: Array) -> void:
	if randf() < 0.3:
		if _do_upgrade(ai_buildings):
			return
	_send_one(ai_buildings, _find_weakest("opponent"))

# --- Level 2: Expander ---
func _expander(ai_buildings: Array) -> void:
	if randf() < 0.2:
		if _do_upgrade(ai_buildings):
			return

	var target: Dictionary = _find_weakest_by_owner("neutral")
	if target.is_empty():
		target = _find_weakest_by_owner("player")
	if target.is_empty():
		return

	var sorted_sources: Array = _sort_by_units(ai_buildings)
	var sends: int = 0
	for source in sorted_sources:
		if sends >= 2:
			break
		if _do_send(source, target):
			sends += 1

# --- Level 3: Aggressor ---
func _aggressor(ai_buildings: Array) -> void:
	if randf() < 0.15:
		if _do_upgrade(ai_buildings):
			return

	var target: Dictionary = _find_weakest_by_owner("player")
	if target.is_empty():
		target = _find_weakest_by_owner("neutral")
	if target.is_empty():
		return

	var sorted_sources: Array = _sort_by_units(ai_buildings)
	var sends: int = 0
	for source in sorted_sources:
		if sends >= 3:
			break
		if _do_send(source, target):
			sends += 1

# --- Level 4: General ---
func _general(ai_buildings: Array) -> void:
	var ai_count: int = ai_buildings.size()
	var total_ai_units: int = 0
	var max_level: int = 0
	for b in ai_buildings:
		total_ai_units += b["units"]
		if b["level"] > max_level:
			max_level = b["level"]

	var neutral_count: int = 0
	for b in main.buildings:
		if b["owner"] == "neutral":
			neutral_count += 1

	# Phase 1: Expand — grab nearby neutrals first
	if neutral_count > 0 and ai_count < 4:
		var target: Dictionary = _find_closest_neutral(ai_buildings)
		if not target.is_empty():
			var closest_source: Dictionary = _find_closest_source(ai_buildings, target)
			if not closest_source.is_empty():
				_do_send(closest_source, target)
				return

	# Phase 2: Upgrade
	var upgradable: int = 0
	for b in ai_buildings:
		if b["level"] < GameData.MAX_BUILDING_LEVEL:
			upgradable += 1
	if upgradable > 0 and randf() < 0.5:
		if _do_upgrade(ai_buildings):
			return

	# Phase 3: Attack
	var target: Dictionary = _find_beatable_target(ai_buildings, total_ai_units)
	if target.is_empty():
		_do_upgrade(ai_buildings)
		return

	var sorted_sources: Array = _sort_by_units(ai_buildings)
	for source in sorted_sources:
		_do_send(source, target)

# === AI Helpers ===

func _do_upgrade(ai_buildings: Array) -> bool:
	var sorted: Array = _sort_by_units(ai_buildings)
	for b in sorted:
		if b["type"] == "forge" or b["upgrading"]:
			continue
		var cost: int = GameData.get_tower_upgrade_cost() if b["type"] == "tower" else GameData.get_upgrade_cost(b["level"])
		if b["level"] < GameData.MAX_BUILDING_LEVEL and b["units"] >= cost:
			main._start_building_upgrade(b, cost, GameData.get_upgrade_duration(b["level"]))
			return true
	return false

func _do_send(source: Dictionary, target: Dictionary) -> bool:
	var send_count: int = int(source["units"] * get_send_ratio())
	if send_count <= 2:
		return false
	main.dispatch_queues.append({
		"source_id": source["id"],
		"target_id": target["id"],
		"owner": "opponent",
		"remaining": send_count,
		"wave_timer": 0.0,
		"start_pos": source["position"],
		"end_pos": target["position"],
	})
	return true

func _send_one(ai_buildings: Array, target: Dictionary) -> void:
	if target.is_empty():
		return
	var best_source: Dictionary = {}
	var best_units: int = 0
	for b in ai_buildings:
		if b["units"] > best_units:
			best_units = b["units"]
			best_source = b
	if not best_source.is_empty():
		_do_send(best_source, target)

func _sort_by_units(ai_buildings: Array) -> Array:
	var sorted: Array = ai_buildings.duplicate()
	sorted.sort_custom(func(a, b): return a["units"] > b["units"])
	return sorted

func _find_weakest(exclude_owner: String = "") -> Dictionary:
	var best: Dictionary = {}
	var lowest: int = 9999
	for b in main.buildings:
		if b["owner"] == exclude_owner:
			continue
		if b["units"] < lowest:
			lowest = b["units"]
			best = b
	return best

func _find_weakest_by_owner(owner: String) -> Dictionary:
	var best: Dictionary = {}
	var lowest: int = 9999
	for b in main.buildings:
		if b["owner"] != owner:
			continue
		if b["units"] < lowest:
			lowest = b["units"]
			best = b
	return best

func _find_closest_neutral(ai_buildings: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = 99999.0
	for b in main.buildings:
		if b["owner"] != "neutral":
			continue
		for ab in ai_buildings:
			var dist: float = ab["position"].distance_to(b["position"])
			if dist < best_dist:
				best_dist = dist
				best = b
	return best

func _find_closest_source(ai_buildings: Array, target: Dictionary) -> Dictionary:
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

func _find_beatable_target(ai_buildings: Array, total_ai_units: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1.0
	for b in main.buildings:
		if b["owner"] == "opponent":
			continue
		var defenders: int = b["units"]
		if defenders <= 0:
			defenders = 1
		var sendable: int = int(total_ai_units * get_send_ratio())
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
