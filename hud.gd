extends Control
## Screen-space HUD: class menu, life/mana orbs, potion belt, skill, XP bar, target info, messages.

var main
var font: Font
var map_img: Image
var map_tex: ImageTexture
var map_refresh := 0
var hp_trail := 1.0
var res_trail := 1.0

const CLASSES := [
	{
		"name": "KNIGHT",
		"tag": "Steel, shield and crossbow.",
		"lines": ["120 Life  ·  25% block", "Wields heavy weapons:", "  Greatsword, War Hammer, Halberd", "RMB: Crossbow (uses bolts)",
			"Q: Shield Bash — stun & knock back", "No mana: learned spells recharge"],
		"col": Color(0.65, 0.68, 0.75),
	},
	{
		"name": "PALADIN",
		"tag": "Holy warrior of the Ember Order.",
		"lines": ["95 Life  ·  60 Mana  ·  12% block", "Light weapons only:", "  Swords, Maces, Flails", "RMB: cast spell (starts with Holy Bolt)",
			"Scrolls teach & level up spells", "Q: Healing Light — heal & burn undead"],
		"col": Color(0.95, 0.8, 0.35),
	},
]


func _ready() -> void:
	font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp minimap pixels


func life_bar_rect() -> Rect2:
	return Rect2(16, size.y - 64, 320, 20)


func res_bar_rect() -> Rect2:
	return Rect2(size.x - 336, size.y - 64, 320, 20)


func card_rect(i: int) -> Rect2:
	var w := 340.0
	var h := 300.0
	var cx := size.x / 2 + (i * 2 - 1) * (w / 2 + 20)
	return Rect2(cx - w / 2, size.y * 0.32, w, h)


func mode_rect() -> Rect2:
	return Rect2(size.x / 2 - 290, size.y * 0.32 + 314, 280, 34)


func diff_rect() -> Rect2:
	return Rect2(size.x / 2 + 10, size.y * 0.32 + 314, 280, 34)


func _draw() -> void:
	if main == null:
		return
	# The manual's pictures only need rendering while they are on screen.
	var pics: bool = main.state == "menu" and main.manual_open and main.manual_page in [3, 4]
	if main.portraits != null:
		for vp in main.portraits.get_children():
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if pics else SubViewport.UPDATE_DISABLED
	if main.state == "menu":
		_draw_menu()
		if main.manual_open:
			_draw_manual()
		return
	var sz := size
	var m = main
	var knight: bool = m.hero == "knight"

	draw_rect(Rect2(0, sz.y - 34, sz.x, 34), Color(0.07, 0.06, 0.05, 0.92))
	draw_line(Vector2(0, sz.y - 34), Vector2(sz.x, sz.y - 34), Color(0.45, 0.36, 0.22), 2.0)

	var dt := get_process_delta_time()
	var hp_f: float = m.p_hp / m.p_max_hp
	var res_f: float = float(m.bolts) / m.max_bolts if knight else m.p_mp / m.p_max_mp
	hp_trail = maxf(hp_f, move_toward(hp_trail, hp_f, dt * 0.6))
	res_trail = maxf(res_f, move_toward(res_trail, res_f, dt * 0.6))
	_bar(life_bar_rect(), hp_f, hp_trail, Color(0.72, 0.1, 0.08), "Life  %d / %d" % [ceili(m.p_hp), int(m.p_max_hp)])
	if knight:
		_bar(res_bar_rect(), res_f, res_trail, Color(0.55, 0.4, 0.22), "Bolts  %d / %d" % [m.bolts, m.max_bolts])
	else:
		_bar(res_bar_rect(), res_f, res_trail, Color(0.15, 0.3, 0.85), "Mana  %d / %d" % [int(m.p_mp), int(m.p_max_mp)])

	var xr := Rect2(16, sz.y - 39, sz.x - 32, 3)
	draw_rect(xr, Color(0.15, 0.13, 0.1))
	draw_rect(Rect2(xr.position, Vector2(xr.size.x * float(m.xp) / m.xp_next, xr.size.y)), Color(0.85, 0.7, 0.3))

	# Belt + skill
	var bx := sz.x / 2 - 70
	_slot(Vector2(bx, sz.y - 30), "1", str(m.hp_pots), Color(0.85, 0.15, 0.15), 0.0)
	if knight:
		_slot(Vector2(bx + 36, sz.y - 30), "2", "-", Color(0.3, 0.3, 0.3), 0.0)
	else:
		_slot(Vector2(bx + 36, sz.y - 30), "2", str(m.mp_pots), Color(0.2, 0.35, 1.0), 0.0)
	_slot(Vector2(bx + 80, sz.y - 30), "Q", "", Color(0.75, 0.75, 0.8) if knight else Color(1.0, 0.85, 0.4), m.skill_cd / m.skill_max)

	_label("Lv %d" % m.level, Vector2(bx + 124, sz.y - 14), 16, Color(0.9, 0.85, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	# Spellbook: known spells show their level (and a Knight's recharge); the active one is framed in gold.
	var order: Array = m.spell_order()
	for i in order.size():
		var sid: String = order[i]
		var known: bool = m.spell_lvl.has(sid)
		var sp := Vector2(bx - 44 - (order.size() - i) * 36, sz.y - 30)
		var cd: float = m.spell_cd.get(sid, 0.0) / m.knight_cd(sid) if knight and known else 0.0
		_slot(sp, m.spell_key(sid), ("L%d" % m.spell_lvl[sid]) if known else "-", m.SPELLS[sid].col, cd)
		if sid == m.selected_spell:
			draw_rect(Rect2(sp, Vector2(30, 26)).grow(1), Color(1.0, 0.85, 0.3), false, 2.0)
	_label("Gold %d" % m.gold, Vector2(sz.x / 2 - 360, sz.y - 14), 16, Color(1.0, 0.8, 0.3), HORIZONTAL_ALIGNMENT_LEFT)
	_label(("Wave %d" if m.rush else "Depth %d") % m.depth, Vector2(sz.x / 2 + 175, sz.y - 14), 16, Color(0.8, 0.75, 0.7), HORIZONTAL_ALIGNMENT_LEFT)

	# Equipped weapons, above the orbs
	var wtext: String = m.melee.label() + "  %d-%d" % [m.melee.dmg_min, m.melee.dmg_max]
	_label(wtext, Vector2(16, sz.y - 84), 14, Color(0.9, 0.85, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
	if knight and m.bow:
		_label(m.bow.label() + "  %d-%d" % [m.bow.dmg_min, m.bow.dmg_max], Vector2(sz.x - 16, sz.y - 84), 14, Color(0.9, 0.85, 0.65), HORIZONTAL_ALIGNMENT_RIGHT)

	var bar_y := 14.0
	var bs = m.boss
	if m.brood_of != null:
		var left := 0
		for o in m.enemies:
			if o.kind == "red_spider" and o.hp > 0.0:
				left += 1
		var bw := 520.0
		var bb := Rect2(sz.x / 2 - bw / 2, 12, bw, 26)
		draw_rect(bb.grow(3), Color(0.05, 0.02, 0.02, 0.9))
		draw_rect(bb, Color(0.12, 0.02, 0.02))
		draw_rect(Rect2(bb.position, Vector2(bw * left / 10.0, 26)), Color(0.6, 0.04, 0.04))
		draw_rect(bb.grow(1), Color(0.75, 0.55, 0.25), false, 2.0)
		_label("Spawn of %s — %d left" % [m.brood_of.name.split(",")[0], left], bb.get_center() + Vector2(0, -1), 16, Color(1.0, 0.85, 0.5))
		bar_y = 50.0
	if bs != null and bs.hp > 0.0:
		var bw := 520.0
		var bb := Rect2(sz.x / 2 - bw / 2, 12, bw, 26)
		draw_rect(bb.grow(3), Color(0.05, 0.02, 0.02, 0.9))
		draw_rect(bb, Color(0.12, 0.02, 0.02))
		draw_rect(Rect2(bb.position, Vector2(bw * bs.hp / bs.max_hp, 26)), Color(0.6, 0.04, 0.04))
		draw_rect(Rect2(bb.position, Vector2(bw * bs.hp / bs.max_hp, 8)), Color(0.8, 0.15, 0.1))
		draw_rect(bb.grow(1), Color(0.75, 0.55, 0.25), false, 2.0)
		_label(bs.name, bb.get_center() + Vector2(0, -1), 16, Color(1.0, 0.85, 0.5))
		bar_y = 50.0
	if m.rush:
		var rt := "BOSS RUSH (%s)  ·  Slain %d / %d  ·  %s" % [m.diff().name, m.rush_wave, m.BOSSES.size(), clock(m.rush_time)]
		_label(rt, Vector2(16, 18), 15, Color(0.95, 0.5, 0.35), HORIZONTAL_ALIGNMENT_LEFT)
		if m.rush_won:
			var k := clampf(6.0 - m.rush_end_t, 0.0, 1.0)
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.04, 0.0, 0.5 * k))
			_label("BOSS RUSH COMPLETE", Vector2(sz.x / 2, sz.y * 0.42), 54, Color(1.0, 0.8, 0.3, k))
			var best := "   ·   New best!" if not m.run_debug and m.rush_best_time == m.rush_time else ""
			if m.run_debug:
				best = "   ·   (debug run, not recorded)"
			_label("Time %s%s" % [clock(m.rush_time), best], Vector2(sz.x / 2, sz.y * 0.5), 22, Color(0.95, 0.9, 0.8, k))
			_label("Returning to the title...", Vector2(sz.x / 2, sz.y * 0.56), 16, Color(1, 1, 1, 0.7 * k))
		elif m.merchant_on and not m.dead:
			if not m.shop_open:
				_label("Trade with the merchant — press Enter when ready for the next boss", Vector2(sz.x / 2, sz.y - 112), 18, Color(1.0, 0.8, 0.45, 0.9))
		elif not m.boss_spawned and not m.dead:
			_label("Next boss in %d" % ceili(m.rush_break), Vector2(sz.x / 2, sz.y * 0.3), 30, Color(1.0, 0.4, 0.25, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)))
	var e = m.hover_enemy
	if e == null:
		e = m.target_enemy
	if e != null and e.hp > 0.0 and e != bs:
		var w := 260.0
		var br := Rect2(sz.x / 2 - w / 2, bar_y, w, 22)
		draw_rect(br, Color(0.1, 0.02, 0.02, 0.85))
		draw_rect(Rect2(br.position, Vector2(w * e.hp / e.max_hp, 22)), Color(0.55, 0.05, 0.05))
		draw_rect(br, Color(0.5, 0.4, 0.25), false, 1.5)
		_label(e.name, Vector2(sz.x / 2, bar_y + 11), 15, Color(1.0, 0.8, 0.3) if e.elite else Color(1, 1, 1))

	# Inventory button
	var ib := inv_button_rect()
	var ib_hot: bool = ib.has_point(get_local_mouse_position()) or m.inv_open
	draw_rect(ib, Color(0.16, 0.13, 0.09) if ib_hot else Color(0.1, 0.09, 0.07))
	draw_rect(ib, Color(0.6, 0.48, 0.28) if ib_hot else Color(0.45, 0.36, 0.22), false, 1.5)
	_label("Inventory", ib.get_center() + Vector2(0, -1), 13, Color(0.9, 0.85, 0.7))
	if m.stat_points > 0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
		var bc := ib.end - Vector2(2, ib.size.y - 2)
		draw_circle(bc, 10.0 + pulse * 2.0, Color(1.0, 0.75, 0.2, 0.3))
		draw_circle(bc, 9.0, Color(0.85, 0.6, 0.15))
		_label("+%d" % m.stat_points, bc + Vector2(0, -1), 11, Color(1, 1, 1))

	if m.show_map and not m.inv_open and not m.dead:
		_draw_minimap()

	if m.inv_open and not m.dead:
		_draw_inventory()
	if m.shop_open and not m.dead:
		_draw_shop()

	if m.touch_on and not m.dead:
		_draw_touch()

	if m.message_t > 0.0:
		_label(m.message, Vector2(sz.x / 2, sz.y * 0.22), 28, Color(0.95, 0.85, 0.65, clampf(m.message_t, 0.0, 1.0)))

	if m.depth == 1 and m.level == 1 and m.xp == 0 and m.touch_on:
		_label("Tap: move / attack / loot (hold to keep moving)    %s: %s at the nearest foe" % ["Crossbow" if knight else "Cast", "shoot" if knight else "cast your spell"], Vector2(sz.x / 2, sz.y - 120), 13, Color(0.75, 0.7, 0.6, 0.85))
		_label("Tap the belt: potions, skill and spells    Back: close panels", Vector2(sz.x / 2, sz.y - 104), 13, Color(0.75, 0.7, 0.6, 0.85))
	elif m.depth == 1 and m.level == 1 and m.xp == 0:
		var hint := "LMB: move / attack / loot    Shift+LMB: attack in place    RMB: %s    Q: %s    1: potion" % [
			"crossbow" if knight else "cast spell", "shield bash" if knight else "healing light"]
		var hint2 := ("F / MMB: cast spell    3-6 / wheel: pick spell" if knight else "3-7 / wheel: pick spell") + "    I: inventory    M: map    N: music"
		_label(hint, Vector2(sz.x / 2, sz.y - 120), 12, Color(0.75, 0.7, 0.6, 0.85))
		_label(hint2, Vector2(sz.x / 2, sz.y - 104), 12, Color(0.75, 0.7, 0.6, 0.85))

	if m.debug:
		_label("DEBUG: INVINCIBLE (F9)", Vector2(sz.x - 16, 18), 14, Color(0.4, 0.85, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)

	if m.hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.6, 0.0, 0.0, m.hurt_flash * 0.5))

	if m.dead:
		var k := clampf(m.death_timer, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.0, 0.0, 0.6 * k))
		_label("YOU HAVE FALLEN", Vector2(sz.x / 2, sz.y * 0.42), 54, Color(0.8, 0.1, 0.1, k))
		var summary := "%s  ·  %s  ·  Depth %d  ·  Level %d  ·  %d gold" % [m.hero.capitalize(), m.diff().name, m.depth, m.level, m.gold]
		if m.rush:
			summary = "%s  ·  %s  ·  Bosses slain: %d  ·  Time %s  ·  Best %d" % [m.hero.capitalize(), m.diff().name, m.rush_wave, clock(m.rush_time), m.rush_best]
		_label(summary, Vector2(sz.x / 2, sz.y * 0.5), 20, Color(0.9, 0.85, 0.75, k))
		if m.rush:
			_label("Returning to the title...", Vector2(sz.x / 2, sz.y * 0.57), 18, Color(1, 1, 1, k))
		elif m.death_timer > 1.0:
			_label("Click or press R to return to the menu", Vector2(sz.x / 2, sz.y * 0.57), 18, Color(1, 1, 1, k))


