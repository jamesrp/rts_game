# Node Wars: Roguelike RTS Design Sketch (v3)

## Elevator Pitch

A single-player roguelike where each “combat encounter” is a short real-time strategy battle in the style of Mushroom Wars 2 / Zone Control. Between battles, the player navigates a branching map and collects upgrades that define their army identity — unit types, abilities, and passive bonuses. Think Slay the Spire, but instead of playing cards, you’re commanding units to capture nodes.

The roguelike layer defines *what* your army is. The battle layer is a clean positional strategy game where you play that identity against varied opponents.

-----

## Core Battle Mechanics

Each battle takes place on a 2D map with **nodes** connected by **paths**.

- Nodes generate units over time. Generation rate scales with node level.
- Nodes can be **upgraded** by spending units (increasing generation rate and max capacity), similar to towers/forges in Mushroom Wars. Upgrade decisions are simple (spend units to level up) — there are no branching building types in battle.
- The player selects one or more owned nodes and sends a percentage of their units to a target node along the connecting path.
- If units arrive at an enemy or neutral node, they reduce its garrison. If the garrison hits zero, the node is captured.
- A battle is won when all enemy nodes are captured or the enemy’s base node is destroyed.

### The Home Base

Each side has a **home base node** positioned at the rear of their territory. The home base is special:

- It functions like a normal node for generation and garrisoning.
- When enemy units attack the home base, damage is dealt to the player’s **run HP pool** rather than simply attriting the garrison. (Mechanically: the garrison still fights back and can repel attackers, but every hit that lands also chips away at your persistent HP.)
- The enemy AI also has a home base. Destroying the enemy base is the primary win condition.

**Why this works:** It unifies the battle layer and the run layer. Your HP isn’t an abstract post-battle calculation — it’s a physical thing on the map you’re defending. This creates natural tension: do you leave units garrisoned at home for protection, or send everything forward and risk run damage? Sloppy play bleeds you out over the course of a run, but the damage feels *fair* because you can see it happening and react.

**Map positioning:** The home base should always sit behind other friendly nodes, so the enemy must push through your territory to reach it. Harder battles can place the home base in more exposed positions. The AI pathfinds toward your base like any other node, but has to fight through your front line first.

**Defeat condition:** If the enemy achieves full map dominance, they will inevitably reach and destroy your base. There’s no need for a separate “you lose” trigger — loss of map control naturally translates to run HP damage and eventual death.

### Battle Pacing

Battles do **not** have a hard time limit or stalemate mechanic. They end when one side’s base is destroyed.

Pacing is controlled entirely by **opponent design**. Some AI opponents naturally punish slow play:

- Scaling opponents ramp up generation over time, so delay is death.
- Wave opponents periodically launch coordinated assaults that grow in size.
- Static opponents are positional puzzles you can take your time solving.

This mirrors how Slay the Spire handles pacing — some enemies (Cultist) scale and demand urgency, while others (Louses) are flat and let you play at your own speed. The variety comes from the encounter roster, not from a universal rule.

**Stalemate prevention through design:** Rather than a safety valve mechanic, stalemates are prevented at the design level. Maps should be tuned so that full territorial control by either side is always achievable — if the economy and AI aggression are balanced correctly, games should naturally resolve. If playtesting reveals persistent stalemate scenarios, the fix is in the map layout and AI tuning, not in an artificial timer.

-----

## The Run Structure

A run consists of ~12–15 battles across 3 acts, with a boss battle at the end of each act.

### Branching Map (Slay the Spire style)

Each act presents a branching path of ~4–5 encounters. Node types on the meta-map:

- **Battle**: standard encounter against an AI opponent.
- **Elite**: harder battle with better rewards.
- **Campfire**: heal run HP, or forgo healing to acquire a unit upgrade (see Campfire Choices below).
- **Event (?)**: random event — risk/reward choices, shops, special challenges, or unit type unlocks.
- **Boss**: mandatory battle at end of each act. Boss has a signature AI behavior and unique map layout.

### Health / Run Continuity

The player has an **HP pool** that persists across the entire run.

