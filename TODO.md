# Roguelike Mode — Implementation Plan

## Overview

Add a 3rd game mode "Roguelike" to the level select screen. The player navigates a branching meta-map (Slay the Spire style), fighting RTS battles at each node, with persistent HP and army upgrades across a run.

This is broken into 8 phases. Each phase produces a playable increment.

---

## Phase 1: Run Shell & Meta-Map

**Goal:** A new "Roguelike" button on the level select launches a run. The player sees a branching node map for Act 1 and can click nodes to advance. Clicking a Battle node starts a battle (reusing existing AI battle logic). Winning returns to the meta-map with the node marked complete. No rewards yet — just the navigation loop.

**Tasks:**
- [x] Add `game_state = "roguelike_map"` state and a new "ROGUELIKE" column/button on the level select screen
- [x] Add run state variables: `run_hp`, `run_max_hp`, `run_act` (1–3), `run_map` (array of node rows), `run_current_row`, `run_current_node`, `run_modifiers`, `run_unit_types`
- [x] Implement `_generate_run_map(act)` — creates a branching graph of ~5 rows with 2–4 nodes each. Node types for now: "battle" and "boss" (last row). Edges connect each node to 1–2 nodes in the next row. Store as array of rows, each row an array of `{type, edges, completed, position}`.
- [x] Draw the meta-map: dark background, nodes as icons (circle for battle, skull for boss), edges as lines, current row highlighted, completed nodes dimmed
- [x] Handle click on available node → if "battle", call `_start_level("ai", 1)` (hardcoded for now) with `game_state = "playing"` and a flag `in_roguelike_run = true`
- [x] On battle win: return to meta-map (`game_state = "roguelike_map"`), mark node complete, advance `run_current_row`
- [x] On battle loss: deduct run HP instead of instant game-over (lose ~25 HP per loss). If run HP ≤ 0, end the run with a "Run Over" screen
- [x] On reaching the boss row and completing it, show "Act Complete" and either advance act or show "Run Won" for Act 3

**Estimated scope:** ~200 lines of new code (map gen, map drawing, state transitions).

---

## Phase 2: Home Base & Run HP Integration

**Goal:** Each battle map has a designated Home Base node for each side. Enemy units that damage the home base also reduce run HP. The run HP bar is visible during battles.

**Tasks:**
- [x] Add `home_base_id` field to battle config — the player's rearmost building becomes the home base
- [x] Visually distinguish the home base (larger, glowing outline, or a shield icon)
- [x] When enemy units arrive at the home base and deal damage, also subtract from `run_hp` (proportional to units lost)
- [x] Draw a persistent run HP bar at the top of the screen during roguelike battles
- [x] Battle loss condition changes: losing the home base specifically = battle lost (not losing all buildings)
- [x] Generate battle maps that position the home base behind other friendly nodes

**Estimated scope:** ~80 lines.

---

## Phase 3: Varied Battle Maps & AI Scaling

**Goal:** Different battles use different map layouts and AI difficulties that scale with act/row progression.

**Tasks:**
- [ ] Create a pool of 6–8 procedural battle map templates (different node counts, layouts, connectivity)
- [ ] AI difficulty scales: Act 1 uses level 1–2 AI, Act 2 uses level 2–3, Act 3 uses level 3–4
- [ ] Elite nodes get harder maps (more enemy starting nodes, pre-upgraded buildings)
- [ ] Add "elite" node type to meta-map generation (1–2 per act, marked with a star)

**Estimated scope:** ~150 lines.

---

## Phase 4: Reward Screens & Passive Modifiers

**Goal:** After winning a battle, the player picks 1 of 3 passive modifiers. Modifiers persist for the rest of the run and affect battles.

**Tasks:**
- [ ] Add `game_state = "roguelike_reward"` screen showing 3 random modifier cards
- [ ] Implement ~10 passive modifiers to start:
  - +15% unit generation rate
  - +20% unit move speed
  - +25% node max capacity
  - Newly captured nodes burst 5 units
  - Start battles with +1 extra friendly node
  - Home base generates 2x when below 50% run HP
  - Nodes slowly drain adjacent enemy nodes
  - +10% attack power
  - +15% defense power
  - Units move 10% faster on capture
