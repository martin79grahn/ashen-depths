extends Node
## Procedural audio. Every sound effect and the ambient score are synthesized in code at startup —
## there are no audio files. SFX are built on a worker thread so the game starts instantly.
##
## play(name, world_pos, volume_db)  — positional sound (pans/attenuates relative to the camera)
## play_ui(name, volume_db)          — non-positional sound
## toggle_music()

const SR := 22050

var sounds := {}           # name -> Array[AudioStreamWAV]
var pool: Array[AudioStreamPlayer2D] = []
var pool_i := 0
var ui: Array[AudioStreamPlayer] = []
var ui_i := 0
var last := {}             # name -> msec, to avoid stacking identical sounds in one frame
var gen_thread: Thread
var music_on := true

# --- music
const PAD_DB := -15.0
const PAD_BASE := 110.0
# Slow, dark progression: Am(add9) - Fmaj7 - C(add9) - Em7
const CHORDS := [
	[110.0, 130.81, 164.81, 246.94],
	[87.31, 110.0, 130.81, 164.81],
	[130.81, 196.0, 293.66, 164.81],
	[82.41, 98.0, 123.47, 146.83],
]
# A minor pentatonic, relative to the 440 Hz bell sample
const BELL_NOTES := [1.0, 1.1892, 1.3348, 1.4983, 1.7818, 0.5, 0.7491, 0.6674]
var pad_banks := [[], []]
var bank := 0
var chord_i := 0
var chord_timer := 0.0
var bell_timer := 5.0
var bells: Array[AudioStreamPlayer] = []
var lowpass: AudioEffectLowPassFilter
var t := 0.0


func _ready() -> void:
	_setup_buses()
	for i in 28:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 1000.0
		p.attenuation = 1.3
		add_child(p)
		pool.append(p)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		ui.append(p)
	_start_music()
	gen_thread = Thread.new()
	gen_thread.start(_make_sfx)


func _exit_tree() -> void:
	if gen_thread and gen_thread.is_started():
		gen_thread.wait_to_finish()


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var mi := AudioServer.get_bus_index("Music")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 1200.0
	lowpass.resonance = 0.6
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.95
	rev.damping = 0.35
	rev.spread = 1.0
	rev.wet = 0.5
	rev.dry = 0.65
	AudioServer.add_bus_effect(mi, lowpass)
	AudioServer.add_bus_effect(mi, rev)
	AudioServer.set_bus_volume_db(mi, -3.0)
	# A little dungeon room tone on the effects.
	var si := AudioServer.get_bus_index("SFX")
	var r2 := AudioEffectReverb.new()
	r2.room_size = 0.55
	r2.damping = 0.6
	r2.wet = 0.16
	r2.dry = 1.0
	AudioServer.add_bus_effect(si, r2)


# ================================================================ playback

func play(sound: String, pos: Vector2, vol_db := 0.0, pitch_var := 0.07) -> void:
	var s := _pick(sound)
	if s == null:
		return
	var p := pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_ui(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(sound)
	if s == null:
		return
	var p := ui[ui_i]
	ui_i = (ui_i + 1) % ui.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func _pick(sound: String) -> AudioStreamWAV:
	if not sounds.has(sound):
		return null   # still generating, or unknown
	var now := Time.get_ticks_msec()
	if now - int(last.get(sound, -1000)) < 35:
		return null
	last[sound] = now
	return sounds[sound].pick_random()


var heartbeat: AudioStreamPlayer

## Boss fights get a pounding heartbeat under the music.
func set_boss(on: bool) -> void:
	if heartbeat == null:
		heartbeat = AudioStreamPlayer.new()
		heartbeat.stream = _wav(_heartbeat(), true)
		heartbeat.bus = "Music"
		add_child(heartbeat)
	if on:
		heartbeat.volume_db = -4.0
		if not heartbeat.playing:
			heartbeat.play()
	else:
		var tw := create_tween()
		tw.tween_property(heartbeat, "volume_db", -60.0, 3.0)
		tw.tween_callback(heartbeat.stop)


func toggle_music() -> void:
	music_on = not music_on
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_on)


# ================================================================ music

