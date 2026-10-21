extends RefCounted
## Read-only collection presentation. Never grants rewards or writes the save.
const STYLE = preload("res://ui/GameStyle.gd")
const ICONS := {
	"collectibles":"search", "races":"flag-check", "bests":"stopwatch",
	"ski_races":"ski-jumping", "mountain_clues":"mountain", "money":"cash",
	"weapons":"target", "armor":"shield", "wanted_stars":"stars",
	"best_drift_score":"car", "chop_shop_deliveries":"tool",
}
static var textures := {}

static func stats(session) -> Dictionary:
	var result: Dictionary = session.state.economy.achievement_stats()
	var activities: Dictionary = session.activities.snapshot()
	var best := 0
	for score in activities.get("drift_best",{}).values(): best = maxi(best,int(score))
	result.merge({"races":activities.get("races_finished",0),"bests":activities.get("race_records",0),
		"best_drift_score":best,"armor":session.world.gameplay.armor,"wanted_stars":session.world.gameplay.stars})
	if session.mountain_progression != null: result.merge(session.mountain_progression.stats(),true)
	return result

static func progress(entry: Dictionary, values: Dictionary, completed: bool) -> Vector2:
	var criterion := str(entry.get("check","")).split(">=")
	if criterion.size() != 2: return Vector2(1 if completed else 0,1)
	var goal := maxf(1,float(criterion[1]))
	return Vector2(goal if completed else clampf(float(values.get(criterion[0],0)),0,goal),goal)

static func icon_name(id: String, entry: Dictionary, achievements: bool) -> String:
	if achievements:
		if id == "secret_lead" or id == "map_explorer": return "compass"
		return ICONS.get(str(entry.get("check","")).split(">=")[0],"search")
	if "letter" in id: return "mail"
	if "pack" in id: return "backpack"
	if "journal" in id: return "book"
	if "camera" in id: return "camera"
	return "file-search"

static func texture(path: String) -> Texture2D:
	if not textures.has(path): textures[path] = load(path)
	return textures[path]

