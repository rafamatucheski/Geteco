extends SceneTree

## Captura Visual em Alta Resolucao do MountainPass (1920x1080)
## Renderiza 8 angulos cinematograficos reais do jogo para avaliacao na tela:
## 1. Visao Geral Panoramica Ampla
## 2. Ponte do Porto, SUV 3D e Tunel Cutaway
## 3. Vale da Madeireira e Lago de Corredeiras
## 4. Vale Leste dos Chales Alpinos e Estradinha de Terra
## 5. Loja Ammu-Nation da Montanha, Estacionamento e Estande de Tiro
## 6. Subida em Curvas Fechadas (Hairpins) e Mirante
## 7. Cume Polar, Base Militar dos Lobos de Gelo e Heliponto
## 8. Interior Rustico do Chale com Lareira de Pedra

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	
	var scene := load("res://world/mountain_pass/MountainPass.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	
	for frame in 18:
		await process_frame

	var camera := Camera2D.new()
	camera.name = "ShowcaseCamera"
	scene.add_child(camera)
	camera.make_current()

	var cabin: Node2D = null
	var interior_mgr = scene.get_node_or_null("MountainInteriorManager")
	if interior_mgr:
		cabin = interior_mgr.get_node_or_null("MountainInteriorSpaces/MountainCabinInterior")
		if cabin:
			if cabin.has_method("set_npc_rendering_active"):
				cabin.set_npc_rendering_active(true)
			for station in [cabin.get_node_or_null("LegendaryRifleStation"), cabin.get_node_or_null("HuntingKnifeStation")]:
				if station:
					var card = station.get_node_or_null("InspectionCard")
					if card:
						card.visible = true

	var shots: Array[Dictionary] = [
		{
			"id": "overview",
			"pos": Vector2(6500, -800),
			"zoom": 0.24,
			"desc": "Visao Panoramica Geral da Serra Expandida com Chales e Ammu-Nation"
		},
		{
			"id": "bridge_tunnel_suv",
			"pos": Vector2(4000, 400),
			"zoom": 0.85,
			"desc": "Ponte do Porto, Carro 3D Summit SUV e Entrada do Tunel"
		},
		{
			"id": "sawmill_lake",
			"pos": Vector2(6550, 350),
			"zoom": 0.75,
			"desc": "Madeireira, Lago com Corredeiras e Inicio das Estradas de Terra"
		},
		{
			"id": "chalets_east_vale",
			"pos": Vector2(7800, 560),
			"zoom": 0.68,
			"desc": "Vale Leste dos Chales Alpinos, Estradinha de Terra e Picape"
		},
		{
			"id": "chalet_entrance_button",
			"pos": Vector2(7350, 685),
			"zoom": 1.95,
			"desc": "Entrada do Chale Alpino: Botao '[E] APERTE E PARA ENTRAR', Lanterna e Tapete"
		},
		{
			"id": "chalet_pickup_3d",
			"pos": Vector2(8450, 490),
			"zoom": 1.25,
			"desc": "Picape Ranch Single 3D 4x4 Estacionada no Chale Alpino"
		},
		{
			"id": "ammunation_outpost",
			"pos": Vector2(7750, -220),
			"zoom": 0.78,
			"desc": "Loja Ammu-Nation da Montanha, Estacionamento e Estande de Tiro"
		},
		{
			"id": "hairpins_lookout",
			"pos": Vector2(6800, -1000),
			"zoom": 0.72,
			"desc": "Subida em Curvas Fechadas, Guard-Rails, Chevrons e Mirante"
		},
		{
			"id": "secret_lake_overview",
			"pos": Vector2(5520, -1080),
			"zoom": 0.82,
			"desc": "Lago Secreto dos Contrabandistas com Cascata e Trilha Off-Road"
		},
		{
			"id": "secret_lake_campsite_jeep",
			"pos": Vector2(5620, -960),
			"zoom": 1.65,
			"desc": "Acampamento dos Contrabandistas e Jeepzao de Gelo 3D Pronto para Roubar"
		},
		{
			"id": "secret_lake_secrets",
			"pos": Vector2(5450, -1150),
			"zoom": 1.65,
			"desc": "Misterios do Lago: Aviao Submerso, Ilha Secreta e Cofre com Ouro e Armas"
		},
		{
			"id": "summit_bunker",
			"pos": Vector2(6500, -2700),
			"zoom": 0.80,
			"desc": "Cume Congelado, Bunker Militar, Heliponto, Radar e Nevasca"
		},
		{
			"id": "cabin_interior",
			"pos": Vector2(22500, 20000),
			"zoom": 1.95,
			"desc": "Visão Geral do Chalé Alpino: Vigas de Madeira, Lustre de Ferro e Assoalho Nobre"
		},
		{
			"id": "cabin_interior_closeup",
			"pos": Vector2(22500, 19960),
			"zoom": 2.75,
			"desc": "Lareira Monumental de Pedras, Fogão 3D, Urso 3D, Sofá Chesterfield e Mapa da Serra"
		},
		{
			"id": "cabin_interior_zones",
			"pos": Vector2(22360, 19950),
			"zoom": 3.0,
			"desc": "Bar dos Caçadores com Tampo de Ardósia, Banqueta, Uísque e Canto do Quarto"
		},
		{
			"id": "cabin_legendary_rifle",
			"pos": Vector2(22700, 19935),
			"zoom": 2.80,
			"desc": "Fuzil de Caça Lendário 'Presa do Inverno' (Tier 5): Ícone, Stats, Aura e Luneta"
		},
		{
			"id": "cabin_hunting_knife",
			"pos": Vector2(22300, 19925),
			"zoom": 2.80,
			"desc": "Faca de Caça Tática 'Lâmina do Rastreador' (Mil-Spec): Ícone, Stats e Faca 3D"
		}
	]

	var brain_dir := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"

	for shot in shots:
		if cabin:
			var rifle_st = cabin.get_node_or_null("LegendaryRifleStation")
			var knife_st = cabin.get_node_or_null("HuntingKnifeStation")
			var r_card = rifle_st.get_node_or_null("InspectionCard") if rifle_st else null
			var k_card = knife_st.get_node_or_null("InspectionCard") if knife_st else null

			if shot["id"] == "cabin_legendary_rifle":
				if r_card: r_card.visible = true
				if k_card: k_card.visible = false
			elif shot["id"] == "cabin_hunting_knife":
				if r_card: r_card.visible = false
				if k_card: k_card.visible = true
			elif shot["id"].begins_with("cabin_"):
				if r_card: r_card.visible = false
				if k_card: k_card.visible = false

		camera.position = shot["pos"]
		camera.zoom = Vector2.ONE * shot["zoom"]
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw

		var img := root.get_texture().get_image()
		var p1 := "%s/mountain_view_%s.png" % [brain_dir, shot["id"]]
		var p2 := "d:/geteco/game/tests/visual/mountain_view_%s.png" % shot["id"]
		img.save_png(p1)
		img.save_png(p2)
		print("CAPTURED: %s" % p1)

	scene.queue_free()
	for frame in 3:
		await process_frame
	quit(0)
