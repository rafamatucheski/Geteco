extends Node3D
## Lived-in disorder for the Vértice office (company-local metres, office bay
## x28..42, z0..30). Paper piles, open boxes, a jammed printer and knocked
## chairs, all static and batched per material like the site dressing.
## Kept clear: the x35 door walk, the z8 warehouse passage, the clerks' routes
## (x31/x38.5 at z6, x30.5 at z8) and the hidden envelope at (35, 3).
var solids: Array[StaticBody3D] = []
var _materials := {}
var _batches := {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	name = "VerticeOfficeClutter"
	_rng.seed = 280926
	_desks()
	_floor_mess()
	_printer_corner()
	_walls()
	_flush()

func set_region_active(active: bool) -> void:
	visible = active
	for body in solids: body.collision_layer = 1 if active else 0

func _desks() -> void:
	for z in [14.0,21.0]:
		# Loose, skewed paper piles and folders over the whole desk top.
		for spot in [Vector2(38.25,z+.3),Vector2(40.55,z+.4),Vector2(38.4,z-.45)]:
			_paper_pile(Vector3(spot.x,.81,spot.y),_rng.randi_range(4,9))
		_box(Vector3(40.7,.83,z-.1),Vector3(.32,.03,.24),"folder_red",Vector3(0,.5,0))
		_box(Vector3(40.72,.86,z-.08),Vector3(.3,.03,.23),"folder_blue",Vector3(0,.2,0))
		_mug(Vector3(38.05,.81,z+.05))
		_mug(Vector3(40.95,.81,z+.55))
		# Sticky notes around the monitor bezel.
		for i in 4:
			_box(Vector3(38.95+i*.22,1.45+(i%2)*.05,z-.29),Vector3(.08,.08,.004),"sticky" if i%3 else "sticky_pink",Vector3(0,0,_rng.randf_range(-.3,.3)))
		# Cables hanging behind the desk and an overflowing bin beside it.
		_box(Vector3(39.5,.45,z-.72),Vector3(.02,.75,.02),"dark",Vector3(0,0,.2))
		_bin(Vector3(37.55,0,z+.35))
	# Pizza box and a toppled binder on the rear desk.
	_box(Vector3(38.5,.84,21.2),Vector3(.5,.05,.5),"carton",Vector3(0,.35,0))
	_box(Vector3(40.4,.87,21.25),Vector3(.32,.06,.26),"folder_blue",Vector3(0,-.6,1.4))
	# A spare rolling chair left askew in the free west bay.
	_chair(Vector3(31.3,0,16.4),.8)
	_chair(Vector3(31.6,0,22.4),-1.9)

func _floor_mess() -> void:
	# Archive boxes against the rear wall and in corners, some lids off.
	_box_stack(Vector3(29.4,0,1.3),3,.1)
	_box_stack(Vector3(30.7,0,1.1),2,-.15)
	_box_stack(Vector3(32.0,0,1.4),1,.35,true)
	_box_stack(Vector3(40.9,0,27.4),2,.2)
	_box_stack(Vector3(39.6,0,28.3),1,-.4,true)
	_box_stack(Vector3(41.0,0,8.3),2,.05)
	# Loose sheets on the floor: flat, no collision.
	for area in [Rect2(28.6,.6,4.5,3.5),Rect2(36.6,12.5,4.6,3),Rect2(36.6,19.5,4.6,3.2),Rect2(38.5,25,3,3)]:
		for i in 7:
			var p := Vector3(_rng.randf_range(area.position.x,area.end.x),.022+i*.001,_rng.randf_range(area.position.y,area.end.y))
			_box(p,Vector3(.21,.003,.297),"paper_white",Vector3(0,_rng.randf_range(0,TAU),0))
	# Crumpled balls that missed the bins.
	for p in [Vector3(37.9,.05,15.2),Vector3(37.2,.05,14.9),Vector3(37.8,.05,22.3),Vector3(36.9,.05,21.6),Vector3(33.2,.05,2.1)]:
		_ball(p)
	# Coat dropped on the waiting bench and a backpack on the floor.
	_box(Vector3(29.2,.9,24.2),Vector3(.55,.12,.9),"coat",Vector3(.2,.3,0))
	_box(Vector3(29.9,.2,26.9),Vector3(.4,.4,.25),"folder_blue",Vector3(0,.4,.15))

func _printer_corner() -> void:
	# West wall printer on a cabinet, paper jam spilling out, toner boxes.
	var at := Vector3(29.0,0,11.8)
	_box(at+Vector3(0,.4,0),Vector3(1.0,.8,.7),"cabinet")
	_box(at+Vector3(0,1.0,0),Vector3(.8,.4,.6),"printer")
	_box(at+Vector3(0,1.22,-.05),Vector3(.62,.04,.45),"dark")
	_box(at+Vector3(.47,1.05,0),Vector3(.2,.02,.3),"paper_white",Vector3(0,0,-.5))
	_paper_pile(at+Vector3(-.2,1.24,.05),6)
	_box(at+Vector3(.4,.14,.55),Vector3(.45,.28,.35),"carton",Vector3(0,.3,0))
	_box(at+Vector3(-.3,.14,.6),Vector3(.45,.28,.35),"carton",Vector3(0,-.2,0))
	_solid(at+Vector3(0,.6,.1),Vector3(1.1,1.2,.95))

func _walls() -> void:
	# Whiteboard on the rear wall with scribbles and a crooked calendar.
	_box(Vector3(35.8,1.7,.24),Vector3(2.6,1.2,.04),"board")
	_box(Vector3(35.8,1.7,.22),Vector3(2.7,1.3,.03),"dark")
	for i in 9:
		var p := Vector3(34.8+_rng.randf_range(0,2.0),1.35+_rng.randf_range(0,.7),.265)
		_box(p,Vector3(_rng.randf_range(.25,.7),.018,.004),"ink_blue" if i%3 else "ink_red",Vector3(0,0,_rng.randf_range(-.4,.4)))
	for i in 5:
		_box(Vector3(34.7+i*.5,2.28,.265),Vector3(.1,.1,.004),"sticky",Vector3(0,0,_rng.randf_range(-.25,.25)))
	_box(Vector3(39.6,1.9,.24),Vector3(.5,.65,.02),"paper_white",Vector3(0,0,.12))
	_box(Vector3(39.6,2.15,.25),Vector3(.5,.14,.01),"folder_red",Vector3(0,0,.12))
	# Papers pinned sideways over the notice boards.
	for z in [10.6,11.2,22.3,23.2]:
		_box(Vector3(41.68,1.75+_rng.randf_range(-.2,.2),z),Vector3(.004,.3,.21),"paper_white",Vector3(_rng.randf_range(-.4,.4),0,0))

func _paper_pile(at: Vector3, sheets: int) -> void:
	var yaw := _rng.randf_range(-.5,.5)
	for i in sheets:
		yaw += _rng.randf_range(-.18,.18)
		var p := at+Vector3(_rng.randf_range(-.03,.03),.006+i*.012,_rng.randf_range(-.03,.03))
		_box(p,Vector3(.21,.01,.297),"paper_white" if i%4 else "paper",Vector3(0,yaw,0))

func _mug(at: Vector3) -> void:
	_cylinder(at+Vector3(0,.055,0),.045,.11,"mug")
	_cylinder(at+Vector3(0,.108,0),.038,.004,"coffee")

func _ball(at: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = .05
	mesh.height = .09
	mesh.radial_segments = 6
	mesh.rings = 3
	_append(mesh,at,"paper_white",Vector3(_rng.randf(),_rng.randf(),0))

func _bin(at: Vector3) -> void:
	_cylinder(at+Vector3(0,.2,0),.17,.4,"dark")
	for i in 5:
		_ball(at+Vector3(_rng.randf_range(-.08,.08),.4+i*.03,_rng.randf_range(-.08,.08)))

func _chair(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP,yaw)
	_box(at+basis*Vector3(0,.47,0),Vector3(.5,.08,.48),"chair",Vector3(0,yaw,0))
	_box(at+basis*Vector3(0,.82,.24),Vector3(.48,.6,.06),"chair",Vector3(-.12,yaw,0))
	_cylinder(at+Vector3(0,.24,0),.03,.42,"steel")
	for i in 5:
		var arm := Basis(Vector3.UP,yaw+i*TAU/5)
		_box(at+arm*Vector3(0,.05,.17),Vector3(.05,.04,.34),"dark",Vector3(0,yaw+i*TAU/5,0))
	_solid(at+Vector3(0,.5,0),Vector3(.6,1.0,.6))

func _box_stack(at: Vector3, count: int, yaw: float, open := false) -> void:
	for i in count:
		var turn := yaw+_rng.randf_range(-.12,.12)
		var p := at+Vector3(_rng.randf_range(-.05,.05),.17+i*.34,_rng.randf_range(-.05,.05))
		_box(p,Vector3(.62,.33,.44),"carton",Vector3(0,turn,0))
		if open and i == count-1:
			_paper_pile(p+Vector3(0,.12,0),5)
			_box(p+Vector3(.32,.1,0),Vector3(.02,.3,.44),"carton",Vector3(0,turn,-.9))
		else:
			_box(p+Vector3(0,.166,0),Vector3(.64,.02,.46),"carton_lid",Vector3(0,turn,0))
	_solid(at+Vector3(0,count*.17,0),Vector3(.7,count*.34,.55))

func _material(key: String) -> Material:
	if _materials.has(key): return _materials[key]
	var colors := {"paper_white":"e9e6dc","paper":"cfc3a2","folder_red":"a8433a","folder_blue":"3e6690",
		"mug":"ece7dc","coffee":"3b2618","sticky":"f0dc5a","sticky_pink":"ec8db0","dark":"252d2e",
		"carton":"a9865a","carton_lid":"b8966a","chair":"2f3b44","steel":"69767a","coat":"4a4f38",
		"cabinet":"8b9491","printer":"d7d6cf","board":"f1f1ec","ink_blue":"2a4f9c","ink_red":"b53a2f"}
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(colors.get(key,"ffffff"))
	material.roughness = .8
	_materials[key] = material
	return material

func _box(at: Vector3, size: Vector3, key: String, angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh,at,key,angles)

func _cylinder(at: Vector3, radius: float, height: float, key: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	_append(mesh,at,key,Vector3.ZERO)

func _append(mesh: Mesh, at: Vector3, key: String, angles: Vector3) -> void:
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = surface
	(_batches[key] as SurfaceTool).append_from(mesh,0,Transform3D(Basis.from_euler(angles),at))

func _solid(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "OfficeClutterSolid"
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id","vertice/clutter/"+str(solids.size()))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	solids.append(body)

func _flush() -> void:
	for key in _batches:
		var instance := MeshInstance3D.new()
		instance.name = "OfficeClutter_"+key
		instance.mesh = (_batches[key] as SurfaceTool).commit()
		instance.material_override = _material(key)
		add_child(instance)
	_batches.clear()
