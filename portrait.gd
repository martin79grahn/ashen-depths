extends "res://main.gd"
## One enemy or boss for the "How to Play" manual, drawn by the game's own drawing code
## into an off-screen viewport. build() makes one viewport per picture; the HUD shows the
## texture of viewport i.

const CELL := 128
## [kind, elite, unmasked, boss]: matches the order of the manual's Enemies and Bosses lists.
const FOES := [
	["shambler", false, false, false], ["runner", false, false, false], ["spitter", false, false, false],
	["bloater", false, false, false], ["armored", false, false, false], ["butcher", false, false, false],
	["red_spider", false, false, false], ["shambler", true, false, false], ["small_spider", false, false, false],
	["clown", false, false, true], ["slasher", false, false, true], ["slasher", false, true, true],
	["dream", false, false, true],
]
const FIRST_BOSS := 9

var foe: Enemy
var game          # the real main node (for env's spider drawing)


static func build(m: Node) -> Node:
	var holder := Node.new()
	m.add_child(holder)
	var script: Script = load("res://portrait.gd")
	for i in FOES.size():
		var f: Array = FOES[i]
		# Each picture gets its own viewport, so long weapons can't spill into the next one.
		var vp := SubViewport.new()
		vp.size = Vector2i(CELL, CELL)
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		holder.add_child(vp)
		var cm := CanvasModulate.new()
		cm.color = Color(0.9, 0.86, 0.82)
		vp.add_child(cm)
		var n = script.new()
		n.game = m
		n.spheres = m.spheres
		n.font = m.font
		n.stone_tex = m.stone_tex
		n.position = Vector2(CELL * 0.5, CELL * 0.54)
		n.foe = n._make(f[0], f[1], f[2], f[3])
		var span: float = n.foe.radius * (2.0 if f[3] else (3.4 if f[0] == "red_spider" else 2.6))
		n.scale = Vector2.ONE * (CELL * 0.72 / span)
		if f[0] == "small_spider":
			n.scale = Vector2.ONE * 7.0
		vp.add_child(n)
		# A torch above and to the left, so the normal maps give it shape.
		var lamp := PointLight2D.new()
		lamp.texture = m.light_tex
		lamp.texture_scale = 1.0
		lamp.color = Color(1.0, 0.86, 0.66)
		lamp.energy = 0.9
		lamp.height = 60.0
		lamp.position = Vector2(CELL * 0.35, CELL * 0.25)
		vp.add_child(lamp)
	return holder


func _make(kind: String, elite: bool, unmasked: bool, is_boss: bool) -> Enemy:
	var e: Enemy
	if is_boss:
		e = Enemy.new()
		e.boss = true
		e.kind = kind
		for b in BOSSES:
			if b.kind == kind:
				e.radius = b.r
		_boss_looks(e)
		e.unmasked = unmasked
	elif kind == "small_spider":
		e = Enemy.new()
		e.kind = kind
		e.radius = 4.0
	else:
		_spawn_enemy(kind, Vector2.ZERO, elite)
		e = enemies.pop_back()
	e.pos = Vector2.ZERO
	e.facing = Vector2(0.25, 1.0).normalized()
	e.anim = randf() * 10.0
	return e


func _ready() -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _process(delta: float) -> void:
	if get_viewport().render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	foe.anim += delta * 0.6
	queue_redraw()


func _vis(_p: Vector2) -> float:
	return 1.0


func _light_dir(_from: Vector2) -> Vector2:
	return Vector2(-0.4, -0.9).normalized()


func _draw() -> void:
	var e := foe
	# A flagstone floor behind it, tinted like depth 1.
	var half := Vector2.ONE * CELL * 0.5 / scale.x
	draw_texture_rect_region(stone_tex, Rect2(-half - Vector2(0, CELL * 0.04 / scale.x), half * 2.0), Rect2(64, 0, 64, 64))
	for k in 24:   # a soft pool of torchlight under it, so dark clothes stand out
		draw_circle(Vector2.ZERO, half.x * (0.9 - k * 0.032), Color(1.0, 0.8, 0.55, 0.018))
	if e.kind == "small_spider":
		game.env.draw_spider(self, Vector2.ZERO, e.facing, 1.0, e.anim, true, 1.0)
		return
	if e.elite:
		draw_circle(e.pos, e.radius * 1.45, Color(1.0, 0.65, 0.2, 0.12))
		draw_arc(e.pos, e.radius * 1.3, 0, TAU, 32, Color(1.0, 0.7, 0.25, 0.45), 1.0)
	_draw_zombie(e)
	if e.boss or e.kind == "armored":
		return
	var side := e.facing.orthogonal()
	if e.kind == "red_spider":
		for s in [-1.0, 1.0]:
			draw_circle(e.pos + e.facing * e.radius * 0.65 + side * s * e.radius * 0.15, 0.9, Color(1.5, 0.2, 0.1))
		return
	# The eye glint the game draws in its unlit overlay.
	var hd := _zombie_head(e)
	var eye: Vector2 = hd[0] + e.facing * hd[1] * 0.62
	var ec := Color(1.0, 0.85, 0.4) if e.kind != "spitter" else Color(0.7, 1.0, 0.3)
	for s in [-1.0, 1.0]:
		draw_circle(eye + side * s * hd[1] * 0.42, 0.9, Color(ec.r * 1.4, ec.g * 1.4, ec.b * 1.4, 0.85))
