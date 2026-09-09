extends "res://world/harbor/interiors/HarborInteriorBase.gd"
## Prototype robbery states; rewards are stored as campaign flags, not reset on re-entry.
var is_bank := true
var actor: Node2D
var entrance: Node2D
var armed_warning := false
var alarm_started := false
var shots_fired := false
var call_confirmed := false
var alarm_time := 30.0
var dispatched := false
var vault_open := false
var lockpick: CanvasLayer
var hold_time := 0.0
var hold_target := ""
var civilians: Array[Node2D] = []
var guards: Array[Node2D] = []
var vault: Node3D
var vault_body: StaticBody2D
var counter_body: StaticBody2D
var view: SubViewport
var room_camera: Camera3D
var room_display: Sprite2D
var actor_scale: Node
var vault_position := Vector2(0,-75)
var status: Label
var cashier_resists := false
var cash_paid := false
var intimidation := 0.0
var loot_meshes: Array[Node3D] = []
var loot_positions := [Vector2(-95,-105),Vector2(0,-105),Vector2(95,-105)]

func _init() -> void:
	room_size=Vector2(460,330)
	floor_color=Color("494d4b")
	accent_color=Color("7a8989")
func _build_lights() -> void: pass
func _build_walls_and_floor() -> void:
	if not is_bank: super._build_walls_and_floor()

func _setup_interior_content() -> void:
	actor=get_tree().get_first_node_in_group("player")
	_create_spawn_and_exit(Vector2(0,95),Vector2(0,145),&"robbery_exit","SAIR")
	view=SubViewport.new()
	view.size=Vector2i(1440,1000) if is_bank else Vector2i(800,600)
	view.transparent_bg=true
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(view)
	var model := Node3D.new()
	view.add_child(model)
	var builder := preload("res://world/shared/pedestrians/CitizenDetails.gd")
	builder.piece(model,Vector3(14,.15,10),Vector3(0,-.1,0),floor_color)
	for x in range(-6,7): builder.piece(model,Vector3(.025,.012,10),Vector3(x,0,0),Color("646b68"))
	builder.piece(model,Vector3(14,2.5,.18),Vector3(0,1.2,-5),Color("a29c88"))
	for x in [-7,7]: builder.piece(model,Vector3(.18,2.5,10),Vector3(x,1.2,0),Color("8c8b7f"))
	if is_bank:
		vault_body=_solid(Vector2(0,-85),Vector2(65,14))
		vault=Node3D.new()
		vault.position=Vector3(-1.1,0,-3.2)
		model.add_child(vault)
		builder.piece(vault,Vector3(2.2,2.6,.22),Vector3(1.1,1.3,0),Color("64727a"))
		builder.piece(vault,Vector3(.75,.75,.18),Vector3(1.1,1.3,.18),Color("aeb8b4"),true)
		for x in [-4.5,4.5]:
			builder.piece(model,Vector3(2.6,1.1,1.2),Vector3(x,.55,-1),Color("514b3c"))
			_solid(Vector2(x*32,-40),Vector2(90,40))
		for i in 3:
			loot_meshes.append(builder.piece(model,Vector3(.6,.18,.4),Vector3(-3+i*3,.1,-4.2),Color("81986c")))
		for x in [-170,170]:
			var guard := preload("res://world/harbor/events/BankGuard.gd").new()
			guard.position=Vector2(x,25)
			guard.room=self
			guard.uses_shotgun=guards.is_empty()
			add_child(guard)
			guards.append(guard)
	else:
		builder.piece(model,Vector3(6,1.1,1.3),Vector3(0,.55,-2),Color("6a4a39"))
		counter_body=_solid(Vector2(0,-55),Vector2(195,40))
		for x in [-5,5]:
			for y in [0.5,1.2,1.9]:
				builder.piece(model,Vector3(1.3,.15,2.8),Vector3(x,y,-1),Color("727e80"))
		cashier_resists=randf()<.25
	if is_bank:
		for x in [-4.05,4.05]:
			builder.piece(model,Vector3(5.9,2.6,.22),Vector3(x,1.3,-3.2),Color("797e79"))
		for x in [-4.5,4.5]:
			builder.piece(model,Vector3(.55,.42,.35),Vector3(x,.55+1,-1),Color("25333b"))
		for x in [-5,5]:
			builder.piece(model,Vector3(2,.12,.6),Vector3(x,.4,2.8),Color("3c514c"))
			for side in [-1,1]: builder.piece(model,Vector3(.1,.4,.5),Vector3(x+side*.8,.2,2.8),Color("77776d"))
	if is_bank: _install_finished_bank(model)
	var cam := Camera3D.new()
	view.add_child(cam)
	cam.position=Vector3(0,13,9)
	cam.look_at(Vector3.ZERO)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.size=16
	room_camera=cam
	if is_bank:
		cam.projection=Camera3D.PROJECTION_PERSPECTIVE
		cam.fov=46
		cam.look_at_from_position(Vector3(3.2,8.4,8.5),Vector3(0,1.2,-.6))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-65,-20,0)
	sun.light_energy=1.3
	sun.shadow_enabled=true
	view.add_child(sun)
	if is_bank:
		var environment := WorldEnvironment.new()
		environment.environment=Environment.new()
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color("c4cbd0")
		environment.environment.ambient_light_energy=.35
		view.add_child(environment)
	var image := Sprite2D.new()
	image.texture=view.get_texture()
	image.scale=Vector2(.52,.52) if is_bank else Vector2(.85,.85)
	room_display=image
	add_child(image)
	for i in (2 if is_bank else 1):
		var person := preload("res://world/harbor/events/RobberyCivilian.gd").new()
		person.position=Vector2(-70+i*70,40) if is_bank else Vector2(0,-100)
		person.reaction=["cower","flee","call"][i] if is_bank else "cower"
		person.room=self
		add_child(person)
		civilians.append(person)
	if is_bank: _project_bank_layout()
	exit_door.custom_prompt_text="[E] SAIR"
	exit_door.get_node("Facade").hide()
	status=Label.new()
	status.position=Vector2(-205,-155)
	status.z_index=12
	status.size=Vector2(410,50)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size",14)
	status.add_theme_color_override("font_color",Color("eedca7"))
	add_child(status)
	if actor: actor.weapon_fired.connect(_on_shot)
	_refresh_loot()
	if is_bank:
		lockpick=preload("res://ui/BankLockpick.gd").new()
		add_child(lockpick)
		lockpick.unlocked.connect(_unlock_vault)
		lockpick.cancelled.connect(func():
			actor.set_dialogue_active(false)
			hold_time=0
		)

