extends RefCounted
## Exterior line-of-sight window. Collision queries select nearby visual scopes;
## the shader clips only pixels in front of the target, including batched rails.
const SHADER := preload("res://scripts/camera/ExteriorReveal.gdshader")
const BUILDING_GROUP := &"exterior_reveal_building"
const SCAN_INTERVAL := 0.10
const RELEASE_DELAY := 0.24
var _states: Dictionary = {}
var _materials: Dictionary = {}
var _scopes: Dictionary = {}
var _shaders: Dictionary = {}
var _clock := 0.0
var _next_scan := 0.0
var _last_target := 0
var _last_position := Vector3.INF
var _shape := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _lead := Vector3.ZERO
var _radius := 4.0
var _origin := Vector3.ZERO
var _to_camera := Vector3.ZERO
var enabled := true
var last_query_hits := 0

func update(camera: Camera3D, target: Node3D, vehicle: bool, velocity: Vector3, delta: float, allowed: bool) -> void:
	if not enabled or not allowed or not is_instance_valid(target) or not target.is_inside_tree():
		release()
		return
	var dt := clampf(delta, 0.0, 0.1)
	_clock += dt
	var point := target.get_global_transform_interpolated().origin
	if _last_target != target.get_instance_id() or _last_position.distance_to(point) > 12.0:
		release()
		_last_target = target.get_instance_id()
		_lead = Vector3.ZERO
	_last_position = point
	_origin = point + Vector3.UP * (0.75 if vehicle else 0.85)
	_radius = move_toward(_radius, 7.0 if vehicle else 4.0, dt * 16.0)
	var desired := velocity.limit_length(24.0) * (0.42 if vehicle else 0.18)
	_lead = _lead.lerp(desired, 1.0-exp(-8.0*dt))
	# Orthographic rays stay parallel even with camera lead or an orbit.
	_to_camera = camera.global_basis.z * maxf(1.0, (_origin-camera.global_position).length())
	if _clock >= _next_scan:
		_next_scan = _clock + SCAN_INTERVAL
		_scan(camera,target)
	for entry in _materials.values():
		var material: ShaderMaterial = entry.material
		material.set_shader_parameter("reveal_origin",_origin)
		material.set_shader_parameter("reveal_ahead",_lead)
		material.set_shader_parameter("reveal_to_camera",_to_camera)
		material.set_shader_parameter("reveal_radius",_radius)
	for id in _states.keys():
		var state: Dictionary = _states[id]
		if not is_instance_valid(state.node): _restore(id); continue
		var wanted := _clock-float(state.seen) <= RELEASE_DELAY
		state.amount = move_toward(float(state.amount),1.0 if wanted else 0.0,dt/(0.18 if wanted else 0.32))
		state.node.set_instance_shader_parameter("exterior_reveal_amount",state.amount)
		if not wanted and state.amount <= 0.0: _restore(id)

func _scan(camera: Camera3D, target: Node3D) -> void:
	for entry in _materials.values():
		if entry.source is ShaderMaterial:
			for uniform in entry.uniforms:
				entry.material.set_shader_parameter(uniform.name,entry.source.get_shader_parameter(uniform.name))
		else:
			entry.material.set_shader_parameter("base_color",entry.source.albedo_color)
			entry.material.set_shader_parameter("emission_color",entry.source.emission*entry.source.emission_energy_multiplier if entry.source.emission_enabled else Color.BLACK)
	var direction := _to_camera.normalized()
	var center := _origin + _lead*.5 + _to_camera*.5
	var reach := _radius + _lead.length()*.5 + 0.8
	_shape.size = Vector3(reach*2,reach*2,_to_camera.length())
	_query.shape = _shape
	_query.transform = Transform3D(Basis.looking_at(-direction),center)
	_query.collision_mask = 1 | 4
	_query.collide_with_areas = false
	_query.exclude = [target.get_rid()] if target is CollisionObject3D else []
	var hits := camera.get_world_3d().direct_space_state.intersect_shape(_query,128)
	last_query_hits = hits.size()
	var visited := {}
	for hit in hits:
		var body: Node = hit.collider
		var scope := _visual_scope(body,camera.get_parent())
		if scope == null or not _is_building_scope(scope) or visited.has(scope.get_instance_id()): continue
		visited[scope.get_instance_id()] = true
		for node in _items(scope):
			if not is_instance_valid(node) or not node.is_visible_in_tree() or node.is_queued_for_deletion(): continue
			if node == target or target.is_ancestor_of(node): continue
			var box: AABB = node.global_transform * node.get_aabb()
			if box.end.y <= target.global_position.y + 0.3: continue
			if not box.grow(_radius+0.8).intersects_segment(_origin,_origin+_to_camera) and not box.grow(_radius+0.8).intersects_segment(_origin+_lead,_origin+_lead+_to_camera): continue
			var id: int = node.get_instance_id()
			if not _states.has(id): _capture(node)
			if _states.has(id): _states[id].seen = _clock
	for key in _scopes.keys():
		if _clock - float(_scopes[key].used) > 2.0: _scopes.erase(key)

