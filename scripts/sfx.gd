extends Node
## Procedural sound: every effect and the music loop are synthesised into AudioStreamWAV at startup.

const RATE := 22050
const MRATE := 16000

var streams := {}
var voices: Array = []
var next_voice := 0
var music: AudioStreamPlayer
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		voices.append(p)
	streams.jump = _sweep(330.0, 700.0, 0.13, 0, 0.35)
	streams.land = _sweep(160.0, 60.0, 0.09, 2, 0.5, 0.7)
	streams.coin = _notes([988.0, 1319.0], 0.07, 0, 0.3)
	streams.boing = _sweep(180.0, 900.0, 0.28, 1, 0.55)
	streams.checkpoint = _notes([523.0, 659.0, 784.0, 1047.0], 0.08, 1, 0.5)
	streams.die = _sweep(600.0, 90.0, 0.45, 0, 0.3, 0.25)
	streams.poof = _sweep(400.0, 200.0, 0.12, 2, 0.35, 0.9)
	streams.knock = _sweep(220.0, 110.0, 0.16, 0, 0.4, 0.4)
	streams.click = _sweep(900.0, 700.0, 0.04, 1, 0.4)
	streams.buy = _notes([784.0, 988.0, 1175.0, 1568.0], 0.06, 0, 0.3)
	streams.deny = _notes([220.0, 180.0], 0.09, 0, 0.3)
	streams.win = _notes([523.0, 659.0, 784.0, 659.0, 784.0, 1047.0, 1047.0], 0.11, 1, 0.55)
	streams.fail = _notes([392.0, 330.0, 262.0, 196.0], 0.16, 1, 0.5)
	music = AudioStreamPlayer.new()
	music.volume_db = -13.0
	add_child(music)
	music.stream = _music()


func set_enabled(on: bool) -> void:
	enabled = on
	if on:
		if not music.playing:
			music.play()
	else:
		music.stop()
		for v in voices:
			v.stop()


func start_music() -> void:
	if enabled and not music.playing:
		music.play()


func play(name: String, pitch := 1.0) -> void:
	if not enabled or not streams.has(name):
		return
	var p: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	p.stream = streams[name]
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()


func _wave(ph: float, w: int) -> float:
	var f := fposmod(ph, 1.0)
	match w:
		0:
			return 1.0 if f < 0.5 else -1.0
		1:
			return absf(f * 4.0 - 2.0) - 1.0
		_:
			return randf() * 2.0 - 1.0


func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _sweep(f0: float, f1: float, dur: float, w: int, vol: float, noise := 0.0) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += lerpf(f0, f1, t) / RATE
		var s := _wave(ph, w)
		if noise > 0.0 and w != 2:
			s = lerpf(s, randf() * 2.0 - 1.0, noise)
		var env := (1.0 - t) * (1.0 - t) * minf(1.0, i / 60.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 30000.0))
	return _wav(data, RATE)


func _notes(freqs: Array, nd: float, w: int, vol: float) -> AudioStreamWAV:
	var per := int(nd * RATE)
	var n := per * freqs.size() + int(0.15 * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var k := mini(i / per, freqs.size() - 1)
		var local := float(i - k * per) / per
		ph += freqs[k] / RATE
		var env := exp(-local * 3.0) * minf(1.0, (i - k * per) / 40.0)
		if i >= per * freqs.size():
			env = exp(-(local) * 3.0) * maxf(0.0, 1.0 - float(i - per * freqs.size()) / (0.15 * RATE))
		data.encode_s16(i * 2, int(clampf(_wave(ph, w) * env * vol, -1.0, 1.0) * 30000.0))
	return _wav(data, RATE)


## Breezy 4-bar loop: triangle bass + soft square arpeggio + noise hats.
func _music() -> AudioStreamWAV:
	var bpm := 132.0
	var eighth := 60.0 / bpm / 2.0
	var chords := [[0, 4, 7], [-3, 0, 4], [-7, -3, 0], [-5, -1, 2]]
	var pattern := [0, 1, 2, 1, 0, 2, 1, 2]
	var melody := [12, 11, 7, 9, 7, 4, 7, -99, 9, 7, 4, 2, 4, 0, -99, -99, 5, 4, 0, 2, 4, 5, 7, -99, 7, 9, 11, 12, 11, 7, -99, -99]
	var steps := 32
	var per := int(eighth * MRATE)
	var n := per * steps
	var data := PackedByteArray()
	data.resize(n * 2)
	var base := 261.63
	var ph_b := 0.0
	var ph_a := 0.0
	var ph_m := 0.0
	for i in n:
		var st := i / per
		var lt := float(i - st * per) / per
		var ch: Array = chords[st / 8]
		var fb := base * 0.25 * pow(2.0, ch[0] / 12.0)
		var fa := base * pow(2.0, (ch[pattern[st % 8]] + 12) / 12.0)
		ph_b += fb / MRATE
		ph_a += fa / MRATE
		var s := (absf(fposmod(ph_b, 1.0) * 4.0 - 2.0) - 1.0) * 0.42 * (1.0 - lt * 0.5)
		s += (1.0 if fposmod(ph_a, 1.0) < 0.25 else -0.25) * 0.07 * exp(-lt * 4.0)
		var mn: int = melody[st]
		if mn > -50:
			var fm := base * pow(2.0, mn / 12.0)
			ph_m += fm / MRATE
			s += (absf(fposmod(ph_m, 1.0) * 4.0 - 2.0) - 1.0) * 0.2 * exp(-lt * 1.6) * minf(1.0, lt * 40.0)
		if st % 2 == 1:
			s += (randf() * 2.0 - 1.0) * 0.05 * exp(-lt * 18.0)
		if st % 4 == 0:
			s += sin(lt * 60.0 * exp(-lt * 6.0)) * 0.35 * exp(-lt * 7.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var w := _wav(data, MRATE)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w
