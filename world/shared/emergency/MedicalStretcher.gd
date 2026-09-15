extends CharacterBody2D
var viewport: SubViewport
var rig: Node3D
var display: Sprite2D
var patient_model: Node3D
var heading := 0.0
var camera: Camera3D
var patient_actor: Node2D
var patient_viewport: SubViewport
var patient_display: Sprite2D
var patient_origin := Vector2.ZERO
var patient_transform := Transform3D.IDENTITY
var patient_z := 0
var patient_joints: Array[Dictionary] = []
var patient_shadow: Node3D
var patient_shadow_visible := true
var lift_progress := 0.0
var footprint: CollisionShape2D
var floor_vertices := PackedVector3Array()
var _floor_cache := {}

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = 3
	z_index = 7
	footprint = CollisionShape2D.new()
	footprint.shape = ConvexPolygonShape2D.new()
	add_child(footprint)
	viewport = SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	add_child(viewport)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(camera)
	camera.position = Vector3(0,8,4)
	camera.look_at(Vector3(0,.7,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	viewport.add_child(environment)
	rig = Node3D.new()
	viewport.add_child(rig)
	_box(Vector3(0,.66,0),Vector3(.63,.09,1.95),Color("c4ccd0"))
	_box(Vector3(0,.74,0),Vector3(.56,.10,1.85),Color("b7d5d2"))
	for x in [-.32,.32]:
		_box(Vector3(x,.89,0),Vector3(.035,.035,1.45),Color("d9e0e0"))
		for z in [-.68,.68]:
			_box(Vector3(x,.42,z),Vector3(.04,.48,.04),Color("aab6bd"))
			_box(Vector3(x,.16,z),Vector3(.12,.15,.15),Color("242c32"))
	display = Sprite2D.new()
	display.texture = viewport.get_texture()
	display.scale = Vector2.ONE * (4.0*74.0/4.46/128.0)
	display.position = -(camera.unproject_position(Vector3.ZERO)-Vector2(64,64))*display.scale
	add_child(display)
	# Derive the support footprint from the authored cot meshes, projected onto
	# the floor with the same camera/scale as their visible presentation.
	for child in rig.get_children():
		if not child is MeshInstance3D: continue
		var bounds: AABB = child.get_aabb()
		for corner in 8:
			var p: Vector3 = child.transform * bounds.get_endpoint(corner)
			floor_vertices.append(Vector3(p.x,0,p.z))
	set_heading(heading)

func floor_polygon(angle: float) -> PackedVector2Array:
	var key := snappedf(fposmod(angle,TAU),.00001)
	if _floor_cache.has(key): return _floor_cache[key]
	var vertices := PackedVector2Array()
	var basis := Basis(Vector3.UP, -angle-PI*.5)
	var ppm: float = float(viewport.size.x) / camera.size * display.scale.x
	for vertex in floor_vertices:
		var p := basis * vertex
		vertices.append(Vector2(p.x, -p.z * camera.basis.y.z) * ppm)
	var result := Geometry2D.convex_hull(vertices)
	if _floor_cache.size() >= 64: _floor_cache.clear()
	_floor_cache[key] = result
	return result

func set_heading(angle: float) -> void:
	heading = angle
	rig.rotation.y = -heading-PI*.5
	if footprint: footprint.shape.points = floor_polygon(heading)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	mesh.position = at
	rig.add_child(mesh)

func load_patient(actor: Node) -> void:
	# Keep the actual actor and its camera: replacing it with a duplicate in
	# this viewport changed both its scale and screen position in one frame.
	var care := get_node("/root/NPCMedicalCare")
	patient_model = care.model_for(actor)
	patient_viewport = care.viewport_for(actor)
	if patient_model == null or patient_viewport == null: return
	patient_actor = actor
	patient_origin = actor.global_position
	patient_transform = patient_model.transform
	patient_z = actor.z_index
	for child in actor.get_children():
		if child is Sprite2D and child.texture == patient_viewport.get_texture():
			patient_display = child
			break
	patient_shadow = patient_viewport.get_node_or_null("GroundShadow")
	if patient_shadow:
		patient_shadow_visible = patient_shadow.visible
		patient_shadow.hide()
	var fall: Variant = actor.get("fall_presentation") if "fall_presentation" in actor else actor.get("fall")
	if fall != null:
		for joint in fall.joints:
			patient_joints.append({"node": joint.node, "from": joint.node.rotation, "to": joint.initial})
	actor.show()
	update_patient(0.0)

func update_patient(progress: float = 1.0) -> void:
	if not is_instance_valid(patient_actor) or not is_instance_valid(patient_model): return
	lift_progress = clampf(progress, 0.0, 1.0)
	var blend := smoothstep(0.0, 1.0, lift_progress)
	# Straighten gently while lifting. Height is represented in screen space,
	# so the patient's original tightly framed camera never clips the head.
	var facing := -heading - PI * .5
	var target_rotation := Vector3(PI * .5, facing, 0)
	var target_basis := Basis.from_euler(target_rotation).scaled(patient_transform.basis.get_scale())
	var center := Basis(Vector3.UP, facing) * Vector3(0, .23, -.68 * patient_transform.basis.get_scale().y)
	patient_model.transform = patient_transform.interpolate_with(Transform3D(target_basis, center), blend)
	for joint in patient_joints:
		if is_instance_valid(joint.node): joint.node.rotation = (joint.from as Vector3).lerp(joint.to, blend)
	if is_instance_valid(patient_display):
		var source_camera := patient_viewport.get_camera_3d()
		var body_center := patient_model.to_global(Vector3(0, .68, 0))
		var source_pixel := source_camera.unproject_position(body_center) - Vector2(patient_viewport.size) * .5
		var body_offset := patient_actor.global_transform.basis_xform(patient_display.position + source_pixel * patient_display.scale)
		var cot_pixel := camera.unproject_position(rig.to_global(Vector3(0, .86, 0))) - Vector2(viewport.size) * .5
		var cot_center := to_global(display.position + cot_pixel * display.scale)
		patient_actor.global_position = patient_origin.lerp(cot_center - body_offset, blend)
	patient_actor.z_index = z_index + 1
	patient_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func release_patient() -> void:
	if not is_instance_valid(patient_actor): return
	patient_actor.z_index = patient_z
	if is_instance_valid(patient_model): patient_model.transform = patient_transform
	for joint in patient_joints:
		if is_instance_valid(joint.node): joint.node.rotation = joint.from
	if is_instance_valid(patient_shadow): patient_shadow.visible = patient_shadow_visible
	if is_instance_valid(patient_viewport): patient_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	patient_actor = null
	patient_model = null

func orient(direction: Vector2, delta: float = 0.0166667) -> void:
	if direction.length_squared() > .01:
		# A wheeled cot rolls either way. Returning to the ambulance must not
		# spin the patient 180 degrees or make the medics exchange handles.
		var desired := direction.angle()
		if absf(angle_difference(heading, desired)) > PI * .5: desired += PI
		heading = rotate_toward(heading, desired, 1.5 * delta)
	set_heading(heading)

func _exit_tree() -> void:
	release_patient()