func _install_finished_bank(model: Node3D) -> void:
	var packed := load("res://assets/bank/bank-finished.tscn") as PackedScene
	if packed == null: return
	for child in model.get_children():
		if child != vault and not child in loot_meshes:
			child.free()
	for child in vault.get_children(): child.free()
	var finished := packed.instantiate()
	model.add_child(finished)
	for part in finished.find_children("*", "MeshInstance3D", true, false):
		var label := str(part.name)
		if label.begins_with("VaultDoor") or label.begins_with("DoorBolt") or label.begins_with("Wheel") or label.begins_with("Spoke"):
			part.reparent(vault, true)

func _solid(point: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position=point
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size=size
	shape.shape=box
	body.add_child(shape)
	add_child(body)
	return body
func actor_inside() -> bool:
	return is_instance_valid(actor) and actor.visible and get_camera_rect().has_point(actor.global_position)
func armed() -> bool:
	return actor.active_weapon_id not in ["fists","knife","grenade"]
func _on_shot() -> void:
	if not actor_inside(): return
	shots_fired=true
	start_alarm()
func start_alarm() -> void:
	if alarm_started: return
	alarm_started=true
	for person in civilians: person.frighten()
	var sound := AudioStreamPlayer2D.new()
	sound.stream=ProceduralAudio.get_police_alarm_stream()
	sound.volume_db=-20
	sound.bus="SFX"
	add_child(sound)
	sound.play()
	get_tree().create_timer(3).timeout.connect(sound.queue_free)
func _process(delta: float) -> void:
	_sync_actor_scale()
	if alarm_started and not dispatched:
		alarm_time=maxf(0,alarm_time-delta)
		if alarm_time<=0: dispatch_response()
	if not actor_inside():
		if is_instance_valid(lockpick) and lockpick.active: lockpick.finish(false)
		hold_time=0
		intimidation=0
		return
	armed_warning=is_bank and armed()
	if armed_warning and actor.weapon_aim_active: start_alarm()
	if armed_warning and not alarm_started:
		status.text="SEGURANÇA: Largue a arma! Fique parado!"
	elif not alarm_started: status.text=""
	if is_bank:
		if alarm_started:
			status.text="ALARME — despacho em %ds | [E] cofre • Segure [E] dinheiro" % ceili(alarm_time) if not dispatched else "REFORÇOS ACIONADOS — procure a saída!"
		if not vault_open and to_local(actor.global_position).distance_to(vault_position)<50 and not lockpick.active:
			status.text="[E] ABRIR COFRE — destravar fechadura"
		_tick_vault(delta,Input.is_action_pressed("interact") if vault_open else Input.is_action_just_pressed("interact"))
	else:
		_tick_cashier(delta,actor.get_global_mouse_position())

func _flag(id: String) -> StringName: return StringName(("bank_" if is_bank else "fuel_")+id)
func _taken(id: String) -> bool: return get_node("/root/CampaignState").has_campaign_flag(_flag(id))
func _pay(id: String, amount: int) -> void:
	if _taken(id): return
	get_node("/root/CampaignState").set_campaign_flag(_flag(id),true)
	actor.money+=amount
	actor._refresh_weapon_ui()
	actor._show_weapon_notice("+$%d"%amount)
	var audio := AudioStreamPlayer2D.new()
	audio.stream=ProceduralAudio.get_cash_register_stream()
	audio.bus="SFX"
	audio.volume_db=-10
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()
func _tick_vault(delta: float, holding: bool) -> void:
	if is_instance_valid(lockpick) and lockpick.active: return
	var local_actor := to_local(actor.global_position)
	var target_id := ""
	if local_actor.distance_to(vault_position)<50 and not vault_open: target_id="vault"
	if vault_open:
		for i in 3:
			if local_actor.distance_to(loot_positions[i])<40 and not _taken("cash%d"%i): target_id="cash%d"%i
	if not holding or target_id.is_empty():
		hold_time=0
		hold_target=""
		return
	if target_id!=hold_target:
		hold_target=target_id
		hold_time=0
	start_alarm()
	hold_time+=delta
	if target_id=="vault" or hold_time >= 1.2:
		if target_id=="vault":
			actor.set_dialogue_active(true)
			lockpick.begin()
		else:
			_pay(target_id,400)
			_refresh_loot()
		hold_time=0
func _refresh_loot() -> void:
	for i in loot_meshes.size(): loot_meshes[i].visible=not _taken("cash%d"%i)
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
func _tick_cashier(delta: float, aim_point: Vector2) -> void:
	var clerk: Node2D=civilians[0]
	if clerk.is_dead or cash_paid or _taken("register"): return
	var ray := PhysicsRayQueryParameters2D.create(actor.global_position,clerk.global_position,1)
	# Counter separates bodies but not the customer's line of sight above it.
	ray.exclude=[actor.get_rid(),counter_body.get_rid()]
	var direction := actor.global_position.direction_to(clerk.global_position)
	var aiming: bool = actor.weapon_aim_active and armed() and actor.global_position.distance_to(clerk.global_position)<220 and direction.dot(actor.global_position.direction_to(aim_point))>.94
	if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): aiming=false
	if not aiming:
		intimidation=0
		return
	start_alarm()
	intimidation+=delta
	if cashier_resists:
		clerk.speech.text="Não vou abrir o caixa! Estou chamando a polícia!"
		call_confirmed=true
	else:
		clerk.speech.text="Calma! Vou abrir o caixa..."
		if intimidation>=3:
			_pay("register",180)
			cash_paid=true
			clerk.speech.text="Leva e vai embora!"
