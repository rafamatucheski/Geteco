extends Control
## Interfaces produtivas V1 da fileira comercial. A operação econômica continua
## pertencendo a GameState/Economy; este adaptador só apresenta o estoque original
## e exige que Dante esteja fisicamente dentro do estabelecimento correspondente.

const STYLE := preload("res://ui/GameStyle.gd")
const OUTFITS := preload("res://data/catalogs/OutfitCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const AMMUNATION := preload("res://runtime/HarborAmmunationCatalog.gd")
const OUTFIT_NAMES := {
	"dante_classic":"Dante clássico", "dante_suit":"Terno", "dante_arctic":"Parka ártica",
	"dante_ski":"Conjunto de ski", "dante_trench":"Sobretudo de lã", "dante_cowboy":"Pistoleiro",
	"dante_madmax":"Sobrevivente", "dante_lumberjack":"Lenhador", "dante_ghillie":"Camuflado",
	"dante_hawaii":"Havaiana", "dante_badboy":"Regata",
}

var session
var active_kind := ""
var selected_outfit := "dante_classic"
var filter := "Todos"
var content: VBoxContainer
var status_label: Label
var wallet_label: Label
var shell_panel: PanelContainer
var preview_actor: CharacterBody3D
var preview_viewport: SubViewport
var ammunation: Control

func configure(owner_session) -> void:
	session = owner_session
	name = "HarborStorefronts"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

func is_open() -> bool:
	return not active_kind.is_empty() and visible

func open_weapons() -> bool:
	if not _can_open("harbor_ammunation"): return false
	active_kind = "weapons"
	for child in get_children(): child.queue_free()
	show()
	ammunation = AMMUNATION.new()
	ammunation.configure(session)
	add_child(ammunation)
	ammunation.close_requested.connect(session.close_menu)
	ammunation.open_catalog()
	status_label = ammunation.feedback
	shell_panel = ammunation.panel
	_finish_open()
	return true

func open_clothing() -> bool:
	if not _can_open("harbor_clothing"): return false
	active_kind = "clothing"
	filter = "Todos"
	selected_outfit = session.state.economy.outfit
	_open_shell("UNION / ROUPAS")
	_build_clothing()
	_finish_open()
	return true

func open_maciota_service() -> bool:
	if not _can_open_maciota(): return false
	active_kind = "maciota"
	_open_shell("MACIOTA · MONALIZA", Vector2(640, 300))
	var car = session.personal_car._car()
	var state_text := "Fora da garagem"
	if is_instance_valid(car):
		state_text = "Condição  %d%%" % roundi(100.0 * car.health / maxf(car.max_health, 1.0))
	content.add_child(_label(state_text, 18, STYLE.TEXT))
	content.add_child(_label("A oficina cuida somente da Monaliza conquistada.", 14, STYLE.MUTED))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	actions.add_child(_button("Reparar · R$ 50", _run_maciota.bind(false)))
	actions.add_child(_button("Recuperar à baia · R$ 50", _run_maciota.bind(true)))
	_finish_open()
	return true

func dismiss() -> void:
	active_kind = ""
	if is_instance_valid(ammunation): ammunation.dismiss()
	if is_instance_valid(preview_viewport): preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ammunation = null
	preview_actor = null
	preview_viewport = null
	hide()
	for child in get_children(): child.queue_free()
	content = null
	status_label = null
	wallet_label = null
	shell_panel = null

func handle_input(event: InputEvent) -> bool:
	return active_kind == "weapons" and is_instance_valid(ammunation) and ammunation.handle_input(event)

func _can_open(place: String) -> bool:
	return session != null and session.ready_for_play and session.state.place_id == place \
		and is_instance_valid(session.room) and not session.world.driving.occupied \
		and session.world.gameplay.health > 0 and session.world.player.global_position.distance_to(session.room.interaction_points.service) < 1.7

func _can_open_maciota() -> bool:
	return session != null and session.ready_for_play and session.state.place_id == "maciota" \
		and is_instance_valid(session.world.maciota_place) and not session.world.driving.occupied \
		and session.world.gameplay.health > 0 and session.world.player.global_position.distance_to(session.world.maciota_place.interaction_points.workbench) < 2.0

func _valid_action(place: String) -> bool:
	if not _can_open(place) or active_kind.is_empty():
		session.close_menu()
		return false
	return true

func _open_shell(title_text: String, shell_size := Vector2(880, 600)) -> void:
	for child in get_children(): child.queue_free()
	show()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.025, 0.032, .82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	shell_panel = PanelContainer.new()
	shell_panel.name = "StorePanel"
	shell_panel.set_anchors_preset(Control.PRESET_CENTER)
	shell_panel.position = -shell_size * .5
	shell_panel.size = shell_size
	shell_panel.add_theme_stylebox_override("panel", STYLE.panel(true))
	add_child(shell_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_"+side, 20)
	shell_panel.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	content.add_child(header)
	var title := _label(title_text, 23, STYLE.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	wallet_label = _label("", 16, STYLE.MUTED)
	header.add_child(wallet_label)
	var close := _button("Fechar · Esc", session.close_menu)
	header.add_child(close)
	status_label = _label("", 14, STYLE.ACCENT)
	status_label.custom_minimum_size.y = 20
	content.add_child(status_label)
	_refresh_wallet()

func _finish_open() -> void:
	session.modal = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	session.dialogue_open = false
	session.world.player.input_locked = true
	if is_instance_valid(session.world.driving.car): session.world.driving.car.input_locked = true
	if active_kind != "weapons": STYLE.apply(self)
	STYLE.trap_focus(self, false)
	_grab_first_focus.call_deferred()

func _grab_first_focus() -> void:
	if not is_inside_tree() or not visible: return
	STYLE.trap_focus(self)

func _build_clothing() -> void:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	content.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	left.add_child(_build_outfit_preview())
	var rotate_hint := _label("Arraste para girar", 12, STYLE.MUTED)
	rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(rotate_hint)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 380
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	var filters := HBoxContainer.new()
	right.add_child(filters)
	filters.add_child(_button("Todas", _set_filter.bind("Todos")))
	filters.add_child(_button("Inverno", _set_filter.bind("Distrito do Gelo")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "OutfitList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id in OUTFITS.ORDER:
		var spec: Dictionary = OUTFITS.OUTFITS[id]
		if filter != "Todos" and spec.district != filter: continue
		var owned: bool = session.state.economy.owns_outfit(id)
		list.add_child(_button(_outfit_name(id) + (" · seu" if owned else " · R$ %d" % int(spec.price)), _select_outfit.bind(id)))
	var detail := VBoxContainer.new()
	detail.name = "OutfitDetail"
	right.add_child(detail)
	_refresh_outfit_detail(detail)

func _build_outfit_preview() -> Control:
	var container := SubViewportContainer.new()
	container.name = "OutfitPreview"
	container.custom_minimum_size = Vector2(340, 470)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.stretch = true
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(340, 470)
	preview_viewport.transparent_bg = true
	preview_viewport.own_world_3d = true
	preview_viewport.msaa_3d = Viewport.MSAA_2X
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(preview_viewport)
	container.gui_input.connect(_preview_input)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	camera.look_at_from_position(Vector3(0, 1.05, 3.5), Vector3(0, .9, 0))
	preview_viewport.add_child(camera)
	for spec in [[Vector3(-30,35,0),1.25,Color("ffe5cc")], [Vector3(-20,-50,0),.65,Color("c6dbed")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_energy = spec[1]
		light.light_color = spec[2]
		preview_viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("8896a3")
	environment.environment.ambient_light_energy = .45
	preview_viewport.add_child(environment)
	preview_actor = ACTOR.new()
	preview_actor.is_player = true
	preview_actor.outfit_id = selected_outfit
	preview_actor.collision_layer = 0
	preview_actor.collision_mask = 0
	preview_actor.rotation.y = PI
	preview_viewport.add_child(preview_actor)
	preview_actor.set_physics_process(false)
	preview_actor.set_process(false)
	return container

func _preview_input(event: InputEvent) -> void:
	if active_kind != "clothing" or not is_instance_valid(preview_actor): return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		preview_actor.rotation.y += event.relative.x * .012

func _set_filter(value: String) -> void:
	if not _valid_action("harbor_clothing"): return
	filter = value
	if filter != "Todos" and OUTFITS.OUTFITS[selected_outfit].district != filter: selected_outfit = "dante_arctic"
	_rebuild_current()

func _select_outfit(id: String) -> void:
	if not _valid_action("harbor_clothing"): return
	selected_outfit = id
	_rebuild_current()

func _refresh_outfit_detail(detail: VBoxContainer) -> void:
	var spec: Dictionary = OUTFITS.OUTFITS[selected_outfit]
	detail.add_child(_label(_outfit_name(selected_outfit), 19, STYLE.TEXT))
	var protection := roundi(_cold_protection(selected_outfit) * 100.0)
	detail.add_child(_label("%d%% menos perda de calor" % protection if protection > 0 else "Sem proteção contra o frio", 14, STYLE.MUTED))
	var owned: bool = session.state.economy.owns_outfit(selected_outfit)
	var equipped: bool = session.state.economy.outfit == selected_outfit
	var action := _button("Equipado" if equipped else ("Vestir" if owned else "Comprar e vestir · R$ %d" % int(spec.price)), _wear_outfit)
	action.disabled = equipped
	detail.add_child(action)

func _cold_protection(id: String) -> float:
	return float({"dante_arctic":.78, "dante_ski":.82, "dante_trench":.62, "dante_lumberjack":.35, "dante_ghillie":.28}.get(id, 0.0))

func _outfit_name(id: String) -> String:
	return str(OUTFIT_NAMES.get(id, OUTFITS.OUTFITS[id].name))

func _wear_outfit() -> void:
	if not _valid_action("harbor_clothing"): return
	var economy = session.state.economy
	if not economy.owns_outfit(selected_outfit):
		var result: Dictionary = economy.purchase("outfit", selected_outfit, session._transaction())
		if not result.ok:
			if result.reason == "insufficient_funds":
				_set_status("Faltam R$ %d." % maxi(0, int(OUTFITS.OUTFITS[selected_outfit].price) - economy.balance))
			else: _set_status(_reason(result.reason))
			return
	if not economy.equip_outfit(selected_outfit): _set_status("Roupa indisponível."); return
	session.apply_outfit()
	session.save_game()
	_set_status("Roupa equipada.")
	_rebuild_current()

func _run_maciota(recover: bool) -> void:
	if not _can_open_maciota():
		session.close_menu()
		return
	session.personal_car._service(recover)

func _rebuild_current() -> void:
	var message := status_label.text if is_instance_valid(status_label) else ""
	if active_kind == "clothing":
		_open_shell("UNION / ROUPAS")
		_build_clothing()
	elif active_kind == "maciota":
		open_maciota_service()
		return
	else: return
	status_label.text = message
	_finish_open()

func _refresh_wallet() -> void:
	if is_instance_valid(wallet_label): wallet_label.text = "Saldo  R$ %d" % session.state.economy.balance

func _set_status(message: String) -> void:
	if is_instance_valid(status_label): status_label.text = message
	_refresh_wallet()

func _reason(reason: String) -> String:
	return {"insufficient_funds":"Dinheiro insuficiente.", "already_owned":"Você já possui este item.",
		"discovery_required":"Item ainda não descoberto.", "reward_only":"Item não vendido nesta loja."}.get(reason, "Operação indisponível.")

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	return button
