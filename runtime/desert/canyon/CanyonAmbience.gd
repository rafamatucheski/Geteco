extends Node3D
## Three bounded voices on the existing Ambient bus. Original PCM is baked
## offline; no synthesis, world scans or resource loads in the frame loop.
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const REMAINS := preload("res://world/desert/canyon/ScavengerRemains.gd")
const TERRAIN := preload("res://world/desert/canyon/DesertSmugglerTerrain.gd")
const BANK := {
	"wind":preload("res://audio/desert_canyon/gorge_wind.wav"),
	"canvas":preload("res://audio/desert_canyon/hideout_canvas.wav"),
	"metal":[preload("res://audio/desert_canyon/bridge_stress_0.wav"),preload("res://audio/desert_canyon/bridge_stress_1.wav")],
	"vulture":[preload("res://audio/desert_canyon/vulture_croak_0.wav"),preload("res://audio/desert_canyon/vulture_croak_1.wav")],
}
var session
var encounter: Node3D
var wind: AudioStreamPlayer
var detail: AudioStreamPlayer3D
var shelter: AudioStreamPlayer3D
var enabled := true
var _tick := 0.0
var _gain := 0.0
var _shelter_gain := 0.0
var _combat_hold := 0.0
var _detail_clock := 3.0
var _last_kind := "vulture"
var _played := {"metal":0,"vulture":0}
var _bird_positions: Array[Vector3]=[]
var _rng := RandomNumberGenerator.new()

func configure(owner_session, owner_encounter: Node3D) -> void:
	session=owner_session
	encounter=owner_encounter
	name="CanyonAmbience"
	_rng.seed=8102026
	var bus := &"Ambient" if AudioServer.get_bus_index(&"Ambient")>=0 else (&"SFX" if AudioServer.get_bus_index(&"SFX")>=0 else &"Master")
	wind=AudioStreamPlayer.new()
	wind.name="DeepGorgeWind"
	wind.bus=bus
	wind.max_polyphony=1
	wind.volume_db=-80
	wind.stream=_loop(BANK.wind)
	add_child(wind)
	detail=_voice("BridgeAndScavengerDetail",bus)
	detail.unit_size=70
	detail.max_distance=240
	shelter=_voice("HideoutCanvas",bus)
	shelter.unit_size=40
	shelter.max_distance=95
	shelter.position=L.CENTER+Vector3(2,1.2,7)
	shelter.stream=_loop(BANK.canvas)
	for point: Vector2 in REMAINS.BODY_POINTS:
		_bird_positions.append(Vector3(point.x,TERRAIN.surface_height(point)+.7,point.y))
	session.world.gameplay.weapon_fired.connect(_weapon_fired)
	session.world.gameplay.npc_gunfire.connect(_npc_gunfire)

func _voice(label: String, bus: StringName) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name=label
	voice.bus=bus
	voice.volume_db=-80
	voice.max_polyphony=1
	add_child(voice)
	return voice

static func _loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin=0
	stream.loop_end=roundi(stream.get_length()*stream.mix_rate)
	return stream

static func presence(point: Vector3) -> Dictionary:
	var bridge_x := 1.0-smoothstep(6.0,60.0,absf(point.x-L.CENTER.x))
	var beyond_bridge := maxf(0.0,maxf(-803.0-point.z,point.z+516.0))
	var bridge := bridge_x*(1.0-smoothstep(0.0,34.0,beyond_bridge))
	var camp_distance := Vector2(point.x-L.CENTER.x,point.z-L.CENTER.z).length()
	var camp := 1.0-smoothstep(12.0,52.0,camp_distance)
	return {"bridge":bridge,"camp":camp,"wind":maxf(bridge,camp*.67)}

func _allowed() -> bool:
	return enabled and L.enabled() and is_instance_valid(session) and session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.gameplay.health>0 and not session.world.player.dead and (not session.modal or session.dialogue_open) and not session.has_position_transition()