# ================================================================ minimap

func _refresh_map_image() -> void:
	var m = main
	if map_img == null or map_img.get_width() != m.W:
		map_img = Image.create(m.W, m.H, false, Image.FORMAT_RGBA8)
		map_tex = null
	for y in m.H:
		for x in m.W:
			var i: int = y * m.W + x
			var col := Color(0, 0, 0, 0)
			if m.explored[i] == 1:
				if m.grid[i] == 0:
					col = Color(0.42, 0.37, 0.31, 0.85)
				else:
					# Only draw walls that border floor, so rooms read as outlines.
					var edge := false
					for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = x + o.x
						var ny: int = y + o.y
						if nx >= 0 and ny >= 0 and nx < m.W and ny < m.H and m.grid[ny * m.W + nx] == 0:
							edge = true
							break
					if edge:
						col = Color(0.75, 0.62, 0.42, 0.9)
			map_img.set_pixel(x, y, col)
	if map_tex == null:
		map_tex = ImageTexture.create_from_image(map_img)
	else:
		map_tex.update(map_img)


func minimap_rect() -> Rect2:
	var w := 200.0
	var h: float = w * float(main.H) / main.W
	return Rect2(size.x - w - 14, size.y - 104 - h, w, h)


func _draw_minimap() -> void:
	var m = main
	# Rebuilding the image is cheap but not free; every 10 frames is plenty.
	map_refresh -= 1
	if map_refresh <= 0 or map_tex == null:
		map_refresh = 10
		_refresh_map_image()
	var r := minimap_rect()
	draw_rect(r.grow(4), Color(0.04, 0.035, 0.03, 0.8))
	draw_rect(r.grow(4), Color(0.45, 0.36, 0.22), false, 1.5)
	draw_texture_rect(map_tex, r, false)
	var k := r.size / Vector2(m.W * m.T, m.H * m.T)

	var sc: Vector2i = m._cell(m.stairs_pos)
	if m.explored[sc.y * m.W + sc.x] == 1:
		var sp: Vector2 = r.position + m.stairs_pos * k
		draw_rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 0.8, 1.0))
	for d in m.drops:
		var c: Vector2i = m._cell(d.pos)
		if m.explored[c.y * m.W + c.x] == 1:
			draw_rect(Rect2(r.position + d.pos * k - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.85, 0.3))
	for e in m.enemies:
		if m._light(e.pos) > 0.05:
			draw_circle(r.position + e.pos * k, 2.5 if e.elite else 1.8, Color(1.0, 0.75, 0.2) if e.elite else Color(0.95, 0.2, 0.15))
	var pp: Vector2 = r.position + m.p_pos * k
	var t := Time.get_ticks_msec() / 1000.0
	draw_circle(pp, 5.0 + sin(t * 4.0), Color(1, 1, 1, 0.2))
	draw_circle(pp, 2.8, Color(1, 1, 1))
	draw_line(pp, pp + m.facing * 6.0, Color(1, 1, 1), 1.5)
	_label(("Wave %d" if m.rush else "Depth %d") % m.depth, Vector2(r.position.x + 4, r.position.y + 7), 11, Color(0.85, 0.8, 0.7, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_label("[M]", Vector2(r.end.x - 4, r.position.y + 7), 10, Color(0.6, 0.55, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)


# ================================================================ inventory

const BAG_COLS := 8
const CELL := 46.0

func inv_panel_rect() -> Rect2:
	return Rect2(size.x - 440, 10, 420, 560)


func inv_button_rect() -> Rect2:
	return Rect2(size.x / 2 + 255, size.y - 30, 86, 26)


## The belt's clickable slots: "hp", "mp", "skill" and "spell:<id>" -> rectangle.
func belt_rects() -> Dictionary:
	var bx := size.x / 2 - 70
	var r := {"hp": Rect2(bx, size.y - 30, 30, 26), "mp": Rect2(bx + 36, size.y - 30, 30, 26), "skill": Rect2(bx + 80, size.y - 30, 30, 26)}
	var order: Array = main.spell_order()
	for i in order.size():
		r["spell:" + order[i]] = Rect2(bx - 44 - (order.size() - i) * 36, size.y - 30, 30, 26)
	return r


func belt_at(p: Vector2) -> String:
	var r := belt_rects()
	for k in r:
		if (r[k] as Rect2).grow(3).has_point(p):
			return k
	return ""


# ================================================================ touch controls
## Round on-screen buttons for phones: name -> [center, radius, label].
func touch_buttons() -> Dictionary:
	var b := {}
	if main.inv_open or main.shop_open:
		return b                       # the panels need the room
	var knight: bool = main.hero == "knight"
	b["cast"] = [Vector2(size.x - 300, size.y - 130), 50.0, "Crossbow" if knight else "Cast"]
	if knight:
		b["spell"] = [Vector2(size.x - 300, size.y - 245), 40.0, "Spell"]
	b["map"] = [Vector2(size.x - 60, 60), 30.0, "Map"]
	return b


func touch_button_at(p: Vector2) -> String:
	if not main.touch_on or main.state != "play" or main.dead:
		return ""
	var b := touch_buttons()
	for k in b:
		if p.distance_to(b[k][0]) <= b[k][1] + 6.0:
			return k
	if (main.inv_open or main.shop_open) and touch_mode_rect().has_point(p):
		return "mode"
	return ""


## In the inventory/shop on a phone: switches what a tap does (equip/buy or drop/sell).
func touch_mode_rect() -> Rect2:
	var r := inv_panel_rect()
	return Rect2(r.position.x + 20, r.end.y + 6, r.size.x - 40, 34)


func _draw_touch() -> void:
	var m = main
	var b := touch_buttons()
	for k in b:
		var held: bool = k in m.touch_fingers.values()
		draw_circle(b[k][0], b[k][1], Color(0.12, 0.09, 0.06, 0.55 if not held else 0.8))
		draw_arc(b[k][0], b[k][1], 0, TAU, 48, Color(0.75, 0.6, 0.35, 0.8), 2.0)
		var txt: String = b[k][2]
		if k == "spell" and m.selected_spell != "":
			txt = m.SPELLS[m.selected_spell].name
		_label(txt, b[k][0], 16 if k != "map" else 13, Color(0.95, 0.88, 0.7))
	if m.inv_open or m.shop_open:
		var r := touch_mode_rect()
		draw_rect(r, Color(0.14, 0.1, 0.07, 0.9))
		draw_rect(r, Color(0.6, 0.48, 0.28), false, 1.5)
		var what := ("Tap = sell / drop" if m.shop_open else "Tap = drop on floor") if m.touch_alt else ("Tap = buy / equip" if m.shop_open else "Tap = equip")
		_label(what + "   (tap here to switch)", r.get_center(), 15, Color(1.0, 0.85, 0.5) if m.touch_alt else Color(0.9, 0.85, 0.7))


func _melee_slot() -> Rect2:
	var p := inv_panel_rect()
	return Rect2(p.position + Vector2(26, 66), Vector2(84, 130))


func _ranged_slot() -> Rect2:
	var p := inv_panel_rect()
	return Rect2(p.position + Vector2(124, 66), Vector2(84, 130))


func _bag_cell(i: int) -> Rect2:
	var p := inv_panel_rect()
	@warning_ignore("integer_division")
	var row := i / BAG_COLS
	return Rect2(p.position + Vector2(26 + (i % BAG_COLS) * CELL, 406 + row * CELL), Vector2(CELL - 4, CELL - 4))


func attr_button_rect(i: int) -> Rect2:
	var p := inv_panel_rect()
	return Rect2(p.end.x - 46, p.position.y + 266 + i * 28, 22, 22)


func _spell_cell(i: int) -> Rect2:
	var p := inv_panel_rect()
	return Rect2(p.position + Vector2(26 + i * 37, 206), Vector2(31, 31))


func inv_slot_at(pos: Vector2) -> Dictionary:
	var order: Array = main.spell_order()
	for i in order.size():
		if _spell_cell(i).has_point(pos):
			return {"type": "spell", "id": order[i]}
	for i in 4:
		if attr_button_rect(i).has_point(pos):
			return {"type": "attr", "i": i}
	if _melee_slot().has_point(pos):
		return {"type": "melee"}
	if _ranged_slot().has_point(pos):
		return {"type": "ranged"}
	for i in main.BAG_SIZE:
		if _bag_cell(i).has_point(pos):
			return {"type": "bag", "i": i}
	return {}


func _weapon_icon(w, rect: Rect2, s: float) -> void:
	var lengths := {"sword": 22.0, "greatsword": 36.0, "mace": 22.0, "hammer": 25.0, "halberd": 50.0, "crossbow": 18.0}
	var ang := -PI / 4.0
	var length: float = lengths.get(w.style, 22.0) * s
	var hand := rect.get_center() - Vector2.from_angle(ang) * length * 0.5
	main.draw_weapon_on(self, w, hand, ang, 1.0, s)
	if w.bonus > 0:
		_label("+%d" % w.bonus, rect.position + Vector2(rect.size.x - 6, rect.size.y - 8), 11, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_inventory() -> void:
	var m = main
	var knight: bool = m.hero == "knight"
	var p := inv_panel_rect()
	var mouse := get_local_mouse_position()
	var gold_line := Color(0.45, 0.36, 0.22)

	draw_rect(p, Color(0.06, 0.05, 0.045, 0.96))
	draw_rect(p, gold_line, false, 2.0)
	draw_rect(p.grow(-4), Color(0.3, 0.24, 0.15), false, 1.0)
	_label("INVENTORY", Vector2(p.get_center().x, p.position.y + 24), 22, Color(0.95, 0.8, 0.5))
	_label("[I] close", Vector2(p.end.x - 14, p.position.y + 24), 12, Color(0.6, 0.55, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)

	# Equipment
	var ms := _melee_slot()
	var rs := _ranged_slot()
	_label("Weapon", Vector2(ms.get_center().x, ms.position.y - 10), 13, Color(0.8, 0.75, 0.65))
	_label("Crossbow" if knight else "Spell", Vector2(rs.get_center().x, rs.position.y - 10), 13, Color(0.8, 0.75, 0.65))
	for r in [ms, rs]:
		draw_rect(r, Color(0.1, 0.09, 0.08))
		draw_rect(r, gold_line.lightened(0.2) if r.has_point(mouse) else gold_line, false, 1.5)
	_weapon_icon(m.melee, ms, 1.6)
	if knight:
		if m.bow:
			_weapon_icon(m.bow, rs, 2.2)
		else:
			_label("empty", rs.get_center(), 12, Color(0.5, 0.45, 0.4))
	else:
		# The Paladin's second slot is his active spell, chosen from the spellbook below.
		var sid: String = m.selected_spell
		var sc: Color = m.SPELLS[sid].col
		var c := rs.get_center() + Vector2(0, -12)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
		draw_circle(c, 24.0, Color(sc, 0.08 + 0.06 * pulse))
		draw_circle(c, 15.0, sc.darkened(0.35))
		draw_circle(c + Vector2(-3, -3), 9.0, sc)
		draw_circle(c + Vector2(-5, -6), 3.5, Color(1, 1, 1, 0.7))
		_label(m.SPELLS[sid].name, rs.get_center() + Vector2(0, 28), 10 if m.SPELLS[sid].name.length() > 11 else 12, Color(0.95, 0.9, 0.8))
		_label("Lv %d · %d mana" % [m.spell_lvl[sid], int(m.SPELL_COST[sid])], rs.get_center() + Vector2(0, 45), 11, Color(0.6, 0.7, 1.0))
	# Spellbook: click a known spell to make it the active one.
	for i in m.spell_order().size():
		var cid: String = m.spell_order()[i]
		var cell := _spell_cell(i)
		var known: bool = m.spell_lvl.has(cid)
		var ccol: Color = m.SPELLS[cid].col
		draw_rect(cell, Color(0.1, 0.09, 0.08))
		if known:
			draw_circle(cell.get_center(), 10.0, ccol.darkened(0.3))
			draw_circle(cell.get_center() + Vector2(-2, -2), 6.0, ccol)
			_label(str(m.spell_lvl[cid]), cell.end - Vector2(5, 7), 11, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			draw_circle(cell.get_center(), 9.0, Color(0.18, 0.16, 0.14))
			_label("?", cell.get_center() + Vector2(0, -1), 13, Color(0.4, 0.37, 0.32))
		var hot := cell.has_point(mouse)
		var border := Color(1.0, 0.85, 0.3) if cid == m.selected_spell else (gold_line.lightened(0.3) if hot else Color(0.3, 0.25, 0.17))
		draw_rect(cell, border, false, 2.0 if cid == m.selected_spell else 1.0)

	# Character stats
	var sx := p.position.x + 228
	var sy := p.position.y + 70
	var lv_bonus: int = m.melee_bonus()
	var stats := [
		["Class", m.hero.capitalize()],
		["Level", str(m.level)],
		["Experience", "%d / %d" % [m.xp, m.xp_next]],
		["Life", "%d / %d" % [ceili(m.p_hp), int(m.p_max_hp)]],
		["Bolts" if knight else "Mana", "%d / %d" % [m.bolts, m.max_bolts] if knight else "%d / %d" % [int(m.p_mp), int(m.p_max_mp)]],
		["Block", "%d%%" % int(m.block * 100)],
		["Melee damage", "%d-%d" % [m.melee.dmg_min + lv_bonus, m.melee.dmg_max + lv_bonus]],
		["Attacks / sec", "%.2f" % (m.atk_mult() / m.melee.speed)],
		["Move speed", "%d%%" % roundi(m.move_speed() / m.PLAYER_SPEED * 100.0)],
	]
	for st in stats:
		_label(st[0], Vector2(sx, sy), 13, Color(0.7, 0.65, 0.55), HORIZONTAL_ALIGNMENT_LEFT)
		_label(st[1], Vector2(p.end.x - 18, sy), 13, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_RIGHT)
		sy += 19

	# Attributes
	var pts: int = m.stat_points
	_label("Attributes", Vector2(p.position.x + 26, p.position.y + 250), 13, Color(0.8, 0.75, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
	if pts > 0:
		var t := Time.get_ticks_msec() / 1000.0
		_label("%d point%s to spend" % [pts, "" if pts == 1 else "s"], Vector2(p.end.x - 18, p.position.y + 250), 13,
			Color(1.0, 0.85, 0.3, 0.7 + 0.3 * sin(t * 5.0)), HORIZONTAL_ALIGNMENT_RIGHT)
	var a: Dictionary = m.attr
	var rows := [
		["Strength", a.strength, "+%d melee damage" % (a.strength * m.STR_DMG), "+%d melee damage per point" % m.STR_DMG],
		["Speed", a.speed, "+%d%% move  +%d%% attack" % [a.speed * 6, a.speed * 5] + ("  (max)" if a.speed >= m.SPEED_CAP else ""),
			"+6%% move speed, +5%% attack/reload speed (max %d)" % m.SPEED_CAP],
		["Max Life", a.life, "+%d life" % (a.life * m.LIFE_PER), "+%d max life per point" % m.LIFE_PER],
		["Max Bolts" if knight else "Max Mana", a.capacity,
			("+%d bolts" % (a.capacity * m.BOLTS_PER)) if knight else ("+%d mana" % (a.capacity * m.MANA_PER)),
			("+%d bolt capacity per point" % m.BOLTS_PER) if knight else ("+%d max mana per point" % m.MANA_PER)],
	]
	var attr_tip := ""
	for i in 4:
		var b := attr_button_rect(i)
		var cy := b.get_center().y
		_label(rows[i][0], Vector2(p.position.x + 26, cy), 14, Color(0.9, 0.85, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
		_label(str(rows[i][1]), Vector2(p.position.x + 130, cy), 14, Color(1, 1, 1))
		_label(rows[i][2], Vector2(p.position.x + 156, cy), 12, Color(0.65, 0.75, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
		var ok: bool = m.can_spend(m.ATTRS[i])
		var hot := b.has_point(mouse)
		draw_rect(b, Color(0.35, 0.27, 0.1) if ok and hot else (Color(0.2, 0.16, 0.08) if ok else Color(0.09, 0.08, 0.07)))
		draw_rect(b, Color(1.0, 0.8, 0.3) if ok else Color(0.3, 0.26, 0.2), false, 1.5)
		_label("+", b.get_center() + Vector2(0, -1), 18, Color(1.0, 0.9, 0.5) if ok else Color(0.35, 0.32, 0.28))
		if hot:
			attr_tip = rows[i][3]
	if attr_tip != "":
		var tw := 330.0
		var tr := Rect2(mouse + Vector2(-tw - 12, 10), Vector2(tw, 26))
		draw_rect(tr, Color(0.03, 0.03, 0.03, 0.95))
		draw_rect(tr, gold_line, false, 1.5)
		_label(attr_tip, tr.get_center(), 13, Color(0.95, 0.92, 0.85))

	# Backpack
	_label("Backpack", Vector2(p.position.x + 26, p.position.y + 388), 13, Color(0.8, 0.75, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
	for i in m.BAG_SIZE:
		var c := _bag_cell(i)
		var w = m.bag[i]
		var bg := Color(0.1, 0.09, 0.08)
		if w != null and not m.can_use(w):
			bg = Color(0.22, 0.06, 0.04)
		draw_rect(c, bg)
		draw_rect(c, gold_line.lightened(0.25) if c.has_point(mouse) else Color(0.3, 0.25, 0.17), false, 1.0)
		if w != null:
			_weapon_icon(w, c, 0.75 if w.style != "crossbow" else 1.2)
	_label("LMB: equip    RMB: sell to merchant" if m.shop_open else "LMB: equip    RMB: drop on floor", Vector2(p.get_center().x, p.end.y - 14), 12, Color(0.6, 0.55, 0.45))

	# Tooltip
	var slot := inv_slot_at(mouse)
	var hovered = null
	if slot.get("type") == "melee":
		hovered = m.melee
	elif slot.get("type") == "ranged":
		hovered = m.bow
	elif slot.get("type") == "bag":
		hovered = m.bag[slot.i]
	if hovered != null:
		_tooltip(hovered, mouse, slot.get("type") == "bag")
	if slot.get("type") == "spell" or (not knight and slot.get("type") == "ranged"):
		_spell_tooltip(slot.get("id", m.selected_spell), mouse, false)


func _spell_tooltip(id: String, at: Vector2, right: bool) -> void:
	var m = main
	var lv: int = m.spell_lvl.get(id, 0)
	var sp: Dictionary = m.SPELLS[id]
	var lines: Array = []
	lines.append([sp.name + ("  — Level %d" % lv if lv > 0 else "  — not learned"), sp.col])
	if lv > 0:
		lines.append([m.spell_desc(id, lv), Color(0.9, 0.9, 0.9)])
		if m.hero == "paladin":
			lines.append(["%d mana  ·  key %s" % [int(m.SPELL_COST[id]), m.spell_key(id)], Color(0.6, 0.7, 1.0)])
		else:
			lines.append(["%.0fs recharge  ·  key %s  ·  F / middle mouse" % [m.knight_cd(id), m.spell_key(id)], Color(0.6, 0.7, 1.0)])
		if lv < m.SPELL_MAX:
			lines.append(["Next level: " + m.spell_desc(id, lv + 1), Color(0.6, 0.85, 0.6)])
		else:
			lines.append(["Maximum level", Color(1.0, 0.85, 0.3)])
		if not right:
			lines.append(["LMB: make this your active spell", Color(0.65, 0.6, 0.5)])
	else:
		lines.append(["Read its scroll to learn: " + m.spell_desc(id, 1), Color(0.75, 0.7, 0.6)])
	var wdt := 330.0
	var h := 14.0 + lines.size() * 18.0
	var pos := at + (Vector2(16, 8) if right else Vector2(-wdt - 16, 8))
	pos.x = clampf(pos.x, 4.0, size.x - wdt - 4.0)
	pos.y = minf(pos.y, size.y - h - 40)
	var r := Rect2(pos, Vector2(wdt, h))
	draw_rect(r, Color(0.03, 0.03, 0.03, 0.95))
	draw_rect(r, Color(0.45, 0.36, 0.22), false, 1.5)
	var y := pos.y + 16
	for ln in lines:
		_label(ln[0], Vector2(pos.x + wdt / 2, y), 13 if ln != lines[0] else 15, ln[1])
		y += 18


func _tooltip(w, at: Vector2, in_bag: bool, right := false) -> void:
	var m = main
	var usable: bool = m.can_use(w)
	var lines: Array = []   # [text, color]
	var title_col := Color(1.0, 0.85, 0.35) if w.bonus > 0 else Color(0.95, 0.95, 0.95)
	if not usable:
		title_col = Color(1.0, 0.4, 0.3)
	lines.append([w.label(), title_col])
	lines.append(["Damage: %d-%d" % [w.dmg_min, w.dmg_max], Color(0.85, 0.85, 0.85)])
	if w.ranged:
		lines.append(["Reload: %.2fs" % w.speed, Color(0.85, 0.85, 0.85)])
	else:
		lines.append(["Attacks / sec: %.1f" % (1.0 / w.speed), Color(0.85, 0.85, 0.85)])
		if w.reach > 0:
			lines.append(["Reach: +%d" % int(w.reach), Color(0.85, 0.85, 0.85)])
		match w.style:
			"hammer": lines.append(["Hits stun enemies", Color(0.6, 0.75, 1.0)])
			"halberd": lines.append(["Long reach, narrow arc", Color(0.6, 0.75, 1.0)])
	if w.heavy:
		lines.append(["Heavy — requires Knight", Color(1.0, 0.4, 0.3) if not usable else Color(0.7, 0.65, 0.55)])
	if in_bag and usable:
		var cur = m.bow if w.ranged else m.melee
		if cur != null:
			var diff: float = (w.dmg_min + w.dmg_max) / 2.0 - (cur.dmg_min + cur.dmg_max) / 2.0
			if not w.ranged:
				diff = (w.dmg_min + w.dmg_max) / 2.0 / w.speed - (cur.dmg_min + cur.dmg_max) / 2.0 / cur.speed
				lines.append(["%+.1f damage/sec vs equipped" % diff, Color(0.4, 1.0, 0.4) if diff >= 0 else Color(1.0, 0.45, 0.4)])
			else:
				lines.append(["%+.1f avg damage vs equipped" % diff, Color(0.4, 1.0, 0.4) if diff >= 0 else Color(1.0, 0.45, 0.4)])
	if in_bag and m.shop_open and not right:
		lines.append(["Sells for %d gold (RMB)" % m.sell_value(m.weapon_price(w)), Color(1.0, 0.85, 0.3)])
	if right:
		lines.append(["Price: %d gold" % m.weapon_price(w), Color(1.0, 0.85, 0.3) if m.gold >= m.weapon_price(w) else Color(1.0, 0.4, 0.3)])
	var h := 14.0 + lines.size() * 18.0
	var wdt := 250.0
	var pos := at + (Vector2(16, 8) if right else Vector2(-wdt - 16, 8))
	pos.x = maxf(pos.x, 4.0)
	pos.y = minf(pos.y, size.y - h - 40)
	var r := Rect2(pos, Vector2(wdt, h))
	draw_rect(r, Color(0.03, 0.03, 0.03, 0.95))
	draw_rect(r, Color(0.45, 0.36, 0.22), false, 1.5)
	var y := pos.y + 16
	for ln in lines:
		_label(ln[0], Vector2(pos.x + wdt / 2, y), 13 if ln != lines[0] else 15, ln[1])
		y += 18


# ================================================================ manual

const MANUAL_TABS := ["Heroes", "Weapons", "Magic", "Enemies", "Bosses", "Items & Tips"]


func manual_button_rect() -> Rect2:
	return Rect2(size.x / 2 - 110, size.y * 0.32 + 404, 220, 30)


func _manual_rect() -> Rect2:
	return Rect2(Vector2(60, 30), size - Vector2(120, 60))


func manual_tab_rect(i: int) -> Rect2:
	var r := _manual_rect()
	var w := (r.size.x - 40) / MANUAL_TABS.size()
	return Rect2(r.position.x + 20 + i * w, r.position.y + 58, w - 6, 30)


func manual_close_rect() -> Rect2:
	var r := _manual_rect()
	return Rect2(r.end.x - 40, r.position.y + 12, 28, 28)


func _draw_manual() -> void:
	var m = main
	var r := _manual_rect()
	var mouse := get_local_mouse_position()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	draw_rect(r, Color(0.06, 0.05, 0.045, 0.98))
	draw_rect(r, Color(0.55, 0.43, 0.25), false, 2.0)
	draw_rect(r.grow(-4), Color(0.3, 0.24, 0.15), false, 1.0)
	_label("HOW TO PLAY", Vector2(r.get_center().x, r.position.y + 28), 28, Color(0.95, 0.65, 0.3))
	var cr := manual_close_rect()
	draw_rect(cr, Color(0.3, 0.1, 0.06) if cr.has_point(mouse) else Color(0.12, 0.08, 0.06))
	draw_rect(cr, Color(0.6, 0.45, 0.25), false, 1.5)
	_label("X", cr.get_center() + Vector2(0, -1), 15, Color(1, 0.85, 0.7))
	for i in MANUAL_TABS.size():
		var tr := manual_tab_rect(i)
		var sel: bool = i == m.manual_page
		draw_rect(tr, Color(0.22, 0.16, 0.08) if sel else (Color(0.13, 0.1, 0.07) if tr.has_point(mouse) else Color(0.09, 0.08, 0.07)))
		draw_rect(tr, Color(1.0, 0.8, 0.35) if sel else Color(0.4, 0.32, 0.2), false, 2.0 if sel else 1.0)
		_label(MANUAL_TABS[i], tr.get_center() + Vector2(0, -1), 15, Color(1.0, 0.88, 0.6) if sel else Color(0.75, 0.7, 0.6))
	var x := r.position.x + 36
	var y := r.position.y + 120
	match m.manual_page:
		0: _manual_heroes(x, y)
		1: _manual_weapons(x, y)
		2: _manual_magic(x, y)
		3: _manual_enemies(x, y)
		4: _manual_bosses(x, y)
		5: _manual_tips(x, y)
	_label("Click a tab or use ← →   ·   Esc / H to close", Vector2(r.get_center().x, r.end.y - 18), 13, Color(0.6, 0.55, 0.45))


## Writes a heading and lines of text, returns the y after them.
func _section(x: float, y: float, title: String, col: Color, lines: Array, w := 1100.0) -> float:
	_label(title, Vector2(x, y), 18, col, HORIZONTAL_ALIGNMENT_LEFT)
	y += 24
	for ln in lines:
		_label_w(str(ln), Vector2(x + 12, y), 14, Color(0.86, 0.83, 0.76), w)
		y += 19
	return y + 8


func _label_w(s: String, pos: Vector2, sz: int, col: Color, w: float) -> void:
	draw_string_outline(font, Vector2(pos.x, pos.y + sz * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, w, sz, 3, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, Vector2(pos.x, pos.y + sz * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, w, sz, col)


func _manual_heroes(x: float, y: float) -> void:
	var cx := x + 560.0
	_section(x, y, "KNIGHT — steel, shield and crossbow", CLASSES[0].col, [
		"120 life, 25% chance to block melee hits.",
		"Uses every weapon, including the heavy",
		"  Greatsword, War Hammer and Halberd.",
		"RMB: fire the crossbow (uses bolts).",
		"Q: Shield Bash — knocks back and stuns",
		"  everything in front of you (5 s cooldown).",
		"Scrolls teach him spells too. With no mana,",
		"  he casts with F / middle mouse and waits",
		"  for each spell to recharge.",
	], 500.0)
	_section(cx, y, "PALADIN — holy warrior", CLASSES[1].col, [
		"95 life, 60 mana, 12% block.",
		"Light weapons only: swords, maces, flails.",
		"RMB: cast the active spell (Holy Bolt at start).",
		"Q: Healing Light (20 mana) — heals you and",
		"  burns nearby undead.",
		"Scrolls teach him spells for good; reading the",
		"  same scroll again levels the spell up (max 5).",
		"Pick the active spell with 3-7 or the wheel.",
	], 500.0)
	_section(x, y + 210, "Growing stronger", Color(1.0, 0.85, 0.35), [
		"Every level up gives 1 attribute point; every boss you kill gives 3. Spend them in the inventory (I).",
		"Strength: +2 melee damage.   Speed: +6% move and +5% attack speed (max 10).",
		"Max Life: +15 life.   Max Bolts (Knight): +15 bolts.   Max Mana (Paladin): +10 mana.",
		"Life and mana never come back by themselves — only from potions, level ups and Healing Light.",
	])


func _manual_weapons(x: float, y: float) -> void:
	var m = main
	var notes := {"Greatsword": "Wide sweeping swings", "War Hammer": "Hits stun enemies", "Halberd": "Longest reach, narrow arc",
		"Flail": "Extra reach", "Short Sword": "Fastest", "Arming Sword": "Balanced", "Mace": "Solid all-rounder"}
	_label("Melee weapons", Vector2(x, y), 18, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_LEFT)
	var cols := [x + 70, x + 250, x + 360, x + 470, x + 560, x + 680]
	var hdr := ["Weapon", "Damage", "Hits/sec", "Reach", "Who", "Notes"]
	for i in hdr.size():
		_label(hdr[i], Vector2(cols[i], y + 26), 13, Color(0.65, 0.6, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	var yy := y + 52
	for name in m.MELEE:
		var d: Array = m.MELEE[name]
		var w = m._make_melee(name, 0)
		_weapon_icon(w, Rect2(x, yy - 16, 56, 32), 0.7)
		_label(name, Vector2(cols[0], yy), 15, Color(0.95, 0.9, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
		_label("%d-%d" % [d[0], d[1]], Vector2(cols[1], yy), 14, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_label("%.1f" % (1.0 / d[2]), Vector2(cols[2], yy), 14, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_label("+%d" % d[3] if d[3] > 0 else "—", Vector2(cols[3], yy), 14, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_label("Knight" if d[4] else "Both", Vector2(cols[4], yy), 14, Color(1.0, 0.55, 0.4) if d[4] else Color(0.6, 0.9, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
		_label(notes.get(name, ""), Vector2(cols[5], yy), 14, Color(0.75, 0.72, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
		yy += 36
	_label("Crossbows (Knight only)", Vector2(x, yy + 4), 18, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_LEFT)
	yy += 40
	for name in m.CROSSBOWS:
		var d: Array = m.CROSSBOWS[name]
		var w = m._make_crossbow(name, 0)
		_weapon_icon(w, Rect2(x, yy - 16, 56, 32), 1.0)
		_label(name, Vector2(cols[0], yy), 15, Color(0.95, 0.9, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
		_label("%d-%d" % [d[0], d[1]], Vector2(cols[1], yy), 14, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_label("reload %.2fs" % d[2], Vector2(cols[2], yy), 14, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_label("Uses 1 bolt per shot", Vector2(cols[5], yy), 14, Color(0.75, 0.72, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
		yy += 36
	_label_w("Found weapons can roll a +bonus (+2 min / +3 max damage per +1). Hover items in the inventory to compare with what you hold.",
		Vector2(x, yy + 6), 13, Color(0.7, 0.66, 0.58), 1100.0)


func _manual_magic(x: float, y: float) -> void:
	var m = main
	_label_w("Spell scrolls are sold by the merchant. Reading one teaches you the spell for good; every further scroll of it raises it a level (max 5).",
		Vector2(x, y), 14, Color(0.86, 0.83, 0.76), 1120.0)
	_label_w("Pick the active spell with keys 3-7 or the mouse wheel. Paladin: RMB, costs mana. Knight: F / middle mouse, then it recharges.",
		Vector2(x, y + 20), 14, Color(0.86, 0.83, 0.76), 1120.0)
	var yy := y + 64
	var cols := [x + 36, x + 220, x + 300, x + 640]
	var hdr := ["Spell", "Mana / Knight", "At level 1", "At level 5"]
	for i in hdr.size():
		_label(hdr[i], Vector2(cols[i], yy), 13, Color(0.65, 0.6, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	yy += 28
	var blurb := {"holy": "Paladin's starting spell — a fast bolt of light.",
		"fireball": "Flies to the cursor and explodes, scorching the floor.",
		"frost": "A ring of ice around you; frozen enemies can't move or attack.",
		"lightning": "Strikes the enemy nearest the cursor and jumps onward.",
		"ward": "A golden shield that soaks up most incoming damage."}
	for id in m.PALADIN_SPELLS:
		var sp: Dictionary = m.SPELLS[id]
		draw_circle(Vector2(x + 14, yy + 6), 10, sp.col.darkened(0.3))
		draw_circle(Vector2(x + 12, yy + 4), 6, sp.col)
		_label(sp.name, Vector2(cols[0], yy), 16, sp.col.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT)
		var cost := str(int(m.SPELL_COST[id])) + ("  /  %ds" % int(m.KNIGHT_CD[id]) if m.KNIGHT_CD.has(id) else "  /  —")
		_label(cost, Vector2(cols[1], yy), 14, Color(0.6, 0.7, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
		_label(m.spell_desc(id, 1), Vector2(cols[2], yy), 14, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_label(m.spell_desc(id, 5), Vector2(cols[3], yy), 14, Color(0.6, 0.9, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
		_label(blurb[id], Vector2(cols[0], yy + 19), 13, Color(0.7, 0.66, 0.58), HORIZONTAL_ALIGNMENT_LEFT)
		yy += 50
	_section(x, yy + 6, "Class skills (Q)", Color(1.0, 0.85, 0.35), [
		"Knight — Shield Bash: shoves and stuns every enemy in a wide arc in front of you.",
		"Paladin — Healing Light: 20 mana, restores life and sears undead around you.",
	])


func _manual_enemies(x: float, y: float) -> void:
	var foes := [
		["Shambler", "Slow, lurching and common. Weak alone, dangerous in crowds.", "Depth 1+"],
		["Fresh Runner", "Recently turned and fast. Attacks quickly but has little life.", "Depth 1+"],
		["Bile Spitter", "Keeps its distance and spits acid bile. Close in or shoot it.", "Depth 1+"],
		["Bloater", "Swollen with rot. Bursts when killed, hurting everything nearby — you included.", "Depth 1+"],
		["Fallen Man-at-Arms", "Armored (3 damage absorbed per hit). Heavy hits and magic work best.", "Depth 2+"],
		["Butcher", "Huge and brutal, with lots of life and heavy blows from his cleaver.", "Depth 3+"],
		["Giggling Spawn", "Red spiders the Drain Clown bursts into. Fast biters — kill all 10.", "Boss 1"],
		["Elites", "Named, golden-glowing versions with 3x life. One guards the stairs; they drop loot.", "Every floor"],
		["Small spiders", "Harmless critters. Step on them or swat them for fun.", "Everywhere"],
	]
	var cw := 362.0
	for i in foes.size():
		var f: Array = foes[i]
		var c := Rect2(x + (i % 3) * cw, y - 10 + (i / 3) * 146, cw - 12, 136)
		draw_rect(c, Color(0.09, 0.075, 0.06))
		draw_rect(c, Color(0.3, 0.24, 0.15), false, 1.0)
		_portrait(i, Rect2(c.position + Vector2(6, 22), Vector2(104, 104)))
		_label(f[0], c.position + Vector2(10, 13), 16, Color(0.95, 0.75, 0.55), HORIZONTAL_ALIGNMENT_LEFT)
		_label(f[2], Vector2(c.end.x - 10, c.position.y + 13), 12, Color(0.6, 0.55, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
		_wrapped(f[1], c.position + Vector2(116, 42), 14, Color(0.86, 0.83, 0.76), c.size.x - 124)
	_label_w("Enemies grow tougher with every depth, and each level tints the dead in its own colours. Difficulty changes their life and how hard they hit.",
		Vector2(x, y + 432), 13, Color(0.7, 0.66, 0.58), 1120.0)


func _manual_bosses(x: float, y: float) -> void:
	y = _section(x, y, "When 3 or fewer enemies remain, the floor's boss arrives. The stairs stay sealed until it dies.", Color(0.9, 0.82, 0.6), [
		"Bosses drop two improved weapons, gold and potions, give 3 attribute points, and a merchant appears afterwards.",
		"After depth 3 they return, stronger each round.",
	])
	var bosses := [
		[[9], "Mr. Giggles, the Drain Clown  (depth 1)", Color(1.0, 0.45, 0.35), [
			"Vanishes in a puff and reappears beside you, laughing. Releases floating red balloons",
			"that drift after you and burst. Your sword pops balloons.",
			"When he dies he bursts into 10 red spiders — he only counts as beaten when all are dead.",
		]],
		[[10, 11], "The Lakeside Slasher  (depth 2)", Color(0.85, 0.85, 0.75), [
			"Armored, can't be stunned or knocked back. A red line warns of his charge — step out of the way.",
			"Below half life his mask cracks off, showing what's beneath (right), and he gets faster.",
		]],
		[[12], "The Nightmare Man  (depth 3)", Color(0.95, 0.4, 0.3), [
			"Fades until only his glowing eyes show, then appears behind you, slashing with a bladed glove.",
			"He can also shrink your torchlight to a small circle for a few seconds.",
		]],
	]
	var sz := 112.0
	for b in bosses:
		var pics: Array = b[0]
		var c := Rect2(x - 6, y - 4, 1100, sz + 8)
		draw_rect(c, Color(0.09, 0.075, 0.06))
		draw_rect(c, Color(0.3, 0.24, 0.15), false, 1.0)
		for k in pics.size():
			_portrait(pics[k], Rect2(Vector2(x + k * (sz - 6), y), Vector2(sz, sz)))
		var tx := x + 2 * (sz - 6) + 14
		_section(tx, y + 14, b[1], b[2], b[3], 1100 - (tx - x))
		y += sz + 16


## Picture i of the manual's portraits (portrait.gd), framed.
func _portrait(i: int, at: Rect2) -> void:
	if main.portraits == null:
		return
	draw_texture_rect(main.portraits.get_child(i).get_texture(), at, false)
	draw_rect(at, Color(0.4, 0.32, 0.2), false, 1.0)


func _wrapped(s: String, pos: Vector2, sz: int, col: Color, w: float) -> void:
	draw_multiline_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, w, sz, -1, 3, Color(0, 0, 0, 0.85))
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, w, sz, -1, col)


func _manual_tips(x: float, y: float) -> void:
	var cx := x + 560.0
	_section(x, y, "Items", Color(1.0, 0.85, 0.35), [
		"Healing potion (1) — restores 45% life.",
		"Mana potion (2, Paladin) — restores 60% mana.",
		"You can carry up to 99 of each potion.",
		"Bolts refill the Knight's crossbow.",
		"Items fly to you when you walk close, and",
		"  vanish after 10 seconds — grab them fast.",
		"Gold buys gear from the wandering merchant",
		"  (it sells back at 40%). Time stops while",
		"  you trade.",
	], 520.0)
	_section(cx, y, "Controls", Color(1.0, 0.85, 0.35), [
		"LMB: move / attack / pick up / stairs (hold)",
		"Shift+LMB: attack in place",
		"RMB: crossbow or active spell",
		"Q: class skill    1 / 2: potions",
		"3-7 or mouse wheel: pick spell    F / MMB: Knight casts",
		"I or Tab: inventory    M: minimap    N: music",
		"Enter: next boss (Boss Rush)    F9: debug mode",
		"Esc: close windows / quit",
	], 520.0)
	_section(x, y + 230, "Modes", Color(1.0, 0.85, 0.35), [
		"Campaign: descend floor by floor, a boss at the end of each.",
		"Boss Rush: all three bosses back to back in one arena; best times are kept per difficulty.",
		"Difficulty: Easy (enemies 70% life, hit for 60%) · Normal · Hard (135% / 140%) · Nightmare (180% / 190%).",
	])


# ================================================================ store

func shop_rect() -> Rect2:
	return Rect2(20, 10, 440, 600)


func _stock_cell(i: int) -> Rect2:
	var p := shop_rect()
	return Rect2(p.position + Vector2(26 + i * 100, 96), Vector2(88, 88))


func _shop_row(i: int) -> Rect2:
	var p := shop_rect()
	return Rect2(p.position + Vector2(18, 236 + i * 37 + (26 if i >= 2 else 0)), Vector2(p.size.x - 36, 33))


func _buy_btn(i: int) -> Rect2:
	var r := _shop_row(i)
	return Rect2(r.end.x - 152, r.position.y + 4, 72, 25)


func _sell_btn(i: int) -> Rect2:
	var r := _shop_row(i)
	return Rect2(r.end.x - 74, r.position.y + 4, 72, 25)


func _leave_btn() -> Rect2:
	var p := shop_rect()
	return Rect2(p.get_center().x - 120, p.end.y - 50, 240, 34)


func shop_slot_at(pos: Vector2) -> Dictionary:
	for i in 4:
		if _stock_cell(i).has_point(pos):
			return {"type": "stock", "i": i}
	var items: Array = main.shop_items()
	for i in items.size():
		if _buy_btn(i).has_point(pos):
			return {"type": "buy", "k": items[i]}
		if _sell_btn(i).has_point(pos):
			return {"type": "sell", "k": items[i]}
	if _leave_btn().has_point(pos):
		return {"type": "leave"}
	return {}


func _button(r: Rect2, text: String, enabled: bool, mouse: Vector2) -> void:
	var hot := enabled and r.has_point(mouse)
	draw_rect(r, Color(0.3, 0.22, 0.1) if hot else (Color(0.16, 0.12, 0.07) if enabled else Color(0.08, 0.07, 0.06)))
	draw_rect(r, Color(1.0, 0.8, 0.35) if hot else (Color(0.55, 0.43, 0.25) if enabled else Color(0.25, 0.22, 0.18)), false, 1.5)
	_label(text, r.get_center() + Vector2(0, -1), 13, Color(1.0, 0.92, 0.7) if enabled else Color(0.4, 0.37, 0.32))


func _draw_shop() -> void:
	var m = main
	var p := shop_rect()
	var mouse := get_local_mouse_position()
	var gold_line := Color(0.45, 0.36, 0.22)
	draw_rect(p, Color(0.06, 0.05, 0.045, 0.97))
	draw_rect(p, gold_line, false, 2.0)
	draw_rect(p.grow(-4), Color(0.3, 0.24, 0.15), false, 1.0)
	_label("WANDERING MERCHANT", Vector2(p.get_center().x, p.position.y + 24), 22, Color(0.95, 0.8, 0.5))
	_label("[Esc] close", Vector2(p.end.x - 14, p.position.y + 24), 12, Color(0.6, 0.55, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("\"Fine steel, potions, scrolls... gold only, friend.\"", Vector2(p.get_center().x, p.position.y + 48), 13, Color(0.75, 0.68, 0.55))
	_label("Your gold: %d" % m.gold, Vector2(p.get_center().x, p.position.y + 68), 15, Color(1.0, 0.82, 0.3))

	# Weapons
	_label("Weapons", Vector2(p.position.x + 26, p.position.y + 86), 13, Color(0.8, 0.75, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
	var hovered = null
	for i in 4:
		var c := _stock_cell(i)
		var w = m.shop_stock[i] if i < m.shop_stock.size() else null
		var hot := c.has_point(mouse) and w != null
		draw_rect(c, Color(0.1, 0.09, 0.08))
		draw_rect(c, gold_line.lightened(0.3) if hot else Color(0.3, 0.25, 0.17), false, 1.5)
		if w == null:
			_label("SOLD", c.get_center(), 14, Color(0.45, 0.4, 0.35))
			continue
		_weapon_icon(w, c.grow(-6) if w.style != "halberd" else c, 1.35 if w.style != "crossbow" else 2.0)
		_label(w.base, Vector2(c.get_center().x, c.position.y + 10), 11, Color(0.85, 0.8, 0.7) if m.can_use(w) else Color(1.0, 0.4, 0.3))
		var price: int = m.weapon_price(w)
		_label("%d g" % price, Vector2(c.get_center().x, c.end.y + 12), 13, Color(1.0, 0.82, 0.3) if m.gold >= price else Color(0.9, 0.35, 0.3))
		if hot:
			hovered = w
	_label("Click a weapon to buy it", Vector2(p.get_center().x, p.position.y + 216), 12, Color(0.6, 0.55, 0.45))

	# Supplies and scrolls
	var items: Array = m.shop_items()
	_label("Supplies", Vector2(p.position.x + 26, _shop_row(0).position.y - 8), 13, Color(0.8, 0.75, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
	_label("Spell scrolls — learn a spell, or raise its level", Vector2(p.position.x + 26, _shop_row(2).position.y - 9), 13, Color(0.8, 0.75, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
	var tip := ""
	for i in items.size():
		var k: String = items[i]
		var r := _shop_row(i)
		draw_rect(r, Color(0.09, 0.08, 0.07))
		var col := Color(0.85, 0.15, 0.15)
		match k:
			"mp": col = Color(0.2, 0.35, 1.0)
			"bolts": col = Color(0.6, 0.5, 0.35)
			_:
				if m.SPELLS.has(k):
					col = m.SPELLS[k].col
		draw_circle(r.position + Vector2(18, 18), 9, col.darkened(0.3))
		draw_circle(r.position + Vector2(16, 16), 5, col)
		var title: String = m.item_name(k)
		if m.SPELLS.has(k):
			title += "  [%s]" % m.spell_key(k)
		_label(title, r.position + Vector2(36, 17), 14, Color(0.92, 0.88, 0.78), HORIZONTAL_ALIGNMENT_LEFT)
		var owned: int = m.item_owned(k)
		var price: int = m.item_price(k)
		var spell_book: bool = m.SPELLS.has(k)
		if spell_book:
			_label(("Lv %d" % owned) if owned > 0 else "unknown", Vector2(r.end.x - 160, r.position.y + 17), 12,
				Color(0.6, 0.75, 1.0) if owned > 0 else Color(0.55, 0.5, 0.42), HORIZONTAL_ALIGNMENT_RIGHT)
			var maxed: bool = owned >= m.SPELL_MAX
			_button(_buy_btn(i), "Max" if maxed else ("Read %d" % price), m.gold >= price and not maxed, mouse)
			_button(_sell_btn(i), "—", false, mouse)
		else:
			_label("have %d" % owned, Vector2(r.end.x - 160, r.position.y + 17), 12, Color(0.65, 0.6, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
			_button(_buy_btn(i), "Buy %d" % price, m.gold >= price, mouse)
			_button(_sell_btn(i), "Sell %d" % m.sell_value(price), owned >= (15 if k == "bolts" else 1), mouse)
		if r.has_point(mouse) and m.SPELLS.has(k):
			tip = k

	var footer := "RMB on a backpack weapon (right panel) to sell it"
	_label(footer, Vector2(p.get_center().x, _leave_btn().position.y - 16), 12, Color(0.6, 0.55, 0.45))
	_button(_leave_btn(), "Fight the next boss  [Enter]" if m.rush else "Leave", true, mouse)

	if tip != "":
		_spell_tooltip(tip, mouse, true)
	if hovered != null:
		_tooltip(hovered, mouse, true, true)


func _draw_menu() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.55))
	var t := Time.get_ticks_msec() / 1000.0
	_label("ASHEN DEPTHS", Vector2(sz.x / 2, sz.y * 0.13), 64, Color(0.9, 0.55, 0.25))
	_label("The dead of Emberfall have risen. Choose who descends.", Vector2(sz.x / 2, sz.y * 0.22), 18, Color(0.8, 0.75, 0.65))
	var mouse := get_local_mouse_position()
	for i in 2:
		var c: Dictionary = CLASSES[i]
		var rect := card_rect(i)
		var hot := rect.has_point(mouse)
		var col: Color = c.col
		draw_rect(rect, Color(0.08, 0.07, 0.06, 0.95))
		draw_rect(rect, col if hot else Color(0.4, 0.33, 0.22), false, 3.0 if hot else 1.5)
		if hot:
			draw_rect(rect.grow(-3), Color(col, 0.06 + 0.03 * sin(t * 4.0)))
		_label(c.name, Vector2(rect.get_center().x, rect.position.y + 34), 32, col)
		_label(c.tag, Vector2(rect.get_center().x, rect.position.y + 70), 15, Color(0.8, 0.75, 0.65))
		var y: float = rect.position.y + 112
		for line in c.lines:
			_label(line, Vector2(rect.position.x + 24, y), 15, Color(0.85, 0.82, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
			y += 26
		_label("[%d]" % (i + 1), Vector2(rect.get_center().x, rect.end.y - 18), 14, Color(0.6, 0.55, 0.45))
	var mr := mode_rect()
	var mhot := mr.has_point(mouse)
	var rc := Color(0.95, 0.3, 0.2) if main.rush else Color(0.6, 0.5, 0.35)
	draw_rect(mr, Color(0.14, 0.05, 0.04, 0.95) if main.rush else Color(0.08, 0.07, 0.06, 0.95))
	draw_rect(mr, rc if mhot or main.rush else Color(0.4, 0.33, 0.22), false, 2.0)
	_label("Mode:  %s   [B]" % ("BOSS RUSH" if main.rush else "Campaign"), mr.get_center() + Vector2(0, -1), 17, rc.lightened(0.2))
	var dr := diff_rect()
	var dd: Dictionary = main.diff()
	var dhot := dr.has_point(mouse)
	draw_rect(dr, Color(0.08, 0.07, 0.06, 0.95))
	draw_rect(dr, dd.col if dhot else Color(dd.col, 0.6), false, 2.0)
	_label("Difficulty:  %s   [D]" % dd.name.to_upper(), dr.get_center() + Vector2(0, -1), 17, dd.col)
	var sub := "Descend floor by floor through the undead"
	if main.rush:
		sub = "All three bosses, back to back"
		if main.rush_best > 0:
			if main.rush_best >= main.BOSSES.size():
				sub += "   ·   Best clear: %s" % clock(main.rush_best_time)
			else:
				sub += "   ·   Best: %d bosses (%s)" % [main.rush_best, clock(main.rush_best_time)]
	_label(sub, Vector2(sz.x / 2, mr.end.y + 16), 14, Color(0.8, 0.75, 0.65, 0.85))
	_label("Click a class or press 1 / 2", Vector2(sz.x / 2, mr.end.y + 42), 16, Color(1, 1, 1, 0.5 + 0.4 * sin(t * 3.0)))
	var hb := manual_button_rect()
	var hhot := hb.has_point(mouse)
	draw_rect(hb, Color(0.16, 0.12, 0.07) if hhot else Color(0.08, 0.07, 0.06, 0.95))
	draw_rect(hb, Color(1.0, 0.8, 0.35) if hhot else Color(0.55, 0.43, 0.25), false, 1.5)
	_label("How to Play  [H]", hb.get_center() + Vector2(0, -1), 15, Color(0.95, 0.85, 0.6))
	_label("F9: debug mode — %s" % ("ON, invincible" if main.debug else "off"), Vector2(sz.x - 16, sz.y - 18), 13,
		Color(0.4, 0.85, 1.0) if main.debug else Color(0.6, 0.55, 0.45, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)


static func clock(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


func _bar(r: Rect2, fill: float, trail: float, col: Color, text: String) -> void:
	fill = clampf(fill, 0.0, 1.0)
	draw_rect(r.grow(3), Color(0.05, 0.04, 0.035, 0.92))
	draw_rect(r, Color(0.09, 0.07, 0.06))
	# Recently lost amount shows as a pale strip that drains away.
	if trail > fill:
		draw_rect(Rect2(r.position + Vector2(r.size.x * fill, 0), Vector2(r.size.x * (trail - fill), r.size.y)), Color(1.0, 0.9, 0.75, 0.55))
	if fill > 0.0:
		var fr := Rect2(r.position, Vector2(r.size.x * fill, r.size.y))
		draw_rect(fr, col)
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, r.size.y * 0.35)), Color(col.lightened(0.35), 0.8))
		draw_rect(Rect2(fr.position + Vector2(0, r.size.y * 0.8), Vector2(fr.size.x, r.size.y * 0.2)), col.darkened(0.3))
	for k in range(1, 4):   # quarter ticks
		var x := r.position.x + r.size.x * k / 4.0
		draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(0, 0, 0, 0.35), 1.0)
	draw_rect(r.grow(1), Color(0.65, 0.52, 0.3), false, 1.5)
	_label(text, r.get_center() + Vector2(0, -1), 13, Color(1, 1, 1, 0.95))


func _slot(p: Vector2, key: String, count: String, col: Color, cooldown: float) -> void:
	var rect := Rect2(p, Vector2(30, 26))
	draw_rect(rect, Color(0.12, 0.1, 0.08))
	draw_rect(rect, Color(0.45, 0.36, 0.22), false, 1.5)
	if count != "0" and count != "-":
		draw_circle(p + Vector2(15, 15), 7, col)
		if key != "Q":
			draw_rect(Rect2(p + Vector2(13, 4), Vector2(4, 4)), Color(0.7, 0.6, 0.5))
	if cooldown > 0.0:
		draw_rect(Rect2(p, Vector2(30, 26 * cooldown)), Color(0, 0, 0, 0.7))
	_label(key, p + Vector2(5, 9), 10, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	if count != "":
		_label(count, p + Vector2(24, 22), 11, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)


func _label(s: String, pos: Vector2, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var w := 900.0
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w / 2
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	draw_string_outline(font, Vector2(x, pos.y + sz * 0.35), s, align, w, sz, 3, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, Vector2(x, pos.y + sz * 0.35), s, align, w, sz, col)
