extends Node3D
## Six native 3D walk-in homes. Player, residents, architecture and furniture
## share one depth buffer and physical world; no sprite/projection workaround.
signal house_entered(index: int)
signal house_exited(index: int)
var homes: Array[Dictionary] = []
var occupant_points: Array[Vector3] = []
var doorway_points: Array[Vector3] = []
var outside_points: Array[Vector3] = []
var loot_points: Array[Vector3] = []
var solids: Array[StaticBody3D] = []
var furniture: Array[Dictionary] = []
var current_home := -1
var session
var player: Node3D
var interior_camera: Camera3D
var _outside_camera: Camera3D
var _previous_shelter := false
var _village: Node3D
var _materials := {}
var _batches := {}
var _scan := 0.0
var _active := true
var _exiting_tree := false

func configure(owner_session) -> void:
	session = owner_session
	player = session.world.player if session!=null else null
	set_physics_process(_active and is_instance_valid(player))

func build(village: Node3D,layout: Array) -> void:
	_village = village
	name = "VillageHomes"
	for i in layout.size():
		var home := Node3D.new()
		home.name = "Home%d"%(i+1)
		home.transform = Transform3D(Basis(Vector3.UP,float(layout[i][2])),layout[i][0])
		add_child(home)
		var roof := Node3D.new()
		roof.name = "Roof"
		home.add_child(roof)
		var upper := Node3D.new()
		upper.name = "UpperWalls"
		home.add_child(upper)
		var room: Dictionary = {"id":"truckers_home_%d"%(i+1),"index":i,"root":home,"roof":roof,"upper":upper,"center":home.global_position,"inside":Rect2(-6.3,-4.3,12.6,8.6),"entry":home.to_global(Vector3(0,0,4.5)),"outside":home.to_global(Vector3(0,0,6)),"open":false,"amount":0.0,"solid_start":solids.size()}
		homes.append(room)
		_shell(room,Color(layout[i][1]))
		_furnish(room,i)
		var find := Node3D.new()
		find.name = "CashFind"
		find.position = Vector3(1.5,.055,-3)
		home.add_child(find)
		var money := MeshInstance3D.new()
		var cash := BoxMesh.new()
		cash.size = Vector3(.25,.05,.15)
		money.mesh = cash
		money.material_override = _material("809075")
		find.add_child(money)
		room.loot = find
		room.solid_end = solids.size()
		occupant_points.append(home.to_global(Vector3(-1.5,0,-1)))
		doorway_points.append(room.entry)
		outside_points.append(room.outside)
		loot_points.append(find.global_position)
		if village.get("houses")!=null: village.houses.append(home.global_position)
	_flush()
	interior_camera = Camera3D.new()
	interior_camera.name = "HomesCamera"
	interior_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Exterior trees remain intact. Only their crowns leave the indoor view so
	# foreground foliage cannot cover the room, its furniture or its residents.
	interior_camera.cull_mask &= ~preload("res://gameplay/urban_v1/TruckersVillageVegetation.gd").INTERIOR_OCCLUDING_CANOPY_LAYER
	interior_camera.size = 17
	interior_camera.far = 80
	add_child(interior_camera)
	set_physics_process(is_instance_valid(player))

func occupant_anchors(index: int) -> Array[Vector3]:
	var home: Node3D = homes[index].root
	return [home.to_global(Vector3(-1.5,0,-1)),home.to_global(Vector3(1.5,0,-1))]

func house_at(point: Vector3) -> int:
	for room in homes:
		var local: Vector3 = room.root.to_local(point)
		if room.inside.has_point(Vector2(local.x,local.z)) and absf(local.y)<3: return room.index
	return -1

func set_region_active(value: bool) -> void:
	_active = value
	visible = value
	for body in solids: body.collision_layer = 1 if value else 0
	set_physics_process(value and is_instance_valid(player))
	if not value: _set_inside(-1)

