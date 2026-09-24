extends Node3D
## Shared low-poly winter meshes; static groups render once with their surroundings.
const FLOOR_Y := 0.76822128
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
var features: Array[Dictionary] = []
const FEATURE_BATCH_META := &"winter_dressing_feature_batch"
const GROUP_BATCH_META := &"winter_dressing_group_batch"
const STREAM_BUILD_BUDGET_USEC := 1200
const RUNTIME_WORK := preload("res://systems/RuntimeWorkScheduler.gd")
const CACHED_SNOW_MATERIAL := preload("res://world/mountain_pass/transit/WinterDressingSnowMaterial.res")

static func floor_point(point: Vector2) -> Vector3:
	return Vector3(point.x/18.0,0,point.y/(18.0*FLOOR_Y))

func build(entries: Array[Dictionary]) -> void:
	_ensure_resources()
	for index in entries.size():
		_append_feature(entries[index],index)
	_allocate_group_batches()

func build_streamed(entries: Array[Dictionary]) -> void:
	var ticket: Dictionary = await RUNTIME_WORK.reserve(
		self,&"mountain_winter",RUNTIME_WORK.PRIORITY_VISIBLE,STREAM_BUILD_BUDGET_USEC)
	if ticket.is_empty(): return
	var slice_started := Time.get_ticks_usec()
	_ensure_resources()
	var peak_feature_usec := 0
	for index in entries.size():
		var feature_started := Time.get_ticks_usec()
		_append_feature(entries[index],index)
		peak_feature_usec = maxi(peak_feature_usec,Time.get_ticks_usec()-feature_started)
		if Time.get_ticks_usec()-slice_started >= STREAM_BUILD_BUDGET_USEC:
			RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-slice_started)
			ticket = await RUNTIME_WORK.reserve(
				self,&"mountain_winter",RUNTIME_WORK.PRIORITY_VISIBLE,STREAM_BUILD_BUDGET_USEC)
			if ticket.is_empty(): return
			slice_started = Time.get_ticks_usec()
	RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-slice_started)
	# Allocate the small fixed set of shape/material batches only after every
	# candidate has contributed its exact capacity.
	ticket = await RUNTIME_WORK.reserve(
		self,&"mountain_winter",RUNTIME_WORK.PRIORITY_VISIBLE,STREAM_BUILD_BUDGET_USEC)
	if ticket.is_empty(): return
	var allocation_started := Time.get_ticks_usec()
	_allocate_group_batches()
	RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-allocation_started)
	set_meta("stream_build_peak_feature_usec",peak_feature_usec)
	set_meta("stream_build_batch_allocation_usec",Time.get_ticks_usec()-allocation_started)

func _append_feature(entry: Dictionary, index: int) -> void:
	var feature := Node3D.new()
	feature.name = "%s%02d" % [String(entry.kind).capitalize(),index]
	feature.position = floor_point(entry.point)
	feature.scale = Vector3.ONE*float(entry.get("scale",1.0))
	feature.rotation.y = -float(entry.get("angle",0.0))
	add_child(feature)
	_begin_feature(feature)
	match entry.kind:
		"pine": _pine(feature,index)
		"rock": _rock(feature,index)
		"log": _log(feature,index)
		"branches": _branches(feature,index)
	_add_footprint_proxy(feature)
	features.append({"root":feature,"kind":entry.kind,"solid":entry.kind!="branches","point":entry.point})

func dress_base(feature: Dictionary, seed_value: int) -> void:
	var parent: Node3D = feature.root
	if bool((parent.get_meta(FEATURE_BATCH_META, {}) as Dictionary).get("committed", false)):
		return
	var radius := 1.45 if feature.kind in ["pine","log"] else .83
	_mesh(parent,"stone",Vector3(-.1,.036,.06),Vector3(radius,.025,radius*.68),"snow")
	# Fallen needles and twig fragments collect under trees, around rock groups
	# and along logs, instead of becoming evenly scattered isolated props.
	for index in 11:
		var angle := float(index)*2.39996+float(seed_value)*.23
		var reach := radius*(.47+float(index%4)*.15)
		var a := Vector3(cos(angle)*reach,.067,sin(angle)*reach*.71)
		var b := a+Vector3(cos(angle+.9)*.12,.0,sin(angle+.9)*.12)
		_rod(parent,a,b,.008,"ring" if index%3 else "needles")
	_commit_feature(parent)