func _visual_scope(body: Node, world: Node) -> Node:
	if body is CharacterBody3D or body is RigidBody3D: return body
	var parent := body.get_parent()
	if parent == null or parent == world: return body
	# Native buildings keep sibling Visuals and Collision roots.
	if parent.name == "Collision" and parent.get_parent() != world: return parent.get_parent()
	return parent

func _is_building_scope(scope: Node) -> bool:
	var node := scope
	while node != null:
		if node.is_in_group(BUILDING_GROUP) or node.is_in_group("v2_walkin_facade") or node.is_in_group("harbor_building_facade"):
			return true
		if node.has_meta("place_id") and not str(node.get_meta("place_id", "")).is_empty():
			return true
		node = node.get_parent()
	return false

func _items(scope: Node) -> Array:
	var id := scope.get_instance_id()
	var cached: Dictionary = _scopes.get(id,{})
	if cached.is_empty() or _clock-float(cached.built) > .7:
		var items: Array = []
		if scope is MeshInstance3D or scope is MultiMeshInstance3D: items.append(scope)
		for node in scope.find_children("*","GeometryInstance3D",true,false):
			if node is MeshInstance3D or node is MultiMeshInstance3D: items.append(node)
		cached = {"items":items,"built":_clock}
		_scopes[id] = cached
	cached.used = _clock
	return cached.items

func _capture(node: GeometryInstance3D) -> void:
	var saved: Array[Dictionary] = []
	if node.material_override != null:
		node.material_override = source_material(node.material_override)
		_replace(node,-1,node.material_override,saved)
	elif node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count(): _replace(node,surface,node.get_active_material(surface),saved)
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null and node.multimesh.mesh.get_surface_count() == 1:
		_replace(node,-1,node.multimesh.mesh.surface_get_material(0),saved)
	if saved.is_empty(): return
	_states[node.get_instance_id()] = {"node":node,"saved":saved,"amount":0.0,"seen":_clock,"parameter":node.get_instance_shader_parameter("exterior_reveal_amount")}
	node.set_instance_shader_parameter("exterior_reveal_amount",0.0)