func set_loot_collected(index: int,collected: bool) -> void:
	if index>=0 and index<homes.size(): homes[index].loot.visible = not collected

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player): return
	_scan -= delta
	if _scan<=0:
		_scan = .12
		var occupied := house_at(player.global_position)
		if player.get("dead")==true: occupied = -1
		_set_inside(occupied)
		for room in homes:
			var entry: Vector3 = room.entry
			var nearby := player.global_position.distance_squared_to(entry)<8.4
			if player.global_position.distance_squared_to(room.center)<2500:
				var shape := SphereShape3D.new()
				shape.radius = 2.8
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = shape
				query.transform.origin = entry+Vector3.UP*.9
				query.collision_mask = 2
				nearby = nearby or not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
			room.open = nearby
	for room in homes:
		var amount := move_toward(float(room.amount),1.0 if room.open else 0.0,delta*3.8)
		if is_equal_approx(amount,float(room.amount)): continue
		room.amount = amount
		room.door.rotation.y = -PI*.5*amount

func _set_inside(index: int) -> void:
	if current_home==index: return
	var previous := current_home
	if previous>=0:
		homes[previous].roof.show()
		homes[previous].upper.show()
		if not _exiting_tree: house_exited.emit(previous)
	current_home = index
	if index>=0:
		var room: Dictionary = homes[index]
		room.roof.hide()
		room.upper.hide()
		var home: Node3D = room.root
		interior_camera.global_position = home.to_global(Vector3(0,18,15))
		interior_camera.look_at(home.to_global(Vector3(0,.5,0)),Vector3.UP)
		if previous<0:
			_outside_camera = get_viewport().get_camera_3d()
			if is_instance_valid(player):
				_previous_shelter = player.get_meta("mountain_shelter",false)
		if is_instance_valid(player):
			player.set_meta("mountain_shelter",true)
			if player.get("camera")!=null: player.camera = interior_camera
		interior_camera.make_current()
		house_entered.emit(index)
	elif previous>=0:
		if is_instance_valid(_outside_camera):
			_outside_camera.make_current()
			if is_instance_valid(player) and player.get("camera")!=null: player.camera = _outside_camera
		if is_instance_valid(player): player.set_meta("mountain_shelter",_previous_shelter)
	if not _exiting_tree and session!=null and is_instance_valid(session.weather): session.weather._update()

func _exit_tree() -> void:
	_exiting_tree = true
	if current_home>=0: _set_inside(-1)