func _start_music() -> void:
	var pad := _pad_note()
	for b in 2:
		for j in 4:
			var p := AudioStreamPlayer.new()
			p.stream = pad
			p.bus = "Music"
			p.volume_db = -60.0
			add_child(p)
			pad_banks[b].append(p)
	var drone := AudioStreamPlayer.new()
	drone.stream = _drone()
	drone.bus = "Music"
	drone.volume_db = -14.0
	add_child(drone)
	drone.play()
	var bell := _bell()
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.stream = bell
		p.bus = "Music"
		add_child(p)
		bells.append(p)
	_next_chord()


func _next_chord() -> void:
	var old: Array = pad_banks[bank]
	bank = 1 - bank
	var cur: Array = pad_banks[bank]
	var notes: Array = CHORDS[chord_i % CHORDS.size()]
	chord_i += 1
	for j in 4:
		var p: AudioStreamPlayer = cur[j]
		p.pitch_scale = notes[j] / PAD_BASE
		p.volume_db = -60.0
		p.play(randf() * 1.9)
		create_tween().tween_property(p, "volume_db", PAD_DB - (4.0 if j == 3 else 0.0), 6.0).set_trans(Tween.TRANS_SINE)
	for p in old:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, 7.0).set_trans(Tween.TRANS_SINE)
			tw.tween_callback(p.stop)
	chord_timer = randf_range(13.0, 17.0)


func _process(delta: float) -> void:
	t += delta
	# The pads slowly open and close like breathing.
	lowpass.cutoff_hz = 1000.0 + 650.0 * sin(t * 0.09) + 200.0 * sin(t * 0.23)
	chord_timer -= delta
	if chord_timer <= 0.0:
		_next_chord()
	bell_timer -= delta
	if bell_timer <= 0.0:
		bell_timer = randf_range(3.5, 9.0)
		for b in bells:
			if not b.playing:
				b.pitch_scale = BELL_NOTES.pick_random()
				b.volume_db = randf_range(-24.0, -18.0)
				b.play()
				break


# ================================================================ synthesis helpers

func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * SR))
	return b


func _norm(b: PackedFloat32Array, peak := 0.85) -> PackedFloat32Array:
	var m := 0.0
	for x in b:
		m = maxf(m, absf(x))
	if m > 0.0:
		var k := peak / m
		for i in b.size():
			b[i] *= k
	return b


