extends RefCounted
## Generates the dungeon's stone textures at startup: an albedo atlas plus a matching normal map,
## combined into a CanvasTexture so Godot's 2D lights pick out mortar, bevels and cracks.
##
## Atlas layout (TEX texels per tile, VARIANTS columns):
##   row 0 (y 0..64)      floor flagstones
##   row 1 (y 64..128)    wall tops (rough rock)
##   row 2 (y 128..164)   wall faces (brick), FACE_H texels tall

const TEX := 64
const VARIANTS := 8
const FACE_H := 36


static func build() -> CanvasTexture:
	var w := TEX * VARIANTS
	var h := TEX * 2 + FACE_H
	var albedo := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var height := PackedFloat32Array()
	height.resize(w * h)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.seed = 13
	fine.frequency = 0.4
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for v in VARIANTS:
		_floor(albedo, height, w, v * TEX, 0, rng, noise, fine)
		_wall_top(albedo, height, w, v * TEX, TEX, noise, fine)
		_wall_face(albedo, height, w, v * TEX, TEX * 2, rng, noise, fine)
	var normal := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for v in VARIANTS:
		_normals(height, normal, w, Rect2i(v * TEX, 0, TEX, TEX), 2.5)
		_normals(height, normal, w, Rect2i(v * TEX, TEX, TEX, TEX), 2.0)
		_normals(height, normal, w, Rect2i(v * TEX, TEX * 2, TEX, FACE_H), 2.5)
	var ct := CanvasTexture.new()
	ct.diffuse_texture = ImageTexture.create_from_image(albedo)
	ct.normal_texture = ImageTexture.create_from_image(normal)
	return ct


## A flagstone tile: 1–4 slabs with mortar joints, bevelled edges, grain, the odd crack and moss.
static func _floor(img: Image, hgt: PackedFloat32Array, w: int, ox: int, oy: int,
		rng: RandomNumberGenerator, noise: FastNoiseLite, fine: FastNoiseLite) -> void:
	var layout := rng.randi() % 4
	var sx := rng.randi_range(24, 40)
	var sy := rng.randi_range(24, 40)
	var cols: Array[Color] = []
	for k in 4:
		var tint := Color(0.36, 0.33, 0.3).lerp(Color(0.31, 0.32, 0.31) if rng.randf() < 0.5 else Color(0.38, 0.32, 0.26), rng.randf())
		cols.append(tint * rng.randf_range(0.85, 1.12))
	var crack := {}
	if rng.randf() < 0.25:
		var cp := Vector2(rng.randf_range(10, 54), rng.randf_range(10, 54))
		var cd := Vector2.from_angle(rng.randf() * TAU)
		for s in 45:
			cd = cd.rotated(rng.randf_range(-0.5, 0.5))
			cp += cd
			crack[Vector2i(cp)] = true
	var moss := rng.randf() < 0.3
	var nx := rng.randf() * 500.0
	var ny := rng.randf() * 500.0
	for y in TEX:
		for x in TEX:
			var x0 := 0
			var x1 := TEX
			var y0 := 0
			var y1 := TEX
			var stone := 0
			if layout == 1 or layout == 3:
				if x < sx:
					x1 = sx
				else:
					x0 = sx
					stone += 1
			if layout == 2 or layout == 3:
				if y < sy:
					y1 = sy
				else:
					y0 = sy
					stone += 2
			var edge := float(mini(mini(x - x0, x1 - 1 - x), mini(y - y0, y1 - 1 - y)))
			var n := noise.get_noise_2d(x + nx, y + ny)
			var g := fine.get_noise_2d(x + ox, y + oy)
			var hv: float
			var col: Color
			if edge < 1.5:
				hv = 0.05 * g
				col = Color(0.15, 0.135, 0.12) * (0.9 + 0.2 * g)
			else:
				var bevel := clampf(edge / 5.0, 0.0, 1.0)
				hv = 0.45 + 0.45 * bevel + 0.2 * n + 0.07 * g
				col = cols[stone % 4] * (0.82 + 0.3 * n + 0.12 * g)
				col = col.darkened((1.0 - bevel) * 0.3)
				if crack.has(Vector2i(x, y)):
					col = col.darkened(0.35)
					hv -= 0.3
				if moss and n > 0.2:
					col = col.lerp(Color(0.17, 0.23, 0.11), clampf((n - 0.2) * 3.0, 0.0, 0.7))
			img.set_pixel(ox + x, oy + y, Color(col, 1.0))
			hgt[(oy + y) * w + ox + x] = hv


static func _wall_top(img: Image, hgt: PackedFloat32Array, w: int, ox: int, oy: int,
		noise: FastNoiseLite, fine: FastNoiseLite) -> void:
	for y in TEX:
		for x in TEX:
			var n := noise.get_noise_2d(x + ox * 3.1, y + 900.0)
			var g := fine.get_noise_2d(x + ox, y + oy + 300.0)
			var col := Color(0.15, 0.13, 0.12) * (0.75 + 0.5 * n + 0.15 * g)
			img.set_pixel(ox + x, oy + y, Color(col, 1.0))
			hgt[(oy + y) * w + ox + x] = 0.5 + 0.4 * n + 0.15 * g


