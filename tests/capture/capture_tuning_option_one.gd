extends SceneTree
## Comparação visual só de UI; integração no Main e cronometragem têm runners à parte.
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
const OUT := "res://artifacts/tuning-design-20261019/qa/"
var panel: CanvasLayer

func _initialize() -> void: run.call_deferred()

func capture(name: String) -> void:
	for frame in 8: await process_frame
	while not panel._thumbnailer.is_ready(): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+name+".png"))
	print("TUNING_UI_CAPTURE ",name," viewport=",root.size)

func run() -> void:
	TranslationServer.set_locale("pt_BR")
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280,720)
	panel = PANEL.new()
	root.add_child(panel)
	var installed := {"paint":"paint_ocean","finish":"finish_satin","sunroof":"sunroof_glass","spoiler":"spoiler_lip"}
	panel.show_vehicle("desert_coyote",installed,installed.values(),4,12400,{"archetype":"desert_coyote","paint":Color("284d79")})
	await capture("hierarchy-visual-menu-1280")
	panel._open_slot("sunroof")
	await capture("hierarchy-roof-options-1280")
	panel.request_cancel()
	await capture("hierarchy-back-to-visuals-1280")
	panel._open_category("Rodas")
	await capture("hierarchy-wheels-menu-1280")
	panel._select_slot("wheel_model")
	panel._choose_part("wheel_model","wheel_mesh")
	panel._choose_part("wheel_size","wheel_size_sport")
	panel._choose_part("wheels","wheels_bronze")
	panel._select_slot("wheel_model")
	await capture("hierarchy-wheel-model-options-1280")
	panel.close_panel()
	await capture("hierarchy-confirm-exit-1280")
	panel.request_cancel()
	root.size = Vector2i(1672,941)
	panel._showroom.set_auto_rotate(false)
	panel._showroom.reset_view()
	await capture("option-one-wheels-1672")
	root.size = Vector2i(1280,720)
	await capture("option-one-wheels-1280")
	panel._select_slot("sunroof")
	await capture("sunroof-1280")
	panel._select_slot("taillights")
	panel._choose_part("taillights","taillights_amber")
	panel._showroom._yaw = PI
	await capture("taillights-1280")
	panel._select_slot("wheels")
	panel.show_vehicle("desert_coyote",{"wheels":"wheels_bronze"},["wheels_bronze"],4,12400,{"archetype":"desert_coyote","paint":Color("284d79")})
	panel._showroom.reset_view()
	panel._preview({})
	await capture("stock-bronze-1280")
	panel.discard_and_close()
	panel.queue_free()
	for frame in 3: await process_frame
	quit(0)