static func row(id: String, entry: Dictionary, completed: bool, achievements: bool, values: Dictionary) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Entry_"+id
	outer.set_meta("collection_id",id)
	outer.set_meta("completed",completed)
	outer.add_theme_constant_override("separation",10)
	var line := HBoxContainer.new()
	line.custom_minimum_size.y = 76
	line.add_theme_constant_override("separation",20)
	outer.add_child(line)
	var medal := TextureRect.new()
	medal.texture = texture("res://ui/art/collection_medal.png")
	medal.custom_minimum_size = Vector2(76,76)
	medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal.self_modulate = Color("e8bd70") if completed else Color.WHITE
	line.add_child(medal)
	var icon := TextureRect.new()
	icon.texture = texture("res://ui/icons/tabler/%s.svg" % icon_name(id,entry,achievements))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = STYLE.ACCENT if completed else Color("ced2d6")
	medal.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 22; icon.offset_top = 22; icon.offset_right = -22; icon.offset_bottom = -22
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_stretch_ratio = 1.25
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation",5)
	line.add_child(copy)
	var title := STYLE.label(str(entry.get("name","Achado preservado")),22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(title)
	var objective := STYLE.label(str(entry.get("desc", "")) if achievements else str(entry.get("region","")),17,STYLE.MUTED)
	objective.add_theme_font_override("font",STYLE.FONT)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.visible = not objective.text.is_empty()
	copy.add_child(objective)
	var meter := VBoxContainer.new()
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_theme_constant_override("separation",8)
	line.add_child(meter)
	var state := STYLE.label(("CONCLUÍDO" if achievements else "ENCONTRADO") if completed else ("EM PROGRESSO" if achievements else "NÃO ENCONTRADO"),15,STYLE.ACCENT if completed else STYLE.MUTED)
	meter.add_child(state)
	var amount := progress(entry,values,completed)
	var bar_line := HBoxContainer.new()
	bar_line.add_theme_constant_override("separation",16)
	meter.add_child(bar_line)
	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.max_value = amount.y
	bar.value = amount.x
	bar.show_percentage = false
	bar.custom_minimum_size.y = 9
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for style in ["background","fill"]:
		var box := StyleBoxFlat.new()
		box.bg_color = STYLE.SURFACE if style == "background" else STYLE.ACCENT
		box.set_corner_radius_all(5)
		bar.add_theme_stylebox_override(style,box)
	bar_line.add_child(bar)
	var count := STYLE.label("%s / %s" % [STYLE.amount(int(amount.x)),STYLE.amount(int(amount.y))],16,STYLE.MUTED)
	count.custom_minimum_size.x = 92
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_line.add_child(count)
	var separator := HSeparator.new()
	var rule := StyleBoxFlat.new()
	rule.bg_color = Color(STYLE.LINE,.45)
	rule.content_margin_top = 1
	separator.add_theme_stylebox_override("separator",rule)
	outer.add_child(separator)
	return outer

static func setup(panel: Control, achievements: bool, switch_tab: Callable) -> void:
	panel.custom_minimum_size = Vector2.ZERO
	panel.anchor_left = .06; panel.anchor_right = .94
	panel.anchor_top = .06; panel.anchor_bottom = .94
	panel.offset_left = 0; panel.offset_right = 0; panel.offset_top = 0; panel.offset_bottom = 0
	var box := panel.get_node("Margin/VBox")
	var margin := panel.get_node("Margin")
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,6)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,0)
	var title: Label = box.get_node("AchievementsModalTitle" if achievements else "CollectiblesModalTitle")
	var summary: Label = box.get_node("AchievementsProgressLabel" if achievements else "CollectiblesProgressLabel")
	var scene_owner := title.owner
	box.remove_child(title)
	box.remove_child(summary)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",18)
	box.add_child(header)
	box.move_child(header,0)
	title.text = "MEDALHAS E OBJETIVOS" if achievements else "COLECIONÁVEIS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",30)
	title.add_theme_font_override("font",STYLE.STRONG)
	title.add_theme_color_override("font_color",STYLE.TEXT)
	header.add_child(title)
	title.owner = scene_owner
	for tab in [true,false]:
		var button := Button.new()
		button.name = "AchievementsTab" if tab else "CollectiblesTab"
		button.text = "CONQUISTAS" if tab else "COLECIONÁVEIS"
		button.add_theme_font_override("font",STYLE.STRONG)
		button.add_theme_font_size_override("font_size",17)
		button.set_meta("primary_action",tab == achievements)
		button.pressed.connect(switch_tab.bind(tab))
		header.add_child(button)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary.custom_minimum_size.x = 110
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size",16)
	header.add_child(summary)
	summary.owner = scene_owner
	var scroll: ScrollContainer = box.get_node("Scroll")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	scroll.gui_input.connect(_scroll_input.bind(scroll))

static func finish_style(panel: Control, achievements: bool) -> void:
	var surface := STYLE.panel()
	surface.bg_color = Color(19.0/255,22.0/255,27.0/255,.97)
	panel.add_theme_stylebox_override("panel",surface)
	var back: Button = panel.find_child("BtnCloseAchievements" if achievements else "BtnCloseCollectibles",true,false)
	back.add_theme_stylebox_override("normal",STYLE.button(true))
	for tab in [true,false]:
		var button: Button = panel.find_child("AchievementsTab" if tab else "CollectiblesTab",true,false)
		for state in ["normal","hover","pressed","focus"]:
			var box := StyleBoxFlat.new()
			box.content_margin_left = 14; box.content_margin_right = 14
			box.content_margin_top = 10; box.content_margin_bottom = 10
			box.bg_color = Color(STYLE.ACCENT,.10) if tab == achievements or state != "normal" else Color.TRANSPARENT
			box.border_color = STYLE.ACCENT
			box.border_width_bottom = 2 if tab == achievements or state != "normal" else 0
			button.add_theme_stylebox_override(state,box)

static func _scroll_input(event: InputEvent, scroll: ScrollContainer) -> void:
	var step := 0
	if event.is_action_pressed("ui_down",true): step = 96
	elif event.is_action_pressed("ui_up",true): step = -96
	elif event.is_action_pressed("ui_page_down",true): step = int(scroll.size.y)-24
	elif event.is_action_pressed("ui_page_up",true): step = -int(scroll.size.y)+24
	if step != 0:
		scroll.scroll_vertical += step
		scroll.accept_event()
