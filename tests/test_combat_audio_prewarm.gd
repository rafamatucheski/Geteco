extends SceneTree
const AUDIO = preload("res://gameplay/CombatAudio.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("AUDIO_PREWARM ","PASS " if ok else "FAIL ",label)
func run() -> void:
	var api := AUDIO.new()
	if not api.has_method("prewarm_reload_banks"):
		check(false,"reload banks must be retained before ready_for_play")
		quit(1);return
	AUDIO._wav.clear();AUDIO._reload_seconds.clear()
	AUDIO._last_gunfire_take["ak47"] = 3
	seed(10201);var expected := randi();seed(10201)
	var began := Time.get_ticks_usec()
	await api.call("prewarm_reload_banks",self)
	var warm_ms := float(Time.get_ticks_usec()-began)/1000.0
	check(randi()==expected,"global RNG preserved")
	check(AUDIO._last_gunfire_take["ak47"]==3,"gunfire no-repeat state preserved")
	var retained_bytes := 0
	for id in AUDIO.RELOAD_WEAPONS:
		var longest := 0.0
		for take in AUDIO.RELOAD_TAKES:
			var key := "reload/%s_%d.wav" % [id,take]
			var stream = AUDIO._wav.get(key)
			check(stream is AudioStream and stream.get_length()>0.0,"imported retained "+key)
			if stream is AudioStream:longest=maxf(longest,stream.get_length())
			if stream is AudioStreamWAV:retained_bytes+=stream.data.size()
		check(AUDIO._reload_seconds.has(id) and is_equal_approx(AUDIO.reload_seconds(id),maxf(AUDIO.MIN_RELOAD,longest)),"duration unchanged "+id)
	var identity:Dictionary=AUDIO._wav.duplicate()
	await api.call("prewarm_reload_banks",self)
	check(identity==AUDIO._wav,"repeat prewarm retains identical resources")
	print("AUDIO_PREWARM wall_ms=",warm_ms," retained_stream_data_bytes=",retained_bytes)
	print("AUDIO_PREWARM checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
