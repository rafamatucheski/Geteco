extends RefCounted
## Duas ruínas externas contínuas: sem troca de cômodo, paredes invisíveis ou fade de teto.
## A região é dona do streaming e reserva estas áreas antes de espalhar a areia.
const G := preload("res://world/desert/DesertGeometry.gd")
const MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")
const POSITION := Vector3(-1160,0.0,-1080)
const CABIN_POSITION := Vector3(-1195,0.0,-1074)
const HOUSE_ID := "desert_abandoned_house"
const CABIN_ID := "desert_abandoned_cabin"
const HOUSE_RECT := Rect2(-1166,-1085,12.0,13.0)
const CABIN_RECT := Rect2(-1199,-1078,10.0,9.0)
const PATH := [Vector2(-1148,-1060),Vector2(-1158,-1068),Vector2(-1160,-1074),Vector2(-1174,-1070),Vector2(-1185,-1072),Vector2(-1191,-1074)]

static func reservation_clear(point: Vector2, radius: float = 0.0) -> bool:
	if HOUSE_RECT.grow(radius + 2.0).has_point(point) or CABIN_RECT.grow(radius + 2.0).has_point(point):
		return false
	for i in range(1, PATH.size()):
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, PATH[i-1], PATH[i])) < radius + 3.0:
			return false
	return true

static func definitions() -> Array[Dictionary]:
	return [
		{"id":HOUSE_ID,"position":POSITION,"size":Vector2(12,13),"entry":POSITION+Vector3(0,0,5.5),"interaction":POSITION+Vector3(1.05,0,-.8),"target":POSITION+Vector3(2.5,.95,-.8),"kind":"open_ruin"},
		{"id":CABIN_ID,"position":CABIN_POSITION,"size":Vector2(6,5),"entry":CABIN_POSITION+Vector3(4,0,0),"interaction":CABIN_POSITION+Vector3(.1,0,-.4),"target":CABIN_POSITION+Vector3(-1,.3,-.9),"kind":"open_ruin"},
	]

static func build() -> Node3D:
	var site := Node3D.new()
	site.name = "DesertAbandonedSite"
	site.position = POSITION
	site.set_meta("desert_explorable_ruin", true)
	var house := _house()
	site.add_child(house)
	var cabin := _cabin()
	cabin.position = CABIN_POSITION - POSITION
	site.add_child(cabin)
	# Areia achatada marca uma rota antiga, mas o chão regional contínuo é dono do
	# apoio físico. Nenhuma laje elevada ou emenda de colisão cruza a entrada.
	for i in range(1, PATH.size()):
		var a: Vector2 = PATH[i-1] - Vector2(POSITION.x, POSITION.z)
		var b: Vector2 = PATH[i] - Vector2(POSITION.x, POSITION.z)
		var direction := (b-a).normalized()
		var side := Vector2(-direction.y,direction.x)*1.15
		G.quad(site,"WornPath",PackedVector3Array([Vector3(a.x-side.x,.012,a.y-side.y),Vector3(a.x+side.x,.012,a.y+side.y),Vector3(b.x+side.x,.012,b.y+side.y),Vector3(b.x-side.x,.012,b.y-side.y)]),G.material(Color("b49b77"),true))
	return site

static func set_collected(site: Node3D, id: String, collected: bool) -> void:
	if not is_instance_valid(site): return
	var path := "House/SecretContents" if id == HOUSE_ID else "Cabin/CabinContents"
	var contents := site.get_node_or_null(path) as Node3D
	if is_instance_valid(contents): contents.visible = not collected

