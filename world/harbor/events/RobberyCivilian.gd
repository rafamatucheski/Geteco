extends "res://world/harbor/events/WorldEventResident.gd"
var reaction := "cower"
var frightened := false
var call_progress := 0.0
var room: Node2D
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
	super._physics_process(delta)
	if not frightened or is_dead: return
	if reaction=="call":
		call_progress+=delta
		if call_progress>5:
			room.call_confirmed=true
			speech.text="A polícia está a caminho!"
	elif reaction=="flee" and finished:
		hide()
		collision_layer=0
		set_physics_process(false)

func take_damage(amount: int, source: Variant = null) -> void:
	if amount>0 and is_instance_valid(room) and room.actor_inside(): room._on_shot()
	super.take_damage(amount,source)
