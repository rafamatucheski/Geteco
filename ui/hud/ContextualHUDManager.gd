extends CanvasLayer
signal layout_changed
## Presentation boundary. Gameplay, saves, inventory and controls retain ownership.
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPH := preload("res://ui/hud/HUDGlyph.gd")
const WANTED := preload("res://ui/hud/WantedPresentation.gd")
var world: Node
var root_control: Control
var player_status: PanelContainer
var money: VBoxContainer
var weapon: VBoxContainer
var interaction_row: PanelContainer
var objective_card: PanelContainer
var feedback_card: PanelContainer
var minimap: Control
var vehicle_name: Label
var backpack: Button
var backpack_hint: Label
var stars_label: RichTextLabel
var search_progress: ProgressBar
## Rádio da central na perseguição (DispatchController.radio_line).
var radio_label: Label
var _wanted_clock := 0.0
var _wanted_phase := "clear"
var speed_label: Label
# Stable public references used by transitions and existing integration tooling.
var weapon_icon: Control
var ammo_label: Label
var health_bar: ProgressBar
var armor_bar: ProgressBar
var money_label: Label
var objective_label: Label
var current_objective: PanelContainer
var current_objective_label: Label
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
var _layout_running := false
var _layout_queued := false
var _center_feed: VBoxContainer
var _speech_caption: Control

