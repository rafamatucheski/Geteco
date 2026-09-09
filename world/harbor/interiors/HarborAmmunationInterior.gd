class_name HarborAmmunationInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"
const BUILD=preload("res://world/shared/pedestrians/CitizenDetails.gd")
const ARSENAL=preload("res://scripts/player/ArsenalWeapon3D.gd")
var actor: Node2D
var room_view: SubViewport
var camera: Camera3D
var room_sprite: Sprite2D
var scale_helper: Node
var merchant_point: Vector2
var catalog: CanvasLayer
var panel: PanelContainer
var preview: SubViewport
var gun: Node3D
var caption: Label
var feedback: Label
var buy: Button
var selection := 0
var stock := ["pistol","magnum","shotgun","sawed_off","smg","ak47","m4a1","hunting_rifle"]
var active := false
func _init() -> void:
	interior_id=&"ammunation"
	display_name="AMMU-NATION"
	room_size=Vector2(720,500)
func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass
func floor_point(p: Vector2) -> Vector2:
	return (camera.unproject_position(Vector3(p.x,0,p.y))-Vector2(room_view.size)*.5)*.52
func _setup_interior_content() -> void:
	actor=get_tree().get_first_node_in_group("player")
	room_view=SubViewport.new()
	room_view.size=Vector2i(1440,1000)
	room_view.own_world_3d=true
	room_view.transparent_bg=true
	room_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(room_view)
	var world=Node3D.new()
	room_view.add_child(world)
	BUILD.piece(world,Vector3(14,.12,10),Vector3(0,-.08,0),Color("4e5150"))
	for x in range(-7,8): BUILD.piece(world,Vector3(.018,.012,10),Vector3(x,0,0),Color("6c706c"))
	BUILD.piece(world,Vector3(14,2.7,.18),Vector3(0,1.35,-5),Color("5b5148"))
	for x in [-7,7]: BUILD.piece(world,Vector3(.18,2.7,10),Vector3(x,1.35,0),Color("6c6658"))
	BUILD.piece(world,Vector3(4,1.0,1),Vector3(0,.5,-2.2),Color("694c34"))
	BUILD.piece(world,Vector3(4.15,.10,1.1),Vector3(0,1.05,-2.2),Color("282d30"))
	var merchant=preload("res://world/harbor/events/BankClerkModel.gd").new()
	merchant.position=Vector3(0,0,-3.2)
	world.add_child(merchant)
	merchant.set_process(false)
	for side in [-1,1]:
		BUILD.piece(world,Vector3(3.2,1.8,.12),Vector3(side*4.6,1.5,-4.75),Color("24292b"))
		for i in 3:
			var rack_gun=Node3D.new()
			world.add_child(rack_gun)
			ARSENAL.build(rack_gun,stock[i+2])
			rack_gun.position=Vector3(side*4.6,1+i*.48,-4.5)
			rack_gun.rotation.y=PI*.5
			rack_gun.scale=Vector3.ONE*1.8
	camera=Camera3D.new()
	room_view.add_child(camera)
	camera.fov=46
	camera.look_at_from_position(Vector3(3.2,8.4,8.5),Vector3(0,1.2,-.6))
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-25,0)
	light.light_energy=1.0
	room_view.add_child(light)
	var environment=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("c6d0d4")
	environment.environment.ambient_light_energy=.4
	room_view.add_child(environment)
	for side in [-1,1]:
		BUILD.piece(world,Vector3(1.2,.7,1.0),Vector3(side*5.5,.35,1.5),Color("484f3b"))
		BUILD.piece(world,Vector3(1.25,.07,1.05),Vector3(side*5.5,.74,1.5),Color("626a50"))
		BUILD.piece(world,Vector3(.8,.16,.5),Vector3(side*5.5,.85,1.5),Color("aa8c55"))
	room_sprite=Sprite2D.new()
	room_sprite.texture=room_view.get_texture()
	room_sprite.scale=Vector2.ONE*.52
	add_child(room_sprite)
	_create_spawn_and_exit(floor_point(Vector2(0,3)),floor_point(Vector2(0,4.1)),&"ammunation_exterior_return","SAIR")
	exit_door.get_node("Facade").hide()
	exit_door.custom_prompt_text="[E] SAIR"
	for rect in [Rect2(-7,-5,14,.18),Rect2(-7,-5,.18,10),Rect2(6.82,-5,.18,10),Rect2(-7,4.8,14,.18),Rect2(-2,-2.7,4,1),Rect2(-6.1,1,1.2,1),Rect2(4.9,1,1.2,1)]:
		var body=StaticBody2D.new()
		var collision=CollisionPolygon2D.new()
		collision.polygon=PackedVector2Array([floor_point(rect.position),floor_point(Vector2(rect.end.x,rect.position.y)),floor_point(rect.end),floor_point(Vector2(rect.position.x,rect.end.y))])
		body.add_child(collision)
		add_child(body)
	merchant_point=floor_point(Vector2(0,-1.25))
	var prompt=Label.new()
	prompt.text="[E] FALAR COM O ARMEIRO"
	prompt.position=merchant_point+Vector2(-100,-25)
	add_child(prompt)
	_build_catalog()
