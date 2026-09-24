extends "res://world/mountain_pass/MountainPineTree.gd"
## O mesmo modelo projetado e a mesma escala dos atores. Renders estáticos
## são compartilhados pela floresta inteira, sem um viewport por árvore.
static var _views: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _atlas_worker: PineAtlasQueueWorker
const ATLAS_BUILD_BUDGET_USEC := 1200
const RUNTIME_WORK := preload("res://systems/RuntimeWorkScheduler.gd")

class PineAtlasQueueWorker:
	extends Node
	var jobs: Array[Dictionary] = []
	var running := false
	var owner_script: Script

	func enqueue(job: Dictionary) -> void:
		jobs.append(job)
		if not running:
			_drain.call_deferred()

	func _drain() -> void:
		if running:
			return
		running = true
		while not jobs.is_empty():
			var item: Dictionary = jobs.pop_front()
			var view := (item.viewport as WeakRef).get_ref() as SubViewport
			if is_instance_valid(view):
				await owner_script.call(
					"_populate_shared_view",
					view,
					int(item.variant),
					bool(item.snowy),
					String(item.key),
					get_tree()
				)
		running = false

	func _exit_tree() -> void:
		jobs.clear()
		running = false
		if owner_script != null:
			owner_script.call("_release_atlas_cache")

var presentation: Sprite2D
var _last_ice_impact := -10000
var _atlas_ready := false

func _ready() -> void:
	super._ready()
	var variant := posmod(variant_seed, 8)
	# Low conifer boughs occupy space at bonnet height. Keep the original
	# single static shape, but include these solid branches in its footprint.
	# Bare trunks and trees with raised crowns retain a narrower passage.
	if enable_collision:
		var clearance: float = [32.0,24.0,22.0,10.0,12.0,7.0,18.0,25.0][variant]
		get_node("TrunkCol").shape.radius = clearance * tree_scale
	var key := "%d_%d" % [int(is_snowy), variant]
	var data: Dictionary = _views.get(key, {})
	if data.is_empty() or not is_instance_valid(data.viewport.get_ref()):
		data = _create_shared_view_shell(variant, key)
		data["waiters"] = []
		_views[key] = data
		var tree_loop := Engine.get_main_loop() as SceneTree
		var worker := _atlas_worker_for(tree_loop, get_script())
		worker.enqueue({
			"key": key,
			"variant": variant,
			"snowy": is_snowy,
			"viewport": weakref(data.viewport.get_ref()),
		})
	var atlas_view := data.viewport.get_ref() as SubViewport
	_atlas_ready = is_instance_valid(atlas_view) and bool(atlas_view.get_meta("pine_atlas_ready", false))
	if not _atlas_ready:
		var waiters: Array = data.get("waiters", [])
		waiters.append(weakref(self))
		data["waiters"] = waiters
		_views[key] = data
	var sprite := Sprite2D.new()
	presentation = sprite
	sprite.texture = data.texture
	sprite.scale = Vector2.ONE * float(data.scale) * tree_scale
	sprite.position = Vector2(data.offset) * tree_scale
	add_child(sprite)
	# A copa projetada sobe muito acima da base. Sem repintá-la sobre quem
	# passa atrás do tronco, o ator (z 10) aparecia em pé em cima da árvore.
	# Margem curta: na floresta densa a área encosta em muitos troncos vizinhos.
	if enable_collision:
		preload("res://systems/interiors/ExteriorOcclusion.gd").attach(sprite, 3.0 * tree_scale, 80.0)
	set_meta("forest_species",["pine","fir","young_pine","birch","rowan","bare_tree","old_pine","leaning_fir"][variant])
	if posmod(variant_seed,3)==0 or variant==4:
		var details := preload("res://world/mountain_pass/ForestFloorDetails.gd").new()
		details.variant_seed = variant_seed
		details.fruiting = variant==4 and not is_snowy
		details.snowy = is_snowy
		details.scale = Vector2.ONE*tree_scale
		add_child(details)

func receive_vehicle_contact(speed: float, direction: Vector2, vehicle: CharacterBody2D) -> void:
	if not is_snowy or speed<35.0: return
	var now := Time.get_ticks_msec()
	if now-_last_ice_impact<2200: return
	_last_ice_impact = now
	preload("res://world/mountain_pass/TreeIceFall.gd").spawn(self,vehicle,direction,speed)
	if is_instance_valid(presentation):
		var origin := presentation.position
		var shake := create_tween()
		shake.tween_property(presentation,"position",origin+direction*2.5,.08)
		shake.tween_property(presentation,"position",origin-direction*1.5,.12)
		shake.tween_property(presentation,"position",origin,.22)