func _ready() -> void:
	name="HUD"; layer=50; process_mode=Node.PROCESS_MODE_ALWAYS; process_priority=1000; add_to_group("hud")
	root_control=Control.new(); root_control.name="GameplayHUDRoot"; root_control.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_control.theme=STYLE.create_theme(); add_child(root_control)
	root_margin=root_control
	_center_feed=VBoxContainer.new(); _center_feed.name="CenterFeed"; _center_feed.add_theme_constant_override("separation",8)
	_center_feed.mouse_filter=Control.MOUSE_FILTER_IGNORE; root_control.add_child(_center_feed)
	root_control.add_child(preload("res://ui/hud/PoliceVitalsHUD.gd").new())
	player_status=preload("res://ui/hud/PlayerStatusHUD.gd").new(); root_control.add_child(player_status)
	player_status.rage_requested.connect(func():
		if is_instance_valid(world) and world.gameplay != null: world.gameplay.request_rage()
	)
	health_bar=player_status.health_bar; armor_bar=player_status.armor_bar
	_upper_right=VBoxContainer.new(); _upper_right.add_theme_constant_override("separation",8); root_control.add_child(_upper_right)
	money=preload("res://ui/hud/MoneyHUD.gd").new(); _upper_right.add_child(money); money_label=money.amount
	stars_label=RichTextLabel.new(); stars_label.bbcode_enabled=true; stars_label.fit_content=true; stars_label.scroll_active=false
	stars_label.add_theme_font_override("normal_font",STYLE.FONT); stars_label.add_theme_font_size_override("normal_font_size",13)
	stars_label.add_theme_color_override("default_color",STYLE.ACCENT); stars_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stars_label.add_theme_color_override("font_outline_color",Color("20272b")); stars_label.add_theme_constant_override("outline_size",1)
	_upper_right.add_child(stars_label)
	search_progress=ProgressBar.new(); search_progress.max_value=1.0; search_progress.show_percentage=false; search_progress.custom_minimum_size=Vector2(0,4)
	search_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE; _upper_right.add_child(search_progress); search_progress.hide()
	var search_track := StyleBoxFlat.new(); search_track.bg_color=Color("20272bdd")
	var search_fill := StyleBoxFlat.new(); search_fill.bg_color=STYLE.ACCENT
	search_progress.add_theme_stylebox_override("background",search_track); search_progress.add_theme_stylebox_override("fill",search_fill)
	radio_label=STYLE.label("",13,Color("cfe0ff")); radio_label.name="PoliceRadio"; radio_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	radio_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; radio_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	radio_label.add_theme_color_override("font_outline_color",Color("20272b")); radio_label.add_theme_constant_override("outline_size",1)
	radio_label.add_theme_stylebox_override("normal",STYLE.compact(false,8))
	_center_feed.add_child(radio_label); radio_label.hide()
	top_right_panel=_upper_right
	_lower_right=HBoxContainer.new(); _lower_right.alignment=BoxContainer.ALIGNMENT_END; _lower_right.add_theme_constant_override("separation",10); root_control.add_child(_lower_right)
	weapon=preload("res://ui/hud/WeaponHUD.gd").new(); weapon.size_flags_vertical=Control.SIZE_SHRINK_END; _lower_right.add_child(weapon)
	weapon_icon=weapon.weapon_icon; ammo_label=weapon.ammo_label; combat_panel=weapon.equipped
	var bag_column := VBoxContainer.new(); bag_column.size_flags_vertical=Control.SIZE_SHRINK_END; _lower_right.add_child(bag_column)
	backpack=Button.new(); backpack.name="BackpackButton"; backpack.tooltip_text="Mochila"; backpack.custom_minimum_size=Vector2(36,36); backpack.focus_mode=Control.FOCUS_NONE
	backpack.add_theme_stylebox_override("normal",STYLE.compact(false,10)); bag_column.add_child(backpack)
	var glyph := GLYPH.new("bag"); backpack.add_child(glyph); glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); glyph.offset_left=9; glyph.offset_right=-9; glyph.offset_top=8; glyph.offset_bottom=-8
	backpack.pressed.connect(func(): if _bound: _session.show_inventory())
	backpack_hint=STYLE.label("",11,STYLE.MUTED); backpack_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; bag_column.add_child(backpack_hint)
	minimap=preload("res://ui/v1/HarborMinimap3D.gd").new(); minimap.world=world; root_control.add_child(minimap)
	current_objective=PanelContainer.new(); current_objective.name="CurrentObjective"; current_objective.mouse_filter=Control.MOUSE_FILTER_IGNORE
	current_objective.add_theme_stylebox_override("panel",STYLE.compact(false,10)); root_control.add_child(current_objective)
	current_objective_label=STYLE.label("",13); current_objective_label.custom_minimum_size.x=168
	current_objective_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; current_objective.add_child(current_objective_label)
	current_objective.hide()
	vehicle_name=preload("res://ui/hud/VehicleNameHUD.gd").new(); minimap.add_child(vehicle_name)
	interaction_row=preload("res://ui/hud/InteractionPrompt.gd").new(); root_control.add_child(interaction_row)
	interaction_key=interaction_row.key; interaction_label=interaction_row.caption
	_notifications=VBoxContainer.new(); _notifications.name="Notifications"; _notifications.add_theme_constant_override("separation",8); _center_feed.add_child(_notifications)
	objective_card=preload("res://ui/hud/NotificationUI.gd").new(); objective_card.name="ObjectiveUpdate"; _notifications.add_child(objective_card); objective_label=objective_card.message
	feedback_card=preload("res://ui/hud/NotificationUI.gd").new(); feedback_card.name="Feedback"; _notifications.add_child(feedback_card); notice_label=feedback_card.message
	speed_label=STYLE.label("",16); speed_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; root_control.add_child(speed_label)
	var help := Label.new(); help.name="Help"; help.hide(); add_child(help)
	for node in [player_status,_upper_right,_lower_right,current_objective,vehicle_name,minimap.caption,minimap.weekday_label,interaction_row,_center_feed,_notifications,radio_label,objective_card,feedback_card,speed_label]:
		_watch_layout(node)
	get_viewport().size_changed.connect(_queue_layout); _layout()

