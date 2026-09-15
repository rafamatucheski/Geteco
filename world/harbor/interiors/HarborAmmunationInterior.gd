class_name HarborAmmunationInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"
const ART = preload("res://guns/ammunation/AmmunationArt.gd")
const DISPLAY_SCALE := .52
var actor: Node2D
var room_view: SubViewport
var camera: Camera3D
var room_sprite: Sprite2D
var scale_helper: Node
var merchant_point: Vector2
var merchant_prompt: Label
var catalog: CanvasLayer
var panel: PanelContainer
var preview: SubViewport
var gun: Node3D
var caption: Label
var feedback: Label
var buy: Button
var ammo_button: Button
var category_buttons: Array[Button] = []
var selection := 0
var stock := ["pistol","magnum","shotgun","sawed_off","smg","ak47","m4a1","hunting_rifle","knife","knuckles","bat","axe","grenade","rpg","armor"]
var active := false
var floor_polygon := PackedVector2Array()
var _occupied := false
var _saved_camera := {}

func _init() -> void:
	interior_id = &"ammunation"
	display_name = "AMMU-NATION"
	room_size = Vector2(620,450)
func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass
func floor_point(p: Vector2) -> Vector2:
	return (camera.unproject_position(Vector3(p.x,0,p.y))-Vector2(room_view.size)*.5)*DISPLAY_SCALE
func project_floor(p: Vector2) -> Vector2: return floor_point(p)
func _setup_interior_content() -> void:
	actor = get_tree().get_first_node_in_group("player")
	room_view = SubViewport.new()
	room_view.size = Vector2i(1440,1000)
	room_view.own_world_3d = true
	room_view.transparent_bg = true
	room_view.msaa_3d = Viewport.MSAA_2X
	room_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(room_view)
	var world := Node3D.new()
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_view.add_child(world)
	ART.room(world)
	camera = Camera3D.new()
	room_view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.4
	camera.look_at_from_position(Vector3(1.8,12,12),Vector3(0,.6,0))
	# Projection must read the final transform on this frame, before making geodata.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.light_energy = 1.3
	room_view.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d6ddd0")
	env.environment.ambient_light_energy = .75
	room_view.add_child(env)
	room_sprite = Sprite2D.new()
	room_sprite.texture = room_view.get_texture()
	room_sprite.scale = Vector2.ONE*DISPLAY_SCALE
	add_child(room_sprite)
	floor_polygon = _project_rect(Rect2(-6.9,-4.9,13.8,9.8))
	var solids := {
		"NorthWall":Rect2(-7.25,-5.25,14.5,.50),
		"WestWall":Rect2(-7.25,-5.25,.50,10.5),
		"EastWall":Rect2(6.75,-5.25,.50,10.5),
		"SouthWall":Rect2(-7.25,4.75,14.5,.50),
		"ServiceCounter":Rect2(-2.6,-2.8,5.2,1.2),
		"ArmorDisplay":Rect2(-6.35,-1.05,1.7,3.05),
		"ExplosivesDisplay":Rect2(4.65,-1.05,1.7,3.05),
		"LeftStock":Rect2(-6.05,2.2,1.1,1.6),
		"RightStock":Rect2(4.95,2.2,1.1,1.6),
		"StaffOnly":Rect2(-6.8,-4.85,13.6,1.7)
	}
	for key in solids:
		var body := StaticBody2D.new()
		body.name = key
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionPolygon2D.new()
		collision.polygon = _project_rect(solids[key])
		body.add_child(collision)
		add_child(body)
	_create_spawn_and_exit(floor_point(Vector2(0,2.65)),floor_point(Vector2(0,4.0)),&"ammunation_exterior_return","SAIR DA AMMU-NATION")
	exit_door.get_node("Facade").hide()
	exit_door.get_node("Prompt").modulate.a = 0.0
	var sensor: Area2D = exit_door.get_node("InteractionArea")
	sensor.position = Vector2.ZERO
	sensor.collision_mask = 4
	var shape: CollisionShape2D = sensor.get_node("CollisionShape2D")
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(92,54)
	merchant_point = floor_point(Vector2(0,-.85))
	merchant_prompt = Label.new()
	merchant_prompt.text = "E"
	merchant_prompt.position = merchant_point+Vector2(-40,10)
	merchant_prompt.size.x = 80
	merchant_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	merchant_prompt.add_theme_font_size_override("font_size",14)
	merchant_prompt.add_theme_color_override("font_color",ART.CREAM)
	merchant_prompt.add_theme_color_override("font_outline_color",ART.INK)
	merchant_prompt.add_theme_constant_override("outline_size",3)
	merchant_prompt.hide()
	add_child(merchant_prompt)
	_build_catalog()
