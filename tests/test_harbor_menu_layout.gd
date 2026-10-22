extends SceneTree
## Navigation visibility and uniform cartographic scale; no save writes.
class PreviewWorld extends Node3D:
	var session: Node
	var player: Node3D
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var world := PreviewWorld.new()
	world.set_meta("menu_preview",true)
	root.add_child(world)
	var menu := preload("res://ui/PauseMenu.tscn").instantiate()
	menu.world = world
	root.add_child(menu)
	menu.visible = true
	for viewport_size: Vector2i in [Vector2i(800,600),Vector2i(1280,720)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		await process_frame
		for name in ["BtnResume","BtnSaveGame","BtnLoadGame","BtnSettings","BtnQuit"]:
			var button: Button = menu.find_child(name,true,false)
			check(button.is_visible_in_tree(),name+" remains available")
			check(button.get_theme_font_size("font_size")==20,name+" uses the shared 20px typography")
			check(Rect2(Vector2.ZERO,viewport_size).encloses(button.get_global_rect()),name+" fits viewport")
	menu.open_settings()
	var settings: Control = menu.settings
	settings._select_tab(0)
	settings._choose_video_group("TELA")
	check(settings._widgets.vsync.is_visible_in_tree(),"display controls are discoverable in Tela")
	check(not settings._widgets.msaa.is_visible_in_tree(),"advanced quality does not crowd display controls")
	settings._choose_video_group("QUALIDADE")
	check(settings._widgets.msaa.is_visible_in_tree(),"antialiasing stays accessible")
	settings._choose_video_group("AVANÇADO")
	check(settings._widgets.glow.is_visible_in_tree(),"effects stay accessible")
	settings._choose_video_group("IDIOMA")
	check(settings._widgets.text_language.is_visible_in_tree(),"language stays accessible")
	settings._select_tab(2)
	settings._choose_control_mode(0)
	check(not settings._pad_diagram.is_visible_in_tree() and settings._controls_list.is_visible_in_tree(),"keyboard remapping is directly accessible")
	settings._choose_control_mode(1)
	check(settings._pad_diagram.is_visible_in_tree(),"gamepad diagram stays available")
	settings.close()
	menu.queue_free()
	world.queue_free()
	# Unequal real-world extents must never cause a different per-region scale.
	var map := preload("res://ui/hud/MapUI.gd").new()
	map._area = Control.new()
	map._area.size = Vector2(1280,600)
	map._bounds = Rect2(-1400,-1300,2400,1800)
	map._base_zoom = .3
	map.atlas.region_bounds = {"harbor":Rect2(-200,0,650,450),"mountain":Rect2(500,-700,450,650),"desert":preload("res://world/desert/DesertLayout.gd").BOUNDS}
	var scales: Array[float] = []
	for id in ["harbor","mountain","desert"]:
		map.focus_region(id)
		scales.append(map._base_zoom*map.target_zoom)
	check(is_equal_approx(scales[0],scales[1]) and is_equal_approx(scales[1],scales[2]),"all region tabs share one pixels-per-metre scale")
	map._area.free()
	map.free()
	await process_frame
	print("HARBOR_MENU_LAYOUT ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
