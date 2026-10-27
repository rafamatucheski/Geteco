extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"

const MOUNTAIN_FINISH := preload("res://world/mountain_detail/MountainInteriorFinish.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const FIREFIGHTER := preload("res://gameplay/emergency/FirefighterModel.gd")
## Baias laterais com caminhão estacionado; a do meio fica livre porque é por ela que o jogador
## entra (FIRE_STATION_DOOR_OFFSET) e é ali que o Capitão Rocha atende.
const TRUCK_LANES := [-6.875, 6.875]
## Comprimento e largura do rescue_pumper (VehicleCatalog: 128 × 42 px a 16 px/m).
const TRUCK_SIZE := Vector2(2.7, 8.0)
const TRUCK_Z := 1.6
## Equipe de plantão: lavando o caminhão da esquerda e na bancada de equipamento.
## Ângulo em Y com a frente do modelo em -Z: PI/2 olha para -X (o caminhão), 0 para o fundo.
const CREW := [[Vector3(-4.1, 0, 0.6), PI * .5], [Vector3(2.6, 0, -7.4), 0.0]]
## Lidos pelo NativePlace como colisão (retângulos x/z): caminhões e a equipe de plantão.
var solid_rects := {}

func _ready() -> void:
	# Pedido de 27/10: o quartel por dentro era caixa de cor lisa, sem caminhão nem bombeiro.
	# O acabamento é o mesmo dos interiores da serra (MountainInteriorFinish): mesmos recursos de
	# shader, nada compila ao entrar.
	_finish(box("Foundation",Vector3(28,.22,20.8),Vector3(0,-.15,.4),"373e3e"),"slab","373e3e")
	_finish(box("ConcreteFloor",Vector3(27.8,.05,20.6),Vector3(0,0,.4),"777a70"),"epoxy","777a70")
	for x in range(-12,14,2):
		box("ConcreteJoint",Vector3(.025,.012,20),Vector3(x,.04,0),"59615b")
	for z in range(-10,11,2):
		box("ConcreteJoint",Vector3(28,.012,.025),Vector3(0,.04,z),"59615b")
	_finish(_solid("BackWall",Vector3(28,4,.25),Vector3(0,2,-10),"b6b4a0"),"block","b6b4a0")
	_finish(box("BackWainscot",Vector3(27.5,1.1,.06),Vector3(0,.55,-9.85),"a94835"),"painted","a94835")
	for side in [-1.0,1.0]:
		_finish(_solid("SideWall%d"%int(side),Vector3(.25,4,20),Vector3(side*14,2,0),"898e81"),"block","a3a596")
		_finish(box("WallStripe",Vector3(.05,.28,19.8),Vector3(side*13.85,1.5,0),"a94835"),"painted","a94835")
	for spec in [[-11.6,4.75],[-3.44,2.25],[3.44,2.25],[11.6,4.75]]:
		_finish(_solid("FrontPier%.2f"%spec[0],Vector3(spec[1],.6,.3),Vector3(spec[0],.3,10),"6d756c"),"cast","6d756c")
	for lane in [-6.875,0.0,6.875]:
		for side in [-1.0,1.0]:
			box("BayLine",Vector3(.09,.014,16.6),Vector3(lane+side*2.25,.045,1.2),"d9ba62")
			_finish(box("DoorJamb",Vector3(.18,3.6,.35),Vector3(lane+side*2.3,1.8,10),"b1b1a2"),"painted","b1b1a2")
		box("Drain",Vector3(3.9,.02,.3),Vector3(lane,.055,6.5),"343e3a")
		for i in 18:
			box("DrainGrate",Vector3(.06,.015,.32),Vector3(lane-1.8+i*.21,.073,6.5),"8b9489")
		_finish(box("ShutterHousing",Vector3(4.8,.35,.42),Vector3(lane,3.8,10),"8f9890"),"painted","8f9890")
		box("RearWindow",Vector3(3.8,1.05,.06),Vector3(lane,2.6,-9.84),"7f9c9b")
		for x in [-1.9,0,1.9]:
			box("WindowMullion",Vector3(.08,1.15,.09),Vector3(lane+x,2.6,-9.77),"404f49")
		# Batente de pneu no fundo da baia: o caminhão para sempre no mesmo lugar.
		_finish(box("WheelStop",Vector3(1.9,.14,.22),Vector3(lane,.07,-3.0),"d9ba62"),"painted","d9ba62")
	for index in 5:
		var z := -7.5+index*1.25
		_finish(_solid("GearLocker%d"%index,Vector3(1.1,2.35,1.1),Vector3(-12.5,1.175,z),"a54735"),"painted","a54735")
		_finish(box("LockerDoor",Vector3(.04,2.14,.96),Vector3(-11.93,1.18,z),"b85943"),"painted","b85943")
		box("LockerHandle",Vector3(.07,.22,.045),Vector3(-11.89,1.08,z+.3),"d1c2a0")
		for vent in 4:
			box("Vent",Vector3(.03,.03,.55),Vector3(-11.88,1.8+vent*.08,z),"553f33")
	_gear_rack()
	_hose_wall()
	_finish(_solid("MedicalCabinet",Vector3(1.2,1.5,2.8),Vector3(12.4,.75,-5.3),"d2d0bb"),"painted","d2d0bb")
	box("MedicalCross",Vector3(.025,.65,.18),Vector3(11.78,1.0,-5.3),"b34638")
	box("MedicalCross",Vector3(.025,.18,.65),Vector3(11.77,1.0,-5.3),"b34638")
	_finish(_solid("OxygenRack",Vector3(1.25,.2,2.4),Vector3(12.4,.15,-1.5),"525d51"),"painted","525d51")
	for i in 3:
		var tank := cylinder("OxygenTank",.26,1.3,Vector3(12.4,.9,-2.2+i*.7),"94a993")
		tank.set_meta("interior_solid_id",&"OxygenRack")
		box("TankValve",Vector3(.15,.12,.12),Vector3(12.4,1.62,-2.2+i*.7),"b49b66")
	_finish(_solid("WorkBench",Vector3(5.2,1.0,1.1),Vector3(0,.5,-8.4),"816545"),"wood","816545")
	_finish(_solid("WorkBench",Vector3(5.4,.09,1.2),Vector3(0,1.05,-8.4),"baa379"),"wood","baa379")
	for i in 4:
		box("Helmet",Vector3(.35,.23,.38),Vector3(-1.8+i*1.2,1.22,-8.4),"c9b154")
	for x in [-7,0,7]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,3.6,-2.0)
		lamp.light_color = Color("ffdfaa")
		lamp.light_energy = .8
		lamp.omni_range = 9
		add_child(lamp)
		box("CeilingLight",Vector3(2.8,.12,.45),Vector3(x,3.65,-2.0),"ddd8b9")
	_trucks()
	_crew()