func _shell(room: Dictionary,color: Color) -> void:
	var home: Node3D = room.root
	var upper: Node3D = room.upper
	var roof: Node3D = room.roof
	var paint := color.to_html(false)
	# All floor finishes are shallow and walkable over the terrain collider.
	_box(home,Vector3(0,.017,0),Vector3(12.6,.028,8.6),"80694d")
	for z in range(-4,5): _box(home,Vector3(0,.036,z),Vector3(12.6,.008,.028),"655540")
	var walls: Array = [[Vector3(-6.4,1.5,0),Vector3(.2,3,9)],[Vector3(6.4,1.5,0),Vector3(.2,3,9)],[Vector3(-3.7,1.5,4.4),Vector3(5.6,3,.2)],[Vector3(3.7,1.5,4.4),Vector3(5.6,3,.2)]]
	if room.index == 0:
		# Casa 1 grows into a narrow pantry annex. Split the original rear wall
		# around its doorway so the route to the cellar is physically continuous.
		walls.append([Vector3(-3.29,1.5,-4.4),Vector3(6.22,3,.2)])
		walls.append([Vector3(3.99,1.5,-4.4),Vector3(5.02,3,.2)])
	else:
		walls.append([Vector3(0,1.5,-4.4),Vector3(13,3,.2)])
	for wall in walls:
		var center: Vector3 = wall[0]
		var size: Vector3 = wall[1]
		_box(home,Vector3(center.x,.3,center.z),Vector3(size.x,.6,size.z),paint)
		_box(upper,Vector3(center.x,1.8,center.z),Vector3(size.x,2.4,size.z),paint)
		_solid(room,"ExteriorWall",center,size)
	if room.index == 0:
		_box(upper,Vector3(.65,2.69,-4.4),Vector3(1.66,.62,.2),paint)
		_solid(room,"CellarDoorHeader",Vector3(.65,2.69,-4.4),Vector3(1.66,.62,.2))
	_box(upper,Vector3(0,2.66,4.4),Vector3(1.8,.68,.2),paint)
	_solid(room,"DoorHeader",Vector3(0,2.66,4.4),Vector3(1.8,.68,.2))
	for x in [-3.6,3.6]:
		for z in [-4.51,4.51]:
			_box(upper,Vector3(x,1.75,z),Vector3(1.8,1.3,.05),"536968")
			for edge in [-.94,.94]: _box(upper,Vector3(x+edge,1.75,z*1.01),Vector3(.10,1.5,.09),"675c45")
			_box(upper,Vector3(x,1.75,z*1.013),Vector3(.07,1.3,.05),"bfb294")
			# Interior curtains sit on the room-facing side of the rear glazing.
		_box(upper,Vector3(x,2.5,-4.20),Vector3(2.1,.05,.05),"675c45")
		for edge in [-.75,.75]: _box(upper,Vector3(x+edge,1.8,-4.18),Vector3(.30,1.4,.035),"b4aa87")
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(-.9,0,4.4)
	home.add_child(pivot)
	_box(pivot,Vector3(.9,1.14,0),Vector3(1.8,2.28,.13),"67533c")
	for x in [.12,.6,1.08,1.56]: _box(pivot,Vector3(x,1.15,.074),Vector3(.035,2.12,.035),"8b7351")
	_box(pivot,Vector3(1.55,1.05,.12),Vector3(.10,.06,.1),"b79855")
	var door_body := _solid(room,"EntryDoor",Vector3(.9,1.14,0),Vector3(1.8,2.28,.16),pivot)
	room.door = pivot
	room.door_body = door_body
	for side in [-1.0,1.0]:
		_box(roof,Vector3(side*3.6,3.65,0),Vector3(7.55,.16,10.4),"865f48",Vector3(0,0,-side*.19))
		for z in range(-5,6): _box(roof,Vector3(side*3.6,3.77,z),Vector3(7.55,.05,.07),"9a7254",Vector3(0,0,-side*.19))
	_box(roof,Vector3(0,2.92,5.65),Vector3(9,.12,2.5),"716b50",Vector3(.08,0,0))
	for x in [-4.2,4.2]:
		_box(home,Vector3(x,1.43,6.55),Vector3(.14,2.86,.14),"73624a")
		_solid(room,"PorchPost",Vector3(x,1.43,6.55),Vector3(.14,2.86,.14))
	_bench(room,Vector3(-2.8,0,5.9))
	_light(home,Vector3(0,2.55,-.4),"ffe1b2")
	_light(home,Vector3(.9,2.3,4.9),"ffcf89")

