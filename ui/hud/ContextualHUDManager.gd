extends CanvasLayer
## Presentation boundary. Gameplay, saves, inventory and controls retain ownership.
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPH := preload("res://ui/hud/HUDGlyph.gd")
var world: Node
var root_control: Control
var player_status: PanelContainer
var money: VBoxContainer
var weapon: VBoxContainer
var interaction_row: PanelContainer
var objective_card: PanelContainer
var notification: PanelContainer
var minimap: Control
var backpack: Button
var backpack_hint: Label
var stars_label: Label
var speed_label: Label
# Stable public references used by transitions and existing integration tooling.
var weapon_icon: Control
var ammo_label: Label
var health_bar: ProgressBar
var armor_bar: ProgressBar
var money_label: Label
var objective_label: Label
var interaction_key: Label
var interaction_label: Label
var notice_label: Label
var combat_panel: PanelContainer
var top_right_panel: Control
var root_margin: Control
var _session: Node
var _driving: Node
var _controls: Node
var _bound := false
var _status_clock := 0.0
var _last_objective := ""
var _last_notice := ""
var _last_modal_signature := ""
var _legacy_sources: Array[Node]=[]
var _lower_right: HBoxContainer
var _upper_right: VBoxContainer
var _notifications: VBoxContainer

func _ready() -> void:
	name="HUD"; layer=50; process_mode=Node.PROCESS_MODE_ALWAYS; process_priority=1000; add_to_group("hud")
	root_control=Control.new(); root_control.name="GameplayHUDRoot"; root_control.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_control.theme=STYLE.create_theme(); add_child(root_control)
	root_margin=root_control
	player_status=preload("res://ui/hud/PlayerStatusHUD.gd").new(); root_control.add_child(player_status)
	health_bar=player_status.health_bar; armor_bar=player_status.armor_bar
	_upper_right=VBoxContainer.new(); _upper_right.add_theme_constant_override("separation",8); root_control.add_child(_upper_right)
	money=preload("res://ui/hud/MoneyHUD.gd").new(); _upper_right.add_child(money); money_label=money.amount
	stars_label=STYLE.label("",15,STYLE.ACCENT); stars_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; _upper_right.add_child(stars_label)
	top_right_panel=_upper_right
	_lower_right=HBoxContainer.new(); _lower_right.alignment=BoxContainer.ALIGNMENT_END; _lower_right.add_theme_constant_override("separation",10); root_control.add_child(_lower_right)
	weapon=preload("res://ui/hud/WeaponHUD.gd").new(); weapon.size_flags_vertical=Control.SIZE_SHRINK_END; _lower_right.add_child(weapon)
	weapon_icon=weapon.weapon_icon; ammo_label=weapon.ammo_label; combat_panel=weapon.equipped
	var bag_column := VBoxContainer.new(); bag_column.size_flags_vertical=Control.SIZE_SHRINK_END; _lower_right.add_child(bag_column)
	backpack=Button.new(); backpack.name="BackpackButton"; backpack.tooltip_text="Mochila"; backpack.custom_minimum_size=Vector2(44,44); backpack.focus_mode=Control.FOCUS_NONE
	backpack.add_theme_stylebox_override("normal",STYLE.compact(false,10)); bag_column.add_child(backpack)
	var glyph := GLYPH.new("bag"); backpack.add_child(glyph); glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); glyph.offset_left=11; glyph.offset_right=-11; glyph.offset_top=9; glyph.offset_bottom=-9
	backpack.pressed.connect(func(): if _bound: _session.show_inventory())
	backpack_hint=STYLE.label("",12,STYLE.MUTED); backpack_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; bag_column.add_child(backpack_hint)
	minimap=preload("res://ui/v1/HarborMinimap3D.gd").new(); minimap.world=world; root_control.add_child(minimap)
	interaction_row=preload("res://ui/hud/InteractionPrompt.gd").new(); root_control.add_child(interaction_row)
	interaction_key=interaction_row.key; interaction_label=interaction_row.caption
	_notifications=VBoxContainer.new(); _notifications.add_theme_constant_override("separation",8); root_control.add_child(_notifications)
	objective_card=preload("res://ui/hud/NotificationUI.gd").new(); objective_card.name="ObjectiveUpdate"; _notifications.add_child(objective_card); objective_label=objective_card.message
	notification=preload("res://ui/hud/NotificationUI.gd").new(); notification.name="Feedback"; _notifications.add_child(notification); notice_label=notification.message
	speed_label=STYLE.label("",20); speed_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; root_control.add_child(speed_label)
	var help := Label.new(); help.name="Help"; help.hide(); add_child(help)
	get_viewport().size_changed.connect(_layout); _layout()

func _process(delta: float) -> void:
	if not _bound: _try_bind()
	if not _bound: return
	_status_clock+=delta
	# Text/state projection is bounded. No UI tree rebuild or styling every frame.
	if _status_clock>=.08:
		var elapsed := _status_clock; _status_clock=0
		_sync_channels(); _sync_status(elapsed); _style_modal_if_needed()
	if interaction_row.visible:
		interaction_row.follow_actor(world.player,world.camera,get_viewport().get_visible_rect().size)

func _try_bind() -> void:
	if not is_instance_valid(world): return
	_session=world.get("session"); _driving=world.get("driving"); _controls=get_node_or_null("/root/GameInput")
	if not is_instance_valid(_session) or not is_instance_valid(_driving) or _session.get("state")==null or _session.get("stats")==null: return
	for property in ["stats","objective","prompt","notice","thermal_status"]:
		var source: Node=_session.get(property)
		if is_instance_valid(source): _legacy_sources.append(source)
	for property in ["prompt","speed_label"]:
		var source: Node=_driving.get(property)
		if is_instance_valid(source): _legacy_sources.append(source)
	_legacy_sources.append(get_node("Help")); _bound=true
	_controls.device_changed.connect(_sync_prompts); _controls.bindings_changed.connect(_sync_prompts)
	_sync_prompts(); refresh_from_state()

