extends CharacterBody3D
## A real capsule follows a clear authored aisle. Obstructions stop the worker;
## neither route following nor conversation teleports him through furniture.
const MODEL := preload("res://runtime/desert/DesertDigoMechanicModel.gd")
const REPAIR_POINT := Vector3(-1.35,.04,-1.45)
const BENCH_POINT := Vector3(-4.5,.04,1.25)
const AISLE := [Vector3(-2.6,.04,-2.8),Vector3(-4.5,.04,-1.5)]
const WALK_SPEED := 1.05
const TOOL_SOUNDS := [preload("res://audio/living_city/workshop_detail_0.wav"),preload("res://audio/living_city/workshop_detail_1.wav"),preload("res://audio/living_city/workshop_detail_2.wav")]
var model: Node3D
var workshop_origin := Vector3.ZERO
var state := "repair"
var remaining := 8.0
var route_index := 0
var talking := false
var suspended := false
var audio_enabled := true
var tool_audio: AudioStreamPlayer3D
var _tool_wait := .3
var _tool_take := 0
var _route: Array[Vector3] = []
var _conversation_target := Vector3.ZERO

func _ready() -> void:
	name="Digo"
	set_meta("gameplay_role","desert_digo_mechanic")
	set_meta("reaction_exempt",true)
	add_to_group("digo_character")
	add_to_group("desert_digo_mechanic")
	collision_layer=2
	collision_mask=7
	floor_snap_length=.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=.30
	capsule.height=1.76
	shape.shape=capsule
	shape.position.y=.88
	add_child(shape)
	model=MODEL.new()
	add_child(model)
	rotation.y=PI*.5
	tool_audio=AudioStreamPlayer3D.new()
	tool_audio.name="DigoTools"
	tool_audio.position=Vector3(0,1,.35)
	tool_audio.max_distance=65
	tool_audio.unit_size=16
	tool_audio.volume_db=-1
	if AudioServer.get_bus_index("SFX")>=0: tool_audio.bus="SFX"
	add_child(tool_audio)

func set_talking(value: bool, target := Vector3.ZERO) -> void:
	talking=value
	_conversation_target=target
	if value:
		if tool_audio!=null: tool_audio.stop()
		velocity=Vector3.ZERO
		model.speed=0.0
		model.activity="talk"
	else: model.activity=state if state in ["repair","tools"] else "walk"

func set_suspended(value: bool) -> void:
	suspended=value
	model.frozen=value
	if value:
		velocity=Vector3.ZERO
		model.speed=0.0
		if tool_audio!=null: tool_audio.stop()

func _physics_process(delta: float) -> void:
	if suspended: return
	if talking:
		_face(_conversation_target-global_position,delta)
		_set_velocity(Vector3.ZERO,delta)
		return
	if state in ["repair","tools"]:
		remaining-=delta
		_tool_wait-=delta
		if audio_enabled and _tool_wait<=0 and remaining>3.0 and not tool_audio.playing:
			tool_audio.stream=TOOL_SOUNDS[_tool_take%TOOL_SOUNDS.size()]
			tool_audio.pitch_scale=1.0 if state=="repair" else 1.08
			tool_audio.play()
			_tool_take+=1
			_tool_wait=3.4
		_face(Vector3.RIGHT if state=="repair" else Vector3.BACK,delta)
		_set_velocity(Vector3.ZERO,delta)
		if remaining<=0:
			_route.assign([AISLE[0],AISLE[1],BENCH_POINT] if state=="repair" else [AISLE[1],AISLE[0],REPAIR_POINT])
			state="to_bench" if state=="repair" else "to_car"
			route_index=0
			model.activity="walk"
		return
	var target := workshop_origin+_route[route_index]
	var offset := target-global_position
	offset.y=0
	if offset.length()<.07:
		route_index+=1
		if route_index>=_route.size():
			state="tools" if state=="to_bench" else "repair"
			remaining=3.5 if state=="tools" else 8.0
			_tool_wait=.25
			model.activity=state
		_set_velocity(Vector3.ZERO,delta)
		return
	_face(offset,delta)
	_set_velocity(offset.normalized()*minf(WALK_SPEED,offset.length()/maxf(delta,.001)),delta)

func _set_velocity(horizontal: Vector3, delta: float) -> void:
	velocity=Vector3(horizontal.x,maxf(-20.0,velocity.y-18.0*delta),horizontal.z)
	var before := global_position
	move_and_slide()
	var moved := global_position-before
	moved.y=0
	model.speed=moved.length()/maxf(delta,.001)
	if not audio_enabled and tool_audio.playing: tool_audio.stop()

func _face(offset: Vector3, delta: float) -> void:
	offset.y=0
	if offset.length_squared()>.0001:
		rotation.y=lerp_angle(rotation.y,atan2(offset.x,offset.z),minf(delta*6,1))