func _furnish(room: Dictionary,index: int) -> void:
	var home: Node3D = room.root
	# Deliberately different arrangements, with a continuous central aisle.
	match index:
		0:
			_bed(room,Vector3(-4.5,0,-2.6),true,"8d694e")
			_kitchen(room,Vector3(4.8,0,-2.8),true)
			_table(room,Vector3(4,0,1.4),Vector2(2.1,1.1))
			_sofa(room,Vector3(-4.4,0,1.6),"716d53")
			_partition(room,Vector3(-2.5,1.1,-3.0),Vector3(.12,2.2,2.8))
		1:
			_bed(room,Vector3(4.7,0,-2.6),false,"8b766d")
			_kitchen(room,Vector3(-4.9,0,-2.8),false)
			_work_table(room,Vector3(-4.5,0,.9),true)
			_sofa(room,Vector3(4.5,0,1.8),"647b74")
			_cabinet(room,Vector3(3.3,0,-3.95),Vector3(1.25,1.9,.55))
		2:
			_bed(room,Vector3(-4.7,0,-2.6),false,"596b78")
			_bed(room,Vector3(-4.7,.96,-2.6),false,"83765c",false)
			_solid(room,"BunkBedVolume",Vector3(-4.7,.92,-2.6),Vector3(1.6,1.84,2.5))
			_kitchen(room,Vector3(4.9,0,-2.8),false)
			_radio(room,Vector3(-4.6,0,1.5))
			_table(room,Vector3(4.2,0,1.6),Vector2(2.0,1.5))
		3:
			_bed(room,Vector3(-4.4,0,-2.4),true,"7e7961")
			_partition(room,Vector3(-2.5,1.1,-2.8),Vector3(.12,2.2,3.0))
			_kitchen(room,Vector3(4.8,0,-2.8),true)
			_work_table(room,Vector3(-4.5,0,1.8),false)
			_cabinet(room,Vector3(4.9,0,1.8),Vector3(1.5,1.7,.7))
		4:
			_bed(room,Vector3(-4.9,0,-2.5),false,"9a755b")
			_bed(room,Vector3(4.9,0,-2.5),false,"607a78")
			_table(room,Vector3(-4.1,0,1.4),Vector2(2.2,1.45))
			_kitchen(room,Vector3(4.8,0,1.8),false)
		5:
			_bed(room,Vector3(4.5,0,-2.6),true,"756279")
			_kitchen(room,Vector3(-4.8,0,-2.8),false)
			_sofa(room,Vector3(-4.5,0,1.7),"876a50")
			_work_table(room,Vector3(4.7,0,1.9),false)
			_partition(room,Vector3(2.5,1.1,-3.2),Vector3(.12,2.2,2.2))
	# A woven rug marks the clear living aisle; never a collision surface.
	_box(home,Vector3(0,.04,1),Vector3(2.5,.02,2.4),["9a8261","766d62","6f7b6b"][index%3])
	for z in [.0,.25,1.75,2.0]: _box(home,Vector3(0,.052,z),Vector3(2.4,.006,.035),"b5a482")
	if index != 0:
		_cabinet(room,Vector3(-.65,0,-4.02),Vector3(1.3,.85,.52))
		_box(home,Vector3(-.65,1.01,-4.0),Vector3(.5,.28,.28),"544a3b")
		for x in [-.81,-.50]: _cylinder(home,Vector3(x,1.01,-3.845),.065,.025,"aaa18b",Vector3(PI*.5,0,0))

func _bed(room: Dictionary,at: Vector3,double: bool,color: String,solid := true) -> void:
	var home: Node3D=room.root
	var width := 2.1 if double else 1.45
	_box(home,at+Vector3(0,.22,0),Vector3(width,.35,2.35),"65533b")
	_box(home,at+Vector3(0,.49,0),Vector3(width-.08,.22,2.22),"d0c8aa")
	_box(home,at+Vector3(0,.62,.30),Vector3(width-.04,.06,1.6),color)
	_box(home,at+Vector3(0,.62,-.76),Vector3(width*.72,.13,.42),"d9d1b8")
	_box(home,at+Vector3(0,.65,-1.17),Vector3(width,.95,.12),"796449")
	if solid: _solid(room,"Bed",at+Vector3(0,.56,0),Vector3(width,1.12,2.5))

func _kitchen(room: Dictionary,at: Vector3,corner: bool) -> void:
	var home: Node3D=room.root
	_box(home,at+Vector3(0,.48,0),Vector3(2.6,.96,.8),"8d8066")
	_box(home,at+Vector3(0,1.0,0),Vector3(2.7,.10,.88),"b7b39f")
	for x in [-.85,0,.85]:
		_box(home,at+Vector3(x,.55,.411),Vector3(.76,.77,.04),"9d9277")
		_box(home,at+Vector3(x,.81,.44),Vector3(.24,.045,.035),"514f45")
	_box(home,at+Vector3(-.55,1.064,0),Vector3(.65,.025,.50),"60716c")
	_box(home,at+Vector3(-.55,1.24,-.22),Vector3(.045,.38,.045),"9eaa9d")
	_box(home,at+Vector3(-.55,1.42,-.12),Vector3(.045,.045,.22),"9eaa9d")
	for x in [.5,.95]: _cylinder(home,at+Vector3(x,1.068,0),.15,.024,"3e4239")
	_solid(room,"KitchenCounter",at+Vector3(0,.54,0),Vector3(2.7,1.08,.9))
	if corner:
		_box(home,at+Vector3(1.02,.48,1.0),Vector3(.65,.96,1.25),"8d8066")
		_box(home,at+Vector3(1.02,1.0,1.0),Vector3(.72,.1,1.3),"b7b39f")
		_solid(room,"KitchenReturn",at+Vector3(1.02,.55,1),Vector3(.72,1.1,1.3))