- [ ] Apply active modifiers in battle logic (generation, movement, combat formulas)
- [ ] Show collected modifiers as icons on the meta-map screen
- [ ] Elite rewards: pick from rarer/stronger modifiers + gain an activated ability

**Estimated scope:** ~200 lines.

---

## Phase 5: Campfire & Event Nodes

**Goal:** Add campfire and event (?) nodes to the meta-map. Campfires let you rest (heal) or train (unit upgrade). Events offer risk/reward choices.

**Tasks:**
- [ ] Add "campfire" and "event" node types to map generation (1–2 campfires, 1–2 events per act)
- [ ] Campfire screen: choose "Rest" (heal 30% max HP) or "Train" (pick a unit upgrade)
- [ ] Implement ~6 unit upgrades:
  - Siege Protocol: 2x damage to level 3+ nodes, -15% speed
  - Leech: kills heal home base slightly
  - Volatile: units explode on death, damaging enemy units at same node
  - Entrenching: garrisoned units gain defense over time
  - Cloaked Arrival: brief invisibility on node arrival
  - Flanking Instinct: bonus damage when node attacked from multiple sources
- [ ] Event screen: show a narrative text + 2–3 choices with risk/reward outcomes
- [ ] Implement ~5 events:
  - Wandering battalion: gain a new unit type
  - Sacrifice HP for a strong modifier
  - Gamble: 50/50 great modifier or curse
  - Merchant: trade HP for a specific upgrade
  - Ambush: fight a quick battle with reduced starting units

**Estimated scope:** ~250 lines.

---

## Phase 6: Unit Types & Slotting

**Goal:** Multiple unit types with distinct stats. Player slots 1–3 types before each battle, affecting all node production.

**Tasks:**
- [ ] Define unit types: Basic (default), Swarmlings (fast/fragile/high gen), Heavies (slow/tanky/low gen), Scouts (very fast/weak), Sappers (bonus vs garrisons)
- [ ] Add pre-battle slotting screen (pick which types to use from unlocked pool)
- [ ] Slotted types determine unit stats for all nodes: speed, attack, defense, generation rate
- [ ] Visual distinction: different colored dots for different unit types in mixed groups
- [ ] Unit type unlocks come from events and elite rewards
- [ ] Mixed compositions (2 or 3 types slotted) produce proportional mixes

**Estimated scope:** ~200 lines.

---

## Phase 7: Activated Abilities

**Goal:** Limited-use or cooldown abilities usable during battle, acquired from elites/events.

**Tasks:**
- [ ] Ability system: each ability has a cooldown or per-battle use limit
- [ ] Implement ~4 abilities:
  - Airstrike: destroy 50% units at target node (1/battle)
  - Fortify: node invulnerable 10s (1/battle)
  - Rally: all nodes send reinforcements to target (90s cooldown)
  - Sabotage: enemy node stops generating 15s (60s cooldown)
- [ ] Ability bar UI at bottom of screen during battle
- [ ] Click ability → click target node to activate
- [ ] Abilities acquired from elite battle rewards and boss relics

**Estimated scope:** ~180 lines.

---

## Phase 8: Boss Encounters & Act Progression

**Goal:** Unique boss battles at the end of each act with signature AI behaviors and larger maps.

**Tasks:**
- [ ] Act 1 Boss — The Swarm: fast generation, low capacity, constant small waves
- [ ] Act 2 Boss — The Fortress: pre-upgraded nodes, defensive, slow expansion
- [ ] Act 3 Boss — The Warlord: multi-phase (expand → siege → assault), largest map
- [ ] Boss-specific maps (hand-designed layouts, larger than normal)
- [ ] Boss relics: unique powerful reward after each boss
- [ ] Victory screen after Act 3 boss with run stats

**Estimated scope:** ~250 lines.

---

## Start Here: Phases 1–2

These two phases create the core loop: navigate map → fight battle → take damage / win → continue. Everything else layers on top.

**Total for Phases 1–2:** ~280 lines of new code added to `main.gd`.
