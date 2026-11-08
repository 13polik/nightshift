class_name ProceduralAudio
extends RefCounted
## Development sound synthesiser. Every cue in the SoundLibrary first looks for a real
## file in res://audio/cues/<id>.(ogg|wav|mp3); only when none exists is a sound generated
## here, so sound designers can replace cues one by one without touching code.

const RATE := 22050


static func generate(cue: String) -> AudioStreamWAV:
	match cue:
		"amb_hum": return _loop(_hum(4.0, 50.0), 4.0)
		"amb_vent": return _loop(_vent(6.0), 6.0)
		"amb_drone": return _loop(_drone(8.0, 41.2), 8.0)
		"amb_distant": return _one(_distant_bang(2.5))
		"amb_drip": return _one(_drip(0.6))
		"amb_creak": return _one(_creak(1.8))
		"music_pulse": return _loop(_pulse(4.0, 70.0), 4.0)
		"music_tension": return _loop(_tension(8.0), 8.0)
		"music_chase": return _loop(_chase(4.0), 4.0)
		"step_player": return _one(_step(0.18, 0.5))
		"step_hunter": return _one(_step(0.35, 1.0, 55.0))
		"door_open": return _one(_slide(0.9, true))
		"door_close": return _one(_slide(0.9, false))
		"door_locked": return _one(_buzz(0.35, 140.0))
		"door_bash": return _one(_impact(0.6, 70.0))
		"alarm": return _loop(_alarm(2.0), 2.0)
		"power_down": return _one(_sweep(2.2, 220.0, 30.0))
		"power_up": return _one(_sweep(2.6, 40.0, 260.0))
		"generator_loop": return _loop(_hum(3.0, 30.0, 0.5), 3.0)
		"hunter_screech": return _one(_screech(1.4))
		"hunter_growl": return _one(_growl(2.0))
		"hunter_click": return _one(_clicks(1.2))
		"hunter_attack": return _one(_impact(0.5, 90.0))
		"player_hurt": return _one(_impact(0.3, 160.0))
		"heartbeat": return _loop(_heartbeat(1.0), 1.0)
		"ui_click": return _one(_beep(0.05, 1200.0))
		"ui_confirm": return _one(_two_tone(0.22, 880.0, 1320.0))
		"ui_back": return _one(_two_tone(0.2, 900.0, 600.0))
		"ui_error": return _one(_buzz(0.3, 180.0))
		"pickup": return _one(_two_tone(0.25, 660.0, 990.0))
		"interact_loop": return _loop(_terminal(1.0), 1.0)
		"interact_done": return _one(_two_tone(0.35, 520.0, 1040.0))
		"search": return _one(_rummage(0.9))
		"heal": return _one(_sweep(0.6, 300.0, 700.0, 0.25))
		"stun": return _one(_zap(0.7))
		"flashlight": return _one(_beep(0.04, 2400.0))
		"downed": return _one(_sweep(1.2, 200.0, 60.0))
		"objective": return _one(_chord(1.2))
		"evac_horn": return _one(_horn(2.5))
		"elevator": return _loop(_hum(2.0, 70.0, 0.6), 2.0)
		"ping": return _one(_two_tone(0.3, 1500.0, 1900.0))
	return _one(_beep(0.08, 440.0))


# --- stream builders -----------------------------------------------------------------

static func _one(samples: PackedFloat32Array) -> AudioStreamWAV:
	return _to_stream(samples, false)


static func _loop(samples: PackedFloat32Array, _seconds: float) -> AudioStreamWAV:
	return _to_stream(samples, true)


