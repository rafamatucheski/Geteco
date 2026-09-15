extends Node3D
## Real geometry for the port's cached orthographic model views.
const CONTAINER := preload("res://prototypes/harbor_art_pack/props/PortContainer40ft3D.gd")
var materials: Dictionary = {}
var mesh_stats: Dictionary = {}
var height := 1.0
var solid_floor_bounds: Dictionary = {}
var hoist_start := Vector3.ZERO
var hoist_end := Vector3.ZERO

func build(kind: String, width: float, depth: float, variant: int) -> void:
	match kind:
		"containers": _containers(width,depth,variant)
		"transfer_cargo":
			height = 2.91*width/12.19
			_container(Vector3.ZERO,width,depth,variant)
		"open_container": _open_container(width,depth)
		"warehouse": _warehouse(width,depth,variant)
		"office": _office(width,depth,variant)
		"supplies": _supplies(width,depth,variant)
		"loose_cargo": _loose_cargo(width,depth,variant)
		"floodlight": _floodlight()
		"ship_cargo": _ship_cargo(width,depth)
		"crane": _crane(width,depth)
	solid_floor_bounds = preload("res://world/shared/interiors/InteriorSolidProjection.gd").mesh_bounds(self)
	mesh_stats = preload("res://prototypes/harbor_art_pack/PortMeshOptimizer.gd").optimize_hierarchy(self)
	# Recompute face normals after the container's nonuniform scale and rotation.
	for batch in get_node("BatchedStaticGeometry").get_children():
		var surface := SurfaceTool.new()
		surface.create_from(batch.mesh,0)
		surface.generate_normals()
		batch.mesh = surface.commit()
		_preserve_hard_edges(batch)

func _preserve_hard_edges(batch: MeshInstance3D) -> void:
	# Average only indexed neighbours, never unrelated faces at the same position.
	var arrays: Array = batch.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var reference: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0,indices.size(),3):
		var a := indices[i]
		var b := indices[i+1]
		var c := indices[i+2]
		var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).normalized()
		if normal.dot(reference[a]+reference[b]+reference[c]) < 0: normal = -normal
		for index in [a,b,c]: normals[index] += normal
	for i in normals.size(): normals[i] = normals[i].normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	batch.mesh = mesh

func _open_container(w: float,d: float) -> void:
	height = 3.6
	box(Vector3(0,.07,0),Vector3(w,.14,d),"435254",true)
	for side in [-1,1]:
		box(Vector3(0,height*.5,side*d*.5),Vector3(w,height,.16),"ac8545",true)
		for rib in range(int(w/.45)):
			box(Vector3(-w*.5+.25+rib*.45,height*.5,side*(d*.5+.08)),Vector3(.1,height-.2,.10),"bd9b57",true)
		var door := box(Vector3(w*.5+.55,height*.5,side*(d*.5+.4)),Vector3(1.3,height,.14),"c3a461",true)
		door.rotation.y = -side*.65
	box(Vector3(-w*.5,height*.5,0),Vector3(.15,height,d),"b49450",true)
	box(Vector3(-w*.33,height,0),Vector3(w*.34,.12,d+.16),"bfa267",true)

func material(color: String, metal: bool = false) -> StandardMaterial3D:
	var key := color+str(metal)
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color)
		mat.roughness = .62 if metal else .88
		mat.metallic = .35 if metal else 0
		materials[key] = mat
	return materials[key]

func box(at: Vector3, size: Vector3, color: String, metal: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color,metal)
	node.position = at
	add_child(node)
	return node

