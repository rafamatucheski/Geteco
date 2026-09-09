extends SceneTree

## Captura Cinematográfica 3D em Alta Resolução (1920x1080) do Chalé Alpino:
## Renderiza a cabana em 3D REAL volumétrico de múltiplos ângulos:
## 1. Visão Isométrica 3/4 Cutaway Completa (The Sims / Hades / Disco Elysium style)
## 2. Lareira Monumental de Cantaria, Fogão 3D, Chaleira de Cobre, Brasas e Galhadas
## 3. Sala de Estar: Sofá Chesterfield 3D em Couro Conhaque, Mesa de Tronco e Tapete de Urso
## 4. Bar dos Caçadores em Ardósia e Quarto com Cama de Toras e Colcha Patchwork
## 5. Estação Tática do Ranger Silas Vance, Rádio Militar e Suporte de Rifles

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size

	var cabin_3d := preload("res://district/mountain_pass/MountainCabin3D.gd").new()
	root.add_child(cabin_3d)

	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 46.0
	cabin_3d.add_child(camera)

	# Ângulos cinematográficos 3D reais
	var shots: Array[Dictionary] = [
		{
			"id": "cabin_3d_isometric_overview",
			"pos": Vector3(4.8, 8.2, 8.5),
			"look_at": Vector3(0.0, 1.2, -0.6),
			"desc": "Visao Geral Isometrica 3D Cutaway do Chale Alpino"
		},
		{
			"id": "cabin_3d_hearth_fireplace",
			"pos": Vector3(2.8, 2.2, 0.8),
			"look_at": Vector3(-0.4, 1.2, -3.8),
			"desc": "Lareira Monumental 3D, Fogao de Ferro, Chaleira de Cobre, Brasas e Galhadas"
		},
		{
			"id": "cabin_3d_chesterfield_lounge",
			"pos": Vector3(3.6, 2.3, 1.4),
			"look_at": Vector3(-1.4, 0.8, -1.2),
			"desc": "Sofa Chesterfield 3D em Couro Conhaque, Mesa de Tronco e Tapete de Urso"
		},
		{
			"id": "cabin_3d_kitchen_bar_bedroom",
			"pos": Vector3(2.8, 3.8, 4.8),
			"look_at": Vector3(-4.5, 1.0, -0.5),
			"desc": "Bar dos Cacadores com Tampo de Ardosia e Cama de Toras com Colcha Patchwork"
		},
		{
			"id": "cabin_3d_ranger_armory_desk",
			"pos": Vector3(-2.8, 2.8, 2.5),
			"look_at": Vector3(4.5, 1.4, -0.6),
			"desc": "Estacao Tatica de Radio 3D, Silas Vance 3D, Bankers Lamp e Suporte de Rifles"
		}
	]

	var brain_dir := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"

	for shot in shots:
		camera.position = shot["pos"]
		camera.look_at(shot["look_at"], Vector3.UP)
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw

		var img := root.get_texture().get_image()
		var p1 := "%s/mountain_view_%s.png" % [brain_dir, shot["id"]]
		var p2 := "d:/geteco/game/tests/visual/mountain_view_%s.png" % shot["id"]
		img.save_png(p1)
		img.save_png(p2)
		print("CAPTURED 3D: %s" % p1)

	cabin_3d.queue_free()
	for frame in 3:
		await process_frame
	quit(0)
