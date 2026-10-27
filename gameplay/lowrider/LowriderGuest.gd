extends "res://runtime/desert/drag_meet/DragMeetGuest.gd"
## Convidado do encontro de lowriders: civil comum (dano, fuga e volta herdados do encontro do
## racha), que balança no ritmo perto do som e comemora quando um carro pula.
## Só quem está perto da câmera anima e simula, como o público do racha.
var dancer := false
var _cheer_time := 0.0
var _near_clock := 0.0
var _near := false

func _create_person() -> Node3D:
	return preload("res://gameplay/lowrider/LowriderDancerModel.gd").new()

func _ready() -> void:
	super._ready()
	set_meta("authored_population_owner", "lowrider_meet")
	add_to_group("lowrider_meet_guest")
	_update_budget()

## Um carro pulou perto: braços para cima por alguns segundos.
func cheer(seconds: float) -> void:
	if dead: return
	_cheer_time = maxf(_cheer_time, seconds)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if dead or not is_instance_valid(person): return
	_cheer_time = maxf(0.0, _cheer_time - delta)
	var standing := automatic_direction.length_squared() < .01
	if _panic > 0.0 or social_paused or not standing: return
	if _cheer_time > 0.0: person.activity = "cheer"
	elif dancer: person.activity = "groove"

func _process(delta: float) -> void:
	_near_clock -= delta
	if _near_clock > 0.0: return
	_near_clock = .25
	_update_budget()

func _update_budget() -> void:
	var view_camera := get_viewport().get_camera_3d()
	if not is_instance_valid(view_camera) or not is_instance_valid(person): return
	# A câmera fica alta e atrás: mede-se do alvo dela (o jogador), como no CivilianModel.
	var focus := view_camera.global_position
	var target: Variant = view_camera.get("target")
	if target is Node3D and is_instance_valid(target): focus = (target as Node3D).global_position
	var radius := 60.0 if _near else 45.0
	_near = focus.distance_squared_to(global_position) < radius * radius
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").set_animation_active(person, not dead and (_near or _panic > 0.0))
	set_physics_process(not dead and (_near or _panic > 0.0 or _cheer_time > 0.0))
