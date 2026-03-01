# Node Wars: Roguelike RTS Design Sketch (v5)

## Elevator Pitch

A single-player roguelike where each "combat encounter" is a short real-time strategy battle in the style of Mushroom Wars 2 / Zone Control. Between battles, the player navigates a branching map and collects upgrades that define their army identity — hero power upgrades, hero powers, and passive bonuses. Think Slay the Spire, but instead of playing cards, you're commanding units to capture nodes.

The roguelike layer defines *what* your army is. The battle layer is a clean positional strategy game where you play that identity against varied opponents.

-----

## Core Battle Mechanics

Each battle takes place on a 2D map with **nodes** connected by **paths**.

- Nodes generate units over time. Generation rate scales with node level.
- Nodes can be **upgraded** by spending units (increasing generation rate and max capacity), similar to towers/forges in Mushroom Wars. Upgrade decisions are simple (spend units to level up) — there are no branching building types in battle.
- The player selects one or more owned nodes and sends a percentage of their units to a target node along the connecting path.
- If units arrive at an enemy or neutral node, they reduce its garrison. If the garrison hits zero, the node is captured.
- A battle is won when all enemy nodes are captured.

### The Run Timer

Each act operates on a **10:00 timer** that resets at the start of each act. The timer ticks down while the player is in battle. It does not tick on the meta-map, at campfires, or during events — only during active combat.

- The timer is always visible as a prominent UI element during battle.
- The act ends in failure if the timer hits 0:00 before the act boss is defeated. The run is over.
- Time can be restored at campfire nodes and through certain modifiers/events.

**Design goal:** The timer creates a fundamentally different tension than an HP pool. Every second spent in a battle costs you, even if you play perfectly. This rewards efficiency — not just winning, but winning *fast*. Turtling and playing safe still bleeds the clock. Even a flawless player is always racing the clock.

**Pacing implications:** The timer naturally solves stalemate problems. Players can't afford to sit in a deadlocked battle because the clock is always ticking. It also creates interesting risk/reward decisions: do you mop up every enemy node for a clean win, or capture the last holdouts ASAP and move on to save time?

**Per-act reset:** Resetting to 10:00 each act keeps the pressure consistent and prevents early mistakes from making later acts unwinnable. It also makes each act feel like a self-contained challenge — the player knows exactly how much time they have to work with, and can plan their path through the branching map accordingly.

### Battle Pacing

Battles do **not** have a hard per-battle time limit. They end when all enemy nodes are captured. However, the run timer creates organic urgency — every second in battle is a second off the act's clock.

Pacing is further controlled by **opponent design**. Some AI opponents naturally punish slow play:

- Scaling opponents ramp up generation over time, so delay is death.
- Wave opponents periodically launch coordinated assaults that grow in size.
- Static opponents are positional puzzles you can solve quickly if you read them right.

This mirrors how Slay the Spire handles pacing — some enemies (Cultist) scale and demand urgency, while others (Louses) are flat and let you play at your own speed. The variety comes from the encounter roster, not from a universal rule. The run timer adds a baseline urgency to every encounter.

-----

## The Run Structure

A run consists of ~12–15 battles across 3 acts, with a boss battle at the end of each act.

### Branching Map (Slay the Spire style)

Each act presents a branching path of ~4–5 encounters. Node types on the meta-map:

- **Battle**: standard encounter against an AI opponent.
- **Elite**: harder battle with better rewards.
- **Campfire**: restore run time, or forgo restoration to acquire a hero power upgrade (see Campfire Choices below).
- **Event (?)**: random event — risk/reward choices, shops, special challenges.
- **Boss**: mandatory battle at end of each act. Boss has a signature AI behavior and unique map layout.

### Run Timer / Run Continuity

Each act starts with a fresh **10:00 timer**.

- Each battle starts fresh in terms of units — you don't carry units between battles. Your starting node layout is determined by the battle map.
- **Time drains while in combat.** Play efficiently to minimize time spent per battle.
- Time can be restored at campfire nodes and through certain modifiers/events.
- If the timer hits zero, the run is over. The run also ends after defeating the Act 3 boss.

