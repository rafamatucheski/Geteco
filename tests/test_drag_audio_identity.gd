extends SceneTree
## Finite score lifetime, native bus routing, phase balance and spatial handoff.
## PCM balance is covered separately by capture_drag_audio_identity.gd in Main.
const SCORE := preload("res://runtime/desert/drag_meet/DragMeetScore.gd")
const AMBIENCE := preload("res://runtime/desert/drag_meet/DragMeetAmbience.gd")
const BARKS := preload("res://runtime/desert/drag_meet/DragMeetBarks.gd")
const BANK := preload("res://audio/DirectedVoiceBank.gd")
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const LIFE := preload("res://runtime/desert/drag_meet/DragMeetLife.gd")
var checks := 0
var failures: Array[String] = []

class HealthFixture extends Node:
	var health := 100.0

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("DRAG_AUDIO timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	print("DRAG_AUDIO ","PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)

func settle(score: Node, seconds := 4.0) -> void:
	for tick in int(seconds*60): score._process(1.0/60.0)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var initial_music_bus := AudioServer.get_bus_index("Music")
	var initial_music_db := AudioServer.get_bus_volume_db(initial_music_bus)
	var initial_music_mute := AudioServer.is_bus_mute(initial_music_bus)
	# This isolated process exercises both enabled and disabled settings without
	# writing a preference file or assuming the developer's current sliders.
	AudioServer.set_bus_volume_db(initial_music_bus,0.0)
	AudioServer.set_bus_mute(initial_music_bus,false)
	for identity in BARKS.LINES:
		var line: Dictionary=BARKS.LINES[identity]
		var row := BANK.canonical(line.text,line.persona)
		var profile := BANK.profile(row)
		var covered := not profile.is_empty()
		if covered:
			for language in ["pt_BR","en"]:
				var shown := VOICE.presentation(line.text,line.persona,language,language,str(profile.character_id),str(row.get("source_section","")))
				covered=covered and shown.stream!=null and shown.stream.get_length()>.1
		check(covered,"canonical owner and PT/EN recordings exist for "+str(identity))
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene=scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position=Vector3(-922,5,-1306)
	camera.make_current()
	var score := SCORE.new()
	scene.add_child(score)
	var at := Vector3(-922,0,-1306)
	check(score.players.size()==2 and not score.is_processing(),"score starts silent with two native players")
	check(score.players.all(func(p): return p.bus==&"Music"),"both stems use the user-controlled Music bus")
	score.update_context(at,"idle",false,false,false,12.0)
	settle(score)
	check(score.players.all(func(p): return p.playing and p.stream is AudioStreamOggVorbis and p.stream.loop),"both original stems play as native looping Ogg")
	check(score.snapshot().voices==2 and not score.is_processing(),"settled audible score keeps both native voices without a frame callback")
	check(absf(score.players[0].stream.get_length()-score.players[1].stream.get_length())<.001,"stems have matching duration")
	check(absf(score.players[0].get_playback_position()-score.players[1].get_playback_position())<.025,"both stems start at the same musical phase")
	var music_bus := AudioServer.get_bus_index("Music")
	var old_db := AudioServer.get_bus_volume_db(music_bus)
	var old_mute := AudioServer.is_bus_mute(music_bus)
	AudioServer.set_bus_mute(music_bus,true)
	score.update_context(at,"idle",false,false,false,13.0)
	check(AudioServer.is_bus_mute(music_bus),"score never unmutes the user's Music setting")
	settle(score)
	check(score.snapshot().voices==0,"Music mute releases both decoder voices")
	AudioServer.set_bus_volume_db(music_bus,-31.0)
	score.update_context(at,"staging",false,false,false,14.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus),-31.0),"phase changes preserve the user's Music volume")
	AudioServer.set_bus_volume_db(music_bus,old_db)
	AudioServer.set_bus_mute(music_bus,old_mute)
	score.update_context(at,"staging",false,false,false,14.5)
	settle(score)
	var staging := score.targets.duplicate()
	score.update_context(Vector3(-100,0,-1320),"racing",false,false,false,30.0)
	check(score.is_processing() and score.snapshot().voices==2,"a new race phase wakes the fade without cutting native playback")
	settle(score)
	check(score.snapshot().voices==2 and score.mode=="racing","score survives beyond the 220 m crowd radius during 800 m pass")
	var visit := LIFE.new()
	var healthy := HealthFixture.new()
	visit.score=score
	visit.gameplay=healthy
	visit.barks.heard["livia"]=true
	visit._clear()
	check(visit.barks.heard.has("livia"),"streaming the crowd during a pass preserves heard greetings")
	check(score.targets[0]<staging[0] and score.targets[1]<staging[1],"race leaves more headroom for both engine cues than staging")
	score.update_context(Vector3(-100,0,-1320),"results",false,false,false,42.0)
	settle(score)
	check(score.targets[0]>staging[0] and score.snapshot().voices==2,"results restore the musical bed even at the far end")
	var result_db := score.targets[0]
	score.update_context(Vector3(-100,0,-1320),"results",false,true,false,43.0)
	check(score.targets[0]<=result_db-15.9,"speech ducks both stems by sixteen dB")
	score.update_context(at,"idle",false,false,true,45.0)
	settle(score)
	check(score.snapshot().voices==0,"driver-selected radio silences both score stems")
	score.update_context(at,"idle",false,false,false,47.0)
	settle(score)
	check(score.snapshot().voices==2,"switching radio off resumes the same two score players")
	score.update_context(Vector3.ZERO,"idle",false,false,false,50.0)
	settle(score)
	check(score.snapshot().voices==0 and not score.is_processing(),"leaving without an active race releases score playback")
	visit._clear()
	check(visit.barks.heard.is_empty(),"actually leaving the encounter begins a new speech visit")
	visit.free()
	healthy.free()
	score.update_context(at,"staging",true,false,false,53.0)
	settle(score)
	check(score.snapshot().voices==0,"death, interiors and transitions override race phase")
	score.update_context(at,"idle",false,false,false,54.0)
	settle(score)
	check(score.snapshot().voices==2 and score.get_child_count()==2,"revisit reuses exactly two players")
	AudioServer.set_bus_volume_db(music_bus,-80.0)
	score.update_context(at,"idle",false,false,false,55.0)
	settle(score)
	check(score.snapshot().voices==0,"zero Music slider silences and stops both stems")
	AudioServer.set_bus_volume_db(music_bus,old_db)
	score.stop()
	check(score.snapshot().voices==0 and not score.is_processing(),"explicit teardown silences score immediately")
	var ambience := AMBIENCE.new()
	scene.add_child(ambience)
	ambience.update(Vector3(-945,0,-1259),false,10.0,true,"idle")
	settle(ambience)
	check(ambience.voices.size()==6,"spatial mixer retains five loops and one detail")
	var routed := true
	for voice in ambience.voices:
		if voice.get_meta("source_id","")=="": continue
		var engine := str(voice.get_meta("source_id","")).ends_with("_engine")
		if voice.bus!=(&"SFX" if engine else &"Ambient"): routed=false
	check(routed,"parked engines use SFX while crowd and workshop use Ambient")
	check(ambience.sources.all(func(s): return s.category!="music"),"spatial mixer cannot start a competing second song")
	ambience.update(Vector3.ZERO,false,11.0,true,"idle")
	check(ambience.voices.any(func(v): return v.playing),"leaving a sound island begins a fade instead of abrupt stop")
	settle(ambience)
	check(ambience.voices.all(func(v): return not v.playing),"departed spatial loops release after the fade")
	ambience.update(Vector3(-945,0,-1259),false,12.0,true,"racing")
	settle(ambience)
	check(not ambience._detail.playing,"workshop one-shots do not interrupt a race")
	ambience.stop()
	check(ambience.voices.all(func(v): return not v.playing) and not ambience.is_processing(),"spatial teardown stops every native voice")
	AudioServer.set_bus_volume_db(initial_music_bus,initial_music_db)
	AudioServer.set_bus_mute(initial_music_bus,initial_music_mute)
	scene.free()
	await process_frame
	print("DRAG_AUDIO_DONE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
