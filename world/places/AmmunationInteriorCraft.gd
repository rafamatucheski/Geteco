extends RefCounted
## Harbor store: human-scale stock, a clear customer aisle and a fitted rear desk.
## Footprints match NativePlace's authored counters and stock solids.
const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")
const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")
const METAL := Color("303a39")
const WOOD := Color("76624b")
const PLASTER := Color("b9b7a5")
const RED := Color("8c3f37")
const FELT := Color("364b43")
static var _counter_glass: StandardMaterial3D

static func build(root: Node3D) -> void:
	_floor(root)
	_walls(root)
	_rear_displays(root)
	_counter(root)
	_side_displays(root)
	# Mesma posição de trabalho autorada e contrato de NPC reativo do kit compartilhado.
	var npc := ART.gunsmith(root, true)
	npc.position = Vector3(0, 0, -3.4)

static func _part(root: Node3D, id: String, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var mesh := ART.box(root, size, point, color)
	mesh.name = id
	if color == WOOD:
		mesh.material_override = SURFACES.material("ammo_refresh_wood","wood",WOOD,.78,0,1.2,.35)
	elif color == PLASTER:
		mesh.material_override = SURFACES.material("ammo_refresh_plaster","plaster",PLASTER,.93,0,2,.22)
	elif color == METAL:
		mesh.material_override = SURFACES.material("ammo_refresh_metal","metal",METAL,.42,.55,.65,.18)
	elif color == FELT:
		mesh.material_override = SURFACES.material("ammo_refresh_felt","fabric",FELT,.98,0,.6,.18)
	elif id == "Floor":
		mesh.material_override = SURFACES.material("ammo_refresh_floor","concrete",color,.88,0,2,.18)
	return mesh

static func _floor(root: Node3D) -> void:
	_part(root,"Floor",Vector3(14,.16,10),Vector3(0,-.09,0),Color("686b62"))
	# Ladrilhos grandes de pedra, com juntas rasas abaixo da sola física dos atores.
	for x in range(-6,7,2):
		_part(root,"FloorJoint",Vector3(.014,.008,10),Vector3(x,-.004,0),Color("484f49"))
	for z in range(-4,5,2):
		_part(root,"FloorJoint",Vector3(14,.008,.014),Vector3(0,-.004,z),Color("484f49"))
	_part(root,"EntranceMat",Vector3(2.1,.018,1.5),Vector3(0,.001,3.75),FELT)

static func _walls(root: Node3D) -> void:
	_part(root,"RearPlaster",Vector3(14,3,.22),Vector3(0,1.5,-5),PLASTER)
	_part(root,"RearWainscot",Vector3(13.8,.85,.08),Vector3(0,.425,-4.83),WOOD)
	_part(root,"RearDado",Vector3(13.8,.06,.12),Vector3(0,.88,-4.8),METAL)
	for side in [-1,1]:
		_part(root,"SidePlaster",Vector3(.22,2.4,10),Vector3(side*7,1.2,0),PLASTER)
		_part(root,"SideWainscot",Vector3(.08,.85,9.8),Vector3(side*6.84,.425,0),WOOD)
		_part(root,"SideDado",Vector3(.10,.06,9.8),Vector3(side*6.82,.88,0),METAL)
		_part(root,"ExitCutaway",Vector3(5.8,.42,.22),Vector3(side*4.1,.21,4.9),WOOD)
		var jamb := _part(root,"EntranceJamb",Vector3(.18,1.4,.26),Vector3(side*1.15,.7,4.82),METAL)
		jamb.set_meta("interior_solid_id","HarborEntranceJamb%d"%side)
	# O nome da loja é o único letreiro decorativo.
	_part(root,"BrandBoard",Vector3(5.8,.67,.10),Vector3(0,2.52,-4.78),RED)
	ART.text(root,"AMMU-NATION",Vector3(0,2.53,-4.71),.012,Color("e4dfcc"))

static func _rear_displays(root: Node3D) -> void:
	for side in [-1,1]:
		var x: float = side*4.8
		_part(root,"WeaponCabinet",Vector3(3.5,1.85,.18),Vector3(x,1.22,-4.73),METAL)
		_part(root,"WeaponBacking",Vector3(3.28,1.63,.04),Vector3(x,1.23,-4.61),Color("616d61"))
		# Os trilhos parecem acessórios de oficina em vez de centenas de pontinhos de pino individuais.
		for row in 3:
			var y := .63+row*.51
			_part(root,"WeaponRail",Vector3(3.15,.035,.05),Vector3(x,y,-4.55),Color("929589"))
			var gun := Node3D.new()
			gun.name = "WallWeapon"
			root.add_child(gun)
			ART.item(gun,["shotgun","ak47","m4a1","smg","magnum","hunting_rifle"][row+(0 if side<0 else 3)])
			gun.position = Vector3(x,y+.06,-4.39)
			gun.rotation.y = PI*.5
		_part(root,"CabinetTop",Vector3(3.6,.08,.32),Vector3(x,2.19,-4.68),WOOD)
		_part(root,"StockCabinet",Vector3(1.25,1.45,.45),Vector3(side*2.25,.73,-4.5),METAL)
		for row in 3:
			_part(root,"StockShelf",Vector3(1.3,.06,.52),Vector3(side*2.25,.18+row*.43,-4.46),WOOD)
			for col in 3:
				var point := Vector3(side*2.25-.39+col*.39,.34+row*.43,-4.42)
				_part(root,"AmmoCarton",Vector3(.31,.25,.28),point,Color("b1a07a") if row%2==0 else Color("6d795c"))
				_part(root,"AmmoCartonBand",Vector3(.31,.045,.29),point,RED)

static func _counter(root: Node3D) -> void:
	_part(root,"CounterPlinth",Vector3(5.02,.12,1.1),Vector3(0,.06,-2.2),METAL)
	_part(root,"CounterCabinet",Vector3(5,.62,1.08),Vector3(0,.41,-2.2),WOOD)
	for x in [-1.68,0,1.68]:
		_part(root,"CounterFrontPanel",Vector3(1.52,.42,.025),Vector3(x,.43,-1.645),Color("84735a"))
	_part(root,"CounterFelt",Vector3(4.98,.05,1.1),Vector3(0,.75,-2.2),FELT)
	# Reaproveita o shader de vidro do kit; não precisa de luz extra nem efeito animado.
	if _counter_glass == null:
		_counter_glass = StandardMaterial3D.new()
		_counter_glass.albedo_color = Color(.62,.78,.74,.12)
		_counter_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_counter_glass.roughness = .28
		_counter_glass.get_rid()
	var glass := _counter_glass
	for x in [-2.53,2.53]:
		var end := _part(root,"CounterGlassEnd",Vector3(.025,.32,1.1),Vector3(x,.91,-2.2),METAL)
		end.material_override = glass
	var front := _part(root,"CounterGlassFront",Vector3(5.08,.32,.025),Vector3(0,.91,-1.65),METAL)
	front.material_override = glass
	var top := _part(root,"CounterGlassTop",Vector3(5.16,.035,1.18),Vector3(0,1.08,-2.2),METAL)
	top.material_override = glass
	for z in [-2.78,-1.62]:
		_part(root,"CounterEdge",Vector3(5.16,.055,.045),Vector3(0,1.08,z),METAL)
	for x in [-2.56,2.56]:
		_part(root,"CounterEdge",Vector3(.045,.38,1.15),Vector3(x,.91,-2.2),METAL)
	for i in 3:
		var gun := Node3D.new()
		gun.name = "CounterWeapon"
		root.add_child(gun)
		ART.item(gun,["pistol","magnum","sawed_off"][i])
		gun.position = Vector3(-1.6+i*1.6,.81,-2.02)
		gun.rotation = Vector3(0,PI*.5,PI*.5)
	_part(root,"RegisterBase",Vector3(.48,.08,.40),Vector3(1.85,1.15,-2.2),METAL)
	_part(root,"RegisterScreen",Vector3(.40,.27,.065),Vector3(1.85,1.31,-2.35),METAL)
	_part(root,"RegisterDisplay",Vector3(.32,.18,.012),Vector3(1.85,1.32,-2.31),Color("72958a"))

static func _side_displays(root: Node3D) -> void:
	for side in [-1,1]:
		var x: float = side*5.5
		_part(root,"SideDisplayBase",Vector3(1.55,.85,2.9),Vector3(x,.425,.5),WOOD)
		_part(root,"SideDisplayTop",Vector3(1.65,.08,3),Vector3(x,.90,.5),METAL)
		# Low display trays preserve visibility across the customer floor.
		for i in 3:
			var z := -.3+i*.85
			_part(root,"DisplayTray",Vector3(1.20,.035,.68),Vector3(x,.96,z),FELT)
			var stock := Node3D.new()
			stock.name = "ArmorDisplay" if side<0 else "GrenadeDisplay"
			root.add_child(stock)
			ART.item(stock,"armor" if side<0 else "grenade")
			stock.position = Vector3(x,1.23 if side<0 else 1.08,z)
			if side < 0: stock.rotation.x = -PI*.35
		# Cases all stay inside the authored stock footprint.
		for i in 3:
			var z := 2.5+i*.46
			_part(root,"StockCase",Vector3(.8,.26,.40),Vector3(x,.13,z),Color("505c49"))
			_part(root,"CaseHandle",Vector3(.22,.035,.04),Vector3(x,.23,z+.205),METAL)
