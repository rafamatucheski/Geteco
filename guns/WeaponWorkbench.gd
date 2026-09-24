extends PanelContainer
signal closed
const CUSTOM = preload("res://guns/WeaponCustomization.gd")
const ARSENAL = preload("res://scripts/player/ArsenalWeapon3D.gd")
var actor: Node
var weapon_id := ""
var slot := "finish"
var candidate := "none"
var viewport: SubViewport
var model: Node3D
var wallet: Label
var detail: Label
var title: Label
var slots: HBoxContainer
var options: VBoxContainer
var apply_button: Button
var preview_state: Dictionary

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -430
	offset_right = 430
	offset_top = -310
	offset_bottom = 310
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172323")
	style.border_color = Color("a3322d")
	style.border_width_top = 6
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size",23)
	box.add_child(title)
	wallet = Label.new()
	box.add_child(wallet)
	slots = HBoxContainer.new()
	box.add_child(slots)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var view := SubViewportContainer.new()
	view.custom_minimum_size = Vector2(470,340)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.stretch = true
	body.add_child(view)
	viewport = SubViewport.new()
	viewport.size = Vector2i(470,340)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	view.add_child(viewport)
	model = Node3D.new()
	viewport.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.2
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(.7,.35,.55),Vector3.ZERO)
	for rotation in [Vector3(-45,-35,0),Vector3(25,140,0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = rotation
		light.light_energy = 1.35
		viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("becdc8")
	environment.environment.ambient_light_energy = .7
	viewport.add_child(environment)
	options = VBoxContainer.new()
	options.custom_minimum_size.x = 265
	body.add_child(options)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.y = 54
	box.add_child(detail)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	apply_button = Button.new()
	apply_button.custom_minimum_size.y = 40
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(apply_selection)
	actions.add_child(apply_button)
	var back := Button.new()
	back.text = "VOLTAR [ESC]"
	back.pressed.connect(close)
	actions.add_child(back)
	close(false)

func open(player: Node, id: String) -> void:
	actor = player
	weapon_id = id
	if id not in CUSTOM.CUSTOMIZABLE or actor.weapon_inventory.get(id,false) != true: return
	title.text = "AMMU-NATION / PERSONALIZAR — " + str(WeaponCatalog.get_weapon(id).get("short_label",id))
	for child in slots.get_children(): child.free()
	var available: Array[String] = []
	for category in CUSTOM.SLOTS:
		# The flashlight stays a single direct install/remove action in the catalog.
		if category == "flashlight": continue
		if not CUSTOM.PARTS.keys().any(func(part): return CUSTOM.PARTS[part].slot == category and CUSTOM.supports(id,part)): continue
		available.append(category)
		var button := Button.new()
		button.text = CUSTOM.SLOTS[category]
		button.add_theme_font_size_override("font_size",12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_slot.bind(category))
		button.toggle_mode = true
		button.set_meta("slot",category)
		slots.add_child(button)
	show()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	select_slot(slot if slot in available else available[0])

func select_slot(value: String) -> void:
	slot = value
	for button in slots.get_children(): button.set_pressed_no_signal(button.get_meta("slot") == slot)
	for child in options.get_children(): child.free()
	_option("none", "ORIGINAL / SEM ACESSÓRIO")
	for part in CUSTOM.PARTS:
		if CUSTOM.PARTS[part].slot == slot and CUSTOM.supports(weapon_id,part):
			var owned := CUSTOM.owns(actor.weapon_customization,weapon_id,part)
			_option(part, str(CUSTOM.PARTS[part].label) + (" • ADQUIRIDO" if owned else " • $%d" % CUSTOM.PARTS[part].price))
	select_candidate(CUSTOM.selected(actor.weapon_customization,weapon_id,slot))

func _option(id: String, words: String) -> void:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size",15)
	button.pressed.connect(select_candidate.bind(id))
	button.toggle_mode = true
	button.set_meta("part",id)
	options.add_child(button)

func select_candidate(part: String) -> void:
	candidate = part
	for button in options.get_children(): button.set_pressed_no_signal(button.get_meta("part") == part)
	preview_state = actor.weapon_customization.duplicate(true)
	var entry: Dictionary = preview_state.get(weapon_id,{}).duplicate(true)
	if slot == "flashlight": entry["installed"] = part != "none"
	else:
		var parts: Dictionary = entry.get("parts",{})
		if part == "none": parts.erase(slot)
		else: parts[slot] = part
		entry["parts"] = parts
	preview_state[weapon_id] = entry
	_rebuild_model()
	var data := CUSTOM.effective_data(weapon_id,preview_state)
	var price := 0 if CUSTOM.owns(actor.weapon_customization,weapon_id,part) else int(CUSTOM.PARTS[part].price)
	wallet.text = "SALDO: $%d" % actor.money
	var capacity := int(data.get("magazine_size",-1))
	detail.text = "Capacidade: %d • Recarga: +%d%% • Recuo: −%d%%" % [capacity,roundi((float(data.reload_multiplier)-1.0)*100.0),roundi((1.0-float(data.recoil_multiplier))*100.0)] if capacity>0 else ""
	if slot == "muzzle": detail.text += "\nSilenciador: reduz o barulho; pessoas próximas e na trajetória ainda reagem."
	elif slot == "laser": detail.text += "\nLaser ativo ao mirar; o ponto para no primeiro obstáculo."
	elif slot == "scope": detail.text += "\nAo mirar: ampliação 2× e visão adiantada, fora dos interiores."
	elif slot == "flashlight": detail.text += "\n[%s] Ligar / desligar" % get_node("/root/GameInput").hint("weapon_flashlight")
	var same := part == CUSTOM.selected(actor.weapon_customization,weapon_id,slot)
	apply_button.text = "INSTALADO" if same else ("APLICAR SEM CUSTO" if price == 0 else "COMPRAR E INSTALAR • $%d" % price)
	apply_button.disabled = same or actor.money<price

func _rebuild_model() -> void:
	for child in model.get_children(): child.free()
	var weapon := Node3D.new()
	model.add_child(weapon)
	var muzzle := ARSENAL.build(weapon,weapon_id)
	CUSTOM.fit(weapon,weapon_id,preview_state,muzzle)
	var bounds := _bounds(weapon,Transform3D.IDENTITY)
	weapon.position = -bounds.get_center()
	model.scale = Vector3.ONE * (1.12/maxf(bounds.size.length(),.1))
	model.rotation.y = -.5

func _bounds(node: Node3D, transform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	if node is MeshInstance3D:
		result = transform * node.get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _bounds(child,transform*child.transform)
			if child_bounds.size == Vector3.ZERO: continue
			result = child_bounds if first else result.merge(child_bounds)
			first = false
	return result

func apply_selection() -> void:
	if not visible or apply_button.disabled: return
	var message: String = actor.customize_weapon_part(weapon_id,slot,candidate)
	select_slot(slot)
	detail.text = message + "\n" + detail.text

func close(emit_signal := true) -> void:
	hide()
	if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	if emit_signal: closed.emit()
func _process(delta: float) -> void:
	model.rotation.y += delta*.22
