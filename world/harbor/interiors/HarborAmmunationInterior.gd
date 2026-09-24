class_name HarborAmmunationInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"
const ART = preload("res://guns/ammunation/AmmunationArt.gd")
const DISPLAY_SCALE := .52
const INLINE_ROOM_BOUNDS := Rect2(-4.0, -2.04, 8.0, 4.18)
var actor: Node2D
var room_view: SubViewport
var camera: Camera3D
var room_sprite: Sprite2D
var mountain_branch := false
var inline_mode := false
var inline_pixels_per_metre := 25.0
var inline_facade: Node2D
var inline_entrance: BuildingEntrance
var inline_manager: Node
var viewport_3d: SubViewport:
	get: return room_view
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
var customize_button: Button
var workbench: PanelContainer
var workbench_button: Button
const CUSTOM = preload("res://guns/WeaponCustomization.gd")
var category_buttons: Array[Button] = []
var selection := 0
var stock := ["pistol","magnum","shotgun","sawed_off","smg","ak47","m4a1","hunting_rifle","knife","knuckles","bat","axe","grenade","rpg","flamethrower","armor"]
var active := false
var floor_polygon := PackedVector2Array()
var _occupied := false
var _saved_camera := {}

func _init() -> void:
	interior_id = &"ammunation"
	display_name = "AMMU-NATION"
	room_size = Vector2(620,450)
func _build_blackout() -> void:
	if not inline_mode:
		super._build_blackout()
func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass
func floor_point(p: Vector2) -> Vector2:
	if inline_mode:
		return (camera.unproject_position(Vector3(p.x,0,p.y))-camera.unproject_position(Vector3.ZERO)) * (inline_pixels_per_metre * 12.0 / 800.0)
	return (camera.unproject_position(Vector3(p.x,0,p.y))-Vector2(room_view.size)*.5)*DISPLAY_SCALE
