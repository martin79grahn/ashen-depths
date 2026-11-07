extends Node2D
## Ashen Depths — a top-down click-to-move action RPG.
## Pick a Knight (heavy weapons, shield, crossbow, no magic) or a Paladin (light weapons + holy magic).
## LMB: move / attack / pick up / stairs   Shift+LMB: attack in place
## RMB: crossbow (Knight) or the active spell (Paladin)   F/MMB: Knight's active spell   Q: class skill
## 1/2: potions   3-7 or mouse wheel: pick spell   Esc: quit
## Everything is generated and drawn in code; no external assets.

const T := 32
const W := 72
const H := 52
const LIGHT_R := 380.0
const PLAYER_R := 11.0
const REACH := 24.0
const PLAYER_SPEED := 175.0
const MAGNET_R := 80.0      # items within this range fly to you
const ITEM_LIFE := 10.0     # seconds before an item on the floor vanishes
const CORPSE_LIFE := 10.0   # seconds before a body disappears (its blood stays)
const MAX_DECALS := 4000

# name: [min, max, cooldown, reach bonus, heavy (Knight only), style]
const MELEE := {
	"Short Sword": [5, 9, 0.42, 0, false, "sword"],
	"Arming Sword": [7, 12, 0.5, 2, false, "sword"],
	"Mace": [8, 13, 0.55, 0, false, "mace"],
	"Flail": [9, 16, 0.62, 4, false, "mace"],
	"Greatsword": [14, 23, 0.8, 12, true, "greatsword"],
	"War Hammer": [17, 28, 0.92, 6, true, "hammer"],
	"Halberd": [13, 22, 0.85, 18, true, "halberd"],
}
# name: [min, max, reload]
const CROSSBOWS := {
	"Light Crossbow": [8, 13, 0.8],
	"Heavy Crossbow": [15, 24, 1.25],
}

class Weapon:
	var base := ""
	var bonus := 0
	var ranged := false
	var heavy := false
	var style := "sword"
	var dmg_min := 1
	var dmg_max := 2
	var speed := 0.5
	var reach := 0.0
	func label() -> String:
		return base + (" +%d" % bonus if bonus > 0 else "")

class Enemy:
	var kind := ""
	var name := ""
	var pos := Vector2.ZERO
	var radius := 12.0
	var hp := 10.0
	var max_hp := 10.0
	var speed := 80.0
	var dmg_min := 2
	var dmg_max := 4
	var armor := 0
	var xp := 10
	var ranged := false
	var elite := false
	var aggro := false
	var cd := 0.0
	var windup := 0.0
	var stun := 0.0
	var path := PackedVector2Array()
	var repath := 0.0
	var flash := 0.0
	var facing := Vector2.DOWN
	var anim := 0.0
	# Looks — every zombie gets its own
	var skin := Color.WHITE
	var shirt := Color.WHITE
	var pants := Color.WHITE
	var hair := Color.WHITE
	var bald := false
	var torn := false
	var last_dir := Vector2.RIGHT
	# Bosses
	var boss := false
	var ability := 3.0
	var mode := ""          # vanish | telegraph | charge | fade
	var mode_t := 0.0
	var charge_dir := Vector2.ZERO
	var charge_hit := false
	var chill := 0.0        # frosted by Frost Nova (visual)
	var unmasked := false   # the Slasher loses his mask below half life

class Corpse:
	var e: Enemy
	var t := 0.0
	var ang := 0.0

class Projectile:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 1
	var friendly := true
	var life := 2.0
	var color := Color.WHITE
	var radius := 5.0
	var style := "orb"   # orb | bolt | bile | balloon | fire
	var blast := 0.0     # > 0: explodes with this radius on impact (Fireball)
	var light: PointLight2D = null   # glowing projectiles carry a real light

class Drop:
	var pos := Vector2.ZERO
	var kind := "gold"   # gold | hp | mp | bolts | weapon
	var amount := 1
	var weapon: Weapon = null
	var t := 0.0
	var pull := 0.0      # magnet speed while being sucked in
	var locked := false  # dropped by the player: no magnet until they walk away

class FloatText:
	var pos := Vector2.ZERO
	var text := ""
	var color := Color.WHITE
	var life := 1.0
	var size := 16

var state := "menu"   # menu | play
var hero := "knight"  # knight | paladin

# Map
var grid := PackedByteArray()
var explored := PackedByteArray()
var shade := PackedFloat32Array()
var astar := AStarGrid2D.new()
var rooms: Array[Rect2i] = []
var stairs_pos := Vector2.ZERO
var depth := 1

# Player
var p_pos := Vector2.ZERO
var p_hp := 100.0
var p_max_hp := 100.0
var p_mp := 0.0
var p_max_mp := 0.0
var block := 0.2
var level := 1
var xp := 0
var xp_next := 60
var gold := 0
var hp_pots := 2
var mp_pots := 0
var bolts := 0
var max_bolts := 60
var melee: Weapon
var bow: Weapon = null
var path := PackedVector2Array()
var target_enemy: Enemy = null
var target_drop: Drop = null
var target_stairs := false
var atk_cd := 0.0
var swing := 0.0
var swing_len := 0.22
var ranged_cd := 0.0
var shoot_anim := 0.0
var skill_cd := 0.0
var skill_max := 6.0
var facing := Vector2.DOWN
var walk_anim := 0.0
var dead := false
var death_timer := 0.0
var hurt_flash := 0.0
var repath_timer := 0.0
var hold_timer := 0.0

# Inventory
const BAG_SIZE := 24
var bag: Array = []          # BAG_SIZE entries, each a Weapon or null
var inv_open := false
var show_map := true

var enemies: Array[Enemy] = []
var projectiles: Array[Projectile] = []
var drops: Array[Drop] = []
var texts: Array[FloatText] = []
var particles: Array = []   # {pos, vel, life, max, col, size}
var rings: Array = []       # expanding effect rings {pos, r, max, col, life}
var hover_enemy: Enemy = null
var hover_drop: Drop = null
var click_marker := Vector2.ZERO
var click_marker_t := 0.0
var message := ""
var message_t := 0.0
var shake := 0.0

var font: Font
var camera: Camera2D
var hud
var touch_on := false            # a touch screen is in use: show the on-screen buttons
var touch_fingers := {}          # touch index -> button held
var touch_alt := false           # inventory/shop on a phone: a tap acts as a right click
var portraits: Node          # the manual's enemy & boss pictures: one SubViewport each (portrait.gd)
var audio
var corpses: Array[Corpse] = []
var env                     # env.gd: props, torches, spiders
var overlay: Node2D         # unlit world-space layer: flames, glows, rings, text
var stone_tex: CanvasTexture
var light_tex: GradientTexture2D
var player_light: PointLight2D
var occluder_root: Node2D
var tile_var := PackedByteArray()
const FACE_TEX_H := 36.0
const AMBIENT := Color(0.12, 0.11, 0.13)
var spheres := {}           # normal-mapped sphere sprites: skin | cloth | metal | bone

# One boss per floor, in this order (then repeating, stronger). Names are original —
# rename them here if you like.
const BOSSES := [
	{"kind": "clown", "name": "Mr. Giggles, the Drain Clown", "hp": 260.0, "r": 20.0, "speed": 85.0, "dmg": [10, 16],
		"intro": "Laughter echoes up from the drains..."},
	{"kind": "slasher", "name": "The Lakeside Slasher", "hp": 480.0, "r": 23.0, "speed": 66.0, "dmg": [16, 24],
		"intro": "Heavy footsteps. Something that will not stop is coming."},
	{"kind": "dream", "name": "The Nightmare Man", "hp": 520.0, "r": 19.0, "speed": 95.0, "dmg": [9, 14],
		"intro": "Your eyes grow heavy... welcome to your nightmare."},
]
var boss: Enemy = null
var boss_spawned := false
# Boss Rush: one arena, the bosses back to back, each wave stronger.
const RUSH_BREAK := 8.0
const RUSH_SAVE := "user://boss_rush.cfg"
var rush := false           # chosen on the menu
# Difficulty (menu, key D): scales enemy life and the damage you take.
const DIFFICULTIES := [
	{"name": "Easy", "hp": 0.7, "dmg": 0.6, "col": Color(0.5, 0.85, 0.5)},
	{"name": "Normal", "hp": 1.0, "dmg": 1.0, "col": Color(0.9, 0.82, 0.6)},
	{"name": "Hard", "hp": 1.35, "dmg": 1.4, "col": Color(1.0, 0.55, 0.25)},
	{"name": "Nightmare", "hp": 1.8, "dmg": 1.9, "col": Color(1.0, 0.2, 0.15)},
]
var difficulty := 1
var manual_open := false    # "How to Play" pages on the menu
var manual_page := 0
const MAX_POTIONS := 99
# Each level gets its own colour theme: stone tint, a hue the dead share, and spider colour.
const LEVEL_THEMES := [
	{"floor": Color(1.0, 1.0, 1.0), "zombie": Color(0.55, 0.6, 0.5), "spider": Color(0.11, 0.08, 0.06)},
	{"floor": Color(0.86, 0.93, 1.05), "zombie": Color(0.5, 0.58, 0.75), "spider": Color(0.06, 0.08, 0.13)},
	{"floor": Color(1.06, 0.9, 0.8), "zombie": Color(0.75, 0.5, 0.42), "spider": Color(0.16, 0.06, 0.04)},
	{"floor": Color(0.9, 1.04, 0.86), "zombie": Color(0.5, 0.72, 0.42), "spider": Color(0.07, 0.12, 0.05)},
	{"floor": Color(0.98, 0.88, 1.04), "zombie": Color(0.65, 0.5, 0.75), "spider": Color(0.12, 0.06, 0.14)},
	{"floor": Color(1.04, 1.0, 0.82), "zombie": Color(0.72, 0.7, 0.42), "spider": Color(0.14, 0.12, 0.04)},
]
var rush_wave := 0          # bosses slain this run
var rush_break := 0.0       # countdown to the next boss
var rush_time := 0.0
var rush_best := 0
var rush_best_time := 0.0
var rush_won := false
var rush_end_t := 0.0       # after victory, seconds until we return to the title
var debug := false          # F9: invincible (runs played with it on don't set records)
var run_debug := false
var boss_dead := false
var brood_of: Enemy = null  # the clown, while the spiders it burst into are still alive
var pending_brood := false
var fallen_mask := {}       # the Slasher's mask lying on the floor: {pos, ang}

# Spell scrolls. Reading one learns that spell for good, or raises it a level if already known.
# The active spell is picked with keys 3-7, the mouse wheel or the spellbook in the inventory.
# A Paladin casts it with RMB using mana; a Knight has no mana, so he casts with F / middle
# mouse and each spell then needs a while to recharge (KNIGHT_CD).
const SPELLS := {
	"holy": {"name": "Holy Bolt", "key": "3", "price": 40, "col": Color(1.0, 0.9, 0.5), "desc": "A bolt of holy light"},
	"fireball": {"name": "Fireball", "key": "3", "price": 45, "col": Color(1.0, 0.45, 0.1), "desc": "Exploding fireball toward the cursor"},
	"frost": {"name": "Frost Nova", "key": "4", "price": 40, "col": Color(0.45, 0.8, 1.0), "desc": "Freezes and hurts everything around you"},
	"lightning": {"name": "Chain Lightning", "key": "5", "price": 55, "col": Color(0.75, 0.8, 1.0), "desc": "Arcs through up to 5 enemies near the cursor"},
	"ward": {"name": "Holy Ward", "key": "6", "price": 50, "col": Color(1.0, 0.85, 0.35), "desc": "Take 60% less damage for 12 seconds"},
}
const SPELL_ORDER := ["fireball", "frost", "lightning", "ward"]
const PALADIN_SPELLS := ["holy", "fireball", "frost", "lightning", "ward"]
const SPELL_COST := {"holy": 5.0, "fireball": 12.0, "frost": 16.0, "lightning": 14.0, "ward": 22.0}
const SPELL_CD := {"holy": 0.35, "fireball": 0.8, "frost": 1.4, "lightning": 0.7, "ward": 2.0}
const SPELL_MAX := 5
const KNIGHT_CD := {"fireball": 6.0, "frost": 9.0, "lightning": 7.0, "ward": 18.0}   # -8% per level
var spell_lvl := {}         # known spells -> level
var selected_spell := "holy"   # "" while a Knight knows no spells
var spell_cd := {}          # Knight: seconds until each spell is ready again
var ward_mult := 0.4        # damage taken while Holy Ward is up
var ward_t := 0.0
var zaps: Array = []        # lightning arcs {pts, life}

# The wandering merchant shows up after every boss.
const SUPPLY := {"hp": ["Healing Potion", 25], "mp": ["Mana Potion", 25], "bolts": ["Bolts (15)", 15]}
const SELL_RATE := 0.4
var merchant_on := false
var merchant_pos := Vector2.ZERO
var merchant_light: PointLight2D = null
var shop_open := false
var shop_stock: Array = []  # 4 Weapons (null once sold)
var target_merchant := false
var nightmare_t := 0.0      # the Nightmare Man shrinks your torchlight
var light_r := LIGHT_R
var decals: Array = []      # blood stains: {pos, r, col, born, grow}
var growl_timer := 2.0


func _ready() -> void:
	randomize()
	_load_rush()
	font = ThemeDB.fallback_font
	camera = Camera2D.new()
	camera.zoom = Vector2(2.2, 2.2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)

	# Real 2D lighting: a dark ambient, the player's torch with wall shadows, and normal-mapped stone.
	stone_tex = preload("res://textures.gd").build()
	var cm := CanvasModulate.new()
	cm.color = AMBIENT
	add_child(cm)
	light_tex = GradientTexture2D.new()
	light_tex.width = 512
	light_tex.height = 512
	light_tex.fill = GradientTexture2D.FILL_RADIAL
	light_tex.fill_from = Vector2(0.5, 0.5)
	light_tex.fill_to = Vector2(1.0, 0.5)
	var lg := Gradient.new()
	lg.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	lg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.8, 0.8, 0.8, 1), Color(0.28, 0.28, 0.28, 1), Color(0, 0, 0, 1)])
	light_tex.gradient = lg
	player_light = PointLight2D.new()
	player_light.texture = light_tex
	player_light.texture_scale = LIGHT_R / 256.0 * 1.15
	player_light.color = Color(1.0, 0.84, 0.62)
	player_light.energy = 1.3
	player_light.height = 45.0
	player_light.shadow_enabled = true
	player_light.shadow_filter = Light2D.SHADOW_FILTER_PCF13
	player_light.shadow_filter_smooth = 4.0
	add_child(player_light)
	occluder_root = Node2D.new()
	add_child(occluder_root)
	env = preload("res://env.gd").new(self)
	spheres = preload("res://textures.gd").build_spheres()

	# Bloom: anything drawn brighter than 1.0 (flames, magic, eyes) glows.
	var we := WorldEnvironment.new()
	var envr := Environment.new()
	envr.background_mode = Environment.BG_CANVAS
	envr.background_canvas_max_layer = 1
	envr.glow_enabled = true
	envr.glow_intensity = 0.8
	envr.glow_strength = 1.0
	envr.glow_bloom = 0.0
	envr.glow_hdr_threshold = 1.0
	envr.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for lv in 7:
		envr.set_glow_level(lv, lv >= 1 and lv <= 4)
	we.environment = envr
	add_child(we)

	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 1
	fx_layer.follow_viewport_enabled = true
	add_child(fx_layer)
	overlay = Node2D.new()
	fx_layer.add_child(overlay)
	overlay.draw.connect(_draw_overlay)

	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var vignette := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.7))
	g.set_offset(0, 0.65)
	grad.gradient = g
	vignette.texture = grad
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vignette)

	audio = preload("res://audio.gd").new()
	add_child(audio)

	touch_on = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	hud = preload("res://hud.gd").new()
	hud.main = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	portraits = load("res://portrait.gd").build(self)

	# A floor behind the menu for atmosphere.
	_generate_floor()


# ================================================================ game flow

func _start(cls: String) -> void:
	hero = cls
	state = "play"
	depth = 1
	level = 1
	xp = 0
	xp_next = 60
	gold = 0
	hp_pots = 2
	dead = false
	skill_cd = 0.0
	inv_open = false
	bag.clear()
	bag.resize(BAG_SIZE)
	stat_points = 0
	attr = {"strength": 0, "speed": 0, "life": 0, "capacity": 0}
	max_bolts = 60
	if hero == "knight":
		p_max_hp = 120.0
		p_max_mp = 0.0
		block = 0.25
		mp_pots = 0
		bolts = 30
		melee = _make_melee("Arming Sword", 0)
		bow = _make_crossbow("Light Crossbow", 0)
		skill_max = 5.0
	else:
		p_max_hp = 95.0
		p_max_mp = 60.0
		block = 0.12
		mp_pots = 2
		bolts = 0
		melee = _make_melee("Mace", 0)
		bow = null
		skill_max = 1.0
	p_hp = p_max_hp
	p_mp = p_max_mp
	rush_wave = 0
	rush_won = false
	spell_lvl = {"holy": 1} if hero == "paladin" else {}
	selected_spell = "holy" if hero == "paladin" else ""
	spell_cd = {}
	ward_t = 0.0
	shop_open = false
	run_debug = debug
	rush_time = 0.0
	rush_break = 3.0
	if rush:
		# A head start, since there are no zombies to level up on first.
		stat_points = 3
		hp_pots = 5
		if hero == "knight":
			bolts = max_bolts
		else:
			mp_pots = 4
	_generate_floor()
	if rush:
		_say("Boss Rush — spend your 3 points (I) and get ready")
	else:
		_say("Depth 1 — The Ashen Gate")


func _next_floor() -> void:
	depth += 1
	_generate_floor()
	_say("Depth %d" % depth)


func diff() -> Dictionary:
	return DIFFICULTIES[difficulty]


func theme() -> Dictionary:
	return LEVEL_THEMES[(depth - 1) % LEVEL_THEMES.size()]


func cycle_difficulty() -> void:
	difficulty = (difficulty + 1) % DIFFICULTIES.size()
	_load_rush()


func _say(s: String) -> void:
	message = s
	message_t = 3.0


func _make_melee(base: String, bonus: int) -> Weapon:
	var d: Array = MELEE[base]
	var w := Weapon.new()
	w.base = base
	w.bonus = bonus
	w.dmg_min = d[0] + bonus * 2
	w.dmg_max = d[1] + bonus * 3
	w.speed = d[2]
	w.reach = d[3]
	w.heavy = d[4]
	w.style = d[5]
	return w


func _make_crossbow(base: String, bonus: int) -> Weapon:
	var d: Array = CROSSBOWS[base]
	var w := Weapon.new()
	w.base = base
	w.bonus = bonus
	w.ranged = true
	w.heavy = true
	w.style = "crossbow"
	w.dmg_min = d[0] + bonus * 2
	w.dmg_max = d[1] + bonus * 3
	w.speed = d[2]
	return w