- Each battle starts fresh in terms of units — you don’t carry units between battles. Your starting node layout is determined by the battle map.
- **Run HP damage comes from your home base being attacked during battles.** Play well and protect your base, and you take zero damage. Let enemies slip through, and you bleed.
- HP can be restored at campfire nodes and through certain modifiers/events.
- The run ends when HP hits zero or after defeating the Act 3 boss.

**Design goal:** Each battle is self-contained and fair, but sloppy play accumulates as attrition. The home base makes this feel tangible — you can *see* when you’re taking run damage and *choose* how to respond.

-----

## Army Identity: The Roguelike Progression System

This is the “deck-building” equivalent. Instead of collecting cards, the player builds an **army identity** across the run — choosing unit types, unlocking abilities, and stacking passive modifiers. All army composition decisions happen *between* battles at campfires, events, and reward screens. In battle, the player focuses purely on positional strategy.

### Unit Types

The player starts each run with a **basic unit type** (balanced stats). Over the course of the run, they can unlock additional unit types that change how their army plays:

- **Swarmlings**: fast, fragile, high generation rate. Rewards aggressive expansion and overwhelming numbers.
- **Heavies**: slow, tanky, low generation rate. Rewards turtling and holding key positions.
- **Scouts**: very fast movement, low combat power. Rewards backdoor attacks and map control.
- **Sappers**: moderate stats, but deal bonus damage to node garrisons. Rewards targeted strikes on fortified positions.

### Unit Slotting System

When the player unlocks a new unit type, it enters their **unit pool**. Before each battle (or between battles on the meta-map), the player chooses which unit types to **slot** from their pool.

- **Single type slotted**: all nodes produce that unit type exclusively. Clean identity, full commitment.
- **Two types slotted**: nodes produce a 50/50 mix. Balanced composition with hybrid strengths and weaknesses.
- **Three types slotted**: nodes produce a 33/33/33 mix. Versatile but diluted — no single type dominates.

The player can re-slot freely between battles. This is a strategic pre-battle decision: do you go all-in on Heavies for a Fortress boss, or slot Heavies + Scouts for a mix of durability and flanking? Committing to fewer types gives a stronger identity; spreading across more gives flexibility.

**Why per-battle slotting, not per-node assignment:** Assigning unit types to individual nodes during battle would add real-time management overhead that cuts against the game’s “clean positional strategy” goal. The slot system keeps army composition as a roguelike-layer decision (between battles) while still giving the player meaningful control. It also preserves visual readability — you know going in what your army looks like.

**Visual distinction:** Each unit type needs a clearly distinct silhouette/color so the player can read mixed armies at a glance. In a 50/50 mix, you should be able to see the Heavies and Scouts flowing along a path as visually distinct groups.

Unit types are unlocked through:

- **Event (?) rooms**: “A wandering battalion offers to join your cause. Accept the Heavies into your army?”
- **Elite battle rewards**: defeating an elite encounter can offer a new unit type as a reward option.
- **Boss relics**: some boss rewards might grant a unique unit variant.

### Unit Upgrades (Campfire Choices)

At campfire nodes, the player chooses between:

- **Rest**: heal a portion of run HP.
- **Train**: acquire a unit upgrade that changes how your units behave.

Unit upgrades should **change how you play**, not just inflate numbers. Examples:

- **Cloaked Arrival**: your units are briefly invisible when they arrive at a node, allowing surprise attacks.
- **Siege Protocol**: your units deal double damage to nodes above level 3, but move 15% slower.
- **Leech**: your units heal your home base slightly for every enemy unit killed.
- **Volatile**: your units explode on death, damaging nearby enemy units at the same node.
- **Entrenching**: units that garrison a node for 10+ seconds gain a defensive bonus.
- **Flanking Instinct**: units that attack a node already under assault from another direction deal bonus damage.

These map to Starcraft-style upgrades conceptually (Stim, Blue Flame, Concussive Shells) — they give your army a distinct tactical personality that synergizes with your unit type slots and passive modifiers.

**Note:** Unit upgrades apply to **all** unit types. This keeps the system simple and avoids the combinatorial explosion of type-specific upgrades. The interesting interplay comes from how upgrades interact with the types you’ve slotted — “Volatile” is devastating on Swarmlings (many cheap units dying = many explosions) but marginal on Heavies (few deaths). The player discovers these synergies through the slotting decision.