func project_floor(p: Vector2) -> Vector2: return floor_point(p)
func _setup_interior_content() -> void:
	actor = get_tree().get_first_node_in_group("player")
	room_view = SubViewport.new()
	room_view.size = Vector2i(960,800) if inline_mode else Vector2i(1440,1000)
	room_view.own_world_3d = true
	room_view.transparent_bg = true
	room_view.msaa_3d = Viewport.MSAA_2X
	room_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(room_view)
	var world := Node3D.new()
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_view.add_child(world)
	if inline_mode:
		ART.compact_room(world, mountain_branch)
	else:
		ART.room(world, mountain_branch)
	camera = Camera3D.new()
	room_view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0 if inline_mode else 16.4
	if inline_mode:
		camera.look_at_from_position(Vector3(0,25.8,20),Vector3(0,1.8,0))
	else:
		camera.look_at_from_position(Vector3(0,18.6,15),Vector3(0,.6,0))
	camera.force_update_transform()
	# Projection must read the final transform on this frame, before making geodata.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 30.0
	room_view.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d6ddd0")
	env.environment.ambient_light_energy = .45
	room_view.add_child(env)
	room_sprite = Sprite2D.new()
	room_sprite.texture = room_view.get_texture()
	if inline_mode:
		var scale_factor := inline_pixels_per_metre * 12.0 / 800.0
		room_sprite.scale = Vector2.ONE * scale_factor
		room_sprite.position = -(camera.unproject_position(Vector3.ZERO) - Vector2(room_view.size) * .5) * scale_factor
		room_sprite.hide()
		room_size = Vector2(340,240)
	else:
		room_sprite.scale = Vector2.ONE*DISPLAY_SCALE
	add_child(room_sprite)
	floor_polygon = _project_rect(INLINE_ROOM_BOUNDS if inline_mode else Rect2(-6.9,-4.9,13.8,9.8))
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
	if inline_mode:
		solids = {
			"RearWall":Rect2(-4.2,-2.25,8.4,.23),
			"LeftWall":Rect2(-4.2,-2.2,.23,4.4),
			"RightWall":Rect2(3.97,-2.2,.23,4.4),
			"LeftFront":Rect2(-4.2,2.07,2.9,.23),
			"RightFront":Rect2(1.3,2.07,2.9,.23),
			"ServiceCounter":Rect2(-2.42,-1.29,4.84,.77),
			"StaffOnly":Rect2(-3.2,-2.08,6.4,.91),
			"LeftStock":Rect2(-4.0,-1.05,.79,2.3),
			"RightStock":Rect2(3.21,-1.05,.79,2.3),
		}
		if mountain_branch:
			solids["MountainStove"] = Rect2(-4.0,1.25,.56,.56)
	elif mountain_branch:
		solids.ServiceCounter.position.x += 1.7
		solids.ArmorDisplay.position.x += 2.6
		solids.LeftStock.position.x += 2.6
		solids["WoodStove"] = Rect2(-6.15,1.225,1.0,.975)
	for key in solids:
		var body := StaticBody2D.new()
		body.name = key
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionPolygon2D.new()
		collision.polygon = _project_rect(solids[key])
		body.add_child(collision)
		add_child(body)
	if inline_mode:
		spawn_point = Marker2D.new()
		spawn_point.name = "SpawnPoint"
		spawn_point.position = floor_point(Vector2(0,1.55))
		add_child(spawn_point)
	else:
		_create_spawn_and_exit(floor_point(Vector2(0,2.65)),floor_point(Vector2(0,4.0)),&"ammunation_exterior_return","SAIR DA AMMU-NATION")
		exit_door.get_node("Facade").hide()
		var sensor: Area2D = exit_door.get_node("InteractionArea")
		sensor.position = Vector2.ZERO
		sensor.collision_mask = 4
		var shape: CollisionShape2D = sensor.get_node("CollisionShape2D")
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(92,54)
	merchant_point = floor_point(Vector2(0, .14) if inline_mode else Vector2(1.7 if mountain_branch else 0.0,-.85))
	merchant_prompt = Label.new()
	merchant_prompt.text = "" if inline_mode else "E"
	merchant_prompt.position = merchant_point+(Vector2(-40,-65) if inline_mode else Vector2(-40,10))
	merchant_prompt.size.x = 80
	merchant_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	merchant_prompt.add_theme_font_size_override("font_size",10 if inline_mode else 14)
	merchant_prompt.add_theme_color_override("font_color",ART.CREAM)
	merchant_prompt.add_theme_color_override("font_outline_color",ART.INK)
	merchant_prompt.add_theme_constant_override("outline_size",3)
	merchant_prompt.hide()
	add_child(merchant_prompt)
	_build_catalog()
	var gift := preload("res://world/mountain_pass/MountainWeaponPickup.gd").new()
	gift.weapon_id = "knife" if mountain_branch else "knuckles"
	gift.pickup_id = "mountain_ammunation_gift" if mountain_branch else "harbor_ammunation_gift"
	gift.render_host = self
	gift.position = floor_point(Vector2(1.7,1.42) if inline_mode else Vector2(1.5,2.6))
	add_child(gift)
	gift.install_model(world,Vector3(1.7,.08,1.42) if inline_mode else Vector3(1.5,.08,2.6))

func contains_actor(body: Node2D) -> bool:
	return is_instance_valid(body) and is_visible_in_tree() and contains_point(body.global_position)
