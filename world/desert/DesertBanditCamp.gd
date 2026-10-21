extends RefCounted
## A small occupied desert shelter. Shared terrain remains the only floor.
const G := preload("res://world/desert/DesertGeometry.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const CENTER := Vector3(-1110,0,-1000)
const POSITION := CENTER
const FOOTPRINT := Rect2(-1121,-1011,22,22)
const POSTS := [Vector3(-4,0,3),Vector3(2,0,1),Vector3(5,0,-4)]

static func reserved(point: Vector2, radius := 0.0) -> bool:
	return FOOTPRINT.grow(radius+2.0).has_point(point)

static func ground(point: Vector3) -> Vector3:
	return Vector3(point.x,HM.surface_height(Vector2(point.x,point.z)),point.z)

static func build() -> Node3D:
	var root := Node3D.new()
	root.name="RemoteBanditCamp"
	root.position=ground(CENTER)
	# An open canvas shelter, a bedroll and water stores read as temporary habitation.
	for x in [-7.0,-1.5]:
		for z in [-7.0,-3.0]:
			G.cylinder(root,"CanvasPole",Vector3(x,1.35,z),.065,2.7,Color("74634b"),true)
	var canvas := G.quad(root,"WeatheredCanvas",PackedVector3Array([
		Vector3(-7.35,2.65,-7.3),Vector3(-1.2,2.5,-7.3),Vector3(-1.2,2.3,-2.7),Vector3(-7.35,2.5,-2.7)
	]),G.material(Color("827557")),false)
	canvas.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	G.box(root,"Bedroll",Vector3(-5,.11,-5),Vector3(.82,.22,1.85),Color("625e49"))
	G.cylinder(root,"RolledBlanket",Vector3(-5,.26,-5.75),.22,.83,Color("72684c")).rotation.z=PI*.5
	for row in [Vector3(5,.48,5),Vector3(6.15,.48,5),Vector3(5,1.38,5)]:
		var crate := G.box(root,"SupplyCrate",row,Vector3(1.05,.9,.9),Color("786347"),true)
		for x in [-.42,.42]: G.box(crate,"IronStrap",Vector3(x,0,0),Vector3(.07,.92,.92),Color("494c45"))
	for offset in [Vector3(3.2,0,5.2),Vector3(3.1,0,6.3)]:
		G.cylinder(root,"WaterDrum",offset+Vector3.UP*.52,.36,1.04,Color("686e64"),true)
		for height in [.12,.88]: G.cylinder(root,"DrumRing",offset+Vector3.UP*height,.37,.045,Color("494d45"))
	G.box(root,"LowSupplyTable",Vector3(-3,.7,-6),Vector3(1.6,.12,.7),Color("79634a"),true)
	for x in [-3.65,-2.35]: G.box(root,"TableLeg",Vector3(x,.34,-6),Vector3(.1,.68,.56),Color("595449"),true)
	G.batch_repeated_meshes(root)
	return root
