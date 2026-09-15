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
	if room.is_bank:
		_navigation.grid_step=12.0
func _create_model() -> Node3D:
	if is_instance_valid(room) and room.is_bank: return preload("res://world/harbor/events/BankClerkModel.gd").new()
	return preload("res://prototypes/living_cast/CivilianDriverModel.gd").new()
func frighten() -> void:
	if frightened or is_dead: return
	frightened=true
	if room.is_bank: reaction="flee"
	if reaction=="flee":
		travel_speed=65
		# Clear the inner edge of the counter before turning toward the exit.
		var side := -1.0 if position.x<0 else 1.0
		set_route(PackedVector2Array([room.to_global(room.project_floor(Vector2(side*1.65,-1.9))),room.to_global(room.project_floor(Vector2(side*1.65,.6))),room.to_global(room.project_floor(Vector2(side*.7,4.3)))]))
		if room.is_bank:
			var voice := AudioStreamPlayer2D.new()
			voice.name="HelpVoice"
			voice.stream=load("res://audio/reactions/bank_help_female.wav" if resident_name=="HELENA" else "res://audio/reactions/bank_help_male.wav")
			voice.bus=&"SFX"
			voice.volume_db=-4
			add_child(voice)
			voice.play()
			voice.finished.connect(voice.queue_free)
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
	if has_meta("interior_actor_presentation"):
		get_meta("interior_actor_presentation").restore()
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
	var was_dead:=is_dead
	if amount>0 and is_instance_valid(room) and room.actor_inside(): room._on_shot()
	super.take_damage(amount,source)
	if is_dead and not was_dead and is_instance_valid(room) and room.is_bank and not outside_bank:
		var pool:=preload("res://world/harbor/events/BankFloorBlood.gd").new()
		pool.guard=self
		room.add_child(pool)