func _project_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([floor_point(rect.position),floor_point(Vector2(rect.end.x,rect.position.y)),floor_point(rect.end),floor_point(Vector2(rect.position.x,rect.end.y))])
func contains_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(point),floor_polygon)
func attach_inline_facade(facade: Node2D, entrance: BuildingEntrance) -> void:
	if not inline_mode or not is_instance_valid(facade):
		return
	inline_facade = facade
	inline_entrance = entrance
	inline_manager = get_parent().get_parent()
	global_position = facade.global_position
	z_as_relative = false
	z_index = 6
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	room_sprite.hide()
	var facade_sprite := facade.get("sprite_3d") as Sprite2D
	if is_instance_valid(facade_sprite):
		facade_sprite.show()
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
	var customization_row := HBoxContainer.new()
	customization_row.add_theme_constant_override("separation", 10)
	box.add_child(customization_row)
	workbench_button = Button.new()
	workbench_button.text = "PERSONALIZAR ARMA"
	workbench_button.custom_minimum_size.y = 46
	workbench_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workbench_button.size_flags_stretch_ratio = 1.7
	workbench_button.add_theme_font_size_override("font_size", 17)
	var personalize_style := StyleBoxFlat.new()
	personalize_style.bg_color = ART.RED.darkened(0.20)
	personalize_style.border_color = ART.CREAM
	personalize_style.set_border_width_all(2)
	personalize_style.corner_radius_top_left = 5
	personalize_style.corner_radius_top_right = 5
	personalize_style.corner_radius_bottom_left = 5
	personalize_style.corner_radius_bottom_right = 5
	workbench_button.add_theme_stylebox_override("normal", personalize_style)
	var personalize_hover := personalize_style.duplicate() as StyleBoxFlat
	personalize_hover.bg_color = ART.RED
	workbench_button.add_theme_stylebox_override("hover", personalize_hover)
	workbench_button.pressed.connect(_open_workbench)
	customization_row.add_child(workbench_button)
	customize_button = Button.new()
	customize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	customize_button.custom_minimum_size.y = 46
	customize_button.add_theme_font_size_override("font_size", 14)
	customize_button.pressed.connect(_customize)
	customization_row.add_child(customize_button)
	workbench = preload("res://guns/WeaponWorkbench.gd").new()
	layout.add_child(workbench)
	workbench.closed.connect(func():
		panel.show()
		preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		if active: change_selection(0))
	catalog.hide()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
func change_selection(step: int) -> void:
	selection = posmod(selection+step,stock.size())
	for child in gun.get_children(): child.free()
	var model := Node3D.new()
	gun.add_child(model)
	ART.item(model,stock[selection])
	if stock[selection] in CUSTOM.CUSTOMIZABLE:
		# Shared arsenal geometry supplies the same muzzle used by the held model.
		var muzzle: Vector3 = model.get_meta("weapon_muzzle", Vector3.ZERO)
		CUSTOM.fit(model, stock[selection], actor.weapon_customization, muzzle)
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
	return actor.get_weapon_data(stock[selection])
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
	var compatible: bool = id in CUSTOM.COMPATIBLE
	var kit: Dictionary = actor.weapon_customization.get(id, {})
	customize_button.visible = compatible
	workbench_button.visible = id in CUSTOM.CUSTOMIZABLE
	workbench_button.disabled = not owned
	customize_button.disabled = not owned or (not kit.get("owned", false) and actor.money < CUSTOM.PRICE)
	customize_button.text = "REMOVER LANTERNA" if kit.get("installed", false) else ("INSTALAR LANTERNA" if kit.get("owned", false) else "INSTALAR LANTERNA • $%d" % CUSTOM.PRICE)
	if compatible and kit.get("installed", false): feedback.text += "\n[%s] Ligar / desligar lanterna" % get_node("/root/GameInput").hint("weapon_flashlight")
	var category := 4 if armor else (3 if id in ["grenade","rpg"] else (2 if id in ["knife","knuckles","bat","axe"] else (0 if id in ["pistol","magnum"] else 1)))
	for i in category_buttons.size(): category_buttons[i].modulate = ART.CREAM if i==category else Color("8faaa3")
func _ammo_price(rounds: int) -> int:
	return maxi(40,rounds*(60 if stock[selection] in ["grenade","rpg"] else 2))
func _customize() -> void:
	if not active or customize_button.disabled or not customize_button.visible: return
	var id: String = stock[selection]
	var message: String = actor.customize_weapon(id, "remove" if CUSTOM.installed(actor.weapon_customization, id) else "install")
	change_selection(0)
	feedback.text = message + "\nSaldo: $%d • [%s] Lanterna" % [actor.money, get_node("/root/GameInput").hint("weapon_flashlight")]
