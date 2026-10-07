class_name MicRecorder
extends Node
## Push-to-talk microphone capture.
##
## Audio path: AudioStreamMicrophone -> "Mic" bus (AudioEffectRecord, so we can
## grab a WAV) -> "MicSink" bus (muted, so you don't hear yourself).
## The Mic bus itself stays un-muted so its peak meter shows your volume.

const MAX_SECONDS := 15.0

var _player: AudioStreamPlayer
var _record: AudioEffectRecord
var _mic_bus := -1
var _started_at := 0.0


func _ready() -> void:
	_mic_bus = AudioServer.get_bus_index("Mic")
	if _mic_bus == -1:
		var sink := AudioServer.bus_count
		AudioServer.add_bus(sink)
		AudioServer.set_bus_name(sink, "MicSink")
		AudioServer.set_bus_mute(sink, true)
		_mic_bus = AudioServer.bus_count
		AudioServer.add_bus(_mic_bus)
		AudioServer.set_bus_name(_mic_bus, "Mic")
		AudioServer.set_bus_send(_mic_bus, "MicSink")
		AudioServer.add_bus_effect(_mic_bus, AudioEffectRecord.new())
	_record = AudioServer.get_bus_effect(_mic_bus, 0) as AudioEffectRecord
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = "Mic"
	add_child(_player)


func is_recording() -> bool:
	return _record != null and _record.is_recording_active()


func start() -> void:
	if _record == null:
		return
	if not _player.playing:
		_player.play()
	_record.set_recording_active(true)
	_started_at = Time.get_ticks_msec() / 1000.0


## Stops recording and returns WAV file bytes (empty if nothing useful).
func stop() -> PackedByteArray:
	if not is_recording():
		return PackedByteArray()
	_record.set_recording_active(false)
	var held := Time.get_ticks_msec() / 1000.0 - _started_at
	var rec := _record.get_recording()
	if rec == null or held < 0.3:
		return PackedByteArray()
	var path := "user://last_mic_clip.wav"
	if rec.save_to_wav(path) != OK:
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func seconds_recorded() -> float:
	return Time.get_ticks_msec() / 1000.0 - _started_at if is_recording() else 0.0


## 0..1 loudness for the little mic meter in the UI.
func level() -> float:
	if _mic_bus < 0:
		return 0.0
	var db := maxf(AudioServer.get_bus_peak_volume_left_db(_mic_bus, 0), AudioServer.get_bus_peak_volume_right_db(_mic_bus, 0))
	return clampf((db + 50.0) / 50.0, 0.0, 1.0)

