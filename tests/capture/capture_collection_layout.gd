extends SceneTree
const VIEW = preload("res://ui/CollectionPresentation.gd")
const ECONOMY = preload("res://systems/economy/Economy.gd")
class ActivityData extends RefCounted:
	func snapshot(): return {"races_finished":0,"race_records":0,"drift_best":{"test":2400}}
class PreviewWorld extends Node3D:
	var session: Dictionary
	var player: Node
	var gameplay: Node
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.get_node("V2Settings").text_language = "pt_BR"
	TranslationServer.set_locale("pt_BR")
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	var world = PreviewWorld.new()
	world.set_meta("menu_preview",true)
	var economy = ECONOMY.new()
	economy.collect("harbor_col_navio_01")
	economy.collect("harbor_col_cobras_01")
	economy.evaluate_achievements(economy.achievement_stats())
	world.session = {"state":{"economy":economy},"activities":ActivityData.new(),"world":{"gameplay":{"armor":0,"stars":0}},"mountain_progression":null}
	root.add_child(world)
	var menu = load("res://ui/PauseMenu.tscn").instantiate()
	menu.world = world
	world.add_child(menu)
	menu.show()
	var folder := "res://artifacts/collections-design-20261021"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var before = economy.snapshot()
	for achievements in [true,false]:
		menu._show_collection(achievements)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("achievements.png" if achievements else "collectibles.png"))
		assert(economy.snapshot() == before)
		var panel = menu.get_node("%AchievementsModal" if achievements else "%CollectiblesModal")
		var scroll = panel.get_node("Margin/VBox/Scroll")
		scroll.grab_focus()
		var event := InputEventKey.new()
		event.keycode = KEY_PAGEDOWN
		event.physical_keycode = KEY_PAGEDOWN
		event.pressed = true
		Input.parse_input_event(event)
		for i in 3: await process_frame
		assert(scroll.scroll_vertical > 0, "Page Down must scroll the focused list")
		var previous: int = scroll.scroll_vertical
		var down := InputEventAction.new()
		down.action = "ui_down"
		down.pressed = true
		Input.parse_input_event(down)
		for i in 3: await process_frame
		assert(scroll.scroll_vertical > previous,"Directional action must scroll the focused list")
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("achievements-bottom.png" if achievements else "collectibles-bottom.png"))
		assert(scroll.scroll_vertical > 0)
		var other = panel.find_child("CollectiblesTab" if achievements else "AchievementsTab",true,false)
		other.pressed.emit()
		assert(not panel.visible)
	menu._close_collection()
	assert(menu.get_node("RootControl/CenterPanel").visible)
	assert(economy.snapshot() == before)
	root.get_node("V2Settings").text_language = "en"
	menu._show_collection(true)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("achievements-en.png"))
	assert(TranslationServer.translate("EM PROGRESSO") == "IN PROGRESS")
	print("COLLECTION_LAYOUT PASS: tabs, scrolling, close, no economy mutation")
	quit()