**Design goal:** Each battle is self-contained and fair, but slow play accumulates as attrition within each act. The per-act reset keeps the pressure consistent — you always know you have (at most) 10:00 to clear the act, and can plan your meta-map path accordingly. The always-ticking clock rewards offensive efficiency: winning fast is just as important as winning clean.

-----

## Heroes

At the start of each run, the player selects a **hero**. The hero defines the player's top-bar powers — a set of powerful abilities that charge during battle and provide strategic tools beyond pure unit control.

### Hero Power System

Each hero has **4 hero powers**, inspired by StarCraft co-op commander top-bar abilities. These are battle-layer abilities with real-time impact.

- Hero powers charge via an **energy system**. Energy accumulates passively during battle (slow trickle) and is gained in bursts from combat actions: capturing nodes, destroying enemy units, and upgrading nodes.
- Each power has an **energy cost** to activate. Cheaper powers are available frequently; expensive powers are tide-turners used once or twice per battle.
- All 4 hero powers are **unlocked from the start of the run**. The player has their full toolkit from battle one.
- Hero powers **scale through relics and upgrades** acquired during the run. A power's base stats (duration, percentage, radius, etc.) can be enhanced by specific modifiers. This means the same hero plays differently depending on what you pick up — an early "Rally Cry sends 50% instead of 30%" relic fundamentally changes how aggressively you can play the Commander.

### Hero Roster

#### The Commander
A frontline leader who inspires and rallies troops. Rewards aggressive, push-oriented play.

1. **Rally Cry** *(low cost)*: All owned nodes instantly send 30% of their garrison to a target node. Enables sudden, coordinated pushes.
2. **Forced March** *(low cost)*: All units currently in transit move at 2x speed for 8 seconds. Closes gaps and enables surprise attacks.
3. **Conscription** *(medium cost)*: All owned nodes instantly generate a burst of bonus units (scaling with node level). A shot of reinforcements when you need mass.
4. **Blitz** *(high cost)*: For 12 seconds, your units deal double damage when attacking enemy nodes, and captured nodes immediately begin producing at full rate. A game-ending offensive push.

#### The Warden
A defensive specialist who fortifies positions and punishes attackers. Rewards positional play and turtling.

1. **Fortify** *(low cost)*: Target node becomes invulnerable for 8 seconds. Saves a key position under assault.
2. **Entrench** *(low cost)*: All units at a target node gain a 50% defensive bonus for 15 seconds. Turns a node into a wall.
3. **Minefield** *(medium cost)*: Place a trap on a path. The next enemy group that travels along it loses 40% of its units. Area denial and ambush tool.
4. **Citadel** *(high cost)*: Target node is massively upgraded — max capacity doubles and generation triples for 20 seconds. Creates an impregnable fortress that floods the area with units.

#### The Saboteur
A disruptive specialist who weakens and confuses the enemy. Rewards opportunistic, hit-and-run play.

1. **Sabotage** *(low cost)*: Target enemy node stops generating units for 12 seconds. Disrupts enemy economy.
2. **Blackout** *(low cost)*: Enemy units in transit on a target path are slowed by 50% for 10 seconds. Buys time and disrupts timing attacks.
3. **Turncoat** *(medium cost)*: Convert 30% of units at a target enemy node to your side. They immediately begin fighting the remaining garrison. Chaos behind enemy lines.
4. **EMP** *(high cost)*: All enemy nodes stop generating for 10 seconds, and all enemy units in transit are frozen in place. A massive window of opportunity.

#### The Architect
An economy-focused hero who builds infrastructure advantages. Rewards efficient expansion and node development.

1. **Overclock** *(low cost)*: Target node generates at 3x rate for 12 seconds. Flood a key node with units.
2. **Supply Line** *(low cost)*: Select two owned nodes — they share garrisons for 15 seconds (units teleport freely between them). Enables flexible defense and rapid repositioning.
3. **Terraform** *(medium cost)*: Instantly upgrade a target owned node by 2 levels (bypassing the unit cost). Rapid infrastructure development.
4. **Nexus** *(high cost)*: For 15 seconds, all your nodes generate units as if they were the level of your highest-level node. Turns your entire network into a powerhouse.

### Hero Power Scaling

Hero powers start at base effectiveness and grow stronger through relics and upgrades found during the run. This is the primary way the hero "levels up" — not by unlocking new tools, but by making existing tools more powerful.

