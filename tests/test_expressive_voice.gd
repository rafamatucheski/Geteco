extends SceneTree
const VOICE := preload("res://ExpressiveVoice.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var a := VOICE.line("Oi. Oi", "dante", 1.0)
	var b := VOICE.line("Oi. Oi", "maciota", 1.0)
	var c := VOICE.line("Oi. Oi", "caller", 1.0)
	check(a == VOICE.line("Oi. Oi", "dante", 1.0), "Buffers reused")
	check(a.data != b.data and a.data != c.data and b.data != c.data, "Three distinct profiles")
	check(a.data.decode_s16(int(0.4 * VOICE.RATE) * 2) == 0, "Period creates a silent pause")
	var peak := 0
	for i in range(0, a.data.size(), 2): peak = maxi(peak, absi(a.data.decode_s16(i)))
	check(peak > 1000 and peak < 32767, "Audible PCM without clipping")
	check(a.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Speech cannot loop forever")
	var audio := AudioStreamPlayer.new()
	root.add_child(audio)
	audio.stream = a
	audio.play()
	await create_timer(1.2).timeout
	check(not audio.playing and VOICE.mouth(audio) == 0.0, "Finite voice and closed mouth after completion")
	audio.stream = b
	audio.play()
	audio.stop()
	check(VOICE.mouth(audio) == 0.0, "Cancel closes mouth immediately")
	for i in 35: VOICE.line("Teste %d." % i, "dante", 0.3)
	check(VOICE.cache.size() <= 32, "Bounded cache")
	audio.queue_free()
	await process_frame
	print("EXPRESSIVE_VOICE: %d failures" % failures)
	quit(0 if failures == 0 else 1)