func _replace(node: GeometryInstance3D, surface: int, source: Material, saved: Array[Dictionary]) -> void:
	if source is ShaderMaterial:
		_replace_shader(node,surface,source,saved)
		return
	if not source is StandardMaterial3D: return
	# Terrain/custom surfaces and multi-pass authored effects keep their owner.
	if source.next_pass != null or source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return
	var id := source.get_instance_id()
	if not _materials.has(id):
		var material := ShaderMaterial.new()
		var cull := int(source.cull_mode)
		var variant := "standard_%d_%s" % [cull,source.normal_enabled]
		if not _shaders.has(variant):
			var shader := Shader.new()
			shader.code = SHADER.code.replace("cull_back", "cull_front" if cull == BaseMaterial3D.CULL_FRONT else "cull_disabled" if cull == BaseMaterial3D.CULL_DISABLED else "cull_back")
			if not source.normal_enabled:
				shader.code = shader.code.replace("if (normal_enabled) { NORMAL_MAP = texture(normal_texture, UV).rgb; NORMAL_MAP_DEPTH = normal_scale; }", "")
			_shaders[variant] = shader
		material.shader = _shaders[variant]
		material.render_priority = source.render_priority
		material.set_shader_parameter("base_color",source.albedo_color)
		material.set_shader_parameter("base_texture",source.albedo_texture)
		material.set_shader_parameter("uv_scale",source.uv1_scale)
		material.set_shader_parameter("uv_offset",source.uv1_offset)
		material.set_shader_parameter("triplanar_enabled",source.uv1_triplanar)
		material.set_shader_parameter("world_triplanar",source.uv1_world_triplanar)
		material.set_shader_parameter("triplanar_sharpness",source.uv1_triplanar_sharpness)
		material.set_shader_parameter("vertex_color_enabled",source.vertex_color_use_as_albedo)
		material.set_shader_parameter("normal_enabled",source.normal_enabled)
		material.set_shader_parameter("normal_texture",source.normal_texture)
		material.set_shader_parameter("normal_scale",source.normal_scale)
		material.set_shader_parameter("roughness_value",source.roughness)
		material.set_shader_parameter("metallic_value",source.metallic)
		material.set_shader_parameter("specular_value",source.metallic_specular)
		material.set_shader_parameter("emission_color",source.emission * source.emission_energy_multiplier if source.emission_enabled else Color.BLACK)
		material.set_shader_parameter("emission_texture",source.emission_texture)
		material.set_shader_parameter("unshaded_source",source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		material.set_meta("exterior_reveal_source",source)
		_materials[id] = {"material":material,"users":0,"source":source}
	var replacement: ShaderMaterial = _materials[id].material
	var original: Material = node.material_override if surface < 0 else node.get_surface_override_material(surface)
	saved.append({"surface":surface,"original":original,"replacement":replacement,"source":source})
	_materials[id].users += 1
	if surface < 0: node.material_override = replacement
	else: node.set_surface_override_material(surface,replacement)

func _replace_shader(node: GeometryInstance3D, surface: int, source: ShaderMaterial, saved: Array[Dictionary]) -> void:
	if source.shader == null or source.next_pass != null: return
	var code := source.shader.code
	if not "shader_type spatial" in code or "depth_test_disabled" in code or "reveal_origin" in code: return
	var id := source.get_instance_id()
	if not _materials.has(id):
		var shader_key := "custom_%d" % source.shader.get_instance_id()
		if not _shaders.has(shader_key):
			var expression := RegEx.new()
			expression.compile("void\\s+fragment\\s*\\(\\s*\\)\\s*\\{")
			var found := expression.search(code)
			if found == null: return
			var end := found.get_end()
			var depth := 1
			while end < code.length() and depth > 0:
				if code[end] == "{": depth += 1
				elif code[end] == "}": depth -= 1
				end += 1
			if depth != 0: return
			var fragment := SHADER.code.substr(SHADER.code.find("vec3 view ="))
			fragment = fragment.substr(0,fragment.rfind("}"))
			fragment = fragment.replace("reveal_world", "(INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz")
			fragment = fragment.replace("ALPHA = color.a *", "ALPHA *=")
			for word in ["distance_to_path","relative","lateral","window","ahead","depth","view","t"]:
				var names := RegEx.new()
				names.compile("\\b"+word+"\\b")
				fragment = names.sub(fragment,"er_"+word,true)
			var alpha_write := RegEx.new()
			alpha_write.compile("ALPHA\\s*[*+/-]?=")
			if alpha_write.search(code) == null: fragment = "ALPHA = 1.0;\n" + fragment
			code = code.insert(end-1,"\n"+fragment+"\n")
			var uniforms := SHADER.code.substr(SHADER.code.find("uniform vec3 reveal_origin;"))
			uniforms = uniforms.substr(0,uniforms.find("varying vec3"))
			code = code.insert(found.get_start(),uniforms+"\n")
			if not "depth_prepass_alpha" in code:
				if "render_mode" in code: code = code.replace("render_mode ","render_mode depth_prepass_alpha, ")
				else: code = code.replace("shader_type spatial;","shader_type spatial;\nrender_mode depth_prepass_alpha;")
			var shader := Shader.new()
			shader.code = code
			_shaders[shader_key] = shader
		var material: ShaderMaterial = source.duplicate()
		material.shader = _shaders[shader_key]
		material.set_meta("exterior_reveal_source",source)
		_materials[id] = {"material":material,"users":0,"source":source,"uniforms":source.shader.get_shader_uniform_list()}
	var replacement: ShaderMaterial = _materials[id].material
	var original: Material = node.material_override if surface < 0 else node.get_surface_override_material(surface)
	saved.append({"surface":surface,"original":original,"replacement":replacement,"source":source})
	_materials[id].users += 1
	if surface < 0: node.material_override = replacement
	else: node.set_surface_override_material(surface,replacement)

static func source_material(material: Material) -> Material:
	while material != null and material.has_meta("exterior_reveal_source"):
		material = material.get_meta("exterior_reveal_source")
	return material

func _restore(id: int) -> void:
	var state: Dictionary = _states[id]
	for saved in state.saved:
		if is_instance_valid(state.node):
			var node: GeometryInstance3D = state.node
			if saved.surface < 0:
				if node.material_override == saved.replacement: node.material_override = saved.original
			elif node.get_surface_override_material(saved.surface) == saved.replacement:
				node.set_surface_override_material(saved.surface,saved.original)
		var key: int = saved.source.get_instance_id()
		_materials[key].users -= 1
		if _materials[key].users == 0: _materials.erase(key)
	if is_instance_valid(state.node): state.node.set_instance_shader_parameter("exterior_reveal_amount",state.parameter)
	_states.erase(id)

func release() -> void:
	for id in _states.keys(): _restore(id)
	_scopes.clear()
	_next_scan = 0.0
	_last_target = 0
	_last_position = Vector3.INF

func debug_snapshot() -> Dictionary:
	return {"geometry":_states.size(),"materials":_materials.size(),"scopes":_scopes.size(),"hits":last_query_hits,"radius":_radius,"lead":_lead}