**Hero-specific relics** (examples):

- *Commander — Warchief's Banner*: Rally Cry sends 50% of garrison instead of 30%.
- *Commander — Shock Doctrine*: Blitz duration increased to 18 seconds.
- *Warden — Reinforced Walls*: Fortify duration increased to 14 seconds and grants a burst of 5 units when it expires.
- *Warden — Concertina Wire*: Minefield now also slows survivors by 50% for 8 seconds.
- *Saboteur — Deep Cover*: Sabotage duration increased to 20 seconds and also halves the node's garrison.
- *Saboteur — Double Agent*: Turncoat converts 50% instead of 30%.
- *Architect — Rapid Expansion*: Terraform now upgrades by 3 levels instead of 2.
- *Architect — Grid Link*: Supply Line duration increased to 25 seconds and connects up to 3 nodes.

**Universal power relics** (work for any hero):

- *Capacitor*: Energy generation increased by 25%.
- *Efficiency Core*: All hero power costs reduced by 20%.
- *Surge Converter*: Capturing a node instantly grants bonus energy equal to the node's level.
- *Feedback Loop*: Using a hero power grants 10% of its cost back as energy over 5 seconds.

**Design goal:** The player's hero feels meaningfully stronger by Act 3 compared to Act 1, even though all powers were available from the start. The progression comes from *how good* the powers are, not *which* powers you have. Finding a key hero relic can redefine your strategy mid-run.

-----

## Army Identity: The Roguelike Progression System

This is the "deck-building" equivalent. Instead of collecting cards, the player builds an **army identity** across the run — choosing hero power upgrades, collecting hero power relics, and stacking passive modifiers. All army composition decisions happen *between* battles at campfires, events, and reward screens. In battle, the player focuses purely on positional strategy and hero power usage.

### Units

The player commands a single unit type throughout the run — balanced, general-purpose soldiers. What makes them *your* army is the upgrades, modifiers, and hero powers layered on top.

**Why one unit type:** A single unit type keeps the battle layer clean and readable. The strategic depth comes from upgrades and hero powers that change *how* your units behave, not from managing multiple unit types in real time. This lets the player focus on positional decision-making — where to send, when to push, when to hold — without real-time army composition management.

### Hero Power Upgrades (Campfire Choices)

At campfire nodes, the player chooses between:

- **Rest**: restore a portion of run time.
- **Train**: acquire a hero power upgrade that enhances one of your hero's abilities.

Hero power upgrades should **change how you use your powers**, not just inflate numbers. They modify a specific hero power's behavior, adding new effects or altering how the ability works. Each upgrade is hero-specific — you only see upgrades for your current hero.

Examples per hero:

**Commander:**
- **Rolling Thunder**: Rally Cry sends units in two waves — 30% immediately, then 20% more after 3 seconds.
- **Double Time**: Forced March also increases unit combat power by 25% while active.
- **War Economy**: Conscription generates more units at higher-level nodes (scaling bonus).
- **Scorched Earth**: During Blitz, capturing an enemy node damages adjacent enemy nodes' garrisons.

**Warden:**
- **Reactive Armor**: Fortify reflects 20% of incoming damage back to attackers.
- **Bunker Down**: Entrench also increases the node's generation rate by 50% while active.
- **Chain Mines**: Minefield splits into two smaller traps on adjacent paths when triggered.
- **Iron Curtain**: Citadel's bonus also spreads to adjacent owned nodes at half effectiveness.

**Saboteur:**
- **Rolling Blackout**: Sabotage spreads to one adjacent enemy node at half duration.
- **Quicksand**: Blackout-slowed units also deal 25% less damage on arrival.
- **Sleeper Cell**: Turncoat-converted units continue to convert 1 additional unit every 3 seconds for 10 seconds.
- **Total Shutdown**: EMP also prevents enemy hero power usage for its duration.

**Architect:**
- **Overdrive**: Overclock's bonus generation also applies to adjacent owned nodes at half rate.
- **Wormhole**: Supply Line-connected nodes can share units with any other owned node, not just each other.
- **Deep Foundations**: Terraform'd nodes retain 1 bonus level permanently after the upgrade.
- **Power Grid**: During Nexus, all nodes also share 10% of their garrison with their lowest-garrisoned neighbor every 3 seconds.

