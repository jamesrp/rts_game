class_name GameRelics
extends RefCounted

# All relic definitions keyed by ID
const RELICS: Dictionary = {
	# === Hero Relics (cost 150g in shop) ===
	# Commander
	"warchief_banner": {
		"name": "Warchief Banner",
		"description": "Rally sends 50% of units",
		"hero": "commander",
		"cost": 150,
		"tier": "hero",
		"color": Color(0.9, 0.3, 0.3),
	},
	"shock_doctrine": {
		"name": "Shock Doctrine",
		"description": "Blitz lasts 18s",
		"hero": "commander",
		"cost": 150,
		"tier": "hero",
		"color": Color(1.0, 0.4, 0.2),
	},
	# Warden
	"reinforced_walls": {
		"name": "Reinforced Walls",
		"description": "Fortify 14s + adds 5 units",
		"hero": "warden",
		"cost": 150,
		"tier": "hero",
		"color": Color(0.3, 0.7, 0.3),
	},
	"concertina_wire": {
		"name": "Concertina Wire",
		"description": "Minefield slows survivors",
		"hero": "warden",
		"cost": 150,
		"tier": "hero",
		"color": Color(0.5, 0.8, 0.3),
	},
	# Saboteur
	"deep_cover": {
		"name": "Deep Cover",
		"description": "Sabotage 20s + halves garrison",
		"hero": "saboteur",
		"cost": 150,
		"tier": "hero",
		"color": Color(0.6, 0.2, 0.8),
	},
	"double_agent": {
		"name": "Double Agent",
		"description": "Turncoat converts 50%",
		"hero": "saboteur",
		"cost": 150,
		"tier": "hero",
		"color": Color(0.8, 0.3, 0.9),
	},
	# Architect
	"rapid_expansion": {
		"name": "Rapid Expansion",
		"description": "Terraform adds +3 levels",
		"hero": "architect",
		"cost": 150,
		"tier": "hero",
		"color": Color(0.2, 0.6, 0.9),
	},
	"grid_link": {
		"name": "Grid Link",
		"description": "Supply Line lasts 25s",
		"hero": "architect",
		"cost": 150,
		"tier": "hero",
		"color": Color(0.3, 0.8, 1.0),
	},

	# === Universal Relics (cost 120g in shop) ===
	"capacitor": {
		"name": "Capacitor",
		"description": "+25% energy generation",
		"hero": "",
		"cost": 120,
		"tier": "universal",
		"color": Color(1.0, 0.9, 0.3),
	},
	"efficiency_core": {
		"name": "Efficiency Core",
		"description": "-20% hero power costs",
		"hero": "",
		"cost": 120,
		"tier": "universal",
		"color": Color(0.4, 0.9, 0.6),
	},
	"surge_converter": {
		"name": "Surge Converter",
		"description": "Capture grants +15 energy",
		"hero": "",
		"cost": 120,
		"tier": "universal",
		"color": Color(0.9, 0.6, 0.2),
	},
	"feedback_loop": {
		"name": "Feedback Loop",
		"description": "10% power cost refunded",
		"hero": "",
		"cost": 120,
		"tier": "universal",
		"color": Color(0.5, 0.7, 1.0),
	},

	# === Passive Relics (cost 100g in shop) ===
	"gen_boost": {
		"name": "Gen Boost",
		"description": "+15% unit generation",
		"hero": "",
		"cost": 100,
		"tier": "passive",
		"color": Color(0.3, 0.85, 0.3),
	},
	"swift_legs": {
		"name": "Swift Legs",
		"description": "+20% unit speed",
		"hero": "",
		"cost": 100,
		"tier": "passive",
		"color": Color(0.35, 0.75, 1.0),
	},
	"deep_reserves": {
		"name": "Deep Reserves",
		"description": "+25% building capacity",
		"hero": "",
		"cost": 100,
		"tier": "passive",
		"color": Color(0.6, 0.5, 0.9),
	},
	"burst_capture": {
		"name": "Burst Capture",
		"description": "+5 units on building capture",
		"hero": "",
		"cost": 100,
		"tier": "passive",
		"color": Color(1.0, 0.7, 0.3),
	},
	"heritage": {
		"name": "Heritage",
		"description": "Captured buildings keep level",
		"hero": "",
		"cost": 100,
		"tier": "passive",
		"color": Color(0.8, 0.7, 0.4),
	},
	"dynamo": {
		"name": "Dynamo",
		"description": "+20% energy generation",
		"hero": "",
		"cost": 100,
		"tier": "passive",
		"color": Color(1.0, 0.85, 0.2),
	},
	"free_opener": {
		"name": "Free Opener",
		"description": "First power free each battle",
		"hero": "",
		"cost": 100,
		"tier": "passive",
		"color": Color(0.9, 0.9, 0.5),
	},

	# === Boss Relics (choice of 3 after boss, not sold) ===
	"war_machine": {
		"name": "War Machine",
		"description": "+30% attack power",
		"hero": "",
		"cost": 0,
		"tier": "boss",
		"color": Color(1.0, 0.3, 0.2),
	},
	"iron_bastion": {
		"name": "Iron Bastion",
		"description": "+30% defense",
		"hero": "",
		"cost": 0,
		"tier": "boss",
		"color": Color(0.4, 0.8, 0.4),
	},
	"overdrive": {
		"name": "Overdrive",
		"description": "+50% energy generation",
		"hero": "",
		"cost": 0,
		"tier": "boss",
		"color": Color(1.0, 0.8, 0.1),
	},
	"temporal_flux": {
		"name": "Temporal Flux",
		"description": "+90s run timer",
		"hero": "",
		"cost": 0,
		"tier": "boss",
		"color": Color(0.3, 0.7, 1.0),
	},
	"gold_hoard": {
		"name": "Gold Hoard",
		"description": "+50g now, +5g per fight",
		"hero": "",
		"cost": 0,
		"tier": "boss",
		"color": Color(1.0, 0.85, 0.2),
	},
	"titan_form": {
		"name": "Titan Form",
		"description": "+40% capacity, +15% gen",
		"hero": "",
		"cost": 0,
		"tier": "boss",
		"color": Color(0.7, 0.4, 0.9),
	},
}

