extends RefCounted
## Quatro baias de serviço no pátio oeste existente do North Pier. A fachada continua
## um corredor de pedestres; só a entrada de carros o cruza durante a partida.
const SLOTS := [Vector3(30,.08,11.5), Vector3(30,.08,2), Vector3(22.5,.08,11.5), Vector3(22.5,.08,2)]
const DEPARTURE_ORDER := [0,2,1,3]
const MERGE := Vector3(23.25,0,38)

static func arrival_slot(index: int) -> Vector3:
	# A escolta/caminhão da frente pega primeiro a baia do fundo; os seguintes nunca precisam
	# atravessar um colega estacionado para chegar ao espaço de descarga.
	return SLOTS[index ^ 1]

static func arrival(index: int) -> Array[Vector3]:
	var point := arrival_slot(index)
	return [Vector3(point.x+8,0,21.5),Vector3(point.x+4,0,21.5),
		Vector3(point.x+1,0,20),Vector3(point.x,0,17),point]

static func migrate_loading(data: Dictionary) -> void:
	# Só checkpoints de carga neutros e não publicados vão para as baias corrigidas.
	# Corpos vivos, combate, carga, baixas e viagens já em andamento são mantidos.
	var returning: bool = data.get("destination","") == "harbor_bank" and data.get("phase","") == "unloading"
	var loading: bool = data.get("origin","") == "harbor_bank" and data.get("phase","") in ["loading","boarding"]
	if data.get("hostile",false) or not (loading or returning): return
	data.service_layout = 1
	if data.get("vehicles",[]).size() != 4: return
	if data.vehicles.all(func(row): return contains(Vector3(row.point[0],row.point[1],row.point[2]))): return
	for index in 4:
		var point: Vector3 = arrival_slot(index) if returning else SLOTS[index]
		data.vehicles[index].point = [point.x,point.y,point.z]
		data.vehicles[index].yaw = 0.0 if returning else PI
	data.virtual_poses = true
	for guard in data.guards: guard.phase = "board"

static func contains(point: Vector3) -> bool:
	return point.x > 19.0 and point.x < 33.0 and point.z < 17.0 and point.z > -3.0

static func departure(index: int) -> Array[Vector3]:
	var point: Vector3 = SLOTS[index]
	# Sai para o sul pela Westgate. Cruzar a Foundry até as faixas
	# para leste cria um conflito de frente com carros para oeste e ônibus articulados.
	var path: Array[Vector3] = [point]
	if index < 2:
		path.append_array([Vector3(30,0,15),Vector3(28.5,0,17),Vector3(25.5,0,18)])
	path.append_array([Vector3(23.25,0,22),Vector3(23.25,0,28),MERGE])
	return path

static func carrier_path(car: Node3D, position: Vector3, target: Vector3, bank: Vector3, to_bank: bool, to_door: bool) -> Array[Vector3]:
	var door: Vector3 = car.door_point()
	var aisle := Vector3(32.25,.08,door.z)
	var frontage := Vector3(32.25,.08,bank.z)
	var result: Array[Vector3] = []
	if to_bank:
		if position.x < 31.8: result.append(aisle)
		result.append(frontage)
	elif to_door:
		if position.x > 33.0: result.append(frontage)
		result.append(aisle)
	else:
		if position.x > 33.0: result.append(frontage)
		if position.x < 31.8: result.append(aisle)
	result.append(target)
	return result
