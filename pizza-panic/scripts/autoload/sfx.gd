extends Node
## Every sound in the game is synthesized here at startup, so the project ships
## with zero audio files. Also makes "babble" voices (Animal Crossing style
## gibberish) for when no AI voice is available.

const RATE := 22050

var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_sounds.honk = _make_honk()
	_sounds.bonk = _make_bonk()
	_sounds.cash = _make_arpeggio([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.06, 0.5)
	_sounds.pickup = _make_arpeggio([392.0, 523.0, 659.0], 0.07, 0.35)
	_sounds.fail = _make_arpeggio([392.0, 330.0, 262.0, 196.0], 0.14, 0.4, true)
	_sounds.blip = _make_tone(880.0, 0.05, 0.25, "square")
	_sounds.click = _make_tone(1320.0, 0.03, 0.2, "square")
	_sounds.boing = _make_boing()
	_sounds.slam = _make_noise_thud(0.35, 0.9)
	_sounds.splat = _make_noise_thud(0.2, 0.6, 2400.0)
	_sounds.knock = _make_knock()
	_sounds.mic_on = _make_arpeggio([660.0, 990.0], 0.05, 0.25)
	_sounds.mic_off = _make_arpeggio([990.0, 660.0], 0.05, 0.25)


func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not _sounds.has(sound):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sounds[sound]
			p.pitch_scale = pitch
			p.volume_db = volume_db
			p.play()
			return


## Gibberish speech for a line of text. `pitch` is the base frequency in Hz.
func babble(text: String, pitch := 220.0, speed := 1.0) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var syllable := 0.075 / maxf(speed, 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text)
	var lower := text.to_lower()
	var question := lower.strip_edges().ends_with("?")
	var shout := text == text.to_upper() and text.length() > 3
	var i := 0
	var count := 0
	while i < lower.length():
		var c := lower[i]
		if c == " ":
			_append_silence(samples, syllable * 0.6)
		elif c in ".!?,;:":
			_append_silence(samples, syllable * 2.5)
		elif c >= "a" and c <= "z":
			# Every other letter makes a sound, which sounds more like talking.
			if count % 2 == 0:
				var vowel := c in "aeiou"
				var f := pitch * (1.0 + (c.unicode_at(0) - 97) / 60.0)
				f *= rng.randf_range(0.92, 1.12)
				if question and i > lower.length() - 6:
					f *= 1.35
				if shout:
					f *= 1.2
				_append_blip(samples, f, syllable * (1.3 if vowel else 1.0))
			count += 1
		i += 1
	return _to_wav(samples)


# --- synth helpers ------------------------------------------------------------

func _osc(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"saw":
			return fmod(phase, 1.0) * 2.0 - 1.0
		"tri":
			return abs(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
	return sin(phase * TAU)


func _append_silence(s: PackedFloat32Array, secs: float) -> void:
	for n in int(secs * RATE):
		s.append(0.0)


func _append_blip(s: PackedFloat32Array, freq: float, secs: float) -> void:
	var n := int(secs * RATE)
	var phase := 0.0
	for k in n:
		var t := float(k) / n
		var env := minf(t * 12.0, 1.0) * (1.0 - t) * (1.0 - t)
		phase += freq * (1.0 + 0.15 * t) / RATE
		var v := 0.55 * _osc("square", phase) + 0.45 * _osc("sine", phase * 0.5)
		s.append(v * env * 0.35)


func _make_tone(freq: float, secs: float, vol: float, kind := "sine") -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var n := int(secs * RATE)
	var phase := 0.0
	for k in n:
		var t := float(k) / n
		phase += freq / RATE
		s.append(_osc(kind, phase) * vol * (1.0 - t))
	return _to_wav(s)


func _make_arpeggio(notes: Array, step: float, vol: float, sad := false) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	for idx in notes.size():
		var n := int(step * RATE)
		var phase := 0.0
		for k in n:
			var t := float(k) / n
			phase += notes[idx] / RATE
			var env := (1.0 - t) if not sad else (1.0 - t * 0.5)
			s.append(_osc("square" if sad else "tri", phase) * vol * env)
	return _to_wav(s)


func _make_honk() -> AudioStreamWAV:
	# Clown-car "meep meep".
	var s := PackedFloat32Array()
	for beep in 2:
		var n := int(0.16 * RATE)
		var phase := 0.0
		var phase2 := 0.0
		for k in n:
			var t := float(k) / n
			var f := 420.0 + 60.0 * sin(t * PI)
			phase += f / RATE
			phase2 += f * 1.26 / RATE
			var env := minf(t * 20.0, 1.0) * minf((1.0 - t) * 10.0, 1.0)
			s.append((_osc("square", phase) * 0.5 + _osc("square", phase2) * 0.35) * env * 0.4)
		_append_silence(s, 0.05)
	return _to_wav(s)


func _make_bonk() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var n := int(0.28 * RATE)
	var phase := 0.0
	for k in n:
		var t := float(k) / n
		phase += lerpf(520.0, 110.0, sqrt(t)) / RATE
		s.append(sin(phase * TAU) * (1.0 - t) * 0.7)
	return _to_wav(s)


func _make_boing() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var n := int(0.4 * RATE)
	var phase := 0.0
	for k in n:
		var t := float(k) / n
		var f := lerpf(180.0, 520.0, t) + 40.0 * sin(t * 50.0)
		phase += f / RATE
		s.append(_osc("tri", phase) * (1.0 - t) * 0.5)
	return _to_wav(s)


func _make_noise_thud(secs: float, vol: float, cutoff := 600.0) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var n := int(secs * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var y := 0.0
	var a := clampf(cutoff / RATE * TAU, 0.0, 1.0)
	for k in n:
		var t := float(k) / n
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		s.append(clampf(y * 3.0, -1.0, 1.0) * pow(1.0 - t, 3.0) * vol)
	return _to_wav(s)


func _make_knock() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	for i in 3:
		var n := int(0.07 * RATE)
		var phase := 0.0
		for k in n:
			var t := float(k) / n
			phase += lerpf(260.0, 140.0, t) / RATE
			s.append(sin(phase * TAU) * pow(1.0 - t, 4.0) * 0.8)
		_append_silence(s, 0.1)
	return _to_wav(s)


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