func _process(delta: float) -> void:
	_tick+=delta
	if _tick<.1 or not is_instance_valid(wind): return
	var elapsed := _tick
	_tick=0
	if not _allowed():
		stop()
		return
	_combat_hold=maxf(0,_combat_hold-elapsed)
	var fighting := _combat_hold>0 or (is_instance_valid(encounter) and bool(encounter.get("_engaged")))
	var talking: bool=session.dialogue_open
	var weights := presence(session.world.player.global_position)
	var duck := .22 if fighting else (.28 if talking else 1.0)
	_gain=lerpf(_gain,float(weights.wind)*duck,1-exp(-elapsed/.65))
	_shelter_gain=lerpf(_shelter_gain,float(weights.camp)*(0.0 if fighting else (.28 if talking else 1.0)),1-exp(-elapsed/.7))
	wind.volume_db=-16.0+linear_to_db(maxf(_gain,.0001))
	shelter.volume_db=-13.0+linear_to_db(maxf(_shelter_gain,.0001))
	_update_bed(wind,_gain)
	_update_bed(shelter,_shelter_gain)
	if fighting or talking or float(weights.bridge)<.05:
		detail.stop()
		_detail_clock=maxf(_detail_clock,2.5)
		return
	_detail_clock-=elapsed
	if _detail_clock<=0 and not detail.playing: _play_detail(float(weights.bridge))

func _update_bed(voice: Node, gain: float) -> void:
	if gain>.008 and not voice.playing: voice.play()
	elif gain<.002 and voice.playing: voice.stop()

func _play_detail(weight: float) -> void:
	var at: Vector3=session.world.player.global_position
	var kind := "vulture" if _last_kind=="metal" else "metal"
	var variant := _rng.randi_range(0,1)
	if kind=="vulture":
		var closest := _bird_positions[0]
		var best := INF
		for bird in _bird_positions:
			var distance := Vector2(bird.x-at.x,bird.z-at.z).length_squared()
			if distance<best: best=distance; closest=bird
		detail.global_position=closest
		detail.volume_db=-5.0+linear_to_db(maxf(weight,.0001))
	else:
		# The stressed member is beside the crossing, not at an arbitrary urban
		# sound anchor. Slight position variation preserves the exposed span.
		detail.global_position=Vector3(L.CENTER.x+(-1.8 if variant==0 else 1.8),.4,clampf(at.z+_rng.randf_range(-5,5),-796,-522))
		detail.volume_db=-12.0+linear_to_db(maxf(weight,.0001))
	detail.stream=BANK[kind][variant]
	detail.pitch_scale=_rng.randf_range(.90,1.04)
	detail.play()
	_played[kind]=int(_played[kind])+1
	_last_kind=kind
	_detail_clock=_rng.randf_range(8.0,12.0)

func _weapon_fired(_weapon: String, point: Vector3) -> void: _duck_for_shot(point)
func _npc_gunfire(point: Vector3, _direction: Vector3, _shooter: Node3D) -> void: _duck_for_shot(point)
func _duck_for_shot(point: Vector3) -> void:
	if not _allowed(): return
	if session.world.player.global_position.distance_squared_to(point)<6400:
		_combat_hold=3.5
		if is_instance_valid(detail): detail.stop()

func set_enabled(value: bool) -> void:
	enabled=value
	set_process(value)
	if not value: stop()

func stop() -> void:
	for voice in [wind,detail,shelter]:
		if is_instance_valid(voice): voice.stop()
	_gain=0
	_shelter_gain=0
	_combat_hold=0
	_detail_clock=3

func snapshot() -> Dictionary:
	return {"enabled":enabled,"allowed":_allowed(),"voice_budget":3,"wind_playing":is_instance_valid(wind) and wind.playing,"detail_playing":is_instance_valid(detail) and detail.playing,"shelter_playing":is_instance_valid(shelter) and shelter.playing,"wind_gain":_gain,"shelter_gain":_shelter_gain,"combat_hold":_combat_hold,"played":_played.duplicate(),"detail_position":str(detail.global_position) if is_instance_valid(detail) else ""}

func _notification(what: int) -> void:
	if what==NOTIFICATION_PAUSED: stop()

func _exit_tree() -> void:
	stop()
	for voice in [wind,detail,shelter]:
		if is_instance_valid(voice): voice.stream=null
