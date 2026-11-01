extends RefCounted
## Dungeon dressing: puddles, bone piles, skeletons, cobwebs, wall torches and scuttling spiders.
## Generated per floor by generate(); main.gd calls update() every frame and the draw_* functions
## from its lit world pass (draw_under / draw_spiders / draw_over) and unlit overlay (draw_flames).

var main
var props: Array = []      # {kind: water|bones|skeleton|web, pos, ...}
var spiders: Array = []    # {pos, dir, speed, move_t, pause, anim, moving, size}
var torches: Array = []    # {pos, light, phase, cell}
var drip_timer := 4.0
var splash_t := 0.0

const BONE := Color(0.78, 0.74, 0.64)


func _init(m) -> void:
	main = m


func clear() -> void:
	for t in torches:
		t.light.queue_free()
	props.clear()
	spiders.clear()
	torches.clear()


func generate() -> void:
	clear()
	var T: int = main.T
	for ri in main.rooms.size():
		var r: Rect2i = main.rooms[ri]
		var area := Rect2(Vector2(r.position) * T, Vector2(r.size) * T)
		var inner := area.grow(-T * 0.9)
		if randf() < 0.45:
			_add_puddle(_spot(inner))
		for k in randi_range(0, 2):
			_add_bones(_spot(inner))
		if randf() < 0.35:
			props.append({"kind": "skeleton", "pos": _spot(inner), "ang": randf() * TAU, "seed": randi()})
		var corners := [
			[area.position, Vector2(1, 1)], [Vector2(area.end.x, area.position.y), Vector2(-1, 1)],
			[Vector2(area.position.x, area.end.y), Vector2(1, -1)], [area.end, Vector2(-1, -1)],
		]
		for c in corners:
			if randf() < 0.4:
				props.append({"kind": "web", "pos": c[0], "dir": c[1], "r": randf_range(18.0, 34.0), "seed": randi()})
		# A torch on the north wall of most rooms.
		if randf() < 0.75:
			var tx := randi_range(r.position.x + 1, r.end.x - 2)
			var cell := Vector2i(tx, r.position.y - 1)
			if main._solid(cell) and not main._solid(cell + Vector2i(0, 1)):
				_add_torch(cell)
		for k in randi_range(1, 3):
			spiders.append({"pos": _spot(inner), "dir": Vector2.from_angle(randf() * TAU), "speed": 60.0,
				"move_t": 0.0, "pause": randf() * 2.0, "anim": randf() * 10.0, "moving": false, "size": randf_range(1.4, 2.0)})
	# A few remains scattered along the corridors.
	for k in 40:
		var c := Vector2i(randi_range(1, main.W - 2), randi_range(1, main.H - 2))
		if not main._solid(c) and not _in_room(c) and randf() < 0.35:
			_add_bones(main._tile_center(c) + Vector2(randf_range(-6, 6), randf_range(-6, 6)))


func _spot(inner: Rect2) -> Vector2:
	for attempt in 8:
		var p := Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
		if p.distance_to(main.stairs_pos) > 40.0 and p.distance_to(main.p_pos) > 40.0:
			return p
	return inner.get_center()


func _in_room(c: Vector2i) -> bool:
	for r in main.rooms:
		if r.has_point(c):
			return true
	return false


func _add_puddle(c: Vector2) -> void:
	var blobs := []
	for k in randi_range(4, 7):
		blobs.append({"o": Vector2.from_angle(randf() * TAU) * randf_range(0, 10), "r": randf_range(6.0, 13.0)})
	props.append({"kind": "water", "pos": c, "blobs": blobs, "ripples": [], "rt": randf_range(1.0, 5.0)})


func _add_bones(c: Vector2) -> void:
	var bones := []
	for k in randi_range(3, 6):
		bones.append({"o": Vector2(randf_range(-8, 8), randf_range(-6, 6)), "ang": randf() * TAU, "len": randf_range(5.0, 9.0)})
	var skull = null
	if randf() < 0.55:
		skull = {"o": Vector2(randf_range(-5, 5), randf_range(-4, 4)), "ang": randf() * TAU}
	props.append({"kind": "bones", "pos": c, "bones": bones, "skull": skull})