func refresh_from_state() -> void:
	if not _bound: _try_bind()
	if not _bound: return
	_sync_channels(); _sync_status(0); _layout(); _style_modal_if_needed()

func _sync_channels() -> void:
	for source in _legacy_sources:
		if is_instance_valid(source): source.hide()
	var active := not bool(_session.modal) and not get_tree().paused and not bool(_session.rescue_pending) and not bool(_session.arrest_pending)
	root_control.visible=active
	var text := str(_session.objective.text).strip_edges()
	if text in ["J  Missões · M  Mapa","J Missions · M Map"]: text=""
	if text!=_last_objective:
		_last_objective=text
		if not text.is_empty(): objective_card.present(text,"NOVO OBJETIVO")
	var feedback := ""
	if float(_session.notice_time)>0: feedback=str(_session.notice.text).strip_edges()
	elif float(_driving.status_time)>0: feedback=str(_driving.status).strip_edges()
	if feedback!=_last_notice:
		_last_notice=feedback
		if not feedback.is_empty(): notification.present(feedback)
	var action_text := str(_session.prompt.text).strip_edges()
	var action := "interact"
	if action_text.is_empty() and float(_driving.status_time)<=0:
		action_text=str(_driving.prompt.text).strip_edges()
		action="exit_vehicle" if bool(_driving.occupied) else "vehicle_interact"
	if bool(world.player.input_locked): action_text=""
	interaction_row.update_prompt(action_text,action,_controls)
	speed_label.text=str(_driving.speed_label.text).strip_edges()
	speed_label.visible=bool(_driving.occupied) and not speed_label.text.is_empty()
	backpack.disabled=bool(_driving.occupied) or bool(world.player.input_locked)
	_suppress_invented_scope_overlay()

func _sync_status(delta: float) -> void:
	var state = _session.state
	var gameplay = world.gameplay
	money.update_balance(int(state.economy.balance))
	var thermal: Dictionary=_session.cold.status() if _session.cold!=null else {}
	player_status.update_status(float(gameplay.health),float(gameplay.armor),thermal,delta)
	weapon.update_weapon(state,root_control.visible)
	var stars := clampi(int(gameplay.stars),0,6)
	stars_label.text="★".repeat(stars)
	var phase := String(gameplay.police_case.phase()) if gameplay.get("police_case")!=null else "clear"
	if phase=="search": stars_label.text+="  BUSCA"
	elif phase=="surrender": stars_label.text="RENDENDO-SE"
	elif stars==0 and phase=="investigation": stars_label.text="INVESTIGAÇÃO"
	stars_label.visible=not stars_label.text.is_empty()

func _sync_prompts() -> void:
	backpack_hint.text=_controls.prompt("inventory")
	if _bound: _sync_channels()

func _anchor(node: Control, preset: Control.LayoutPreset, offsets: Rect2) -> void:
	node.set_anchors_and_offsets_preset(preset)
	node.offset_left=offsets.position.x; node.offset_top=offsets.position.y
	node.offset_right=offsets.end.x; node.offset_bottom=offsets.end.y

func _layout() -> void:
	if not is_instance_valid(root_control): return
	var view := get_viewport().get_visible_rect().size
	var margin := STYLE.SAFE_MARGIN
	_anchor(player_status,Control.PRESET_TOP_LEFT,Rect2(margin,margin,172,0))
	_anchor(_upper_right,Control.PRESET_TOP_RIGHT,Rect2(-224-margin,margin,224,0))
	_anchor(_lower_right,Control.PRESET_BOTTOM_RIGHT,Rect2(-264-margin,-margin-112,264,112))
	_anchor(minimap,Control.PRESET_BOTTOM_LEFT,Rect2(margin,-margin-minimap.size.y,minimap.size.x,minimap.size.y))
	_anchor(_notifications,Control.PRESET_TOP_LEFT,Rect2(margin,122,minf(320,view.x-48),0))
	_anchor(speed_label,Control.PRESET_BOTTOM_RIGHT,Rect2(-220-margin,-margin-148,220,30))
	_layout_modal()

func _style_modal_if_needed() -> void:
	if not is_instance_valid(_session.get("panel")) or not _session.panel.visible: return
	var ids := PackedStringArray()
	for child in _session.column.get_children(): ids.append(str(child.get_instance_id()))
	var signature := ",".join(ids)
	if signature==_last_modal_signature: return
	_last_modal_signature=signature
	STYLE.apply(_session.panel); STYLE.trap_focus.call_deferred(_session.panel); _layout_modal()

func _layout_modal() -> void:
	if not _bound or not is_instance_valid(_session.get("panel")): return
	var panel: Control=_session.panel
	var view := get_viewport().get_visible_rect().size
	var preferred: Vector2=panel.get_meta("modal_preferred_size",Vector2(640,480))
	var extent := Vector2(minf(preferred.x,view.x-48),minf(preferred.y,view.y-48))
	panel.custom_minimum_size=extent.round(); panel.size=extent.round(); panel.position=((view-extent)*.5).round()

func _suppress_invented_scope_overlay() -> void:
	var reticle := get_node_or_null("ScopeReticle")
	if reticle==null: return
	for child in reticle.get_children():
		if child is CanvasItem: child.visible=false