These upgrades create meaningful build decisions at campfires — do you double down on your most-used power, or shore up a weaker one? They synergize with hero power relics, creating layered power scaling across the run.

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
- Your starting nodes begin at level 2 when the act timer is below 5:00.
- Nodes you own slowly drain adjacent enemy nodes (1 unit per 5 seconds).
- When you capture a node, its level is preserved instead of resetting to 1.
- Energy generation is increased by 20%. *(Hero power synergy.)*
- Your first hero power activation each battle costs no energy.

**Design principle:** Mechanical modifiers should reward or enable specific playstyles. "Adjacent node drain" is a turtle enabler. "Burst on capture" is a rush enabler. Energy modifiers let you lean into hero power-centric builds. The player should feel like they're building toward something.

### Activated Abilities (≈ Potions / Powers)

Limited-use abilities usable during battle (once per battle). Acquired from elite rewards, events, and boss relics. These are separate from hero powers — smaller, tactical tools.

- **Airstrike**: destroy 50% of units at a target node. Once per battle.
- **Recall**: all units currently in transit return to their origin nodes.
- **Time Warp**: the run timer pauses for 15 seconds. *(Extremely valuable.)*
- **Scout Pulse**: reveal all enemy unit counts and movements for 20 seconds.
- **Overcharge**: target node instantly gains +50% of its max capacity in bonus units.

### Curses / Trade-offs

Acquired through events or as the cost of powerful rewards:

- Your nodes generate faster, but have 50% max capacity.
- You start with an extra node, but one random node begins neutral instead of friendly.
- Your units move faster, but enemy nodes take 20% more units to capture.

### Reward Structure

- **After normal battles**: pick 1 of 3 random passive modifiers.
- **After elite battles**: pick 1 of 3 rare/powerful modifiers + gain an activated ability (or a hero-specific power relic).
- **After bosses**: choose a powerful "boss relic" unique to that boss (may include hero power relics).
- **Campfires**: restore run time or train a hero power upgrade.
- **Events**: offer situational choices — e.g., "sacrifice 1:00 of act time to gain a strong modifier," "gamble: 50% chance of a great modifier, 50% chance of a curse."

### Build Archetypes (Emergent, Not Prescribed)

Modifiers, hero powers, and upgrades should be designed so certain combinations are notably powerful:

- **Blitz build**: Commander hero + speed modifiers + burst-on-capture + Scorched Earth upgrade. Rally everything forward, cap fast, end fights in seconds.
- **Fortress build**: Warden hero + capacity bonuses + Iron Curtain upgrade + adjacent drain. Lock down territory, let Citadel and Minefield do the heavy lifting.
- **Sabotage build**: Saboteur hero + Sleeper Cell upgrade + energy generation bonuses. Constantly disrupt the enemy while converted units spread chaos behind enemy lines.
- **Engine build**: Architect hero + node level preservation + Deep Foundations upgrade + generation bonuses. Build an overwhelming economic machine that floods the map.
- **Power build**: any hero + energy generation modifiers + "first power free" relic + hero power upgrades. Win through constant hero power activations rather than raw unit strength.

-----

## AI Opponents

The game uses a roster of AI "personalities" with distinct behaviors and **distinct visual identities**. The player can read what kind of opponent they're facing from the meta-map and from the first moments of battle, similar to how Slay the Spire shows enemy types before combat.

### Visual Identity

Each AI personality has a unique **sprite set and node aesthetic** so the player immediately knows what they're facing:

- The Swarm might use insectoid hive nodes and tiny fast-moving units.
- The Fortress might use stone towers and slow, heavy units.
- The Expansionist might use vine-like spreading nodes.

This is low-cost (palette swaps and minor sprite variations) but high-value for readability.

### Base AI Behaviors

- **Rusher**: attacks early and often, even with small numbers. Dangerous if you're slow to expand, but overextends. *Scaling: generation rate increases over time, punishing slow play.*
- **Turtler**: upgrades nodes and builds up before attacking. Weak to early aggression, but overwhelming if left alone. *Static: no scaling, but a wall if you don't crack it early.*
- **Expansionist**: prioritizes capturing neutral nodes quickly. Spreads thin but controls the map. *Semi-scaling: more nodes = more total generation, so delay lets it snowball.*
- **Opportunist**: attacks your weakest node. Punishes poor defense. *Adaptive: reads your board state and strikes gaps.*

