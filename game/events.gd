class_name GameEvents
extends RefCounted

# Each event has:
#   "title"       – displayed at top of overlay
#   "description" – flavour text
#   "choices"     – array of {label, description, effect_text, callback_id}
#
# callback_id is matched in main.gd _apply_event_choice() to apply the effect.

const EVENTS: Array = [
	# --- Gamble: Time vs Curse ---
	{
		"title": "Mysterious Shrine",
		"description": "A crumbling shrine hums with unstable energy.\nDo you dare touch it?",
		"choices": [
			{
				"label": "Touch it",
				"description": "50% chance: gain a powerful relic. 50% chance: lose 1:30.",
				"effect_text": "",
				"callback_id": "shrine_gamble",
			},
			{
				"label": "Walk away",
				"description": "Nothing ventured, nothing gained.",
				"effect_text": "",
				"callback_id": "nothing",
			},
		],
	},
	# --- Trade time for gold ---
	{
		"title": "Time Merchant",
		"description": "A hooded figure offers a deal:\n\"Your time is money, friend.\"",
		"choices": [
			{
				"label": "Sell 1:00",
				"description": "Lose 1:00 of act time, gain 60 gold.",
				"effect_text": "",
				"callback_id": "sell_time_60",
			},
			{
				"label": "Sell 2:00",
				"description": "Lose 2:00 of act time, gain 130 gold.",
				"effect_text": "",
				"callback_id": "sell_time_120",
			},
			{
				"label": "Decline",
				"description": "Keep your time.",
				"effect_text": "",
				"callback_id": "nothing",
			},
		],
	},
	# --- Free small bonus ---
	{
		"title": "Abandoned Supply Cache",
		"description": "You stumble upon crates left behind\nby a retreating army.",
		"choices": [
			{
				"label": "Take the gold",
				"description": "Gain 40 gold.",
				"effect_text": "",
				"callback_id": "cache_gold",
			},
			{
				"label": "Take the supplies",
				"description": "Restore 1:00 of act time.",
				"effect_text": "",
				"callback_id": "cache_time",
			},
		],
	},
	# --- Risk / reward: sacrifice gold for relic ---
	{
		"title": "Wandering Collector",
		"description": "An eccentric traveler shows you a\nglowing artifact. \"100 gold, take it or leave it.\"",
		"choices": [
			{
				"label": "Buy it",
				"description": "Pay 100 gold for a random relic.",
				"effect_text": "",
				"callback_id": "collector_buy",
			},
			{
				"label": "Refuse",
				"description": "Save your gold.",
				"effect_text": "",
				"callback_id": "nothing",
			},
		],
	},
	# --- Upgrade boost ---
	{
		"title": "Training Grounds",
		"description": "An old battlefield, perfect for drills.\nYour troops could sharpen their skills here.",
		"choices": [
			{
				"label": "Speed drills",
				"description": "Gain +1 Speed upgrade level.",
				"effect_text": "",
				"callback_id": "train_speed",
			},
			{
				"label": "Combat drills",
				"description": "Gain +1 Attack upgrade level.",
				"effect_text": "",
				"callback_id": "train_attack",
			},
			{
				"label": "Fortification drills",
				"description": "Gain +1 Defense upgrade level.",
				"effect_text": "",
				"callback_id": "train_defense",
			},
		],
	},
	# --- Sacrifice HP for power ---
	{
		"title": "Blood Altar",
		"description": "A dark altar pulses with forbidden power.\nIt demands a sacrifice of time.",
		"choices": [
			{
				"label": "Offer 1:30",
				"description": "Lose 1:30 of act time. Gain a random relic and 30 gold.",
				"effect_text": "",
				"callback_id": "blood_altar",
			},
			{
				"label": "Leave",
				"description": "This place gives you the creeps.",
				"effect_text": "",
				"callback_id": "nothing",
			},
		],
	},
]

static func get_random_event() -> Dictionary:
	return EVENTS[randi() % EVENTS.size()]
