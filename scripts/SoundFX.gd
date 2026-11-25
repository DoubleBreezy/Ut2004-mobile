extends Node

# Процедурный звуковой движок UT2004 (без внешних WAV-файлов, ноль фризов)
const SAMPLE_RATE := 22050
const POOL_SIZE := 14

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx: int = 0

func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_build_all_sounds()

func play(sound_name: String, volume_db: float = -3.0, pitch_jitter: float = 0.06) -> void:
	if not _streams.has(sound_name):
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = _streams[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var s := clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _build_all_sounds() -> void:
	_streams["bio_fire"] = _gen_bio_fire()
	_streams["bio_charge"] = _gen_bio_charge()
	_streams["shock_beam"] = _gen_shock_beam()
	_streams["shock_core"] = _gen_shock_core()
	_streams["shock_combo"] = _gen_shock_combo()
	_streams["flak_fire"] = _gen_flak_fire()
	_streams["flak_alt"] = _gen_flak_alt()
	_streams["flak_ricochet"] = _gen_ricochet()
	_streams["rocket_fire"] = _gen_rocket_fire()
	_streams["explosion"] = _gen_explosion()
	_streams["jump_pad"] = _gen_jump_pad()
	_streams["dodge"] = _gen_dodge()
	_streams["jump"] = _gen_jump()
	_streams["footstep"] = _gen_footstep()
	_streams["hit_confirm"] = _gen_hit_confirm()
	_streams["pickup"] = _gen_pickup()
	_streams["hurt"] = _gen_hurt()
	_streams["announce_kill"] = _gen_announce_kill()

func _gen_bio_fire() -> AudioStreamWAV:
	var dur := 0.24
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 14.0)
		var freq := lerpf(420.0, 95.0, t / dur) + sin(t * 90.0) * 65.0
		ph += TAU * freq / SAMPLE_RATE
		var bubble := sin(ph) * 0.65 + (randf() * 2.0 - 1.0) * 0.25 * exp(-t * 25.0)
		buf[i] = clampf(bubble * env * 0.9, -1.0, 1.0)
	return _make_wav(buf)

func _gen_bio_charge() -> AudioStreamWAV:
	var dur := 0.16
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := sin(PI * (t / dur))
		var freq := lerpf(210.0, 480.0, t / dur)
		ph += TAU * freq / SAMPLE_RATE
		buf[i] = sin(ph) * env * 0.45
	return _make_wav(buf)

func _gen_shock_beam() -> AudioStreamWAV:
	var dur := 0.28
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var ph2 := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 11.0)
		var freq := lerpf(1650.0, 190.0, pow(t / dur, 0.55))
		ph += TAU * freq / SAMPLE_RATE
		ph2 += TAU * (freq * 1.5) / SAMPLE_RATE
		var crack := (randf() * 2.0 - 1.0) * exp(-t * 45.0) * 0.6
		var wave := (sin(ph) * 0.55 + signf(sin(ph2)) * 0.22 + crack) * env
		buf[i] = clampf(wave * 0.85, -1.0, 1.0)
	return _make_wav(buf)

func _gen_shock_core() -> AudioStreamWAV:
	var dur := 0.30
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 8.0)
		var freq := lerpf(540.0, 145.0, t / dur)
		ph += TAU * freq / SAMPLE_RATE
		var mod := 1.0 + 0.35 * sin(t * 75.0)
		buf[i] = clampf(sin(ph) * mod * env * 0.75, -1.0, 1.0)
	return _make_wav(buf)

func _gen_shock_combo() -> AudioStreamWAV:
	var dur := 0.68
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 4.2)
		var freq := lerpf(190.0, 34.0, pow(t / dur, 0.6))
		ph += TAU * freq / SAMPLE_RATE
		var raw_noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, raw_noise, 0.14)
		var shimmer := sin(t * TAU * lerpf(920.0, 220.0, t / dur)) * exp(-t * 9.0) * 0.38
		var s := (sin(ph) * 0.75 + lp * 0.85 + shimmer) * env
		buf[i] = clampf(tanh(s * 1.4), -1.0, 1.0)
	return _make_wav(buf)

func _gen_flak_fire() -> AudioStreamWAV:
	var dur := 0.36
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 10.5)
		var freq := lerpf(180.0, 38.0, t / dur)
		ph += TAU * freq / SAMPLE_RATE
		var noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.32)
		# Лязг затвора Flak Cannon через 150 мс
		var clank := 0.0
		if t > 0.15 and t < 0.24:
			var ct := t - 0.15
			clank = sin(ct * TAU * 860.0) * exp(-ct * 35.0) * 0.35
		var s := (lp * 0.85 + sin(ph) * 0.6) * env + clank
		buf[i] = clampf(tanh(s * 1.3), -1.0, 1.0)
	return _make_wav(buf)

