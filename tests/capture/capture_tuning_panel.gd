extends SceneTree
## Captura a tela de tuning renderizada (precisa de render real, sem --headless).
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
const OUT := "res://evidence/tuning-panel/"

func _initialize() -> void: run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT+name+".png"))
	print("CAPTURE ",name," ",image.get_size())

func run() -> void:
	root.size = Vector2i(1280,720)
	var bg := ColorRect.new()
	bg.color = Color("6b7a85")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var panel := PANEL.new()
	root.add_child(panel)
	panel.show_vehicle("porto_rosso",{"engine":"street_cam","turbo":"turbo_small"},["street_cam","turbo_small","ecu_1"],4,12400,{"archetype":"porto_rosso","paint":Color("e01824")})
	await _shot("1_motor_estoque")
	panel._select_slot("turbo")
	panel._preview({"slot":"turbo","id":"turbo_mid"})
	await _shot("2_turbo_previa")
	panel._select_slot("ecu")
	panel._preview({"slot":"ecu","id":"ecu_3"})
	await _shot("3_ecu_bloqueada")
	panel.show_vehicle("sedan_classic",{"neon":"neon_magenta"},["neon_magenta"],1,800,{"archetype":"sedan_classic","paint":Color("284d79")})
	panel._select_slot("neon")
	await _shot("4_sedan_neon")
	quit(0)