func _random_weapon() -> Weapon:
	var bonus := randi_range(0, depth)
	# Crossbows only show up for knights; heavy melee shows up for both (paladins can't use it).
	if hero == "knight" and randf() < 0.25:
		return _make_crossbow(CROSSBOWS.keys().pick_random(), bonus)
	return _make_melee(MELEE.keys().pick_random(), bonus)


func can_use(w: Weapon) -> bool:
	return hero == "knight" or not w.heavy


# ================================================================ dungeon generation

func _generate_floor() -> void:
	grid.resize(W * H)
	grid.fill(1)
	explored.resize(W * H)
	explored.fill(0)
	shade.resize(W * H)
	for i in W * H:
		shade[i] = randf_range(-0.03, 0.03)

	rooms.clear()
	if rush:
		_carve_arena()
	for attempt in 300:
		if rush or rooms.size() >= 13:
			break
		var rw := randi_range(6, 13)
		var rh := randi_range(5, 10)
		var r := Rect2i(randi_range(1, W - rw - 2), randi_range(1, H - rh - 2), rw, rh)
		var ok := true
		for o in rooms:
			if r.grow(2).intersects(o):
				ok = false
				break
		if ok:
			rooms.append(r)
	for r in rooms:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				grid[y * W + x] = 0
	for i in range(1, rooms.size()):
		var best := 0
		var best_d := INF
		for j in i:
			var d := Vector2(rooms[i].get_center()).distance_to(Vector2(rooms[j].get_center()))
			if d < best_d:
				best_d = d
				best = j
		_carve_corridor(rooms[i].get_center(), rooms[best].get_center())
	for k in 0 if rush else 2:
		_carve_corridor(rooms[randi() % rooms.size()].get_center(), rooms[randi() % rooms.size()].get_center())

	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(T, T)
	astar.offset = Vector2(T, T) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in H:
		for x in W:
			if grid[y * W + x] == 1:
				astar.set_point_solid(Vector2i(x, y))

	p_pos = _tile_center(rooms[0].get_center())
	var far := mini(1, rooms.size() - 1)
	var far_d := 0.0
	for i in range(1, rooms.size()):
		var d := Vector2(rooms[i].get_center()).distance_to(Vector2(rooms[0].get_center()))
		if d > far_d:
			far_d = d
			far = i
	stairs_pos = _tile_center(rooms[far].get_center())
	if rush:
		# No way down in the arena: park the stairs in the far corner wall, which is never lit
		# or explored, so they are never drawn or clickable.
		p_pos = _tile_center(rooms[0].get_center() + Vector2i(0, 7))
		stairs_pos = _tile_center(Vector2i.ZERO)

	enemies.clear()
	for pr in projectiles:
		if pr.light:
			pr.light.queue_free()
	projectiles.clear()
	drops.clear()
	texts.clear()
	particles.clear()
	rings.clear()
	corpses.clear()
	boss = null
	boss_spawned = false
	boss_dead = false
	brood_of = null
	pending_brood = false
	fallen_mask = {}
	zaps.clear()
	_merchant_leave(false)
	nightmare_t = 0.0
	if audio:
		audio.set_boss(false)
	decals.clear()
	path.clear()
	target_enemy = null
	target_drop = null
	target_stairs = false
	target_merchant = false

	for i in range(1, 0 if rush else rooms.size()):
		var r := rooms[i]
		var count := randi_range(1, 3) + depth / 2
		for n in count:
			var cell := Vector2i(randi_range(r.position.x + 1, r.end.x - 2), randi_range(r.position.y + 1, r.end.y - 2))
			_spawn_enemy(_pick_kind(), _tile_center(cell), false)
	var guard := "shambler"
	if depth >= 3:
		guard = "butcher"
	elif depth >= 2:
		guard = "armored"
	if not rush:
		_spawn_enemy(guard, stairs_pos + Vector2(T * 2, 0), true)

	tile_var.resize(W * H)
	for i in W * H:
		tile_var[i] = randi() % 16
	env.generate()
	_build_occluders()

	camera.position = p_pos
	camera.reset_smoothing()


func _to_menu() -> void:
	state = "menu"
	manual_open = false
	inv_open = false
	shop_open = false
	nightmare_t = 0.0
	audio.set_boss(false)


## The Boss Rush arena: one big hall with four pillars to duck behind.
func _carve_arena() -> void:
	var r := Rect2i(W / 2 - 17, H / 2 - 12, 34, 24)
	rooms.append(r)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			grid[y * W + x] = 0
	var c := r.get_center()
	for off in [Vector2i(-8, -5), Vector2i(7, -5), Vector2i(-8, 4), Vector2i(7, 4)]:
		for dy in 2:
			for dx in 2:
				grid[(c.y + off.y + dy) * W + c.x + off.x + dx] = 1


## Walls cast shadows. Each run of wall tiles that touches floor becomes one occluder. Walls with
## floor directly below only occlude their top part, so the brick face stays lit.
func _build_occluders() -> void:
	for c in occluder_root.get_children():
		c.queue_free()
	for y in H:
		var run_start := -1
		var run_kind := 0
		for x in W + 1:
			var kind := 0
			if x < W and grid[y * W + x] == 1:
				var edge := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var c := Vector2i(x + dx, y + dy)
						if c.x >= 0 and c.y >= 0 and c.x < W and c.y < H and grid[c.y * W + c.x] == 0:
							edge = true
				if edge:
					kind = 2 if (y + 1 < H and grid[(y + 1) * W + x] == 0) else 1
			if kind != run_kind:
				if run_kind != 0:
					_add_occluder(run_start, x, y, run_kind)
				run_start = x
				run_kind = kind


func _add_occluder(x0: int, x1: int, y: int, kind: int) -> void:
	var h := float(T) if kind == 1 else T * 0.45
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(x0 * T, y * T), Vector2(x1 * T, y * T), Vector2(x1 * T, y * T + h), Vector2(x0 * T, y * T + h)])
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	occluder_root.add_child(occ)


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	var y := a.y
	if randf() < 0.5:
		while x != b.x:
			_carve2(x, y); x += signi(b.x - x)
		while y != b.y:
			_carve2(x, y); y += signi(b.y - y)
	else:
		while y != b.y:
			_carve2(x, y); y += signi(b.y - y)
		while x != b.x:
			_carve2(x, y); x += signi(b.x - x)
	_carve2(x, y)


func _carve2(x: int, y: int) -> void:
	for dy in 2:
		for dx in 2:
			grid[clampi(y + dy, 1, H - 2) * W + clampi(x + dx, 1, W - 2)] = 0


func _pick_kind() -> String:
	var table := {"shambler": 40, "runner": 22, "spitter": 18, "bloater": 12}
	if depth >= 2:
		table["armored"] = 14
	if depth >= 3:
		table["butcher"] = 7
	var total := 0
	for k in table:
		total += table[k]
	var roll := randi() % total
	for k in table:
		roll -= table[k]
		if roll < 0:
			return k
	return "shambler"


const SKINS := [Color(0.55, 0.62, 0.5), Color(0.6, 0.62, 0.68), Color(0.68, 0.66, 0.48), Color(0.58, 0.5, 0.58), Color(0.5, 0.56, 0.45)]
const CLOTH := [Color(0.42, 0.3, 0.22), Color(0.3, 0.33, 0.4), Color(0.45, 0.42, 0.35), Color(0.35, 0.18, 0.16),
	Color(0.25, 0.3, 0.22), Color(0.5, 0.48, 0.42), Color(0.22, 0.2, 0.25), Color(0.4, 0.35, 0.15)]
const HAIRS := [Color(0.15, 0.1, 0.07), Color(0.35, 0.22, 0.12), Color(0.55, 0.55, 0.52), Color(0.6, 0.48, 0.25), Color(0.08, 0.08, 0.08)]

func _spawn_enemy(kind: String, pos: Vector2, elite: bool) -> void:
	var e := Enemy.new()
	e.kind = kind
	e.pos = pos
	var skin: Color = SKINS.pick_random()
	e.skin = skin.darkened(randf_range(0.0, 0.15))
	e.shirt = CLOTH.pick_random()
	var pants: Color = CLOTH.pick_random()
	e.pants = pants.darkened(0.3)
	e.hair = HAIRS.pick_random()
	e.bald = randf() < 0.25
	e.torn = randf() < 0.5
	var size := randf_range(0.9, 1.1)
	match kind:
		"shambler":
			e.name = "Shambler"; e.radius = 11; e.max_hp = 24; e.speed = 55
			e.dmg_min = 4; e.dmg_max = 7; e.xp = 12
		"runner":
			e.name = "Fresh Runner"; e.radius = 10; e.max_hp = 14; e.speed = 135
			e.dmg_min = 3; e.dmg_max = 5; e.xp = 14
			e.skin = e.skin.lerp(Color(0.75, 0.62, 0.55), 0.5)   # recently turned
		"spitter":
			e.name = "Bile Spitter"; e.radius = 10; e.max_hp = 18; e.speed = 60
			e.dmg_min = 5; e.dmg_max = 8; e.xp = 16; e.ranged = true
			e.skin = e.skin.lerp(Color(0.5, 0.65, 0.25), 0.5)
		"bloater":
			e.name = "Bloater"; e.radius = 15; e.max_hp = 30; e.speed = 45
			e.dmg_min = 6; e.dmg_max = 9; e.xp = 18
			e.skin = e.skin.lerp(Color(0.6, 0.65, 0.35), 0.6)
		"armored":
			e.name = "Fallen Man-at-Arms"; e.radius = 12; e.max_hp = 45; e.speed = 65
			e.dmg_min = 7; e.dmg_max = 11; e.armor = 3; e.xp = 28
			e.shirt = Color(0.5, 0.52, 0.55)
		"butcher":
			e.name = "Butcher"; e.radius = 16; e.max_hp = 70; e.speed = 58
			e.dmg_min = 10; e.dmg_max = 16; e.xp = 40
			e.shirt = Color(0.75, 0.72, 0.65)
		"red_spider":
			e.name = "Giggling Spawn"; e.radius = 9; e.max_hp = 16; e.speed = 150
			e.dmg_min = 3; e.dmg_max = 5; e.xp = 8
			e.skin = Color(0.72, 0.06, 0.04)
	e.radius *= size
	var mult := 1.0 + 0.3 * (depth - 1)
	e.max_hp *= mult * diff().hp
	# This level's hue seeps into the dead.
	var hue: Color = theme().zombie
	e.skin = e.skin.lerp(hue, 0.3)
	e.shirt = e.shirt.lerp(hue.darkened(0.3), 0.18)
	e.pants = e.pants.lerp(hue.darkened(0.45), 0.15)
	if kind == "red_spider":
		e.skin = Color(0.72, 0.06, 0.04).lerp(hue, 0.22)
	e.dmg_min += depth - 1
	e.dmg_max += (depth - 1) * 2
	e.xp = int(e.xp * mult)
	if elite:
		e.elite = true
		e.name = ["Grimjaw", "Old Wilhelm", "the Hollow Warden", "Mother Soot", "Brother Ash"].pick_random() + " (" + e.name + ")"
		e.max_hp *= 3.0
		e.radius *= 1.25
		e.dmg_min = int(e.dmg_min * 1.4)
		e.dmg_max = int(e.dmg_max * 1.4)
		e.xp *= 4
	e.hp = e.max_hp
	e.facing = Vector2.from_angle(randf() * TAU)
	e.anim = randf() * 10.0
	enemies.append(e)


# ================================================================ helpers

func _tile_center(c: Vector2i) -> Vector2:
	return Vector2(c) * T + Vector2(T, T) * 0.5


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


