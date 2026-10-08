extends RefCounted
## Focus Mk1 five-door: authored from Rauhz's reference, in metres, nose at -Z.
## Reuses fleet wheel/paint batches, boarding and equipment semantics.
const SHAPE := preload("res://gameplay/desert_cars/DesertCarModel.gd")
const CABIN := preload("res://gameplay/desert_cars/DesertCarCabin.gd")

static func create(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "RauhzFocusMK1"
	var paint := SHAPE._material(Color("101817"),.23,.48,"paint")
	var trim := SHAPE._material(Color("111519"),.65,.12,"trim")
	var glass := SHAPE._material(Color("1b3038"),.17,.38,"glass")
	var alloy := SHAPE._material(Color("c4c9cc"),.20,.82,"wheel_alloy")
	var metal := SHAPE._material(Color("abb3b6"),.27,.75,"alloy")
	var rubber := SHAPE._material(Color("14171a"),.91,0,"rubber")
	var lamp := SHAPE._material(Color("bac4c7"),.19,.42,"headlight")
	var tail := SHAPE._material(Color("b82c29"),.24,.18,"tail")
	var amber := SHAPE._material(Color("d88b32"),.3,.05,"indicator")
	SHAPE._body(root,s,paint)
	CABIN.create(root,s,paint,glass,trim)
	var w := float(s.size[0])
	var l := float(s.size[2])
	var h := float(s.size[1])
	var belt := float(s.shoulder)
	for side in [-1.0,1.0]:
		SHAPE._beam(root,"MirrorStem",Vector3(side*w*.40,belt+.04,-.80),Vector3(side*w*.50,belt+.13,-.76),.04,trim)
		SHAPE._box(root,"Mirror",Vector3(.13,.095,.19),Vector3(side*w*.515,belt+.14,-.75),paint)
		SHAPE._box(root,"MirrorGlass",Vector3(.014,.064,.135),Vector3(side*w*.554,belt+.14,-.735),metal)
		# Two real door outlines, rear quarter glass and the Mk1 rising beltline.
		for z in [l*float(s.door_back),l*.30]:
			SHAPE._box(root,"DoorHandle",Vector3(.024,.032,.15),Vector3(side*w*.486,belt-.10,z-.13),paint)
			SHAPE._box(root,"DoorSeam",Vector3(.009,.46,.008),Vector3(side*w*.482,.51,z),trim)
		SHAPE._box(root,"SideMoulding",Vector3(.018,.047,2.00),Vector3(side*w*.486,.49,0),trim)
		SHAPE._box(root,"SideSkirt",Vector3(.058,.075,1.95),Vector3(side*w*.479,.25,0),paint)
		SHAPE._box(root,"SideRepeater",Vector3(.018,.039,.10),Vector3(side*w*.485,.73,-1.04),amber)
		SHAPE._beam(root,"QuarterPillar",CABIN._side_point(s,side,1.04,belt+.04,.010),CABIN._side_point(s,side,.99,h-.15,.010),.035,trim)
		# Swept triangular headlamps wrap around the hood's pointed front corners.
		_hood_lens(root,side,paint,lamp)
		_polygon(root,"FocusHeadlightFace",[
			Vector3(side*.39,.675,-l*.496),Vector3(side*.77,.627,-l*.496),
			Vector3(side*.77,.731,-l*.496),Vector3(side*.36,.754,-l*.496)
		],Vector3.FORWARD,lamp)
		_polygon(root,"FocusLensCorner",[
			Vector3(side*.77,.627,-l*.496),Vector3(side*.77,.731,-l*.496),
			Vector3(side*.77,.800,-1.835)
		],Vector3(side,0,0),lamp)
		# High D-pillar lamps are visible from both the side and rear.
		var top := Vector3(side*.665,1.30,1.17)
		var outer := Vector3(side*.806,.83,1.83)
		var inner := Vector3(side*.68,.83,1.83)
		_polygon(root,"FocusHighTail",[top,outer,inner],Vector3(side,.3,1),tail)
		_polygon(root,"FocusTailSide",[top,Vector3(side*.765,1.23,1.29),outer],Vector3(side,.2,.5),tail)
		SHAPE._box(root,"RearReflector",Vector3(.15,.04,.017),Vector3(side*.66,.34,l*.493),tail)
		for axle in [-1.0,1.0]:
			SHAPE._arch(root,s,axle,side,paint)
			var wheel_spec := s.duplicate()
			wheel_spec.style = "gt" # Five silver spokes and low-profile road tyres.
			SHAPE._wheel(root,wheel_spec,axle,side,rubber,alloy,trim,metal)
	SHAPE._box(root,"UpperGrille",Vector3(.68,.10,.025),Vector3(0,.695,-l*.497),trim)
	SHAPE._box(root,"LowerGrille",Vector3(1.04,.125,.025),Vector3(0,.38,-l*.497),trim)
	SHAPE._box(root,"FrontBumper",Vector3(1.58,.12,.09),Vector3(0,.54,-l*.481),paint)
	SHAPE._box(root,"RearBumper",Vector3(1.58,.18,.085),Vector3(0,.44,l*.477),paint)
	SHAPE._box(root,"RearBumperStrip",Vector3(1.48,.055,.017),Vector3(0,.48,l*.489),trim)
	SHAPE._box(root,"HatchHandle",Vector3(.30,.035,.027),Vector3(0,.74,l*.491),trim)
	SHAPE._box(root,"RoofSpoiler",Vector3(1.30,.045,.17),Vector3(0,h-.092,1.12),paint)
	SHAPE._beam(root,"RoofAerial",Vector3(0,h-.01,.73),Vector3(0,h+.17,1.03),.009,trim)
	SHAPE._beam(root,"RearWiper",Vector3(.26,.89,1.80),Vector3(-.20,1.02,1.63),.016,trim)
	var plate := SHAPE._material(Color("c7cacc"),.75,0,"plate")
	for end in [-1.0,1.0]:
		SHAPE._box(root,"Plate",Vector3(.35,.105,.018),Vector3(0,.535,end*l*.499),plate)
	preload("res://gameplay/desert_cars/DesertCarWheelShape.gd").exhaust(root,Vector3(-.53,.26,2.04),metal)
	SHAPE._batch(root)
	root.set_meta("desert_body_style","hatch")
	root.set_meta("desert_edition","street")
	root.set_meta("vehicle_identity","ford_focus_mk1_2002")
	root.set_meta("vehicle_interior_spec",preload("res://gameplay/desert_cars/DesertCarInterior.gd").spec(s))
	return root

static func _hood_lens(root: Node3D,side: float,paint: Material,lamp: Material) -> void:
	# Project a subdivided swept lens onto the actual bonnet bevel, avoiding
	# both buried triangles and floating corners at its change of slope.
	var hull := PackedVector3Array()
	for part: MeshInstance3D in root.get_children():
		if part.material_override==paint and part.name=="BodyShell": hull=part.mesh.get_faces()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(side*.36,0,-2.063)
	var b := Vector3(side*.77,0,-2.063)
	var c := Vector3(side*.77,0,-1.835)
	var d := Vector3(side*.65,0,-1.835)
	_lens_triangle(st,a,b,c,hull,3)
	_lens_triangle(st,a,c,d,hull,3)
	SHAPE._mesh(root,"FocusSweptHeadlight",st,lamp)

static func _lens_triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,hull: PackedVector3Array,depth: int) -> void:
	if depth>0:
		var ab := (a+b)*.5
		var bc := (b+c)*.5
		var ca := (c+a)*.5
		_lens_triangle(st,a,ab,ca,hull,depth-1)
		_lens_triangle(st,ab,b,bc,hull,depth-1)
		_lens_triangle(st,ca,bc,c,hull,depth-1)
		_lens_triangle(st,ab,bc,ca,hull,depth-1)
		return
	var points: Array[Vector3] = []
	for p in [a,b,c]:
		var y := -INF
		for i in range(0,hull.size(),3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x,1.1,p.z),Vector3.DOWN,hull[i],hull[i+1],hull[i+2])
			if hit is Vector3: y=maxf(y,hit.y)
		assert(is_finite(y),"Focus lens must be supported by the bonnet")
		points.append(Vector3(p.x,y+.004,p.z))
	SHAPE._triangle(st,points[0],points[1],points[2],Vector3.UP)

static func _polygon(root: Node3D,label: String,points: Array,outward: Vector3,material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,points.size()-1): SHAPE._triangle(st,points[0],points[i],points[i+1],outward.normalized())
	var part := SHAPE._mesh(root,label,st,material)
	if material.resource_name=="tail": part.set_meta("coupe_damage_material_key","tail")
