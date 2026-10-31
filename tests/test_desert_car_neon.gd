extends SceneTree
## Só contratos funcionais. A aparência temporal e o custo de GPU exigem as
## capturas renderizadas e integradas de arrancada/direção livre, rodadas à parte.
const NEON := preload("res://gameplay/desert_cars/DesertCarNeon.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var scene: Node3D

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _spawn(id: String, point: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "neon_contract_"+id
	car.position = point
	scene.add_child(car)
	car.set_physics_process(false)
	return car

func _settle(car: CharacterBody3D) -> void:
	for i in 5:
		await physics_frame
		car.velocity = Vector3.DOWN
		car.move_and_slide()

func _tick(effect: Node3D, hour: float, camera: Camera3D, exterior: bool, seconds := 1.0) -> void:
	for i in ceili(seconds*60.0): effect.update(hour,camera,exterior,1.0/60.0)

func _run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60,.2,60)
	shape.shape = box
	shape.position.y = -.1
	floor.add_child(shape)
	scene.add_child(floor)
	var camera := Camera3D.new()
	camera.position = Vector3(8,4,7)
	scene.add_child(camera)
	camera.make_current()
	var stock := _spawn("desert_faisca",Vector3(-8,.03,0))
	_check(NEON.install(stock,CARS.spec("desert_faisca"))==null,"Stock desert traffic must not acquire a race neon kit")
	_check(not stock.has_node("DesertCarNeon"),"Stock car must pay no neon node/light cost")
	var car := _spawn("desert_mirage_gt",Vector3(0,.03,0))
	await _settle(car)
	_check(car.is_on_floor(),"Neon contract fixture must establish real physical support")
	var neon = NEON.install(car,CARS.spec("desert_mirage_gt"))
	if neon == null:
		_check(false,"GT variant must install its authored night kit")
		scene.free()
		quit(1)
		return
	_check(NEON.install(car,CARS.spec("desert_mirage_gt"))==neon,"Restoring/tuning a car must reuse its kit")
	_check(car.find_children("DesertCarNeon","",false,false).size()==1,"Repeated attachment must not stack lights")
	_check(neon.find_children("*","Light3D",true,false).size()==1,"A race kit has one bounded real source")
	_check((neon.ground_light as SpotLight3D).global_basis.z.dot(Vector3.UP)>.99,"Neon source must face down toward the pavement")
	_check(not neon.ground_finish.no_depth_test,"Floor wash must respect intervening opaque geometry")
	_check(not neon.ground_light.shadow_enabled,"Neon kit must not add a shadow pass")
	_tick(neon,.5,camera,true)
	_check(neon.strength==0.0 and not neon.ground_light.visible and not neon.ground_pool.visible,"Midday leaves the neon light and floor wash off")
	neon.update(.95,camera,true,1.0/60.0)
	_check(neon.strength>0.0 and neon.strength<.2,"Entering night must ramp up instead of flash")
	_tick(neon,.95,camera,true)
	var near_strength: float = neon.strength
	_check(near_strength>.95 and neon.ground_light.visible and neon.ground_pool.visible,"Supported night racer lights its tubes and pavement")
	_check(NEON.night_weight(.81)>NEON.night_weight(.76) and NEON.night_weight(.81)<NEON.night_weight(.95),"Dusk must progressively expose the night kit")
	_check(is_equal_approx(NEON.night_weight(0.0),NEON.night_weight(1.0)),"Midnight rollover must keep continuous night brightness")
	var second := _spawn("desert_coyote_drag",Vector3(8,.03,0))
	await _settle(second)
	var other = NEON.install(second,CARS.spec("desert_coyote_drag"))
	_check(other != null,"Second race family must receive its own authored kit")
	if other != null:
		_check(other.strip_finish!=neon.strip_finish and other.ground_finish!=neon.ground_finish,"Distance/time fades cannot mutate a neighbouring car's materials")
		_check(other.color!=neon.color,"Rival identities retain different authored neon colours")
		_check(other.ground_finish.albedo_texture==neon.ground_finish.albedo_texture,"Cars reuse the same immutable floor texture")
	camera.position = Vector3(0,4,45)
	_tick(neon,.95,camera,true)
	var middle_strength: float = neon.strength
	_check(middle_strength>0.0 and middle_strength<near_strength,"The actual race camera receives a gradual distance fade")
	camera.position = Vector3(0,4,80)
	_tick(neon,.95,camera,true)
	_check(neon.strength==0.0 and not neon.ground_light.visible,"Distant cars release their light source")
	camera.position = Vector3(8,4,7)
	_tick(neon,.95,camera,true)
	car.position.y = 1.0
	car.velocity = Vector3.ZERO
	await physics_frame
	car.move_and_slide()
	_check(not car.is_on_floor(),"Airborne fixture must leave the physical floor")
	neon.update(.95,camera,true,1.0/60.0)
	_check(neon.strength>.9 and not neon.ground_pool.visible,"An airborne car keeps its tubes while the wash cannot float beneath it")
	car.position.y = .03
	await _settle(car)
	_tick(neon,.95,camera,true)
	_check(neon.ground_pool.visible,"Landing restores the grounded wash")
	_tick(neon,.95,camera,false)
	_check(neon.strength==0.0 and not neon.ground_light.visible,"Entering an interior retires exterior neon light")
	_tick(neon,.95,camera,true)
	car.health = 0
	_tick(neon,.95,camera,true)
	_check(neon.strength==0.0 and not neon.ground_pool.visible,"Destroyed cars cannot retain active underglow")
	car.health = car.max_health
	_tick(neon,.95,camera,true)
	_tick(neon,.95,null,true)
	_check(neon.strength==0.0,"Missing rendering camera must not keep a distant source active")
	var before: float = neon.strength
	neon.update(.95,camera,true,NAN)
	_check(neon.strength==before,"Invalid frame delta must not poison the persistent fade state")
	scene.free()
	await process_frame
	_check(get_nodes_in_group(NEON.GROUP).is_empty(),"Freeing streamed cars must remove all neon group entries")
	print("DESERT_CAR_NEON_","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