func _draw() -> void:
	if not _atlas_ready:
		super._draw()
		return
	if not _shadow_poly.is_empty():
		draw_colored_polygon(_shadow_poly, Color(0.02,0.035,0.045,0.25))

func _atlas_became_ready() -> void:
	_atlas_ready = true
	queue_redraw()

static func _atlas_worker_for(tree_loop: SceneTree, owner_script: Script) -> PineAtlasQueueWorker:
	if is_instance_valid(_atlas_worker):
		return _atlas_worker
	_atlas_worker = PineAtlasQueueWorker.new()
	_atlas_worker.name = "MountainPineAtlasWorker"
	_atlas_worker.owner_script = owner_script
	tree_loop.root.call_deferred("add_child", _atlas_worker)
	return _atlas_worker

func _create_shared_view_shell(variant: int, key: String) -> Dictionary:
	var view := SubViewport.new()
	view.name = "PineAtlas_%d_%d" % [int(is_snowy), variant]
	view.size = Vector2i(160, 224)
	view.transparent_bg = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.set_meta("pine_atlas_key", key)
	view.set_meta("pine_atlas_ready", false)
	view.set_meta("pine_atlas_peak_stage_usec", 0)
	view.set_meta("pine_atlas_stage_samples", [])
	# Nasce sob a raiz da árvore de cena, adiada por um quadro -- mesmo padrão
	# de StreetLamp._get_shared_lamp_data() (tree.root.call_deferred). O pai
	# desta árvore de memorial pode estar "ocupado montando filhos" quando
	# várias nascem juntas dentro de uma subárvore pré-montada (cena
	# congelada pelo bake de distrito), e o Godot recusa add_child síncrono
	# nesse instante. Por isso a câmera abaixo usa look_at_from_position() e
	# a projeção é calculada à mão em vez de unproject_position(): nenhuma
	# das duas pode depender da câmera já estar dentro da árvore.
	var tree_loop := Engine.get_main_loop() as SceneTree
	if tree_loop != null and tree_loop.root != null:
		tree_loop.root.call_deferred("add_child", view)
	else:
		get_tree().root.call_deferred("add_child", view)
	var camera_position := Vector3(0,10,6)
	var camera_target := Vector3(0,2.0,0)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = camera_position
	camera.look_at_from_position(camera_position, camera_target)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Equivalente analítico do que unproject_position() daria, sem exigir que
	# a câmera esteja dentro da árvore (ela nasce adiada, ver acima). Câmera
	# ortogonal: a escala (pixels por unidade de mundo) é uniforme e não
	# depende de rotação -- só de view.size/camera.size. O deslocamento
	# depende da orientação, calculada com a mesma convenção que
	# Basis.looking_at() usa por baixo de look_at_from_position() (a câmera
	# olha ao longo do -Z local).
	var basis_z := -(camera_target - camera_position).normalized()
	var basis_x := Vector3.UP.cross(basis_z).normalized()
	var basis_y := basis_z.cross(basis_x).normalized()
	var pixels_per_unit := 224.0 / camera.size
	var display_scale := 18.0/pixels_per_unit
	var origin_relative_to_camera := -camera_position
	var offset := Vector2(
		-origin_relative_to_camera.dot(basis_x),
		origin_relative_to_camera.dot(basis_y)
	) * 18.0
	var tex := view.get_texture()
	return {"viewport":weakref(view),"texture":tex,"scale":display_scale,"offset":offset}