func _pine(parent: Node3D, variant: int) -> void:
	_rod(parent,Vector3.ZERO,Vector3(0.07,3.7,0),0.115,"bark")
	# Layered branch clusters have separate asymmetric snowy cushions. Their
	# offset silhouettes avoid the perfect cone stacks used by distant trees.
	for tier in 4:
		var reach := 1.05-float(tier)*0.22
		var height := 1.05+float(tier)*0.77
		for arm in 5:
			var angle := float(arm)*TAU/5.0+float(tier)*0.57+float(variant)*0.31
			var length := reach*(0.78+float(posmod(arm*7+variant,5))*0.07)
			var center := Vector3(cos(angle)*length*0.56,height+sin(angle*2.0)*0.06,sin(angle)*length*0.56)
			_rod(parent,Vector3(0,height+0.08,0),center+Vector3(cos(angle)*length*.23,-0.1,sin(angle)*length*.23),0.035,"bark")
			var shape := Vector3(length*.83,0.30+reach*.08,length*.52)
			_mesh(parent,"stone",center,shape,"needles" if arm%2 else "light_needles",Vector3(0,-angle,0))
			_mesh(parent,"stone",center+Vector3(-0.045,0.19,0.025),shape*Vector3(.87,.62,.85),"snow",Vector3(0,-angle,0))
	_mesh(parent,"stone",Vector3(0.07,3.86,0),Vector3(.22,.45,.21),"needles")
	_mesh(parent,"stone",Vector3(.04,4.05,0),Vector3(.16,.25,.16),"snow")
	for arm in 4:
		var angle := float(arm)*TAU/4+0.3
		_rod(parent,Vector3.ZERO,Vector3(cos(angle)*.37,.025,sin(angle)*.3),.055,"bark")

func _rock(parent: Node3D, variant: int) -> void:
	_mesh(parent,"stone",Vector3(0,.29,0),Vector3(.70,.43,.51),"rock",Vector3(5,variant*37,12)*PI/180.0)
	_mesh(parent,"stone",Vector3(-.14,.61,-.035),Vector3(.51,.12,.35),"snow")
	_mesh(parent,"stone",Vector3(.55,.12,.26),Vector3(.28,.19,.24),"lichen",Vector3(0,float(variant),0))
	_mesh(parent,"stone",Vector3(-.58,.08,.31),Vector3(.16,.1,.12),"rock")

func _log(parent: Node3D, variant: int) -> void:
	var a := Vector3(-1.12,.22,0)
	var b := Vector3(1.13,.29,.10)
	_rod(parent,a,b,.20,"bark")
	_rod(parent,a-Vector3(.005,0,0),a+Vector3(.012,0,0),.166,"cut")
	_rod(parent,b-Vector3(.008,0,0),b+Vector3(.012,0,0),.16,"cut")
	_rod(parent,b+Vector3(.013,0,0),b+Vector3(.017,0,0),.092,"ring")
	_rod(parent,b+Vector3(.018,0,0),b+Vector3(.021,0,0),.067,"cut")
	for ridge in 4:
		var z := (float(ridge)-1.5)*.09
		_rod(parent,a+Vector3(.1,.14,z),b+Vector3(-.12,.13,z),.017,"ring")
	_mesh(parent,"stone",Vector3(-.14,.42,.02),Vector3(.93,.09,.17),"snow")
	_rod(parent,Vector3(-.18,.27,.04),Vector3(-.35,.45,.55),.055,"bark")
	_rod(parent,Vector3(-.35,.45,.55),Vector3(-.09,.51,.68),.023,"bark")
	if variant%2 == 0: _mesh(parent,"stone",Vector3(.70,.06,.41),Vector3(.15,.09,.1),"rock")

func _branches(parent: Node3D, variant: int) -> void:
	_rod(parent,Vector3(-.68,.06,-.10),Vector3(.7,.06,.15),.025,"bark")
	_rod(parent,Vector3(-.24,.065,-.02),Vector3(.08,.07,-.44),.018,"bark")
	_rod(parent,Vector3(.17,.068,.05),Vector3(.55,.07,.48),.017,"bark")
	_rod(parent,Vector3(.30,.07,.06),Vector3(.62,.07,-.20),.013,"bark")
	_mesh(parent,"stone",Vector3(-.28,.08,.03),Vector3(.2,.035,.11),"snow")
	if variant%3==0: _mesh(parent,"stone",Vector3(.45,.06,.1),Vector3(.17,.1,.11),"needles")

func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: String) -> void:
	var basis := Basis(Quaternion(Vector3.UP,a.direction_to(b))).scaled(Vector3(radius,a.distance_to(b),radius))
	_add_instance(parent,"cylinder",Transform3D(basis,(a+b)*.5),material)