static func _house() -> Node3D:
	var room := Node3D.new()
	room.name = "House"
	room.set_meta("desert_place_id",HOUSE_ID)
	_floor(room,Vector2(9,7))
	# Casca de adobe: fundo e oeste continuam altos; frente/leste quebrados mantêm uma
	# linha de visão de cima livre sem esconder paredes físicas do jogador.
	_part(room,"RearAdobe",Vector3(0,1.4,-3.5),Vector3(9,2.8,.36),"adobe")
	_part(room,"WestAdobe",Vector3(-4.5,1.3,0),Vector3(.36,2.6,7),"adobe")
	_part(room,"EastRearAdobe",Vector3(4.5,1.15,-2.25),Vector3(.36,2.3,2.5),"adobe")
	_part(room,"EastBrokenBase",Vector3(4.5,.35,2.7),Vector3(.42,.7,1.6),"adobe")
	for side in [-1.0,1.0]:
		_part(room,"FrontBrokenAdobe",Vector3(side*2.9,.57,3.5),Vector3(3.2,1.14,.4),"adobe")
		_part(room,"DoorJamb",Vector3(side*1.25,1.2,3.5),Vector3(.24,2.4,.48),"wood")
	_part(room,"DoorLintel",Vector3(0,2.5,3.5),Vector3(2.8,.24,.48),"wood")
	# O teto que sobrou cobre só o canto traseiro esquerdo. Os caibros são sólidos no alto
	# nas alturas reais, não bloqueios do piso inteiro nem recortes só de apresentação.
	_part(room,"RoofCorner",Vector3(-2.8,2.76,-2.5),Vector3(3.7,.16,2.0),"roof")
	for x in [-4.2,-3.3,-2.4,-1.5]:
		_part(room,"BrokenRafter",Vector3(x,2.62,-1.9),Vector3(.13,.18,3.0),"wood")
	_part(room,"PorchPost",Vector3(-3.8,1.32,5.1),Vector3(.19,2.64,.19),"wood")
	_part(room,"PorchBeam",Vector3(-2.7,2.65,4.4),Vector3(2.5,.19,1.7),"wood")
	for i in 7:
		_part(room,"PorchSlat",Vector3(-3.8+float(i)*.32,2.8,4.35),Vector3(.18,.08,1.65),"wood",false)
	# Complete furniture footprints, including the void under beds/tables.
	_part(room,"BedSolid",Vector3(-2.75,.28,-1.5),Vector3(1.65,.56,2.3),"wood")
	_part(room,"Mattress",Vector3(-2.75,.63,-1.5),Vector3(1.6,.16,2.2),"roof",false)
	_part(room,"FoldedBlanket",Vector3(-2.75,.74,-.87),Vector3(1.5,.07,.72),"rust",false)
	_part(room,"Pillow",Vector3(-2.75,.76,-2.22),Vector3(1.02,.14,.36),"cream",false)
	_part(room,"TableSolid",Vector3(2.7,.42,-.8),Vector3(1.55,.84,.86),"wood")
	_part(room,"TableTop",Vector3(2.7,.86,-.8),Vector3(1.66,.08,.95),"wood",false)
	_part(room,"RustyChest",Vector3(2.5,1.05,-.8),Vector3(.7,.3,.48),"rust")
	_part(room,"OpenChestLid",Vector3(2.5,1.29,-1.03),Vector3(.72,.4,.045),"steel")
	var contents := Node3D.new()
	contents.name="SecretContents"
	room.add_child(contents)
	_part(contents,"Envelope",Vector3(2.46,1.22,-.76),Vector3(.25,.015,.16),"cream",false)
	_part(contents,"WaxSeal",Vector3(2.46,1.231,-.76),Vector3(.05,.008,.05),"rust",false)
	_part(contents,"Banknotes",Vector3(2.77,1.22,-.79),Vector3(.14,.035,.2),"roof",false)
	_part(room,"WaterJug",Vector3(-3.4,.36,1.7),Vector3(.42,.72,.42),"rust")
	_part(room,"Crate",Vector3(3.65,.35,-2.65),Vector3(.7,.7,.7),"wood")
	_part(room,"Stove",Vector3(-.8,.49,-2.96),Vector3(.64,.98,.48),"steel")
	_part(room,"StovePipe",Vector3(-.8,1.9,-3.0),Vector3(.15,1.85,.15),"rust")
	# Exposed brick courses and flaked plaster show abandonment without signage.
	for i in 8:
		_part(room,"ExposedBrick",Vector3(-3.85+float(i)*.43,.28,3.72),Vector3(.38,.16,.08),"rust",false)
	for i in 5:
		var fragment := _part(room,"FallenPlank",Vector3(5.8+float(i)*.16,.09,-2.8+float(i)*.62),Vector3(.26,.18,1.2),"wood")
		_rotate_solid(fragment,.32+float(i)*.27)
	_part(room,"DetachedDoor",Vector3(-5.3,.62,1.0),Vector3(.12,1.24,1.7),"wood")
	MATERIALS.batch_visuals(room)
	return room

