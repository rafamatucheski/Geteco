extends Node
## Furniture interactions use the real room and the original dressed player.
## The physical body stays at its validated approach point; only the explicit
## bed interaction moves the visual onto the mattress. No preview actor is made.
const WEAPON_MODEL := preload("res://gameplay/ArsenalWeapon3D.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const MIRROR_LAYER := 1 << 19
var session
var station := ""
var camera: Camera3D
var mirror_viewport: SubViewport
var weapon_preview: Node3D
var _room: Node3D
var _model: Node3D
var _player: CharacterBody3D
var _previous_camera: Camera3D
var _visual_transform := Transform3D.IDENTITY
var _visual_global := Transform3D.IDENTITY
var _physics_enabled := true
var _visual_interpolation := Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var _pose: Array = []
var _camera_tween: Tween
var _door_tween: Tween
var _weapon_camera_tween: Tween
var _mirror_material: Material
var _mirror_layers := 1
var _selected_weapon := ""
var quality_state: Dictionary = {}
var _quality_viewport: Viewport
var _sole_contacts: Node3D

func configure(owner_session) -> void:
	session = owner_session
	set_process(false)

func is_active() -> bool:
	return not station.is_empty()

func begin(id: String) -> bool:
	if station == id and is_instance_valid(_room) and _room == session.room: return true
	finish()
	if not is_instance_valid(session.room) or id not in ["wardrobe", "arsenal", "time", "food", "backpack", "chest"]: return false
	_room = session.room
	_model = _room.model
	if not _model.get("presentation_points") is Dictionary: return false
	_player = session.world.player
	_previous_camera = get_viewport().get_camera_3d()
	_visual_transform = _player.visual.transform
	_visual_global = _player.visual.global_transform
	_visual_interpolation = _player.visual.physics_interpolation_mode
	_player.visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_physics_enabled = _player.is_physics_processing()
	_pose = _player._capture_pose()
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	_player._apply_pose(_player._idle_pose)
	_ground_standing_pose()
	_visual_global = _player.visual.global_transform
	_quality_viewport = get_viewport()
	quality_state = {"msaa_3d":_quality_viewport.msaa_3d,"scaling_3d_scale":_quality_viewport.scaling_3d_scale,"scaling_3d_mode":_quality_viewport.scaling_3d_mode,"screen_space_aa":_quality_viewport.screen_space_aa}
	_quality_viewport.msaa_3d = maxi(_quality_viewport.msaa_3d,Viewport.MSAA_4X)
	_quality_viewport.scaling_3d_scale = maxf(_quality_viewport.scaling_3d_scale,1.0)
	station = id
	camera = Camera3D.new()
	camera.name = "ResidenceInteractionCamera"
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .05
	camera.far = 18
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	var focus: Vector3 = _player.global_position + Vector3.UP * .95
	var eye := focus + Vector3(3, 1.8, 3)
	var framing := 3.1
	match station:
		"wardrobe":
			var normal: Vector3 = _model.presentation_points.wardrobe_normal
			focus = _player.global_position + Vector3.UP * 1.05 - normal * .26
			eye = focus + normal * 3.4 + Vector3(0, 1.0, 3.4)
			_player.visual.rotation.y = atan2(-normal.x * .65, -1.0)
			_start_mirror()
		"arsenal":
			_model.bench_light.visible = true
			focus = _model.to_global(_model.presentation_points.arsenal)
			eye = focus + Vector3(0, 5.5, 1.5)
			framing = 2.0
		"time":
			focus = _model.to_global(_model.presentation_points.time) + Vector3(0, .6, -.15)
			var side: float = -signf(_model.presentation_points.time.x)
			eye = focus + Vector3(side * 3.1, 3.7, 3.5)
			framing = 3.7
		"food":
			focus = _model.to_global(_model.presentation_points.food)
			# Look past the player's shoulder and the left-hinged open door.
			eye = focus + Vector3(1.7, .85, 3.4)
			framing = 2.45
			_set_fridge_open(true)
		"backpack", "chest":
			focus = _model.to_global(_model.presentation_points.get(station, _model.presentation_points.backpack))
			eye = focus + Vector3(1.1, 2.2, 3)
			framing = 2.3
	_update_sole_contacts()
	var destination := Transform3D(Basis.looking_at((focus - eye).normalized()), eye)
	if is_instance_valid(_previous_camera):
		camera.global_transform = _previous_camera.global_transform
		camera.size = _previous_camera.size
		camera.far = _previous_camera.far
	else:
		camera.global_transform = destination
		camera.size = framing
	camera.make_current()
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "global_transform", destination, .55)
	_camera_tween.tween_property(camera, "size", framing, .55)
	# Orthographic shadow precision follows the camera's far plane. Keep the
	# whole house, rather than allocating the shadow atlas across the city.
	_camera_tween.tween_property(camera, "far", 18.0, .55)
	# The compact controls occupy the right side of the viewport.
	_camera_tween.tween_property(camera, "h_offset", framing * .31, .55)
	set_process(true)
	return true

