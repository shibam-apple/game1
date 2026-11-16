extends Node
## Tiny synthesised sound set so the build needs no audio files yet.

const RATE := 22050
var _streams := {}
var _players: Array = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# name: [duration, noise, noise_lowpass, tone_hz_start, tone_hz_end, tone_gain, decay]
	var defs := {
		"slash": [0.16, 0.7, 0.35, 0.0, 0.0, 0.0, 9.0],
		"slash_big": [0.28, 0.8, 0.18, 120.0, 60.0, 0.3, 6.0],
		"hit": [0.16, 0.8, 0.5, 140.0, 70.0, 0.7, 14.0],
		"heavy": [0.5, 0.6, 0.08, 70.0, 35.0, 1.0, 5.0],
		"dodge": [0.2, 0.5, 0.12, 0.0, 0.0, 0.0, 7.0],
		"block": [0.18, 0.5, 0.6, 520.0, 420.0, 0.5, 12.0],
		"parry": [0.5, 0.25, 0.9, 1900.0, 1850.0, 0.8, 6.0],
		"warn": [0.22, 0.0, 0.1, 440.0, 520.0, 0.45, 5.0],
		"warn_red": [0.4, 0.05, 0.1, 190.0, 150.0, 0.8, 3.0],
		"bolt": [0.2, 0.2, 0.5, 900.0, 300.0, 0.5, 9.0],
		"heal": [0.5, 0.0, 0.1, 520.0, 880.0, 0.45, 3.5],
		"limit": [0.7, 0.3, 0.1, 160.0, 640.0, 0.6, 2.5],
		"perfect": [0.6, 0.1, 0.9, 1200.0, 1600.0, 0.6, 4.0],
		"stagger": [0.8, 0.7, 0.06, 90.0, 40.0, 1.0, 3.0],
		"ui": [0.08, 0.0, 0.1, 700.0, 700.0, 0.4, 20.0],
	}
	for n in defs:
		_streams[n] = _make(defs[n])


func _make(d: Array) -> AudioStreamWAV:
	var n := int(float(d[0]) * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var u := float(i) / n
		var env := exp(-float(d[6]) * u) * minf(1.0, i / 60.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * float(d[2])
		var hz := lerpf(float(d[3]), float(d[4]), u)
		ph += TAU * hz / RATE
		var v := (lp * float(d[1]) * 2.0 + sin(ph) * float(d[5])) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func play(n: String) -> void:
	if not _streams.has(n):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[n]
	p.pitch_scale = _rng.randf_range(0.93, 1.07)
	p.volume_db = -6.0
	p.play()
