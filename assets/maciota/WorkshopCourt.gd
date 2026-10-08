extends Node3D
## Static fenced service court. Its open frontage connects to Quay Boulevard.
## The M8 parks west of the shell, clear of traffic and the main bay.
const KIT := preload("res://world/city_look/CityPropKit.gd")

func _ready() -> void:
	name = "WorkshopCourt"
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	var body := StaticBody3D.new()
	body.name = "CourtBoundary"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	# The rear boundary steps around FreightOffice (east edge x166.40625,
	# south edge z99.6875). The front stays open across the 111m service corridor.
	for spec in [
		[Vector3(-15.25,.74,-.15),Vector3(.16,1.48,1.1)],
		# A 2.6m pedestrian gate meets FreightOffice's east entrance without
		# crossing the M8 parking bay at x=-10.5.
		[Vector3(-11.525,.74,-.7),Vector3(7.45,1.48,.16)],
		[Vector3(-3.10,.74,-.7),Vector3(4.20,1.48,.16)],
		[Vector3(-1.0,.74,-2.5),Vector3(.16,1.48,3.6)],
		[Vector3(4.5,.74,-4.3),Vector3(11.0,1.48,.16)],
		[Vector3(10.0,.74,.6),Vector3(.16,1.48,9.8)],
	]:
		KIT.box(t,spec[0],spec[1],Color("4e5a59"))
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[1]
		collision.shape = shape
		collision.position = spec[0]
		body.add_child(collision)
	for x in [-1.0,3.5,7.5,10.0]:
		_post(t,body,Vector3(x,.90,-4.3))
	for x in [-15.25,-11.0,-7.9,-5.1,-2.0,-1.0]:
		_post(t,body,Vector3(x,.90,-.7))
	for z in [.4]:
		_post(t,body,Vector3(-15.25,.90,z))
	# Painted parking edges and a stop line only: no slabs stacked on the lot.
	for x in [-12.3,-8.7]:
		KIT.box(t,Vector3(x,.03,2.9),Vector3(.075,.012,6.2),Color("c5aa66"))
	KIT.box(t,Vector3(-10.5,.03,-.22),Vector3(3.65,.012,.075),Color("c5aa66"))
	# Rear service lane remains a continuous foot path alongside the salvage.
	for x in [5.8,6.7,7.6]:
		KIT.box(t,Vector3(x,.032,-2.2),Vector3(.4,.012,.075),Color("b4b3a1"))
	t.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = "CourtStructure"
	visual.mesh = t.commit()
	visual.material_override = KIT.material()
	add_child(visual)

func _post(tool: SurfaceTool, body: StaticBody3D, point: Vector3) -> void:
	var size := Vector3(.18,1.8,.18)
	KIT.box(tool,point,size,Color("273638"))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = point
	body.add_child(collision)