static func _populate_shared_view(view: SubViewport, variant: int, snowy: bool, key: String, tree_loop: SceneTree) -> void:
	# The shell is attached first. Registration, geometry generation and the
	# one-shot draws are then spread across process frames by one global queue.
	await tree_loop.process_frame
	if not is_instance_valid(view):
		return
	var ticket: Dictionary = await RUNTIME_WORK.reserve(
		view,
		&"mountain_pine_atlas",
		RUNTIME_WORK.PRIORITY_VISIBLE,
		ATLAS_BUILD_BUDGET_USEC)
	if ticket.is_empty():
		return
	var slice_started := Time.get_ticks_usec()
	var build_batches: Dictionary = {}
	var tree := Node3D.new()
	view.add_child(tree)
	var trunk_color := Color("acb5aa") if variant == 3 else Color("554333")
	var trunk := _shared_material(trunk_color)
	var needles := _shared_material([Color("294337"),Color("345140"),Color("3e5544"),Color("2c4a40")][variant%4])
	var snow := _shared_material(Color("dde9ec"))
	var ice := _shared_material(Color("aacdd9"), .22, .10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3913+variant*89
	_cylinder(build_batches,Vector3(0,1.65,0),.10,.24,3.3,trunk,9)
	for root_side in 5:
		var angle := root_side*TAU/5
		_branch(build_batches,Vector3(0,.22,0),Vector3(cos(angle)*.48,.035,sin(angle)*.48),.06,trunk)
	for mark in 9:
		var scar_basis := Basis.from_euler(Vector3(0, 0, .08*sin(mark*2.1)))
		_cylinder(build_batches,Vector3(.01,.22+mark*.23,.0),.245-mark*.007,.24-mark*.007,.025,trunk if variant!=3 else needles,7,scar_basis)
		if Time.get_ticks_usec() - slice_started >= ATLAS_BUILD_BUDGET_USEC:
			RUNTIME_WORK.complete(ticket, Time.get_ticks_usec() - slice_started)
			ticket = await RUNTIME_WORK.reserve(view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
			if ticket.is_empty(): return
			slice_started = Time.get_ticks_usec()
	if variant in [3,4,5]:
		for limb in 9:
			var angle := limb*2.4
			var start := Vector3(0,1.4+limb*.20,0)
			var end := start+Vector3(cos(angle)*rng.randf_range(.7,1.2),.65,sin(angle)*rng.randf_range(.7,1.2))
			_branch(build_batches,start,end,.07,trunk)
			_branch(build_batches,end,start.lerp(end,1.35)+Vector3(0,.25,0),.035,trunk)
			if variant!=5:
				_crown(build_batches,end+Vector3(0,.18,0),Vector3(.78,.80,.70) if variant==4 else Vector3(.65,1.05,.62),needles)
			if snowy:
				var cap_height := .96 if variant==4 else (1.20 if variant==3 else .10)
				var cap_size := Vector3(.63,.18,.54) if variant!=5 else Vector3(.24,.07,.19)
				_crown(build_batches,end+Vector3(0,cap_height,0),cap_size,snow)
				_icicle(build_batches,end,ice,.20+limb%3*.06)
			if Time.get_ticks_usec() - slice_started >= ATLAS_BUILD_BUDGET_USEC:
				RUNTIME_WORK.complete(ticket, Time.get_ticks_usec() - slice_started)
				ticket = await RUNTIME_WORK.reserve(view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
				if ticket.is_empty(): return
				slice_started = Time.get_ticks_usec()
	else:
		var tall := 1.13 if variant in [1,6,7] else (.77 if variant==2 else 1.0)
		for tier in 5:
			if variant==6 and tier==0: continue
			var radius := (1.25-tier*.22)*(.73 if variant in [1,2,7] else 1.0)
			var center := (1.35+tier*.72)*tall
			var drift := Vector3(.055*tier if variant==7 else 0,0,0)
			_cylinder(build_batches,Vector3(0,center+.20,0)+drift,.015,radius*.75,1.4*tall,needles,9)
			for bough in 5:
				var angle := bough*TAU/5+tier*.61+variant*.4
				var tip := Vector3(cos(angle)*radius,center-.18,sin(angle)*radius)+drift
				_branch(build_batches,Vector3(0,center,0),tip,.035,trunk)
				var tuft_basis := Basis.from_euler(Vector3(sin(angle)*.18, 0, cos(angle)*.18))
				var tuft_position := tip*.72+Vector3(0,center*.28+.15,0)
				_cylinder(build_batches,tuft_position,.02,radius*.53,.70*tall,needles,7,tuft_basis)
				if snowy and (bough+tier)%3!=0:
					_crown(build_batches,tuft_position+Vector3(0,.20,0),Vector3(radius*.52,.20,radius*.45),snow)
					if tier<3: _icicle(build_batches,tip,ice,.18+(bough%3)*.08)
			if Time.get_ticks_usec() - slice_started >= ATLAS_BUILD_BUDGET_USEC:
				RUNTIME_WORK.complete(ticket, Time.get_ticks_usec() - slice_started)
				ticket = await RUNTIME_WORK.reserve(view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
				if ticket.is_empty(): return
				slice_started = Time.get_ticks_usec()
	RUNTIME_WORK.complete(ticket, Time.get_ticks_usec() - slice_started)
	if not await _flush_batches_staged(build_batches, tree, view, tree_loop):
		return
	view.set_meta("pine_atlas_ready", true)
	_notify_atlas_ready(key)

static func _notify_atlas_ready(key: String) -> void:
	var data: Dictionary = _views.get(key, {})
	for waiter in data.get("waiters", []):
		var pine := (waiter as WeakRef).get_ref() as Node
		if is_instance_valid(pine):
			pine.call_deferred("_atlas_became_ready")
	data["waiters"] = []
	_views[key] = data

static func _release_atlas_cache() -> void:
	_views.clear()
	_mesh_cache.clear()
	_material_cache.clear()
	_atlas_worker = null

static func _branch(build_batches: Dictionary, start: Vector3, end: Vector3, radius: float, mat: Material) -> void:
	var axis := (end-start).normalized()
	var across := axis.cross(Vector3.FORWARD).normalized()
	var orientation := Basis(across,axis,across.cross(axis))
	_cylinder(build_batches,(start+end)*.5,radius*.55,radius,start.distance_to(end),mat,6,orientation)

static func _crown(build_batches: Dictionary, point: Vector3, size: Vector3, mat: Material) -> void:
	var sphere := _shared_sphere_mesh()
	_queue_primitive(build_batches, sphere, mat, Transform3D(Basis.from_scale(size), point))

static func _icicle(build_batches: Dictionary, point: Vector3, mat: Material, length: float) -> void:
	_cylinder(build_batches,point-Vector3(0,length*.5,0),.045,0,length,mat,5)

static func _cylinder(build_batches: Dictionary, point: Vector3, top: float, bottom: float, height: float, material: Material, sides: int, orientation := Basis.IDENTITY) -> void:
	var radius := maxf(top, bottom)
	if radius <= 0.0 or height <= 0.0:
		return
	var cylinder := _shared_cylinder_mesh(top / radius, bottom / radius, sides)
	var scaled_basis: Basis = orientation * Basis.from_scale(Vector3(radius, height, radius))
	_queue_primitive(build_batches, cylinder, material, Transform3D(scaled_basis, point))

static func _queue_primitive(build_batches: Dictionary, mesh: Mesh, material: Material, transform: Transform3D) -> void:
	var key := "%d_%d" % [mesh.get_instance_id(), material.get_instance_id()]
	var batch: Dictionary = build_batches.get(key, {})
	if batch.is_empty():
		batch = {"mesh": mesh, "material": material, "transforms": []}
		build_batches[key] = batch
	var transforms: Array = batch["transforms"]
	transforms.append(transform)

static func _flush_batches_staged(build_batches: Dictionary, parent: Node3D, view: SubViewport, tree_loop: SceneTree) -> bool:
	var peak_stage_usec := 0
	var keys: Array = build_batches.keys()
	if keys.is_empty():
		return true
	# Only the first batch may initialize renderer resources. Keep its three
	# indivisible phases isolated; warm batches below share a 1.2 ms slice.
	var first_batch: Dictionary = build_batches[keys[0]]
	var first_transforms: Array = first_batch["transforms"]
	var ticket: Dictionary = await RUNTIME_WORK.reserve(
		view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
	if ticket.is_empty(): return false
	var stage_started := Time.get_ticks_usec()
	var first_multi := MultiMesh.new()
	first_multi.transform_format = MultiMesh.TRANSFORM_3D
	var setup_usec := Time.get_ticks_usec() - stage_started
	var mesh_started := Time.get_ticks_usec()
	first_multi.mesh = first_batch["mesh"]
	var mesh_usec := Time.get_ticks_usec() - mesh_started
	var stage_usec := Time.get_ticks_usec() - stage_started
	peak_stage_usec = maxi(peak_stage_usec,stage_usec)
	RUNTIME_WORK.complete(ticket,stage_usec)
	ticket = await RUNTIME_WORK.reserve(
		view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
	if ticket.is_empty(): return false
	var instances_started := Time.get_ticks_usec()
	first_multi.instance_count = first_transforms.size()
	for index in first_transforms.size():
		first_multi.set_instance_transform(index,first_transforms[index])
	var instances_usec := Time.get_ticks_usec()-instances_started
	var node_setup_started := Time.get_ticks_usec()
	var first_renderer := MultiMeshInstance3D.new()
	first_renderer.name = "PineBatch_%d" % parent.get_child_count()
	first_renderer.multimesh = first_multi
	first_renderer.material_override = first_batch["material"]
	var node_setup_usec := Time.get_ticks_usec()-node_setup_started
	stage_usec = Time.get_ticks_usec()-instances_started
	peak_stage_usec = maxi(peak_stage_usec,stage_usec)
	RUNTIME_WORK.complete(ticket,stage_usec)
	ticket = await RUNTIME_WORK.reserve(
		view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
	if ticket.is_empty(): return false
	var add_started := Time.get_ticks_usec()
	parent.add_child(first_renderer)
	var add_usec := Time.get_ticks_usec()-add_started
	peak_stage_usec = maxi(peak_stage_usec,add_usec)
	var samples: Array = view.get_meta("pine_atlas_stage_samples",[])
	samples.append({"instances":first_transforms.size(),"setup_usec":setup_usec,"mesh_usec":mesh_usec,
		"transforms_usec":instances_usec,"node_setup_usec":node_setup_usec,"add_usec":add_usec})
	view.set_meta("pine_atlas_stage_samples",samples)
	view.set_meta("pine_atlas_peak_stage_usec",peak_stage_usec)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-add_started)
	await tree_loop.process_frame

	if keys.size() > 1:
		ticket = await RUNTIME_WORK.reserve(
			view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
		if ticket.is_empty(): return false
		var slice_started := Time.get_ticks_usec()
		for batch_index in range(1,keys.size()):
			stage_started = Time.get_ticks_usec()
			var batch: Dictionary = build_batches[keys[batch_index]]
			var transforms: Array = batch["transforms"]
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			setup_usec = Time.get_ticks_usec()-stage_started
			mesh_started = Time.get_ticks_usec()
			multi.mesh = batch["mesh"]
			mesh_usec = Time.get_ticks_usec()-mesh_started
			instances_started = Time.get_ticks_usec()
			multi.instance_count = transforms.size()
			for index in transforms.size():
				multi.set_instance_transform(index,transforms[index])
			instances_usec = Time.get_ticks_usec()-instances_started
			node_setup_started = Time.get_ticks_usec()
			var renderer := MultiMeshInstance3D.new()
			renderer.name = "PineBatch_%d" % parent.get_child_count()
			renderer.multimesh = multi
			renderer.material_override = batch["material"]
			node_setup_usec = Time.get_ticks_usec()-node_setup_started
			add_started = Time.get_ticks_usec()
			parent.add_child(renderer)
			add_usec = Time.get_ticks_usec()-add_started
			stage_usec = Time.get_ticks_usec()-stage_started
			peak_stage_usec = maxi(peak_stage_usec,stage_usec)
			samples = view.get_meta("pine_atlas_stage_samples",[])
			samples.append({"instances":transforms.size(),"setup_usec":setup_usec,"mesh_usec":mesh_usec,
				"transforms_usec":instances_usec,"node_setup_usec":node_setup_usec,"add_usec":add_usec})
			view.set_meta("pine_atlas_stage_samples",samples)
			view.set_meta("pine_atlas_peak_stage_usec",peak_stage_usec)
			view.render_target_update_mode = SubViewport.UPDATE_ONCE
			if Time.get_ticks_usec()-slice_started >= ATLAS_BUILD_BUDGET_USEC:
				RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-slice_started)
				if batch_index+1 < keys.size():
					ticket = await RUNTIME_WORK.reserve(
						view,&"mountain_pine_atlas",RUNTIME_WORK.PRIORITY_VISIBLE,ATLAS_BUILD_BUDGET_USEC)
					if ticket.is_empty(): return false
					slice_started = Time.get_ticks_usec()
				else:
					ticket = {}
		if not ticket.is_empty():
			RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-slice_started)
		await tree_loop.process_frame
	build_batches.clear()
	return true

static func _shared_material(color: Color, roughness := 1.0, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s_%.4f_%.4f" % [color.to_html(true), roughness, metallic]
	var cached := _material_cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material_cache[key] = material
	return material

static func _shared_sphere_mesh() -> SphereMesh:
	var cached := _mesh_cache.get("sphere_7_3") as SphereMesh
	if cached != null:
		return cached
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 3
	sphere.radius = 1.0
	sphere.height = 2.0
	_mesh_cache["sphere_7_3"] = sphere
	return sphere

static func _shared_cylinder_mesh(top_ratio: float, bottom_ratio: float, sides: int) -> CylinderMesh:
	var key := "cylinder_%d_%.6f_%.6f" % [sides, top_ratio, bottom_ratio]
	var cached := _mesh_cache.get(key) as CylinderMesh
	if cached != null:
		return cached
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_ratio
	cylinder.bottom_radius = bottom_ratio
	cylinder.height = 1.0
	cylinder.radial_segments = sides
	_mesh_cache[key] = cylinder
	return cylinder