# Get 2 relics for the merchant shop: 1 matching hero or universal, 1 passive or universal
static func get_shop_relics(hero: String, owned_ids: Array) -> Array:
	var hero_pool: Array = []
	var universal_pool: Array = []
	var passive_pool: Array = []
	for id in RELICS:
		if id in owned_ids:
			continue
		var r: Dictionary = RELICS[id]
		if r["tier"] == "hero" and r["hero"] == hero:
			hero_pool.append(id)
		elif r["tier"] == "universal":
			universal_pool.append(id)
		elif r["tier"] == "passive":
			passive_pool.append(id)

	var result: Array = []

	# Slot 1: hero relic or universal
	var slot1_pool: Array = hero_pool + universal_pool
	slot1_pool.shuffle()
	if slot1_pool.size() > 0:
		result.append(slot1_pool[0])

	# Slot 2: passive or universal (not already picked)
	var slot2_pool: Array = passive_pool + universal_pool
	slot2_pool.shuffle()
	for id in slot2_pool:
		if id not in result:
			result.append(id)
			break

	return result

# Get 1 relic reward after elite fight
static func get_elite_relic(hero: String, owned_ids: Array) -> String:
	var pool: Array = []
	for id in RELICS:
		if id in owned_ids:
			continue
		var r: Dictionary = RELICS[id]
		if r["tier"] == "boss":
			continue
		if r["tier"] == "hero" and r["hero"] != hero:
			continue
		pool.append(id)
	pool.shuffle()
	if pool.size() > 0:
		return pool[0]
	return ""

# Get 3 boss relic choices after boss fight
static func get_boss_relics(owned_ids: Array) -> Array:
	var pool: Array = []
	for id in RELICS:
		if id in owned_ids:
			continue
		var r: Dictionary = RELICS[id]
		if r["tier"] == "boss":
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, mini(3, pool.size()))
