extends Node
## Coordena apresentaÃ§Ã£o sem transferir lÃ³gica de missÃ£o para o HUD.
const STYLE = preload("res://ui/GameStyle.gd")
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
	get_node("/root/SettingsManager").interface_changed.connect(_apply_style)

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
			minimap.panel.offset_left = -260
			minimap.panel.offset_right = -44
			minimap.panel.offset_top = 190
			minimap.panel.offset_bottom = 392
		minimap.panel.visible = not blocked and minimap.map_world_position(player).distance_to(player.global_position)<500
	var arrival: Node = world.get_node_or_null("ArrivalMission")
	var cobra: Node = world.get_node_or_null("CobraCampaign")
	if hud != null and arrival != null and cobra != null:
		var top: Control = hud.get_node("RootMargin/TopLeftPanel")
		var y := maxf(150,top.get_global_rect().end.y+12)
		for card in [arrival.get("_obj_card"),cobra.get("_objective_card")]:
			if is_instance_valid(card): card.position.y = y
		var objective_bottom := y
		for card in [arrival.get("_obj_card"),cobra.get("_objective_card")]:
			if is_instance_valid(card) and card.visible: objective_bottom = maxf(objective_bottom,card.position.y+card.size.y+12)
		var stream: Node = world.get_node_or_null("ContinuousWorld")
		if stream != null and stream.ready_for_crossing:
			if not _mountain_styled:
				_mountain_styled = true
				_apply_style.call_deferred()
			var cold: Node = stream.mountain.get("cold_hud")
			if cold != null and cold.has_method("set_stack_top"): cold.set_stack_top(objective_bottom)
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
		if input.using_gamepad: result = result.replace("[ ESC ]","[ B ]").replace("[Esc]","[B]")
		label.set_meta("hint_source",source)
		label.set_meta("hint_rendered",result)
		label.text = result
