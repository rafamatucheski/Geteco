extends SceneTree
## Private semantic contract; headless is not rendering/FPS approval.
const ORIGINAL = preload("res://tests/fixtures/GroundBlood3D_before_first_material.gd")
const CANDIDATE = preload("res://gameplay/street_physics/GroundBlood3D.gd")
const PROPS := ["albedo_color", "transparency", "depth_draw_mode", "roughness", "metallic_specular", "render_priority", "cull_mode"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _same_stain(control: Dictionary, candidate: Dictionary, label: String) -> void:
	_check(control.radius == candidate.radius, label + " radius/RNG")
	_check(control.node.global_transform.is_equal_approx(candidate.node.global_transform), label + " transform/raycast/RNG")
	_check(control.node.scale.is_equal_approx(candidate.node.scale), label + " scale")
	_check(control.target_scale.is_equal_approx(candidate.target_scale), label + " target scale")
	_check(control.node.cast_shadow == candidate.node.cast_shadow, label + " shadow")
	_check(control.grow == candidate.grow and control.lifetime == candidate.lifetime and control.lethal == candidate.lethal, label + " lifecycle")
	for prop in PROPS:
		_check(control.material.get(prop) == candidate.material.get(prop), label + " material " + prop)


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	root.add_child(floor_body)
	floor_body.position.y = -0.5
	var control := ORIGINAL.new()
	var candidate := CANDIDATE.new()
	root.add_child(control)
	root.add_child(candidate)
	await physics_frame
	_check(control.stains.is_empty() and candidate.stains.is_empty(), "ready no stains")
	_check(control.corpses.is_empty() and candidate.corpses.is_empty(), "ready no corpses")
	_check(control.get_child_count() == 0 and candidate.get_child_count() == 0, "ready no extra nodes")
	_check(control._meshes.size() == 8 and candidate._meshes.size() == 8, "exact eight shapes")
	for index in 8:
		_check(control._meshes[index].get_surface_count() == candidate._meshes[index].get_surface_count(), "shape surfaces " + str(index))
		_check(control._meshes[index].surface_get_arrays(0) == candidate._meshes[index].surface_get_arrays(0), "shape arrays " + str(index))
	var template: StandardMaterial3D = candidate._shader_template
	var template_rid: RID = template.get_rid()
	_check(template != null and template_rid.is_valid(), "ready retained template/RID")
	var expected: StandardMaterial3D = control._material()
	for prop in PROPS:
		_check(template.get(prop) == expected.get(prop), "template prop " + prop)
	control._rng.seed = 947211
	candidate._rng.seed = 947211
	var rng_before: int = candidate._rng.state
	candidate._prepare_material_template()
	_check(candidate._shader_template == template and template.get_rid() == template_rid, "prepare repeat retains one template/RID")
	_check(candidate._rng.state == rng_before, "prepare consumes no RNG")
	var first_control: Dictionary = control.spawn_drip(Vector3.ZERO, 0.35)
	var first_candidate: Dictionary = candidate.spawn_drip(Vector3.ZERO, 0.35)
	_same_stain(first_control, first_candidate, "first")
	_check(first_candidate.material != template, "template never handed to first stain")
	var next_control: Dictionary = control.spawn_pool(Vector3(1, 0, 0), false)
	var next_candidate: Dictionary = candidate.spawn_pool(Vector3(1, 0, 0), false)
	_same_stain(next_control, next_candidate, "next")
	_check(next_candidate.material != template and next_candidate.material != first_candidate.material, "every stain has own material")
	_check(control._rng.state == candidate._rng.state, "RNG after material creation")
	first_control.age = 12.0
	first_candidate.age = 12.0
	control._process(0.0)
	candidate._process(0.0)
	_same_stain(first_control, first_candidate, "dry/fade")
	_check(first_candidate.material.albedo_color != next_candidate.material.albedo_color, "independent stain color/fade")
	for prop in PROPS:
		_check(template.get(prop) == expected.get(prop), "template immutable after fade " + prop)
	var oldest_control: MeshInstance3D = first_control.node
	var oldest_candidate: MeshInstance3D = first_candidate.node
	for index in 65:
		var a: Dictionary = control.spawn_drip(Vector3(index * 0.1, 0, 1), 0.5)
		var b: Dictionary = candidate.spawn_drip(Vector3(index * 0.1, 0, 1), 0.5)
		_same_stain(a, b, "budget " + str(index))
		_check(b.material != template, "template never handed in budget " + str(index))
	_check(control.stains.size() == 64 and candidate.stains.size() == 64, "budget remains64")
	_check(control._rng.state == candidate._rng.state, "RNG after budget eviction")
	await process_frame
	_check(not is_instance_valid(oldest_control) and not is_instance_valid(oldest_candidate), "oldest queued/free lifecycle")
	_check(control.get_child_count() == 64 and candidate.get_child_count() == 64, "no pooled/new retained nodes")
	control._process(19.0)
	candidate._process(19.0)
	_check(control.stains.is_empty() and candidate.stains.is_empty(), "expire all stains before return")
	await process_frame
	_check(control.get_child_count() == 0 and candidate.get_child_count() == 0, "all expired nodes freed")
	_check(candidate._shader_template == template and template.get_rid() == template_rid, "template/RID retained with zero stains")
	for prop in PROPS:
		_check(template.get(prop) == expected.get(prop), "template immutable after all expired " + prop)
	var return_control: Dictionary = control.spawn_drip(Vector3(3, 0, 2), 0.7)
	var return_candidate: Dictionary = candidate.spawn_drip(Vector3(3, 0, 2), 0.7)
	_same_stain(return_control, return_candidate, "return after empty")
	_check(return_candidate.material != template and return_candidate.material != first_candidate.material, "return material own")
	_check(candidate._shader_template == template and template.get_rid() == template_rid, "same retained RID after return")
	_check(control._rng.state == candidate._rng.state, "RNG after zero-stain return")
	var template_weak: WeakRef = weakref(template)
	template = null
	control.queue_free()
	candidate.queue_free()
	floor_body.queue_free()
	await process_frame
	_check(not is_instance_valid(control) and not is_instance_valid(candidate), "owner lifecycle releases nodes")
	_check(template_weak.get_ref() == null, "template resource released with owner")
	print("GROUND_BLOOD_TEMPLATE_CONTRACT checks=" + str(checks) + " failures=" + str(failures.size()) + " " + str(failures))
	quit(0 if failures.is_empty() else 1)
