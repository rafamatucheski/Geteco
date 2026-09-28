extends Node3D
## Native 3D shell: the exact visible wall/crate boxes also build the physics.
const STATE := preload("res://gameplay/urban_v1/PortContainerState.gd")
const OPTIMIZER := preload("res://assets/regions/source/prototypes/harbor_art_pack/PortMeshOptimizer.gd")
const MATERIALS := preload("res://world/regions/PortContainerMaterials.gd")
var cargo_id := ""
var dimensions := Vector2.ZERO
var height := 0.0
var opened := false
var looted := false
var revealed := false
var obstructing := false
var view_quadrant := Vector2i.ZERO
var roof: Node3D
var sides: Array[Node3D] = []
var doors: Array[Node3D] = []
var contents: Node3D
var lid: MeshInstance3D
var reveal_tween: Tween
var door_tween: Tween
var mats: Dictionary = {}
var lock_sound: AudioStreamPlayer3D
var layout_cycle := -1
var cargo_props: Node3D

func build(point: Vector3, size: Vector2) -> void:
	position = point
	dimensions = size
	height = 2.91 * size.x / 12.19
	cargo_id = STATE.cargo_id(point)
	name = cargo_id
	set_meta("native_dynamic_roof",true)
	add_to_group("lootable_port_containers")
	var w := size.x
	var d := size.y
	var color: Color = [Color("995343"),Color("427788"),Color("487c73"),Color("b99549"),Color("bfc5bb")][posmod(int(point.x),5)]
	var floor_group := Node3D.new()
	add_child(floor_group)
	_box(floor_group,"Floor",Vector3(0,.012,0),Vector3(w,.024,d),Color("695944"),false)
	for i in 11:
		_box(floor_group,"PlankSeam",Vector3(0,.027,-d*.5+(i+1)*d/12),Vector3(w,.005,.016),Color("292922"),false)
	for x in [-w*.5+.3,0,w*.5-.3]:
		_box(floor_group,"FloorRail",Vector3(x,.03,0),Vector3(.065,.008,d),Color("45483f"),false)
	OPTIMIZER.optimize_hierarchy(floor_group)
	for z in [-1,1]:
		var side := Node3D.new()
		add_child(side)
		sides.append(side)
		side.set_meta("side",z)
		_box(side,"Wall",Vector3(0,height*.5,z*d*.5),Vector3(w,height,.15),color,true)
		_box(side,"InnerLiner",Vector3(0,height*.5,z*(d*.5-.083)),Vector3(w-.16,height-.14,.012),Color("8b9182"),false)
		for y in [.14,height-.10]:
			_box(side,"SteelRail",Vector3(0,y,z*d*.5),Vector3(w,.17,.21),color.darkened(.36),false)
		for i in 40:
			_box(side,"Rib",Vector3(-w*.5+.25+i*(w-.5)/39,height*.5,z*(d*.5+.08)),Vector3(.11,height-.25,.10),color.lightened(.10),false)
			_box(side,"InnerRib",Vector3(-w*.5+.25+i*(w-.5)/39,height*.5,z*(d*.5-.10)),Vector3(.055,height-.28,.035),Color("727c70"),false)
		OPTIMIZER.optimize_hierarchy(side)
	var back := Node3D.new()
	add_child(back)
	sides.append(back)
	back.set_meta("side",0)
	_box(back,"BackWall",Vector3(-w*.5,height*.5,0),Vector3(.15,height,d),color,true)
	_box(self,"RearCrate",Vector3(-w*.5+1.0,.55,-d*.25),Vector3(1.3,1.1,1.2),Color("806143"),true)
	_box(self,"RearCrateBand",Vector3(-w*.5+1.0,1.11,-d*.25),Vector3(1.32,.025,.12),Color("3c4040"),false)
	contents = Node3D.new()
	contents.position = Vector3(w*.5-3.0,0,-d*.25)
	add_child(contents)
	_box(contents,"LootChest",Vector3(0,.28,0),Vector3(1.05,.56,.75),Color("4b5951"),true)
	lid = _box(contents,"LootLid",Vector3(0,.585,0),Vector3(1.08,.06,.78),Color("6c786a"),false)
	_box(contents,"Latch",Vector3(.54,.40,0),Vector3(.04,.18,.12),Color("c1b789"),false)
	for side in [-1,1]:
		var hinge := Node3D.new()
		hinge.position = Vector3(w*.5,0,side*d*.5)
		add_child(hinge)
		doors.append(hinge)
		hinge.set_meta("side",side)
		_box(hinge,"Door",Vector3(0,height*.5,-side*d*.25),Vector3(.16,height,d*.5),color,true)
		_box(hinge,"DoorLiner",Vector3(-.087,height*.5,-side*d*.25),Vector3(.012,height-.14,d*.5-.08),Color("7b8579"),false)
		for y in [.16,height*.5,height-.16]:
			_box(hinge,"DoorBrace",Vector3(.10,y,-side*d*.25),Vector3(.06,.09,d*.5-.04),color.darkened(.3),false)
			_box(hinge,"Hinge",Vector3(.10,y,0),Vector3(.21,.24,.15),Color("626d68"),false)
		for rib in 7:
			_box(hinge,"DoorRib",Vector3(.1,height*.5,-side*(.15+rib*(d*.5-.3)/6)),Vector3(.045,height-.25,.055),color.lightened(.06),false)
		for fraction in [.18,.36]:
			_box(hinge,"LockingBar",Vector3(.12,height*.5,-side*d*fraction),Vector3(.055,height-.25,.055),Color("b3b7ad"),false)
			_box(hinge,"LockHandle",Vector3(.20,1.1,-side*(d*fraction+.10)),Vector3(.10,.07,.30),Color("a3a79c"),false)
		_box(hinge,"LockBox",Vector3(.20,1.05,-side*(d*.5-.12)),Vector3(.21,.22,.16),Color("a59461"),false)
		OPTIMIZER.optimize_hierarchy(hinge)
	roof = Node3D.new()
	add_child(roof)
	_box(roof,"Roof",Vector3(0,height,0),Vector3(w+.15,.14,d+.16),color.lightened(.07),false)
	for i in 40:
		_box(roof,"RoofRib",Vector3(-w*.5+.25+i*(w-.5)/39,height+.10,0),Vector3(.11,.06,d),color.lightened(.13),false)
	# The upper container remains scenery; it fades with the occupied ground roof
	# because its underside would otherwise entirely occlude the same interior.
	if posmod(int(point.x),3) == 0:
		var upper := preload("res://assets/regions/source/prototypes/harbor_art_pack/props/PortContainer40ft3D.gd").new()
		upper.color_theme = posmod(int(point.x)+1,5)
		upper.position.y = height+.10
		upper.rotation.y = PI*.5
		upper.scale = Vector3(d/2.44,w/12.19,w/12.19)
		roof.add_child(upper)
		for part in upper.get_children():
			if part is MeshInstance3D and part.material_override is StandardMaterial3D:
				part.material_override = MATERIALS.material(part.material_override.albedo_color)
	OPTIMIZER.optimize_hierarchy(roof)
	# A chunk can stream in after session restoration. Restore before physics runs.
	for service in get_tree().get_nodes_in_group("port_container_service"):
		service.bind_container(self)

