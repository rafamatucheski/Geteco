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
var status: Label

const TEXT := Color("eee1bf")
const TEXT_DIM := Color("c9d4cf")
const TEXT_DISABLED := Color("9aa7a2")

## Estilo compartilhado com o catálogo: botões legíveis em todos os estados,
## inclusive desabilitado e aba/opção selecionada.
static func style_button(button: Button) -> void:
	var base := StyleBoxFlat.new()
	base.bg_color = Color("26393a")
	base.border_color = Color("5d7572")
	base.set_border_width_all(1)
	base.set_corner_radius_all(4)
	base.set_content_margin_all(6)
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color("34504f")
	hover.border_color = TEXT
	var pressed := base.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("7c2622")
	pressed.border_color = TEXT
	pressed.set_border_width_all(2)
	var disabled := base.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("1d2929")
	disabled.border_color = Color("3d4d4b")
	button.add_theme_stylebox_override("normal", base)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", TEXT_DIM)
	for key in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]: button.add_theme_color_override(key, TEXT)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)

## Fundo claro atrás da prévia 3D transparente: armas escuras destacam sem
## custo de renderização adicional.
static func stage_style() -> StyleBoxFlat:
	var stage := StyleBoxFlat.new()
	stage.bg_color = Color("6f8580")
	stage.border_color = Color("93a8a2")
	stage.set_border_width_all(1)
	stage.set_corner_radius_all(4)
	return stage

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
	title.add_theme_color_override("font_color", TEXT)
	box.add_child(title)
	wallet = Label.new()
	wallet.add_theme_color_override("font_color", TEXT_DIM)
	box.add_child(wallet)
	slots = HBoxContainer.new()
	box.add_child(slots)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var view := SubViewportContainer.new()
	view.custom_minimum_size = Vector2(440, 300)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.stretch = true
	var stage := PanelContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", stage_style())
	stage.add_child(view)
	body.add_child(stage)
	viewport = SubViewport.new()
	viewport.size = Vector2i(440, 300)
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
	# Lista rolável: acabamentos e peças por arma passam de seis opções.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	options = VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(options)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.y = 54
	detail.add_theme_color_override("font_color", TEXT_DIM)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 17)
	status.add_theme_color_override("font_color", TEXT)
	box.add_child(status)
	box.add_child(detail)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	apply_button = Button.new()
	apply_button.custom_minimum_size.y = 40
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(apply_selection)
	style_button(apply_button)
	actions.add_child(apply_button)
	var back := Button.new()
	back.text = "VOLTAR [ESC]"
	back.pressed.connect(close)
	style_button(back)
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
		button.text = CUSTOM.slot_label(id, category)
		button.add_theme_font_size_override("font_size", 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_slot.bind(category))
		button.toggle_mode = true
		style_button(button)
		button.set_meta("slot", category)
		slots.add_child(button)
	if available.is_empty(): return
	show()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	select_slot(slot if slot in available else available[0])
	# Teclado/controle começam na opção instalada, não fora do painel.
	for button in options.get_children():
		if button.button_pressed: button.grab_focus()

func select_slot(value: String) -> void:
	slot = value
	for button in slots.get_children(): button.set_pressed_no_signal(button.get_meta("slot") == slot)
	for child in options.get_children(): child.free()
	var current: String = CUSTOM.selected(session.world.gameplay.customization, weapon_id, slot)
	_option("none", "ORIGINAL / SEM ACESSÓRIO" + (" • INSTALADO" if current == "none" else ""))
	for part in CUSTOM.PARTS:
		if CUSTOM.PARTS[part].slot == slot and CUSTOM.supports(weapon_id, part):
			var owned := CUSTOM.owns(session.world.gameplay.customization, weapon_id, part)
			var tag := " • INSTALADO" if part == current else (" • ADQUIRIDO" if owned else " • $%d" % CUSTOM.PARTS[part].price)
			var effect := CUSTOM.effect_summary(part)
			_option(part, str(CUSTOM.PARTS[part].label) + tag + ("\n" + effect if not effect.is_empty() else ""))
	select_candidate(CUSTOM.selected(session.world.gameplay.customization, weapon_id, slot))

func _option(id: String, words: String) -> void:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(select_candidate.bind(id))
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	style_button(button)
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
	var price := 0 if part == "none" or CUSTOM.owns(session.world.gameplay.customization, weapon_id, part) else int(CUSTOM.PARTS[part].price)
	wallet.text = "SALDO: $%d" % session.state.economy.balance
	detail.text = compare_stats(weapon_id, session.world.gameplay.customization, preview_state)
	if part != "none" and CUSTOM.PARTS[part].has("note"): detail.text += "\n" + str(CUSTOM.PARTS[part].note)
	var current: String = CUSTOM.selected(session.world.gameplay.customization, weapon_id, slot)
	var same := part == current
	var short: bool = session.state.economy.balance < price
	var owned: bool = part == "none" or CUSTOM.owns(session.world.gameplay.customization, weapon_id, part)
	status.text = candidate_status(part, current, owned, price, short)
	if same: apply_button.text = "JÁ INSTALADO"
	elif part == "none": apply_button.text = "REMOVER " + str(CUSTOM.PARTS[current].label).to_upper()
	elif owned: apply_button.text = "INSTALAR (JÁ ADQUIRIDO)"
	elif short: apply_button.text = "SALDO INSUFICIENTE • $%d" % price
	else: apply_button.text = "COMPRAR E INSTALAR • $%d" % price
	apply_button.disabled = same or short

## "Dano 16 → 21 ▲" para cada número do combate: atual x prévia.
static func compare_stats(id: String, current: Dictionary, preview: Dictionary) -> String:
	var before := CUSTOM.stats(id, current)
	var after := CUSTOM.stats(id, preview)
	var cells: Array[String] = []
	for i in after.size():
		var row: Array = after[i]
		var old: Array = before[i] if i < before.size() and before[i][0] == row[0] else row
		var cell := "%s %s" % [row[0], row[2]]
		if not is_equal_approx(float(old[1]), float(row[1])):
			var better: bool = (float(row[1]) > float(old[1])) == bool(row[3])
			cell = "%s %s → %s %s" % [row[0], old[2], row[2], "▲" if better else "▼"]
		cells.append(cell)
	return "  •  ".join(cells)

func part_name(id: String) -> String:
	return "Original / sem acessório" if id == "none" else str(CUSTOM.PARTS[id].label)

## Separa o que está instalado agora do que está só em prévia.
func candidate_status(part: String, current: String, owned: bool, price: int, short: bool) -> String:
	var line := "Prévia: %s" % part_name(part)
	if part == current: return line + " — instalado agora"
	line += " • Instalado agora: %s" % part_name(current)
	if owned: return line + " • sem custo"
	if short: return line + " • faltam $%d" % (price - int(session.state.economy.balance))
	return line + " • custo $%d" % price

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
	status.text = ("PERSONALIZAÇÃO APLICADA — " if ok else "PERSONALIZAÇÃO INDISPONÍVEL — ") + status.text

func close(emit_signal := true) -> void:
	hide()
	if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	if emit_signal: closed.emit()

func _process(delta: float) -> void:
	if is_instance_valid(model): model.rotation.y += delta * .22
