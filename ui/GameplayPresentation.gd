extends Node
## Coordena apresentaÃ§Ã£o sem transferir lÃ³gica de missÃ£o para o HUD.
const STYLE = preload("res://ui/GameStyle.gd")
const INTERACTION_KEYCAP = preload("res://ui/InteractionKeycap.gd")
var _elapsed := 0.0
var _surfaces: Array[Node] = []
var _labels: Array[Label] = []
var world: Node
var _mountain_styled := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = get_parent()
	await get_tree().process_frame
	if OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args():
		world.add_child(preload("res://ui/TouchControls.gd").new())
	_collect(world)
	for label in world.find_children("*","Label",true,false): _labels.append(label)
	_apply_style()
	get_tree().node_added.connect(_track_label)
	get_node("/root/SettingsManager").interface_changed.connect(_apply_style)

func _track_label(node: Node) -> void:
	if node is Label and world.is_ancestor_of(node):
		_labels.append(node)
		node.tree_exiting.connect(_untrack_label.bind(node), CONNECT_ONE_SHOT)

func _untrack_label(label: Label) -> void:
	_labels.erase(label)

func _collect(node: Node) -> void:
	if node is CanvasLayer:
		_surfaces.append(node)
		return
	for child in node.get_children(): _collect(child)

func _apply_style() -> void:
	_surfaces.clear()
	_collect(world)
	_labels.clear()
	for label in world.find_children("*","Label",true,false): _labels.append(label)
	var factor: float = get_node("/root/SettingsManager").text_scale
	for surface in _surfaces:
		if is_instance_valid(surface): STYLE.apply(surface,factor)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.1: return
	_elapsed = 0
	var player: Node = world.get_node_or_null("Player")
	if player == null: return
	var blocked := get_tree().paused or bool(player.get("is_in_dialogue")) or bool(player.get("is_control_disabled")) or bool(player.get("is_dead"))
	var hud: Node = world.get_node_or_null("HUD")
	if hud != null:
		hud.get_node("RootMargin").visible = not blocked
	var minimap: Node = world.get_node_or_null("Minimap")
	if minimap != null:
		if OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args():
			minimap.panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			minimap.panel.offset_left = -44-minimap.PANEL_SIZE.x
			minimap.panel.offset_right = -44
			minimap.panel.offset_top = 190
			minimap.panel.offset_bottom = 190+minimap.PANEL_SIZE.y
		minimap.panel.visible = not blocked and minimap.map_world_position(player).distance_to(player.global_position)<500
	var arrival: Node = world.get_node_or_null("ArrivalMission")
	var cobra: Node = world.get_node_or_null("CobraCampaign")
	if hud != null and arrival != null and cobra != null:
		var top: Control = hud.get_node("RootMargin/TopRightPanel")
		var y := maxf(200,top.get_global_rect().end.y+12)
		var journal: Control = cobra.get("_journal_button")
		var achievement: Control = hud.get("achievement_panel")
		if is_instance_valid(achievement) and achievement.is_visible_in_tree():
			y = maxf(y,achievement.get_global_rect().end.y+12)
		if is_instance_valid(journal) and journal.is_visible_in_tree():
			journal.position.y = y
			y = journal.get_global_rect().end.y+12
		for card in [arrival.get("_obj_card"),cobra.get("_objective_card")]:
			if is_instance_valid(card):
				card.position = Vector2(get_viewport().get_visible_rect().size.x-24-card.size.x,y)
		var objective_bottom := y
		for card in [arrival.get("_obj_card"),cobra.get("_objective_card")]:
			if is_instance_valid(card) and card.visible: objective_bottom = maxf(objective_bottom,card.position.y+card.size.y+12)
		if minimap != null and (OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args()):
			minimap.panel.position.y = maxf(190,objective_bottom)
		var stream: Node = world.get_node_or_null("ContinuousWorld")
		if stream != null and stream.ready_for_crossing:
			if not _mountain_styled:
				_mountain_styled = true
				_apply_style.call_deferred()
			var cold: Node = stream.mountain.get("cold_hud")
			if cold != null and cold.has_method("set_stack_top"):
				cold.set_stack_top(24.0)
	var tutorials: Node = world.get_node_or_null("GameplayTutorials")
	if tutorials != null:
		tutorials.presenter.visible = not blocked and get_node("/root/SettingsManager").tutorial_hints
		if OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args():
			var box: Control = tutorials.presenter._box
			box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			box.position = Vector2(get_viewport().get_visible_rect().size.x*0.5-190,108)
			box.size.x = 380
	_update_hints()

func _update_hints() -> void:
	var input := get_node("/root/GameInput")
	var tokens := {"E":"interact","T":"trunk","J":"journal","R":"reload","H":"horn","L":"headlights","Q":"weapon_next"}
	for label in _labels:
		if not is_instance_valid(label) or not label.is_visible_in_tree(): continue
		if label.has_meta("interaction_action"):
			label.text = input.hint(String(label.get_meta("interaction_action")))
			INTERACTION_KEYCAP.sync(label, true)
			continue
		var source := label.text
		if source == String(label.get_meta("hint_rendered","")):
			source = String(label.get_meta("hint_source",source))
		var result := source
		if source.strip_edges() == "E": result = input.hint("interact")
		for key in tokens:
			result = result.replace("["+key+"]","["+input.hint(tokens[key])+"]")
		result = result.replace("[ ESPAÇO / E ]","[ "+input.hint("interact")+" ]")
		result = result.replace("[ SPACE / E ]","[ "+input.hint("interact")+" ]")
		result = result.replace("[ E ]","[ "+input.hint("interact")+" ]")
		if input.using_gamepad:
			var cancel_hint: String = input.hint("ui_cancel")
			result = result.replace("[ ESC ]","[ "+cancel_hint+" ]").replace("[Esc]","["+cancel_hint+"]")
		label.set_meta("hint_source",source)
		label.set_meta("hint_rendered",result)
		label.text = result
		INTERACTION_KEYCAP.sync(label, source.strip_edges() == "E")
