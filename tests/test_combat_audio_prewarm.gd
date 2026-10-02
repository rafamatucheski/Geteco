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
	var history := AUDIO._last_gunfire_take.duplicate()
	seed(10202);expected=randi();seed(10202)
	await AUDIO.prewarm_gameplay_banks(self)
	check(randi()==expected and AUDIO._last_gunfire_take==history,"full bank warmup preserves RNG and no-repeat history")
	# Inventory of the actual authored assets, independent of the warmup manifest.
	var audio_files := DirAccess.get_files_at(AUDIO.AUDIO_DIR)
	var authored := 0
	for name in audio_files:
		if not name.ends_with(".wav"): continue
		authored += 1
		var stream: Variant = AUDIO._wav.get(name)
		check(stream is AudioStream and stream.get_length()>0,"gameplay resource retained: "+name)
	check(authored==110,"complete authored gameplay bank inventory")
	var full_identity := AUDIO._wav.duplicate()
	var generated_identity := AUDIO._generated.duplicate()
	await AUDIO.prewarm_gameplay_banks(self)
	check(full_identity==AUDIO._wav and generated_identity==AUDIO._generated,"full warmup is idempotent")
	for id in ["grenade", "grenade_bounce", "flame", "punch", "bat", "knife-1", "knife0", "knife1", "knife2"]:
		check(AUDIO._generated.has(id),"procedural sample prepared: "+id)
	print("AUDIO_PREWARM wall_ms=",warm_ms," retained_stream_data_bytes=",retained_bytes)
	print("AUDIO_PREWARM checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