func _process(delta: float) -> void:
	if not _bound: _try_bind()
	if not _bound: return
	_status_clock+=delta / maxf(Engine.time_scale, 0.001)
	# Text/state projection is bounded. No UI tree rebuild or styling every frame.
	if _status_clock>=.08:
		var elapsed := _status_clock; _status_clock=0
		_sync_channels(); _sync_status(elapsed); _style_modal_if_needed()

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
	# The drag presents its own instruments and controls while it owns driving.
	var drag_active: bool = _session.desert != null and is_instance_valid(_session.desert.drag) and _session.desert.drag.active
	var wheel_active: bool = _session.equipment_wheel != null and _session.equipment_wheel.active
	root_control.visible=active and not drag_active and not wheel_active
	var caption: Control = _session.get("speech_caption")
	if is_instance_valid(caption) and caption!=_speech_caption:
		_speech_caption=caption; _watch_layout(caption)
	vehicle_name.sync(_driving)
	# Campo de dados da sessão (FullSession.hud_objective), não o texto do Label antigo.
	var text := str(_session.hud_objective)
	if text!=_last_objective:
		_last_objective=text
		current_objective_label.text=text
		current_objective.visible=not text.is_empty()
		current_objective.size=Vector2.ZERO
		_queue_layout()
		# The persistent card already presents the new objective. Do not repeat
		# the same instruction as a second transient panel over the play area.
	var feedback := ""
	if float(_session.notice_time)>0 and not bool(_session.get("speech_active")): feedback=str(_session.notice.text).strip_edges()
	elif float(_driving.status_time)>0: feedback=str(_driving.status).strip_edges()
	if feedback!=_last_notice:
		_last_notice=feedback
		if not feedback.is_empty(): feedback_card.present(feedback)
	# Legenda sem tecla (FullSession.hud_prompt, Driving.prompt_caption); a tecla vem da ação.
	var action_text := str(_session.hud_prompt) if not str(_session.prompt.text).is_empty() else ""
	var action: String = _session.prompt_input_action
	if action_text.is_empty() and float(_driving.status_time)<=0:
		action_text=str(_driving.prompt_caption)
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
	money.update_balance(int(state.economy.balance),state.economy.cheat_infinite_money)
	var thermal: Dictionary=_session.cold.status() if _session.cold!=null else {}
	player_status.update_status(float(gameplay.health),float(gameplay.armor),thermal,delta)
	if is_instance_valid(gameplay.rage): player_status.update_rage(gameplay.rage.status(), _controls.prompt("rage"))
	weapon.update_weapon(state,root_control.visible)
	var stars := clampi(int(gameplay.stars),0,6)
	var phase := String(gameplay.police_case.phase()) if gameplay.get("police_case")!=null else "clear"
	if phase!=_wanted_phase: _wanted_clock=0.0; _wanted_phase=phase
	if not get_tree().paused: _wanted_clock=fposmod(_wanted_clock+delta,10.0)
	var progress: float=gameplay.police_evasion_progress()
	var investigation: float=float(gameplay.police_case.investigation_left) if gameplay.get("police_case")!=null else -1.0
	var wanted_text := WANTED.text_for(stars,phase,progress,_wanted_clock,investigation)
	stars_label.text="[right]"+wanted_text+"[/right]" if not wanted_text.is_empty() else ""
	stars_label.visible=not stars_label.text.is_empty()
	search_progress.visible=stars>0 and phase=="search"
	search_progress.value=progress
	var dispatch: Variant=world.get("dispatch")
	var radio: String=dispatch.radio_line() if dispatch!=null and is_instance_valid(dispatch) and dispatch.has_method("radio_line") else ""
	# A fonte do HUD não tem emoji: o prefixo é texto.
	var radio_text := (tr("Rádio")+" · "+radio) if not radio.is_empty() else ""
	if radio_label.text!=radio_text: radio_label.text=radio_text
	radio_label.visible=not radio_text.is_empty()

func _sync_prompts() -> void:
	backpack_hint.text=_controls.prompt("inventory")
	if _bound: _sync_channels()

func _anchor(node: Control, preset: Control.LayoutPreset, offsets: Rect2) -> void:
	node.set_anchors_and_offsets_preset(preset)
	node.offset_left=offsets.position.x; node.offset_top=offsets.position.y
	node.offset_right=offsets.end.x; node.offset_bottom=offsets.end.y

func _watch_layout(node: Control) -> void:
	node.resized.connect(_queue_layout)
	node.minimum_size_changed.connect(_queue_layout)
	node.visibility_changed.connect(_queue_layout)

