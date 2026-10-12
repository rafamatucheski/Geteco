extends SceneTree
const REVEAL := preload("res://scripts/camera/ExteriorReveal.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("EXTERIOR_REVEAL ","PASS " if value else "FAIL ",label)

func box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var resource := BoxMesh.new()
	resource.size = size
	mesh.mesh = resource
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	var body := StaticBody3D.new()
	mesh.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	return mesh

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,25,25)
	camera.look_at(Vector3.ZERO)
	var target := CharacterBody3D.new()
	stage.add_child(target)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ce9466")
	var wall := box(stage,Vector3(0,4,5),Vector3(12,8,1),material)
	wall.add_to_group(REVEAL.BUILDING_GROUP)
	var unrelated := box(stage,Vector3(20,4,5),Vector3(12,8,1),material)
	unrelated.add_to_group(REVEAL.BUILDING_GROUP)
	var street_prop := box(stage,Vector3(0,2,3),Vector3(.4,4,.4),material)
	var floor := box(stage,Vector3(0,-.2,0),Vector3(60,.4,60),material)
	var player_art := box(target,Vector3(0,1,0),Vector3(.6,2,.6),material)
	var reveal := REVEAL.new()
	await physics_frame
	await physics_frame
	for i in 5: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(not reveal.enabled and wall.material_override == material,"normal exterior keeps the foreground wall opaque")
	check(reveal._clock == 0.0 and reveal.last_query_hits == 0 and reveal._states.is_empty() and reveal._materials.is_empty() and reveal._scopes.is_empty(),"disabled exterior window does no queries or material capture")
	check(reveal.debug_snapshot().parameter_writes == 0 and reveal.debug_snapshot().instance_writes == 0,"disabled exterior window sends no shader parameters")
	reveal.enabled = true
	for i in 5: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(wall.material_override is ShaderMaterial,"foreground wall reveals")
	check(street_prop.material_override == material,"untagged street prop stays opaque in the sightline")
	check(unrelated.material_override == material,"shared material stays intact elsewhere")
	check(floor.material_override == material,"floor stays solid and opaque")
	check(player_art.material_override == material,"target never fades")
	check(material.albedo_color == Color("ce9466"),"source material unchanged")
	check(wall.get_child(0).collision_layer == 1,"collision stays enabled")
	if wall.material_override is ShaderMaterial:
		check(wall.material_override.get_shader_parameter("reveal_origin") == reveal._origin and wall.material_override.get_shader_parameter("reveal_ahead") == Vector3.ZERO,"first upload initializes origin and zero lead")
		var settled := reveal.debug_snapshot()
		for i in 4: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
		var still := reveal.debug_snapshot()
		check(still.parameter_writes == settled.parameter_writes and still.instance_writes == settled.instance_writes,"stationary reveal keeps scanning without redundant uploads")
	for i in 5: reveal.update(camera,target,true,Vector3(18,0,0),.1,true)
	check(reveal._radius > 4 and reveal._lead.x > 4,"driving widens and anticipates path")
	reveal.enabled = false
	check(wall.material_override == material and reveal._states.is_empty(),"disabling diagnostic restores walls immediately without another camera frame")
	var disabled_snapshot := reveal.debug_snapshot()
	var disabled_clock := reveal._clock
	for i in 5: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(reveal.debug_snapshot() == disabled_snapshot and reveal._clock == disabled_clock,"disabled diagnostic remains idle after restoring materials")
	reveal.enabled = true
	for i in 5: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	reveal.update(camera,target,false,Vector3.ZERO,.1,false)
	check(wall.material_override == material and reveal._states.is_empty(),"authored camera transition restores material")
	for i in 5: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	wall.queue_free()
	await process_frame
	reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(reveal._states.is_empty(),"streaming removal clears ownership")
	var replacement := box(stage,Vector3(0,4,5),Vector3(12,8,1),material)
	replacement.add_to_group(REVEAL.BUILDING_GROUP)
	await physics_frame
	for i in 9: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(replacement.material_override is ShaderMaterial,"returning geometry is detected")
	if replacement.material_override is ShaderMaterial:
		check(replacement.material_override.get_shader_parameter("reveal_radius") == reveal._radius and replacement.material_override.get_shader_parameter("reveal_origin") == reveal._origin,"returning geometry receives current uniforms while stationary")
	var external := StandardMaterial3D.new()
	replacement.material_override = external
	reveal.release()
	check(replacement.material_override == external,"cleanup preserves another owner's material change")
	check(reveal._materials.is_empty() and reveal._scopes.is_empty(),"resources released")
	var authored := ShaderMaterial.new()
	var authored_shader := Shader.new()
	authored_shader.code = "shader_type spatial; render_mode cull_disabled; uniform vec4 paint : source_color; void fragment() { ALBEDO = paint.rgb; ROUGHNESS = 0.9; }"
	authored.shader = authored_shader
	authored.set_shader_parameter("paint",Color("703b22"))
	replacement.material_override = authored
	for i in 10: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(replacement.material_override != authored,"authored roof shader receives reveal")
	check(replacement.material_override.get_shader_parameter("paint") == Color("703b22"),"authored shader uniforms preserved")
	check(not "reveal_origin" in authored_shader.code,"shared authored shader untouched")
	authored.set_shader_parameter("paint",Color("226688"))
	for i in 2: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(replacement.material_override.get_shader_parameter("paint") == Color("226688"),"animated source uniforms stay current")
	var rig := preload("res://scripts/CameraRig.gd").new()
	check(not rig._exterior_reveal.enabled,"production camera leaves exterior transparency disabled by default")
	stage.add_child(rig)
	rig.set_process(false)
	rig._exterior_reveal = reveal
	rig.locked = true
	check(replacement.material_override == authored and reveal._states.is_empty(),"locking camera restores immediately even with processing disabled")
	var concrete := StandardMaterial3D.new()
	concrete.uv1_triplanar = true
	concrete.uv1_world_triplanar = true
	replacement.material_override = concrete
	for i in 10: reveal.update(camera,target,false,Vector3.ZERO,.1,true)
	check(replacement.material_override is ShaderMaterial,"triplanar roof and viaduct materials reveal the actual body")
	check(replacement.material_override.get_shader_parameter("world_triplanar") == true,"world texture projection retained")
	check(REVEAL.source_material(replacement.material_override) == concrete,"derived geometry can recover authored material")
	var copied_roof := box(stage,Vector3(0,6,6),Vector3(8,.1,8),replacement.material_override)
	reveal._capture(copied_roof)
	check(reveal._states.has(copied_roof.get_instance_id()),"copied roof joins reveal instead of staying opaque")
	reveal.release()
	check(copied_roof.material_override == concrete,"copied roof restores authored material")
	check(replacement.material_override == concrete,"triplanar material restored")
	stage.free()
	print("EXTERIOR_REVEAL_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