func _mesh(parent: Node3D, kind: String, point: Vector3, size: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	var basis := Basis.from_euler(rotation).scaled(size)
	_add_instance(parent,kind,Transform3D(basis,point),material)

func _ensure_resources() -> void:
	if _materials.is_empty():
		for pair in [["bark","554237"],["cut","b6946b"],["ring","795b40"],["rock","687780"],["lichen","879183"],["snow","c6d5d9"],["needles","314d42"],["light_needles","476252"]]:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(pair[1])
			material.roughness = 0.95
			_materials[pair[0]] = material
		# The deterministic 256x256 albedo/normal pair used to be generated here.
		# Keeping it as a baked Resource preserves the exact material while avoiding
		# a >100 ms first-visit main-thread slice.
		_materials["snow"] = CACHED_SNOW_MATERIAL
	if not _meshes.has("cylinder"):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 1.0
		cylinder.radial_segments = 7
		_meshes["cylinder"] = cylinder
	if not _meshes.has("stone"):
		var stone := SphereMesh.new()
		stone.radius = 1.0
		stone.height = 2.0
		stone.radial_segments = 7
		stone.rings = 3
		_meshes["stone"] = stone
	if not _meshes.has("proxy_box"):
		var proxy_box := BoxMesh.new()
		proxy_box.size = Vector3.ONE
		_meshes["proxy_box"] = proxy_box

func _begin_feature(parent: Node3D) -> void:
	parent.set_meta(FEATURE_BATCH_META,{
		"batches": {},
		"has_bounds": false,
		"bounds_min": Vector3.ZERO,
		"bounds_max": Vector3.ZERO,
		"committed": false,
	})

func _batch_key(kind: String, material: String) -> String:
	return "%s:%s" % [kind,material]

func _add_instance(parent: Node3D, kind: String, transform: Transform3D, material: String) -> void:
	var state: Dictionary = parent.get_meta(FEATURE_BATCH_META)
	var batches: Dictionary = state.batches
	var key := _batch_key(kind,material)
	if not batches.has(key):
		batches[key] = {
			"mesh": _meshes[kind],
			"material": _materials[material],
			"transforms": [],
		}
	var batch: Dictionary = batches[key]
	(batch.transforms as Array).append(transform)
	var aabb: AABB = (_meshes[kind] as Mesh).get_aabb()
	for endpoint in 8:
		var point: Vector3 = transform * aabb.get_endpoint(endpoint)
		if not bool(state.has_bounds):
			state.bounds_min = point
			state.bounds_max = point
			state.has_bounds = true
		else:
			state.bounds_min = (state.bounds_min as Vector3).min(point)
			state.bounds_max = (state.bounds_max as Vector3).max(point)

func _add_footprint_proxy(parent: Node3D) -> void:
	var state: Dictionary = parent.get_meta(FEATURE_BATCH_META)
	if not bool(state.has_bounds):
		return
	var minimum: Vector3 = state.bounds_min
	var maximum: Vector3 = state.bounds_max
	var proxy := MeshInstance3D.new()
	proxy.name = "FootprintProxy"
	proxy.mesh = _meshes["proxy_box"]
	proxy.position = (minimum+maximum)*0.5
	proxy.scale = (maximum-minimum).max(Vector3.ONE*0.001)
	proxy.visible = false
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(proxy)

func _reserve_batch(batches: Dictionary, key: String, mesh: Mesh, material: Material, count: int) -> void:
	if not batches.has(key):
		batches[key] = {"mesh":mesh,"material":material,"capacity":0,"written":0}
	var batch: Dictionary = batches[key]
	batch.capacity = int(batch.capacity)+count

func _allocate_group_batches() -> void:
	var batches: Dictionary = {}
	for feature in features:
		var feature_state: Dictionary = (feature.root as Node3D).get_meta(FEATURE_BATCH_META)
		for key in (feature_state.batches as Dictionary):
			var source: Dictionary = feature_state.batches[key]
			_reserve_batch(batches,key,source.mesh,source.material,(source.transforms as Array).size())
		# Every accepted feature receives the same forest-floor base in dress_base().
		_reserve_batch(batches,_batch_key("stone","snow"),_meshes["stone"],_materials["snow"],1)
		_reserve_batch(batches,_batch_key("cylinder","ring"),_meshes["cylinder"],_materials["ring"],7)
		_reserve_batch(batches,_batch_key("cylinder","needles"),_meshes["cylinder"],_materials["needles"],4)
	var batch_index := 0
	for key in batches:
		var batch: Dictionary = batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = batch.mesh
		multimesh.instance_count = int(batch.capacity)
		multimesh.visible_instance_count = 0
		var instance := MultiMeshInstance3D.new()
		instance.name = "WinterBatch%02d_%s" % [batch_index,String(key).replace(":","_")]
		instance.multimesh = multimesh
		instance.material_override = batch.material
		add_child(instance)
		batch.node = instance
		batch_index += 1
	set_meta(GROUP_BATCH_META,batches)

func _commit_feature(parent: Node3D) -> void:
	var state: Dictionary = parent.get_meta(FEATURE_BATCH_META)
	if bool(state.committed):
		return
	var group := parent.get_parent() as Node3D
	var group_batches: Dictionary = group.get_meta(GROUP_BATCH_META)
	for key in (state.batches as Dictionary):
		var source: Dictionary = state.batches[key]
		var destination: Dictionary = group_batches[key]
		var multimesh: MultiMesh = (destination.node as MultiMeshInstance3D).multimesh
		var written := int(destination.written)
		for local_transform in (source.transforms as Array):
			multimesh.set_instance_transform(written,parent.transform*(local_transform as Transform3D))
			written += 1
		destination.written = written
		multimesh.visible_instance_count = written
	state.committed = true
