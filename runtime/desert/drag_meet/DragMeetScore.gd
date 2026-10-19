extends Node
## Two synchronized, offline-composed stems. Survives the spatial crowd's LOD;
## never changes global bus levels, the radio station, or a persisted setting.
const STEM_PATHS := ["res://audio/drag_night/patio.ogg", "res://audio/drag_night/pulso.ogg"]
const SPEAKERS := [Vector3(-922,1.3,-1306), Vector3(-1028,1.3,-1292)]
const LOOP_SECONDS := 73.8461451247
const SILENT_DB := -72.0
var players: Array[AudioStreamPlayer] = []
var targets := PackedFloat32Array([SILENT_DB,SILENT_DB])
var mode := "outside"
var _clock := 0.0
var _load_attempted := false

func _ready() -> void:
	name = "DragMeetScore"
	for index in STEM_PATHS.size():
		var player := AudioStreamPlayer.new()
		player.name = "Patio" if index==0 else "Pulso"
		player.bus = &"Music" if AudioServer.get_bus_index("Music")>=0 else &"Master"
		player.max_polyphony = 1
		player.volume_db = SILENT_DB
		add_child(player)
		players.append(player)
	set_process(false)

func update_context(listener: Vector3, phase: String, blocked: bool, speaking: bool, radio_active: bool, elapsed: float) -> void:
	_clock = elapsed
	var distance := INF
	for point in SPEAKERS: distance=minf(distance,Vector2(listener.x-point.x,listener.z-point.z).length())
	var in_race := phase in ["staging","racing","braking","results"]
	var near_gain := 1.0-smoothstep(24.0,98.0,distance)
	mode = phase if in_race else ("patio" if near_gain>.001 else "outside")
	var gains := Vector2(-10.0,-15.0)
	match phase:
		"staging": gains=Vector2(-19.0,-16.0)
		"racing": gains=Vector2(-26.0,-26.0)
		"braking": gains=Vector2(-21.0,-24.0)
		"results": gains=Vector2(-12.0,-17.0)
	if not in_race: gains+=Vector2.ONE*linear_to_db(maxf(.0001,near_gain))
	if speaking: gains-=Vector2.ONE*16.0
	var music_bus := AudioServer.get_bus_index("Music")
	var muted := music_bus>=0 and (AudioServer.is_bus_mute(music_bus) or AudioServer.get_bus_volume_db(music_bus)<=-79.9)
	# Driver-selected radio wins. Both stems fade together, preserving the user's
	# choice and preventing two unrelated songs from playing over each other.
	if blocked or muted or radio_active or (not in_race and near_gain<=.001): gains=Vector2(SILENT_DB,SILENT_DB)
	targets[0]=maxf(SILENT_DB,gains.x)
	targets[1]=maxf(SILENT_DB,gains.y)
	if targets[0]>SILENT_DB or targets[1]>SILENT_DB:
		_start_pair()
	set_process(true)

func _start_pair() -> void:
	if players.size()!=2: return
	if players[0].playing and players[1].playing: return
	if not _load_attempted:
		_load_attempted=true
		for index in players.size():
			var path: String = STEM_PATHS[index]
			var original: AudioStreamOggVorbis
			if ResourceLoader.exists(path,"AudioStream"):
				original=ResourceLoader.load(path,"AudioStream") as AudioStreamOggVorbis
			elif FileAccess.file_exists(path):
				# Source-only worktree before import; exported PCK uses the resource
				# branch above. A missing asset is diagnosed once, never per tick.
				original=AudioStreamOggVorbis.load_from_file(path)
			if original==null:
				push_warning("DragMeetScore missing stem: "+path)
				continue
			var stream := original.duplicate() as AudioStreamOggVorbis
			stream.loop=true
			players[index].stream=stream
	if players[0].stream==null or players[1].stream==null: return
	# Start as one pair at the visit's musical clock, including after a mute or
	# returning from another region. Asset length and phase are identical.
	for index in players.size():
		var player := players[index]
		player.play(fposmod(_clock,LOOP_SECONDS))

func _process(delta: float) -> void:
	var settled := true
	var silent := true
	for index in players.size():
		var player := players[index]
		var current := player.volume_db
		var rate := 42.0 if targets[index]<current else 24.0
		var next := move_toward(current,targets[index],maxf(0.0,delta)*rate)
		if not is_equal_approx(current,next): player.volume_db=next
		if not is_equal_approx(next,targets[index]): settled=false
		if next>SILENT_DB+.01 or targets[index]>SILENT_DB: silent=false
	if settled:
		# Native playback continues without a parent frame callback. Context
		# updates wake the same fade when phase, speech, radio or settings change.
		if silent:
			for player in players: player.stop()
		set_process(false)

func stop() -> void:
	for index in players.size():
		players[index].stop()
		players[index].volume_db=SILENT_DB
		targets[index]=SILENT_DB
	mode="outside"
	set_process(false)

func snapshot() -> Dictionary:
	var playing := 0
	var levels: Array[float] = []
	for player in players:
		if player.playing: playing+=1
		levels.append(player.volume_db)
	return {"mode":mode,"voices":playing,"budget":2,"levels":levels,"targets":Array(targets),"bus":"Music"}