### Boss AI Concepts

- **Act 1 Boss — The Swarm**: extremely fast unit generation, but nodes have low max capacity. Constantly sends small waves from every direction. Test of multitasking and territorial defense. *(The constant pressure eats clock time, making efficiency critical.)*
- **Act 2 Boss — The Fortress**: starts with heavily upgraded nodes. Barely attacks but is very hard to crack. Test of efficiency and targeted strikes. The clock is the real enemy — every second spent chipping at their defenses is a second off your act timer.
- **Act 3 Boss — The Warlord**: a deterministic, multi-phase encounter designed as a final exam of the player's run build. The Warlord combines the threats of earlier bosses into a single escalating fight:
  - **Phase 1 — Expansion**: the Warlord starts with more nodes than any previous opponent and aggressively captures remaining neutral territory. Tests the player's ability to contest map control under pressure.
  - **Phase 2 — Siege**: once the Warlord controls a critical mass of nodes, it begins upgrading them and launching coordinated waves at the player's territory. Generation rates increase. Tests defensive play and resource management.
  - **Phase 3 — Assault**: the Warlord commits everything toward recapturing lost territory. All nodes send units in a sustained push. The player must either have built enough of a positional advantage to weather the storm, or must break through and capture the Warlord's remaining nodes before being overwhelmed.
  
  The Warlord's map is the largest and most complex in the game, with multiple viable attack routes. Its phases are deterministic (triggered by node control thresholds and time elapsed), so the player can learn the fight and plan around it. The difficulty comes from the combination of threats, not from the AI reading the player's strategy.

-----

## Visual / Thematic Notes

Theme is TBD but should be abstract enough to work with simple art:

- Nodes as circles/hexagons with unit counts displayed.
- Units as small dots/sprites flowing along paths.
- Color-coded factions (player = blue, enemy = red, neutral = gray), with AI personality indicated by node/unit sprite style.
- The meta-map is a node graph, visually similar to Slay the Spire's map.
- Clean, readable UI is more important than visual flair. Prototype with geometric shapes.
- **Run timer**: prominently displayed, always visible. Should pulse or change color as it gets low (below 3:00 = yellow, below 1:00 = red).
- **Hero power bar**: displayed alongside the timer. Energy meter fills visibly. Power icons should be large and clear with hotkey labels. Cooldown/cost should be instantly readable.

-----

## Open Design Questions

- **Timer tuning**: 10:00 per act is a starting point. Should time restoration at campfires be a fixed amount or percentage? Does the timer feel too punishing or too generous? How much time should each act's encounters consume on average to leave room for elites and campfires? Needs extensive playtesting.
- **Energy economy tuning**: how fast does energy generate passively vs. from combat actions? If energy is too plentiful, hero powers lose their weight. If too scarce, they feel irrelevant. Each hero may need different tuning.
- **Hero balance**: heroes need to feel different without one being strictly dominant. The Commander's offense vs. the Warden's defense should be a genuine playstyle choice, not a power ranking.
- **Hero power relic density**: how often should hero-specific relics appear? Too rare and power scaling feels flat. Too common and the player is swimming in upgrades. Should hero relics compete with general relics in reward pools, or be offered separately?
- **How many modifiers / upgrades / abilities for launch?** Target minimums for interesting runs: ~25 passive modifiers, ~5 activated abilities, ~10 events, ~4 hero power upgrades per hero per power (16 per hero), ~8-12 hero power relics per hero, 4 heroes. Enough that you don't see everything every run.
- **Difficulty scaling within a run**: acts need to get harder. Levers include: more enemy starting nodes, faster AI generation, tighter map layouts, AI personalities with scaling mechanics, higher-level starting nodes for the enemy, and reduced time restoration at campfires. Needs iteration and playtesting.
- **Multiplayer someday**: the battle system is inherently PvP-friendly (both players have hero powers). A future mode could use the same battle maps for 1v1. Keep the architecture clean enough that this is possible but don't design around it now.
