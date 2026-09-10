extends "res://world/harbor/events/WorldEventResident.gd"
var reaction := "cower"
var frightened := false
var call_progress := 0.0
var room: Node2D
var outside_bank := false
func _ready() -> void:
	lines.clear()
	coat_color=[Color("65515c"),Color("5b7073"),Color("7d7057")].pick_random()
	super._ready()
	add_to_group("damageable")
func _create_model() -> Node3D:
	if is_instance_valid(room) and room.is_bank: return preload("res://world/harbor/events/BankClerkModel.gd").new()
	return preload("res://prototypes/living_cast/CivilianDriverModel.gd").new()
func frighten() -> void:
	if frightened or is_dead: return
	frightened=true
	if room.is_bank: reaction="flee"
	if reaction=="flee":
		travel_speed=65
		set_route(PackedVector2Array([room.global_position+room.project_floor(Vector2(-2.3 if position.x<0 else 2.3,-2.2)),room.global_position+room.project_floor(Vector2(0,2.5)),room.exit_door.global_position]))
	elif reaction=="call": speech.text="Está acontecendo um assalto!"
	else:
		model.scale.y*=.6
		model.rotation.x=.3
func _physics_process(delta: float) -> void:
	if is_dead:
		fall_presentation.update(delta)
		return
	# A rota de evacuação tem prioridade sobre o desvio aleatório dos tiros.
	if frightened and room.is_bank: panic_timer=0
	super._physics_process(delta)
	if not frightened or is_dead: return
	if reaction=="call":
		call_progress+=delta
		if call_progress>5:
			room.call_confirmed=true
			speech.text="A polícia está a caminho!"
	elif reaction=="flee" and finished:
		if room.is_bank and not outside_bank:
			_leave_bank()
		else:
			queue_free()

func _leave_bank() -> void:
	outside_bank=true
	var side := -1.0 if resident_name=="HELENA" else 1.0
	reparent(get_tree().current_scene)
	global_position=room.entrance.global_position+Vector2(side*18,30)
	reset_physics_interpolation()
	for child in get_children():
		if child is Sprite2D:
			child.scale=Vector2.ONE*.18
			child.position=-(viewport.get_camera_3d().unproject_position(Vector3.ZERO)-Vector2(viewport.size)*.5)*child.scale
	travel_speed=85
	set_route(PackedVector2Array([room.entrance.global_position+Vector2(side*70,90),room.entrance.global_position+Vector2(side*360,100)]))

func take_damage(amount: int, source: Variant = null) -> void:
	if amount>0 and is_instance_valid(room) and room.actor_inside(): room._on_shot()
	super.take_damage(amount,source)