### Passive Modifiers (≈ Relics)

Acquired after battles and from events. These are persistent bonuses for the rest of the run.

**Stat modifiers** (necessary but less interesting on their own):

- Your nodes generate units 15% faster.
- Units move 20% faster.
- Nodes have +25% max capacity.

**Mechanical modifiers** (these are the interesting ones — they change *how you play*):

- Newly captured nodes instantly produce a burst of 5 units.
- You start each battle with +1 extra node.
- Enemy units that pass through a path adjacent to your node take attrition damage.
- Your home base generates units at 2x rate when below 50% run HP.
- Nodes you own slowly drain adjacent enemy nodes (1 unit per 5 seconds).
- When you capture a node, its level is preserved instead of resetting to 1.

**Design principle:** Mechanical modifiers should reward or enable specific playstyles. “Adjacent node drain” is a turtle enabler. “Burst on capture” is a rush enabler. The player should feel like they’re building toward something.

### Activated Abilities (≈ Potions / Powers)

Limited-use or cooldown-gated abilities usable during battle. Acquired from elite rewards, events, and boss relics.

- **Airstrike**: destroy 50% of units at a target node. Once per battle.
- **Fortify**: selected node becomes invulnerable for 10 seconds.
- **Rally**: all your nodes instantly send reinforcements to a target node.
- **Sabotage**: enemy node stops generating units for 15 seconds.
- **Recall**: all units currently in transit return to their origin nodes.
- **Overdrive**: selected node generates at 3x rate for 15 seconds, then is disabled for 10 seconds.

### Curses / Trade-offs

Acquired through events or as the cost of powerful rewards:

- Your nodes generate faster, but have 50% max capacity.
- You start with an extra node, but one random node begins neutral instead of friendly.
- Your units move faster, but your home base has reduced HP.

### Reward Structure

- **After normal battles**: pick 1 of 3 random passive modifiers.
- **After elite battles**: pick 1 of 3 rare/powerful modifiers + gain an activated ability (or unit type unlock).
- **After bosses**: choose a powerful “boss relic” unique to that boss.
- **Campfires**: heal HP or train a unit upgrade.
- **Events**: offer situational choices — e.g., “sacrifice 20% HP to gain a strong modifier,” “gamble: 50% chance of a great modifier, 50% chance of a curse,” or unlock a new unit type.

### Build Archetypes (Emergent, Not Prescribed)

Modifiers, unit types, and upgrades should be designed so certain combinations are notably powerful:

- **Blitz build**: Swarmlings (slotted solo) + speed modifiers + burst-on-capture + Airstrike. Overwhelm the map before the enemy can respond.
- **Fortress build**: Heavies (slotted solo) + capacity bonuses + Entrenching + Fortify + adjacent drain. Lock down territory and grind the enemy out.
- **Assassin build**: Scouts (slotted solo) + Cloaked Arrival + Sabotage + home-base-targeting modifiers. Ignore the front line, slip through, and kill the enemy base.
- **Hybrid build**: Heavies + Scouts (slotted together) + Flanking Instinct. Heavies hold the line while Scouts flank. The 50/50 mix means you’re not dominant at either role, but the combination covers more situations.
- **Ability build**: multiple activated abilities + cooldown reduction modifiers. Win through constant active interventions rather than raw unit strength.

-----

## AI Opponents

The game uses a roster of AI “personalities” with distinct behaviors and **distinct visual identities**. The player can read what kind of opponent they’re facing from the meta-map and from the first moments of battle, similar to how Slay the Spire shows enemy types before combat.

### Visual Identity

Each AI personality has a unique **sprite set and node aesthetic** so the player immediately knows what they’re facing:

- The Swarm might use insectoid hive nodes and tiny fast-moving units.
- The Fortress might use stone towers and slow, heavy units.
- The Expansionist might use vine-like spreading nodes.

This is low-cost (palette swaps and minor sprite variations) but high-value for readability.

### Base AI Behaviors