static func _cabin() -> Node3D:
	var room := Node3D.new()
	room.name="Cabin"
	room.set_meta("desert_place_id",CABIN_ID)
	_floor(room,Vector2(5,4))
	_part(room,"RearCabin",Vector3(-2.5,1.12,0),Vector3(.16,2.24,4),"wood")
	_part(room,"NorthCabin",Vector3(0,1.0,-2),Vector3(5,2,.16),"wood")
	_part(room,"SouthBrokenCabin",Vector3(-1.2,.5,2),Vector3(2.6,1,.16),"wood")
	for z in [-1.9,1.9]:
		_part(room,"CabinPost",Vector3(2.4,1.12,z),Vector3(.16,2.24,.16),"wood")
	_part(room,"CabinRoofRemnant",Vector3(-1.7,2.32,0),Vector3(1.8,.13,4.4),"rust")
	for z in [-1.85,-.6,.65,1.9]:
		_part(room,"CabinRafter",Vector3(-.8,2.23,z),Vector3(3.5,.15,.13),"wood")
	_part(room,"CabinCot",Vector3(-1.35,.28,.45),Vector3(.9,.56,1.9),"wood")
	_part(room,"CabinBedding",Vector3(-1.35,.61,.45),Vector3(.86,.1,1.86),"roof",false)
	_part(room,"CabinCache",Vector3(-1,.19,-.9),Vector3(.56,.38,.4),"steel")
	var contents := Node3D.new()
	contents.name="CabinContents"
	room.add_child(contents)
	_part(contents,"CashRoll",Vector3(-1,.4,-.9),Vector3(.2,.03,.13),"cream",false)
	for i in 9:
		_part(room,"CabinWeatheredSlat",Vector3(-2.6,.18+float(i)*.24,0),Vector3(.06,.035,4.03),"rust",false)
	MATERIALS.batch_visuals(room)
	return room

static func _floor(parent: Node3D, size: Vector2) -> void:
	var floor_mesh := G.box(parent,"WornFloor",Vector3(0,.002,0),Vector3(size.x,.006,size.y),Color("ad987c"))
	floor_mesh.material_override=MATERIALS.material("stone")
	floor_mesh.set_meta("walkable_floor",true)

static func _part(parent: Node3D, id: String, at: Vector3, size: Vector3, finish: String, solid: bool = true) -> MeshInstance3D:
	var visual := G.box(parent,id,at,size,Color.WHITE)
	visual.material_override=MATERIALS.material(finish)
	if solid:
		var body := StaticBody3D.new()
		body.name=id+"Solid"
		body.position=at
		body.collision_layer=1
		body.collision_mask=0
		body.set_meta("interior_solid_id",id)
		var shape := BoxShape3D.new()
		shape.size=size
		var collision := CollisionShape3D.new()
		collision.shape=shape
		body.add_child(collision)
		parent.add_child(body)
		visual.set_meta("physical_body",body)
	return visual

static func _rotate_solid(visual: MeshInstance3D, yaw: float) -> void:
	visual.rotation.y=yaw
	if visual.has_meta("physical_body"):
		var body: Node3D=visual.get_meta("physical_body")
		body.rotation.y=yaw
