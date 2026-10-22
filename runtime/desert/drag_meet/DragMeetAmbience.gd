extends Node3D
## Five spatial loops and one detail. Music is owned by DragMeetScore so the
## 800 m race never depends on the crowd's streaming radius.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const ROSTER := preload("res://runtime/desert/drag_meet/DragMeetRoster.gd")
const LOOP_BUDGET := 5
const CATEGORY_BUDGET := {"crowd":2,"engine":2,"work":1}
var voices: Array[AudioStreamPlayer3D] = []
var sources: Array[Dictionary] = []
var _streams: Dictionary = {}
var _detail: AudioStreamPlayer3D
var _last_detail := -1

func _ready() -> void:
	name = "DragMeetAmbience"
	_source("vicente_crowd","crowd",LAYOUT.drag_vicente_point()+Vector3.UP,"res://audio/ambience_el/crowd_1.wav",-19.0,62.0)
	for team in ROSTER.LEADERS:
		_source(team+"_crowd","crowd",ROSTER.LEADERS[team]+Vector3.UP,"res://audio/ambience_el/crowd_%d.wav"%(sources.size()%3),-19.0,60.0)
	_source("start_crowd","crowd",Vector3(-759,1,-814),"res://audio/ambience_el/crowd_2.wav",-19.0,60.0)
	for row in [["vicente",Vector3(-805,0.7,-739.5),"muscle"],["livia",Vector3(-824,0.7,-776.8),"street"],
		["raul",Vector3(-868,0.7,-778),"muscle"],["jessica",Vector3(-768.5,0.7,-740),"street"],["nadir",Vector3(-820.5,0.7,-721),"muscle"]]:
		_source(str(row[0])+"_engine","engine",row[1],"res://audio/acoustic/engine_%s_1.wav"%row[2],-23.0,48.0)
	_source("workshop","work",LAYOUT.drag_workshop_point()+Vector3(0,1,0),"res://audio/living_city/workshop_0.ogg",-24.0,38.0)
	for index in LOOP_BUDGET: _voice("MeetLoop%d"%index)
	_detail = _voice("MeetDetail")

func _source(id: String, category: String, point: Vector3, path: String, volume: float, reach: float) -> void:
	sources.append({"id":id,"category":category,"position":point,"path":path,"volume":volume,"reach":reach})

func _voice(title: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = title
	player.bus = &"Ambient" if AudioServer.get_bus_index("Ambient")>=0 else &"Master"
	player.area_mask = 0
	player.unit_size = 15.0
	player.volume_db = -50.0
	player.max_db = -16.0
	player.set_meta("target_gain",-72.0)
	add_child(player)
	voices.append(player)
	return player

func update(listener: Vector3, suppressed: bool, elapsed: float, workshop_active := true, heat_phase := "idle", speaking := false) -> void:
	var selected: Array[Dictionary] = []
	for category in CATEGORY_BUDGET:
		var choices: Array[Dictionary] = []
		for source in sources:
			if source.category=="work" and not workshop_active: continue
			var distance: float = listener.distance_to(source.position)
			if source.category!=category or distance>=float(source.reach): continue
			var score := distance
			for index in LOOP_BUDGET:
				if voices[index].get_meta("source_id","")==source.id: score-=5.0
			choices.append({"source":source,"distance":score})
		choices.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.distance)<float(b.distance))
		for choice in choices.slice(0,int(CATEGORY_BUDGET[category])): selected.append(choice.source)
	var retained: Array[String] = []
	for source in selected: retained.append(source.id)
	for index in LOOP_BUDGET:
		var voice := voices[index]
		if str(voice.get_meta("source_id","")) not in retained:
			voice.set_meta("target_gain",-72.0)
	for source in selected:
		var voice: AudioStreamPlayer3D
		for index in LOOP_BUDGET:
			if voices[index].get_meta("source_id","")==source.id: voice=voices[index]; break
		if voice==null:
			for index in LOOP_BUDGET:
				if voices[index].get_meta("source_id","")=="": voice=voices[index]; break
		if voice==null: continue
		if voice.get_meta("source_id","")!=source.id:
			voice.stream = _stream(source.path,true)
			voice.position = source.position
			voice.max_distance = float(source.reach)
			voice.bus = &"Vehicles" if source.category=="engine" and AudioServer.get_bus_index("Vehicles")>=0 else (&"Ambient" if AudioServer.get_bus_index("Ambient")>=0 else &"Master")
			voice.unit_size = 6.0 if source.category=="engine" else 15.0
			voice.max_db = -22.0 if source.category=="engine" else -16.0
			voice.set_meta("source_id",source.id)
			voice.volume_db = -60.0
			if voice.stream!=null: voice.play(fposmod(float(abs(hash(source.id))%71),maxf(.1,voice.stream.get_length())))
		var pitch := 1.0
		var gain := float(source.volume)-(20.0 if suppressed else 0.0)-(12.0 if speaking else 0.0)
		if heat_phase in ["staging","racing","braking"]:
			# Leave the RPM cues of the two actual racers intelligible. Spatial
			# spectators can still be heard passing, with no extra artificial motors.
			gain += (1.0 if heat_phase=="staging" else -4.0) if source.category=="crowd" else -18.0
		if source.category=="engine":
			var phase := fposmod(elapsed+float(abs(hash(source.id))%17),19.0)
			var rev := sin((phase-12.0)*PI/2.0) if phase>12.0 and phase<14.0 else 0.0
			pitch+=rev*.55
			gain+=rev*4.0
		voice.pitch_scale = pitch
		voice.set_meta("target_gain",gain)
	_play_detail(listener,suppressed or speaking or heat_phase in ["staging","racing","braking"],elapsed)
	set_process(true)

func _process(delta: float) -> void:
	for index in LOOP_BUDGET:
		var voice := voices[index]
		var target := float(voice.get_meta("target_gain",-72.0))
		voice.volume_db = move_toward(voice.volume_db,target,maxf(0.0,delta)*42.0)
		if target<=-72.0 and voice.volume_db<=-71.99:
			voice.stop()
			voice.set_meta("source_id","")

func _play_detail(listener: Vector3, suppressed: bool, elapsed: float) -> void:
	var beat := int(elapsed/6.0)
	if suppressed:
		_detail.stop()
		_last_detail=beat
		return
	if beat==_last_detail: return
	_last_detail=beat
	var points := [Vector3(-868,0.8,-778),Vector3(-824,0.8,-776.8),Vector3(-768.5,0.8,-740),Vector3(-820.5,0.8,-721)]
	var point: Vector3 = points[beat%points.size()]
	if listener.distance_to(point)>32.0: return
	_detail.stream = _stream("res://audio/regional/scrap_%d.wav"%(beat%6),false)
	_detail.position = point
	_detail.max_distance = 36.0
	_detail.volume_db = -24.0
	_detail.pitch_scale = .92+float(beat%4)*.06
	if _detail.stream!=null: _detail.play()

func _stream(path: String, looped: bool) -> AudioStream:
	if _streams.has(path): return _streams[path]
	var original := load(path) as AudioStream
	if original==null: return null
	var stream := original.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis: stream.loop=looped
	elif stream is AudioStreamWAV and looped:
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=maxi(1,roundi(stream.get_length()*stream.mix_rate)-8)
	_streams[path]=stream
	return stream

func stop() -> void:
	for voice in voices:
		voice.stop()
		voice.volume_db=-72.0
		voice.set_meta("target_gain",-72.0)
		voice.set_meta("source_id","")
	set_process(false)