func _queue_layout() -> void:
	if _layout_running or _layout_queued or not is_inside_tree(): return
	_layout_queued=true
	get_tree().process_frame.connect(_flush_layout,CONNECT_ONE_SHOT)

func _flush_layout() -> void:
	_layout_queued=false
	_layout()

func attach_station_notice(notice: Label) -> void:
	# Audio retains its text/fade/timer; all radio messages share one layout owner.
	if notice.get_parent()!=null: notice.reparent(_center_feed)
	else: _center_feed.add_child(notice)
	_center_feed.move_child(notice,0)
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	notice.custom_minimum_size=Vector2.ZERO
	notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_watch_layout(notice); _queue_layout()

func attach_activity_notice(notice: Label) -> void:
	if notice.get_parent()!=null: notice.reparent(_center_feed)
	else: _center_feed.add_child(notice)
	_center_feed.move_child(notice,_center_feed.get_child_count()-2)
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	notice.custom_minimum_size=Vector2.ZERO
	notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_override("font",STYLE.FONT)
	notice.add_theme_font_size_override("font_size",14)
	notice.add_theme_constant_override("outline_size",1)
	notice.add_theme_stylebox_override("normal",STYLE.compact(false,8))
	_watch_layout(notice); _queue_layout()

func save_feedback_bottom() -> float:
	return (speed_label.position.y if speed_label.visible else _lower_right.position.y)-12

func save_feedback_top() -> float:
	if OS.has_feature("android") or "--touch-controls" in OS.get_cmdline_user_args():
		return (speed_label.get_rect().end.y if speed_label.visible else _lower_right.get_rect().end.y)+12
	return -1

func save_feedback_width() -> float:
	return minf(264,get_viewport().get_visible_rect().size.x-STYLE.SAFE_MARGIN-_center_feed.get_rect().end.x-12)

