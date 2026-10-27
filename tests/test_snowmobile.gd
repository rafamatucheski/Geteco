extends SceneTree
## Snowmobile (bike_snow): modelo próprio (sem peças da moto atravessando), repintável sem cobrir o adesivo
## de corrida, esquis e guidão esterçando, piloto com banco e manoplas, e som próprio (motor de dois tempos
## e esteira). Uso: "$GODOT" --path . --script res://tests/test_snowmobile.gd
const VEHICLE := preload("res://scripts/Vehicle.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const BANKS := preload("res://audio/EngineBankCache.gd")
const SNOW_AUDIO := preload("res://audio/snowmobile/SnowmobileAudio.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failures.append(label)
	push_error(label)

func run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var car := VEHICLE.new()
	car.archetype = "bike_snow"
	car.vehicle_id = "snowmobile_test"
	root.add_child(car)
	car.place(Vector3(0, .12, 0), 0.0)
	for frame in 10: await physics_frame
	car.set_physics_process(false)
	var names := {}
	var visible_wheels := 0
	var lowest := INF
	for mesh: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		names[str(mesh.name).rstrip("0123456789")] = true
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		if mesh.has_meta("wheel_center") and mesh.get_meta("wheel_spins", true): visible_wheels += 1
		lowest = minf(lowest, (mesh.global_transform * mesh.get_aabb()).position.y)
	check(not names.has("Exhaust") and not names.has("LicensePlate"), "sem peças herdadas da moto")
	check(visible_wheels == 0, "nenhuma roda à mostra (%d)" % visible_wheels)
	check(absf(lowest - car.global_position.y) < .015, "esqui e esteira apoiados no chão (%.3f m)" % (lowest - car.global_position.y))
	# Pintura: catálogo e garagem pegam no capô/túnel; o adesivo e o resto ficam como estão.
	check(car._paint.materials.size() == 1, "um material de pintura (%d)" % car._paint.materials.size())
	var vinyl: Array[StandardMaterial3D] = []
	# Nomes repetidos ganham prefixo/sufixo do Godot ("@RaceStripe@…"): procura pelo trecho.
	for mesh: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).contains("RaceStripe"): vinyl.append(mesh.get_active_material(0) as StandardMaterial3D)
	check(vinyl.size() == 2, "duas faixas de corrida no capô (%d)" % vinyl.size())
	var stripe_color := vinyl[0].albedo_color if not vinyl.is_empty() else Color.BLACK
	car.paint_color = Color("1f8a4c")
	check(not car._paint.materials.is_empty() and car._paint.materials[0].albedo_color.is_equal_approx(Color("1f8a4c")), "repintura muda a carenagem")
	check(not vinyl.is_empty() and vinyl[0].albedo_color.is_equal_approx(stripe_color) and vinyl[0] not in car._paint.materials, "repintura não cobre o adesivo")
	# Piloto e direção.
	var holds: Dictionary = car.motorcycle_handholds()
	check(holds.has("Left") and holds.has("Right"), "duas manoplas para o piloto")
	check(car.steer_pivots.size() == 3, "guidão e dois esquis esterçam (%d pivôs)" % car.steer_pivots.size())
	check(car.wheels.size() == 2, "duas rodas de contato escondidas (%d)" % car.wheels.size())
	# Som.
	check(PROFILE.family("bike_snow") == "snowmobile" and PROFILE.bank_family("bike_snow") == "snowmobile", "família de motor própria")
	check(PROFILE.family("bike_urban") == "bike_urban", "moto urbana segue com o som dela")
	check(BANKS.has_bank("snowmobile") and BANKS.bank("snowmobile").size() == 7, "banco de 7 faixas do dois tempos")
	var track := SNOW_AUDIO.track_stream()
	check(track != null and track.loop_mode == AudioStreamWAV.LOOP_FORWARD and track.loop_end > int(track.mix_rate), "laço da esteira de 2 s")
	check(SNOW_AUDIO.track_gain(0.0) == 0.0 and SNOW_AUDIO.track_gain(12.0) > .5, "esteira cala parada e soa andando")
	print("SNOWMOBILE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