func _open_workbench() -> void:
	if not active or workbench_button.disabled or not workbench_button.visible: return
	panel.hide()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	workbench.open(actor,stock[selection])
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
	workbench.close(false)
	panel.show()
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
	if workbench.visible:
		if event.is_action_pressed("ui_cancel"):
			workbench.close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"): close_catalog()
	elif event.is_action_pressed("ui_left"): change_selection(-1)
	elif event.is_action_pressed("ui_right"): change_selection(1)
	else: return
	get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if active and workbench.visible: return
	if active:
		if event.is_action_pressed("ui_left"): change_selection(-1)
		elif event.is_action_pressed("ui_right"): change_selection(1)
		else: return
		get_viewport().set_input_as_handled()
	elif is_instance_valid(actor) and contains_point(actor.global_position) and to_local(actor.global_position).distance_to(merchant_point)<(24 if inline_mode else 65) and event.is_action_pressed("interact") and not event.is_echo():
		open_catalog()
		get_viewport().set_input_as_handled()
func set_npc_rendering_active(value: bool) -> void:
	if room_view: room_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if not value:
		close_catalog()
		_restore_presentation()
func _process(delta: float) -> void:
	# MountainPass builds rooms before spawning its player. Resolve the actor
	# when it becomes available instead of keeping the setup-time null forever.
	if not is_instance_valid(actor):
		_restore_presentation()
		actor = get_tree().get_first_node_in_group("player")
	if active: gun.rotation.y += delta*.22
	var inside: bool = is_instance_valid(actor) and actor.get("is_dead") != true and contains_point(actor.global_position)
	merchant_prompt.visible = not inline_mode and inside and not active and to_local(actor.global_position).distance_to(merchant_point)<65
	if inside and not _occupied:
		_occupied = true
		if inline_mode:
			room_sprite.show()
			if is_instance_valid(inline_facade):
				var facade_sprite := inline_facade.get("sprite_3d") as Sprite2D
				if is_instance_valid(facade_sprite): facade_sprite.hide()
			if mountain_branch:
				actor.set_meta("mountain_interior", true)
				actor.set_meta("mountain_interior_id", &"ammunation")
			else:
				actor.set_meta("harbor_interior", true)
			if is_instance_valid(inline_manager):
				inline_manager.emit_signal("actor_entered_interior", actor, interior_id)
		scale_helper = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
		add_child(scale_helper)
		scale_helper.configure(actor,camera,room_sprite)
		room_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
		if inline_mode:
			room_sprite.hide()
			if is_instance_valid(inline_facade):
				var facade_sprite := inline_facade.get("sprite_3d") as Sprite2D
				if is_instance_valid(facade_sprite): facade_sprite.show()
			if is_instance_valid(actor):
				if mountain_branch:
					actor.remove_meta("mountain_interior")
					actor.remove_meta("mountain_interior_id")
				else:
					actor.remove_meta("harbor_interior")
			if is_instance_valid(inline_manager):
				inline_manager.emit_signal("actor_returned_to_exterior", actor, interior_id)
func _restore_presentation() -> void:
	if inline_mode and _occupied:
		room_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		room_sprite.hide()
		if is_instance_valid(inline_facade):
			var facade_sprite := inline_facade.get("sprite_3d") as Sprite2D
			if is_instance_valid(facade_sprite): facade_sprite.show()
	if is_instance_valid(scale_helper):
		scale_helper.restore()
		scale_helper.queue_free()
		scale_helper = null
	if _occupied and is_instance_valid(actor):
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.remove_meta("compact_interior")
			if not inline_mode:
				cam.zoom = _saved_camera.get("zoom",Vector2.ONE)
			cam.position = _saved_camera.get("position",Vector2.ZERO)
			if not inline_mode:
				cam.reset_smoothing()
	_occupied = false
func _exit_tree() -> void:
	_restore_presentation()