func _gen_flak_alt() -> AudioStreamWAV:
	var dur := 0.28
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 12.0)
		var freq := lerpf(260.0, 62.0, pow(t / dur, 0.5))
		ph += TAU * freq / SAMPLE_RATE
		var thump := sin(ph) * 0.85 + (randf() * 2.0 - 1.0) * 0.25 * exp(-t * 28.0)
		buf[i] = clampf(thump * env, -1.0, 1.0)
	return _make_wav(buf)

func _gen_ricochet() -> AudioStreamWAV:
	var dur := 0.16
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 22.0)
		var freq := lerpf(2400.0, 980.0, t / dur)
		ph += TAU * freq / SAMPLE_RATE
		var zing := sin(ph) * 0.65 + sin(ph * 2.37) * 0.35
		buf[i] = clampf(zing * env * 0.7, -1.0, 1.0)
	return _make_wav(buf)

func _gen_rocket_fire() -> AudioStreamWAV:
	var dur := 0.42
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 6.5)
		var freq := lerpf(150.0, 48.0, t / dur)
		ph += TAU * freq / SAMPLE_RATE
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.22)
		var s := (lp * 0.95 + sin(ph) * 0.55) * env
		buf[i] = clampf(s, -1.0, 1.0)
	return _make_wav(buf)

func _gen_explosion() -> AudioStreamWAV:
	var dur := 0.55
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 5.2)
		var freq := lerpf(125.0, 26.0, pow(t / dur, 0.5))
		ph += TAU * freq / SAMPLE_RATE
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.16)
		var s := (lp * 1.0 + sin(ph) * 0.7) * env
		buf[i] = clampf(tanh(s * 1.4), -1.0, 1.0)
	return _make_wav(buf)

func _gen_jump_pad() -> AudioStreamWAV:
	var dur := 0.42
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := sin(PI * minf(1.0, t / dur)) * exp(-t * 2.2)
		var freq := lerpf(180.0, 880.0, pow(t / dur, 0.75))
		ph += TAU * freq / SAMPLE_RATE
		var s := (sin(ph) * 0.7 + sin(ph * 2.0) * 0.25) * env
		buf[i] = clampf(s, -1.0, 1.0)
	return _make_wav(buf)

func _gen_dodge() -> AudioStreamWAV:
	var dur := 0.18
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 16.0)
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.28)
		var s := (lp * 0.65 + sin(t * TAU * lerpf(280.0, 120.0, t / dur)) * 0.35) * env
		buf[i] = clampf(s, -1.0, 1.0)
	return _make_wav(buf)

func _gen_jump() -> AudioStreamWAV:
	var dur := 0.12
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 22.0)
		ph += TAU * lerpf(160.0, 360.0, t / dur) / SAMPLE_RATE
		buf[i] = sin(ph) * env * 0.45
	return _make_wav(buf)

func _gen_footstep() -> AudioStreamWAV:
	var dur := 0.075
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 42.0)
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.22)
		var thud := sin(t * TAU * 115.0) * 0.45 + lp * 0.45
		buf[i] = clampf(thud * env * 0.55, -1.0, 1.0)
	return _make_wav(buf)

func _gen_hit_confirm() -> AudioStreamWAV:
	var dur := 0.07
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 36.0)
		buf[i] = sin(t * TAU * 1240.0) * env * 0.55
	return _make_wav(buf)

func _gen_pickup() -> AudioStreamWAV:
	var dur := 0.26
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 9.0)
		var f := 580.0 if t < 0.11 else 870.0
		buf[i] = sin(t * TAU * f) * env * 0.55
	return _make_wav(buf)

func _gen_hurt() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 14.0)
		ph += TAU * lerpf(210.0, 72.0, t / dur) / SAMPLE_RATE
		var crunch := (randf() * 2.0 - 1.0) * 0.35 + signf(sin(ph)) * 0.45
		buf[i] = clampf(crunch * env * 0.65, -1.0, 1.0)
	return _make_wav(buf)

func _gen_announce_kill() -> AudioStreamWAV:
	var dur := 0.48
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 4.5)
		var chord := sin(t * TAU * 220.0) * 0.4 + sin(t * TAU * 330.0) * 0.3 + sin(t * TAU * 440.0) * 0.2
		buf[i] = clampf(chord * env * 0.7, -1.0, 1.0)
	return _make_wav(buf)
