extends Node
const PLAZA := preload("res://world/desert/entrance/DesertTollPlaza.gd")
const PRICE := 10
var session
var paid_car: Node3D
var _clock:=0.0

func configure(owner_session) -> void:
	session=owner_session
	name="DesertToll"

func _car() -> Node3D:
	if not is_instance_valid(session) or not session.ready_for_play: return null
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return null
	if not session.world.driving.occupied: return null
	return session.world.driving.car

func nearest_action() -> Dictionary:
	var car:=_car()
	if car==null or car==paid_car or session.modal or session.has_position_transition(): return {}
	if session.world.gameplay.health<=0 or car.input_locked or absf(car.speed)>.5: return {}
	var local:=car.global_position-PLAZA.POSITION
	if local.x<1.0 or local.x>4.6 or local.z< -3.0 or local.z>7.5: return {}
	if car.global_basis.z.z<.5: return {}
	if get_tree().get_first_node_in_group(PLAZA.GROUP)==null: return {}
	return {"id":"desert","target":"entrance_toll","label":"Pagar pedágio · R$ %d"%PRICE}

func perform() -> bool:
	if nearest_action().is_empty(): return false
	var car:=_car()
	# Deriva o serial da carteira persistida, para que carregar/reentrar não reaproveite um débito.
	var serial:=0
	for key in session.state.economy.snapshot().transactions:
		if str(key).begins_with("spend:desert_toll:"):
			serial=maxi(serial,str(key).trim_prefix("spend:desert_toll:").to_int())
	if not session.state.economy.spend(PRICE,"desert_toll:%d"%(serial+1)):
		session.show_message("Dinheiro insuficiente para o pedágio.")
		return true
	paid_car=car
	_refresh()
	return true

func save_block_reason() -> String:
	return "Atravesse o pedágio para salvar." if is_instance_valid(paid_car) else ""

func cancel_attempt() -> void:
	paid_car=null
	_refresh()

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.1: return
	_clock=0.0
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(session) or not session.ready_for_play: return
	if is_instance_valid(paid_car):
		if paid_car.global_position.distance_to(PLAZA.POSITION)>24 or paid_car!=_car():
			paid_car=null
			session.save_game()
	var plaza=get_tree().get_first_node_in_group(PLAZA.GROUP)
	if not is_instance_valid(plaza): return
	var opened: Array[bool]=[is_instance_valid(paid_car),false]
	# O trânsito comum usa as mesmas cancelas. Uma cancela nunca fecha sobre um ocupante.
	# Despacho, ônibus e outros motoristas NPC ficam fora da frota ambiente.
	# Todos os veículos reais dividem este grupo, incluindo a ocupação física.
	for car in get_tree().get_nodes_in_group("drivable"):
		if not is_instance_valid(car): continue
		var local: Vector3=car.global_position-PLAZA.POSITION
		if absf(local.x)>5.2 or absf(local.z)>22: continue
		var lane:=0 if local.x>0 else 1
		var barrier_z: float=-4.3 if lane==0 else 4.3
		var clearance: float=car.half_length+2.0
		if absf(local.z-barrier_z)<clearance and absf(plaza.arms[lane].rotation.z)>.1: opened[lane]=true
		if lane==1 or (car!=_car() and (car.traffic or car.external_input)): opened[lane]=true
	# Pedestres parados sob um braço já erguido também ficam protegidos.
	var player: Vector3=session.world.player.global_position-PLAZA.POSITION
	for lane in 2:
		if absf(player.x-(2.8 if lane==0 else -2.8))<2.1 and absf(player.z-(-4.3 if lane==0 else 4.3))<1.0 and absf(plaza.arms[lane].rotation.z)>.1: opened[lane]=true
	for lane in 2: plaza.set_open(lane,opened[lane])