func _build_catalog() -> void:
	catalog=CanvasLayer.new()
	catalog.layer=80
	add_child(catalog)
	var layout=Control.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catalog.add_child(layout)
	panel=PanelContainer.new()
	layout.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-330
	panel.offset_right=330
	panel.offset_top=-270
	panel.offset_bottom=270
	var style=StyleBoxFlat.new()
	style.bg_color=Color("171d22")
	style.border_color=Color("b75c40")
	style.set_border_width_all(2)
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=18
	style.content_margin_bottom=18
	panel.add_theme_stylebox_override("panel",style)
	var box=VBoxContainer.new()
	panel.add_child(box)
	caption=Label.new()
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",22)
	box.add_child(caption)
	var container=SubViewportContainer.new()
	container.custom_minimum_size=Vector2(620,285)
	container.stretch=true
	box.add_child(container)
	preview=SubViewport.new()
	preview.size=Vector2i(620,285)
	preview.own_world_3d=true
	preview.transparent_bg=true
	container.add_child(preview)
	gun=Node3D.new()
	preview.add_child(gun)
	var cam=Camera3D.new()
	preview.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.size=1.1
	cam.position=Vector3(.8,.5,.6)
	cam.look_at(Vector3(0,0,-.18))
	var lamp=DirectionalLight3D.new()
	lamp.rotation_degrees=Vector3(-40,-40,0)
	lamp.light_energy=1.6
	preview.add_child(lamp)
	var fill=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(25,140,0)
	fill.light_energy=.8
	preview.add_child(fill)
	feedback=Label.new()
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.y=52
	box.add_child(feedback)
	var row=HBoxContainer.new()
	box.add_child(row)
	for text in ["◀ ANTERIOR","COMPRAR","PRÓXIMA ▶","FECHAR"]:
		var button=Button.new()
		button.text=text
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(button)
		match text:
			"◀ ANTERIOR": button.pressed.connect(func(): change_selection(-1))
			"PRÓXIMA ▶": button.pressed.connect(func(): change_selection(1))
			"COMPRAR":
				buy=button
				button.pressed.connect(purchase)
			_: button.pressed.connect(close_catalog)
	catalog.hide()
	preview.render_target_update_mode=SubViewport.UPDATE_DISABLED
func change_selection(step: int) -> void:
	selection=posmod(selection+step,stock.size())
	for child in gun.get_children(): child.free()
	ARSENAL.build(gun,stock[selection])
	gun.rotation=Vector3.ZERO
	gun.scale=Vector3.ONE*(2.5 if stock[selection] in ["pistol","magnum","sawed_off"] else 1.5)
	_refresh()
func _refresh() -> void:
	var id=stock[selection]
	var data=WeaponCatalog.get_weapon(id)
	caption.text="AMMU-NATION • %s\n$%d"%[data.get("label",id),data.get("price",0)]
	var owned=actor.weapon_inventory.get(id,false)==true
	var unlocked=actor.is_weapon_shop_unlocked(id)
	buy.disabled=owned or not unlocked or actor.money<int(data.get("price",0))
	buy.text="JÁ POSSUI" if owned else ("BLOQUEADA" if not unlocked else "COMPRAR")
	feedback.text="Saldo: $%d • Dano: %d • Pente: %d\n%s"%[actor.money,data.get("damage",0),data.get("magazine_size",0),data.get("discovery_hint","") if not unlocked else "Vance: Pode olhar com calma. Escolha o que precisa."]
func open_catalog() -> void:
	if active: return
	active=true
	set_modal_state(true)
	catalog.show()
	preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	change_selection(0)
	buy.grab_focus()
func close_catalog() -> void:
	if not active: return
	active=false
	catalog.hide()
	preview.render_target_update_mode=SubViewport.UPDATE_DISABLED
	set_modal_state(false)
func purchase() -> void:
	if not active or buy.disabled: return
	var message=actor.buy_weapon(stock[selection])
	_refresh()
	feedback.text=message+"\nSaldo: $%d"%actor.money
func _unhandled_input(event: InputEvent) -> void:
	if active:
		if event.is_action_pressed("ui_cancel"): close_catalog()
		elif event.is_action_pressed("ui_left"): change_selection(-1)
		elif event.is_action_pressed("ui_right"): change_selection(1)
		else: return
		get_viewport().set_input_as_handled()
	elif actor and get_camera_rect().has_point(actor.global_position) and to_local(actor.global_position).distance_to(merchant_point)<70 and event.is_action_pressed("interact"):
		open_catalog()
		get_viewport().set_input_as_handled()
func _process(delta: float) -> void:
	if active: gun.rotation.y+=delta*.35
	var inside=actor and get_camera_rect().has_point(actor.global_position)
	if inside and not is_instance_valid(scale_helper):
		scale_helper=preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
		add_child(scale_helper)
		scale_helper.configure(actor,camera,room_sprite)
	elif not inside:
		close_catalog()
		if is_instance_valid(scale_helper):
			scale_helper.restore()
			scale_helper.queue_free()
			scale_helper=null
func _exit_tree() -> void:
	if is_instance_valid(scale_helper): scale_helper.restore()
