extends Node
## Sonda de pipelines (diagnóstico, GETECO_PIPELINE_PROBE=1; 3ª rodada de desempenho, 22/10).
##
## O StallLog só conta pipelines por tipo (surface/draw/specialization...). Com o cache de pipeline frio cada
## pipeline nova no jogo custou 0,1–1,1 s (primeiro tiro, 2ª rodada) e, a quente, o carro novo do trânsito
## ainda criava 2 `surface` por quadro; para cobrir no pré-aquecimento é preciso saber QUAL material e QUAL
## malha a criaram. A cada desenho (frame_post_draw) a sonda lê os contadores do motor; quando sobem, grava as
## combinações (shader do material × formato da superfície × sombra × multimesh/partícula) das
## GeometryInstance3D que entraram na árvore desde o desenho anterior e que nunca tinham aparecido antes nesta
## sessão. Com a partida jogável, um quadro com pipeline nova também revarre os nós já vistos: pega o material
## trocado num nó que já existia (emissores dos pools do CombatEffects, lentes, pintura). O conjunto "já
## visto" começa no início do processo: tudo o que os pré-aquecimentos desenharam conta como visto.
## `stage(label)` fecha a etapa `label` da carga (ProductionWorld): duração desde a marca anterior e pipelines dela.
##
## Grava <pasta do exe>/evidence/pipeline-probe/probe-<data>-<pid>.jsonl. Custa CPU por nó adicionado (e a
## revarredura, só em quadro com pipeline nova): serve para atribuir, nunca para medir tempo de quadro.
const SOURCES := {"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS, "mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE, "draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION}
const MAX_NEW_PER_RECORD := 48
const MAX_RESCAN_NODES := 120000
static var _instance: Node

var _file: FileAccess
var _path := ""
var _pending: PackedInt64Array = PackedInt64Array()
var _known: Dictionary = {}
var _seen: Dictionary = {}
var _last: Dictionary = {}
var _last_draw_usec := 0
var _started_usec := 0
var _stage_label := "boot"
var _stage_counts: Dictionary = {}
var _stage_usec := 0
var _material_props: PackedStringArray = PackedStringArray()
var _texture_props: PackedStringArray = PackedStringArray()
var _records := 0
var _game_pipelines: Dictionary = {}
var _mat_cache: Dictionary = {}
var _material_defaults: Dictionary = {}
## Modo leve (GETECO_PIPELINE_PROBE=lite, 24/10): a sonda completa descreve cada nó novo durante a carga e
## atrasava a carga fria o bastante para o quadro de ~0,9 s sumir (5ª rodada). No leve, a carga só guarda os ids;
## o conjunto "já visto" é montado uma vez no 1º quadro jogável e, dali em diante, só quadro com pipeline nova
## descreve (nós novos e revarredura).
var _lite := false
var _seeded := false

static func enabled() -> bool:
	return OS.get_environment("GETECO_PIPELINE_PROBE") in ["1", "lite"] and not "--headless" in OS.get_cmdline_args()

## Fecha a etapa `label` da carga, que começou na marca anterior (não faz nada com a sonda desligada).
static func stage(label: String) -> void:
	if is_instance_valid(_instance): _instance._stage(label)

func _ready() -> void:
	_instance = self
	_lite = OS.get_environment("GETECO_PIPELINE_PROBE") == "lite"
	name = "PipelineProbe"
	process_mode = Node.PROCESS_MODE_ALWAYS
	var folder := ProjectSettings.globalize_path("res://evidence/pipeline-probe")
	if DirAccess.make_dir_recursive_absolute(folder) != OK: folder = ProjectSettings.globalize_path("user://pipeline-probe")
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")
	_path = "%s/probe-%s-%d.jsonl" % [folder, stamp, OS.get_process_id()]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	_started_usec = Time.get_ticks_usec()
	_stage_usec = _started_usec
	_last = _counts()
	_stage_counts = _last.duplicate()
	_prepare_material_props()
	get_tree().node_added.connect(_on_node_added)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_write({"type": "header", "pid": OS.get_process_id(), "gpu": RenderingServer.get_video_adapter_name(),
		"driver": RenderingServer.get_current_rendering_driver_name(), "method": RenderingServer.get_current_rendering_method(),
		"args": OS.get_cmdline_user_args(), "counts": _last})
	print("PipelineProbe: gravando em ", _path)

func _prepare_material_props() -> void:
	# Só o que muda o shader gerado do BaseMaterial3D: enums/flags (bool/int) e textura presente ou não.
	# Cor, número e vetor viram uniform e não criam pipeline.
	var sample := StandardMaterial3D.new()
	for property in sample.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		var kind := int(property.type)
		var prop_name := str(property.name)
		if prop_name in ["render_priority", "resource_local_to_scene", "resource_name", "resource_scene_unique_id"]: continue
		if kind == TYPE_BOOL or kind == TYPE_INT:
			_material_props.append(prop_name)
			_material_defaults[prop_name] = sample.get(prop_name)
		elif kind == TYPE_OBJECT and prop_name.ends_with("_texture"): _texture_props.append(prop_name)

func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D or node is Light3D or node is ReflectionProbe or node is Decal or node is FogVolume:
		_pending.append(node.get_instance_id())

func _on_post_draw() -> void:
	var now := Time.get_ticks_usec()
	var counts := _counts()
	var delta := {}
	var changed := false
	for key in counts:
		var step := int(counts[key]) - int(_last.get(key, 0))
		if step != 0:
			delta[key] = step
			changed = true
	var playing := _playing()
	var fresh: Array = []
	var described := 0
	if _lite and not (playing and _seeded):
		for id in _pending: _known[id] = true
		_pending.clear()
		if playing:
			# Uma vez: tudo o que existe ao ficar jogável conta como visto (sem gravar).
			var seed_began := Time.get_ticks_usec()
			_mat_cache.clear()
			var scratch: Array = []
			for id in _known.keys():
				var node: Object = instance_from_id(id)
				if is_instance_valid(node) and (node as Node).is_inside_tree(): _collect(node as Node, scratch, "seed")
			_seeded = true
			_write({"type": "seed", "t": snappedf(float(now - _started_usec) / 1000000.0, 0.001), "nodes": _known.size(),
				"keys": _seen.size(), "ms": snappedf(float(Time.get_ticks_usec() - seed_began) / 1000.0, 0.01)})
		if changed and not playing:
			_write({"type": "compile", "t": snappedf(float(now - _started_usec) / 1000000.0, 0.001), "playing": false,
				"stage": _stage_label, "delta": delta, "lite": true})
		_last = counts
		_last_draw_usec = Time.get_ticks_usec()
		return
	# Um material é descrito uma vez por desenho (dezenas de milhares de nós repartem poucos materiais).
	_mat_cache.clear()
	for id in _pending:
		var node: Object = instance_from_id(id)
		if not is_instance_valid(node) or not (node as Node).is_inside_tree(): continue
		_known[id] = true
		described += 1
		_collect(node as Node, fresh, "added")
	_pending.clear()
	var rescanned := 0
	# Só especialização não depende de material novo (é a variante por luzes/névoa do mesmo shader).
	var structural := int(delta.get("surface", 0)) + int(delta.get("draw", 0)) + int(delta.get("mesh", 0)) > 0
	if structural and playing:
		# Material trocado num nó já existente não passa por node_added.
		for id in _known.keys():
			if rescanned >= MAX_RESCAN_NODES: break
			var node: Object = instance_from_id(id)
			if not is_instance_valid(node):
				_known.erase(id)
				continue
			if not (node as Node).is_inside_tree(): continue
			rescanned += 1
			_collect(node as Node, fresh, "rescan")
	if changed:
		var record := {"type": "compile", "t": snappedf(float(now - _started_usec) / 1000000.0, 0.001),
			"frame": Engine.get_process_frames(), "draw_interval_ms": snappedf(float(now - _last_draw_usec) / 1000.0, 0.01),
			"playing": playing, "stage": _stage_label, "delta": delta, "added_nodes": described, "rescanned": rescanned,
			"new_count": fresh.size(), "new": fresh.slice(0, MAX_NEW_PER_RECORD), "scene": _scene_state()}
		if playing:
			for key in delta: _game_pipelines[key] = int(_game_pipelines.get(key, 0)) + int(delta[key])
		_write(record)
	_last = counts
	_last_draw_usec = Time.get_ticks_usec()

func _collect(node: Node, out: Array, how: String) -> void:
	for entry in _keys(node):
		var key: String = entry.key
		if _seen.has(key): continue
		_seen[key] = true
		entry["how"] = how
		if entry.has("material_ref"):
			entry["desc"] = _material_desc(entry.material_ref)
		entry.erase("material_ref")
		out.append(entry)

## Só para o registro: o que difere de um StandardMaterial3D novo, com nome (a chave é posicional).
func _material_desc(material: Variant) -> String:
	if not material is Material: return ""
	if material is ShaderMaterial:
		var shader: Shader = (material as ShaderMaterial).shader
		return "shader=" + (shader.resource_path if shader != null else "null")
	if not material is BaseMaterial3D: return material.get_class()
	var parts := PackedStringArray()
	for prop_name in _material_props:
		var value: Variant = material.get(prop_name)
		if value != _material_defaults.get(prop_name): parts.append("%s=%s" % [prop_name, str(value)])
	for prop_name in _texture_props:
		if material.get(prop_name) != null: parts.append(prop_name)
	if (material as Material).next_pass != null: parts.append("next_pass=" + _material_desc((material as Material).next_pass))
	return " ".join(parts)

func _keys(node: Node) -> Array:
	var out: Array = []
	var path := str(node.get_path()) if node.is_inside_tree() else str(node.name)
	if path.length() > 160: path = "…" + path.right(159)
	if node is Light3D:
		var light := node as Light3D
		var mode := ""
		if light is OmniLight3D: mode = "omni%d" % int((light as OmniLight3D).omni_shadow_mode)
		elif light is SpotLight3D: mode = "spot"
		else: mode = "dir%d" % int((light as DirectionalLight3D).directional_shadow_mode)
		out.append({"key": "L|%s|sh%d|proj%d" % [mode, int(light.shadow_enabled), int(light.light_projector != null)], "node": path})
		return out
	if not node is GeometryInstance3D:
		out.append({"key": "V|" + node.get_class(), "node": path})
		return out
	var geometry := node as GeometryInstance3D
	var flags := "sh%d tr%d fade%d" % [int(geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
		int(geometry.transparency > 0.0), int(geometry.visibility_range_fade_mode)]
	if geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: flags += " only"
	var overlay := _material_key(geometry.material_overlay) if geometry.material_overlay != null else ""
	if geometry is MeshInstance3D:
		var mi := geometry as MeshInstance3D
		_mesh_keys(mi.mesh, func(index: int) -> Material: return mi.get_active_material(index), "mesh " + flags, overlay, path, out)
	elif geometry is MultiMeshInstance3D:
		var mm := (geometry as MultiMeshInstance3D).multimesh
		if mm != null:
			var mm_flags := "mm tf%d c%d cd%d %s" % [int(mm.transform_format), int(mm.use_colors), int(mm.use_custom_data), flags]
			var override := geometry.material_override
			_mesh_keys(mm.mesh, func(index: int) -> Material: return override if override != null else (mm.mesh.surface_get_material(index) if mm.mesh != null else null), mm_flags, overlay, path, out)
	elif geometry is CPUParticles3D:
		var cpu := geometry as CPUParticles3D
		var override := geometry.material_override
		_mesh_keys(cpu.mesh, func(index: int) -> Material: return override if override != null else (cpu.mesh.surface_get_material(index) if cpu.mesh != null else null), "cpup " + flags, overlay, path, out)
	elif geometry is GPUParticles3D:
		var gpu := geometry as GPUParticles3D
		var override := geometry.material_override
		var process := _material_key(gpu.process_material) if gpu.process_material != null else "none"
		for pass_index in range(1, gpu.draw_passes + 1):
			var pass_mesh: Mesh = gpu.get("draw_pass_%d" % pass_index)
			_mesh_keys(pass_mesh, func(index: int) -> Material: return override if override != null else (pass_mesh.surface_get_material(index) if pass_mesh != null else null), "gpup proc=" + process + " " + flags, overlay, path, out)
	else:
		# Label3D, Sprite3D, CSG...: o material é gerado pelo nó a partir destas opções.
		var parts := PackedStringArray([geometry.get_class(), flags])
		for property in geometry.get_property_list():
			var kind := int(property.type)
			if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or not (kind == TYPE_BOOL or kind == TYPE_INT): continue
			var prop_name := str(property.name)
			if prop_name in ["layers", "sorting_offset", "render_priority", "outline_render_priority", "frame", "font_size", "outline_size", "physics_interpolation_mode", "process_mode", "process_priority", "process_physics_priority", "process_thread_group", "process_thread_group_order", "process_thread_messages", "editor_description", "unique_name_in_owner"]: continue
			parts.append("%s=%s" % [prop_name, str(geometry.get(prop_name))])
		parts.append("ovr=" + (_material_key(geometry.material_override) if geometry.material_override != null else "none"))
		out.append({"key": "O|" + "|".join(parts), "node": path})
	return out

func _mesh_keys(mesh: Mesh, material_of: Callable, flags: String, overlay: String, path: String, out: Array) -> void:
	if mesh == null: return
	for index in mesh.get_surface_count():
		var material: Material = material_of.call(index)
		var format := 0
		var primitive := 0
		if mesh is ArrayMesh:
			format = (mesh as ArrayMesh).surface_get_format(index)
			primitive = (mesh as ArrayMesh).surface_get_primitive_type(index)
		else:
			# PrimitiveMesh: formato fixo do tipo (posição, normal, tangente, UV).
			format = -1
			primitive = Mesh.PRIMITIVE_TRIANGLES
		var key := "S|%s|f%d|p%d|%s|%s" % [_material_key(material), format, primitive, flags, overlay]
		if mesh is PrimitiveMesh: key += "|" + mesh.get_class()
		out.append({"key": key, "node": path, "mesh": (mesh.resource_path if not mesh.resource_path.is_empty() else mesh.get_class() + ":" + str(mesh.resource_name)), "surface": index,
			"material": (material.resource_path if material != null and not material.resource_path.is_empty() else (str(material.resource_name) if material != null else "")),
			"material_ref": material})

func _material_key(material: Material) -> String:
	if material == null: return "none"
	var cached: Variant = _mat_cache.get(material.get_instance_id())
	if cached != null: return cached
	var key := ""
	if material is ShaderMaterial:
		var shader: Shader = (material as ShaderMaterial).shader
		if shader == null: key = "SM:null"
		elif not shader.resource_path.is_empty(): key = "SM:" + shader.resource_path.get_file()
		else: key = "SM:code#%d" % shader.code.hash()
	elif material is BaseMaterial3D:
		var parts := PackedStringArray([material.get_class()])
		for prop_name in _material_props: parts.append(str(int(material.get(prop_name))))
		var textures := ""
		for prop_name in _texture_props: textures += "1" if material.get(prop_name) != null else "0"
		parts.append(textures)
		key = "BM:" + ",".join(parts)
	else:
		key = material.get_class()
	if material.next_pass != null: key += ">" + _material_key(material.next_pass)
	_mat_cache[material.get_instance_id()] = key
	return key

func _counts() -> Dictionary:
	var counts := {}
	for key in SOURCES: counts[key] = int(Performance.get_monitor(SOURCES[key]))
	return counts

func _playing() -> bool:
	var scene := get_tree().current_scene
	if scene == null: return false
	var session: Variant = scene.get("session")
	return session != null and is_instance_valid(session) and bool(session.get("ready_for_play"))

func _scene_state() -> Dictionary:
	var state := {}
	var viewport := get_viewport()
	var world := viewport.find_world_3d()
	var environment: Environment = world.environment if world != null else null
	if environment != null:
		state["fog"] = environment.fog_enabled
		state["vfog"] = environment.volumetric_fog_enabled
		state["ssao"] = environment.ssao_enabled
		state["glow"] = environment.glow_enabled
	state["msaa"] = viewport.msaa_3d
	var scene := get_tree().current_scene
	if scene != null:
		var session: Variant = scene.get("session")
		if session != null and is_instance_valid(session):
			var weather: Variant = session.get("weather")
			if weather != null and is_instance_valid(weather):
				state["weather"] = weather.get("weather_state")
				state["hour"] = snappedf(float(weather.get("time_of_day")) * 24.0, 0.1)
		var gameplay: Variant = scene.get("gameplay")
		if gameplay != null and is_instance_valid(gameplay):
			state["stars"] = gameplay.get("stars")
			if gameplay.has_method("equipped"): state["weapon"] = str(gameplay.call("equipped"))
		var driving: Variant = scene.get("driving")
		if driving != null and is_instance_valid(driving): state["driving"] = driving.get("occupied")
	return state

func _stage(label: String) -> void:
	var now := Time.get_ticks_usec()
	var counts := _counts()
	var delta := {}
	for key in counts:
		var step := int(counts[key]) - int(_stage_counts.get(key, 0))
		if step != 0: delta[key] = step
	_write({"type": "stage", "label": label, "ms": snappedf(float(now - _stage_usec) / 1000.0, 0.1), "pipelines": delta,
		"t": snappedf(float(now - _started_usec) / 1000000.0, 0.001), "seen_keys": _seen.size()})
	_stage_label = "after:" + label
	_stage_usec = now
	_stage_counts = counts

func _write(record: Dictionary) -> void:
	if _file == null: return
	_file.store_line(JSON.stringify(record))
	_records += 1
	if _records % 8 == 0: _file.flush()

func _exit_tree() -> void:
	_write({"type": "end", "t": snappedf(float(Time.get_ticks_usec() - _started_usec) / 1000000.0, 0.001), "counts": _counts(),
		"game_pipelines": _game_pipelines, "seen_keys": _seen.size()})
	if _file != null:
		_file.flush()
		_file.close()
	if _instance == self: _instance = null