- **Rusher**: attacks early and often, even with small numbers. Dangerous if you’re slow to expand, but overextends. *Scaling: generation rate increases over time, punishing slow play.*
- **Turtler**: upgrades nodes and builds up before attacking. Weak to early aggression, but overwhelming if left alone. *Static: no scaling, but a wall if you don’t crack it early.*
- **Expansionist**: prioritizes capturing neutral nodes quickly. Spreads thin but controls the map. *Semi-scaling: more nodes = more total generation, so delay lets it snowball.*
- **Opportunist**: attacks your weakest node. Punishes poor defense. *Adaptive: reads your board state and strikes gaps.*

### Boss AI Concepts

- **Act 1 Boss — The Swarm**: extremely fast unit generation, but nodes have low max capacity. Constantly sends small waves from every direction. Test of multitasking and home base defense.
- **Act 2 Boss — The Fortress**: starts with heavily upgraded nodes. Barely attacks but is very hard to crack. Test of efficiency and targeted strikes. Your home base is relatively safe, but the clock is the Fortress’s slow, inevitable expansion.
- **Act 3 Boss — The Warlord**: a deterministic, multi-phase encounter designed as a final exam of the player’s run build. The Warlord combines the threats of earlier bosses into a single escalating fight:
  - **Phase 1 — Expansion**: the Warlord starts with more nodes than any previous opponent and aggressively captures remaining neutral territory. Tests the player’s ability to contest map control under pressure.
  - **Phase 2 — Siege**: once the Warlord controls a critical mass of nodes, it begins upgrading them and launching coordinated waves at the player’s territory. Generation rates increase. Tests defensive play and resource management.
  - **Phase 3 — Assault**: the Warlord commits everything toward the player’s home base. All nodes send units in a sustained push. The player must either have built enough of a positional advantage to weather the storm, or must break through and destroy the Warlord’s base before their own falls.
  
  The Warlord’s map is the largest and most complex in the game, with multiple viable attack routes. Its phases are deterministic (triggered by node control thresholds and time elapsed), so the player can learn the fight and plan around it. The difficulty comes from the combination of threats, not from the AI reading the player’s strategy.

-----

## Visual / Thematic Notes

Theme is TBD but should be abstract enough to work with simple art:

- Nodes as circles/hexagons with unit counts displayed.
- Units as small dots/sprites flowing along paths.
- Color-coded factions (player = blue, enemy = red, neutral = gray), with AI personality indicated by node/unit sprite style.
- The meta-map is a node graph, visually similar to Slay the Spire’s map.
- Clean, readable UI is more important than visual flair. Prototype with geometric shapes.
- Home base node should be visually distinct (larger, glowing, or marked) so the player always knows where it is and can assess its safety at a glance.
- **Unit type readability**: each unit type needs a distinct silhouette and/or color that remains readable at small sizes and in mixed groups. When Heavies and Scouts flow along the same path, the player should be able to tell them apart at a glance.

-----

## Open Design Questions

- **Slot UI and timing**: should slotting happen on the meta-map (before you see the battle map) or on a pre-battle screen (after you see the map and opponent type)? Slotting blind rewards general-purpose builds; slotting with info rewards counter-picking. The latter is more strategic but reduces the cost of spreading across many unit types. Prototype both and see which feels better.
- **How many modifiers / unit types / upgrades for launch?** Target minimums for interesting runs: ~25 passive modifiers, ~8 activated abilities, ~10 events, ~4-5 unit types, ~12-15 unit upgrades. Enough that you don’t see everything every run.
- **Difficulty scaling within a run**: acts need to get harder. Levers include: more enemy starting nodes, faster AI generation, tighter map layouts (more exposed home base), AI personalities with scaling mechanics, and higher-level starting nodes for the enemy. Needs iteration and playtesting.
- **Multiple playable “characters”?** Different starting unit types / modifier pools / home base abilities. High-value for replayability but doubles design work. Defer to post-prototype.
- **Home base HP tuning**: how much run HP does a hit to the base cost? Should it scale with act/difficulty? Should different enemy unit types deal different amounts of base damage? Needs extensive playtesting.
- **Multiplayer someday**: the battle system is inherently PvP-friendly (both players have a home base to protect). A future mode could use the same battle maps for 1v1. Keep the architecture clean enough that this is possible but don’t design around it now.
