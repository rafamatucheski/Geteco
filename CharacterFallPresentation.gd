extends RefCounted
## Queda visual compartilhada. A física do ator continua responsável pelo
## deslocamento no mundo; o rig articula o corpo e a sombra fica no plano do chão.
var started := false
var active := false
var elapsed := 0.0
var duration := 1.05
var airborne := false
var rig: Node3D
var viewport: SubViewport
var shadow: MeshInstance3D
var initial_transform := Transform3D.IDENTITY
var initial_rotation := Vector3.ZERO
var initial_shadow := Transform3D.IDENTITY
var initial_alpha := 0.5
var yaw := 0.0
var joints: Array[Dictionary] = []
var camera: Camera3D
var camera_transform := Transform3D.IDENTITY
var camera_focus := Vector3.ZERO
var camera_fov := 36.0
var camera_size := 2.6

func start(actor: Node, model: Node3D, render: SubViewport, impact := Vector2.ZERO) -> void:
	if started or not is_instance_valid(model): return
	started = true
	active = true
	elapsed = 0.0
	rig = model
	viewport = render
	camera = viewport.get_camera_3d()
	if camera:
		camera_transform = camera.transform
		camera_fov = camera.fov
		camera_size = camera.size
		var forward := -camera.basis.z
		camera_focus = Vector3(0, camera.position.y - camera.position.z * forward.y / forward.z, 0) if absf(forward.z) > 0.001 else Vector3(0, 0, camera.position.z)
	initial_transform = rig.transform
	initial_rotation = rig.rotation
	airborne = impact.length() > 1.0
	duration = 0.95 if airborne else 1.05
	yaw = -impact.angle() - PI * 0.5 if airborne else rig.rotation.y
	shadow = viewport.get_node_or_null("GroundShadow") as MeshInstance3D
	if shadow == null:
		shadow = MeshInstance3D.new()
		shadow.name = "GroundShadow"
		var disk := CylinderMesh.new()
		disk.top_radius = 0.28
		disk.bottom_radius = 0.28
		disk.height = 0.008
		shadow.mesh = disk
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.02, 0.02, 0.04, 0.5)
		shadow.material_override = material
		shadow.position.y = 0.008
		viewport.add_child(shadow)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	initial_shadow = shadow.transform
	initial_alpha = shadow.material_override.albedo_color.a
	var poses := {
		"left_upper_leg": [Vector3(-0.48, 0, -0.08), Vector3(-0.10, 0, -0.14)],
		"right_upper_leg": [Vector3(-0.32, 0, 0.08), Vector3(0.12, 0, 0.12)],
		"left_lower_leg": [Vector3(0.95, 0, 0), Vector3(0.30, 0, 0)],
		"right_lower_leg": [Vector3(0.75, 0, 0), Vector3(0.16, 0, 0)],
		"left_upper_arm": [Vector3(-0.65, 0, -0.50), Vector3(-0.22, 0, -0.48)],
		"right_upper_arm": [Vector3(-0.85, 0, 0.55), Vector3(-0.42, 0, 0.62)],
		"left_lower_arm": [Vector3(0.45, 0, 0), Vector3(0.32, 0, 0)],
		"right_lower_arm": [Vector3(0.55, 0, 0), Vector3(0.50, 0, 0)]
	}
	for key in poses:
		var joint := actor.get(key) as Node3D
		if is_instance_valid(joint):
			joints.append({"node": joint, "initial": joint.rotation, "brace": poses[key][0], "rest": poses[key][1]})
	# Os moradores da montanha/motoristas usam quatro articulações mais simples.
	if joints.is_empty() and rig.get("limbs") is Array:
		var limbs: Array = rig.get("limbs")
		for i in limbs.size():
			var joint := limbs[i] as Node3D
			var side := -1.0 if i < 2 else 1.0
			joints.append({"node": joint, "initial": joint.rotation, "brace": Vector3(-0.4, 0, side * 0.4), "rest": Vector3(0.12, 0, side * (0.5 if i % 2 else 0.12))})
	update(0.0)

func update(delta: float) -> void:
	if not active or not is_instance_valid(rig): return
	elapsed = minf(duration, elapsed + maxf(0.0, delta))
	var progress := elapsed / duration
	var fall := smoothstep(0.12, 0.78, progress)
	var brace := smoothstep(0.0, 0.35, progress)
	var settle := smoothstep(0.55, 1.0, progress)
	var bounce := sin(clampf((progress - 0.78) / 0.22, 0.0, 1.0) * PI) * 0.055
	var pitch := fall * PI * 0.5 - bounce
	var facing := lerp_angle(initial_rotation.y, yaw, brace)
	rig.rotation = Vector3(pitch, facing, lerpf(initial_rotation.z, 0.06, fall))
	var height := 0.32 * sin(clampf(progress / 0.70, 0.0, 1.0) * PI) if airborne else -0.10 * sin(progress * PI)
	var center := Basis(Vector3.UP, facing) * Vector3(0, lerpf(0.0, 0.23, fall) + height, -0.68 * rig.scale.y * sin(pitch))
	rig.position = initial_transform.origin + center
	for pose in joints:
		if is_instance_valid(pose.node):
			pose.node.rotation = (pose.initial as Vector3).lerp(pose.brace, brace).lerp(pose.rest, settle)
	# Apenas yaw no disco: nunca herdar inclinação/altura do corpo.
	shadow.rotation = Vector3(0, facing, 0)
	shadow.position = initial_shadow.origin
	shadow.scale = Vector3(lerpf(1.0, 1.05, fall), 1.0, lerpf(1.0, 2.8 * rig.scale.y, fall))
	shadow.material_override.albedo_color.a = initial_alpha * (1.0 - maxf(0.0, height) * 1.2)
	# O enquadramento em pé mira o peito. No chão precisa mirar o corpo inteiro,
	# senão cabeça e mãos desaparecem nas bordas do SubViewport.
	if camera:
		# O IML usa câmera vertical; seu eixo de cima original evita a
		# singularidade de look_at com direção paralela ao eixo Y do mundo.
		camera.look_at(camera_focus.lerp(Vector3(0, 0.20, 0), fall), camera_transform.basis.y.normalized())
		camera.fov = lerpf(camera_fov, maxf(camera_fov, 40.0), fall)
		camera.size = lerpf(camera_size, maxf(camera_size, 2.6), fall)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	active = elapsed < duration

func reset() -> void:
	if is_instance_valid(rig): rig.transform = initial_transform
	for pose in joints:
		if is_instance_valid(pose.node): pose.node.rotation = pose.initial
	if is_instance_valid(shadow):
		shadow.transform = initial_shadow
		shadow.material_override.albedo_color.a = initial_alpha
	if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if is_instance_valid(camera):
		camera.transform = camera_transform
		camera.fov = camera_fov
		camera.size = camera_size
	joints.clear()
	started = false
	active = false
	elapsed = 0.0
