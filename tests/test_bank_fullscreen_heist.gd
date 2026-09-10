extends "res://tests/test_bank_heist_flow.gd"
## Mantém as evidências anteriores e registra o assalto com a câmera de gameplay.
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var folder := "res://docs/measurements/bank-fullscreen-0910/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"heist_"+label+".png")