func _layout() -> void:
	if not is_instance_valid(root_control) or _layout_running: return
	_layout_running=true
	var view := get_viewport().get_visible_rect().size
	var margin := STYLE.SAFE_MARGIN
	var top := maxf(32,margin)
	_anchor(player_status,Control.PRESET_TOP_LEFT,Rect2(margin,top,160,0))
	_anchor(_upper_right,Control.PRESET_TOP_RIGHT,Rect2(-224-margin,top,224,0))
	var bottom := view.y-margin
	# Non-modal speech owns a full lower row. Raise the lower HUD above it instead
	# of painting the subtitle over navigation, ammunition and interaction hints.
	var caption: Control = _session.get("speech_caption") if _bound else null
	if is_instance_valid(caption) and caption.is_visible_in_tree():
		bottom=minf(bottom,caption.get_global_rect().position.y-12)
	var lower_height := maxf(72,_lower_right.get_combined_minimum_size().y)
	_anchor(_lower_right,Control.PRESET_TOP_LEFT,Rect2(view.x-264-margin,bottom-lower_height,264,lower_height))
	_anchor(minimap,Control.PRESET_TOP_LEFT,Rect2(margin,bottom-minimap.size.y,minimap.size.x,minimap.size.y))
	# The boarding introduction gets its own row while the destination stays visible.
	vehicle_name.position=Vector2(0,-56 if minimap.caption.visible else -40)
	var navigation_gap := 72 if vehicle_name.visible else 40
	_anchor(current_objective,Control.PRESET_TOP_LEFT,Rect2(margin,minimap.position.y-navigation_gap-current_objective.get_combined_minimum_size().y,minimap.size.x,current_objective.get_combined_minimum_size().y))
	_anchor(speed_label,Control.PRESET_TOP_LEFT,Rect2(view.x-220-margin,_lower_right.position.y-38,220,30))
	# Symmetric clearance keeps the radio truly centered while the corner stacks grow.
	var side := maxf(player_status.get_rect().end.x+12,view.x-_upper_right.position.x+12)
	var feed_width := minf(360,view.x-2*side)
	var feed_top := top
	if feed_width<240:
		feed_width=minf(360,view.x-2*margin)
		feed_top=maxf(player_status.get_rect().end.y,_upper_right.get_rect().end.y)+12
	var touch := OS.has_feature("android") or "--touch-controls" in OS.get_cmdline_user_args()
	if touch:
		# Reserve both lower corners for thumbs; keep navigation and ammo readable.
		backpack.get_parent().hide()
		minimap.weekday_label.add_theme_font_size_override("font_size",11)
		minimap.weekday_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		minimap.weekday_label.position.x=minimap.size.x+4
		minimap.weekday_label.size.x=56
		minimap.weather_icon.position=minimap.weekday_label.position+Vector2(0,minimap.weekday_label.get_combined_minimum_size().y+4)
		feed_width=minf(360,view.x-2*(margin+minimap.size.x+68))
		var map_top := maxf(110,player_status.get_rect().end.y+navigation_gap+12)
		_anchor(minimap,Control.PRESET_TOP_LEFT,Rect2(margin,map_top,minimap.size.x,minimap.size.y))
		_anchor(current_objective,Control.PRESET_TOP_LEFT,Rect2(margin,map_top+minimap.size.y+12,minimap.size.x,current_objective.size.y))
		var equipment_width := _lower_right.get_combined_minimum_size().x
		_anchor(_lower_right,Control.PRESET_TOP_RIGHT,Rect2(-equipment_width-margin,maxf(112,_upper_right.get_rect().end.y+12),equipment_width,lower_height))
		_anchor(speed_label,Control.PRESET_TOP_LEFT,Rect2(_lower_right.position.x,_lower_right.get_rect().end.y+8,equipment_width,30))
		var touch_unit := minf(view.x/720.0,view.y/900.0) if view.x<view.y*1.4 else minf(view.x/1280.0,view.y/720.0)
		feed_top=maxf(feed_top,147*touch_unit+12)
	_anchor(_center_feed,Control.PRESET_TOP_LEFT,Rect2((view.x-feed_width)*.5,feed_top,feed_width,0))
	var prompt_left := minimap.position.x+minimap.size.x+102
	var prompt_right := _lower_right.position.x-12
	var prompt_bottom := bottom-4
	if touch:
		prompt_left=view.x*.3
		prompt_right=view.x*.7
		prompt_bottom=minf(view.y-120,bottom-4)
	if prompt_right-prompt_left<160:
		prompt_left=margin; prompt_right=view.x-margin
		prompt_bottom=minf(current_objective.position.y,_lower_right.position.y)-12
	if interaction_row.visible:
		interaction_row.layout_in_rect(Rect2(prompt_left,top,prompt_right-prompt_left,maxf(0,prompt_bottom-top)))
	_layout_modal()
	_layout_running=false
	layout_changed.emit()

func _style_modal_if_needed() -> void:
	if not is_instance_valid(_session.get("panel")) or not _session.panel.visible: return
	var ids := PackedStringArray()
	for child in _session.column.get_children(): ids.append(str(child.get_instance_id()))
	var signature := ",".join(ids)
	if signature==_last_modal_signature: return
	_last_modal_signature=signature
	# FullSession assigns initial focus when opening the menu. A later styling
	# poll must preserve the button the player has already selected.
	STYLE.apply(_session.panel); STYLE.trap_focus.call_deferred(_session.panel, false); _layout_modal()

func _layout_modal() -> void:
	if not _bound or not is_instance_valid(_session.get("panel")): return
	var panel: Control=_session.panel
	var view := get_viewport().get_visible_rect().size
	var preferred: Vector2=panel.get_meta("modal_preferred_size",Vector2(640,480))
	var extent := Vector2(minf(preferred.x,view.x-48),minf(preferred.y,view.y-48))
	panel.custom_minimum_size=extent.round(); panel.size=extent.round(); panel.position=((view-extent)*.5).round()
	if panel.get_meta("modal_dock_right",false): panel.position=Vector2(view.x-extent.x-24,(view.y-extent.y)*.5).round()

func _suppress_invented_scope_overlay() -> void:
	var reticle := get_node_or_null("ScopeReticle")
	if reticle==null: return
	for child in reticle.get_children():
		if child is CanvasItem: child.visible=false
