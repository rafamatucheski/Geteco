extends SceneTree
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const MODELS := preload("res://activities/motocross/MotocrossModels.gd")
const PROGRESS := preload("res://activities/motocross/MotocrossProgress.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var hull := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300,1,300)
	hull.shape = shape
	ground.position.y = -.5
	ground.add_child(hull)
	world.add_child(ground)
	var bikes: Array = []
	for model in 3:
		var bike := BIKE.new()
		MODELS.apply(bike,model)
		world.add_child(bike)
		bike.reset_to(Transform3D(Basis.IDENTITY,Vector3(model*20,.1,0)))
		bikes.append(bike)
	await frames(8)
	for bike in bikes: bike.drive(1,0)
	await frames(60)
	check(bikes[1].speed>bikes[0].speed+1.5 and bikes[1].distance_travelled>bikes[0].distance_travelled,"arrancada ganha velocidade e distância na física real")
	check(bikes[0].max_speed>bikes[1].max_speed and bikes[0].max_speed>bikes[2].max_speed,"equilibrada compensa com maior final")
	for bike in bikes:
		bike.reset_to(Transform3D(Basis.IDENTITY,Vector3(bike.profile_id*20,.1,0)))
	await frames(8)
	for bike in bikes:
		bike.speed = 8
		bike.drive(0,1)
	await frames(45)
	check(absf(bikes[2].rotation.y)>absf(bikes[0].rotation.y)*1.15 and absf(bikes[0].rotation.y)>absf(bikes[1].rotation.y),"moto de curva gira mais no mesmo tempo e velocidade inicial")
	check(bikes[2].grip_multiplier>bikes[0].grip_multiplier,"moto de curva sustenta mais aderência")
	var progress := PROGRESS.new()
	var old := progress.snapshot()
	old.erase("bike_model")
	check(progress.restore_snapshot(old) and progress.data.bike_model==0,"save antigo recebe modelo equilibrado")
	for invalid in [-1,3,1.5,"2",NAN]:
		var bad := progress.snapshot()
		bad.bike_model = invalid
		check(not progress.restore_snapshot(bad),"modelo de save inválido rejeitado: %s"%str(invalid))
	world.free()
	print("MOTOCROSS_MODELS_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
