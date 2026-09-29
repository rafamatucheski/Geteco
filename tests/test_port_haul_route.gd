extends SceneTree

## A rota do caminhão de carga até o armazém não pode passar duas vezes pelo mesmo trecho.
## O caminhão mede o progresso pelo ponto mais próximo da rota; com um laço (retorno até
## o ponto de passagem e outro de volta) ele ficava girando para sempre e nunca entregava
## (medido 2026-09-29: ponto de passagem no eixo da rua, z 140,4, pegava a faixa de volta).
var world
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 500:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false,"Main V2 starts")
		quit(1)
		return
	check(world.production.no_save,"Route observation does not touch personal save")
	var haul = preload("res://gameplay/urban_v1/PortHaulRoutes.gd")
	var graph = world.session.controller.traffic_routes
	for returning in [false,true]:
		var name := "return" if returning else "outbound"
		var curve: Curve3D = haul.journey(graph,Vector3(259.3,0,208.8) if not returning else haul.dock(0),0,returning)
		check(curve != null,"%s journey exists"%name)
		if curve == null: continue
		var length := curve.get_baked_length()
		var samples: Array[Vector3] = []
		var offset := 0.0
		while offset < length:
			samples.append(curve.sample_baked(offset,true))
			offset += 4.0
		var worst := 0.0
		var worst_pair := Vector2i.ZERO
		# Dois pontos a mais de 60 m de distância pela rota e a menos de 2 m no mapa = laço.
		for i in samples.size():
			for j in range(i+15,samples.size()):
				var gap := Vector2(samples[i].x-samples[j].x,samples[i].z-samples[j].z).length()
				if gap < 2.0 and 2.0-gap > worst:
					worst = 2.0-gap
					worst_pair = Vector2i(i*4,j*4)
		check(worst == 0.0,"%s journey does not revisit its own path (offsets %s)"%[name,worst_pair])
		print("HAUL_ROUTE ",name," length=",snappedf(length,.1)," loop_offsets=",worst_pair if worst > 0.0 else "none")
	print("PORT_HAUL_ROUTE failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
