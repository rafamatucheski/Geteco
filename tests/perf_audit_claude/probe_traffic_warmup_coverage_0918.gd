extends SceneTree
## A pergunta: prepare_common_models() já teria uma segunda passada dinâmica
## (linhas 81-99 de VehicleGeometryCache.gd) que aquece o model_class de
## QUALQUER ator já presente nos grupos modern_traffic/modern_parked_vehicle/
## regional_coach no momento do loading -- isso já cobriria moto de tráfego
## ambiente sem precisar entrar na lista fixa? Testa reproduzindo exatamente
## essa passada com uma moto de tráfego real, depois mede uma construção NOVA
## da mesma silhueta como gameplay real faria.

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	# Recria uma moto de tráfego ambiente real, do jeito que ModernTrafficFactory faz.
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2(0,0))
	path.curve.add_point(Vector2(2000,0))
	path.add_to_group("unified_traffic_lane")
	world.add_child(path)
	var ambient := ModernTrafficFactory.spawn_moving_vehicle(path, "AmbientBike", "bike_urban", 0.3, 120.0, 0)
	print("ambient motorcycle spawned, defer_presentation=", ambient.defer_presentation, " has_pending_spec=", ambient.get("_pending_spec") != null and not ambient.get("_pending_spec").is_empty())

	# Passada dinâmica de VehicleGeometryCache.prepare_common_models(), igual ao loading real.
	var t_warm0 := Time.get_ticks_usec()
	await preload("res://cars/VehicleGeometryCache.gd").prepare_common_models(self)
	var t_warm1 := Time.get_ticks_usec()
	print("prepare_common_models levou %.2f ms" % [(t_warm1 - t_warm0) / 1000.0])

	# Agora uma moto NOVA, como se tivesse acabado de ficar relevante em jogo real.
	var live := (load("res://cars/traffic/TrafficVehicle.tscn") as PackedScene).instantiate()
	live.defer_presentation = false
	live.crop = VehicleCatalog.VEHICLE_CROPS[0]
	live.target_length = 76.0
	world.add_child(live)
	var t0 := Time.get_ticks_usec()
	live.apply_archetype("bike_urban", Color.WHITE)
	var t1 := Time.get_ticks_usec()
	print("RESULTADO: moto NOVA depois do aquecimento de loading = %.2f ms (compare com ~50ms sem aquecimento nenhum, ~22ms so com o conserto do batcher sem aquecimento)" % [(t1 - t0) / 1000.0])
	quit(0)