func dispatch_response() -> void:
	if dispatched: return
	dispatched=true
	var wanted := get_node("/root/WantedManager")
	wanted.report_crime(35 if is_bank else 15)
	var depot := get_tree().get_first_node_in_group("emergency_depot_director")
	var unit: Node2D
	if depot and is_instance_valid(entrance):
		entrance.set_meta("police_search_position",true)
		unit=depot.request_dispatch("police",entrance)
	if not is_instance_valid(unit): wanted._dispatch_police()
	wanted.police_spawn_timer=8

func project_floor(point: Vector2) -> Vector2:
	return (room_camera.unproject_position(Vector3(point.x,0,point.y))-Vector2(view.size)*.5)*room_display.scale

func _projected_solid(rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := CollisionPolygon2D.new()
	shape.polygon=PackedVector2Array([project_floor(rect.position),project_floor(Vector2(rect.end.x,rect.position.y)),project_floor(rect.end),project_floor(Vector2(rect.position.x,rect.end.y))])
	body.add_child(shape)
	add_child(body)
	return body

func _project_bank_layout() -> void:
	room_size=Vector2(720,500)
	for child in get_children():
		if child is StaticBody2D:
			remove_child(child)
			child.queue_free()
	for box in [Rect2(-7,-5,14,.18),Rect2(-7,-5,.18,10),Rect2(6.82,-5,.18,10),Rect2(-7,4.8,14,.18),Rect2(-7,-3.3,5.9,.22),Rect2(1.1,-3.3,5.9,.22),Rect2(-5.8,-1.6,2.6,1.2),Rect2(3.2,-1.6,2.6,1.2),Rect2(-6,2.5,2,.6),Rect2(4,2.5,2,.6)]:
		_projected_solid(box)
	vault_body=_projected_solid(Rect2(-1.1,-3.3,2.2,.22))
	vault_position=project_floor(Vector2(0,-2.5))
	for i in 3: loot_positions[i]=project_floor(Vector2(-3+i*3,-4.2))
	spawn_point.position=project_floor(Vector2(0,3))
	exit_door.position=project_floor(Vector2(0,4.15))
	for i in guards.size():
		guards[i].position=project_floor(Vector2(-5 if i==0 else 5,.5))
		_scale_npc(guards[i],guards[i].viewport_3d,guards[i].sprite_3d_display,Vector2(-5 if i==0 else 5,.5),1.45)
	for i in civilians.size():
		civilians[i].position=project_floor(Vector2(-4.5 if i==0 else 4.5,-2.2))
		var sprite: Sprite2D
		for child in civilians[i].get_children():
			if child is Sprite2D: sprite=child
		_scale_npc(civilians[i],civilians[i].viewport,sprite,Vector2(-4.5 if i==0 else 4.5,-2.2),1.8)

func _scale_npc(_person: Node2D, render: SubViewport, sprite: Sprite2D, point: Vector2, height: float) -> void:
	render.size=Vector2i(256,256)
	var camera := render.get_camera_3d()
	var floor_point := Vector3(point.x,0,point.y)
	var pixels := room_camera.unproject_position(floor_point+Vector3.UP*1.8).distance_to(room_camera.unproject_position(floor_point))*room_display.scale.y
	var rig_pixels := camera.unproject_position(Vector3.UP*height).distance_to(camera.unproject_position(Vector3.ZERO))
	sprite.scale=Vector2.ONE*pixels/maxf(1,rig_pixels)
	sprite.position=-(camera.unproject_position(Vector3.ZERO)-Vector2(render.size)*.5)*sprite.scale
	render.render_target_update_mode=SubViewport.UPDATE_ONCE

func _sync_actor_scale() -> void:
	if not is_bank: return
	if actor_inside() and not is_instance_valid(actor_scale):
		actor_scale=preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
		add_child(actor_scale)
		actor_scale.configure(actor,room_camera,room_display)
	elif not actor_inside() and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale=null
func _exit_tree() -> void:
	if is_instance_valid(actor_scale): actor_scale.restore()

func _unlock_vault() -> void:
	vault_open=true
	vault_body.collision_layer=0
	vault.rotation.y=-PI*.65
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
	actor.set_dialogue_active(false)
	hold_time=0



