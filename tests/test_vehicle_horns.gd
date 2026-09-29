extends SceneTree

## Buzina por família de veículo, tecla G dentro do carro e cancela do porto para o
## caminhão de carga dirigido pelo jogador.
const AUDIO := preload("res://gameplay/VehicleEquipmentAudio.gd")
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const SECURITY := preload("res://gameplay/urban_v1/HarborPortSecurity.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	# --- perfis
	for family in AUDIO.HORN_PROFILES:
		var stream: AudioStreamWAV = AUDIO.horn_stream(family)
		check(stream != null and stream.data.size() > 0,"buzina %s gera áudio" % family)
	var street := AUDIO.horn_stream("street")
	check(street.data.size() == 17640,"street continua o oscilador original de 0,4 s")
	check(AUDIO.horn_stream().data == street.data,"chamada sem argumentos igual a street")
	for heavy in ["truck","bus","fire_diesel"]:
		check(AUDIO.horn_stream(heavy).data.size() > street.data.size() * 2 - 1,"buzina de ar de %s é longa" % heavy)
		check(AUDIO.is_heavy_horn(heavy),"%s é buzina de ar" % heavy)
	check(AUDIO.horn_stream("bike_urban").data.size() < street.data.size(),"moto tem bipe curto")
	check(AUDIO.horn_stream("truck").data != street.data and AUDIO.horn_stream("sport").data != street.data,"famílias não soam iguais")
	check(AUDIO.horn_stream("família_inexistente").data == street.data,"família desconhecida cai em street")
	check(not AUDIO.is_heavy_horn("street") and not AUDIO.is_heavy_horn("bike_sport"),"carro e moto não usam buzina de ar")
	# --- desafinação estável por modelo
	check(AUDIO.horn_stream("street","union_sedan") == AUDIO.horn_stream("street","union_sedan"),"mesmo modelo, mesma buzina")
	var names := ["taxi_yellow","union_sedan","courier_van","sport_coupe","ranch_single","arctic_jeep","nimbus_minivan"]
	var distinct := {}
	for name in names: distinct[hash(AUDIO.horn_stream("street",name).data)] = true
	check(distinct.size() >= 3,"modelos da mesma família não soam todos iguais (%d variações)" % distinct.size())
	# --- equipamento: caminhão usa buzina de ar; G buzina dentro do carro
	var world := Node3D.new()
	root.add_child(world)
	check(InputMap.has_action("weapon_flashlight"),"ação da lanterna existe")
	var truck := VEHICLE.new()
	truck.archetype = "cargo_flatbed_truck"
	world.add_child(truck)
	truck.set_physics_process(false)
	var equipment := EQUIPMENT.new()
	equipment.configure(truck,world)
	truck.add_child(equipment)
	truck.controlled = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.keycode = KEY_G
	key.pressed = true
	check(equipment.handle_input(key,true),"G buzina dentro do veículo")
	check(equipment.horn_audio.playing,"a buzina toca")
	check(equipment.horn_audio.stream.data.size() > street.data.size() * 2 - 1,"caminhão usa buzina de ar longa")
	check(equipment.horn_audio.max_distance > 60.0 and equipment.horn_audio.volume_db > -7.0,"buzina de ar é mais alta e alcança mais longe")
	equipment.horn_audio.stop()
	var h_key := InputEventKey.new()
	h_key.physical_keycode = KEY_H
	h_key.keycode = KEY_H
	h_key.pressed = true
	check(equipment.handle_input(h_key,true),"H continua buzinando")
	equipment.horn_audio.stop()
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	world.add_child(car)
	car.set_physics_process(false)
	var car_equipment := EQUIPMENT.new()
	car_equipment.configure(car,world)
	car.add_child(car_equipment)
	car.controlled = true
	car_equipment.honk()
	check(car_equipment.horn_audio.max_distance < 50.0 and car_equipment.horn_audio.stream.data != equipment.horn_audio.stream.data,"carro de passeio não usa a buzina do caminhão")
	# --- cancela: caminhão de carga dirigido pelo jogador
	var gate_point := Vector3(3310.0 / 16.0,0.0,3380.0 / 16.0)
	var driving := {"occupied": true, "car": truck}
	var fake_session := {"world": {"driving": driving}}
	var security := SECURITY.new()
	security.session = fake_session
	truck.set_meta("port_work_vehicle",true)
	truck.global_position = gate_point + Vector3(0,0,10)
	check(security._driven_work_truck() == truck,"reconhece o caminhão do porto ao volante")
	check(security._driven_work_truck_near_gate(),"cancela abre para o caminhão do porto a 10 m")
	truck.global_position = gate_point + Vector3(0,0,40)
	check(not security._driven_work_truck_near_gate(),"longe da cancela ela não abre")
	truck.global_position = gate_point + Vector3(0,0,10)
	truck.set_meta("port_work_vehicle",false)
	check(security._driven_work_truck() == null and not security._driven_work_truck_near_gate(),"outro veículo não abre a cancela")
	truck.set_meta("port_work_vehicle",true)
	driving.occupied = false
	check(security._driven_work_truck() == null,"sem ninguém ao volante não conta")
	security.free()
	world.free()
	await process_frame
	print("VEHICLE_HORNS failures=",failures)
	quit(0 if failures.is_empty() else 1)
