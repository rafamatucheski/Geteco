extends Node3D
class_name HarborBridge3D

## Native 3D translation of world/harbor/HarborBridge.gd. The road system owns
## asphalt and markings; this model owns the deck structure, edge rails,
## cable-stayed pylons, fixtures and physical containment.

const SCALE:=1.0/16.0
const SOURCE_CENTER:=Vector2(3790,400)
var materials:={}
var solid_root: StaticBody3D

func _ready()->void:
	name="FoundryBridge3D"
	set_meta("source_id","world/harbor/HarborBridge.gd")
	solid_root=StaticBody3D.new()
	solid_root.name="BridgeStructureSolids"
	solid_root.collision_layer=1
	solid_root.collision_mask=0
	add_child(solid_root)
	_build_deck()
	_build_pylons_and_stays()
	_build_luminaires()
	_build_abutment()

func _build_deck()->void:
	# V1 deck 3200..4380 x 298..502, centred on this node.
	# Keep the slab below HarborRoadGeometry3D's asphalt; only its margins and
	# underside remain visible, as in the productive V1 layer order.
	_box("BridgeUnderside",Vector3(0,-.38,0),Vector3(1180*SCALE,.64,204*SCALE),"626e6e",true)
	_box("BridgeDeckEdge",Vector3(0,-.13,0),Vector3(1180*SCALE,.12,220*SCALE),"a7aaa0")
	for north in [true,false]:
		var z:=(-112.0 if north else 112.0)*SCALE
		_box("NorthRail" if north else "SouthRail",Vector3(0,.72,z),Vector3(1180*SCALE,1.44,.26),"5e7479",true)
		_box("RailTop",Vector3(0,1.48,z),Vector3(1180*SCALE,.10,.34),"c6d3cc")
		for source_x in range(3220,4381,40):
			var x:=(float(source_x)-SOURCE_CENTER.x)*SCALE
			_box("RailPost",Vector3(x,.74,z),Vector3(.10,1.42,.10),"3d4b4f")
	for source_x in [3208.0,3495.0,4055.0,4372.0]:
		var x:float=(float(source_x)-SOURCE_CENTER.x)*SCALE
		for z in [-6.35,6.35]: _box("ExpansionJoint",Vector3(x,.10,z),Vector3(.20,.04,.45),"445459")

func _build_pylons_and_stays()->void:
	for source_x in [3500.0,4060.0]:
		var x:float=(float(source_x)-SOURCE_CENTER.x)*SCALE
		for north in [true,false]:
			var side:float=-1.0 if north else 1.0
			var foot_z:=side*150.0*SCALE
			var rail_z:=side*114.0*SCALE
			_box("PylonFoot",Vector3(x,1.0,foot_z),Vector3(3.25,2.0,3.75),"d5ccb0",true)
			_box("PylonInset",Vector3(x,2.2,foot_z),Vector3(1.88,3.6,2.4),"829391",true)
			_box("PylonMast",Vector3(x,5.9,foot_z),Vector3(.72,7.6,.72),"d7d8c1",true)
			var top:=Vector3(x,9.7,foot_z)
			_sphere("PylonBeacon",top,.32,"e7bd78")
			for offset in [-245.0,-185.0,-125.0,-65.0,65.0,125.0,185.0,245.0]:
				var anchor_x:=clampf(source_x+offset,3208.0,4372.0)
				var anchor:=Vector3((anchor_x-SOURCE_CENTER.x)*SCALE,.9,rail_z)
				_cable("StayCable",top,anchor,.045,"b7c8c6")

func _build_luminaires()->void:
	for source_x in range(3280,4380,210):
		var x:=(float(source_x)-SOURCE_CENTER.x)*SCALE
		for north in [true,false]:
			var z:=(-112.0 if north else 112.0)*SCALE
			_box("BridgeLampPost",Vector3(x,2.15,z),Vector3(.10,2.8,.10),"465357")
			_box("BridgeLampHead",Vector3(x,3.58,z+(.28 if north else -.28)),Vector3(.46,.16,.72),"d8c994")

func _build_abutment()->void:
	var x:=(4380.0-SOURCE_CENTER.x)*SCALE
	# The old full-height box crossed the entire deck and acted as an invisible
	# wall at the east join.  The structural cap belongs below road level; only
	# the two side wings are allowed to rise beside the traversable surface.
	_box("EastAbutment",Vector3(x+1.05,-.28,0),Vector3(2.25,.56,15.6),"879496",true)
	for z in [-7.1,7.1]:
		_box("AbutmentWing",Vector3(x+.7,.9,z),Vector3(2.9,1.8,1.25),"c5cdbe",true)
	_box("AbutmentJoint",Vector3(x,.12,0),Vector3(.22,.08,15.1),"242d30")

func _box(label:String,at:Vector3,size:Vector3,hex:String,solid:=false)->MeshInstance3D:
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=BoxMesh.new()
	mesh.size=size
	item.mesh=mesh
	item.position=at
	item.material_override=_material(hex)
	add_child(item,true)
	if solid:
		var shape:=CollisionShape3D.new()
		var box_shape:=BoxShape3D.new()
		box_shape.size=size
		shape.shape=box_shape
		shape.position=at
		solid_root.add_child(shape)
	return item

func _sphere(label:String,at:Vector3,radius:float,hex:String)->void:
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=SphereMesh.new()
	mesh.radius=radius
	mesh.height=radius*2.0
	mesh.radial_segments=12
	mesh.rings=6
	item.mesh=mesh
	item.position=at
	item.material_override=_material(hex)
	add_child(item,true)

func _cable(label:String,a:Vector3,b:Vector3,radius:float,hex:String)->void:
	var delta:=b-a
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=delta.length()
	mesh.radial_segments=8
	item.mesh=mesh
	item.position=(a+b)*.5
	item.quaternion=Quaternion(Vector3.UP,delta.normalized())
	item.material_override=_material(hex)
	add_child(item,true)

func _material(hex:String)->StandardMaterial3D:
	if materials.has(hex): return materials[hex]
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(hex)
	material.roughness=.72
	material.metallic=.18 if hex in ["5e7479","c6d3cc","3d4b4f","b7c8c6"] else 0.0
	materials[hex]=material
	return material