func _solid(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return true
	return grid[c.y * W + c.x] == 1


func _blocked(p: Vector2, r: float) -> bool:
	var k := r * 0.85
	return _solid(_cell(p + Vector2(-k, -k))) or _solid(_cell(p + Vector2(k, -k))) \
		or _solid(_cell(p + Vector2(-k, k))) or _solid(_cell(p + Vector2(k, k)))


func _move(p: Vector2, v: Vector2, r: float) -> Vector2:
	var n := p
	if not _blocked(Vector2(p.x + v.x, p.y), r):
		n.x += v.x
	if not _blocked(Vector2(n.x, p.y + v.y), r):
		n.y += v.y
	return n


func _los(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / 10.0)
	for i in range(1, steps):
		if _solid(_cell(a.lerp(b, float(i) / steps))):
			return false
	return true


func _find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var tc := _cell(to)
	if _solid(tc):
		var best := tc
		var best_d := INF
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var c := tc + Vector2i(dx, dy)
				if not _solid(c) and Vector2(dx, dy).length() < best_d:
					best_d = Vector2(dx, dy).length()
					best = c
		if best == tc:
			return PackedVector2Array()
		tc = best
		to = _tile_center(tc)
	var pts := astar.get_point_path(_cell(from), tc, true)
	if pts.size() > 0:
		pts.remove_at(0)
	if pts.size() > 0:
		pts[pts.size() - 1] = to
	elif _cell(from) == tc:
		pts.append(to)
	return pts


func _light(p: Vector2) -> float:
	return clampf(1.0 - p.distance_to(p_pos) / light_r, 0.0, 1.0)


## How visible a point is: lit by the player's torch or by a wall torch the player has seen.
func _vis(p: Vector2) -> float:
	return maxf(_light(p), env.torch_vis(p))


func _enemy_at(p: Vector2) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in enemies:
		var d := e.pos.distance_to(p)
		if d < e.radius + 10.0 and d < best_d and _vis(e.pos) > 0.05 and e.mode != "vanish":
			best = e
			best_d = d
	return best


func _drop_at(p: Vector2) -> Drop:
	for d in drops:
		if d.pos.distance_to(p) < 14.0 and _vis(d.pos) > 0.02:
			return d
	return null


func drop_label(d: Drop) -> String:
	match d.kind:
		"gold": return "%d Gold" % d.amount
		"hp": return "Healing Potion"
		"mp": return "Mana Potion"
		"bolts": return "%d Crossbow Bolts" % d.amount
		"weapon": return d.weapon.label()
	return ""


func _float(pos: Vector2, s: String, col: Color, size := 16) -> void:
	var f := FloatText.new()
	f.pos = pos + Vector2(randf_range(-6, 6), -14)
	f.text = s
	f.color = col
	f.size = size
	texts.append(f)


func _burst(pos: Vector2, col: Color, count: int, speed: float, size := 2.5, glow := false) -> void:
	for i in count:
		var life := randf_range(0.25, 0.7)
		particles.append({
			"pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(0.2, 1.0) * speed,
			"life": life, "max": life, "col": col, "size": randf_range(size * 0.5, size * 1.4), "glow": glow,
		})


func _blood_col(e: Enemy) -> Color:
	if e.kind == "bloater":
		return Color(0.33, 0.4, 0.08)
	return Color(0.32, 0.03, 0.02)


## Spray droplets along dir; each one leaves a stain where it lands or hits a wall.
func _blood(pos: Vector2, dir: Vector2, count: int, col: Color, spread := 0.7, speed := 240.0) -> void:
	for i in count:
		var life := randf_range(0.12, 0.35)
		var v := dir.rotated(randf_range(-spread, spread)) * randf_range(0.25, 1.0) * speed
		particles.append({
			"pos": pos, "vel": v, "life": life, "max": life,
			"col": col.darkened(randf_range(0.0, 0.3)), "size": randf_range(1.2, 3.2), "blood": true,
		})


func _decal(pos: Vector2, r: float, col: Color, grow := 0.0) -> void:
	decals.append({"pos": pos, "r": r, "col": col, "born": Time.get_ticks_msec() / 1000.0, "grow": grow})
	if decals.size() > MAX_DECALS:
		decals.pop_front()


func _proj_light(col: Color, scale: float, energy: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = light_tex
	l.texture_scale = scale
	l.color = col
	l.energy = energy
	l.height = 20.0
	add_child(l)
	return l


func _ring(pos: Vector2, r: float, col: Color) -> void:
	rings.append({"pos": pos, "r": 0.0, "max": r, "col": col, "life": 0.4})


# ================================================================ input

## Touch screens: the round buttons work with any finger, so you can walk and cast at once.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_on = true
			var b: String = hud.touch_button_at(event.position)
			if b != "":
				touch_fingers[event.index] = b
				_touch_press(b)
		else:
			touch_fingers.erase(event.index)


func _touch_press(b: String) -> void:
	match b:
		"cast": _ranged(_auto_target())
		"spell": _knight_cast(_auto_target())
		"map": show_map = not show_map
		"mode": touch_alt = not touch_alt


## Where to aim from a touch button: the nearest foe in sight, or straight ahead.
func _auto_target() -> Vector2:
	var best: Enemy = null
	var bd := 420.0
	for e in enemies:
		if e.hp <= 0.0 or e.mode == "vanish":
			continue
		var d := e.pos.distance_to(p_pos)
		if d < bd and _los(p_pos, e.pos):
			bd = d
			best = e
	return best.pos if best else p_pos + facing * 120.0


func _notification(what: int) -> void:
	# Android's back button/gesture closes panels, or leaves the manual / the game.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if manual_open:
			manual_open = false
		elif shop_open or inv_open:
			shop_open = false
			inv_open = false
		elif state == "menu":
			get_tree().quit()
		elif dead:
			_to_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if state == "menu" and manual_open:
			match event.keycode:
				KEY_ESCAPE, KEY_H: manual_open = false
				KEY_LEFT, KEY_A: manual_page = posmod(manual_page - 1, hud.MANUAL_TABS.size())
				KEY_RIGHT, KEY_D, KEY_TAB: manual_page = (manual_page + 1) % hud.MANUAL_TABS.size()
			return
		if event.keycode == KEY_ESCAPE:
			if shop_open or inv_open:
				shop_open = false
				inv_open = false
				return
			get_tree().quit()
		if state == "play" and not dead and (event.keycode == KEY_I or event.keycode == KEY_TAB):
			inv_open = not inv_open
			shop_open = false
			return
		if state == "play" and rush and merchant_on and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
			_rush_ready()
			return
		if event.keycode == KEY_N:
			audio.toggle_music()
			return
		if event.keycode == KEY_F9:
			debug = not debug
			if debug and state == "play":
				run_debug = true
			_say("Debug mode: %s" % ("INVINCIBLE" if debug else "off"))
			audio.play_ui("coin", -10.0)
			return
		if state == "play" and event.keycode == KEY_M:
			show_map = not show_map
			return
		if state == "menu":
			if event.keycode == KEY_1: _start("knight")
			elif event.keycode == KEY_2: _start("paladin")
			elif event.keycode == KEY_B: rush = not rush
			elif event.keycode == KEY_D: cycle_difficulty()
			elif event.keycode == KEY_H:
				manual_open = true
			return
		match event.keycode:
			KEY_1: _drink_hp()
			KEY_2: _drink_mp()
			KEY_Q: _use_skill()
			KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				var i: int = event.keycode - KEY_3
				if i < spell_order().size():
					select_spell(spell_order()[i])
			KEY_F: _knight_cast()
			KEY_R:
				if dead:
					_to_menu()
		return

	if not (event is InputEventMouseButton and event.pressed):
		return
	if state == "menu" and manual_open:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in hud.MANUAL_TABS.size():
				if hud.manual_tab_rect(i).has_point(event.position):
					manual_page = i
			if hud.manual_close_rect().has_point(event.position):
				manual_open = false
		return
	if state == "menu":
		if event.button_index == MOUSE_BUTTON_LEFT:
			if hud.manual_button_rect().has_point(event.position):
				manual_open = true
				audio.play_ui("coin", -10.0)
				return
			for i in 2:
				if hud.card_rect(i).has_point(event.position):
					_start(["knight", "paladin"][i])
			if hud.mode_rect().has_point(event.position):
				rush = not rush
				audio.play_ui("coin", -10.0)
			if hud.diff_rect().has_point(event.position):
				cycle_difficulty()
				audio.play_ui("coin", -10.0)
		return
	if dead:
		if event.button_index == MOUSE_BUTTON_LEFT and death_timer > 1.0:
			_to_menu()
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not shop_open:
			cycle_spell(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_knight_cast()
		return
	if hud.touch_button_at(event.position) != "":
		return                        # handled by _input
	var belt: String = hud.belt_at(event.position) if event.button_index == MOUSE_BUTTON_LEFT else ""
	if belt != "":
		match belt:
			"hp": _drink_hp()
			"mp": _drink_mp()
			"skill": _use_skill()
			_: select_spell(belt.substr(6))
		return
	if hud.inv_button_rect().has_point(event.position):
		inv_open = not inv_open
		return
	var btn: int = event.button_index
	if touch_alt and touch_on and btn == MOUSE_BUTTON_LEFT:
		btn = MOUSE_BUTTON_RIGHT
	if shop_open and hud.shop_rect().has_point(event.position):
		_shop_click(btn, hud.shop_slot_at(event.position))
		return
	if inv_open and hud.inv_panel_rect().has_point(event.position):
		_inv_click(btn, hud.inv_slot_at(event.position))
		return
	var m := get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_key_pressed(KEY_SHIFT):
			_clear_targets()
			_melee_toward(m)
		else:
			_left_click(m, true)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_ranged(m)


func _clear_targets() -> void:
	target_enemy = null
	target_drop = null
	target_stairs = false
	target_merchant = false
	path.clear()


func _left_click(m: Vector2, fresh: bool) -> void:
	var e := _enemy_at(m)
	if e:
		_clear_targets()
		target_enemy = e
		return
	if fresh:
		var d := _drop_at(m)
		if d:
			_clear_targets()
			target_drop = d
			path = _find_path(p_pos, d.pos)
			return
		if merchant_on and m.distance_to(merchant_pos + Vector2(0, -6)) < 18.0:
			_clear_targets()
			target_merchant = true
			path = _find_path(p_pos, merchant_pos)
			return
		var sc := _cell(stairs_pos)
		if m.distance_to(stairs_pos) < T * 0.8 and explored[sc.y * W + sc.x] == 1:
			_clear_targets()
			target_stairs = true
			path = _find_path(p_pos, stairs_pos)
			return
	_clear_targets()
	path = _find_path(p_pos, m)
	if fresh:
		click_marker = m
		click_marker_t = 0.5


func _reach() -> float:
	return REACH + melee.reach


func _melee_toward(pt: Vector2) -> void:
	if atk_cd > 0.0:
		return
	var dir := pt - p_pos
	if dir.length() > 0.1:
		facing = dir.normalized()
	atk_cd = melee.speed / atk_mult()
	swing_len = minf(0.3, melee.speed * 0.45)
	swing = swing_len
	audio.play("swing", p_pos, -5.0)
	path.clear()
	var arc := 1.1 if melee.style != "halberd" else 0.7
	env.hit_arc(p_pos, facing, PLAYER_R + _reach() + 8.0)
	for pr in projectiles:
		var tb := pr.pos - p_pos
		if pr.style == "balloon" and tb.length() < PLAYER_R + _reach() + 14.0 and absf(facing.angle_to(tb)) < 1.2:
			pr.life = 0.0
	for e in enemies:
		if e.hp <= 0.0:
			continue
		var to := e.pos - p_pos
		if to.length() <= PLAYER_R + e.radius + _reach() + 6.0 and absf(facing.angle_to(to)) < arc:
			var dmg := randi_range(melee.dmg_min, melee.dmg_max) + melee_bonus()
			_hurt_enemy(e, dmg, facing, "melee")
			if melee.style == "hammer":
				e.stun = maxf(e.stun, 0.6)


func _ranged(pt: Vector2) -> void:
	if ranged_cd > 0.0 or dead:
		return
	var dir := (pt - p_pos).normalized()
	if dir == Vector2.ZERO:
		dir = facing
	var pr := Projectile.new()
	pr.friendly = true
	if hero == "knight":
		if bow == null:
			_float(p_pos, "No crossbow equipped", Color(0.8, 0.7, 0.5), 13)
			ranged_cd = 0.5
			return
		if bolts <= 0:
			_float(p_pos, "Out of bolts", Color(0.8, 0.7, 0.5), 13)
			ranged_cd = 0.5
			return
		bolts -= 1
		ranged_cd = bow.speed / atk_mult()
		shoot_anim = 0.3
		audio.play("crossbow", p_pos, -2.0)
		pr.vel = dir * 620.0
		pr.dmg = randi_range(bow.dmg_min, bow.dmg_max) + level
		pr.color = Color(0.75, 0.7, 0.6)
		pr.radius = 3.0
		pr.style = "bolt"
	else:
		var id := selected_spell
		var cost: float = SPELL_COST[id]
		if p_mp < cost:
			_float(p_pos, "Not enough mana", Color(0.5, 0.6, 1.0), 13)
			ranged_cd = 0.4
			return
		if id != "holy":
			if _cast_spell(id, spell_lvl[id], pt):
				p_mp -= cost
				ranged_cd = SPELL_CD[id] / atk_mult()
				facing = dir
			else:
				ranged_cd = 0.3
			return
		p_mp -= cost
		ranged_cd = SPELL_CD[id] / atk_mult()
		pr.vel = dir * 440.0
		pr.dmg = randi_range(9, 14) + int(level * 2.5) + (spell_lvl.holy - 1) * 5
		pr.color = Color(1.0, 0.9, 0.5)
		pr.radius = 6.0
		pr.style = "orb"
		audio.play("magic_cast", p_pos, -4.0)
	facing = dir
	pr.pos = p_pos + dir * 14.0
	if pr.style == "orb":
		pr.light = _proj_light(pr.color, 0.45, 1.1)
	projectiles.append(pr)


func _use_skill() -> void:
	if dead or skill_cd > 0.0:
		return
	if hero == "knight":
		# Shield Bash: knock back and stun everything in front of you.
		skill_cd = skill_max
		var dir := (get_global_mouse_position() - p_pos).normalized()
		if dir != Vector2.ZERO:
			facing = dir
		_ring(p_pos + facing * 20.0, 55.0, Color(0.85, 0.85, 0.9))
		audio.play("bash", p_pos)
		shake = maxf(shake, 4.0)
		for e in enemies:
			var to := e.pos - p_pos
			if to.length() < 60.0 + e.radius and absf(facing.angle_to(to)) < 1.3:
				e.stun = 1.5
				e.windup = 0.0
				_hurt_enemy(e, 4 + level, facing, "quiet")
				for k in 4:
					e.pos = _move(e.pos, to.normalized() * 10.0, e.radius)
	else:
		# Healing Light: heal and burn nearby undead.
		if p_mp < 20.0:
			_float(p_pos, "Not enough mana", Color(0.5, 0.6, 1.0), 13)
			return
		p_mp -= 20.0
		skill_cd = skill_max
		var amt := p_max_hp * 0.35
		p_hp = minf(p_max_hp, p_hp + amt)
		_float(p_pos, "+%d" % int(amt), Color(0.5, 1.0, 0.5))
		_ring(p_pos, 90.0, Color(1.0, 0.9, 0.5))
		audio.play("heal", p_pos, -2.0)
		_burst(p_pos, Color(1.0, 0.9, 0.5), 30, 160.0, 2.5, true)
		for e in enemies:
			if e.pos.distance_to(p_pos) < 90.0 + e.radius:
				_hurt_enemy(e, 6 + level * 2, (e.pos - p_pos).normalized(), "magic")


func _drink_hp() -> void:
	if hp_pots <= 0 or dead or p_hp >= p_max_hp:
		return
	hp_pots -= 1
	var amt := p_max_hp * 0.45
	p_hp = minf(p_max_hp, p_hp + amt)
	_float(p_pos, "+%d" % int(amt), Color(0.4, 1.0, 0.4))
	_burst(p_pos, Color(1.0, 0.3, 0.3), 14, 80.0)


func _drink_mp() -> void:
	if hero != "paladin" or mp_pots <= 0 or dead or p_mp >= p_max_mp:
		return
	mp_pots -= 1
	p_mp = minf(p_max_mp, p_mp + p_max_mp * 0.6)
	_burst(p_pos, Color(0.3, 0.5, 1.0), 14, 80.0)


# ================================================================ combat

## src: melee | bolt | magic | blast | quiet — picks the impact sound.
func _hurt_enemy(e: Enemy, dmg: int, dir: Vector2, src := "melee") -> void:
	if e.hp <= 0.0 or e.mode == "vanish":
		return
	e.last_dir = dir
	var crit := randf() < 0.12
	if crit:
		dmg *= 2
	dmg = maxi(1, dmg - e.armor)
	e.hp -= dmg
	e.flash = 0.12
	if e.boss and e.kind == "slasher" and not e.unmasked and e.hp > 0.0 and e.hp < e.max_hp * 0.5:
		_unmask(e, dir)
	if not e.aggro:
		_alert(e)
	if e.kind != "slasher":
		e.pos = _move(e.pos, dir * (3.0 if e.elite or e.boss else 9.0), e.radius)
	_float(e.pos, str(dmg) + ("!" if crit else ""), Color(1.0, 0.85, 0.3) if crit else Color(1, 1, 1), 20 if crit else 16)
	var armored := e.armor > 0
	match src:
		"melee", "bolt":
			audio.play("metal" if armored else "flesh", e.pos, -2.0 if src == "bolt" else 0.0)
			if armored:
				_burst(e.pos + dir * e.radius * 0.6, Color(1.0, 0.85, 0.5), 7, 170.0, 1.2, true)   # sparks
		"magic":
			audio.play("magic_hit", e.pos, -5.0)
	_blood(e.pos, dir, 16 if crit else 9, _blood_col(e))
	if e.hp > 0.0 and randf() < 0.45:
		audio.play("zhurt", e.pos, -3.0, 0.12)
	if e.hp <= 0.0:
		_kill(e)


func _alert(e: Enemy) -> void:
	e.aggro = true
	for o in enemies:
		if not o.aggro and o.pos.distance_to(e.pos) < 180.0:
			o.aggro = true


func _kill(e: Enemy) -> void:
	shake = maxf(shake, 4.0 if not e.elite else 10.0)
	_burst(e.pos, e.skin, 8, 140.0, 2.5)
	_gain_xp(e.xp)
	var bc := _blood_col(e)
	audio.play("death", e.pos, 0.0, 0.1)
	if e.kind == "bloater":
		audio.play("explode", e.pos, 2.0)
		for k in 3:
			_blood(e.pos, Vector2.from_angle(randf() * TAU), 25, bc, PI, 320.0)
		for k in 8:
			_decal(e.pos + Vector2.from_angle(randf() * TAU) * randf_range(0, 30), randf_range(5, 11), bc.darkened(randf() * 0.3), randf_range(0.3, 1.0))
	else:
		audio.play("squelch", e.pos, -4.0)
		_blood(e.pos, e.last_dir, 22, bc, 1.0, 300.0)
	if e.boss and e.kind == "clown":
		# No body: the clown bursts apart into a swarm of red spiders.
		audio.play("laugh", e.pos, 3.0)
		audio.play("pop", e.pos, 0.0)
		_burst(e.pos, Color(0.9, 0.9, 0.95, 0.7), 40, 170.0, 3.5)
		_burst(e.pos, Color(0.8, 0.05, 0.03), 30, 220.0, 2.5)
		_ring(e.pos, 50.0, Color(1.0, 0.2, 0.1))
	elif e.kind != "bloater":
		# The body falls away from the blow and bleeds out into a slowly spreading pool.
		var c := Corpse.new()
		c.e = e
		c.ang = e.last_dir.angle() + randf_range(-0.5, 0.5)
		corpses.append(c)
		for k in 5:
			_decal(e.pos + Vector2.from_angle(randf() * TAU) * randf_range(0, e.radius * 0.8), e.radius * randf_range(0.5, 0.9),
				bc.darkened(randf_range(0.1, 0.35)), randf_range(1.5, 3.5))
	if target_enemy == e:
		target_enemy = null
	if e.boss:
		if e.kind == "clown" and brood_of == null:
			brood_of = e
			pending_brood = true
			_say("%s bursts into a swarm of spiders!" % e.name.split(",")[0])
			return
		_boss_defeated(e)
	if e.kind == "red_spider":
		if brood_of != null:
			var left := 0
			for o in enemies:
				if o != e and o.kind == "red_spider" and o.hp > 0.0:
					left += 1
			if left == 0 and not pending_brood:
				var b := brood_of
				brood_of = null
				b.pos = e.pos
				_boss_defeated(b)
		if randf() < 0.3:
			_add_drop("gold", e.pos, randi_range(2, 6) * depth)
		return

	if e.kind == "bloater":
		# Bursts in a cloud of rot, hurting everything nearby — including other zombies.
		_ring(e.pos, 75.0, Color(0.6, 0.8, 0.2))
		_burst(e.pos, Color(0.55, 0.75, 0.15), 40, 220.0, 4.0)
		shake = maxf(shake, 7.0)
		if p_pos.distance_to(e.pos) < 75.0:
			_hurt_player(randi_range(10, 16) + depth * 2, true)
		for o in enemies:
			if o != e and o.hp > 0.0 and o.pos.distance_to(e.pos) < 75.0:
				_hurt_enemy(o, 15, (o.pos - e.pos).normalized(), "blast")

	var rolls := 1 if not e.elite else 4
	for i in rolls:
		var off := Vector2.from_angle(randf() * TAU) * (randf_range(8, 22) if i > 0 else 0.0)
		var roll := randf()
		if roll < 0.5 or e.elite:
			_add_drop("gold", e.pos + off, randi_range(3, 10) * depth * (3 if e.elite else 1))
		if roll < 0.13 or (e.elite and i == 0):
			_add_drop("hp", e.pos + off + Vector2(10, 4), 1)
		elif roll > (0.85 if hero == "knight" else 0.74):
			if hero == "knight":
				_add_drop("bolts", e.pos + off + Vector2(-10, 4), randi_range(5, 10))
			else:
				_add_drop("mp", e.pos + off + Vector2(-10, 4), 1)
	if e.elite or randf() < 0.07:
		var d := Drop.new()
		d.kind = "weapon"
		d.weapon = _random_weapon()
		d.pos = e.pos + Vector2(0, -12)
		if _blocked(d.pos, 4):
			d.pos = _tile_center(_cell(e.pos))
		drops.append(d)


func _add_drop(kind: String, pos: Vector2, amount: int) -> void:
	var d := Drop.new()
	d.kind = kind
	d.pos = pos if not _blocked(pos, 4) else _tile_center(_cell(pos))
	d.amount = amount
	drops.append(d)


func _gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_next:
		xp -= xp_next
		xp_next = int(xp_next * 1.45)
		level += 1
		stat_points += 1
		audio.play_ui("levelup", -3.0)
		p_hp = p_max_hp
		p_mp = p_max_mp
		_float(p_pos + Vector2(0, -20), "LEVEL UP!", Color(1.0, 0.85, 0.3), 24)
		_burst(p_pos, Color(1.0, 0.85, 0.3), 40, 200.0, 2.5, true)
		_say("Level %d — +1 attribute point (press I)" % level)


# ================================================================ attributes

const ATTRS := ["strength", "speed", "life", "capacity"]
const SPEED_CAP := 10
const STR_DMG := 2          # melee damage per Strength point
const SPEED_MOVE := 0.06    # +6% move speed per point
const SPEED_ATK := 0.05     # +5% attack / reload speed per point
const LIFE_PER := 15
const MANA_PER := 10
const BOLTS_PER := 15

var stat_points := 0
var attr := {"strength": 0, "speed": 0, "life": 0, "capacity": 0}


func can_spend(a: String) -> bool:
	return stat_points > 0 and not (a == "speed" and attr.speed >= SPEED_CAP)


func spend_point(a: String) -> void:
	if not can_spend(a):
		return
	stat_points -= 1
	attr[a] += 1
	match a:
		"life":
			p_max_hp += LIFE_PER
			p_hp += LIFE_PER
		"capacity":
			if hero == "knight":
				max_bolts += BOLTS_PER
			else:
				p_max_mp += MANA_PER
				p_mp += MANA_PER
	_burst(p_pos, Color(1.0, 0.85, 0.3), 12, 90.0, 2.5, true)


func melee_bonus() -> int:
	return attr.strength * STR_DMG


func atk_mult() -> float:
	return 1.0 + attr.speed * SPEED_ATK


func move_speed() -> float:
	return PLAYER_SPEED * (1.0 + attr.speed * SPEED_MOVE)


func _hurt_player(dmg: int, unblockable := false) -> void:
	if dead:
		return
	if debug:
		_float(p_pos, "Immune", Color(0.6, 0.9, 1.0), 12)
		return
	dmg = maxi(1, roundi(dmg * diff().dmg))
	if ward_t > 0.0:
		dmg = maxi(1, int(dmg * ward_mult))
	if not unblockable and randf() < block:
		_float(p_pos, "Blocked", Color(0.75, 0.8, 0.9), 13)
		audio.play("block", p_pos, -2.0)
		_burst(p_pos + facing.rotated(-1.4) * 10.0, Color(0.9, 0.9, 1.0), 6, 90.0, 1.5)
		return
	p_hp -= dmg
	hurt_flash = 0.25
	shake = maxf(shake, 5.0)
	_float(p_pos, "-%d" % dmg, Color(1.0, 0.3, 0.3))
	audio.play("player_hurt", p_pos, -3.0)
	audio.play("flesh", p_pos, -8.0)
	_blood(p_pos, Vector2.from_angle(randf() * TAU), 8, Color(0.5, 0.02, 0.02))
	if p_hp <= 0.0:
		for k in 4:
			_blood(p_pos, Vector2.from_angle(randf() * TAU), 15, Color(0.5, 0.02, 0.02), 1.2, 260.0)
		for k in 5:
			_decal(p_pos + Vector2.from_angle(randf() * TAU) * randf_range(0, 10), randf_range(6, 11), Color(0.42, 0.02, 0.02), randf_range(1.5, 3.0))
		p_hp = 0.0
		dead = true
		death_timer = 0.0
		_burst(p_pos, Color(0.6, 0.05, 0.05), 50, 220.0, 4.0)
		shake = 14.0


## Whether the magnet should pull this item (room for it, and usable if it's a weapon).
func _wants(d: Drop) -> bool:
	match d.kind:
		"hp": return hp_pots < MAX_POTIONS
		"mp": return mp_pots < MAX_POTIONS
		"bolts": return bolts < max_bolts
		"weapon": return can_use(d.weapon) and bag.has(null)
	return true


func _pickup(d: Drop) -> bool:
	match d.kind:
		"gold":
			gold += d.amount
			audio.play_ui("coin", -9.0, randf_range(0.95, 1.08))
			_float(d.pos, "%d gold" % d.amount, Color(1.0, 0.85, 0.3), 13)
		"hp":
			if hp_pots >= MAX_POTIONS: return false
			hp_pots += 1
		"mp":
			if mp_pots >= MAX_POTIONS: return false
			mp_pots += 1
		"bolts":
			if bolts >= max_bolts: return false
			bolts = mini(max_bolts, bolts + d.amount)
			_float(d.pos, "+%d bolts" % d.amount, Color(0.8, 0.75, 0.6), 13)
		"weapon":
			var slot := bag.find(null)
			if slot == -1:
				_float(p_pos, "Inventory full", Color(1.0, 0.45, 0.35), 14)
				return false
			bag[slot] = d.weapon
			_float(p_pos, "Picked up " + d.weapon.label() + "  [I]", Color(0.9, 0.85, 0.6), 14)
	return true


# ================================================================ inventory

## slot: {"type": "bag", "i": n} | {"type": "melee"} | {"type": "ranged"} | {}
func _inv_click(button: int, slot: Dictionary) -> void:
	if slot.is_empty():
		return
	if slot.type == "attr":
		if button == MOUSE_BUTTON_LEFT:
			spend_point(ATTRS[slot.i])
		return
	if slot.type == "spell":
		if button == MOUSE_BUTTON_LEFT:
			select_spell(slot.id)
		return
	if slot.type == "bag":
		var w: Weapon = bag[slot.i]
		if w == null:
			return
		if button == MOUSE_BUTTON_RIGHT and shop_open:
			bag[slot.i] = null
			var got := sell_value(weapon_price(w))
			gold += got
			audio.play_ui("coin", -6.0)
			_float(p_pos, "Sold %s for %d gold" % [w.label(), got], Color(1.0, 0.85, 0.3), 14)
		elif button == MOUSE_BUTTON_RIGHT:
			# Drop it on the floor.
			bag[slot.i] = null
			var d := Drop.new()
			d.kind = "weapon"
			d.weapon = w
			d.pos = p_pos + Vector2(randf_range(-12, 12), 14)
			d.locked = true
			drops.append(d)
		elif button == MOUSE_BUTTON_LEFT:
			equip_from_bag(slot.i)
	elif slot.type == "ranged" and button == MOUSE_BUTTON_LEFT and bow != null:
		var free := bag.find(null)
		if free != -1:
			bag[free] = bow
			bow = null


func equip_from_bag(i: int) -> void:
	var w: Weapon = bag[i]
	if w == null:
		return
	if not can_use(w):
		_float(p_pos, "Paladins can't use that — Knights only", Color(1.0, 0.45, 0.35), 14)
		return
	if w.ranged:
		bag[i] = bow
		bow = w
	else:
		bag[i] = melee
		melee = w
	_float(p_pos, "Equipped " + w.label(), Color(0.9, 0.85, 0.6), 14)


func mouse_over_inventory() -> bool:
	var mp := get_viewport().get_mouse_position()
	# the belt and the touch buttons are UI too: holding them must not walk the hero
	if hud.belt_at(mp) != "" or hud.touch_button_at(mp) != "":
		return true
	if not inv_open:
		return false
	if shop_open and hud.shop_rect().has_point(mp):
		return true
	return hud.inv_panel_rect().has_point(mp) or hud.inv_button_rect().has_point(mp)


# ================================================================ update

func _process(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 30.0)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	click_marker_t = maxf(0.0, click_marker_t - delta)
	message_t = maxf(0.0, message_t - delta)

	if state == "menu":
		walk_anim += delta
		camera.position = p_pos + Vector2(sin(walk_anim * 0.2), cos(walk_anim * 0.15)) * 120.0
		_update_misc(delta)
		player_light.position = camera.position
		queue_redraw()
		overlay.queue_redraw()
		hud.queue_redraw()
		return

	if dead:
		death_timer += delta
		if rush and death_timer > 4.0:
			_to_menu()
			return
	elif not shop_open:
		_update_player(delta)
	if not shop_open:   # time stands still while you trade
		ward_t = maxf(0.0, ward_t - delta)
		_update_enemies(delta)
		_update_projectiles(delta)
	_update_misc(delta)
	env.update(delta)
	var tm := Time.get_ticks_msec() / 1000.0
	player_light.position = p_pos + Vector2(sin(tm * 3.1), cos(tm * 2.3)) * 1.5
	player_light.energy = 1.3 + 0.06 * sin(tm * 11.0) + 0.04 * sin(tm * 27.0)
	nightmare_t = maxf(0.0, nightmare_t - delta)
	light_r = lerpf(light_r, LIGHT_R * (0.42 if nightmare_t > 0.0 else 1.0), minf(1.0, delta * 2.0))
	player_light.texture_scale = light_r / 256.0 * 1.15

	var mouse := get_global_mouse_position()
	hover_enemy = _enemy_at(mouse) if not dead and not mouse_over_inventory() else null
	hover_drop = _drop_at(mouse) if hover_enemy == null else null
	camera.position = p_pos
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	queue_redraw()
	overlay.queue_redraw()
	hud.queue_redraw()


func _update_player(delta: float) -> void:
	atk_cd -= delta
	ranged_cd -= delta
	for id in spell_cd:
		spell_cd[id] = maxf(0.0, spell_cd[id] - delta)
	skill_cd = maxf(0.0, skill_cd - delta)
	swing = maxf(0.0, swing - delta)
	shoot_anim = maxf(0.0, shoot_anim - delta)

	var ui := mouse_over_inventory()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not ui:
		hold_timer -= delta
		if hold_timer <= 0.0:
			hold_timer = 0.12
			var m := get_global_mouse_position()
			if Input.is_key_pressed(KEY_SHIFT):
				_melee_toward(m)
			elif target_enemy == null and target_drop == null and not target_stairs and not target_merchant:
				_left_click(m, false)
	else:
		hold_timer = 0.12
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not ui:
		_ranged(get_global_mouse_position())
	if "cast" in touch_fingers.values():
		_ranged(_auto_target())       # holding Cast keeps firing (the cooldown sets the pace)

	if target_enemy:
		var e := target_enemy
		if e.hp <= 0.0:
			target_enemy = null
		elif p_pos.distance_to(e.pos) <= PLAYER_R + e.radius + _reach():
			path.clear()
			facing = (e.pos - p_pos).normalized()
			if atk_cd <= 0.0:
				_melee_toward(e.pos)
				if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					target_enemy = null
		else:
			repath_timer -= delta
			if repath_timer <= 0.0 or path.is_empty():
				repath_timer = 0.2
				path = _find_path(p_pos, e.pos)

	if not path.is_empty() and swing <= 0.0:
		var nxt := path[0]
		var to := nxt - p_pos
		var step := move_speed() * delta
		if to.length() <= step:
			p_pos = _move(p_pos, to, PLAYER_R)
			path.remove_at(0)
		else:
			facing = to.normalized()
			var before := p_pos
			p_pos = _move(p_pos, facing * step, PLAYER_R)
			if p_pos.distance_to(before) < step * 0.1:
				path.remove_at(0)
		walk_anim += delta * 10.0

	# Items near you get sucked in (if you have room); clicked items are always picked up.
	for i in range(drops.size() - 1, -1, -1):
		var d := drops[i]
		var dist := d.pos.distance_to(p_pos)
		if d.locked:
			if dist > MAGNET_R + 10.0:
				d.locked = false
			elif target_drop != d:
				continue
		var magnet := dist < MAGNET_R and _wants(d) and _los(d.pos, p_pos)
		if magnet:
			d.pull += 900.0 * delta
			d.pos = d.pos.move_toward(p_pos, (120.0 + d.pull) * delta)
			dist = d.pos.distance_to(p_pos)
		else:
			d.pull = 0.0
		if dist < 18.0 and (magnet or target_drop == d):
			if target_drop == d:
				target_drop = null
			if _pickup(d):
				if d.kind != "gold":
					audio.play_ui("coin", -13.0, 0.65)
				drops.remove_at(i)

	if target_merchant and p_pos.distance_to(merchant_pos) < 34.0:
		target_merchant = false
		path.clear()
		_open_shop()

	if target_stairs and p_pos.distance_to(stairs_pos) < 20.0:
		if boss_dead:
			_next_floor()
		else:
			target_stairs = false
			_say("The stairs are sealed. Something still hunts you here...")

	var pc := _cell(p_pos)
	var rad := int(LIGHT_R / T) + 1
	for y in range(pc.y - rad, pc.y + rad + 1):
		for x in range(pc.x - rad, pc.x + rad + 1):
			if x >= 0 and y >= 0 and x < W and y < H and _light(_tile_center(Vector2i(x, y))) > 0.08:
				explored[y * W + x] = 1


func _update_enemies(delta: float) -> void:
	if rush:
		if rush_won:
			rush_end_t -= delta
			if rush_end_t <= 0.0:
				_to_menu()
		elif not dead:
			rush_time += delta
			if not boss_spawned and not merchant_on:
				rush_break -= delta
				if rush_break <= 0.0:
					depth = rush_wave + 1
					_spawn_boss()
	elif not boss_spawned and not dead:
		var left := 0
		for e in enemies:
			if e.hp > 0.0:
				left += 1
		if left <= 3:
			_spawn_boss()
	if pending_brood and brood_of != null:
		pending_brood = false
		for k in 10:
			var sp := brood_of.pos + Vector2.from_angle(k * TAU / 10.0 + randf() * 0.3) * randf_range(10.0, 36.0)
			if _blocked(sp, 8.0):
				sp = brood_of.pos
			_spawn_enemy("red_spider", sp, false)
			var s: Enemy = enemies.back()
			s.aggro = true
			s.stun = randf_range(0.3, 0.7)
			s.facing = (sp - brood_of.pos).normalized() if sp != brood_of.pos else Vector2.DOWN
	# Ambient growling from zombies nearby — more often when they're hunting you.
	growl_timer -= delta
	if growl_timer <= 0.0 and not dead:
		var near: Array = []
		var hunting := false
		for e in enemies:
			if e.pos.distance_to(p_pos) < 520.0:
				near.append(e)
				hunting = hunting or e.aggro
		if not near.is_empty():
			var g: Enemy = near.pick_random()
			audio.play("growl", g.pos, -3.0 if g.aggro else -9.0, 0.15)
		growl_timer = randf_range(1.2, 3.0) if hunting else randf_range(3.0, 7.0)
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].hp <= 0.0:
			enemies.remove_at(i)

	for e in enemies:
		e.flash -= delta
		e.cd -= delta
		e.anim += delta
		e.chill = maxf(0.0, e.chill - delta)
		if e.boss:
			_update_boss(e, delta)
			continue
		if e.stun > 0.0:
			e.stun -= delta
			continue
		var to_p := p_pos - e.pos
		var d := to_p.length()
		if dead:
			e.aggro = false
			continue
		if not e.aggro and d < 250.0 and _los(e.pos, p_pos):
			_alert(e)
		if not e.aggro:
			# Idle shuffle
			if fmod(e.anim, 4.0) < 1.0:
				e.pos = _move(e.pos, e.facing * 15.0 * delta, e.radius)
			continue
		if d > 900.0:
			e.aggro = false
			continue
		e.facing = e.facing.slerp(to_p.normalized(), minf(1.0, delta * 8.0))

		if e.windup > 0.0:
			e.windup -= delta
			if e.windup <= 0.0:
				if e.ranged:
					var pr := Projectile.new()
					pr.pos = e.pos + e.facing * 12.0
					pr.vel = to_p.normalized() * 260.0
					pr.dmg = randi_range(e.dmg_min, e.dmg_max)
					pr.friendly = false
					pr.color = Color(0.55, 0.75, 0.15)
					pr.radius = 5.0
					pr.style = "bile"
					pr.light = _proj_light(Color(0.5, 0.9, 0.2), 0.22, 0.7)
					projectiles.append(pr)
					audio.play("spit", e.pos, -4.0)
				elif d <= e.radius + PLAYER_R + REACH + 6.0:
					_hurt_player(randi_range(e.dmg_min, e.dmg_max))
			continue

		var see := _los(e.pos, p_pos)
		if e.ranged and see and d < 280.0:
			if d < 100.0:
				e.pos = _move(e.pos, -to_p.normalized() * e.speed * delta, e.radius)
			elif e.cd <= 0.0:
				e.windup = 0.5
				e.cd = randf_range(1.6, 2.4)
			continue
		if not e.ranged and d <= e.radius + PLAYER_R + REACH * 0.6:
			if e.cd <= 0.0:
				e.windup = 0.35 if not e.elite else 0.5
				if randf() < 0.5:
					audio.play("attack", e.pos, -5.0, 0.12)
				if e.kind == "runner" or e.kind == "red_spider":
					e.windup = 0.22
				e.cd = 0.7 if e.kind == "runner" or e.kind == "red_spider" else 1.1
			continue

		# Shamblers lurch: speed pulses as they drag their feet.
		var spd := e.speed
		if e.kind == "shambler" or e.kind == "bloater":
			spd *= 0.6 + 0.6 * absf(sin(e.anim * 2.5))
		e.repath -= delta
		if see:
			e.path.clear()
			e.pos = _move(e.pos, to_p.normalized() * spd * delta, e.radius)
		else:
			if e.repath <= 0.0 or e.path.is_empty():
				e.repath = randf_range(0.4, 0.7)
				e.path = _find_path(e.pos, p_pos)
			if not e.path.is_empty():
				var tw := e.path[0] - e.pos
				if tw.length() < 6.0:
					e.path.remove_at(0)
				else:
					e.pos = _move(e.pos, tw.normalized() * spd * delta, e.radius)

	for a in enemies.size():
		var ea := enemies[a]
		for b in range(a + 1, enemies.size()):
			var eb := enemies[b]
			var diff := eb.pos - ea.pos
			var min_d := ea.radius + eb.radius
			var dd := diff.length()
			if dd < min_d and dd > 0.01:
				var push := diff / dd * (min_d - dd) * 0.5
				ea.pos = _move(ea.pos, -push, ea.radius)
				eb.pos = _move(eb.pos, push, eb.radius)
		var dp := ea.pos - p_pos
		var md := ea.radius + PLAYER_R
		if dp.length() < md and dp.length() > 0.01:
			ea.pos = _move(ea.pos, dp.normalized() * (md - dp.length()), ea.radius)


func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var pr := projectiles[i]
		if pr.style == "balloon":
			var want := (p_pos - pr.pos).normalized() * 75.0 + Vector2(sin(pr.life * 3.0 + i), cos(pr.life * 2.0)) * 20.0
			pr.vel = pr.vel.lerp(want, minf(1.0, delta * 1.5))
		pr.pos += pr.vel * delta
		if pr.light:
			pr.light.position = pr.pos
		pr.life -= delta
		var hit := false
		if _solid(_cell(pr.pos)) or pr.life <= 0.0:
			hit = true
			if pr.style == "bolt" and pr.life > 0.0:
				audio.play("block", pr.pos, -12.0, 0.2)   # bolt clattering off stone
		elif pr.friendly:
			for e in enemies:
				if e.hp > 0.0 and e.pos.distance_to(pr.pos) < e.radius + pr.radius:
					if pr.blast <= 0.0:
						_hurt_enemy(e, pr.dmg, pr.vel.normalized(), "bolt" if pr.style == "bolt" else "magic")
					hit = true
					break
		elif not dead and pr.pos.distance_to(p_pos) < PLAYER_R + pr.radius:
			_hurt_player(pr.dmg)
			hit = true
		if pr.style != "bolt" and randf() < 0.8:
			particles.append({"pos": pr.pos, "vel": -pr.vel * 0.1 + Vector2(randf_range(-30, 30), randf_range(-30, 30)),
				"life": 0.3, "max": 0.3, "col": Color(pr.color, 0.8), "size": 3.0 if pr.style == "orb" else 2.0, "glow": true})
		if hit and pr.style == "balloon":
			audio.play("pop", pr.pos, -2.0)
			_burst(pr.pos, Color(0.8, 0.05, 0.05), 14, 140.0, 2.0)
		if hit and pr.blast > 0.0:
			_explode(pr.pos - pr.vel.normalized() * 6.0, pr.blast, pr.dmg)
		if hit:
			_burst(pr.pos, pr.color, 12 if pr.style == "orb" else 6, 120.0, 2.5, pr.style != "bolt")
			if pr.light:
				pr.light.queue_free()
			projectiles.remove_at(i)


func _update_misc(delta: float) -> void:
	for i in range(zaps.size() - 1, -1, -1):
		zaps[i].life -= delta
		if zaps[i].life <= 0.0:
			zaps.remove_at(i)
	for i in range(particles.size() - 1, -1, -1):
		var pt: Dictionary = particles[i]
		pt.life -= delta
		if pt.has("blood"):
			var np: Vector2 = pt.pos + pt.vel * delta
			if _solid(_cell(np)):
				_decal(np, pt.size * 1.3, pt.col)   # splatters on the wall
				particles.remove_at(i)
				continue
			if pt.life <= 0.0:
				_decal(pt.pos, pt.size * 1.1, pt.col)
				particles.remove_at(i)
				continue
		if pt.life <= 0.0:
			particles.remove_at(i)
			continue
		pt.pos += pt.vel * delta
		pt.vel *= 1.0 - 3.0 * delta
	for i in range(corpses.size() - 1, -1, -1):
		corpses[i].t += delta
		if corpses[i].t >= CORPSE_LIFE:
			corpses.remove_at(i)
	for i in range(rings.size() - 1, -1, -1):
		var rg: Dictionary = rings[i]
		rg.life -= delta
		rg.r = rg.max * (1.0 - rg.life / 0.4)
		if rg.life <= 0.0:
			rings.remove_at(i)
	for i in range(texts.size() - 1, -1, -1):
		texts[i].life -= delta
		texts[i].pos.y -= 30.0 * delta
		if texts[i].life <= 0.0:
			texts.remove_at(i)
	for i in range(drops.size() - 1, -1, -1):
		var d := drops[i]
		d.t += delta
		if d.t >= ITEM_LIFE:
			if target_drop == d:
				target_drop = null
			if _light(d.pos) > 0.05:
				_burst(d.pos, Color(0.7, 0.65, 0.55, 0.6), 6, 50.0, 1.5)
			drops.remove_at(i)


# ================================================================ bosses
# A boss appears once 3 or fewer enemies are left on a floor; the stairs stay sealed until it dies.

func _spawn_boss() -> void:
	boss_spawned = true
	@warning_ignore("integer_division")
	var cycle := (depth - 1) / BOSSES.size()
	var b: Dictionary = BOSSES[(depth - 1) % BOSSES.size()]
	var e := Enemy.new()
	e.boss = true
	e.kind = b.kind
	e.name = b.name
	var mult := (1.0 + 0.3 * (depth - 1)) * pow(1.5, cycle)
	e.max_hp = b.hp * mult * diff().hp
	e.hp = e.max_hp
	e.radius = b.r
	e.speed = b.speed
	e.dmg_min = int(b.dmg[0] * (1.0 + 0.25 * cycle)) + depth - 1
	e.dmg_max = int(b.dmg[1] * (1.0 + 0.25 * cycle)) + (depth - 1) * 2
	e.xp = int(250 * mult)
	e.aggro = true
	e.armor = 2 if e.kind == "slasher" else 0
	_boss_looks(e)
	e.pos = _boss_spot(140.0 if e.kind == "clown" else 260.0)
	e.facing = (p_pos - e.pos).normalized()
	e.ability = 4.0
	enemies.append(e)
	boss = e
	shake = 8.0
	audio.set_boss(true)
	audio.play_ui("boss_roar", -2.0)
	if e.kind == "clown":
		audio.play("laugh", e.pos, 2.0)
		_burst(e.pos, Color(0.9, 0.9, 0.95, 0.7), 30, 150.0, 3.0)
	elif e.kind == "dream":
		audio.play("dream_laugh", e.pos, 2.0)
	_say(b.intro)


## Colours of each boss (shared with the manual's portraits).
func _boss_looks(e: Enemy) -> void:
	match e.kind:
		"clown":
			e.skin = Color(0.95, 0.94, 0.92)
			e.shirt = Color(0.8, 0.8, 0.84)
			e.pants = Color(0.75, 0.75, 0.8)
			e.hair = Color(0.95, 0.4, 0.05)
		"slasher":
			e.skin = Color(0.6, 0.55, 0.5)
			e.shirt = Color(0.27, 0.26, 0.19)
			e.pants = Color(0.18, 0.17, 0.15)
			e.bald = true
		"dream":
			e.skin = Color(0.62, 0.32, 0.26)
			e.shirt = Color(0.6, 0.1, 0.08)
			e.pants = Color(0.25, 0.2, 0.15)
			e.bald = true


## A free spot roughly `dist` away from the player.
func _boss_spot(dist: float) -> Vector2:
	for attempt in 80:
		var p := p_pos + Vector2.from_angle(randf() * TAU) * randf_range(dist * 0.8, dist * 1.2)
		if not _blocked(p, 18.0):
			return p
	return _tile_center(rooms[randi() % rooms.size()].get_center())


func _update_boss(e: Enemy, delta: float) -> void:
	if dead:
		return
	var to_p := p_pos - e.pos
	var d := to_p.length()
	if e.kind == "slasher":
		e.stun = 0.0   # nothing stops him
	if e.stun > 0.0:
		e.stun -= delta
		return
	e.ability -= delta
	if d > 1.0 and e.mode != "charge":
		e.facing = e.facing.slerp(to_p / d, minf(1.0, delta * 7.0)).normalized()

	match e.mode:
		"vanish":
			e.mode_t -= delta
			if e.mode_t <= 0.0:
				e.mode = ""
				e.pos = _boss_spot(80.0)
				_burst(e.pos, Color(0.9, 0.9, 0.95, 0.6), 30, 140.0, 3.0)
				audio.play("laugh", e.pos, 0.0)
				e.cd = 0.0
			return
		"telegraph":
			e.mode_t -= delta
			if e.mode_t <= 0.0:
				e.mode = "charge"
				e.mode_t = 0.55
				audio.play("boss_roar", e.pos, -2.0, 0.1)
			return
		"charge":
			e.mode_t -= delta
			var before := e.pos
			e.pos = _move(e.pos, e.charge_dir * 430.0 * delta, e.radius)
			if e.pos.distance_to(before) < 2.0:
				e.mode_t = 0.0
				shake = maxf(shake, 6.0)
			if not e.charge_hit and e.pos.distance_to(p_pos) < e.radius + PLAYER_R + 4.0:
				e.charge_hit = true
				_hurt_player(randi_range(e.dmg_max, e.dmg_max + 8), true)
				p_pos = _move(p_pos, e.charge_dir * 28.0, PLAYER_R)
				shake = maxf(shake, 10.0)
			if e.mode_t <= 0.0:
				e.mode = ""
			return
		"fade":
			e.mode_t -= delta
			_boss_chase(e, 170.0, delta, to_p, d)
			if e.mode_t <= 0.0 or d < 45.0:
				e.mode = ""
				var behind := p_pos - facing * 30.0
				if not _blocked(behind, e.radius):
					e.pos = behind
				e.windup = 0.25
				e.cd = 0.9
				audio.play("dream_laugh", e.pos, 0.0)
			return

	if e.ability <= 0.0:
		match e.kind:
			"clown":
				if randf() < 0.5:
					e.mode = "vanish"
					e.mode_t = 0.9
					e.windup = 0.0
					_burst(e.pos, Color(0.9, 0.9, 0.95, 0.6), 30, 140.0, 3.0)
					audio.play("teleport", e.pos, 0.0)
					if target_enemy == e:
						target_enemy = null
				else:
					for k in 3:
						var pr := Projectile.new()
						pr.style = "balloon"
						pr.friendly = false
						pr.pos = e.pos + Vector2.from_angle(randf() * TAU) * 14.0
						pr.vel = Vector2.from_angle(randf() * TAU) * 40.0
						pr.dmg = 10 + depth * 3
						pr.radius = 9.0
						pr.life = 7.0
						pr.color = Color(0.85, 0.06, 0.05)
						projectiles.append(pr)
					audio.play("laugh", e.pos, 0.0)
				e.ability = randf_range(5.0, 7.0)
			"slasher":
				if d < 330.0 and d > 60.0 and _los(e.pos, p_pos):
					e.mode = "telegraph"
					e.mode_t = 0.8
					e.charge_dir = to_p / d
					e.charge_hit = false
					e.ability = randf_range(5.5, 7.5)
					return
				e.ability = 1.0
			"dream":
				if randf() < 0.55:
					e.mode = "fade"
					e.mode_t = 3.0
					audio.play("teleport", e.pos, -4.0)
				else:
					nightmare_t = 5.0
					audio.play_ui("dream_laugh", 0.0)
					_say("You feel yourself falling asleep...")
				e.ability = randf_range(6.0, 8.0)

	if e.windup > 0.0:
		e.windup -= delta
		if e.windup <= 0.0:
			audio.play("blades" if e.kind == "dream" else "swing", e.pos, 0.0)
			if d <= e.radius + PLAYER_R + REACH + 8.0:
				_hurt_player(randi_range(e.dmg_min, e.dmg_max))
		return
	if d <= e.radius + PLAYER_R + REACH * 0.7:
		if e.cd <= 0.0:
			match e.kind:
				"clown":
					e.windup = 0.45
					e.cd = 1.1
				"slasher":
					e.windup = 0.6
					e.cd = 1.5
				_:
					e.windup = 0.3
					e.cd = 0.75
			audio.play("attack", e.pos, -3.0, 0.1)
		return
	var spd := e.speed
	if e.kind == "slasher" and e.hp < e.max_hp * 0.5:
		spd *= 1.3   # enraged
	_boss_chase(e, spd, delta, to_p, d)


## Below half life the Slasher's mask is knocked off, showing what's underneath.
func _unmask(e: Enemy, dir: Vector2) -> void:
	e.unmasked = true
	var head := e.pos + e.facing * e.radius * 0.12
	fallen_mask = {"pos": _move(head, dir * 34.0 + Vector2(randf_range(-8, 8), randf_range(-8, 8)), 6.0),
		"ang": randf() * TAU}
	_burst(head, Color(0.92, 0.9, 0.82), 14, 160.0, 2.0)
	_blood(head, dir, 14, Color(0.32, 0.03, 0.02))
	audio.play("boss_roar", e.pos, 2.0)
	audio.play("block", e.pos, -2.0)
	shake = maxf(shake, 10.0)
	e.stun = 0.0
	_say("The mask cracks off... what lies beneath is no longer human.")


func _boss_chase(e: Enemy, spd: float, delta: float, to_p: Vector2, d: float) -> void:
	e.repath -= delta
	if _los(e.pos, p_pos):
		e.path.clear()
		e.pos = _move(e.pos, to_p / maxf(d, 0.01) * spd * delta, e.radius)
	else:
		if e.repath <= 0.0 or e.path.is_empty():
			e.repath = 0.4
			e.path = _find_path(e.pos, p_pos)
		if not e.path.is_empty():
			var tw := e.path[0] - e.pos
			if tw.length() < 6.0:
				e.path.remove_at(0)
			else:
				e.pos = _move(e.pos, tw.normalized() * spd * delta, e.radius)


func _boss_defeated(e: Enemy) -> void:
	boss_dead = true
	audio.set_boss(false)
	audio.play_ui("levelup", -2.0)
	nightmare_t = 0.0
	shake = 14.0
	stat_points += 3
	_float(p_pos + Vector2(0, -34), "+3 ATTRIBUTE POINTS", Color(1.0, 0.85, 0.3), 22)
	if rush:
		rush_wave += 1
		_save_rush()
		if rush_wave >= BOSSES.size():
			rush_won = true
			rush_end_t = 6.0
			_say("Boss Rush complete!")
		else:
			rush_break = RUSH_BREAK
			boss_spawned = false
			boss_dead = false
			_say("%s is defeated! +3 points" % e.name.split(",")[0])
			_spawn_merchant()
	else:
		_say("%s is defeated! +3 attribute points (press I). The way down is open." % e.name.split(",")[0])
		_spawn_merchant()
	for k in 2:
		var d := Drop.new()
		d.kind = "weapon"
		d.weapon = _random_weapon()
		d.weapon.bonus += 1
		d.pos = e.pos + Vector2.from_angle(randf() * TAU) * 16.0
		if _blocked(d.pos, 4):
			d.pos = e.pos
		drops.append(d)
	for k in 5:
		_add_drop("gold", e.pos + Vector2.from_angle(randf() * TAU) * randf_range(10, 26), randi_range(15, 30) * depth)
	_add_drop("hp", e.pos + Vector2(14, 0), 1)
	_add_drop("hp", e.pos + Vector2(-14, 0), 1)
	if hero == "knight":
		_add_drop("bolts", e.pos + Vector2(0, 14), 15)
	else:
		_add_drop("mp", e.pos + Vector2(0, 14), 1)
		_add_drop("mp", e.pos + Vector2(0, -14), 1)


# ================================================================ merchant & store

func _spawn_merchant() -> void:
	merchant_pos = _boss_spot(70.0)
	merchant_on = true
	if merchant_light == null:
		merchant_light = _proj_light(Color(1.0, 0.72, 0.38), 0.7, 1.1)
	merchant_light.position = merchant_pos + Vector2(10, -12)
	shop_stock.clear()
	for i in 4:
		var w := _random_weapon()
		for attempt in 10:
			if can_use(w):
				break
			w = _random_weapon()
		if i == 0:
			w = _make_melee(w.base, w.bonus + 1) if not w.ranged else _make_crossbow(w.base, w.bonus + 1)
		shop_stock.append(w)
	_burst(merchant_pos, Color(1.0, 0.8, 0.4), 30, 120.0, 2.5, true)
	audio.play("teleport", merchant_pos, -4.0)
	_float(merchant_pos + Vector2(0, -30), "A merchant appears — click to trade", Color(1.0, 0.85, 0.5), 14)


func _merchant_leave(fx := true) -> void:
	if merchant_on and fx:
		_burst(merchant_pos, Color(1.0, 0.8, 0.4), 24, 110.0, 2.5, true)
	merchant_on = false
	shop_open = false
	target_merchant = false
	if merchant_light:
		merchant_light.queue_free()
		merchant_light = null


func _open_shop() -> void:
	shop_open = true
	inv_open = true
	audio.play_ui("coin", -8.0)


## Boss Rush: done shopping, bring on the next boss.
func _rush_ready() -> void:
	_merchant_leave()
	inv_open = false
	_say("Get ready...")


func weapon_price(w: Weapon) -> int:
	var dps := (w.dmg_min + w.dmg_max) / 2.0 / w.speed
	return int(dps * (6.0 if w.ranged else 4.0)) + w.bonus * 30


func sell_value(price: int) -> int:
	return maxi(1, int(price * SELL_RATE))


## Supplies and scrolls on sale for this class, in display order.
func shop_items() -> Array:
	if hero == "knight":
		return ["hp", "bolts"] + SPELL_ORDER
	return ["hp", "mp"] + PALADIN_SPELLS


func item_name(k: String) -> String:
	return SUPPLY[k][0] if SUPPLY.has(k) else SPELLS[k].name


func item_price(k: String) -> int:
	if SUPPLY.has(k):
		return SUPPLY[k][1]
	# A scroll costs more for each level you already have in its spell.
	return int(SPELLS[k].price * (1.0 + 0.6 * spell_lvl.get(k, 0)))


## Spell scrolls are read on the spot, so they can't be resold.
func can_sell(k: String) -> bool:
	return SUPPLY.has(k)


func item_owned(k: String) -> int:
	match k:
		"hp": return hp_pots
		"mp": return mp_pots
		"bolts": return bolts
	return spell_lvl.get(k, 0)


func _shop_click(button: int, slot: Dictionary) -> void:
	if button != MOUSE_BUTTON_LEFT or slot.is_empty():
		return
	match slot.type:
		"stock":
			var w: Weapon = shop_stock[slot.i]
			if w == null:
				return
			var price := weapon_price(w)
			var free := bag.find(null)
			if gold < price:
				_float(p_pos, "Not enough gold", Color(1.0, 0.45, 0.35), 14)
			elif free == -1:
				_float(p_pos, "Backpack full", Color(1.0, 0.45, 0.35), 14)
			else:
				gold -= price
				bag[free] = w
				shop_stock[slot.i] = null
				audio.play_ui("coin", -6.0, 0.9)
				_float(p_pos, "Bought %s — in your backpack" % w.label(), Color(0.9, 0.85, 0.6), 14)
		"buy":
			var k: String = slot.k
			var price := item_price(k)
			var full: bool = (k == "hp" and hp_pots >= MAX_POTIONS) or (k == "mp" and mp_pots >= MAX_POTIONS) or (k == "bolts" and bolts >= max_bolts) \
				or spell_lvl.get(k, 0) >= SPELL_MAX
			if gold < price:
				_float(p_pos, "Not enough gold", Color(1.0, 0.45, 0.35), 14)
			elif full:
				_float(p_pos, "You can't carry more", Color(1.0, 0.45, 0.35), 14)
			else:
				gold -= price
				match k:
					"hp": hp_pots += 1
					"mp": mp_pots += 1
					"bolts": bolts = mini(max_bolts, bolts + 15)
					_: _read_scroll(k)
				audio.play_ui("coin", -6.0, 0.9)
		"sell":
			var k: String = slot.k
			var have := item_owned(k)
			if not can_sell(k) or have < (15 if k == "bolts" else 1):
				return
			match k:
				"hp": hp_pots -= 1
				"mp": mp_pots -= 1
				"bolts": bolts -= 15
			gold += sell_value(item_price(k))
			audio.play_ui("coin", -6.0, 1.1)
		"leave":
			if rush:
				_rush_ready()
			else:
				shop_open = false
				inv_open = false


# ================================================================ spell scrolls

## Knight: cast the active spell (no mana; each spell recharges on its own).
func _knight_cast(at := Vector2.INF) -> void:
	if dead or shop_open or hero != "knight":
		return
	var id := selected_spell
	if id == "":
		_float(p_pos, "You know no spells — buy scrolls from the merchant", Color(0.8, 0.7, 0.5), 13)
		return
	if spell_cd.get(id, 0.0) > 0.0:
		_float(p_pos, "%s recharging (%.0fs)" % [SPELLS[id].name, ceilf(spell_cd[id])], Color(0.7, 0.7, 0.8), 13)
		return
	var m := get_global_mouse_position() if at == Vector2.INF else at
	if _cast_spell(id, spell_lvl[id], m):
		spell_cd[id] = knight_cd(id)
		facing = (m - p_pos).normalized() if m != p_pos else facing


func knight_cd(id: String) -> float:
	return KNIGHT_CD[id] * (1.0 - 0.08 * (spell_lvl.get(id, 1) - 1))


## Learn a spell from a scroll, or raise its level.
func _read_scroll(id: String) -> void:
	var lv: int = spell_lvl.get(id, 0) + 1
	spell_lvl[id] = lv
	audio.play_ui("levelup", -6.0)
	_burst(p_pos, SPELLS[id].col, 30, 140.0, 2.5, true)
	if lv == 1:
		selected_spell = id
		_float(p_pos + Vector2(0, -24), "Learned %s! (selected — %s to cast)" % [SPELLS[id].name, "RMB" if hero == "paladin" else "F / middle mouse"], SPELLS[id].col, 15)
	else:
		_float(p_pos + Vector2(0, -24), "%s rises to level %d!" % [SPELLS[id].name, lv], SPELLS[id].col, 15)


func select_spell(id: String) -> void:
	if not spell_lvl.has(id):
		_float(p_pos, "You don't know %s — find its scroll" % SPELLS[id].name, Color(0.8, 0.7, 0.5), 13)
		return
	selected_spell = id
	_float(p_pos, "%s  (Lv %d)" % [SPELLS[id].name, spell_lvl[id]], SPELLS[id].col, 13)


func spell_order() -> Array:
	return PALADIN_SPELLS if hero == "paladin" else SPELL_ORDER


func spell_key(id: String) -> String:
	return str(spell_order().find(id) + 3)


## Mouse wheel: step to the next/previous known spell.
func cycle_spell(step: int) -> void:
	var known: Array = spell_order().filter(func(id): return spell_lvl.has(id))
	if known.is_empty():
		_float(p_pos, "You know no spells — buy scrolls from the merchant", Color(0.8, 0.7, 0.5), 13)
		return
	var i := known.find(selected_spell)
	select_spell(known[posmod(i + step, known.size())] if i != -1 else known[0])


## What a spell does at a given level (for tooltips and the store).
func spell_desc(id: String, lvl: int) -> String:
	match id:
		"holy": return "%d-%d holy damage" % [9 + int(level * 2.5) + (lvl - 1) * 5, 14 + int(level * 2.5) + (lvl - 1) * 5]
		"fireball": return "%d fire damage in a %d radius" % [14 + lvl * 10 + depth * 2, int(56 + lvl * 8)]
		"frost": return "%d damage, freezes %.1fs, radius %d" % [6 + lvl * 6 + depth * 2, 2.0 + 0.5 * lvl, int(95 + lvl * 15)]
		"lightning": return "%d damage, arcs through %d enemies" % [12 + lvl * 8 + depth * 2, mini(6, lvl + 2) + 1]
		"ward": return "-%d%% damage taken for %ds" % [roundi((1.0 - clampf(0.6 - 0.07 * lvl, 0.25, 1.0)) * 100), int(6 + lvl * 3)]
	return ""


## The effect itself. Returns false if it couldn't be cast (no target).
func _cast_spell(id: String, lvl: int, m: Vector2) -> bool:
	var dir := (m - p_pos).normalized()
	if dir == Vector2.ZERO:
		dir = facing
	match id:
		"fireball":
			var pr := Projectile.new()
			pr.friendly = true
			pr.pos = p_pos + dir * 14.0
			pr.vel = dir * 400.0
			pr.dmg = 14 + lvl * 10 + depth * 2
			pr.color = Color(1.0, 0.45, 0.1)
			pr.radius = 7.0
			pr.style = "fire"
			pr.blast = 56.0 + lvl * 8.0
			pr.light = _proj_light(pr.color, 0.6, 1.5)
			projectiles.append(pr)
			audio.play("magic_cast", p_pos, -1.0)
		"frost":
			var fr := 95.0 + lvl * 15.0
			_ring(p_pos, fr, Color(0.5, 0.85, 1.0))
			_ring(p_pos, 80.0, Color(0.7, 0.95, 1.0))
			_burst(p_pos, Color(0.6, 0.9, 1.0), 50, 280.0, 3.0, true)
			audio.play("magic_hit", p_pos, 2.0)
			for e in enemies.duplicate():
				if e.hp > 0.0 and e.pos.distance_to(p_pos) < fr + e.radius:
					e.stun = maxf(e.stun, (1.0 + 0.25 * lvl) if e.boss else (2.0 + 0.5 * lvl))
					e.chill = 3.0
					_hurt_enemy(e, 6 + lvl * 6 + depth * 2, (e.pos - p_pos).normalized(), "magic")
		"lightning":
			var first: Enemy = null
			var best := INF
			for e in enemies:
				if e.hp > 0.0 and e.mode != "vanish" and e.pos.distance_to(p_pos) < 340.0 and _los(p_pos, e.pos):
					var dm := e.pos.distance_to(m)
					if dm < best:
						best = dm
						first = e
			if first == null:
				_float(p_pos, "No target in range", Color(0.8, 0.7, 0.5), 13)
				return false
			var chain: Array[Enemy] = [first]
			for k in mini(6, lvl + 2):
				var cur: Enemy = chain.back()
				var nxt: Enemy = null
				var nd := 160.0
				for e in enemies:
					if e.hp > 0.0 and not chain.has(e) and e.pos.distance_to(cur.pos) < nd and _los(cur.pos, e.pos):
						nd = e.pos.distance_to(cur.pos)
						nxt = e
				if nxt == null:
					break
				chain.append(nxt)
			var pts := PackedVector2Array([p_pos])
			for e in chain:
				pts.append(e.pos)
			zaps.append({"pts": _jagged(pts), "life": 0.35})
			audio.play("magic_hit", first.pos, 2.0)
			audio.play("magic_cast", p_pos, -3.0)
			var dmg := 12 + lvl * 8 + depth * 2
			for i in chain.size():
				var e := chain[i]
				_burst(e.pos, Color(0.7, 0.8, 1.0), 10, 140.0, 2.0, true)
				_hurt_enemy(e, int(dmg * pow(0.85, i)), dir, "magic")
		"ward":
			ward_t = 6.0 + lvl * 3.0
			ward_mult = clampf(0.6 - 0.07 * lvl, 0.25, 1.0)
			audio.play("heal", p_pos, -2.0)
			_ring(p_pos, 40.0, Color(1.0, 0.85, 0.35))
			_burst(p_pos, Color(1.0, 0.85, 0.4), 30, 120.0, 2.5, true)
	facing = dir
	return true


## A crackling path through the given points.
func _jagged(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var n := (b - a).orthogonal().normalized()
		var steps := maxi(3, int(a.distance_to(b) / 14.0))
		for k in range(1, steps):
			out.append(a.lerp(b, float(k) / steps) + n * randf_range(-9.0, 9.0))
		out.append(b)
	return out


func _explode(pos: Vector2, r: float, dmg: int) -> void:
	audio.play("explode", pos, 0.0)
	_ring(pos, r, Color(1.0, 0.5, 0.15))
	_burst(pos, Color(1.0, 0.55, 0.15), 45, 260.0, 4.0, true)
	_burst(pos, Color(0.25, 0.2, 0.18, 0.8), 20, 90.0, 4.0)
	shake = maxf(shake, 8.0)
	for k in 4:
		_decal(pos + Vector2.from_angle(randf() * TAU) * randf_range(0, r * 0.35), randf_range(8, 16), Color(0.05, 0.04, 0.035))
	for e in enemies.duplicate():
		if e.hp > 0.0 and e.pos.distance_to(pos) < r + e.radius:
			_hurt_enemy(e, dmg, (e.pos - pos).normalized(), "blast")


func _load_rush() -> void:
	rush_best = 0
	rush_best_time = 0.0
	var cf := ConfigFile.new()
	if cf.load(RUSH_SAVE) == OK:
		rush_best = cf.get_value(_rush_section(), "bosses", 0)
		rush_best_time = cf.get_value(_rush_section(), "time", 0.0)


## Records are kept per difficulty ("best" is Normal, as before difficulties existed).
func _rush_section() -> String:
	return "best" if difficulty == 1 else "best_" + diff().name.to_lower()


func _save_rush() -> void:
	if run_debug:
		return
	if rush_wave < rush_best or (rush_wave == rush_best and rush_time >= rush_best_time and rush_best_time > 0.0):
		return
	rush_best = rush_wave
	rush_best_time = rush_time
	var cf := ConfigFile.new()
	cf.load(RUSH_SAVE)
	cf.set_value(_rush_section(), "bosses", rush_best)
	cf.set_value(_rush_section(), "time", rush_best_time)
	cf.save(RUSH_SAVE)


func _draw_boss(e: Enemy, a: float) -> void:
	if e.mode == "vanish":
		return
	if e.kind == "dream" and e.mode == "fade":
		a *= 0.12
	var f := e.flash
	var r := e.radius
	var p := e.pos
	var fwd := e.facing
	var side := fwd.orthogonal()
	var ld := _light_dir(p)
	var walk := sin(e.anim * (18.0 if e.mode == "charge" else 6.0))
	_soft_shadow(p + Vector2(2, r * 0.55), r, a)
	for s in [-1.0, 1.0]:
		_ball(p + side * s * r * 0.38 + fwd * walk * s * r * 0.4, r * 0.27, _shade(e.pants.darkened(0.35), f), ld, a)

	var lunge := 0.35 if e.windup > 0.0 else 0.0
	var hands := []
	for s in [-1.0, 1.0]:
		var shoulder: Vector2 = p + side * s * r * 0.7
		var arm_dir: Vector2 = fwd.rotated(-s * 0.35)
		if s > 0:
			arm_dir = fwd.rotated(-0.9 + (1.6 if e.windup > 0.0 else 0.0))   # weapon arm swings
		var hand: Vector2 = shoulder + arm_dir * r * (0.85 + lunge)
		_limb(shoulder, hand, r * 0.34, _shade(e.shirt, f), ld, a)
		hands.append([hand, arm_dir])
	_torso(p, fwd, r, Vector2(0.7, 1.0), _shade(e.shirt, f), ld, a)
	var head := p + fwd * r * 0.12
	var hr := r * 0.42

	match e.kind:
		"clown":
			for k in 3:   # pompoms down the baggy suit
				_ball(p + fwd * r * 0.38 + side * (k - 1) * r * 0.28, r * 0.13, Color(1.0, 0.45, 0.08), ld, a)
			for k in 12:  # ruffled collar
				_ball(head + Vector2.from_angle(k * TAU / 12.0) * hr * 1.25, hr * 0.38, _shade(Color(0.92, 0.9, 0.82), f), ld, a)
			_ball(head, hr, _shade(e.skin, f), ld, a, "skin")
			for s in [-1.0, 1.0]:   # wild orange tufts
				for k in 3:
					_ball(head + side * s * hr * (0.9 + k * 0.15) - fwd * hr * (0.3 - k * 0.25), hr * 0.35, Color(0.95, 0.38, 0.05), ld, a)
			_ball(head + fwd * hr * 0.8, hr * 0.3, Color(0.9, 0.04, 0.04), ld, a, "metal")   # nose
			draw_arc(head + fwd * hr * 0.35, hr * 0.55, fwd.angle() - 0.9, fwd.angle() + 0.9, 10, Color(0.75, 0.03, 0.03, a), 1.6)
			for h in hands:   # white gloves
				_ball(h[0], r * 0.2, Color(0.95, 0.95, 0.95), ld, a)
			var hand0: Vector2 = hands[0][0]
			var bp := hand0 + Vector2(-6 + sin(e.anim * 1.5) * 3, -24)
			draw_line(hand0, bp + Vector2(0, 7), Color(0.85, 0.85, 0.85, 0.7 * a), 0.7)
			_ball(bp, 8.0, Color(0.85, 0.06, 0.05), ld, a, "metal")
		"slasher":
			for h in hands:
				_ball(h[0], r * 0.2, _shade(e.skin.darkened(0.2), f), ld, a, "skin")
			var hand: Vector2 = hands[1][0]
			var dir: Vector2 = hands[1][1]
			var n := dir.orthogonal()
			var b0 := hand + dir * r * 0.3
			var b1 := b0 + dir * r * 1.6
			draw_line(hand - dir * 3.0, b0, Color(0.25, 0.16, 0.09, a), 4.0)
			draw_colored_polygon(PackedVector2Array([b0 - n * 2.0, b1 - n * 1.0, b1 + n * 2.5, b0 + n * 3.0]), Color(0.48, 0.48, 0.47, a))
			draw_line(b0 - n * 2.0, b1 - n * 1.0, Color(0.85, 0.86, 0.88, a), 1.0)
			draw_circle(b0.lerp(b1, 0.6), 2.0, Color(0.35, 0.06, 0.04, a))
			if e.unmasked:
				_draw_ruined_face(head, hr, fwd, side, ld, a, f)
				return
			# Hockey mask: holes, eye slits, red chevrons, strap
			_ball(head, hr * 1.05, _shade(Color(0.92, 0.9, 0.82), f), ld, a, "bone")
			draw_arc(head, hr * 1.05, fwd.angle() + PI - 1.0, fwd.angle() + PI + 1.0, 10, Color(0.1, 0.1, 0.1, a), 1.5)
			for hx in [-1.0, 0.0, 1.0]:
				for hy in [0.0, 1.0, 2.0]:
					if hx != 0.0 or hy != 0.0:
						draw_circle(head + fwd * hr * (0.1 + hy * 0.25) + side * hx * hr * 0.33, 0.8, Color(0.05, 0.05, 0.05, a))
			for s in [-1.0, 1.0]:
				draw_circle(head + fwd * hr * 0.5 + side * s * hr * 0.42, hr * 0.18, Color(0.02, 0.02, 0.02, a))
				var c0: Vector2 = head + fwd * hr * 0.05 + side * s * hr * 0.55
				draw_polyline(PackedVector2Array([c0 + fwd * 2.0 - side * s * 1.5, c0, c0 + fwd * 2.0 + side * s * 1.5]), Color(0.75, 0.05, 0.04, a), 1.2)
		"dream":
			for k in range(-3, 4):   # striped sweater
				var w := sqrt(maxf(0.0, 1.0 - pow(k / 3.6, 2.0))) * r * 0.85
				var c := p + fwd * k * r * 0.17
				draw_line(c - side * w, c + side * w, Color(0.08, 0.22, 0.1, a * 0.9), 2.0)
			_ball(hands[0][0], r * 0.2, _shade(e.skin, f), ld, a, "skin")
			var hand: Vector2 = hands[1][0]
			var dir: Vector2 = hands[1][1]
			_ball(hand, r * 0.23, Color(0.35, 0.22, 0.12), ld, a)   # leather glove
			for k in 4:
				var bd := dir.rotated((k - 1.5) * 0.12)
				var tip := hand + bd * r * (1.2 + (0.3 if e.windup > 0.0 else 0.0))
				draw_line(hand + bd * r * 0.2 + dir.orthogonal() * (k - 1.5) * 1.6, tip, Color(0.82, 0.84, 0.88, a), 1.2)
			_ball(head, hr, _shade(e.skin, f), ld, a, "skin")
			for k in 4:   # burn scars
				draw_circle(head + Vector2.from_angle(k * 1.7 + 0.5) * hr * 0.5, hr * 0.18, Color(0.35, 0.12, 0.1, a * 0.8))
			var hat := head - fwd * hr * 0.45
			draw_circle(hat + Vector2(1.5, 2.0), hr * 1.6, Color(0, 0, 0, 0.25 * a))
			_ball(hat, hr * 1.55, _shade(Color(0.3, 0.21, 0.13), f), ld, a)      # brim
			_ball(hat - fwd * hr * 0.05, hr * 0.95, _shade(Color(0.37, 0.27, 0.17), f), ld, a)   # crown
			draw_arc(hat - fwd * hr * 0.05, hr * 0.6, 0, TAU, 14, Color(0.18, 0.12, 0.07, a), 1.2)


## The Slasher without his mask: a lopsided, swollen skull with one bulging eye, a sunken
## socket, a lipless grin, sores and a few strands of lank hair.
func _draw_ruined_face(head: Vector2, hr: float, fwd: Vector2, side: Vector2, ld: Vector2, a: float, f: float) -> void:
	hr *= 1.15
	var flesh := _shade(Color(0.88, 0.76, 0.62), f)
	var sick := _shade(Color(0.8, 0.78, 0.5), f)
	_ball(head, hr * 1.05, flesh, ld, a, "skin")
	_ball(head - fwd * hr * 0.3 + side * hr * 0.45, hr * 0.62, sick, ld, a, "skin")    # swollen lump
	_ball(head + fwd * hr * 0.2 - side * hr * 0.55, hr * 0.42, flesh.darkened(0.1), ld, a, "skin")
	_ball(head + fwd * hr * 0.55 + side * hr * 0.1, hr * 0.5, sick.lerp(flesh, 0.5), ld, a, "skin")   # drooping cheek
	# Sores and scars
	for k in 6:
		var sp := head + Vector2.from_angle(k * 2.1 + 0.3) * hr * (0.35 + 0.12 * (k % 3))
		draw_circle(sp, hr * (0.1 + 0.05 * (k % 2)), Color(0.55, 0.1, 0.12, 0.95 * a))
		draw_circle(sp, hr * 0.04, Color(0.75, 0.62, 0.3, 0.7 * a))
	draw_line(head - side * hr * 0.7 - fwd * hr * 0.2, head + side * hr * 0.1 + fwd * hr * 0.4, Color(0.35, 0.1, 0.1, 0.8 * a), 1.2)
	# Lank hair strands on the back of the skull
	for k in 5:
		var hb := head - fwd * hr * 0.75 + side * (k - 2) * hr * 0.28
		draw_line(hb, hb - fwd * hr * (0.4 + 0.15 * (k % 2)) + side * (k - 2) * 1.2, Color(0.16, 0.13, 0.1, 0.9 * a), 1.0)
	# Bulging bloodshot eye on one side, a dark sunken socket on the other
	var eye := head + fwd * hr * 0.62 + side * hr * 0.42
	_ball(eye, hr * 0.3, Color(0.92, 0.85, 0.72), ld, a, "bone")
	draw_arc(eye, hr * 0.24, 0, TAU, 10, Color(0.75, 0.1, 0.08, 0.6 * a), 0.8)
	draw_circle(eye + fwd * hr * 0.12, hr * 0.11, Color(0.12, 0.08, 0.05, a))
	var socket := head + fwd * hr * 0.6 - side * hr * 0.4
	draw_circle(socket, hr * 0.22, Color(0.08, 0.02, 0.02, a))
	draw_circle(socket + fwd * hr * 0.05, hr * 0.12, Color(0.2, 0.03, 0.03, a))
	# Lipless grin: gums and crooked teeth
	var mouth := head + fwd * hr * 0.95
	draw_arc(mouth, hr * 0.42, fwd.angle() - 1.1, fwd.angle() + 0.9, 12, Color(0.4, 0.08, 0.08, a), hr * 0.24)
	for k in 7:
		var ta := fwd.angle() - 1.0 + k * 0.28
		var tp := mouth + Vector2.from_angle(ta) * hr * 0.42
		draw_circle(tp, hr * (0.07 + 0.03 * ((k * 5) % 3)), Color(0.82, 0.76, 0.55, a))


func _draw_fallen_mask() -> void:
	var p: Vector2 = fallen_mask.pos
	var a := clampf(_vis(p) * 2.5, 0.0, 1.0)
	if a <= 0.0:
		return
	draw_set_transform(p, fallen_mask.ang, Vector2(1.0, 1.25))
	draw_circle(Vector2(1, 2), 8.5, Color(0, 0, 0, 0.35 * a))
	_ball(Vector2.ZERO, 8.0, Color(0.9, 0.88, 0.8), _light_dir(p).rotated(-fallen_mask.ang), a, "bone")
	for s in [-1.0, 1.0]:
		draw_circle(Vector2(s * 3.0, -2.0), 1.5, Color(0.03, 0.03, 0.03, a))
		draw_polyline(PackedVector2Array([Vector2(s * 4.5, -6.0), Vector2(s * 5.8, -4.6), Vector2(s * 4.5, -3.2)]), Color(0.75, 0.05, 0.04, a), 1.0)
	for hy in [1.0, 3.0, 5.0]:
		for hx in [-2.0, 0.0, 2.0]:
			draw_circle(Vector2(hx, hy), 0.5, Color(0.05, 0.05, 0.05, a))
	draw_line(Vector2(-6, 3), Vector2(4, -6), Color(0.3, 0.25, 0.2, a), 0.8)   # crack
	draw_set_transform(Vector2.ZERO)


# ================================================================ drawing
# Two passes: _draw() is the lit world (affected by CanvasModulate + 2D lights, so torchlight and
# wall shadows fall on it naturally); _draw_overlay() is an unlit world-space layer for things that
# glow or must stay readable — flames, magic, glowing eyes, selection rings and text.

func _draw() -> void:
	var vs := get_viewport_rect().size / camera.zoom
	var tl := _cell(camera.position - vs * 0.5) - Vector2i(1, 1)
	var br := _cell(camera.position + vs * 0.5) + Vector2i(1, 1)
	var menu := state == "menu"
	var TS := 64.0
	var tint: Color = theme().floor

	for y in range(maxi(tl.y, 0), mini(br.y, H - 1) + 1):
		for x in range(maxi(tl.x, 0), mini(br.x, W - 1) + 1):
			var i := y * W + x
			if explored[i] == 0 and not menu:
				continue
			var v := int(tile_var[i]) if tile_var.size() > i else 0
			var rect := Rect2(x * T, y * T, T, T)
			if grid[i] == 0:
				draw_texture_rect_region(stone_tex, rect, Rect2((v % 8) * TS, 0, TS, TS), tint, v >= 8)
				# Ambient occlusion where the floor meets a wall.
				if _solid(Vector2i(x, y - 1)):
					draw_rect(Rect2(x * T, y * T, T, 6), Color(0, 0, 0, 0.34))
					draw_rect(Rect2(x * T, y * T + 6, T, 6), Color(0, 0, 0, 0.14))
				if _solid(Vector2i(x - 1, y)):
					draw_rect(Rect2(x * T, y * T, 5, T), Color(0, 0, 0, 0.26))
				if _solid(Vector2i(x + 1, y)):
					draw_rect(Rect2(x * T + T - 5, y * T, 5, T), Color(0, 0, 0, 0.26))
				if _solid(Vector2i(x, y + 1)):
					draw_rect(Rect2(x * T, y * T + T - 3, T, 3), Color(0, 0, 0, 0.3))
			else:
				var vv := v % 8
				if y + 1 < H and grid[(y + 1) * W + x] == 0:
					var top_h := T * 0.45
					draw_texture_rect_region(stone_tex, Rect2(x * T, y * T, T, top_h), Rect2(vv * TS, TS, TS, TS * 0.45), tint)
					draw_texture_rect_region(stone_tex, Rect2(x * T, y * T + top_h, T, T - top_h), Rect2(vv * TS, TS * 2.0, TS, FACE_TEX_H), tint)
				else:
					draw_texture_rect_region(stone_tex, rect, Rect2(vv * TS, TS, TS, TS), tint)
	if menu:
		env.draw_under(self)
		env.draw_over(self)
		return

	# Stairs: steps descending into darkness.
	var sc := _cell(stairs_pos)
	if explored[sc.y * W + sc.x] == 1:
		var sr := Rect2(stairs_pos - Vector2(T, T) * 0.5, Vector2(T, T))
		draw_rect(sr.grow(1), Color(0.02, 0.02, 0.02))
		for k in 5:
			var yy := sr.position.y + k * T / 5.0
			var sh := 0.34 - k * 0.065
			draw_rect(Rect2(sr.position.x + 2 + k, yy, T - 4 - k * 2, T / 5.0 - 1), Color(sh, sh * 0.93, sh * 0.85))
			draw_line(Vector2(sr.position.x + 2 + k, yy), Vector2(sr.end.x - 2 - k, yy), Color(0.52, 0.47, 0.41), 1.0)

	env.draw_under(self)

	# Blood stains: glossy pools and droplets.
	var now := Time.get_ticks_msec() / 1000.0
	var view := Rect2(camera.position - vs * 0.5, vs).grow(40.0)
	for dc in decals:
		var dp: Vector2 = dc.pos
		if not view.has_point(dp):
			continue
		var dcell := _cell(dp)
		if explored[clampi(dcell.y, 0, H - 1) * W + clampi(dcell.x, 0, W - 1)] == 0:
			continue
		var r: float = dc.r
		if dc.grow > 0.0:
			r *= clampf((now - dc.born) / dc.grow, 0.15, 1.0)
		var col: Color = dc.col
		draw_circle(dp, r, Color(col.darkened(0.25), 0.9))
		draw_circle(dp + Vector2(-0.2, -0.2) * r, r * 0.75, Color(col, 0.9))
		if r > 4.0:
			draw_circle(dp + Vector2(-0.35, -0.4) * r, r * 0.18, Color(col.lightened(0.35), 0.35))

	for c in corpses:
		_draw_corpse(c)
	if not fallen_mask.is_empty():
		_draw_fallen_mask()

	for d in drops:
		_draw_drop(d)

	env.draw_spiders(self)

	var sorted := enemies.duplicate()
	sorted.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for e in sorted:
		_draw_zombie(e)
	if merchant_on:
		_draw_merchant()

	if not dead:
		_draw_player()

	env.draw_over(self)

	for pr in projectiles:
		if _vis(pr.pos) <= 0.02 and not pr.friendly:
			continue
		match pr.style:
			"bolt":
				var dir := pr.vel.normalized()
				draw_line(pr.pos - dir * 12.0, pr.pos, Color(0.42, 0.3, 0.2), 2.0)
				draw_line(pr.pos - dir * 12.0, pr.pos - dir * 9.0, Color(0.75, 0.72, 0.65), 3.0)   # fletching
				draw_line(pr.pos - dir * 3.0, pr.pos + dir * 2.0, Color(0.8, 0.82, 0.85), 3.0)
			"balloon":
				var sway := sin(pr.life * 4.0) * 3.0
				draw_line(pr.pos + Vector2(0, 7), pr.pos + Vector2(sway, 22), Color(0.85, 0.85, 0.85, 0.7), 0.7)
				_ball(pr.pos, 7.5, Color(0.85, 0.06, 0.05), Vector2.ZERO, 1.0, "metal")
				draw_circle(pr.pos + Vector2(-2.5, -3), 1.6, Color(1, 0.7, 0.7, 0.7))
			"bile":
				draw_circle(pr.pos, pr.radius, Color(0.4, 0.55, 0.1))
				draw_circle(pr.pos + Vector2(-1, -1), pr.radius * 0.45, Color(0.7, 0.85, 0.35))

	for pt in particles:
		if pt.get("glow", false):
			continue
		var k: float = pt.life / pt.max
		draw_circle(pt.pos, pt.size * k, Color(pt.col, pt.col.a * k))


func _draw_overlay() -> void:
	var ov := overlay
	if state == "menu":
		env.draw_flames(ov)
		return
	env.draw_flames(ov)

	if click_marker_t > 0.0:
		var k := click_marker_t / 0.5
		ov.draw_arc(click_marker, 10.0 * (1.5 - k), 0, TAU, 20, Color(0.9, 0.8, 0.4, k), 2.0)

	for e in enemies:
		var a := clampf(_vis(e.pos) * 2.5, 0.0, 1.0)
		if a <= 0.0:
			continue
		var r := e.radius
		if e == hover_enemy or e == target_enemy:
			ov.draw_arc(e.pos + Vector2(0, r * 0.4), r + 6, 0, TAU, 28, Color(0.9, 0.2, 0.15, 0.8 * a), 1.5)
		if e.windup > 0.0:
			ov.draw_arc(e.pos, r + 7, 0, TAU, 28, Color(1.0, 0.3, 0.1, 0.6 * a), 2.0)
		if e.mode == "telegraph":
			var k := 1.0 - e.mode_t / 0.8
			ov.draw_line(e.pos, e.pos + e.charge_dir * 230.0, Color(1.5, 0.1, 0.05, 0.25 + 0.5 * k), 3.0 + 6.0 * k)
		if e.elite:
			ov.draw_circle(e.pos, r * 1.45, Color(1.0, 0.65, 0.2, 0.08 * a))
			ov.draw_arc(e.pos, r * 1.3, 0, TAU, 28, Color(1.0, 0.7, 0.25, 0.25 * a), 1.0)
		if e.chill > 0.0:
			ov.draw_circle(e.pos, r * 1.25, Color(0.5, 0.85, 1.2, 0.12 * a * minf(1.0, e.chill)))
			ov.draw_arc(e.pos, r * 1.25, 0, TAU, 24, Color(0.8, 1.2, 1.6, 0.5 * a * minf(1.0, e.chill)), 1.2)
		if e.kind == "red_spider":
			var eye := e.pos + e.facing * r * 0.65
			for s in [-1.0, 1.0]:
				ov.draw_circle(eye + e.facing.orthogonal() * s * r * 0.15, 0.9, Color(2.5, 0.2, 0.1, a))
			continue
		if e.stun > 0.0:
			for k in 3:
				var sa := e.anim * 5.0 + k * TAU / 3.0
				ov.draw_circle(e.pos + Vector2(cos(sa) * r * 0.7, -r - 4 + sin(sa) * 3), 1.6, Color(1, 1, 0.6, a))
		# Eyes glint in the dark.
		var hd := _zombie_head(e)
		var head: Vector2 = hd[0]
		var hr: float = hd[1]
		if e.kind != "armored":
			var side := e.facing.orthogonal()
			var eye := head + e.facing * hr * 0.62
			var ec := Color(1.0, 0.85, 0.4) if e.kind != "spitter" else Color(0.7, 1.0, 0.3)
			for s in [-1.0, 1.0]:
				ov.draw_circle(eye + side * s * hr * 0.42, 1.8, Color(ec, 0.18 * a))
				ov.draw_circle(eye + side * s * hr * 0.42, 0.9, Color(ec.r * 3.0, ec.g * 3.0, ec.b * 3.0, 0.85 * a))

	if not dead and swing > 0.0:
		var k := 1.0 - swing / swing_len
		var ang := facing.angle()
		ov.draw_arc(p_pos, 18.0 + _reach() * 0.8, ang + 1.3, ang + 1.3 - 2.6 * k, 16, Color(1, 1, 1, 0.22), 5.0)

	for pr in projectiles:
		if pr.style == "fire":
			var fl := 0.8 + 0.2 * sin(pr.life * 40.0)
			ov.draw_circle(pr.pos, pr.radius * 2.6 * fl, Color(1.0, 0.4, 0.1, 0.2))
			ov.draw_circle(pr.pos, pr.radius * fl, Color(3.0, 1.2, 0.3))
			ov.draw_circle(pr.pos, pr.radius * 0.45, Color(3.5, 3.0, 1.8))
		if pr.style == "orb":
			ov.draw_circle(pr.pos, pr.radius * 2.4, Color(pr.color, 0.18))
			ov.draw_circle(pr.pos, pr.radius, Color(pr.color.r * 2.5, pr.color.g * 2.5, pr.color.b * 2.0))
			ov.draw_circle(pr.pos, pr.radius * 0.5, Color(3.0, 3.0, 2.6))

	for z in zaps:
		var zk: float = z.life / 0.35
		ov.draw_polyline(z.pts, Color(0.5, 0.6, 1.5, 0.35 * zk), 6.0)
		ov.draw_polyline(z.pts, Color(2.4, 2.6, 4.0, zk), 1.8)

	if ward_t > 0.0 and not dead:
		var wt := Time.get_ticks_msec() / 1000.0
		var wa := minf(1.0, ward_t) * (0.5 + 0.15 * sin(wt * 6.0))
		ov.draw_arc(p_pos, 19.0, wt * 2.0, wt * 2.0 + TAU * 0.8, 24, Color(2.0, 1.6, 0.6, wa), 1.6)
		ov.draw_circle(p_pos, 18.0, Color(1.0, 0.85, 0.4, 0.08 * minf(1.0, ward_t)))

	if merchant_on and _vis(merchant_pos) > 0.05:
		var mt := Time.get_ticks_msec() / 1000.0
		ov.draw_circle(merchant_pos + Vector2(11.5, -14), 3.5, Color(1.0, 0.7, 0.3, 0.3))
		ov.draw_circle(merchant_pos + Vector2(11.5, -14), 1.6 + 0.3 * sin(mt * 13.0), Color(3.0, 2.0, 0.8))
		var hot := get_global_mouse_position().distance_to(merchant_pos + Vector2(0, -6)) < 18.0
		_text("Merchant" + ("  — click to trade" if hot else ""), merchant_pos + Vector2(0, -30), 12,
			Color(1.0, 0.85, 0.5) if hot else Color(0.85, 0.75, 0.55))

	for rg in rings:
		var k: float = rg.life / 0.4
		ov.draw_arc(rg.pos, rg.r, 0, TAU, 32, Color(rg.col, k * 0.8), 4.0 * k + 1.0)

	for pt in particles:
		if not pt.get("glow", false):
			continue
		var k: float = pt.life / pt.max
		var gc: Color = pt.col
		ov.draw_circle(pt.pos, pt.size * k, Color(gc.r * 2.2, gc.g * 2.2, gc.b * 2.2, gc.a * k))

	if explored[_cell(stairs_pos).y * W + _cell(stairs_pos).x] == 1 and _vis(stairs_pos) > 0.05:
		if boss_dead:
			_text("Descend", stairs_pos + Vector2(0, -24), 12, Color(0.85, 0.8, 0.65, minf(1.0, _vis(stairs_pos) * 2.0)))
		else:
			var tt := Time.get_ticks_msec() / 1000.0
			overlay.draw_arc(stairs_pos, T * 0.6, 0, TAU, 32, Color(1.6, 0.15, 0.1, 0.35 + 0.15 * sin(tt * 3.0)), 1.5)
			_text("Sealed", stairs_pos + Vector2(0, -24), 12, Color(0.9, 0.35, 0.3, minf(1.0, _vis(stairs_pos) * 2.0)))

	if hover_drop:
		var d := hover_drop
		var col := Color(1, 1, 1)
		var label := drop_label(d)
		if d.kind == "weapon":
			col = Color(0.9, 0.85, 0.6) if can_use(d.weapon) else Color(1.0, 0.4, 0.3)
			label += "  %d-%d" % [d.weapon.dmg_min, d.weapon.dmg_max]
			if d.weapon.heavy and not d.weapon.ranged:
				label += "  (heavy)"
			if not can_use(d.weapon):
				label += "  — Knight only"
		_text(label, d.pos + Vector2(0, -18), 12, col)

	for f in texts:
		_text(f.text, f.pos, f.size, Color(f.color, clampf(f.life * 1.5, 0.0, 1.0)))


# ---------------------------------------------------------------- shading helpers

## A lit sphere: dark rim, body shifted toward the light, and a soft highlight.
func _ball(c: Vector2, r: float, col: Color, _ld: Vector2, a: float, kind := "cloth") -> void:
	if spheres.is_empty():
		draw_circle(c, r, Color(col, a))
		return
	# Normal-mapped sphere: the real 2D lights do the shading.
	draw_texture_rect(spheres[kind], Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col * 1.15, a))


## A lit cylinder (arm, leg, handle).
## A limb built from overlapping spheres, so it shades correctly at any angle.
func _limb(p0: Vector2, p1: Vector2, w: float, col: Color, ld: Vector2, a: float, kind := "cloth") -> void:
	var n := maxi(2, ceili(p0.distance_to(p1) / (w * 0.4)))
	for i in n + 1:
		_ball(p0.lerp(p1, float(i) / n), w * 0.5, col, ld, a, kind)


## Torso as a cluster of spheres: shoulders, chest and back.
func _torso(p: Vector2, fwd: Vector2, r: float, sc: Vector2, col: Color, ld: Vector2, a: float, kind := "cloth") -> void:
	var side := fwd.orthogonal()
	_ball(p - fwd * r * 0.22 * sc.x, r * 0.62 * sc.y, col.darkened(0.08), ld, a, kind)
	for s in [-1.0, 1.0]:
		_ball(p + side * s * r * 0.5 * sc.y, r * 0.47 * minf(sc.x * 1.4, 1.2), col, ld, a, kind)
	_ball(p + fwd * r * 0.08 * sc.x, r * 0.66 * minf(sc.x * 1.3, sc.y), col, ld, a, kind)


func _soft_shadow(p: Vector2, r: float, a: float) -> void:
	draw_circle(p, r * 1.3, Color(0, 0, 0, 0.1 * a))
	draw_circle(p, r, Color(0, 0, 0, 0.18 * a))
	draw_circle(p, r * 0.65, Color(0, 0, 0, 0.2 * a))


func _light_dir(from: Vector2) -> Vector2:
	var d := p_pos - from
	return d.normalized() if d.length() > 0.5 else Vector2(-0.4, -0.9).normalized()


func _draw_drop(d: Drop) -> void:
	var a := minf(1.0, _vis(d.pos) * 2.0)
	if a <= 0.04:
		return
	# Blink during the last 3 seconds before vanishing, faster near the end.
	var left := ITEM_LIFE - d.t
	if left < 3.0 and fmod(d.t * (4.0 + (3.0 - left) * 3.0), 1.0) < 0.4:
		a *= 0.25
	var bob := sin(d.t * 3.0) * 1.5
	var p := d.pos + Vector2(0, bob)
	var ld := _light_dir(d.pos)
	draw_circle(d.pos + Vector2(1, 5), 5.0, Color(0, 0, 0, 0.25 * a))
	match d.kind:
		"gold":
			for k in 3:
				_ball(p + Vector2(k * 4 - 4, (k % 2) * 2), 3.3, Color(0.95, 0.72, 0.2), ld, a, "metal")
		"hp", "mp":
			var col := Color(0.75, 0.08, 0.08) if d.kind == "hp" else Color(0.15, 0.28, 0.9)
			_ball(p + Vector2(0, 2), 5.5, col, ld, a, "metal")
			draw_rect(Rect2(p + Vector2(-1.5, -7), Vector2(3, 4)), Color(0.55, 0.6, 0.6, a * 0.8))   # glass neck
			draw_rect(Rect2(p + Vector2(-2, -9), Vector2(4, 2.5)), Color(0.45, 0.32, 0.2, a))       # cork
			draw_circle(p + Vector2(-2, 0), 1.2, Color(1, 1, 1, 0.6 * a))
		"bolts":
			for k in 3:
				var o := Vector2(k * 3 - 3, 0)
				draw_line(p + o + Vector2(-2, 6), p + o + Vector2(2, -6), Color(0.45, 0.32, 0.2, a), 2.0)
				draw_line(p + o + Vector2(1.4, -4.5), p + o + Vector2(2, -6), Color(0.8, 0.82, 0.85, a), 2.0)
		"weapon":
			var glow := Color(1.0, 0.85, 0.4, 0.12 * a) if can_use(d.weapon) else Color(1.0, 0.3, 0.2, 0.12 * a)
			draw_circle(p, 14.0, glow)
			_draw_weapon(d.weapon, p + Vector2(-10, 8), -0.8, a)


func _shade(c: Color, flash: float) -> Color:
	return c.lerp(Color.WHITE, 0.7) if flash > 0.0 else c


func _zombie_head(e: Enemy) -> Array:
	var p := e.pos
	if e.kind == "spitter":
		p += e.facing * e.radius * 0.15
	if e.kind == "bloater":
		return [p + e.facing * e.radius * 0.5, e.radius * 0.36]
	return [p + e.facing * e.radius * 0.18, e.radius * 0.46]


func _draw_red_spider(e: Enemy, a: float) -> void:
	var p := e.pos
	var d := e.facing
	var side := d.orthogonal()
	var r := e.radius
	var ld := _light_dir(p)
	var moving := e.stun <= 0.0
	_soft_shadow(p + Vector2(1, 2), r * 1.3, a * 0.6)
	var leg := Color(_shade(Color(0.5, 0.06, 0.04), e.flash), a)
	for sd in [-1.0, 1.0]:
		for i in 4:
			var ph: float = sin(e.anim * 26.0 + i * 1.7 + sd) if moving else 0.0
			var base: Vector2 = p + d * r * (0.35 - i * 0.22) + side * sd * r * 0.25
			var out: Vector2 = d.rotated(sd * (0.55 + i * 0.6) + ph * 0.3)
			var knee: Vector2 = base + out * r * 0.95 + side * sd * r * 0.25
			var tip: Vector2 = knee + out.rotated(sd * 0.7) * r * 0.9
			draw_line(base, knee, leg, 2.0)
			draw_line(knee, tip, leg, 1.4)
	_ball(p - d * r * 0.45, r * 0.72, _shade(e.skin, e.flash), ld, a, "skin")
	_ball(p + d * r * 0.38, r * 0.45, _shade(e.skin.darkened(0.3), e.flash), ld, a, "skin")
	# Pale clown-face markings on the abdomen.
	draw_circle(p - d * r * 0.5, r * 0.22, Color(0.95, 0.92, 0.9, 0.85 * a))
	draw_circle(p - d * r * 0.62 + side * r * 0.12, r * 0.06, Color(0.1, 0.0, 0.0, a))
	draw_circle(p - d * r * 0.62 - side * r * 0.12, r * 0.06, Color(0.1, 0.0, 0.0, a))


func _draw_merchant() -> void:
	var p := merchant_pos
	var a := clampf(_vis(p) * 2.5, 0.0, 1.0)
	if a <= 0.0:
		return
	var ld := _light_dir(p)
	var tt := Time.get_ticks_msec() / 1000.0
	var bob := sin(tt * 2.0) * 0.8
	_soft_shadow(p + Vector2(1, 3), 13.0, a * 0.7)
	# Heavy pack on his back, then a long hooded robe.
	_ball(p + Vector2(-6, -4 + bob), 8.0, Color(0.42, 0.3, 0.18), ld, a)
	draw_line(p + Vector2(-12, -10 + bob), p + Vector2(-2, -12 + bob), Color(0.25, 0.18, 0.1, a), 2.0)
	_torso(p + Vector2(0, bob), Vector2.DOWN, 11.0, Vector2(1.0, 1.1), Color(0.28, 0.22, 0.3), ld, a)
	_ball(p + Vector2(0, -9 + bob), 7.0, Color(0.24, 0.19, 0.26), ld, a)
	draw_circle(p + Vector2(0, -7 + bob), 4.0, Color(0.03, 0.02, 0.02, a))   # face in shadow
	for s in [-1.0, 1.0]:
		draw_circle(p + Vector2(s * 1.6, -7.5 + bob), 0.8, Color(1.0, 0.8, 0.4, a))
	# Lantern on a pole.
	draw_line(p + Vector2(9, 6), p + Vector2(11, -20), Color(0.3, 0.22, 0.14, a), 1.6)
	_ball(p + Vector2(8, 2 + bob), 2.6, Color(0.6, 0.5, 0.45), ld, a, "skin")
	draw_rect(Rect2(p + Vector2(9, -17), Vector2(5, 6)), Color(0.2, 0.15, 0.1, a))


func _draw_corpse(c: Corpse) -> void:
	var e := c.e
	var a := clampf(_vis(e.pos) * 2.5, 0.0, 1.0) * clampf((CORPSE_LIFE - c.t) / 1.5, 0.0, 1.0)
	if a <= 0.0:
		return
	if e.kind == "red_spider":
		# Flipped over, legs curled.
		var lc := Color(0.22, 0.03, 0.02, a)
		for k in 8:
			var ang := k * TAU / 8.0 + c.ang
			var b := e.pos + Vector2.from_angle(ang) * e.radius * 0.4
			var kn := b + Vector2.from_angle(ang) * e.radius * 0.5
			draw_line(b, kn, lc, 1.4)
			draw_line(kn, kn + Vector2.from_angle(ang + 2.2) * e.radius * 0.35, lc, 1.0)
		_ball(e.pos, e.radius * 0.7, e.skin.darkened(0.45), _light_dir(e.pos), a, "skin")
		return
	var r := e.radius
	var dir := Vector2.from_angle(c.ang)    # head end
	var side := dir.orthogonal()
	var p := e.pos
	var ld := _light_dir(p)
	var fall := clampf(c.t / 0.25, 0.0, 1.0)
	var arm_col := e.shirt if not e.torn else e.skin
	if e.kind == "armored":
		arm_col = Color(0.45, 0.47, 0.5)
	_soft_shadow(p + Vector2(1, 2), r * 1.1, a * 0.7)
	for s in [-1.0, 1.0]:
		var hip: Vector2 = p - dir * r * 0.35 + side * s * r * 0.25
		var foot: Vector2 = hip - dir * r * (0.4 + 0.9 * fall) + side * s * r * 0.3 * fall
		_limb(hip, foot, r * 0.36, e.pants.darkened(0.2), ld, a)
	for s in [-1.0, 1.0]:
		var sh: Vector2 = p + dir * r * 0.35 + side * s * r * 0.55
		var hand: Vector2 = sh + (side * s + dir * 0.4 * s).normalized() * r * (0.5 + 0.5 * fall)
		_limb(sh, hand, r * 0.3, arm_col.darkened(0.15), ld, a)
		_ball(hand, r * 0.18, e.skin.darkened(0.2), ld, a, "skin")
	draw_set_transform(p, c.ang, Vector2(1.0, 0.68))
	_ball(Vector2.ZERO, r * 0.95, e.shirt.darkened(0.15), ld.rotated(-c.ang), a)
	if e.kind == "butcher":
		draw_circle(Vector2(r * 0.1, 0), r * 0.6, Color(Color(0.82, 0.78, 0.7).darkened(0.2), a))
	draw_set_transform(Vector2.ZERO)
	var head := p + dir * r * (0.75 + 0.35 * fall)
	var hr := r * 0.44
	_ball(head, hr, e.skin.darkened(0.2), ld, a, "skin")
	if e.kind == "armored":
		_ball(head, hr * 1.12, Color(0.45, 0.47, 0.5), ld, a)
	elif not e.bald:
		draw_arc(head, hr * 0.7, c.ang + PI - 1.3, c.ang + PI + 1.3, 10, Color(e.hair, a), hr * 0.6)


func _draw_zombie(e: Enemy) -> void:
	var a := clampf(_vis(e.pos) * 2.5, 0.0, 1.0)
	if a <= 0.0:
		return
	var f := e.flash
	var r := e.radius
	var ang := e.facing.angle()
	var p := e.pos
	var side := e.facing.orthogonal()
	var walk := sin(e.anim * e.speed / 12.0)
	var ld := _light_dir(e.pos)
	if e.boss:
		_draw_boss(e, a)
		return
	if e.kind == "red_spider":
		_draw_red_spider(e, a)
		return
	if e.kind == "spitter":
		p += e.facing * r * 0.15   # hunched forward

	_soft_shadow(e.pos + Vector2(2, r * 0.55), r * 0.95, a)

	for s in [-1.0, 1.0]:
		var foot: Vector2 = p + side * s * r * 0.4 + e.facing * walk * s * r * 0.4
		_ball(foot, r * 0.26, _shade(e.pants.darkened(0.4), f), ld, a)

	# Arms reach for you; the attack lunges them forward.
	var lunge := 0.4 if e.windup > 0.0 else 0.0
	var arm_col := e.shirt if not e.torn else e.skin
	if e.kind == "armored":
		arm_col = Color(0.45, 0.47, 0.5)
	for s in [-1.0, 1.0]:
		var shoulder: Vector2 = p + side * s * r * 0.72
		var sway := 0.12 * sin(e.anim * 2.0 + s * 1.7)
		var length := r * (1.0 + lunge + 0.1 * sin(e.anim * 3.0 + s))
		var arm_dir := e.facing.rotated(-s * 0.12 + sway)
		if e.kind == "butcher" and s > 0:
			arm_dir = e.facing.rotated(-0.9 + (1.4 if e.windup > 0.0 else 0.0))
		var hand: Vector2 = shoulder + arm_dir * length
		_limb(shoulder, hand, r * 0.36, _shade(arm_col, f), ld, a, "metal" if e.kind == "armored" else ("skin" if e.torn else "cloth"))
		_ball(hand, r * 0.2, _shade(e.skin, f), ld, a, "skin")
		if e.kind == "butcher" and s > 0:
			var n := arm_dir.orthogonal()
			var b0 := hand + arm_dir * r * 0.45
			var b1 := b0 + arm_dir * r * 0.75
			draw_line(hand, b0, Color(0.28, 0.18, 0.1, a), 3.0)
			draw_colored_polygon(PackedVector2Array([b0 - n * 1.5, b1 - n * 1.5, b1 + n * r * 0.4, b0 + n * r * 0.4]), Color(0.45, 0.46, 0.48, a))
			draw_line(b0 - n * 1.5, b1 - n * 1.5, Color(0.85, 0.87, 0.9, a), 1.0)   # honed edge
			draw_circle(b0 + arm_dir * r * 0.4 + n * r * 0.15, 1.5, Color(0.35, 0.05, 0.03, a))

	# Torso (an ellipse, wide across the shoulders)
	var body_scale := Vector2(0.62, 1.0)
	if e.kind == "bloater":
		body_scale = Vector2(1.0, 1.15)
	elif e.kind == "runner":
		body_scale = Vector2(0.55, 0.9)
	var lld := ld.rotated(-ang)
	_torso(p, e.facing, r, body_scale, _shade(e.shirt, f), ld, a, "skin" if e.kind == "bloater" else "cloth")
	draw_set_transform(p, ang, body_scale)
	if e.torn:
		draw_circle(Vector2(r * 0.2, r * 0.35), r * 0.3, Color(_shade(e.skin.darkened(0.15), f), a))
		draw_circle(Vector2(-r * 0.3, -r * 0.4), r * 0.2, Color(0.3, 0.06, 0.05, a))
	match e.kind:
		"bloater":
			_ball(Vector2.ZERO, r * 0.85, _shade(e.skin, f), lld, a, "skin")
			for k in 5:
				var pv := Vector2.from_angle(k * 1.9 + 0.4) * r * (0.35 + 0.1 * (k % 3))
				_ball(pv, r * 0.13, _shade(Color(0.75, 0.8, 0.3), f), lld, a)
		"butcher":
			draw_circle(Vector2(r * 0.2, 0), r * 0.65, Color(_shade(Color(0.78, 0.74, 0.66), f), a))
			draw_circle(Vector2(r * 0.35, r * 0.2), r * 0.18, Color(0.45, 0.06, 0.04, a))
			draw_circle(Vector2(r * 0.1, -r * 0.3), r * 0.14, Color(0.4, 0.05, 0.04, a))
		"armored":
			_ball(Vector2(0, -r * 0.75), r * 0.34, _shade(Color(0.6, 0.62, 0.66), f), lld, a, "metal")
			_ball(Vector2(0, r * 0.75), r * 0.34, _shade(Color(0.6, 0.62, 0.66), f), lld, a, "metal")
			draw_line(Vector2(-r * 0.6, 0), Vector2(r * 0.6, 0), Color(0.35, 0.13, 0.1, a), 3.0)
	draw_set_transform(Vector2.ZERO)

	var hd := _zombie_head(e)
	var head: Vector2 = hd[0]
	var hr: float = hd[1]
	_ball(head, hr, _shade(e.skin, f), ld, a, "skin")
	if e.kind == "armored":
		_ball(head, hr * 1.12, _shade(Color(0.55, 0.57, 0.6), f), ld, a, "metal")
		draw_line(head + e.facing * hr * 0.6 - side * hr * 0.6, head + e.facing * hr * 0.6 + side * hr * 0.6, Color(0.05, 0.05, 0.05, a), 2.0)
	elif not e.bald:
		draw_arc(head, hr * 0.7, ang + PI - 1.3, ang + PI + 1.3, 10, Color(_shade(e.hair, f), a), hr * 0.6)
	# Sunken eye sockets (the glint is drawn in the overlay).
	var eye := head + e.facing * hr * 0.6
	draw_circle(eye + side * hr * 0.42, hr * 0.22, Color(0.05, 0.03, 0.03, a))
	draw_circle(eye - side * hr * 0.42, hr * 0.22, Color(0.05, 0.03, 0.03, a))
	if e.kind == "spitter":
		draw_circle(head + e.facing * hr * 1.1, 2.0 + sin(e.anim * 4.0), Color(0.5, 0.7, 0.15, a))


func _draw_player() -> void:
	var r := PLAYER_R
	var ang := facing.angle()
	var side := facing.orthogonal()
	var moving := not path.is_empty()
	var walk := sin(walk_anim) if moving else 0.0
	var p := p_pos
	var knight := hero == "knight"
	var armor := Color(0.58, 0.6, 0.65) if knight else Color(0.85, 0.82, 0.74)
	var trim := Color(0.33, 0.35, 0.4) if knight else Color(0.85, 0.66, 0.22)
	if hurt_flash > 0.0:
		armor = armor.lerp(Color(1, 0.4, 0.4), 0.6)
	var ld := Vector2(-0.35, -0.6).normalized()   # torch held above

	_soft_shadow(p + Vector2(1, 8), 10.0, 1.0)
	for s in [-1.0, 1.0]:
		_ball(p + side * s * r * 0.4 + facing * walk * s * r * 0.4, r * 0.28, trim.darkened(0.3), ld, 1.0)

	var left := p - side * r * 0.85 + facing * r * 0.35
	var right := p + side * r * 0.8 + facing * r * 0.25

	# Torso: plate (knight) or tabard over mail (paladin)
	_torso(p, facing, r, Vector2(0.62, 1.0), armor, ld, 1.0, "metal" if knight else "cloth")
	draw_set_transform(p, ang, Vector2(0.62, 1.0))
	if knight:
		draw_arc(Vector2.ZERO, r * 0.55, -1.2, 1.2, 10, Color(0.85, 0.87, 0.92, 0.5), 1.0)   # plate edge glint
	else:
		draw_line(Vector2(-r * 0.6, 0), Vector2(r * 0.8, 0), trim, 2.5)   # tabard stripe
	draw_set_transform(Vector2.ZERO)

	if knight:
		draw_set_transform(left, ang, Vector2.ONE)
		draw_rect(Rect2(-3.5, -9.5, 7, 19), Color(0.2, 0.2, 0.22))
		draw_rect(Rect2(-2.5, -9, 6, 18), Color(0.45, 0.16, 0.13))
		draw_rect(Rect2(-2.5, -9, 6, 4), Color(0.6, 0.25, 0.2))
		draw_line(Vector2(-2.5, -9), Vector2(-2.5, 9), Color(0.85, 0.87, 0.9), 1.0)
		draw_set_transform(Vector2.ZERO)
	else:
		_ball(left, 6.0, Color(0.78, 0.76, 0.68), ld, 1.0, "metal")
		draw_arc(left, 6.0, 0, TAU, 14, trim, 1.5)
		draw_circle(left, 1.8, trim)

	if shoot_anim > 0.0 and bow:
		_draw_weapon(bow, p + facing * r * 0.6, ang, 1.0)
	else:
		var wa := ang + 0.6
		if swing > 0.0:
			wa = ang + 1.3 - 2.6 * (1.0 - swing / swing_len)
		_draw_weapon(melee, right, wa, 1.0)
	_ball(right, r * 0.24, trim, ld, 1.0, "metal" if knight else "cloth")

	var head := p + facing * r * 0.15
	if knight:
		_ball(head, r * 0.5, Color(0.62, 0.64, 0.7), ld, 1.0, "metal")
		draw_line(head + facing * r * 0.35 - side * r * 0.3, head + facing * r * 0.35 + side * r * 0.3, Color(0.05, 0.05, 0.06), 2.0)
		draw_line(head - facing * r * 0.45, head + facing * r * 0.2, Color(0.55, 0.12, 0.1), 2.5)  # plume
	else:
		_ball(head, r * 0.46, Color(0.82, 0.66, 0.54), ld, 1.0, "skin")
		draw_arc(head, r * 0.33, ang + PI - 1.4, ang + PI + 1.4, 10, Color(0.4, 0.26, 0.13), r * 0.3)
		draw_arc(head, r * 0.46, 0, TAU, 16, Color(0.95, 0.78, 0.3), 1.5)   # circlet


func _draw_weapon(w: Weapon, hand: Vector2, ang: float, a: float) -> void:
	draw_weapon_on(self, w, hand, ang, a, 1.0)


## Shared with the HUD so inventory icons match what's drawn in the world.
func draw_weapon_on(ci: CanvasItem, w: Weapon, hand: Vector2, ang: float, a: float, s: float) -> void:
	var d := Vector2.from_angle(ang) * s
	var n := Vector2.from_angle(ang).orthogonal() * s
	var steel_dark := Color(0.5, 0.52, 0.58, a)
	var steel := Color(0.85, 0.88, 0.95, a)
	var wood := Color(0.42, 0.28, 0.16, a)
	var brass := Color(0.7, 0.55, 0.28, a)
	match w.style:
		"sword":
			ci.draw_line(hand, hand + d * 22.0, steel_dark, 3.2 * s)
			ci.draw_line(hand + n * 0.5, hand + d * 21.0 + n * 0.5, steel, 1.3 * s)
			ci.draw_line(hand - n * 4.0, hand + n * 4.0, brass, 2.0 * s)
			ci.draw_circle(hand - d * 2.5, 1.5 * s, brass)
		"greatsword":
			ci.draw_line(hand - d * 4.0, hand + d * 32.0, steel_dark, 4.8 * s)
			ci.draw_line(hand + n * 0.7, hand + d * 31.0 + n * 0.7, steel, 1.8 * s)
			ci.draw_line(hand - n * 6.0, hand + n * 6.0, brass, 3.0 * s)
			ci.draw_circle(hand - d * 6.0, 2.0 * s, brass)
		"mace":
			ci.draw_line(hand, hand + d * 16.0, wood, 2.5 * s)
			ci.draw_circle(hand + d * 18.0, 4.8 * s, steel_dark)
			ci.draw_circle(hand + d * 18.0 - n * 1.2 - d * 1.2, 2.4 * s, steel)
			for k in 4:
				ci.draw_circle(hand + d * 18.0 + Vector2.from_angle(ang + k * PI / 2.0 + 0.6) * 4.6 * s, 1.2 * s, steel_dark)
		"hammer":
			ci.draw_line(hand - d * 3.0, hand + d * 22.0, wood, 3.0 * s)
			ci.draw_line(hand + d * 22.0 - n * 7.0, hand + d * 22.0 + n * 7.0, steel_dark, 7.0 * s)
			ci.draw_line(hand + d * 20.0 - n * 7.0, hand + d * 20.0 + n * 7.0, steel, 1.5 * s)
		"halberd":
			ci.draw_line(hand - d * 8.0, hand + d * 38.0, wood, 2.5 * s)
			ci.draw_colored_polygon(PackedVector2Array([hand + d * 27.0, hand + d * 34.0, hand + d * 33.0 + n * 8.0, hand + d * 27.0 + n * 6.0]), steel_dark)
			ci.draw_line(hand + d * 33.0 + n * 8.0, hand + d * 27.0 + n * 6.0, steel, 1.2 * s)
			ci.draw_line(hand + d * 38.0, hand + d * 45.0, steel, 2.5 * s)
		"crossbow":
			ci.draw_line(hand - d * 6.0, hand + d * 12.0, wood, 4.0 * s)
			var span := (12.0 if w.base == "Heavy Crossbow" else 9.0) * s
			ci.draw_arc(hand + d * 6.0, span, ang - 1.4, ang + 1.4, 10, Color(0.35, 0.35, 0.4, a), 2.5 * s)
			ci.draw_line(hand + d * 6.0 + Vector2.from_angle(ang - 1.4) * span, hand + d * 6.0 + Vector2.from_angle(ang + 1.4) * span, Color(0.75, 0.72, 0.65, a * 0.8), 0.7)


## Text is always drawn on the unlit overlay so it stays readable in the dark.
func _text(s: String, pos: Vector2, size: int, col: Color) -> void:
	var w := 400.0
	overlay.draw_string_outline(font, pos - Vector2(w / 2, -size * 0.35), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, 3, Color(0, 0, 0, col.a * 0.8))
	overlay.draw_string(font, pos - Vector2(w / 2, -size * 0.35), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)
