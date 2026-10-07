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
	_sounds.ring = _make_ring()
	_sounds.ding = _make_arpeggio([1568.0, 2093.0], 0.12, 0.35)
	_sounds.register = _make_arpeggio([1319.0, 1760.0, 2637.0], 0.05, 0.3)
	_sounds.awooga = _make_awooga()
	_sounds.airhorn = _make_airhorn()
	_sounds.goat = _make_goat()
	_sounds.hangup = _make_arpeggio([480.0, 480.0, 480.0], 0.12, 0.2, true)
	_sounds.scream = babble("WAAAAAAAAAAAGH!!", 330.0, 1.8)


var _music: AudioStreamPlayer


## Bouncy little background loop (made of math, like everything else).
func start_music() -> void:
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = _make_music()
		add_child(_music)
	_music.volume_db = linear_to_db(maxf(Settings.music_volume * 0.35, 0.0001))
	if not _music.playing:
		_music.play()


func set_music_mood(night: float) -> void:
	if _music:
		_music.pitch_scale = lerpf(1.0, 0.92, night)
		_music.volume_db = linear_to_db(maxf(Settings.music_volume * 0.35, 0.0001))


func _make_music() -> AudioStreamWAV:
	# C - Am - F - G, two times through, with a walking bass and a goofy lead.
	var bpm := 132.0
	var beat := 60.0 / bpm
	var chords := [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
	var lead := [0, 2, 4, 2, 5, 4, 2, 0, 1, 2, 0, -1, 4, 5, 4, 2]
	var scale := [261.6, 293.7, 329.6, 349.2, 392.0, 440.0, 493.9, 523.3]
	var total_beats := 32
	var n := int(total_beats * beat * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var b := t / beat
		var bar := int(b / 4.0) % 4
		var chord: Array = chords[bar]
		var in_beat := fmod(b, 1.0)
		# Bass: root on the beat, fifth on the off-beat
		var bass_f: float = chord[0] * 0.5 * (1.5 if int(b) % 2 == 1 else 1.0)
		var bass := _osc("tri", t * bass_f) * 0.22 * (1.0 - in_beat * 0.6)
		# Chord stabs on the off-beats
		var stab := 0.0
		if fmod(b, 1.0) > 0.5:
			var env := 1.0 - (fmod(b, 1.0) - 0.5) * 2.0
			for f in chord:
				stab += _osc("square", t * f) * 0.025 * env
		# Lead every half beat (silent on some notes so it breathes)
		var step := int(b * 2.0) % lead.size()
		var note: int = lead[step]
		var lead_v := 0.0
		if note >= 0 and int(b * 2.0) % 8 != 7:
			var lf: float = scale[note % scale.size()]
			var le := 1.0 - fmod(b * 2.0, 1.0)
			lead_v = (_osc("square", t * lf) * 0.5 + _osc("sine", t * lf * 2.0) * 0.5) * 0.07 * le
		# Hi-hat tick
		var hat := 0.0
		if fmod(b * 2.0, 1.0) < 0.06:
			hat = (randf() * 2.0 - 1.0) * 0.04
		s[i] = bass + stab + lead_v + hat
	var wav := _to_wav(s)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = s.size()
	return wav


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


## Car horn, by Silly Horn upgrade level.
func honk(horn_level: int) -> void:
	match horn_level:
		1:
			play("awooga")
		2:
			play("airhorn")
		3:
			play("goat", randf_range(0.95, 1.1))
		_:
			play("honk", randf_range(0.95, 1.05))


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


func _make_ring() -> AudioStreamWAV:
	# Old-school telephone: two bursts of a fast warble.
	var s := PackedFloat32Array()
	for burst in 2:
		var n := int(0.45 * RATE)
		var phase := 0.0
		for k in n:
			var t := float(k) / RATE
			var f := 880.0 if int(t * 40.0) % 2 == 0 else 1100.0
			phase += f / RATE
			s.append(_osc("square", phase) * 0.18)
		_append_silence(s, 0.15)
	return _to_wav(s)


func _make_awooga() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var n := int(0.7 * RATE)
	var phase := 0.0
	for k in n:
		var t := float(k) / n
		var f := lerpf(180.0, 420.0, minf(t * 2.0, 1.0)) if t < 0.5 else lerpf(420.0, 300.0, (t - 0.5) * 2.0)
		phase += f / RATE
		s.append(_osc("saw", phase) * 0.35 * minf((1.0 - t) * 6.0, 1.0))
	return _to_wav(s)


func _make_airhorn() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var n := int(0.8 * RATE)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	for k in n:
		var t := float(k) / n
		p1 += 415.0 / RATE
		p2 += 523.0 / RATE
		p3 += 622.0 / RATE
		var env := minf(t * 30.0, 1.0) * minf((1.0 - t) * 8.0, 1.0)
		s.append((_osc("saw", p1) + _osc("saw", p2) + _osc("saw", p3)) * 0.15 * env)
	return _to_wav(s)


func _make_goat() -> AudioStreamWAV:
	# "MEHEHEHEH"
	var s := PackedFloat32Array()
	var n := int(0.9 * RATE)
	var phase := 0.0
	for k in n:
		var t := float(k) / n
		var f := 520.0 * (1.0 + 0.12 * sin(t * TAU * 11.0)) * lerpf(1.1, 0.85, t)
		phase += f / RATE
		var v := _osc("saw", phase) * 0.6 + _osc("square", phase * 2.0) * 0.2
		s.append(v * 0.3 * minf(t * 20.0, 1.0) * minf((1.0 - t) * 5.0, 1.0))
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
