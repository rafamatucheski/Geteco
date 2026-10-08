extends SceneTree
## Rendered regression: the real passenger train moves through the room's
## camera rays while its physical bodies and all uncut PBR pixels are retained.
const SIGHTLINE := preload("res://world/places/harbor_buildings/HarborBuildingSightline.gd")
const TRAIN := preload("res://world/railway/TrainModel.gd")
var scene: Node3D
var camera: Camera3D
var train: Node3D
var sightline: Node3D
var checks := 0
var failures: Array[String] = []
var evidence := ""
var definition := {"id":"MovingFixture","source_id":"MovingFixture","floor_count":3,"storey_height":3.0,"size":Vector2(10,10),"exterior_position":Vector3.ZERO,"exterior_rotation":0.0}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("MOVING_SIGHTLINE ","PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)

func capture(label: String) -> Image:
	for frame: int in 5: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(evidence.path_join(label+".png"))
	return image

func difference(a: Image, b: Image) -> float:
	var total := 0.0
	for y: int in a.get_height():
		for x: int in a.get_width():
			var delta: Color = a.get_pixel(x,y)-b.get_pixel(x,y)
			total += absf(delta.r)+absf(delta.g)+absf(delta.b)
	return total/(float(a.get_width()*a.get_height())*3.0)

func witness_pixels(image: Image) -> int:
	var total := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var value: Color = image.get_pixel(x,y)
			if value.r>.85 and value.b>.85 and value.g<.18: total += 1
	return total

func geometry_snapshot(owner: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in owner.find_children("*","GeometryInstance3D",true,false):
		var item := {"node":node,"override":node.material_override,"overlay":node.material_overlay,"layers":node.layers,"shadow":node.cast_shadow,"surfaces":[]}
		if node is MeshInstance3D:
			item.mesh = node.mesh
			for index: int in node.mesh.get_surface_count(): item.surfaces.append(node.get_surface_override_material(index))
		elif node is MultiMeshInstance3D: item.multimesh = node.multimesh
		result.append(item)
	return result

func matches(snapshot: Array[Dictionary], materials := true) -> bool:
	for item: Dictionary in snapshot:
		var node: GeometryInstance3D = item.node
		if materials and node.material_override!=item.override: return false
		if node.material_overlay!=item.overlay or node.layers!=item.layers or node.cast_shadow!=item.shadow: return false
		if node is MeshInstance3D:
			if node.mesh!=item.mesh: return false
			if materials:
				for index: int in item.surfaces.size():
					if node.get_surface_override_material(index)!=item.surfaces[index]: return false
		elif node is MultiMeshInstance3D and node.multimesh!=item.multimesh: return false
	return true

func physical_hit() -> bool:
	var query := PhysicsRayQueryParameters3D.create(Vector3(0,18,8),Vector3(0,4,8),1)
	return not scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func place_train(x: float) -> void:
	train.position = Vector3(x,5,8)
	train.rotation.y = PI*.5
	train.advance_wheels(.8)
	train.set_doors_open(x<0)
	train.reset_physics_interpolation()

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("MOVING_SIGHTLINE requires the real renderer")
		quit(2)
		return
	create_timer(90).timeout.connect(func(): push_error("MOVING_SIGHTLINE timeout"); quit(3))
	evidence = "res://evidence/harbor-building-moving-sightline-%d-%d"%[OS.get_process_id(),Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(evidence)
	root.size = Vector2i(960,540)
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.use_taa = false
	scene = Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.11,.14,.17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .75
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-28,0)
	light.light_energy = 1.2
	scene.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28
	scene.add_child(camera)
	camera.position = Vector3(0,18,16)
	camera.look_at(Vector3(0,0,1))
	camera.current = true
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(1,0,1)
	for x: float in [-2.0,0.0,2.0]:
		var witness := MeshInstance3D.new()
		var shape := CapsuleMesh.new()
		shape.height = 1.8
		shape.radius = .3
		shape.material = marker_material
		witness.mesh = shape
		witness.position = Vector3(x,.9,2.5)
		scene.add_child(witness)
	train = TRAIN.new()
	scene.add_child(train)
	place_train(0)
	var original := geometry_snapshot(train)
	sightline = SIGHTLINE.new()
	scene.add_child(sightline)
	await physics_frame
	await physics_frame
	train.hide()
	var unobstructed: Image = await capture("00-witness-control")
	var full_witness: int = witness_pixels(unobstructed)
	train.show()
	var baseline: Image = await capture("01-original-train")
	check(full_witness>200 and witness_pixels(baseline)<full_witness*.65,"control: real coach occludes the standing room witnesses")
	check(physical_hit(),"control: authored train body is solid on the same passage")
	var distant := definition.duplicate(true)
	distant.exterior_position = Vector3(100,0,100)
	sightline.configure(distant,0)
	var adapted: Image = await capture("02-uncut-material-control")
	var unchanged: float = difference(baseline,adapted)
	print("MOVING_SIGHTLINE_MATERIAL_DIFFERENCE ",unchanged)
	check(unchanged<.001,"train outside the clip prism retains original rendered PBR appearance")
	check(sightline.debug_snapshot().moving.geometry==original.size(),"all coach/engine/door batches and wheel meshes receive an adapter")
	check(sightline.debug_snapshot().moving.materials==9,"nine authored train materials share nine shader material instances")
	check(matches(original,false),"all original geometry, layers, overlays and shadow settings remain intact")
	sightline.configure(definition,0)
	for x: float in [-4.0,0.0,4.0]:
		place_train(x)
		await physics_frame
		await physics_frame
		var passing: Image = await capture("03-passage-%s"%str(x).replace("-","minus"))
		var visible: int = witness_pixels(passing)
		print("MOVING_SIGHTLINE_WITNESSES x=",x," pixels=",visible," full=",full_witness)
		check(visible>=full_witness*.98,"moving coach exposes all room witnesses at x=%s"%x)
		check(matches(original,false),"moving clip preserves real train geometry at x=%s"%x)
	place_train(0)
	await physics_frame
	await physics_frame
	check(physical_hit(),"train collision still blocks the original passage after clipping and motion")
	sightline.configure(definition,3,true)
	var roof: Image = await capture("04-rooftop-restored")
	check(matches(original) and difference(baseline,roof)<.001,"rooftop restores exact material owners and original train appearance")
	sightline.configure(definition,0)
	sightline.clear()
	check(matches(original),"exit/reset restore every original material override")
	sightline.configure(definition,0)
	var streamed := TRAIN.new()
	streamed.position = Vector3(45,5,8)
	scene.add_child(streamed)
	var streamed_original := geometry_snapshot(streamed)
	await process_frame
	await process_frame
	check(not matches(streamed_original),"a train added during the visit receives local clipping without a world rescan")
	sightline.clear()
	check(matches(streamed_original),"exit restores materials of trains added during the visit")
	sightline.configure(definition,0)
	var cancelled := TRAIN.new()
	cancelled.position = Vector3(-45,5,8)
	scene.add_child(cancelled)
	var cancelled_original := geometry_snapshot(cancelled)
	sightline.clear()
	await process_frame
	await process_frame
	check(matches(cancelled_original),"exit cancels deferred adapters from a stale building generation")
	sightline.configure(definition,0)
	var transient := TRAIN.new()
	scene.add_child(transient)
	transient.free()
	await process_frame
	await process_frame
	check(sightline.debug_snapshot().moving.geometry==original.size()+streamed_original.size()+cancelled_original.size(),"rapid streaming deletion drops weak callbacks without retaining freed train geometry")
	sightline.queue_free()
	await process_frame
	await process_frame
	check(matches(original) and matches(streamed_original) and matches(cancelled_original),"owner deletion restores all surviving trains")
	var report := {"checks":checks,"failures":failures,"material_mean_difference":unchanged,"witness_pixels":full_witness,"evidence":evidence}
	var output := FileAccess.open(evidence.path_join("result.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("MOVING_SIGHTLINE_RESULT ",JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