func _table(room: Dictionary,at: Vector3,size: Vector2) -> void:
	var home: Node3D=room.root
	_box(home,at+Vector3(0,.80,0),Vector3(size.x,.13,size.y),"a18962")
	for x in [-size.x*.4,size.x*.4]:
		for z in [-size.y*.35,size.y*.35]: _box(home,at+Vector3(x,.38,z),Vector3(.1,.76,.1),"65543d")
	_solid(room,"DiningTable",at+Vector3(0,.44,0),Vector3(size.x,.88,size.y))
	for z in [-1.0,1.0]:
		var seat:=at+Vector3(0,0,z*(size.y*.5+.5))
		_box(home,seat+Vector3(0,.43,0),Vector3(.48,.13,.48),"8b7556")
		_box(home,seat+Vector3(0,.70,z*.22),Vector3(.48,.68,.08),"8b7556")
		for x in [-.18,.18]: _box(home,seat+Vector3(x,.2,0),Vector3(.07,.4,.4),"65543d")
		_solid(room,"DiningChair",seat+Vector3(0,.52,0),Vector3(.5,1.04,.56))
	_cylinder(home,at+Vector3(.25,.9,0),.17,.035,"c7c1a7")
	_cylinder(home,at+Vector3(-.25,.99,0),.075,.2,"758478")

func _sofa(room: Dictionary,at: Vector3,color: String) -> void:
	var home: Node3D=room.root
	_box(home,at+Vector3(0,.3,0),Vector3(2.25,.5,.90),"65533b")
	_box(home,at+Vector3(0,.58,.06),Vector3(1.9,.17,.76),color)
	_box(home,at+Vector3(0,.86,-.4),Vector3(2.25,.64,.20),color)
	for x in [-1.0,1.0]: _box(home,at+Vector3(x,.68,0),Vector3(.26,.45,.96),color)
	_solid(room,"Sofa",at+Vector3(0,.58,0),Vector3(2.25,1.16,1.0))

func _cabinet(room: Dictionary,at: Vector3,size: Vector3) -> void:
	var home: Node3D=room.root
	_box(home,at+Vector3(0,size.y*.5,0),size,"79664b")
	for x in [-size.x*.24,size.x*.24]:
		_box(home,at+Vector3(x,size.y*.52,size.z*.5+.025),Vector3(size.x*.45,size.y*.91,.035),"8b7556")
		_box(home,at+Vector3(x*.25,size.y*.55,size.z*.5+.055),Vector3(.035,.15,.035),"b6a77f")
	_solid(room,"Cabinet",at+Vector3(0,size.y*.5,0),size+Vector3(0,0,.12))

func _work_table(room: Dictionary,at: Vector3,sewing: bool) -> void:
	var home: Node3D=room.root
	_box(home,at+Vector3(0,.78,0),Vector3(2.2,.14,1.0),"8b7556")
	for x in [-.88,.88]: _box(home,at+Vector3(x,.37,0),Vector3(.15,.74,.80),"65543d")
	_solid(room,"WorkDesk",at+Vector3(0,.65,0),Vector3(2.2,1.3,1))
	if sewing:
		_box(home,at+Vector3(0,.9,0),Vector3(.9,.1,.5),"343d36")
		_box(home,at+Vector3(.27,1.15,0),Vector3(.2,.45,.23),"343d36")
		_box(home,at+Vector3(0,1.37,0),Vector3(.7,.16,.23),"343d36")
		_box(home,at+Vector3(-.5,.88,.15),Vector3(.5,.03,.4),"ac8d72")
	else:
		for x in [-.7,-.42,-.1]: _box(home,at+Vector3(x,.96,-.25),Vector3(.13,.3,.36),"627564")
		_box(home,at+Vector3(.55,.88,.1),Vector3(.4,.045,.5),"d0c8aa")

