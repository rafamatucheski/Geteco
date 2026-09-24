extends Node3D
class_name HarborProp3D

## Streamable native 3D translations of the productive HarborDistrict,
## HarborEastDistrict and HarborNorthDistrict prop inventories.

var definition: Dictionary
var material_cache:={}
var solids: StaticBody3D

static func records()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	# Breakwater trees, including the memorial verge and the terminal cut-outs.
	for point in [Vector2(1465,865),Vector2(1465,1025),Vector2(1460,1840),Vector2(1460,2040),Vector2(1750,1840),Vector2(1750,2040),Vector2(2040,1840),Vector2(2040,2040),Vector2(650,805),Vector2(880,805)]:
		result.append(_tree_record(point,1,1.25,"446b53","world/harbor/HarborDistrict.gd"))
	for x in [45,205]:
		for y in [1100,1640,1820,2000]: result.append(_tree_record(Vector2(x,y),2,.85,"465d3f","world/harbor/HarborDistrict.gd"))
	for point in [Vector2(1650,2070),Vector2(1920,2070)]: result.append(_record("bench",point,"world/harbor/HarborDistrict.gd"))
	var west_lamps:Array[Vector2]=[Vector2(506,508),Vector2(738,508),Vector2(506,1136),Vector2(743,1136),Vector2(1174,1136),Vector2(1465,955),Vector2(500,550),Vector2(1195,550),Vector2(2320,1390),Vector2(2890,1390)]
	for x in [650,1000,1550,1900,2450,2800]:
		for y in [315,515,1165,1335,2285]:
			var point:=Vector2(x,y)
			if x==650 and y==315: point.x=790
			if x==1550 and y==315: point.x+=70
			if x==650 and y==2285: point.x=800
			elif x==2800 and y==315: point.x=2650
			west_lamps.append(point)
	for x in [315,485,1215,1385,2115,2285]:
		for y in [850,1650,1950]:
			var point:=Vector2(2136,y) if x==2115 and y==1650 else Vector2(x,y)
			if x==1215 and y==850: point.x=1204
			west_lamps.append(point)
	for point in west_lamps: result.append(_record("lamp",point,"world/harbor/HarborDistrict.gd"))

	# Northbank source inventory.
	var east_nature := [
		[Vector2(4860,1123),1,.95,"426451"],[Vector2(4925,1122),3,.75,"65775a"],[Vector2(5340,1120),2,.85,"354f49"],
		[Vector2(5730,970),3,.9,"537366"],[Vector2(6290,970),3,1.05,"647c68"],[Vector2(4870,1685),1,.8,"506d48"],
		[Vector2(4940,1685),3,.7,"758060"],[Vector2(5320,1685),1,.85,"3f624d"],[Vector2(5920,1845),1,1.15,"4c6955"],
		[Vector2(5985,1890),3,.8,"6d7c60"],[Vector2(6260,1825),3,1.0,"527569"],[Vector2(5920,2040),2,.85,"3f5c50"],[Vector2(6250,2040),1,.85,"697c55"]]
	for item in east_nature: result.append(_tree_record(item[0],int(item[1]),float(item[2]),String(item[3]),"world/harbor/HarborEastDistrict.gd"))
	for point in [Vector2(4990,1697),Vector2(5011,1694),Vector2(5880,1935),Vector2(5896,1943),Vector2(6325,1980)]: result.append(_record("rock",point,"world/harbor/HarborEastDistrict.gd"))
	for point in [Vector2(5080,1060),Vector2(6100,1330),Vector2(5050,1330),Vector2(6100,2280),Vector2(5050,2280),Vector2(6020,480)]: result.append(_record("lamp",point,"world/harbor/HarborEastDistrict.gd"))

	# Northgate trees, causeway trees, rocks, benches and lamps.
	var north_points:=[Vector2(4835,-1518),Vector2(4900,-1522),Vector2(5360,-1520),Vector2(5750,-1530),Vector2(6310,-1530),Vector2(4830,-180),Vector2(4900,-174),Vector2(5340,-180),Vector2(5770,-178),Vector2(5840,-174),Vector2(6270,-178)]
	var north_styles:=[1,3,2,3,1,3,1,2,1,3,3]
	var north_scales:=[.8,.7,.85,.8,.85,.8,.75,.8,.85,.7,.9]
	for index in north_points.size(): result.append(_tree_record(north_points[index],north_styles[index],north_scales[index],["476456","64775d","35564b"][index%3],"world/harbor/HarborNorthDistrict.gd"))
	for point in [Vector2(4700,-2310),Vector2(5570,-2190),Vector2(5485,-2260),Vector2(6280,-2325),Vector2(6685,-2290),Vector2(4480,-1650),Vector2(4480,-700),Vector2(6620,-850)]: result.append(_tree_record(point,1,1.25,"667858","world/harbor/HarborNorthDistrict.gd"))
	var bridge_index:=0
	for x in [5729.0,6271.0]:
		for y in range(-3960,-2410,105):
			result.append(_tree_record(Vector2(x,y),2,.85+float(bridge_index%3)*.05,"476456","world/harbor/HarborNorthDistrict.gd"))
			bridge_index+=1
	for point in [Vector2(4950,-185),Vector2(4970,-190),Vector2(5910,-189),Vector2(5933,-181),Vector2(6190,-1530)]: result.append(_record("rock",point,"world/harbor/HarborNorthDistrict.gd"))
	for point in [Vector2(5080,-1535),Vector2(6090,-1540),Vector2(5030,-160),Vector2(6010,-160)]: result.append(_record("bench",point,"world/harbor/HarborNorthDistrict.gd"))
	for point in [Vector2(5000,-1920),Vector2(6100,-1920),Vector2(5000,-1030),Vector2(6100,-1030),Vector2(5050,-285),Vector2(6050,-285)]: result.append(_record("lamp",point,"world/harbor/HarborNorthDistrict.gd"))
	return result