func _add_torch(cell: Vector2i) -> void:
	var T: float = main.T
	var pos := Vector2(cell.x * T + T * 0.5, cell.y * T + T * 0.45 + 7.0)
	var light := PointLight2D.new()
	light.texture = main.light_tex
	light.texture_scale = 0.95
	light.color = Color(1.0, 0.6, 0.28)
	light.energy = 0.95
	light.height = 30.0
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	light.position = Vector2(pos.x, (cell.y + 1) * T + 5.0)
	main.add_child(light)
	torches.append({"pos": pos, "light": light, "phase": randf() * 100.0, "cell": cell})


## Visibility contribution from torches the player has already seen.
func torch_vis(p: Vector2) -> float:
	var best := 0.0
	for t in torches:
		var c: Vector2i = t.cell + Vector2i(0, 1)
		if main.explored[c.y * main.W + c.x] == 0:
			continue
		best = maxf(best, clampf(1.0 - p.distance_to(t.light.position) / 230.0, 0.0, 1.0))
	return best


func _visible(p: Vector2) -> bool:
	var c: Vector2i = main._cell(p)
	if c.x < 0 or c.y < 0 or c.x >= main.W or c.y >= main.H:
		return false
	return main.explored[c.y * main.W + c.x] == 1


# ================================================================ update