## Dois rescue_pumper da frota (mesmo modelo retido pelo ProductionWorld para o despacho), só
## visual: sem corpo de veículo, sem processo de direção. Frente para o portão.
func _trucks() -> void:
	for i in TRUCK_LANES.size():
		var lane: float = TRUCK_LANES[i]
		var truck := FLEET.create("rescue_pumper")
		if truck == null: continue
		truck.name = "ParkedPumper%d" % i
		truck.position = Vector3(lane,0,TRUCK_Z)
		truck.rotation.y = PI
		add_child(truck)
		solid_rects["ParkedPumper%d" % i] = Rect2(lane-TRUCK_SIZE.x*.5,TRUCK_Z-TRUCK_SIZE.y*.5,TRUCK_SIZE.x,TRUCK_SIZE.y)

func _crew() -> void:
	for i in CREW.size():
		var firefighter: Node3D = FIREFIGHTER.new()
		firefighter.name = "OnDutyFirefighter%d" % i
		firefighter.position = CREW[i][0]
		firefighter.rotation.y = CREW[i][1]
		add_child(firefighter)
		var at: Vector3 = CREW[i][0]
		solid_rects["OnDutyFirefighter%d" % i] = Rect2(at.x-.3,at.z-.3,.6,.6)

## Cabideiro de roupa de combate ao lado dos armários: capacete, casaco e bota por gancho.
func _gear_rack() -> void:
	_finish(_solid("GearRack",Vector3(.5,2.0,4.6),Vector3(-13.5,1.0,0.6),"4c544f"),"painted","4c544f")
	for i in 5:
		var z := -1.2+i*.9
		_finish(box("TurnoutCoat",Vector3(.32,.95,.62),Vector3(-13.12,1.3,z),"b48a2a"),"fabric","b48a2a")
		box("CoatStripe",Vector3(.33,.07,.63),Vector3(-13.12,1.05,z),"d8d8c4")
		box("RackHelmet",Vector3(.34,.22,.36),Vector3(-13.12,1.95,z),"c33a2c")
		for side in [-1.0,1.0]:
			box("RackBoot",Vector3(.14,.34,.26),Vector3(-12.95,.17,z+side*.1),"1d1e20")

## Mangueira enrolada e hidrante de parede no fundo, entre as janelas.
func _hose_wall() -> void:
	for lane in [-3.44,3.44]:
		_finish(box("HoseReelPlate",Vector3(1.2,1.2,.06),Vector3(lane,1.55,-9.84),"8f2f25"),"painted","8f2f25")
		var reel := cylinder("HoseReel",.48,.28,Vector3(lane,1.55,-9.66),"b0392b")
		reel.rotation.x = PI*.5
		var hub := cylinder("HoseHub",.14,.32,Vector3(lane,1.55,-9.64),"c9b98e")
		hub.rotation.x = PI*.5
		_finish(box("Standpipe",Vector3(.12,1.0,.12),Vector3(lane+.8,.5,-9.8),"b0392b"),"painted","b0392b")

func _finish(mesh: MeshInstance3D, kind: String, color: String) -> MeshInstance3D:
	mesh.material_override = MOUNTAIN_FINISH.material(kind, Color(color))
	return mesh

func _solid(id: String,size: Vector3,point: Vector3,color: String) -> MeshInstance3D:
	var mesh := box(id,size,point,color)
	mesh.set_meta("interior_solid_id",StringName(id))
	return mesh