func _radio(room: Dictionary,at: Vector3) -> void:
	_cabinet(room,at,Vector3(1.6,.8,.65))
	_box(room.root,at+Vector3(0,1.06,0),Vector3(1.1,.48,.4),"5f4e36")
	_box(room.root,at+Vector3(-.15,1.09,.215),Vector3(.58,.26,.02),"333c34")
	for x in [.30,.44]: _cylinder(room.root,at+Vector3(x,1.02,.23),.04,.025,"b6a77f",Vector3(PI*.5,0,0))

func _partition(room: Dictionary,at: Vector3,size: Vector3) -> void:
	_box(room.upper,at,size,"9d9277")
	_solid(room,"BedroomPartition",at,size)

func _bench(room: Dictionary,at: Vector3) -> void:
	_box(room.root,at+Vector3(0,.48,0),Vector3(2.2,.14,.58),"766449")
	_box(room.root,at+Vector3(0,.88,-.25),Vector3(2.2,.6,.09),"827052")
	for x in [-.8,.8]: _box(room.root,at+Vector3(x,.23,0),Vector3(.13,.46,.45),"5b5845")
	_solid(room,"PorchBench",at+Vector3(0,.55,0),Vector3(2.2,1.1,.65))

func _light(parent: Node3D,at: Vector3,color: String) -> void:
	_box(parent,at,Vector3(.38,.14,.3),"60513b")
	_box(parent,at+Vector3(0,-.075,0),Vector3(.28,.025,.22),"dec392")
	var fitting:=Node3D.new()
	fitting.position=at
	parent.add_child(fitting)
	fitting.add_to_group(&"city_local_light_source")
	fitting.set_meta("local_light",{"range":8.0,"energy":1.35,"color":Color(color)})

func _material(color: String) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=Color(color)
		mat.roughness=.86
		_materials[color]=mat
	return _materials[color]

func _box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles:=Vector3.ZERO) -> void:
	var mesh:=BoxMesh.new()
	mesh.size=size
	_append(parent,mesh,at,color,angles)

func _cylinder(parent: Node3D,at: Vector3,radius: float,height: float,color: String,angles:=Vector3.ZERO) -> void:
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=height
	mesh.radial_segments=10
	mesh.rings=1
	_append(parent,mesh,at,color,angles)

func _append(parent: Node3D,mesh: Mesh,at: Vector3,color: String,angles: Vector3) -> void:
	var key:="%s_%s"%[parent.get_instance_id(),color]
	if not _batches.has(key):
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key]={"surface":surface,"parent":parent,"color":color}
	_batches[key].surface.append_from(mesh,0,Transform3D(Basis.from_euler(angles),at))

func _solid(room: Dictionary,id: String,at: Vector3,size: Vector3,parent: Node3D = null) -> StaticBody3D:
	if parent==null: parent=room.root
	var body:=StaticBody3D.new()
	body.name=id
	body.position=at
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("interior_solid_id",room.id+"/"+id)
	var shape:=BoxShape3D.new()
	shape.size=size
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	parent.add_child(body)
	solids.append(body)
	furniture.append({"home":room.index,"id":id,"body":body,"size":size})
	if _village.get("solids")!=null:
		_village.solids.append(body)
		_village.placements.append({"id":id,"center":_village.to_local(body.global_position),"basis":_village.global_basis.inverse()*body.global_basis,"size":size})
	return body

func _flush() -> void:
	for batch in _batches.values():
		var node:=MeshInstance3D.new()
		node.name="HomeDetail"
		node.mesh=batch.surface.commit()
		node.material_override=_material(batch.color)
		batch.parent.add_child(node)
	_batches.clear()
