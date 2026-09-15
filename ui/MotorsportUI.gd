extends RefCounted
const DRIFT := Color("e8b77d")
const RACE := Color("7acbd3")
const SKI := Color("8fd7ee")

static func card(owner: Node, accent: Color) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = 26
	layer.visible = false
	owner.add_child(layer)
	layer.add_to_group("motorsport_card")
	var panel := PanelContainer.new()
	panel.set_meta("preserve_panel_style", true)
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -338
	panel.offset_right = -28
	panel.offset_top = -154
	panel.offset_bottom = -154
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.055,0.075,0.88)
	style.border_color = Color(accent,0.55)
	style.border_width_left = 1
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var result := {"layer": layer, "panel": panel}
	for entry in [["title",14], ["value",24], ["detail",15], ["hint",14]]:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.custom_minimum_size.x = 274 if entry[0] != "title" else 258
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if entry[0] == "title": label.theme_type_variation = &"EventTitle"
		elif entry[0] == "value": label.theme_type_variation = &"EventValue"
		label.add_theme_font_size_override("font_size",entry[1])
		label.add_theme_color_override("font_color",accent if entry[0] == "title" else Color("d5dee4") if entry[0] == "value" else Color("a9b8c2"))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if entry[0] == "title":
			var header := HBoxContainer.new()
			header.add_theme_constant_override("separation",8)
			box.add_child(header)
			var led := ColorRect.new()
			led.color = accent
			led.custom_minimum_size = Vector2(4,4)
			led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			led.mouse_filter = Control.MOUSE_FILTER_IGNORE
			header.add_child(led)
			header.add_child(label)
			result["led"] = led
		else: box.add_child(label)
		result[entry[0]] = label
	return result

static func pulse(owner: Node, clock: float) -> float:
	var settings := owner.get_node_or_null("/root/SettingsManager")
	if settings and settings.reduce_motion: return 0.75
	return 0.48 + (sin(clock * TAU / 2.4) * 0.5 + 0.5) * 0.37

static func animate(owner: Node, card_data: Dictionary, clock: float) -> void:
	card_data.led.modulate.a = pulse(owner,clock)
	card_data.panel.offset_top = -154 - card_data.panel.get_combined_minimum_size().y
	card_data.panel.offset_bottom = -154

static func present(owner: Node, card_data: Dictionary, visible: bool, priority := 0) -> void:
	var layer: CanvasLayer = card_data.layer
	layer.visible = visible and available(owner)
	layer.set_meta("event_priority",priority)
	if not layer.visible: return
	for other in owner.get_tree().get_nodes_in_group("motorsport_card"):
		if other == layer or not other.visible: continue
		if int(other.get_meta("event_priority",0)) > priority:
			layer.visible = false
			return
		other.visible = false

static func beacon(owner: CanvasItem, at: Vector2, accent: Color, clock: float, drift := false) -> void:
	var intensity := pulse(owner,clock)
	owner.draw_circle(at,14,Color(accent,0.045*intensity))
	var color := Color(accent,intensity)
	if drift:
		for x in [-3.5,3.5]: owner.draw_arc(at+Vector2(x,0),5,-1.4,1.7,12,color,1.4,true)
	else:
		owner.draw_line(at+Vector2(-5,7),at+Vector2(-5,-7),color,1.4,true)
		for y in 2:
			for x in 3:
				if (x+y)%2 == 0: owner.draw_rect(Rect2(at+Vector2(-3+x*3,-7+y*3),Vector2(3,3)),color)
	# Short brackets, no permanent circle or opaque patch on the pavement.
	for side in [-1,1]:
		owner.draw_line(at+Vector2(side*13,-5),at+Vector2(side*13,5),Color(accent,intensity*0.3),1,true)

static func available(owner: Node) -> bool:
	var player := owner.get_tree().get_first_node_in_group("player")
	if player and (player.get("is_dead") == true or player.get("is_in_dialogue") == true or player.get("is_control_disabled") == true): return false
	for event in owner.get_tree().get_nodes_in_group("active_motorsport"):
		if event != owner: return false
	return true

static func driver(owner: Node) -> Node2D:
	for car in owner.get_tree().get_nodes_in_group("vehicle"):
		if car.get("is_driven_by_player") == true and not car.has_meta("vehicle_boarding"): return car
	return null

static func key(owner: Node, action: String) -> String:
	return owner.get_node("/root/GameInput").hint(action)

static func cue(owner: Node, finish := false) -> void:
	preload("res://audio/rewards/RewardAudioBank.gd").play(owner, "complete" if finish else "mission_start", -2.0)

static func checkpoint(owner: Node) -> void:
	preload("res://audio/rewards/RewardAudioBank.gd").play(owner, "checkpoint", -2.0)

static func countdown(owner: Node, go: bool) -> void:
	preload("res://audio/rewards/RewardAudioBank.gd").play(owner, "checkpoint" if go else "countdown", -3.0)

static func sign_at(owner: Node2D, at: Vector2, text: String, accent: Color) -> void:
	var label := Label.new()
	label.position = at + Vector2(-28,-38)
	label.size = Vector2(56,24)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",13)
	label.add_theme_color_override("font_color",accent)
	label.add_theme_color_override("font_outline_color",Color("101c29"))
	label.add_theme_constant_override("outline_size",1)
	owner.add_child(label)
