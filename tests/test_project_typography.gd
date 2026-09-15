extends SceneTree
const TYPE := preload("res://ui/ProjectTypography.gd")
const EVENT_UI := preload("res://ui/MotorsportUI.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ")+description)
	if not ok: failures.append(description)

func run() -> void:
	var world := Node.new()
	root.add_child(world)
	current_scene = world
	check(ThemeDB.fallback_font == TYPE.REGULAR,"procedural and world text use the project family")
	var label := Label.new()
	world.add_child(label)
	check(label.get_theme_font("font") == TYPE.REGULAR,"new labels inherit Barlow without local overrides")
	var button := Button.new()
	world.add_child(button)
	check(button.get_theme_font("font") == TYPE.MEDIUM,"buttons inherit the Medium weight")
	var rich := RichTextLabel.new()
	world.add_child(rich)
	check(rich.get_theme_font("bold_font") == TYPE.SEMIBOLD and rich.get_theme_font("italics_font") == TYPE.ITALIC,"rich text stays within the same family")
	for character in "açãoÀÉÍÓÚâêôçãõ0123456789":
		check(TYPE.REGULAR.has_char(character.unicode_at(0)),"bundled glyph "+character)
	var card := EVENT_UI.card(world,EVENT_UI.DRIFT)
	card.layer.visible = true
	card.title.text = "Drift · Pátio Westgate"
	card.value.text = "25 s para pontuar"
	card.detail.text = "Emende curvas dentro do pátio.\n$150 por 1.000 pontos"
	card.hint.text = "[Espaço] Freio de mão · solte para retomar"
	preload("res://ui/GameStyle.gd").apply(card.layer,1.25)
	await process_frame
	await process_frame
	var bounds: Rect2 = card.panel.get_global_rect()
	check(not bounds.has_point(root.get_visible_rect().get_center()),"event card leaves driving center clear at 125% text")
	check(root.get_visible_rect().encloses(bounds),"event card remains inside viewport at 125% text")
	check(card.title.get_theme_font("font") == TYPE.MEDIUM,"event hierarchy inherits the project theme")
	var other_owner := Node.new()
	world.add_child(other_owner)
	var invitation := EVENT_UI.card(other_owner,EVENT_UI.RACE)
	EVENT_UI.present(world,card,true,1)
	EVENT_UI.present(other_owner,invitation,true,0)
	check(card.layer.visible and not invitation.layer.visible,"a result and a nearby invitation never overlap")
	EVENT_UI.present(other_owner,invitation,true,2)
	check(not card.layer.visible and invitation.layer.visible,"an active event takes priority over an old result")
	var settings := root.get_node("SettingsManager")
	var previous: bool = settings.reduce_motion
	settings.reduce_motion = true
	check(is_equal_approx(EVENT_UI.pulse(world,0),EVENT_UI.pulse(world,1.2)),"reduced motion disables pulsing")
	settings.reduce_motion = previous
	world.queue_free()
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		var menu = load("res://ui/MainMenu.tscn").instantiate()
		root.add_child(menu)
		current_scene = menu
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/subtle-ui-0910/menu-barlow.png")
		menu.queue_free()
		await process_frame
	print("PROJECT_TYPOGRAPHY failures=",failures)
	quit(0 if failures.is_empty() else 1)