static func _record(kind:String,point:Vector2,source:String)->Dictionary:
	return {"kind":kind,"point":point,"source_id":source}

static func _tree_record(point:Vector2,style:int,scale_factor:float,color:String,source:String)->Dictionary:
	var result:=_record("tree",point,source)
	result.style=style
	result.scale_factor=scale_factor
	result.color=color
	return result

func configure(data:Dictionary)->void:
	definition=data

func _ready()->void:
	name="Harbor%s3D"%String(definition.kind).capitalize()
	set_meta("source_id",definition.source_id)
	solids=StaticBody3D.new()
	solids.name="PropSolid"
	solids.collision_layer=1
	solids.collision_mask=0
	add_child(solids)
	match String(definition.kind):
		"tree": _tree(int(definition.style),float(definition.scale_factor),Color(definition.color))
		"rock": _rock()
		"bench": _bench()
		"lamp": _lamp()

func _tree(style:int,scale_factor:float,color:Color)->void:
	var trunk_h:=(3.0 if style!=2 else 3.6)*scale_factor
	_cylinder("TreeTrunk",.22*scale_factor,trunk_h,Vector3(0,trunk_h*.5,0),Color("66513a"),true)
	var crown_centers:=[Vector3(-.58,0,0),Vector3(.48,.20,.12),Vector3(0,.44,-.34),Vector3(.08,-.10,.58)]
	if style==2: crown_centers=[Vector3(0,.2,0),Vector3(0,.85,0),Vector3(0,1.45,0)]
	for index in crown_centers.size():
		var crown:=MeshInstance3D.new()
		crown.name="TreeCanopy"
		var mesh:=SphereMesh.new()
		mesh.radius=(1.05 if style!=2 else 1.22-index*.16)*scale_factor
		mesh.height=mesh.radius*1.8
		mesh.radial_segments=8
		mesh.rings=4
		crown.mesh=mesh
		crown.position=Vector3(0,trunk_h+.62*scale_factor,0)+(crown_centers[index] as Vector3)*scale_factor
		crown.material_override=_material(color.lightened(.06*float(index%3)))
		add_child(crown)

func _rock()->void:
	var rock:=_box("CoastalRock",Vector3(0,.42,0),Vector3(1.4,.85,1.1),Color("68736c"),true)
	rock.rotation.y=.38
	_box("RockFacet",Vector3(-.18,.76,.05),Vector3(.72,.08,.62),Color("9aa08e"))

func _bench()->void:
	_box("BenchSeat",Vector3(0,.52,0),Vector3(4.06,.18,1.18),Color("bd9b69"),true)
	_box("BenchBack",Vector3(0,.98,-.48),Vector3(4.06,.82,.14),Color("463b30"),true)
	for x in [-1.75,0.0,1.75]: _box("BenchLeg",Vector3(x,.25,0),Vector3(.16,.5,.72),Color("26221d"),true)

func _lamp()->void:
	_cylinder("StreetLampPost",.09,3.2,Vector3(0,1.6,0),Color("3f4745"),true)
	_box("StreetLampArm",Vector3(.32,3.08,0),Vector3(.65,.08,.08),Color("3f4745"))
	_box("StreetLampHead",Vector3(.62,2.98,0),Vector3(.48,.18,.38),Color("d3b487"))

func _box(label:String,point:Vector3,size:Vector3,color:Color,solid:=false)->MeshInstance3D:
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=BoxMesh.new()
	mesh.size=size
	item.mesh=mesh
	item.position=point
	item.material_override=_material(color)
	add_child(item)
	if solid: _solid(point,size)
	return item

func _cylinder(label:String,radius:float,height:float,point:Vector3,color:Color,solid:=false)->void:
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=height
	mesh.radial_segments=10
	item.mesh=mesh
	item.position=point
	item.material_override=_material(color)
	add_child(item)
	if solid: _solid(point,Vector3(radius*1.7,height,radius*1.7))

func _solid(point:Vector3,size:Vector3)->void:
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	collider.position=point
	solids.add_child(collider)

func _material(color:Color)->StandardMaterial3D:
	var key:=color.to_html(true)
	if material_cache.has(key): return material_cache[key]
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=.9
	material_cache[key]=material
	return material