static func _to_stream(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if looped:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _env(i: int, n: int, attack: float = 0.01, release: float = 0.2) -> float:
	var t := float(i) / RATE
	var total := float(n) / RATE
	var a := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var r := clampf((total - t) / maxf(release, 0.0001), 0.0, 1.0)
	return a * r


# Seamless loops use whole-number cycles for tones and crossfade noise.
static func _hum(seconds: float, base: float, amp: float = 0.35) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = amp * (0.6 * sin(TAU * base * t) + 0.25 * sin(TAU * base * 2.0 * t) + 0.12 * sin(TAU * base * 3.0 * t)) \
			* (0.85 + 0.15 * sin(TAU * 0.5 * t))
	return b


static func _vent(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lp := 0.0
	for i in b.size():
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.06)
		var t := float(i) / RATE
		b[i] = lp * 0.7 * (0.8 + 0.2 * sin(TAU * 0.25 * t))
	return _crossfade_loop(b, int(0.5 * RATE))


static func _drone(seconds: float, base: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for h in [1.0, 1.5, 2.0, 2.997]:
			v += sin(TAU * base * h * t + sin(TAU * 0.125 * t) * 0.6) / h
		b[i] = v * 0.18
	return b


static func _pulse(seconds: float, bpm: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var beat := 60.0 / bpm
	for i in b.size():
		var t := float(i) / RATE
		var bt := fmod(t, beat)
		b[i] = sin(TAU * 48.0 * t) * exp(-bt * 9.0) * 0.6
	return b


static func _tension(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.3)
		var tone := sin(TAU * 220.0 * t + 3.0 * sin(TAU * 0.25 * t)) * 0.08 + sin(TAU * 233.08 * t) * 0.05
		b[i] = tone + lp * 0.05 * (0.5 + 0.5 * sin(TAU * 0.125 * t))
	return _crossfade_loop(b, int(0.4 * RATE))


static func _chase(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var beat := 0.25
	for i in b.size():
		var t := float(i) / RATE
		var bt := fmod(t, beat)
		var kick := sin(TAU * (60.0 + 80.0 * exp(-bt * 30.0)) * t) * exp(-bt * 12.0)
		var stab := sin(TAU * 110.0 * t) * 0.15 * (1.0 if fmod(t, 1.0) < 0.5 else 0.6)
		b[i] = kick * 0.55 + stab
	return b


static func _step(seconds: float, weight: float, base: float = 90.0) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(weight * 100.0)
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.35
		var thump := sin(TAU * base * t) * exp(-t * 18.0) * weight
		b[i] = (n + thump) * 0.8
	return b


static func _slide(seconds: float, opening: bool) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3 if opening else 4
	var lp := 0.0
	for i in b.size():
		var t := float(i) / seconds / RATE
		var f := 0.05 + 0.25 * (t if opening else 1.0 - t)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), f)
		var clunk := 0.0
		var tt := float(i) / RATE
		var end_t := tt - seconds * 0.85
		if end_t > 0.0:
			clunk = sin(TAU * 70.0 * end_t) * exp(-end_t * 25.0)
		b[i] = (lp * 0.6 + sin(TAU * 120.0 * tt) * 0.1) * _env(i, b.size(), 0.05, 0.15) + clunk * 0.7
	return b


static func _buzz(seconds: float, freq: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (1.0 if sin(TAU * freq * t) > 0.0 else -1.0) * 0.25 * _env(i, b.size(), 0.005, 0.05)
	return b


static func _impact(seconds: float, base: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (rng.randf_range(-1.0, 1.0) * exp(-t * 14.0) * 0.6 + sin(TAU * base * t) * exp(-t * 8.0)) * 0.8
	return b


static func _alarm(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var f := 640.0 if fmod(t, 1.0) < 0.5 else 480.0
		b[i] = sin(TAU * f * t) * 0.35 + sin(TAU * f * 2.0 * t) * 0.08
	return b


static func _sweep(seconds: float, f0: float, f1: float, amp: float = 0.4) -> PackedFloat32Array:
	var b := _buf(seconds)
	var phase := 0.0
	for i in b.size():
		var k := float(i) / b.size()
		var f := lerpf(f0, f1, k * k)
		phase += TAU * f / RATE
		b[i] = (sin(phase) + 0.3 * sin(phase * 2.0)) * amp * _env(i, b.size(), 0.05, 0.4)
	return b


static func _screech(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	var phase := 0.0
	for i in b.size():
		var k := float(i) / b.size()
		var f := 900.0 + 500.0 * sin(k * 9.0) + rng.randf_range(-120.0, 120.0)
		phase += TAU * f / RATE
		b[i] = (sin(phase + 4.0 * sin(phase * 0.51)) * 0.5 + rng.randf_range(-0.3, 0.3)) * _env(i, b.size(), 0.02, 0.5)
	return b


static func _growl(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.15)
		var am := 0.5 + 0.5 * sin(TAU * 18.0 * t)
		b[i] = (lp * am + sin(TAU * 62.0 * t) * 0.3) * _env(i, b.size(), 0.2, 0.6) * 0.8
	return b


static func _clicks(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var next := 0
	while next < b.size():
		for j in range(0, mini(220, b.size() - next)):
			b[next + j] += rng.randf_range(-1.0, 1.0) * exp(-float(j) / 30.0) * 0.7
		next += rng.randi_range(900, 2600)
	return b


static func _heartbeat(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var a := exp(-t * 18.0)
		var t2 := maxf(0.0, t - 0.28)
		var c := exp(-t2 * 18.0) * (1.0 if t > 0.28 else 0.0) * 0.7
		b[i] = sin(TAU * 45.0 * t) * (a + c) * 0.9
	return b


static func _beep(seconds: float, freq: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		b[i] = sin(TAU * freq * float(i) / RATE) * 0.3 * _env(i, b.size(), 0.002, seconds * 0.6)
	return b


static func _two_tone(seconds: float, f0: float, f1: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var half := b.size() / 2
	for i in b.size():
		var f := f0 if i < half else f1
		b[i] = sin(TAU * f * float(i) / RATE) * 0.28 * _env(i, b.size(), 0.004, seconds * 0.4)
	return b


static func _terminal(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 8:
		var start := rng.randi_range(0, b.size() - 600)
		var f := rng.randf_range(1400.0, 2600.0)
		for j in 500:
			b[start + j] += sin(TAU * f * float(j) / RATE) * 0.12 * (1.0 - float(j) / 500.0)
	for i in b.size():
		b[i] += sin(TAU * 100.0 * float(i) / RATE) * 0.04
	return b


static func _rummage(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.4)
		b[i] = lp * (0.5 + 0.5 * sin(TAU * 7.0 * t)) * 0.4 * _env(i, b.size(), 0.05, 0.2)
	return b


static func _zap(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 3000.0 * t) * 0.2) * exp(-t * 4.0)
	return b


static func _chord(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 392.0 * t) + sin(TAU * 493.9 * t) + sin(TAU * 587.3 * t)) * 0.1 * _env(i, b.size(), 0.02, 0.8)
	return b


static func _horn(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for h in range(1, 7):
			v += sin(TAU * 110.0 * h * t) / h
		b[i] = v * 0.22 * _env(i, b.size(), 0.15, 0.5)
	return b


static func _distant_bang(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.05)
		b[i] = (lp * 1.6 + sin(TAU * 38.0 * t) * 0.4) * exp(-t * 2.2) * 0.7
	return b


static func _drip(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * (1200.0 - 700.0 * t / seconds) * t) * exp(-t * 30.0) * 0.35
	return b


static func _creak(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 140.0 + 60.0 * sin(t * 3.0)
		phase += TAU * f / RATE
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		b[i] = saw * 0.18 * (0.5 + 0.5 * sin(TAU * 23.0 * t)) * _env(i, b.size(), 0.3, 0.6)
	return b


static func _crossfade_loop(b: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := b.size()
	if fade * 2 >= n:
		return b
	var out := b.slice(0, n - fade)
	for j in fade:
		var k := float(j) / fade
		out[j] = b[j] * k + b[n - fade + j] * (1.0 - k)
	return out