func refresh_outfit() -> void:
	if is_active() and is_instance_valid(_player):
		_ground_standing_pose()
		_update_sole_contacts()

func _update_sole_contacts() -> void:
	# Mobile rendering lacks ambient contact occlusion. These small, soft sole
	# contacts complement the full directional shadow without changing its
	# bias or lowering the physically grounded boots into the floor.
	if is_instance_valid(_sole_contacts): _sole_contacts.free()
	_sole_contacts = Node3D.new()
	_sole_contacts.name = "SoleContactOcclusion"
	add_child(_sole_contacts)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, depth_draw_never; void fragment(){ float d=length((UV-vec2(0.5))*2.0); ALBEDO=vec3(0.025,0.022,0.018); ALPHA=(1.0-smoothstep(0.2,1.0,d))*0.48; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	for side in ["Left","Right"]:
		var foot: int = _player.skeleton.find_bone(side+"Foot")
		var toe: int = _player.skeleton.find_bone(side+"ToeBase")
		if foot < 0 or toe < 0: continue
		var heel: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(foot).origin)
		var tip: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(toe).origin)
		var direction := tip-heel
		direction.y = 0
		var contact := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(.25,.36)
		contact.mesh = plane
		contact.material_override = material
		contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sole_contacts.add_child(contact)
		contact.global_position = heel.lerp(tip,.5)
		contact.global_position.y = _model.global_position.y+.009
		if direction.length_squared() > .0001: contact.global_basis = Basis.looking_at(direction.normalized())

func _ground_standing_pose() -> void:
	# Walking's blended ankle rotations leave the idle boots on their toes.
	# Use authored flat soles and solve the legs against that support, then
	# align the real skinned sole vertices to the visible oak floor once.
	var skeleton: Skeleton3D = _player.skeleton
	if not is_instance_valid(skeleton): return
	skeleton.set_bone_pose_position(_player.hips,_player.hip_rest)
	for side in ["Left","Right"]:
		var foot := skeleton.find_bone(side+"Foot")
		if foot < 0: continue
		_player._set_combat_bone_rotation(foot,skeleton.get_bone_global_rest(foot).basis)
		var target := skeleton.to_global(skeleton.get_bone_global_pose(foot).origin)
		target.y = skeleton.to_global(skeleton.get_bone_global_rest(foot).origin).y
		_player._solve_leg(side,target)
	var mesh: MeshInstance3D = _player.visual.find_child("Mesh0",true,false)
	if mesh == null or mesh.skin == null: return
	var poses: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		if bone < 0: return
		poses.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
	var lowest := INF
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var influences: int = arrays[Mesh.ARRAY_BONES].size()/maxi(1,vertices.size())
		for index in vertices.size():
			if vertices[index].y > .22: continue
			var point := Vector3.ZERO
			for slot in influences:
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][index*influences+slot]
				if weight <= 0: continue
				point += (poses[arrays[Mesh.ARRAY_BONES][index*influences+slot]]*vertices[index])*weight
			lowest = minf(lowest,point.y)
	if is_finite(lowest): _player.visual.global_position.y += _model.global_position.y+.008-lowest
	skeleton.force_update_all_bone_transforms()
	_player.visual.reset_physics_interpolation()

