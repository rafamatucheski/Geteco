extends PanelContainer
## Port direto da bancada produtiva V1 para o estado/combate nativos V2.

signal closed

const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")

var session
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

func configure(owner_session) -> void:
	session = owner_session

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
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 23)
	box.add_child(title)
	wallet = Label.new()
	box.add_child(wallet)
	slots = HBoxContainer.new()
	box.add_child(slots)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var view := SubViewportContainer.new()
	view.custom_minimum_size = Vector2(470, 340)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.stretch = true
	body.add_child(view)
	viewport = SubViewport.new()
	viewport.size = Vector2i(470, 340)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	view.add_child(viewport)
	model = Node3D.new()
	viewport.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.2
	camera.look_at_from_position(Vector3(.7, .35, .55), Vector3.ZERO)
	viewport.add_child(camera)
	for rotation in [Vector3(-45, -35, 0), Vector3(25, 140, 0)]:
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

func open(id: String) -> void:
	if session == null or id not in CUSTOM.CUSTOMIZABLE or not session.state.economy.owns_weapon(id): return
	weapon_id = id
	title.text = "AMMU-NATION / PERSONALIZAR — " + str(WEAPONS.WEAPONS[id].get("short_label", id))
	for child in slots.get_children(): child.free()
	var available: Array[String] = []
	for category in CUSTOM.SLOTS:
		if category == "flashlight": continue
		if not CUSTOM.PARTS.keys().any(func(part): return CUSTOM.PARTS[part].slot == category and CUSTOM.supports(id, part)): continue
		available.append(category)
		var button := Button.new()
		button.text = CUSTOM.SLOTS[category]
		button.add_theme_font_size_override("font_size", 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_slot.bind(category))
		button.toggle_mode = true
		button.set_meta("slot", category)
		slots.add_child(button)
	if available.is_empty(): return
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
		if CUSTOM.PARTS[part].slot == slot and CUSTOM.supports(weapon_id, part):
			var owned := CUSTOM.owns(session.world.gameplay.customization, weapon_id, part)
			_option(part, str(CUSTOM.PARTS[part].label) + (" • ADQUIRIDO" if owned else " • $%d" % CUSTOM.PARTS[part].price))
	select_candidate(CUSTOM.selected(session.world.gameplay.customization, weapon_id, slot))

func _option(id: String, words: String) -> void:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(select_candidate.bind(id))
	button.toggle_mode = true
	button.set_meta("part", id)
	options.add_child(button)

func select_candidate(part: String) -> void:
	candidate = part
	for button in options.get_children(): button.set_pressed_no_signal(button.get_meta("part") == part)
	preview_state = session.world.gameplay.customization.duplicate(true)
	var entry: Dictionary = preview_state.get(weapon_id, {}).duplicate(true)
	var parts: Dictionary = entry.get("parts", {}).duplicate(true)
	if part == "none": parts.erase(slot)
	else: parts[slot] = part
	entry["parts"] = parts
	preview_state[weapon_id] = entry
	_rebuild_model()
	var data := CUSTOM.effective_data(weapon_id, preview_state)
	var price := 0 if part == "none" or CUSTOM.owns(session.world.gameplay.customization, weapon_id, part) else int(CUSTOM.PARTS[part].price)
	wallet.text = "SALDO: $%d" % session.state.economy.balance
	var capacity := int(data.get("magazine_size", -1))
	detail.text = "Capacidade: %d • Recarga: +%d%% • Recuo: −%d%%" % [capacity, roundi((float(data.reload_multiplier) - 1.0) * 100.0), roundi((1.0 - float(data.recoil_multiplier)) * 100.0)] if capacity > 0 else ""
	if slot == "muzzle": detail.text += "\nSilenciador: reduz o barulho; pessoas próximas e na trajetória ainda reagem."
	elif slot == "laser": detail.text += "\nLaser ativo ao mirar; o ponto para no primeiro obstáculo."
	elif slot == "scope": detail.text += "\nAo mirar: ampliação 2× e visão adiantada, fora dos interiores."
	var current: String = CUSTOM.selected(session.world.gameplay.customization, weapon_id, slot)
	var same := part == current
	apply_button.text = "INSTALADO" if same else ("APLICAR SEM CUSTO" if price == 0 else "COMPRAR E INSTALAR • $%d" % price)
	apply_button.disabled = same or session.state.economy.balance < price

func _rebuild_model() -> void:
	for child in model.get_children(): child.free()
	var weapon := Node3D.new()
	model.add_child(weapon)
	ART.item(weapon, weapon_id)
	CUSTOM.fit(weapon, weapon_id, preview_state, weapon.get_meta("weapon_muzzle", Vector3.ZERO))
	var bounds := _bounds(weapon, Transform3D.IDENTITY)
	weapon.position = -bounds.get_center()
	model.scale = Vector3.ONE * (1.12 / maxf(bounds.size.length(), .1))
	model.rotation.y = -.5

func _bounds(node: Node3D, transform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	if node is MeshInstance3D:
		result = transform * node.get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _bounds(child, transform * child.transform)
			if child_bounds.size == Vector3.ZERO: continue
			result = child_bounds if first else result.merge(child_bounds)
			first = false
	return result

func apply_selection() -> void:
	if not visible or apply_button.disabled: return
	var current: String = CUSTOM.selected(session.world.gameplay.customization, weapon_id, slot)
	var ok := false
	if candidate == "none":
		ok = current != "none" and session.world.gameplay.install_attachment(weapon_id, current, false)
	elif CUSTOM.owns(session.world.gameplay.customization, weapon_id, candidate):
		ok = session.world.gameplay.install_attachment(weapon_id, candidate)
	else:
		ok = session.world.gameplay.buy_attachment(weapon_id, candidate)
	if ok: session.save_game()
	select_slot(slot)
	detail.text = ("PERSONALIZAÇÃO APLICADA" if ok else "PERSONALIZAÇÃO INDISPONÍVEL") + "\n" + detail.text

func close(emit_signal := true) -> void:
	hide()
	if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	if emit_signal: closed.emit()

func _process(delta: float) -> void:
	if is_instance_valid(model): model.rotation.y += delta * .22
