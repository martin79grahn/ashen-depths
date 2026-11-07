# Ashen Depths

An original top-down action RPG made in Godot 4.5. You move and fight by clicking, and every floor is a randomly generated dungeon full of humanoid zombies. Everything is generated and drawn in code.

## Download & play
Grab the latest build from the [Releases](https://github.com/martin79grahn/ashen-depths/releases) page:
- **Linux:** unzip, then run `./AshenDepths.x86_64` (`chmod +x` it first if needed).
- **Windows:** unzip and run `AshenDepths.exe`. Windows may warn about an unknown publisher (the build is unsigned): choose *More info → Run anyway*.
- **Android:** download `AshenDepths.apk` on the phone, open it and allow installing from that source when Android asks.

### Playing on a phone
- **Tap** to move, attack, loot and use doors/stairs. Hold your finger down to keep walking.
- **Cast** (Paladin) or **Crossbow** (Knight) fires at the nearest foe in sight. Hold it to keep firing. The Knight also has a **Spell** button for the active spell.
- **Tap the belt** at the bottom for potions (1, 2), the class skill (Q) and to pick the active spell (3-7). The belt can be clicked on the computer too.
- **Map** toggles the minimap. **Inventory** opens your gear. In the inventory and shop, the button under the panel switches what a tap does (equip/buy, or drop/sell).
- Android's **back** button or gesture closes panels.

To run from source, open the folder in Godot 4.5.1, or run `godot --path .`. Builds are made with `godot --headless --export-release "Linux"` / `"Windows"` / `"Android"` (the Android build needs a signing key, which is not in the repo) (presets in `export_presets.cfg`, output in `export/`).

## Menu options
- **How to Play [H]:** a manual with pages on the heroes, weapons, magic, enemies, bosses, items and controls. The Enemies and Bosses pages show animated pictures of every foe, drawn by the game itself (`portrait.gd`).
- **Difficulty [D]:** Easy (enemies have 70% life and hit for 60%), Normal, Hard (135% / 140%) or Nightmare (180% / 190%). Boss Rush records are kept per difficulty.
- You can carry up to 99 of each potion.
- Each level has its own color theme: the stone, the zombies' skin and clothes, and the spiders are tinted a little differently (6 themes, then they repeat).

## Classes (chosen in the start menu)
- **Knight**: 120 life, 25% block, no mana (spells learned from scrolls recharge instead). Can wield heavy weapons (Greatsword, War Hammer, Halberd) and uses a crossbow (RMB, uses bolts). Q = Shield Bash (stun + knockback).
- **Paladin**: 95 life, 60 mana, 12% block. Light weapons only (swords, maces, flails), and no crossbows. RMB = Holy Bolt, Q = Healing Light (heal + damage nearby undead).

Weapons drop from zombies. Click a weapon on the ground to swap it with your current one. Heavy weapons are marked "Knight only".

## Zombies
Shambler, Fresh Runner (fast), Bile Spitter (ranged), Bloater (explodes on death and hurts everything nearby), Fallen Man-at-Arms (armored, depth 2+), Butcher (cleaver, depth 3+). Each zombie has randomized skin, clothes, hair and size. A named elite guards the stairs on each floor.

## World
No automatic regeneration: life and mana come back only from potions, level-ups and Healing Light, and bolts only from pickups or the merchant.
Real 2D lighting: your torch casts wall shadows, rooms have wall torches, and the stone textures are normal-mapped.
Dungeon dressing: puddles (with drips and splashes), bone piles, skeletons, cobwebs and spiders that flee from you and can be squashed.
Music and sound effects are synthesized at startup by `audio.gd` (N toggles the music).

## Bosses
When 3 or fewer enemies remain on a floor, the floor's boss appears and the stairs stay sealed until it dies:
1. **Mr. Giggles, the Drain Clown**: teleports around you and releases homing red balloons that burst (your sword can pop them).
2. **The Lakeside Slasher**: can't be stunned or knocked back, armored, and charges along a telegraphed red line. Enraged below half life.
3. **The Nightmare Man**: fades almost invisible and reappears behind you, and can shrink your torchlight.
After depth 3 the bosses repeat with more life and damage. Below half life the Lakeside Slasher's mask is knocked off, revealing a deformed face. The cracked mask stays on the floor, and he gets faster. When Mr. Giggles dies he bursts into 10 red spiders, and the boss only counts as defeated when all of them are dead. Names are set in `BOSSES` at the top of `main.gd`. Killing a boss grants 3 attribute points.


## Merchant & spell scrolls
After every boss (except the last one in Boss Rush), a wandering merchant appears with a lantern. Click him to trade. Time stands still while the store is open. He sells 4 weapons for your class (one is +1 better), healing potions, mana potions (Paladin), bolts (Knight) and spell scrolls. He buys back potions, bolts and weapons for 40% of the price (right-click a backpack weapon while trading). In Boss Rush, the next boss's countdown only starts when you press Enter or click "Fight the next boss".

Reading a spell scroll teaches you that spell permanently; reading the same scroll again raises it one level (max 5). Higher levels cost more, and scrolls are read on the spot, so they can't be resold. Pick the active spell with keys 3-7 (Knight 3-6), the **mouse wheel**, or by clicking the spellbook in the inventory.

**Knight:** has no mana. Cast the active spell with **F** or the **middle mouse button**; each spell then recharges (Fireball 6 s, Frost Nova 9 s, Chain Lightning 7 s, Holy Ward 18 s, 8% faster per level).

**Paladin:** casts the active spell with RMB, using mana. Holy Bolt is known from the start and can be leveled too.

| Key (Paladin) | Spell | Mana | Effect (grows with level) |
|---|---|---|---|
| 3 | Holy Bolt | 5 | Holy damage projectile |
| 4 | Fireball | 12 | Exploding fireball, larger blast per level |
| 5 | Frost Nova | 16 | Freezes and hurts everything around you |
| 6 | Chain Lightning | 14 | Arcs through more enemies per level |
| 7 | Holy Ward | 22 | Less damage taken, lasts longer per level |

## Boss Rush
Toggle on the start menu (click the Mode button or press B). You fight all the bosses back to back in one pillared arena, with no zombies. You start with 3 attribute points, 5 healing potions and full bolts (Knight) or 4 mana potions (Paladin). There is an 8-second break between bosses. After the last boss, or when you die, the game returns to the title. Your best run (bosses slain and time) is saved.

## Debug mode
Press F9 (works on the menu or in game) to toggle invincibility. Runs that used debug mode are not saved as records.
## Controls
LMB move / attack / loot / stairs (hold to repeat) · Shift+LMB attack in place · RMB ranged · Q skill · 1/2 potions · 3-7 / mouse wheel: pick spell · F / MMB: Knight casts spell · Enter: next boss (Boss Rush) · Esc quit

Run: `~/Program/godot/Godot_v4.5.1-stable_linux.x86_64 --path ~/orbit-keeper`