func preview_weapon(id: String, force := false, custom_state: Variant = null) -> void:
	if station != "arsenal" or not is_instance_valid(_model) or (id == _selected_weapon and not force): return
	_selected_weapon = id
	if is_instance_valid(weapon_preview):
		weapon_preview.get_parent().remove_child(weapon_preview)
		weapon_preview.queue_free()
	weapon_preview = null
	if id.is_empty() or id == "fists": return
	weapon_preview = Node3D.new()
	weapon_preview.name = "SelectedBenchWeapon"
	_model.add_child(weapon_preview)
	var muzzle := WEAPON_MODEL.build_cached(weapon_preview, id)
	CUSTOM.fit(weapon_preview,id,session.world.gameplay.customization if custom_state == null else custom_state,muzzle)
	# Guns are authored pointing -Z. Lay the original side profile flat on the
	# bench and centre the geometry from its actual bounds, including long arms.
	weapon_preview.basis = Basis(Vector3.UP, PI * .5) * Basis(Vector3.FORWARD, PI * .5)
	var bounds := AABB()
	var first := true
	for part in weapon_preview.find_children("*", "MeshInstance3D", true, false):
		var local: AABB = weapon_preview.global_transform.affine_inverse() * part.global_transform * part.get_aabb()
		var rotated: AABB = Transform3D(weapon_preview.basis, Vector3.ZERO) * local
		bounds = rotated if first else bounds.merge(rotated)
		first = false
	if first: return
	var fit := minf(1.0, 2.24 / maxf(bounds.size.x, .01))
	weapon_preview.scale = Vector3.ONE * fit
	var anchor: Vector3 = _model.presentation_points.arsenal
	weapon_preview.position = anchor + Vector3(-bounds.get_center().x * fit, .002 - bounds.position.y * fit, -bounds.get_center().z * fit)
	if _weapon_camera_tween != null: _weapon_camera_tween.kill()
	var framing := 1.2 if bounds.size.x * fit < .45 else maxf(1.55,bounds.size.x * fit * .92)
	_weapon_camera_tween = create_tween()
	if _camera_tween != null and _camera_tween.is_running(): _weapon_camera_tween.tween_interval(.56)
	_weapon_camera_tween.tween_property(camera,"size",framing,.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_weapon_camera_tween.parallel().tween_property(camera,"h_offset",framing*.31,.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_rest_amount(value: float) -> void:
	if is_instance_valid(_sole_contacts): _sole_contacts.visible = value <= .001
	if station != "time" or not is_instance_valid(_player) or not is_instance_valid(_model): return
	var amount := clampf(value, 0.0, 1.0)
	var bed: Vector3 = _model.presentation_points.time
	var lying := Transform3D(Basis(Vector3.RIGHT, -PI * .5) * Basis(Vector3.UP, PI), _model.to_global(bed + Vector3(0, .95, .97)))
	_player.visual.global_transform = _visual_global.interpolate_with(lying, smoothstep(0.0, 1.0, amount))
	# Lift over the mattress during the deliberate lay-down/get-up motion.
	_player.visual.global_position.y += sin(amount * PI) * .4

func rest_pose(value: float) -> void:
	set_rest_amount(value)

func _set_fridge_open(open: bool) -> void:
	if not is_instance_valid(_model) or not is_instance_valid(_model.fridge_hinge): return
	if _door_tween != null: _door_tween.kill()
	_door_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_door_tween.tween_property(_model.fridge_hinge, "rotation:y", -1.85 if open else 0.0, .5)

func _start_mirror() -> void:
	var mirror: MeshInstance3D = _model.mirror_mesh
	if not is_instance_valid(mirror): return
	_mirror_material = mirror.material_override
	_mirror_layers = mirror.layers
	mirror.layers = MIRROR_LAYER
	mirror_viewport = SubViewport.new()
	mirror_viewport.name = "WardrobeMirror"
	mirror_viewport.size = Vector2i(384, 768)
	mirror_viewport.world_3d = get_viewport().world_3d
	mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mirror_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(mirror_viewport)
	var reflection := Camera3D.new()
	reflection.cull_mask = 0xFFFFF & ~MIRROR_LAYER
	reflection.projection = Camera3D.PROJECTION_ORTHOGONAL
	reflection.keep_aspect = Camera3D.KEEP_HEIGHT
	reflection.size = 2.05
	# Orthographic specular still uses eye distance. Put the reflected eye
	# behind the glass, clipping the wardrobe at its front face, so nearby
	# hair and cloth retain their normal highlights instead of blowing out.
	reflection.near = 3.09
	reflection.far = 19.07
	mirror_viewport.add_child(reflection)
	var normal: Vector3 = _model.presentation_points.wardrobe_normal
	var subject: Vector3 = _player.global_position + Vector3.UP * .92
	var origin: Vector3 = mirror.global_position - normal * 3.0
	origin.y = subject.y
	origin.z = subject.z
	reflection.look_at_from_position(origin, subject)
	reflection.make_current()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D reflection_image : source_color, filter_linear; void fragment(){ ALBEDO = texture(reflection_image, vec2(1.0-UV.x, UV.y)).rgb * vec3(0.90,0.95,1.0); }"
	var surface := ShaderMaterial.new()
	surface.shader = shader
	surface.set_shader_parameter("reflection_image", mirror_viewport.get_texture())
	mirror.material_override = surface

func _process(_delta: float) -> void:
	if not is_active(): return
	if not is_instance_valid(_room) or _room != session.room or not is_instance_valid(_player) or session.world.gameplay.health <= 0 or session.is_transition_blocked():
		finish()

func finish() -> void:
	if is_instance_valid(_sole_contacts):
		_sole_contacts.free()
	_sole_contacts = null
	if is_instance_valid(_quality_viewport) and not quality_state.is_empty():
		for key in quality_state: _quality_viewport.set(key,quality_state[key])
	quality_state.clear()
	_quality_viewport = null
	if _camera_tween != null: _camera_tween.kill()
	_camera_tween = null
	if _door_tween != null: _door_tween.kill()
	_door_tween = null
	if _weapon_camera_tween != null: _weapon_camera_tween.kill()
	_weapon_camera_tween = null
	if is_instance_valid(_model):
		if is_instance_valid(_model.bench_light): _model.bench_light.visible = false
		if is_instance_valid(_model.fridge_hinge): _model.fridge_hinge.rotation.y = 0.0
		if is_instance_valid(_model.mirror_mesh) and _mirror_material != null:
			_model.mirror_mesh.material_override = _mirror_material
			_model.mirror_mesh.layers = _mirror_layers
	if is_instance_valid(mirror_viewport):
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mirror_viewport.queue_free()
	mirror_viewport = null
	_mirror_material = null
	if is_instance_valid(weapon_preview): weapon_preview.queue_free()
	weapon_preview = null
	_selected_weapon = ""
	if is_instance_valid(_player) and not station.is_empty():
		_player.visual.transform = _visual_transform
		_player.visual.physics_interpolation_mode = _visual_interpolation
		if not _pose.is_empty(): _player._apply_pose(_pose)
		if not _player.dead and session.world.gameplay.health > 0:
			_player.set_physics_process(_physics_enabled)
		_player.reset_physics_interpolation()
	if is_instance_valid(camera):
		if camera.is_current() and is_instance_valid(_previous_camera): _previous_camera.make_current()
		camera.queue_free()
	camera = null
	station = ""
	_room = null
	_model = null
	_player = null
	set_process(false)

func _exit_tree() -> void:
	finish()