## Brick courses with mortar, per-brick colour, a capstone lip on top and grime toward the floor.
static func _wall_face(img: Image, hgt: PackedFloat32Array, w: int, ox: int, oy: int,
		rng: RandomNumberGenerator, noise: FastNoiseLite, fine: FastNoiseLite) -> void:
	var row_h := 11
	var brick_w := 21
	var tints := []
	for k in 20:
		tints.append(Color(0.4, 0.33, 0.27).lerp(Color(0.33, 0.3, 0.28), rng.randf()) * rng.randf_range(0.8, 1.15))
	for y in FACE_H:
		for x in TEX:
			var col: Color
			var hv: float
			var g := fine.get_noise_2d(x + ox, y + oy)
			var n := noise.get_noise_2d(x + ox * 2.3, y * 2.0 + 500.0)
			if y < 3:
				# Capstone lip catching the light.
				col = Color(0.42, 0.38, 0.33) * (0.9 + 0.2 * g)
				hv = 1.0
			else:
				var yy := y - 3
				var row := yy / row_h
				var off := (row % 2) * (brick_w / 2)
				var bx := (x + off) / brick_w
				var lx := (x + off) % brick_w
				var ly := yy % row_h
				var edge := float(mini(mini(lx, brick_w - 1 - lx), mini(ly, row_h - 1 - ly)))
				if edge < 1.0:
					col = Color(0.14, 0.12, 0.11)
					hv = 0.0
				else:
					var bevel := clampf(edge / 3.0, 0.0, 1.0)
					col = (tints[(row * 7 + bx) % tints.size()] as Color) * (0.85 + 0.25 * n + 0.1 * g)
					col = col.darkened((1.0 - bevel) * 0.3)
					hv = 0.5 + 0.5 * bevel + 0.15 * n
				var grime := pow(float(y) / FACE_H, 2.0)
				col = col.darkened(grime * 0.45)
			img.set_pixel(ox + x, oy + y, Color(col, 1.0))
			hgt[(oy + y) * w + ox + x] = hv


static func _normals(hgt: PackedFloat32Array, out: Image, w: int, r: Rect2i, strength: float) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var xl := maxi(x - 1, r.position.x)
			var xr := mini(x + 1, r.end.x - 1)
			var yu := maxi(y - 1, r.position.y)
			var yd := mini(y + 1, r.end.y - 1)
			var dx := hgt[y * w + xr] - hgt[y * w + xl]
			var dy := hgt[yd * w + x] - hgt[yu * w + x]
			var n := Vector3(-dx * strength, dy * strength, 1.0).normalized()
			out.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))


## Normal-mapped sphere sprites used for every body part (heads, hands, torsos, limbs are built
## from overlapping spheres, so real 2D lights shade them correctly from any angle).
## Kinds: skin (blotchy), cloth (woven, wrinkled), metal (smooth with scratches), bone.
static func build_spheres() -> Dictionary:
	var out := {}
	var kinds := ["skin", "cloth", "metal", "bone"]
	var S := 64
	for ki in kinds.size():
		var kind: String = kinds[ki]
		var albedo := Image.create(S, S, false, Image.FORMAT_RGBA8)
		var normal := Image.create(S, S, false, Image.FORMAT_RGBA8)
		var noise := FastNoiseLite.new()
		noise.seed = 100 + ki
		noise.frequency = 0.12
		noise.fractal_octaves = 3
		var fine := FastNoiseLite.new()
		fine.seed = 200 + ki
		fine.frequency = 0.6
		for y in S:
			for x in S:
				var u := (x + 0.5) / S * 2.0 - 1.0
				var v := (y + 0.5) / S * 2.0 - 1.0
				var d := sqrt(u * u + v * v)
				var alpha := clampf((1.0 - d) * S * 0.5, 0.0, 1.0)
				var h := sqrt(maxf(0.0, 1.0 - d * d))
				var n := noise.get_noise_2d(x, y)
				var g := fine.get_noise_2d(x, y)
				var c := 1.0
				var bump := 0.0
				match kind:
					"skin":
						c = 0.86 + 0.12 * n + 0.04 * g
						if n < -0.35:
							c *= 0.8   # bruises / rot
						bump = 0.15 * n
					"cloth":
						var weave := sin(x * 2.4) * sin(y * 2.4)
						c = 0.82 + 0.1 * n + 0.06 * weave
						bump = 0.35 * n + 0.05 * weave   # folds
					"metal":
						c = 0.92 + 0.05 * g
						if absf(sin((x + y * 0.3) * 0.9 + n * 6.0)) < 0.04:
							c *= 0.7   # scratches
						bump = 0.04 * g
					"bone":
						c = 0.9 + 0.08 * n
						bump = 0.1 * n
				albedo.set_pixel(x, y, Color(c, c, c, alpha))
				# Hemisphere normal, perturbed by the surface bump; same convention as the stone maps.
				var nn := Vector3(u + bump * 0.6, -v - bump * 0.6, h + 0.15).normalized()
				normal.set_pixel(x, y, Color(nn.x * 0.5 + 0.5, nn.y * 0.5 + 0.5, nn.z * 0.5 + 0.5, alpha))
		var ct := CanvasTexture.new()
		ct.diffuse_texture = ImageTexture.create_from_image(albedo)
		ct.normal_texture = ImageTexture.create_from_image(normal)
		out[kind] = ct
	return out
