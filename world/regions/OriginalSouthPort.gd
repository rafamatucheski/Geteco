extends RefCounted
## Production source: HarborSouthPort, HarborSouthPortLayout and HarborPortDressing.
## Reuses the original meshes without the V1 per-object viewport/camera.
const L := preload("res://world/regions/OriginalSouthPortLayout.gd")
const MODEL := preload("res://assets/regions/source/world/harbor/HarborPortModel3D.gd")
const PORT_SHIP_DRESSING := preload("res://world/regions/PortShipDressing3D.gd")
const SCALE := 1.0/16.0
const CARGO := [Vector2(3890,4010),Vector2(4470,4250),Vector2(5030,4250),Vector2(5380,4250),Vector2(4180,4870),Vector2(4740,4870),Vector2(5290,4870),Vector2(5520,4825),Vector2(4180,5410),Vector2(4650,5420),Vector2(5190,5420),Vector2(5830,4840)]
const MASTS := [Vector2(3650,3400),Vector2(4550,3470),Vector2(5450,3470),Vector2(3860,4270),Vector2(5590,4280),Vector2(3860,4880),Vector2(5570,4930),Vector2(5520,5700)]

static func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var buildings := [L.WAREHOUSES[0],L.WAREHOUSES[1],Rect2(3400,4050,210,180),Rect2(3370,5130,200,270),Rect2(3420,3390,85,90)]
	for i in buildings.size():
		result.append(_record("PortBuilding%d"%i,"office" if i in [2,4] else "warehouse",buildings[i],i))
	result.append(_record("SantaMareCargo3D","ship_cargo",L.SHIP_CARGO,0))
	result.append(_record("SantaMareWheelhouse3D","office",L.WHEELHOUSE,2))
	for i in L.CRANES.size():
		var base: Vector2 = L.CRANES[i]
		result.append(_record("QuaysideCrane3D%d"%i,"crane",Rect2(base+Vector2(-35,-360),Vector2(240,410)),i))
	for i in 6:
		result.append(_record("PalletsAndDrums3D%d"%i,"supplies",Rect2(3970+(i%3)*550,4900 if i<3 else 5420,130,55),i))
	for i in CARGO.size(): result.append(_record("LooseCargo%d"%i,"loose_cargo",Rect2(CARGO[i],Vector2(110,65)),i))
	for i in MASTS.size(): result.append(_record("PortFloodlight%d"%i,"floodlight",Rect2(MASTS[i]-Vector2(36,12),Vector2(72,24)),i))
	return result

static func _record(id: String, model_kind: String, footprint: Rect2, variant: int) -> Dictionary:
	var center := footprint.get_center()*SCALE
	return {"kind":"south_port_model","id":id,"model_kind":model_kind,"footprint":footprint,"variant":variant,"position":Vector3(center.x,0,center.y)}

static func mount(parent: Node3D, record: Dictionary) -> Node3D:
	var art := MODEL.new()
	art.name = record.id
	art.position = record.position
	# V1 HarborPortModelView: PPM=20, floor projection=.8. Preserve ground footprint.
	art.scale = Vector3(20.0/16.0,1.0,20.0*.8/16.0)
	parent.add_child(art)
	var footprint: Rect2 = record.footprint
	art.build(record.model_kind,footprint.size.x/20.0,footprint.size.y/20.0/.8,int(record.variant))
	art.set_meta("source_id","world/harbor/HarborSouthPort.gd:"+str(record.id))
	# Collision follows final batched meshes, including crane legs rather than its whole AABB.
	for mesh in art.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		mesh.create_trimesh_collision()
		for body in mesh.get_children():
			if body is StaticBody3D:
				body.collision_layer = 1
				body.collision_mask = 0
	if record.model_kind == "floodlight":
		art.add_to_group(&"city_local_light_source")
		art.set_meta("local_light", {"offset":Vector3(0,8.3,0),"range":20.0,"energy":14.0,"color":Color("ffc078"),"camera_safe":true})
		var lamp_material: StandardMaterial3D = art.material("e5eff4")
		lamp_material.emission_enabled = true
		lamp_material.emission = Color("ffd09a")
		lamp_material.emission_energy_multiplier = .8
	if record.model_kind == "crane":
		var rigging := PORT_SHIP_DRESSING.new()
		art.add_child(rigging)
		rigging.build_south_crane(footprint.size.x/20.0,footprint.size.y/20.0/.8)
	return art

static func extra_surfaces() -> Array[PackedVector2Array]:
	# LAND is already owned by OriginalWorldData. Access shoulders and piers were missing.
	var result: Array[PackedVector2Array] = [L.rect_polygon(L.WALKWAY),L.ship_hull(),L.rect_polygon(L.SHIP_GANGWAY)]
	for pier in L.PIERS: result.append(L.rect_polygon(pier))
	result.append_array(Geometry2D.offset_polyline(PackedVector2Array(L.ACCESS),L.ACCESS_LAND_HALF_WIDTH,Geometry2D.JOIN_ROUND,Geometry2D.END_SQUARE))
	return result

static func rails() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var hull := L.ship_hull()
	for i in hull.size():
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i+1)%hull.size()]
		if i == 5:
			result.append(PackedVector2Array([a,Vector2(L.SHIP_GANGWAY.end.x,3120)]))
			result.append(PackedVector2Array([Vector2(L.SHIP_GANGWAY.position.x,3120),b]))
		else: result.append(PackedVector2Array([a,b]))
	for x in [4214,4282]: result.append(PackedVector2Array([Vector2(x,3120),Vector2(x,3250)]))
	return result