func _wav(b: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = b.size()
	return w


## Seamless 2 s loop: every voice has a whole number of cycles in the loop
## (110 / 109.5 / 110.5 Hz), so the slow chorus beating never clicks.
func _pad_note() -> AudioStreamWAV:
	var table := PackedFloat32Array()
	table.resize(2048)
	for i in 2048:
		var x := 0.0
		for h in range(1, 8):
			x += sin(TAU * h * i / 2048.0) / pow(h, 1.4)
		table[i] = x
	table = _norm(table, 1.0)
	var b := _buf(2.0)
	var voices := [[PAD_BASE, 0.5], [PAD_BASE - 0.5, 0.35], [PAD_BASE + 0.5, 0.35], [PAD_BASE * 2.0, 0.12]]
	for v in voices:
		var f: float = v[0]
		var amp: float = v[1]
		for i in b.size():
			var ph := fmod(f * i / SR, 1.0)
			b[i] += table[int(ph * 2048.0) & 2047] * amp
	return _wav(_norm(b, 0.7), true)


func _drone() -> AudioStreamWAV:
	var b := _buf(2.0)
	for i in b.size():
		var tt := float(i) / SR
		b[i] = sin(TAU * 55.0 * tt) * 0.6 + sin(TAU * 110.0 * tt) * 0.2 + sin(TAU * 82.5 * tt) * 0.12
	return _wav(_norm(b, 0.6), true)


func _bell() -> AudioStreamWAV:
	var b := _buf(4.5)
	var parts := [[1.0, 1.0, 1.2], [2.0, 0.4, 2.0], [2.76, 0.25, 3.2], [5.4, 0.12, 6.0]]
	for i in b.size():
		var tt := float(i) / SR
		var x := 0.0
		for p in parts:
			x += sin(TAU * 440.0 * p[0] * tt) * p[1] * exp(-tt * p[2])
		b[i] = x * minf(1.0, tt / 0.004)
	return _wav(_norm(b, 0.6))


# ================================================================ sound effects (worker thread)

func _make_sfx() -> void:
	var s := {}
	s["growl"] = [_wav(_growl(0.9, 85, 70, 1.0, 550, 1)), _wav(_growl(1.1, 100, 65, 1.0, 480, 2)), _wav(_growl(0.8, 75, 90, 1.0, 620, 3))]
	s["attack"] = [_wav(_growl(0.35, 130, 90, 0.8, 700, 4)), _wav(_growl(0.3, 120, 95, 0.8, 650, 5))]
	s["zhurt"] = [_wav(_growl(0.28, 150, 110, 0.6, 750, 6)), _wav(_growl(0.25, 170, 120, 0.6, 820, 7)), _wav(_growl(0.3, 135, 100, 0.6, 700, 8))]
	s["death"] = [_wav(_growl(1.2, 120, 45, 1.0, 520, 9)), _wav(_growl(1.0, 140, 55, 1.0, 480, 10))]
	s["player_hurt"] = [_wav(_growl(0.26, 175, 125, 0.0, 780, 29)), _wav(_growl(0.24, 195, 140, 0.0, 830, 30))]
	s["squelch"] = [_wav(_squelch(11)), _wav(_squelch(12))]
	s["flesh"] = [_wav(_flesh(13)), _wav(_flesh(14)), _wav(_flesh(15))]
	s["metal"] = [_wav(_metal(16, 520.0, 0.6)), _wav(_metal(17, 610.0, 0.6))]
	s["block"] = [_wav(_metal(18, 720.0, 0.35))]
	s["bash"] = [_wav(_bash(19))]
	s["swing"] = [_wav(_whoosh(0.22, 500.0, 1800.0, 20)), _wav(_whoosh(0.26, 400.0, 1500.0, 21))]
	s["crossbow"] = [_wav(_crossbow(22)), _wav(_crossbow(23))]
	s["magic_cast"] = [_wav(_magic(24))]
	s["magic_hit"] = [_wav(_magic_hit(25))]
	s["heal"] = [_wav(_heal())]
	s["explode"] = [_wav(_explode(26))]
	s["spit"] = [_wav(_spit(27)), _wav(_spit(28))]
	s["coin"] = [_wav(_coin())]
	s["levelup"] = [_wav(_levelup())]
	s["splash"] = [_wav(_splash(31)), _wav(_splash(32))]
	s["drip"] = [_wav(_drip(1700.0)), _wav(_drip(2100.0))]
	s["laugh"] = [_wav(_laugh(330.0, 950.0, 7, 0.085, 0.0, 41)), _wav(_laugh(360.0, 1000.0, 6, 0.08, 0.0, 42))]
	s["dream_laugh"] = [_wav(_laugh(135.0, 620.0, 4, 0.16, 0.9, 43))]
	s["boss_roar"] = [_wav(_growl(1.6, 70, 42, 1.0, 380, 44))]
	s["teleport"] = [_wav(_teleport(45))]
	s["pop"] = [_wav(_pop(46))]
	s["blades"] = [_wav(_metal(47, 1350.0, 0.45)), _wav(_metal(48, 1550.0, 0.4))]
	call_deferred("_sfx_ready", s)


func _sfx_ready(s: Dictionary) -> void:
	sounds = s
	gen_thread.wait_to_finish()


## Voiced growl: saw + sub-octave + breath noise, through a formant band-pass,
## with pitch wobble and a fast "throat rattle" tremolo.
func _growl(sec: float, f0: float, f_end: float, rough: float, formant: float, seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(sec)
	var n := b.size()
	var ph := 0.0
	var ph2 := 0.0
	var low := 0.0
	var band := 0.0
	var lp := 0.0
	var wob := 0.0
	var fq := 2.0 * sin(PI * formant / SR)
	for i in n:
		var tt := float(i) / SR
		var k := float(i) / n
		wob = lerpf(wob, rng.randf_range(-1.0, 1.0), 0.002)
		var f := lerpf(f0, f_end, k) * (1.0 + 0.1 * sin(TAU * 4.3 * tt) + 0.3 * wob)
		ph = fmod(ph + f / SR, 1.0)
		ph2 = fmod(ph2 + f * 0.5 / SR, 1.0)
		var x := (2.0 * ph - 1.0) * 0.6 + (2.0 * ph2 - 1.0) * 0.4 * rough + rng.randf_range(-1.0, 1.0) * (0.2 + 0.25 * rough)
		x *= 1.0 - rough * 0.45 * (0.5 + 0.5 * sin(TAU * (28.0 + 12.0 * wob) * tt))
		var hi := x - low - 0.5 * band
		band += fq * hi
		low += fq * band
		lp += 0.12 * (x - lp)
		var env := minf(1.0, tt / 0.05) * pow(1.0 - k, 1.2)
		b[i] = (band * 0.8 + lp * 0.6) * env
	return _norm(b, 0.8)


## Sword through flesh: a wet noise slap, a low thump and a squishy tail.
func _flesh(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.24)
	var lp1 := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in b.size():
		var tt := float(i) / SR
		var nz := rng.randf_range(-1.0, 1.0)
		lp1 += 0.3 * (nz - lp1)
		lp2 += 0.06 * (nz - lp2)
		ph += (100.0 - 150.0 * tt) / SR
		var thump := sin(TAU * ph) * exp(-tt * 28.0)
		var squish := lp2 * (0.6 + 0.4 * sin(TAU * 45.0 * tt)) * exp(-tt * 14.0) * 2.5
		b[i] = lp1 * exp(-tt * 40.0) * 1.3 + thump * 0.9 + squish
	return _norm(b, 0.9)


## Inharmonic struck-metal partials plus a sharp click.
func _metal(seed_: int, base: float, sec: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var parts := [1.0, 2.27, 3.52, 5.15, 6.73]
	var det := rng.randf_range(0.96, 1.04)
	var b := _buf(sec)
	for i in b.size():
		var tt := float(i) / SR
		var x := 0.0
		for k in parts.size():
			x += sin(TAU * base * det * parts[k] * tt) * exp(-tt * (5.0 + k * 5.0)) / (k + 1.0)
		x += rng.randf_range(-1.0, 1.0) * exp(-tt * 180.0) * 0.8
		b[i] = x
	return _norm(b, 0.7)


func _bash(seed_: int) -> PackedFloat32Array:
	var m := _metal(seed_, 260.0, 0.7)
	var f := _flesh(seed_ + 100)
	for i in f.size():
		m[i] = m[i] * 0.8 + f[i] * 0.7
	return _norm(m, 0.85)


## Band-passed noise sweeping up then down.
func _whoosh(sec: float, f_lo: float, f_hi: float, seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(sec)
	var n := b.size()
	var low := 0.0
	var band := 0.0
	for i in n:
		var k := float(i) / n
		var fc := lerpf(f_lo, f_hi, sin(PI * k))
		var fq := 2.0 * sin(PI * fc / SR)
		var x := rng.randf_range(-1.0, 1.0)
		var hi := x - low - 0.7 * band
		band += fq * hi
		low += fq * band
		b[i] = band * pow(sin(PI * k), 2.0)
	return _norm(b, 0.55)


## Crossbow: trigger click, plucked string (Karplus–Strong) and a wooden thunk.
func _crossbow(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.4)
	var period := int(SR / rng.randf_range(140.0, 165.0))
	var ks := PackedFloat32Array()
	ks.resize(period)
	for j in period:
		ks[j] = rng.randf_range(-1.0, 1.0)
	var idx := 0
	for i in b.size():
		var tt := float(i) / SR
		var v := ks[idx]
		ks[idx] = (v + ks[(idx + 1) % period]) * 0.5 * 0.99
		idx = (idx + 1) % period
		var click := rng.randf_range(-1.0, 1.0) * exp(-tt * 400.0)
		var thunk := sin(TAU * 70.0 * tt) * exp(-tt * 35.0)
		b[i] = v * 0.7 * exp(-tt * 7.0) + click * 0.9 + thunk * 0.6
	return _norm(b, 0.8)


## Holy bolt: a rising shimmering chord with sparkles.
func _magic(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.7)
	var n := b.size()
	var ph := 0.0
	var spark_t := 1.0
	var spark_f := 3000.0
	for i in n:
		var tt := float(i) / SR
		var k := float(i) / n
		var f := 520.0 * pow(2.0, k) * (1.0 + 0.01 * sin(TAU * 7.0 * tt))
		ph += f / SR
		var x := sin(TAU * ph) + 0.5 * sin(TAU * ph * 1.5) + 0.35 * sin(TAU * ph * 2.01)
		if rng.randf() < 0.002:
			spark_t = 0.0
			spark_f = rng.randf_range(2200.0, 4200.0)
		spark_t += 1.0 / SR
		x += sin(TAU * spark_f * spark_t) * exp(-spark_t * 40.0) * 0.6
		b[i] = x * minf(1.0, tt / 0.04) * exp(-tt * 3.5)
	return _norm(b, 0.6)


func _magic_hit(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.35)
	var lp := 0.0
	for i in b.size():
		var tt := float(i) / SR
		var nz := rng.randf_range(-1.0, 1.0)
		lp += 0.4 * (nz - lp)
		var sizzle := (nz - lp) * exp(-tt * 12.0)
		b[i] = sizzle * 0.8 + sin(TAU * 880.0 * tt) * exp(-tt * 10.0) * 0.5 + sin(TAU * 1320.0 * tt) * exp(-tt * 14.0) * 0.3
	return _norm(b, 0.6)


func _heal() -> PackedFloat32Array:
	var b := _buf(1.5)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in b.size():
		var tt := float(i) / SR
		var x := 0.0
		for j in notes.size():
			var start := j * 0.06
			if tt > start:
				var lt := tt - start
				x += sin(TAU * notes[j] * lt) * minf(1.0, lt / 0.2) * exp(-lt * 1.8)
		b[i] = x * (0.85 + 0.15 * sin(TAU * 6.0 * tt))
	return _norm(b, 0.55)


func _explode(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(1.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var tt := float(i) / SR
		var nz := rng.randf_range(-1.0, 1.0)
		lp += 0.08 * (nz - lp)
		lp2 += 0.03 * (nz - lp2)
		var wet := lp2 * (0.5 + 0.5 * sin(TAU * (18.0 + 30.0 * tt) * tt)) * exp(-tt * 3.0) * 3.0
		b[i] = lp * exp(-tt * 4.0) * 2.0 + sin(TAU * (50.0 - 20.0 * tt) * tt) * exp(-tt * 6.0) + wet
	return _norm(b, 0.95)


func _squelch(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.4)
	var lp := 0.0
	for i in b.size():
		var tt := float(i) / SR
		lp += 0.07 * (rng.randf_range(-1.0, 1.0) - lp)
		var bumps := maxf(0.0, sin(TAU * (9.0 + 6.0 * tt) * tt))
		b[i] = lp * bumps * exp(-tt * 6.0)
	return _norm(b, 0.7)


func _spit(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.3)
	var low := 0.0
	var band := 0.0
	var fq := 2.0 * sin(PI * 1500.0 / SR)
	for i in b.size():
		var tt := float(i) / SR
		var x := rng.randf_range(-1.0, 1.0)
		var hi := x - low - 0.6 * band
		band += fq * hi
		low += fq * band
		b[i] = (band + low * 0.4) * (0.5 + 0.5 * sin(TAU * 35.0 * tt)) * minf(1.0, tt / 0.01) * exp(-tt * 10.0)
	return _norm(b, 0.6)


func _coin() -> PackedFloat32Array:
	var b := _buf(0.3)
	for i in b.size():
		var tt := float(i) / SR
		var x := sin(TAU * 2093.0 * tt) * exp(-tt * 25.0)
		if tt > 0.06:
			var lt := tt - 0.06
			x += sin(TAU * 2637.0 * lt) * exp(-lt * 18.0)
		b[i] = x
	return _norm(b, 0.4)


func _levelup() -> PackedFloat32Array:
	var b := _buf(1.2)
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for i in b.size():
		var tt := float(i) / SR
		var x := 0.0
		for j in notes.size():
			var start := j * 0.1
			if tt > start:
				var lt := tt - start
				x += (sin(TAU * notes[j] * lt) + 0.3 * sin(TAU * notes[j] * 2.0 * lt)) * exp(-lt * 3.0)
		b[i] = x
	return _norm(b, 0.55)


## Foot in a puddle: a short spray of bright noise plus a couple of bubble blips.
func _splash(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.35)
	var low := 0.0
	var band := 0.0
	var fq := 2.0 * sin(PI * 1900.0 / SR)
	for i in b.size():
		var tt := float(i) / SR
		var x := rng.randf_range(-1.0, 1.0)
		var hi := x - low - 0.8 * band
		band += fq * hi
		low += fq * band
		var bub := 0.0
		for k in 2:
			var st := tt - 0.04 - k * 0.07
			if st > 0.0:
				bub += sin(TAU * (500.0 + k * 220.0 + 2500.0 * st) * st) * exp(-st * 40.0)
		b[i] = band * exp(-tt * 11.0) + bub * 0.35
	return _norm(b, 0.6)


## A single water drop: a quick downward "plink".
func _drip(f0: float) -> PackedFloat32Array:
	var b := _buf(0.5)
	var ph := 0.0
	for i in b.size():
		var tt := float(i) / SR
		ph += f0 * (0.55 + 0.45 * exp(-tt * 30.0)) / SR
		b[i] = sin(TAU * ph) * exp(-tt * 14.0) * minf(1.0, tt / 0.002)
	return _norm(b, 0.5)


## A laugh: a run of voiced "ha" syllables with breath, pitch arching up then down.
func _laugh(f0: float, formant: float, count: int, syl: float, rough: float, seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var gap := syl * 0.55
	var b := _buf(count * (syl + gap) + 0.2)
	var ph := 0.0
	var low := 0.0
	var band := 0.0
	var fq := 2.0 * sin(PI * formant / SR)
	for i in b.size():
		var tt := float(i) / SR
		var k := tt / (count * (syl + gap))
		var slot := fmod(tt, syl + gap)
		var env := 0.0
		if slot < syl and k < 1.0:
			env = sin(PI * slot / syl)
		var f := f0 * (1.0 + 0.25 * sin(PI * k) - 0.15 * k) * (1.0 - 0.12 * slot / syl)
		ph = fmod(ph + f / SR, 1.0)
		var x := (2.0 * ph - 1.0) * 0.7 + rng.randf_range(-1.0, 1.0) * (0.3 + 0.3 * rough)
		x *= 1.0 - rough * 0.4 * (0.5 + 0.5 * sin(TAU * 30.0 * tt))
		var hi := x - low - 0.4 * band
		band += fq * hi
		low += fq * band
		b[i] = (band + low * 0.3) * env
	return _norm(b, 0.75)


func _teleport(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.6)
	var n := b.size()
	var low := 0.0
	var band := 0.0
	for i in n:
		var k := float(i) / n
		var fc := lerpf(300.0, 3500.0, k * k)
		var fq := 2.0 * sin(PI * fc / SR)
		var x := rng.randf_range(-1.0, 1.0)
		var hi := x - low - 0.5 * band
		band += fq * hi
		low += fq * band
		b[i] = band * pow(k, 1.5) * (1.0 if k < 0.92 else (1.0 - k) / 0.08) + sin(TAU * 880.0 * k * 0.6) * 0.1 * k
	return _norm(b, 0.6)


func _pop(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var b := _buf(0.15)
	for i in b.size():
		var tt := float(i) / SR
		b[i] = rng.randf_range(-1.0, 1.0) * exp(-tt * 60.0) + sin(TAU * 180.0 * tt) * exp(-tt * 40.0) * 0.6
	return _norm(b, 0.8)


func _heartbeat() -> PackedFloat32Array:
	var b := _buf(1.1)
	for i in b.size():
		var tt := float(i) / SR
		var x := 0.0
		for start in [0.0, 0.26]:
			var lt: float = tt - start
			if lt > 0.0:
				x += sin(TAU * (58.0 - 25.0 * lt) * lt) * exp(-lt * 16.0) * (1.0 if start == 0.0 else 0.7)
		b[i] = x
	return _norm(b, 0.9)