func update(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for tc in torches:
		var ph: float = tc.phase
		tc.light.energy = 0.85 + 0.1 * sin(t * 9.0 + ph) + 0.07 * sin(t * 23.0 + ph * 2.0)
		tc.light.texture_scale = 0.95 + 0.02 * sin(t * 13.0 + ph)

	_update_spiders(delta)

	# Puddles: drips make ripples; walking through splashes.
	splash_t -= delta
	var moving: bool = not main.path.is_empty() and not main.dead
	for p in props:
		if p.kind != "water":
			continue
		p.rt -= delta
		if p.rt <= 0.0:
			p.rt = randf_range(2.0, 6.0)
			var b: Dictionary = p.blobs.pick_random()
			p.ripples.append({"o": b.o + Vector2.from_angle(randf() * TAU) * randf() * b.r * 0.6, "t": 0.0})
		for i in range(p.ripples.size() - 1, -1, -1):
			p.ripples[i].t += delta
			if p.ripples[i].t > 1.2:
				p.ripples.remove_at(i)
		if moving and splash_t <= 0.0 and _in_water(p, main.p_pos):
			splash_t = 0.3
			p.ripples.append({"o": main.p_pos - p.pos, "t": 0.0})
			main._burst(main.p_pos + Vector2(0, 6), Color(0.55, 0.62, 0.7, 0.7), 8, 70.0, 1.3)
			main.audio.play("splash", main.p_pos, -8.0, 0.15)

	# Distant dripping water.
	drip_timer -= delta
	if drip_timer <= 0.0:
		drip_timer = randf_range(2.5, 7.0)
		var near := []
		for p in props:
			if p.kind == "water" and p.pos.distance_to(main.p_pos) < 600.0:
				near.append(p)
		if not near.is_empty():
			var p: Dictionary = near.pick_random()
			main.audio.play("drip", p.pos, -12.0, 0.2)
			p.ripples.append({"o": Vector2.ZERO, "t": 0.0})


func _in_water(p: Dictionary, pos: Vector2) -> bool:
	for b in p.blobs:
		if pos.distance_to(p.pos + b.o) < b.r:
			return true
	return false


func _update_spiders(delta: float) -> void:
	var pp: Vector2 = main.p_pos
	var player_moving: bool = not main.path.is_empty()
	for i in range(spiders.size() - 1, -1, -1):
		var s: Dictionary = spiders[i]
		s.anim += delta
		var to: Vector2 = s.pos - pp
		var d := to.length()
		if not main.dead and d < 7.0 and player_moving:
			squish(i)
			continue
		if not main.dead and d < 90.0:
			s.dir = s.dir.slerp(to.normalized(), 0.25).normalized()
			s.speed = 150.0
			s.move_t = 0.25
		s.move_t -= delta
		if s.move_t > 0.0:
			var step: Vector2 = s.dir * s.speed * delta
			var np: Vector2 = main._move(s.pos, step, 2.0)
			if np.distance_to(s.pos) < step.length() * 0.3:
				s.dir = s.dir.rotated(randf_range(1.5, 3.0))   # bumped into a wall
			s.pos = np
			s.moving = true
		else:
			s.moving = false
			s.pause -= delta
			if s.pause <= 0.0:
				s.move_t = randf_range(0.15, 0.6)
				s.pause = randf_range(0.4, 2.0)
				s.dir = s.dir.rotated(randf_range(-1.6, 1.6))
				s.speed = randf_range(45.0, 90.0)


func squish(i: int) -> void:
	var s: Dictionary = spiders[i]
	main._decal(s.pos, 2.6 * s.size, Color(0.16, 0.18, 0.07))
	main._burst(s.pos, Color(0.2, 0.22, 0.1), 5, 50.0, 1.0)
	main.audio.play("squelch", s.pos, -14.0, 0.2)
	spiders.remove_at(i)


## Sword swings squash spiders in the arc too.
func hit_arc(origin: Vector2, facing: Vector2, reach: float) -> void:
	for i in range(spiders.size() - 1, -1, -1):
		var to: Vector2 = spiders[i].pos - origin
		if to.length() < reach and absf(facing.angle_to(to)) < 1.1:
			squish(i)


# ================================================================ drawing (lit world pass)

func draw_under(ci: CanvasItem) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for p in props:
		if not _visible(p.pos):
			continue
		match p.kind:
			"water": _draw_water(ci, p, t)
			"bones": _draw_bones(ci, p)
			"skeleton": _draw_skeleton(ci, p)


func draw_over(ci: CanvasItem) -> void:
	for p in props:
		if p.kind == "web" and _visible(p.pos + p.dir * 8.0):
			_draw_web(ci, p)
	for tc in torches:
		if _visible(tc.light.position):
			var q: Vector2 = tc.pos
			ci.draw_rect(Rect2(q + Vector2(-3, 1), Vector2(6, 3)), Color(0.12, 0.11, 0.1))        # iron bracket
			ci.draw_line(q + Vector2(0, 3), q + Vector2(0, -6), Color(0.35, 0.22, 0.12), 2.5)     # wooden haft
			ci.draw_line(q + Vector2(-0.6, 2), q + Vector2(-0.6, -5), Color(0.5, 0.33, 0.18), 0.8)


func draw_spiders(ci: CanvasItem) -> void:
	for s in spiders:
		var a: float = clampf(main._vis(s.pos) * 2.5, 0.0, 1.0)
		if a <= 0.05 or not _visible(s.pos):
			continue
		draw_spider(ci, s.pos, s.dir, s.size, s.anim, s.moving, a)


## One small spider; also used for the manual's portrait.
func draw_spider(ci: CanvasItem, p: Vector2, d: Vector2, k: float, anim: float, moving: bool, a: float) -> void:
	var side := d.orthogonal()
	var sc: Color = main.theme().spider
	var leg_col := Color(sc.darkened(0.2), a)
	ci.draw_circle(p + Vector2(0.8, 1.4), 3.2 * k, Color(0, 0, 0, 0.3 * a))
	for sd in [-1.0, 1.0]:
		for i in 4:
			var phase: float = sin(anim * 32.0 + i * 1.7 + sd) if moving else 0.0
			var base: Vector2 = p + d * (1.2 - i * 0.8) * k
			var out: Vector2 = d.rotated(sd * (0.5 + i * 0.6) + phase * 0.25)
			var knee: Vector2 = base + out * 3.6 * k + side * sd * 0.6 * k
			var tip: Vector2 = knee + out.rotated(sd * 0.6) * 3.2 * k
			ci.draw_line(base, knee, leg_col, 0.8)
			ci.draw_line(knee, tip, leg_col, 0.6)
	ci.draw_circle(p - d * 2.2 * k, 2.6 * k, Color(sc, a))
	ci.draw_circle(p - d * 2.6 * k + Vector2(-0.6, -0.6), 1.1 * k, Color(sc.lightened(0.25), a))
	ci.draw_circle(p + d * 0.9 * k, 1.6 * k, Color(sc.darkened(0.15), a))


func _draw_water(ci: CanvasItem, p: Dictionary, t: float) -> void:
	var c: Vector2 = p.pos
	for b in p.blobs:
		ci.draw_circle(c + b.o, b.r + 2.5, Color(0.05, 0.045, 0.04, 0.45))   # wet stone rim
	for b in p.blobs:
		ci.draw_circle(c + b.o, b.r, Color(0.06, 0.08, 0.1, 0.95))
	# Reflected torchlight on the near side, plus glints that shimmer.
	var ld: Vector2 = (main.p_pos - c).normalized() if main.p_pos != c else Vector2.UP
	for b in p.blobs:
		ci.draw_circle(c + b.o + ld * b.r * 0.35, b.r * 0.5, Color(0.38, 0.45, 0.55, 0.3))
	for i in p.blobs.size():
		var b: Dictionary = p.blobs[i]
		var gl: Vector2 = c + b.o + Vector2(cos(i * 2.3), sin(i * 1.7)) * b.r * 0.5
		ci.draw_circle(gl, 1.0, Color(0.85, 0.9, 0.95, 0.15 + 0.2 * (0.5 + 0.5 * sin(t * 2.5 + i * 1.9))))
	for rp in p.ripples:
		var k: float = rp.t / 1.2
		ci.draw_arc(c + rp.o, 1.5 + k * 13.0, 0, TAU, 20, Color(0.6, 0.68, 0.78, 0.45 * (1.0 - k)), 0.8)


func _bone(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col := BONE) -> void:
	ci.draw_line(a + Vector2(0.8, 1.2), b + Vector2(0.8, 1.2), Color(0, 0, 0, 0.35), w)
	ci.draw_line(a, b, col.darkened(0.3), w)
	ci.draw_line(a + Vector2(-0.3, -0.3), b + Vector2(-0.3, -0.3), col, w * 0.45)
	var n := (b - a).normalized().orthogonal()
	for e in [a, b]:
		ci.draw_circle(e + n * w * 0.35, w * 0.55, col.darkened(0.12))
		ci.draw_circle(e - n * w * 0.35, w * 0.55, col.darkened(0.12))


func _skull(ci: CanvasItem, p: Vector2, ang: float, s: float) -> void:
	var d := Vector2.from_angle(ang)
	var side := d.orthogonal()
	ci.draw_circle(p + Vector2(1.0, 1.6), 4.2 * s, Color(0, 0, 0, 0.35))
	ci.draw_circle(p + d * 3.2 * s, 2.5 * s, BONE.darkened(0.15))                 # jaw
	ci.draw_circle(p, 4.2 * s, BONE.darkened(0.2))
	ci.draw_circle(p - d * 0.6 * s + Vector2(-0.7, -0.7) * s, 3.0 * s, BONE.lightened(0.05))
	ci.draw_circle(p + d * 1.6 * s + side * 1.5 * s, 1.15 * s, Color(0.04, 0.03, 0.03))
	ci.draw_circle(p + d * 1.6 * s - side * 1.5 * s, 1.15 * s, Color(0.04, 0.03, 0.03))
	ci.draw_circle(p + d * 2.9 * s, 0.6 * s, Color(0.06, 0.05, 0.04))


func _draw_bones(ci: CanvasItem, p: Dictionary) -> void:
	var c: Vector2 = p.pos
	for b in p.bones:
		var d: Vector2 = Vector2.from_angle(b.ang) * b.len * 0.5
		_bone(ci, c + b.o - d, c + b.o + d, 1.8)
	if p.skull != null:
		_skull(ci, c + p.skull.o, p.skull.ang, 0.9)


func _draw_skeleton(ci: CanvasItem, p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed
	var c: Vector2 = p.pos
	var d := Vector2.from_angle(p.ang)
	var side := d.orthogonal()
	var j := func() -> Vector2: return Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
	# Legs and arms first so the ribcage sits on top.
	for s in [-1.0, 1.0]:
		var hip: Vector2 = c - d * 9.0 + side * s * 3.0
		var knee: Vector2 = hip - d * 8.5 + side * s * 1.5 + j.call()
		var foot: Vector2 = knee - d * 8.0 + side * s * 1.0 + j.call()
		_bone(ci, hip, knee, 2.0)
		_bone(ci, knee, foot, 1.8)
		var sh: Vector2 = c + d * 7.5 + side * s * 5.5
		var elbow: Vector2 = sh + side * s * 3.0 - d * 6.0 + j.call()
		var hand: Vector2 = elbow + side * s * 1.0 - d * 5.5 + j.call()
		_bone(ci, sh, elbow, 1.7)
		_bone(ci, elbow, hand, 1.5)
		for f in 3:
			ci.draw_circle(hand + (side * s * (f - 1) * 0.9) - d * 1.5, 0.6, BONE.darkened(0.15))
	ci.draw_circle(c - d * 9.0, 3.4, BONE.darkened(0.25))                        # pelvis
	ci.draw_circle(c - d * 9.0, 1.4, Color(0.08, 0.07, 0.06))
	for k in 7:
		ci.draw_circle(c + d * (7.0 - k * 2.6), 1.3, BONE.darkened(0.1))            # spine
	for k in 4:
		for s in [-1.0, 1.0]:
			var a: Vector2 = c + d * (6.5 - k * 2.4)
			var pts := PackedVector2Array([a, a + side * s * 4.5 - d * 1.0, a + side * s * 6.0 - d * 3.2])
			ci.draw_polyline(pts, Color(0, 0, 0, 0.3), 1.6)
			ci.draw_polyline(pts, BONE.darkened(0.08), 1.1)
	_skull(ci, c + d * 13.0, p.ang + rng.randf_range(-0.4, 0.4), 1.0)


func _draw_web(ci: CanvasItem, p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed
	var c: Vector2 = p.pos
	var dir: Vector2 = p.dir
	var R: float = p.r
	var col := Color(0.82, 0.83, 0.88, 0.32)
	var n := 6
	var spokes := []
	for i in n:
		var k := float(i) / (n - 1)
		var v := Vector2(dir.x * cos(k * PI / 2.0), dir.y * sin(k * PI / 2.0))
		var L := R * rng.randf_range(0.8, 1.05)
		spokes.append(v * L)
		ci.draw_line(c, c + v * L, col, 0.6)
	for ring in range(1, 5):
		var f := ring / 4.4
		for i in n - 1:
			var a: Vector2 = c + spokes[i] * f
			var b: Vector2 = c + spokes[i + 1] * f
			var mid := (a + b) * 0.5
			mid -= (mid - c) * 0.12   # threads sag toward the corner
			ci.draw_polyline(PackedVector2Array([a, mid, b]), col, 0.5)


# ================================================================ drawing (unlit overlay)

func draw_flames(ov: CanvasItem) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for tc in torches:
		if not _visible(tc.light.position):
			continue
		var ph: float = tc.phase
		var base: Vector2 = tc.pos + Vector2(0, -6)
		var fl := 1.0 + 0.18 * sin(t * 17.0 + ph) + 0.1 * sin(t * 29.0 + ph * 1.3)
		var sway := sin(t * 7.0 + ph) * 1.2
		ov.draw_circle(base + Vector2(0, -3), 9.0 * fl, Color(1.6, 0.7, 0.2, 0.12))
		var tip := base + Vector2(sway, -11.0 * fl)
		ov.draw_colored_polygon(PackedVector2Array([base + Vector2(-3, 0), base + Vector2(-2.2, -4), tip, base + Vector2(2.2, -4), base + Vector2(3, 0), base + Vector2(0, 1.5)]), Color(2.6, 1.05, 0.22, 0.9))
		ov.draw_colored_polygon(PackedVector2Array([base + Vector2(-1.6, 0), base + Vector2(sway * 0.5, -7.0 * fl), base + Vector2(1.6, 0)]), Color(3.0, 2.3, 1.0, 0.95))
		ov.draw_circle(base + Vector2(0, -1), 1.3, Color(3.5, 3.2, 2.4, 0.9))