func _box(parent: Node3D, id: String, at: Vector3, size: Vector3, color: Color, solid: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = id
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var timber := id in ["Floor","RearCrate"]
	var key := color.to_html()+str(timber)
	if not mats.has(key):
		mats[key] = MATERIALS.material(color,timber)
	mesh.material_override = mats[key]
	mesh.position = at
	parent.add_child(mesh)
	if solid:
		mesh.set_meta("interior_solid_id",StringName(id))
		var body := StaticBody3D.new()
		body.name = id+"Solid"
		body.position = at
		body.collision_layer = 1
		body.collision_mask = 0
		parent.add_child(body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	return mesh

func door_point() -> Vector3:
	return to_global(Vector3(dimensions.x*.5+1.0,.1,0))

func loot_point() -> Vector3:
	return contents.global_position + Vector3(.85,.1,.55 if contents.position.z < 0 else -.55)

func play_lock_sound() -> void:
	if not is_instance_valid(lock_sound):
		lock_sound = AudioStreamPlayer3D.new()
		lock_sound.stream = preload("res://audio/footsteps/metal_0.wav")
		lock_sound.position = Vector3(dimensions.x*.5,1.1,0)
		lock_sound.volume_db = -15
		lock_sound.pitch_scale = 1.7
		lock_sound.max_distance = 14
		add_child(lock_sound)
	lock_sound.play()

func contains(point: Vector3) -> bool:
	var p := to_local(point)
	return opened and absf(p.x) < dimensions.x*.5-.12 and absf(p.z) < dimensions.y*.5-.12 and p.y > -.3 and p.y < 2.2

func apply_state(row: Dictionary, animate := false) -> void:
	var cycle := int(row.get("cycle",0))
	if layout_cycle != cycle: _arrange_cargo(cycle)
	var open_now: bool = row.get("opened",false)
	looted = row.get("looted",false)
	lid.rotation.x = -.7 if looted else 0.0
	if opened == open_now: return
	opened = open_now
	if door_tween != null: door_tween.kill()
	if animate: door_tween = create_tween().set_parallel(true)
	for door in doors:
		var angle := float(door.get_meta("side"))*-1.65 if opened else 0.0
		if animate: door_tween.tween_property(door,"rotation:y",angle,.45)
		else: door.rotation.y = angle

func _arrange_cargo(cycle: int) -> void:
	layout_cycle = cycle
	var variant := posmod(STATE.known_ids().find(cargo_id)+cycle,3)
	var side := -1.0 if variant != 1 else 1.0
	contents.position = Vector3([dimensions.x*.5-3.0,1.0,-dimensions.x*.5+4.0][variant],0,side*dimensions.y*.25)
	# Each mesh and its matching body move together; the middle aisle stays clear.
	for part_name in ["RearCrate","RearCrateSolid","RearCrateBand"]:
		get_node(NodePath(part_name)).position.z = side*dimensions.y*.25
	if is_instance_valid(cargo_props):
		remove_child(cargo_props)
		cargo_props.queue_free()
	cargo_props = Node3D.new()
	cargo_props.name = "RotatingCargo"
	add_child(cargo_props)
	for i in variant:
		var at := Vector3(-3.0+i*3.0,.4,-side*dimensions.y*.30)
		_box(cargo_props,"RearCrate",at,Vector3(1.35,.8,.85),Color("806143"),true)
		_box(cargo_props,"CargoStrap",at+Vector3(0,.41,0),Vector3(.13,.02,.87),Color("3c4040"),false)
	OPTIMIZER.optimize_hierarchy(cargo_props)

func set_revealed(value: bool, camera: Camera3D) -> void:
	var view := to_local(camera.global_position)
	var quadrant := Vector2i(1 if view.x >= 0 else -1,1 if view.z >= 0 else -1)
	if revealed == value and (not value or quadrant == view_quadrant): return
	view_quadrant = quadrant
	revealed = value
	roof.show()
	if reveal_tween != null: reveal_tween.kill()
	reveal_tween = create_tween().set_parallel(true)
	for child in get_children():
		if child != roof and child not in sides and child not in doors: _fade(child,0.0)
	_fade(roof,1.0 if value else 0.0)
	for door in doors: _fade(door,.85 if value else 0.0)
	for side in sides:
		var sign_z := int(side.get_meta("side"))
		var facing := view.z*sign_z > 0 if sign_z != 0 else view.x < 0
		_fade(side,.90 if value and facing else 0.0)

func set_obstructing(value: bool) -> void:
	if obstructing == value: return
	obstructing = value
	if reveal_tween != null: reveal_tween.kill()
	reveal_tween = create_tween().set_parallel(true)
	_fade(self,.96 if value else 0.0)
	if value:
		reveal_tween.tween_callback(func():
			if is_instance_valid(roof): roof.hide()
		).set_delay(.30)
	else: roof.show()

func blocks_view(point: Vector3, direction: Vector3) -> bool:
	var levels := 2 if posmod(int(position.x),3) == 0 else 1
	var bounds := AABB(global_position-Vector3(dimensions.x*.5,0,dimensions.y*.5),Vector3(dimensions.x,height*levels+.2,dimensions.y))
	return bounds.intersects_segment(point,point+direction*70) != null

func _fade(node: Node, transparency: float) -> void:
	if node is MeshInstance3D:
		# GeometryInstance3D.transparency is ignored by Mobile. Fade a private
		# material, then return to opaque rendering outside; cached palettes stay intact.
		if not node.has_meta("fade_material"):
			node.material_override = node.material_override.duplicate()
			node.set_meta("fade_material",true)
		var material: StandardMaterial3D = node.material_override
		node.visible = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED if transparency > 0 else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if transparency > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		reveal_tween.tween_property(material,"albedo_color:a",1.0-transparency,.30)
		reveal_tween.tween_callback(func():
			if not is_instance_valid(node): return
			if transparency >= 1.0: node.hide()
			elif is_zero_approx(transparency): material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		).set_delay(.30)
	for child in node.get_children(): _fade(child,transparency)