func beam(a: Vector3,b: Vector3,thickness: float,color: String) -> void:
	var node := box((a+b)*.5,Vector3(thickness,a.distance_to(b),thickness),color,true)
	var up := (b-a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < .1: right = up.cross(Vector3.RIGHT).normalized()
	node.basis = Basis(right,up,right.cross(up)).orthonormalized()

func _container(at: Vector3,w: float,d: float,theme: int,levels: int = 1) -> void:
	var vertical := w/12.19
	for level in levels:
		var holder := Node3D.new()
		holder.position = at+Vector3(0,level*2.91*vertical,0)
		holder.scale = Vector3(w/12.19,vertical,d/2.44)
		add_child(holder)
		var cargo := CONTAINER.new()
		cargo.color_theme = (theme+level)%5
		cargo.rotation.y = PI*.5
		holder.add_child(cargo)
		# Readable corrugation at gameplay scale, using local material copies.
		for part in cargo.get_children():
			if not part is MeshInstance3D or not part.mesh is BoxMesh: continue
			var dimensions: Vector3 = part.mesh.size
			var roof_rib := is_equal_approx(dimensions.y,.03) and dimensions.z > .35
			var wall_rib := is_equal_approx(dimensions.x,.04) and dimensions.y > 2.4
			if roof_rib or wall_rib:
				part.mesh = part.mesh.duplicate()
				if roof_rib: part.mesh.size.y = .09
				else: part.mesh.size.x = .10
				var rib_key := "PortSouthCorrugation_%d" % ((theme+level)%5)
				if not materials.has(rib_key):
					var steel: StandardMaterial3D = part.material_override.duplicate()
					steel.resource_name = rib_key
					steel.albedo_color = steel.albedo_color.lightened(.12)
					materials[rib_key] = steel
				part.material_override = materials[rib_key]

func _containers(w: float,d: float,variant: int) -> void:
	var levels := 2 if variant%3 == 0 else 1
	height = 2.91*w/12.19*levels
	_container(Vector3.ZERO,w,d,variant%5,levels)
	# Shipping line plate, distinct from the corrugated steel.
	box(Vector3(-w*.20,height*.42,d*.5+.025),Vector3(w*.20,height*.18,.035),"e0d8b6")
	for i in 3: box(Vector3(-w*.26+i*w*.05,height*.42,d*.5+.05),Vector3(w*.025,height*.055,.02),"465e63")

func _warehouse(w: float,d: float,variant: int) -> void:
	height = 7.5 if w > 20 else 4.5
	var h := height-1.4
	box(Vector3(0,.25,0),Vector3(w,.5,d),"777a72")
	box(Vector3(0,h*.5,0),Vector3(w-.2,h,d-.2),"9ba7a0").set_meta("interior_solid_id", &"BuildingShell")
	box(Vector3(0,1,0),Vector3(w+.02,1.2,d+.02),"747f7d").set_meta("interior_solid_id", &"BuildingShell")
	# Raised ridge and two pitched steel roof planes.
	var rise := 1.4
	var slope := atan2(rise,d*.5)
	var roof_depth := sqrt(d*d*.25+rise*rise)
	for side in [-1,1]:
		var roof := box(Vector3(0,h+rise*.5,side*d*.25),Vector3(w+.55,.16,roof_depth+.25),"485e69" if variant == 0 else "626b65",true)
		roof.rotation.x = side*slope
		for x in range(-int(w*.5),int(w*.5)+1):
			beam(Vector3(x,h+rise,0),Vector3(x,h,side*(d*.5+.14)),.09,"a0ada8")
	box(Vector3(0,h+rise+.05,0),Vector3(w+.55,.12,.18),"c0c7b8",true)
	var count := 5 if w > 20 else 2
	for i in count:
		var x := -w*.39+float(i)*w*.78/maxf(count-1,1)
		var door_w := w*.12 if count == 5 else w*.27
		box(Vector3(x,1.65,d*.5+.035),Vector3(door_w,2.8,.09),"253f4a",true)
		for rib in 10: box(Vector3(x,.4+rib*.26,d*.5+.10),Vector3(door_w-.1,.045,.035),"728789",true)
		box(Vector3(x,.18,d*.5+.14),Vector3(door_w+.25,.36,.28),"333b3d")
		for side in [-1,1]: box(Vector3(x+side*(door_w*.5+.10),1.6,d*.5+.1),Vector3(.15,3.1,.2),"d4af53",true)
		box(Vector3(x,3.3,d*.5+.23),Vector3(door_w+.5,.16,.48),"e3d1a1",true)
	for i in 4:
		var x := -w*.32+float(i)*w*.21
		box(Vector3(x,h+.85,-d*.17),Vector3(w*.12,.12,d*.21),"9ac4c5",true)
		box(Vector3(x,h+.25,d*.32),Vector3(1.15,.65,.95),"b4bcb4",true)
		for fin in 5: box(Vector3(x-.45+fin*.22,h+.60,d*.32),Vector3(.08,.1,.75),"4c6166",true)
	for x in [-w*.5+.12,w*.5-.12]:
		for z in [-d*.5+.1,d*.5-.1]: box(Vector3(x,h*.5,z),Vector3(.22,h,.22),"c3c6b7",true)

func _office(w: float,d: float,variant: int) -> void:
	height = 4.8 if variant == 2 else 3.2
	var h := height-.3
	box(Vector3(0,h*.5,0),Vector3(w,h,d),"bac2b0").set_meta("interior_solid_id", &"BuildingShell")
	box(Vector3(0,.35,0),Vector3(w+.1,.7,d+.1),"5c6d71").set_meta("interior_solid_id", &"BuildingShell")
	box(Vector3(0,h,0),Vector3(w+.35,.25,d+.35),"4b6870",true)
	for i in maxi(2,int(w/1.5)):
		var x := -w*.4+i*w*.8/maxf(maxi(2,int(w/1.5))-1,1)
		box(Vector3(x,h*.65,d*.5+.025),Vector3(w*.1,h*.3,.06),"244653",true)
		box(Vector3(x,h*.79,d*.5+.075),Vector3(w*.105,.04,.03),"91b6b5")
	box(Vector3(0,1.15,d*.5+.03),Vector3(w*.18,2.3,.07),"3d535b",true)
	box(Vector3(0,2.45,d*.5+.15),Vector3(w*.33,.15,.4),"d2b768",true)
	box(Vector3(-w*.2,h+.3,-d*.22),Vector3(w*.28,.55,d*.22),"aab5ab",true)

func _supplies(w: float,d: float,variant: int) -> void:
	height = 2.2
	var props := [preload("res://prototypes/harbor_art_pack/props/PortPalletStack3D.gd"),preload("res://prototypes/harbor_art_pack/props/PortDrumClusterPallet3D.gd"),preload("res://prototypes/harbor_art_pack/props/PortCargoCrate3D.gd")]
	for i in 3:
		var prop: Node3D = props[(variant+i)%3].new()
		prop.position = Vector3((i-1)*w*.30,0,0)
		add_child(prop)
	box(Vector3(0,.04,0),Vector3(w,.08,d),"797f6c")

func _ship_cargo(w: float,d: float) -> void:
	height = 3
	for col in 7:
		for row in 2:
			_container(Vector3(-w*.5+w/14+col*w/7,0,d*(-.38 if row == 0 else .38)),w/7*.90,d*.21,(col+row)%5)

func _crane(w: float,d: float) -> void:
	height = 11
	var base := Vector3(-w*.4,0,d*.42)
	box(base+Vector3(0,.7,0),Vector3(3,1.4,3),"5e7374",true)
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			beam(base+Vector3(x,1,z),base+Vector3(x*.65,7,z*.65),.22,"c5a153")
	# The rear jib reaches a landing pad behind the pedestal, clear of its legs.
	var start := base+Vector3(0,7,4)
	var tip := Vector3(w*.48,8,-d*.42)
	hoist_start = start
	hoist_end = tip
	for side in [-1,1]: beam(start+Vector3(side*.45,0,0),tip+Vector3(side*.45,0,0),.18,"dfb74e")
	for i in 14:
		var a := start.lerp(tip,float(i)/14)
		var b := start.lerp(tip,float(i+1)/14)
		beam(a+Vector3(-.45,0,0),b+Vector3(.45,0,0),.10,"e4c16b")
		beam(a+Vector3(-.45,0,0),a+Vector3(.45,0,0),.09,"957b46")
	beam(start,base+Vector3(0,11,0),.25,"d2ac56")
	beam(base+Vector3(0,11,0),tip,.05,"909d9c")
	box(start+Vector3(1,-.6,.3),Vector3(1.3,1.4,1.5),"e0d1a3")
	box(start+Vector3(1,-.35,1.06),Vector3(1.1,.7,.04),"275269",true)

func _loose_cargo(w: float, d: float, variant: int) -> void:
	height = 2.8
	for i in 5:
		var x := (float(i%3)-1)*w*.27
		var z := (float(i/3)-.5)*d*.48
		var h := .65+float((variant+i)%3)*.35
		var yaw := sin(float(variant*7+i*3))*.22
		var size := Vector3(w*.22,h,d*.32)
		var crate := box(Vector3(x,h*.5+.15,z),size,"987448")
		crate.rotation.y = yaw
		for side in [-1,1]:
			var strap := box(Vector3(x+side*size.x*.30,h*.5+.15,z),Vector3(.06,h+.035,size.z+.035),"d0ae72")
			strap.rotation.y = yaw
		for slat in 3:
			box(Vector3(x+(slat-1)*size.x*.35,.08,z),Vector3(size.x*.22,.14,size.z*1.12),"66503a")
		if (variant+i)%3 == 0:
			box(Vector3(x,h+.38,z),Vector3(size.x*.8,.46,size.z*.78),"987448")

func _floodlight() -> void:
	height = 9.0
	box(Vector3(0,.16,0),Vector3(.8,.32,.8),"73818a",true)
	box(Vector3(0,4.2,0),Vector3(.18,8.4,.18),"73818a",true)
	box(Vector3(0,8.4,0),Vector3(2.9,.16,.2),"73818a",true)
	for side in [-1,1]:
		box(Vector3(side*1.0,8.4,0),Vector3(1.05,.65,.38),"303c45",true)
		box(Vector3(side*1.0,8.3,.21),Vector3(.9,.46,.04),"e5eff4")
