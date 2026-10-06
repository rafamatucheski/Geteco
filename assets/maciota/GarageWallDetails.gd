extends RefCounted
## Opaque, merged details on the three previously blank sides of both shells.
const KIT := preload("res://world/city_look/CityPropKit.gd")

static func build(parent: Node3D) -> void:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	# Local face coordinates: x runs along the wall, z points outwards.
	for spec in [[Vector3(6.1,0,1.5625), PI, 5.6, false],
		[Vector3(8.9,0,4.6875), PI/2, 6.25, false],
		[Vector3(3.3,0,4.6875), -PI/2, 6.25, false],
		[Vector3(-2,0,1.5625), PI, 7.8, true],
		[Vector3(-5.9,0,4.6875), -PI/2, 6.25, true],
		[Vector3(1.9,0,4.1875), PI/2, 5.25, true]]:
		_wall(t,spec[0],spec[1],spec[2],spec[3])
	# Roof ventilators and raised seams belong to the workshop's industrial roof.
	for x in [-4.6,-3.3,-2.0,-.7,.6]:
		KIT.box(t,Vector3(x,4.56,4.7),Vector3(.045,.045,5.8),Color("53656a"))
	for x in [-3.8,-.2]:
		KIT.box(t,Vector3(x,4.73,3.2),Vector3(.8,.35,.8),Color("4b595b"))
		KIT.box(t,Vector3(x,4.94,3.2),Vector3(.96,.10,.96),Color("9baba8"))
		for z in [2.94,3.12,3.3,3.48]:
			KIT.box(t,Vector3(x,5.005,z),Vector3(.74,.025,.06),Color("334348"))
	t.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = "GarageWallDetails"
	visual.mesh = t.commit()
	visual.material_override = KIT.material()
	parent.add_child(visual)
	# Match the textured roof finishes already used by neighbouring city buildings.
	var roofs := preload("res://world/city_look/RoofSurfaces.gd")
	for spec in [[Vector3(-2,4.548,4.6875),Vector3(7.7,.016,6.1),roofs.METAL],
		[Vector3(6.1,4.168,4.6875),Vector3(5.3,.016,5.8),roofs.METAL]]:
		var roof := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size=spec[1]
		roof.mesh=shape
		roof.position=spec[0]
		roof.material_override=roofs.material(spec[2])
		roof.name="GarageRoofFinish"
		parent.add_child(roof)

static func _part(t: SurfaceTool, origin: Vector3, yaw: float, p: Vector3, size: Vector3, color: String) -> void:
	KIT.box(t,origin+Basis(Vector3.UP,yaw)*p,size,Color(color),yaw)

static func _wall(t: SurfaceTool, origin: Vector3, yaw: float, width: float, workshop: bool) -> void:
	var trim := "aab6ae" if workshop else "d0b69a"
	var height := 4.4 if workshop else 3.8
	for y in ([.48,3.98] if workshop else [.48,3.62]):
		_part(t,origin,yaw,Vector3(0,y,.065),Vector3(width,.12,.15),trim)
	for side in [-1,1]:
		_part(t,origin,yaw,Vector3(side*(width*.5-.16),height*.5,.055),Vector3(.22,height,.13),trim)
	var count := 3 if width < 7 else 4
	for y in [2.8]:
		for i in count:
			var x := (float(i)-float(count-1)*.5)*(width-.8)/float(count)
			var h := .95 if workshop else 1.28
			_part(t,origin,yaw,Vector3(x,y,.085),Vector3(1.15,h+.18,.17),trim)
			_part(t,origin,yaw,Vector3(x,y,.182),Vector3(.96,h,.035),"283e45")
			_part(t,origin,yaw,Vector3(x-.24,y+.08,.205),Vector3(.40,h-.2,.018),"607d83")
			_part(t,origin,yaw,Vector3(x+.24,y-.04,.205),Vector3(.40,h-.14,.018),"425d66")
			_part(t,origin,yaw,Vector3(x,y,.225),Vector3(.055,h,.05),trim)
			_part(t,origin,yaw,Vector3(x,y+.12,.227),Vector3(.96,.05,.05),trim)
			_part(t,origin,yaw,Vector3(x,y-h*.5-.09,.15),Vector3(1.28,.10,.35),trim)
			if not workshop:
				_part(t,origin,yaw,Vector3(x,y+h*.5+.19,.1),Vector3(1.3,.13,.25),trim)
	# Restrained masonry joints beneath windows, above pedestrian head height.
	if workshop:
		for i in 8:
			_part(t,origin,yaw,Vector3(-width*.42+i*width*.12,3.59,.021),Vector3(.38,.025,.035),"59686a")