func _project_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([floor_point(rect.position),floor_point(Vector2(rect.end.x,rect.position.y)),floor_point(rect.end),floor_point(Vector2(rect.position.x,rect.end.y))])
func contains_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(point),floor_polygon)
func _build_catalog() -> void:
	catalog = CanvasLayer.new()
	catalog.layer = 80
	add_child(catalog)
	var layout := Control.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catalog.add_child(layout)
	var dim := ColorRect.new()
	dim.color = Color(0,0,0,.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_child(dim)
	panel = PanelContainer.new()
	layout.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -390
	panel.offset_right = 390
	panel.offset_top = -294
	panel.offset_bottom = 294
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182323")
	style.border_color = ART.RED
	style.border_width_top = 8
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	panel.add_child(box)
	var brand := Label.new()
	brand.text = "⊕  AMMU-NATION                 ARSENAL / SUPRIMENTOS"
	brand.add_theme_font_size_override("font_size",20)
	brand.add_theme_color_override("font_color",ART.CREAM)
	box.add_child(brand)
	var categories := HBoxContainer.new()
	box.add_child(categories)
	for index in 5:
		var button := Button.new()
		button.text = ["ARMAS CURTAS","ARMAS LONGAS","CORPO A CORPO","EXPLOSIVOS","PROTEÇÃO"][index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34
		var first: String = ["pistol","shotgun","knife","grenade","armor"][index]
		button.pressed.connect(func(): selection=stock.find(first); change_selection(0))
		categories.add_child(button)
		category_buttons.append(button)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",23)
	box.add_child(caption)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(720,250)
	container.stretch = true
	box.add_child(container)
	preview = SubViewport.new()
	preview.size = Vector2i(720,250)
	preview.own_world_3d = true
	preview.transparent_bg = true
	preview.msaa_3d = Viewport.MSAA_4X
	container.add_child(preview)
	gun = Node3D.new()
	preview.add_child(gun)
	var cam := Camera3D.new()
	preview.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.25
	cam.look_at_from_position(Vector3(1,.55,.7),Vector3.ZERO)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d6e0dc")
	env.environment.ambient_light_energy = .9
	preview.add_child(env)
	for direction in [Vector3(-40,-40,0),Vector3(25,140,0)]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = direction
		lamp.light_energy = 1.5
		preview.add_child(lamp)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.y = 56
	box.add_child(feedback)
	var row := HBoxContainer.new()
	box.add_child(row)
	for words in ["◀ ANTERIOR","COMPRAR","PRÓXIMA ▶","FECHAR [ESC]"]:
		var button := Button.new()
		button.text = words
		button.custom_minimum_size.y = 38
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		match words:
			"◀ ANTERIOR": button.pressed.connect(func(): change_selection(-1))
			"PRÓXIMA ▶": button.pressed.connect(func(): change_selection(1))
			"COMPRAR":
				buy = button
				button.pressed.connect(purchase)
			_: button.pressed.connect(close_catalog)
	ammo_button = Button.new()
	ammo_button.custom_minimum_size.y = 34
	ammo_button.pressed.connect(_purchase_ammo)
	box.add_child(ammo_button)
	catalog.hide()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
func change_selection(step: int) -> void:
	selection = posmod(selection+step,stock.size())
	for child in gun.get_children(): child.free()
	var model := Node3D.new()
	gun.add_child(model)
	ART.item(model,stock[selection])
	# Fit actual geometry, including long barrels and armor straps.
	var bounds := AABB()
	var first := true
	for part in model.get_children():
		if part is MeshInstance3D:
			var part_bounds: AABB = part.transform*part.get_aabb()
			bounds = part_bounds if first else bounds.merge(part_bounds)
			first = false
	model.position = -bounds.get_center()
	gun.rotation = Vector3(0,-.45,0)
	var target_size := .95 if stock[selection] in ["armor","grenade"] else 1.65
	gun.scale = Vector3.ONE * (target_size/maxf(bounds.size.length(),.1))
	_refresh()
func _data() -> Dictionary:
	if stock[selection]=="armor": return {"label":"COLETE BALÍSTICO","price":500}
	return WeaponCatalog.get_weapon(stock[selection])
func _refresh() -> void:
	var id: String = stock[selection]
	var data := _data()
	caption.text = "%s   /   $%d" % [data.get("label",id),data.get("price",0)]
	var armor := id=="armor"
	var owned: bool = actor.armor>=actor.max_armor if armor else actor.weapon_inventory.get(id,false)==true
	var unlocked: bool = armor or actor.is_weapon_shop_unlocked(id)
	buy.disabled = owned or not unlocked or actor.money<int(data.get("price",0))
	buy.text = ("PROTEÇÃO COMPLETA" if armor else "JÁ POSSUI") if owned else ("BLOQUEADA" if not unlocked else "COMPRAR • $%d"%data.price)
	var info := "Proteção: %d / %d • Reposição de até 100 pontos"%[actor.armor,actor.max_armor] if armor else "Dano: %d • Capacidade: %d"%[data.get("damage",0),maxi(0,data.get("magazine_size",0))]
	feedback.text = "Saldo: $%d  •  %s\nVance: %s"%[actor.money,info,data.get("discovery_hint","") if not unlocked else "Bem-vindo. Escolha uma categoria; eu te mostro o equipamento."]
	var rounds := maxi(0,int(data.get("magazine_size",0)))*2
	var price := _ammo_price(rounds)
	ammo_button.visible = rounds>0 and not armor
	ammo_button.text = "REPOR +%d %s • $%d"%[rounds,"GRANADAS" if id=="grenade" else "MUNIÇÕES",price]
	ammo_button.disabled = not owned or actor.money<price
	var category := 4 if armor else (3 if id in ["grenade","rpg"] else (2 if id in ["knife","knuckles","bat","axe"] else (0 if id in ["pistol","magnum"] else 1)))
	for i in category_buttons.size(): category_buttons[i].modulate = ART.CREAM if i==category else Color("8faaa3")
func _ammo_price(rounds: int) -> int:
	return maxi(40,rounds*(60 if stock[selection] in ["grenade","rpg"] else 2))
func open_catalog() -> void:
	if active or not is_instance_valid(actor) or not contains_point(actor.global_position): return
	active = true
	actor.set_dialogue_active(true)
	set_modal_state(true)
	catalog.show()
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	change_selection(0)
	category_buttons[0].grab_focus()
func close_catalog() -> void:
	if not active: return
	active = false
	catalog.hide()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(actor): actor.set_dialogue_active(false)
	set_modal_state(false)
func purchase() -> void:
	if not active or buy.disabled: return
	var message: String = actor.buy_armor_amount(100,500) if stock[selection]=="armor" else actor.buy_weapon(stock[selection])
	_refresh()
	feedback.text = message+"\nSaldo: $%d"%actor.money
func _purchase_ammo() -> void:
	if not active or ammo_button.disabled or not ammo_button.visible: return
	var rounds := int(_data().get("magazine_size",0))*2
	var message: String = actor.buy_ammo_amount(stock[selection],rounds,_ammo_price(rounds))
	_refresh()
	feedback.text = message+"\nSaldo: $%d"%actor.money
func _input(event: InputEvent) -> void:
	if not active: return
	if event.is_action_pressed("ui_cancel"): close_catalog()
	elif event.is_action_pressed("ui_left"): change_selection(-1)
	elif event.is_action_pressed("ui_right"): change_selection(1)
	else: return
	get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if active:
		if event.is_action_pressed("ui_left"): change_selection(-1)
		elif event.is_action_pressed("ui_right"): change_selection(1)
		else: return
		get_viewport().set_input_as_handled()
	elif is_instance_valid(actor) and contains_point(actor.global_position) and to_local(actor.global_position).distance_to(merchant_point)<65 and event.is_action_pressed("interact") and not event.is_echo():
		open_catalog()
		get_viewport().set_input_as_handled()
func set_npc_rendering_active(value: bool) -> void:
	if room_view: room_view.render_target_update_mode = SubViewport.UPDATE_ONCE if value else SubViewport.UPDATE_DISABLED
	if not value:
		close_catalog()
		_restore_presentation()
func _process(delta: float) -> void:
	if active: gun.rotation.y += delta*.22
	var inside: bool = is_instance_valid(actor) and contains_point(actor.global_position)
	merchant_prompt.visible = inside and not active and to_local(actor.global_position).distance_to(merchant_point)<65
	if inside and not _occupied:
		_occupied = true
		scale_helper = preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
		add_child(scale_helper)
		scale_helper.configure(actor,camera,room_sprite)
		room_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			_saved_camera = {"zoom":cam.zoom,"position":cam.position}
			cam.set_meta("compact_interior",get_camera_rect())
			cam.limit_left = -10000000
			cam.limit_top = -10000000
			cam.limit_right = 10000000
			cam.limit_bottom = 10000000
			cam.reset_smoothing()
	elif not inside and _occupied:
		close_catalog()
		_restore_presentation()
func _restore_presentation() -> void:
	if is_instance_valid(scale_helper):
		scale_helper.restore()
		scale_helper.queue_free()
		scale_helper = null
	if _occupied and is_instance_valid(actor):
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.remove_meta("compact_interior")
			cam.zoom = _saved_camera.get("zoom",Vector2.ONE)
			cam.position = _saved_camera.get("position",Vector2.ZERO)
			cam.reset_smoothing()
	_occupied = false
func _exit_tree() -> void:
	_restore_presentation()
