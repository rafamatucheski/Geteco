extends SceneTree
## Esgoto: segredo da V1 no catálogo, atmosfera sem colisão e ratos em piso livre.
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const ATMOSPHERE = preload("res://world/places/SewerAtmosphere3D.gd")
var failures := 0

func verify(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var definition: Dictionary = CATALOG.get_definition("harbor_sewer")
	verify(definition.reward.get("id","") == "harbor_police_sewer_sawed_off", "id do segredo é o mesmo da V1")
	verify(definition.reward.get("item","") == "sawed_off" and int(definition.reward.get("ammo",0)) == 24, "escopeta serrada com 24 cartuchos como na V1")
	var room = CATALOG.create_place("harbor_sewer")
	root.add_child(room)
	await process_frame
	verify(room.reward_points.size() == 1, "um ponto de recompensa instalado")
	if room.reward_points.size() == 1:
		var local: Vector3 = room.to_local(room.reward_points[0].position)
		verify(local.distance_to(ATMOSPHERE.STASH) < .01, "recompensa no SECRET_POSITION da V1, sem cair no fallback do spawn")
	var atmosphere: Node3D = room.model.get_node_or_null("SewerAtmosphere")
	verify(atmosphere != null, "atmosfera montada pelo SewerModel")
	if atmosphere == null:
		quit(1)
		return
	var tagged := 0
	for mesh in atmosphere.find_children("*","MeshInstance3D",true,false):
		if not str(mesh.get_meta("interior_solid_id","")).is_empty(): tagged += 1
	verify(tagged == 0, "nenhuma peça da atmosfera vira sólido do NativePlace")
	verify(atmosphere.find_children("*","StaticBody3D",true,false).is_empty(), "atmosfera não cria corpo estático")
	var water: MeshInstance3D = atmosphere.get_node("FlowingWater")
	verify(water.position.y > -0.08, "lâmina d'água acima da laje do piso (-0,08 m)")
	# Ratos: todos os pontos das rotas em piso livre (o chão do NativePlace é
	# testado com o mesmo raio de um corpo pequeno).
	var clear := true
	for rat in atmosphere._rats:
		for point in rat.route:
			if not room.is_floor_clear(room.model.to_global(point) - room.global_position, .08): clear = false
	verify(clear, "pontos das rotas dos ratos em piso livre")
	var start: Array[Vector3] = []
	for rat in atmosphere._rats: start.append(rat.node.position)
	for i in 400: atmosphere._process(1.0 / 60.0)
	var moved := false
	for i in atmosphere._rats.size():
		if atmosphere._rats[i].node.position.distance_to(start[i]) > .05: moved = true
	verify(moved, "ratos se movem sozinhos")
	# Dante chega perto: o rato mais próximo dispara em fuga.
	var dante := Node3D.new()
	room.add_child(dante)
	var rat: Dictionary = atmosphere._rats[0]
	rat.pause = 5.0
	dante.global_position = atmosphere.to_global(rat.node.position + Vector3(.6,0,0))
	atmosphere._player = dante
	atmosphere._process(1.0 / 60.0)
	verify(rat.speed > 3.0 and rat.pause <= 0.0, "rato foge quando o Dante se aproxima")
	var fell := false
	for i in 240:
		atmosphere._process(1.0 / 60.0)
		for drip in atmosphere._drips:
			if drip.ripple >= 0.0: fell = true
	verify(fell, "gotas caem e abrem ondulação")
	room.free()
	print("SEWER_ATMOSPHERE failures=%d" % failures)
	quit(1 if failures > 0 else 0)
