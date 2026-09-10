extends "res://tests/test_npc_shared_presentation.gd"
class Vehicle extends Node2D:
	var vehicle_id := "route_city"

func get_output_directory() -> String:
	return "res://docs/measurements/winter-people-0910/"

func display_actor(actor: Node2D, label: String, driver := false) -> void:
	var display := ResidentDisplay.new()
	scene.add_child(display)
	display.viewport_3d = actor.driver_viewport if driver else actor.viewport
	display.model_root = actor.driver_model if driver else actor.model
	display.set_meta("faces_positive_z", true)
	actors.append(display)
	labels.append(label)

func _run() -> void:
	seed(9012)
	create_timer(90).timeout.connect(func(): quit(2))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		var person = load("res://world/mountain_pass/WinterResident.gd").new()
		person.resident_name = ["NORA","RAUL","LIA","BENTO","ANA","CAIO","ÍRIS","PEDRO"][i]
		person.role = ["ranger","logger","trader","visitor"][i%4]
		person.coat_color = [Color("527b8b"),Color("946546"),Color("93627f"),Color("778354")][i%4]
		person.appearance_variant = i
		scene.add_child(person)
		person.set_physics_process(false)
		display_actor(person,person.resident_name + " · " + person.role)
		check(person.model.get_meta("winter_outfit"), "Morador veste roupa térmica")
		check(person.model.has_node("Neck"), "Pescoço liga o rosto ao casaco")
	for id in ["route_city","cargo_flatbed_truck","boxrunner","snow_plow_truck","sedan_classic"]:
		var vehicle := Vehicle.new()
		vehicle.vehicle_id = id
		vehicle.set_meta("driver_appearance_seed",3 if id=="route_city" else 6)
		scene.add_child(vehicle)
		var driver = load("res://CarjackedDriver.tscn").instantiate()
		scene.add_child(driver)
		driver.setup(vehicle,Vector2(100,100))
		driver.set_physics_process(false)
		driver.set_process(false)
		display_actor(driver,{"route_city":"Ônibus · cidade","cargo_flatbed_truck":"Caminhão · carga","boxrunner":"Caminhão · baú","snow_plow_truck":"Limpa-neves","sedan_classic":"Carro · civil"}[id],true)
		if id=="sedan_classic":
			check(not driver.driver_model.has_meta("wardrobe_role"), "Carro comum preserva roupa civil")
		else:
			var role: String = driver.driver_model.get_meta("wardrobe_role")
			check(role==("bus_driver" if id=="route_city" else "truck_driver"), "Roupa corresponde ao veículo: " + id)
			check(driver.driver_model.has_node("DriverID" if id=="route_city" else "ReflectiveBand"), "Identificação visível da profissão: " + id)
			check(driver.driver_model.get_meta("winter_outfit")==(id=="snow_plow_truck"), "Casaco térmico por contexto: " + id)
			var previous = driver.driver_model
			driver.setup(vehicle,Vector2(100,100))
			check(not is_instance_valid(previous), "Troca não acumula modelos de motorista")
			actors[-1].model_root=driver.driver_model
	var winter_route := Node2D.new()
	winter_route.set_meta("mountain_traffic",true)
	scene.add_child(winter_route)
	var bus := Vehicle.new()
	bus.set_meta("driver_appearance_seed",7)
	winter_route.add_child(bus)
	check(preload("res://world/shared/pedestrians/ProfessionalDriverModel.gd").is_winter(bus), "Ônibus comum em rota fria recebe casaco")
	var bus_driver = load("res://CarjackedDriver.tscn").instantiate()
	scene.add_child(bus_driver)
	bus_driver.setup(bus,Vector2(100,100))
	bus_driver.set_physics_process(false)
	bus_driver.set_process(false)
	display_actor(bus_driver,"Ônibus · inverno",true)
	check(bus_driver.driver_model.get_meta("winter_outfit") and bus_driver.driver_model.has_node("DriverID"),"Motorista de ônibus da serra combina casaco e identificação")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(get_output_directory()))
		await capture_gallery("roupas",true)
	for display in actors: display.free()
	actors.clear()
	scene.free()
	var region = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(region)
	current_scene = region
	while not region.region_ready: await process_frame
	for i in 3: await physics_frame
	var people := get_nodes_in_group("winter_resident")
	check(people.size()==25,"Região instancia 25 pessoas, antes eram 15")
	var women := 0
	var hats := {}
	for person in people:
		women += int(person.model.appearance_female)
		hats[person.model.get_meta("headwear_variant")]=true
	check(women>=10 and people.size()-women>=10,"Região fria tem homens e mulheres")
	check(hats.size()==3,"Capuz, gorro e protetores de ouvido aparecem no mapa")
	var layout = preload("res://world/mountain_pass/MountainVillageLayout.gd")
	for entry in layout.RESIDENTS.slice(10):
		for offset in [-35,0,35]:
			check(not region.road.is_point_on_road(entry[0]+Vector2(offset,0),region.road.road_width*.5+16),"Percurso fica fora da pista: " + entry[1])
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := CircleShape2D.new()
		shape.radius=7
		query.shape=shape
		query.transform=Transform2D(0,region.to_global(entry[0]))
		query.collision_mask=1
		var hits: Array = region.get_world_2d().direct_space_state.intersect_shape(query)
		check(hits.is_empty(),"Novo morador nasce fora de obstáculos: " + entry[1])
	if DisplayServer.get_name() != "headless":
		root.size=Vector2i(1280,720)
		region.player_instance.global_position=Vector2(6580,-1750)
		var camera := Camera2D.new()
		region.add_child(camera)
		camera.global_position=Vector2(6580,-1870)
		camera.zoom=Vector2(2.5,2.5)
		camera.make_current()
		for i in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(get_output_directory()+"ponto_de_parada.png")
	region.queue_free()
	for i in 4: await process_frame
	print("WINTER_PEOPLE_DRIVERS: %s verificações, %s falhas" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
