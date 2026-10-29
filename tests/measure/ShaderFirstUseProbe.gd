extends Node
## Diagnóstico de primeira compilação de shader de cena (cache ShaderRD frio).
## A cada quadro lista os arquivos do cache SceneForwardMobileShaderRD; quando
## surge uma chave nova (gravada no fim da compilação, dentro do desenho), mostra
## as assinaturas de material vistas pela primeira vez nos quadros anteriores.
## Só para medição: percorre a árvore inteira quando há chave nova (custa ms).
const CACHE_DIR := "user://shader_cache/SceneForwardMobileShaderRD"
const RECENT_FRAMES := 3
## Forward+ grava em SceneForwardClusteredShaderRD (map_shader_cache_files.gd troca).
var cache_dir := CACHE_DIR

var keys := {}
var seen := {}            # assinatura -> {frame, sample}
var recent: Array = []    # [frame, assinatura]
var pending: Array[Node] = []
var by_id := {}           # instance_id do material -> assinatura (evita refazer)
var reports: Array = []
var listing_usec := 0
var walk_usec := 0

func _ready() -> void:
	for key in _keys(): keys[key] = Engine.get_process_frames()
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is GeometryInstance3D: pending.append(node))

func _process(_delta: float) -> void:
	var frame := Engine.get_process_frames()
	# Materiais costumam ser atribuídos em _ready: avalia no quadro seguinte.
	var batch := pending
	pending = []
	for node in batch:
		if is_instance_valid(node) and node.is_inside_tree(): _register(node, frame)
	var began := Time.get_ticks_usec()
	var fresh: Array = []
	for key in _keys():
		if not keys.has(key):
			keys[key] = frame
			fresh.append(key)
	listing_usec += Time.get_ticks_usec()-began
	if fresh.is_empty():
		if recent.size() > 4096: recent = recent.filter(func(item): return int(item[0]) >= frame-RECENT_FRAMES)
		return
	# Varredura completa: pega materiais trocados em nós antigos (sem node_added).
	began = Time.get_ticks_usec()
	var walked: Array = []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D and (node as GeometryInstance3D).is_visible_in_tree():
			for signature in _register(node, frame): walked.append(signature)
		for child in node.get_children(): stack.append(child)
	walk_usec += Time.get_ticks_usec()-began
	var candidates: Array = []
	for item in recent:
		if int(item[0]) >= frame-RECENT_FRAMES: candidates.append({"frame":item[0], "signature":item[1], "sample":seen[item[1]].sample})
	var row := {"frame":frame, "engine_usec":Time.get_ticks_usec(), "keys":fresh, "candidates":candidates}
	reports.append(row)
	print("SHADER_PROBE ", JSON.stringify(row))
	recent = recent.filter(func(item): return int(item[0]) >= frame-RECENT_FRAMES)

func _register(node: GeometryInstance3D, frame: int) -> Array:
	var found: Array = []
	for material in _materials(node):
		var id: int = material.get_instance_id()
		var signature: String = by_id.get(id, "")
		if signature.is_empty():
			signature = _signature(material, node)
			if not material is SpriteBase3D: by_id[id] = signature
		if seen.has(signature): continue
		seen[signature] = {"frame":frame, "sample":_describe(node, material)}
		recent.append([frame, signature])
		found.append(signature)
	return found

func _materials(node: GeometryInstance3D) -> Array:
	var result: Array = []
	if node.material_override != null: result.append(node.material_override)
	if node.material_overlay != null: result.append(node.material_overlay)
	var meshes: Array = []
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			for surface in instance.mesh.get_surface_count():
				var override := instance.get_surface_override_material(surface)
				result.append(override if override != null else instance.mesh.surface_get_material(surface))
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		meshes.append((node as MultiMeshInstance3D).multimesh.mesh)
	elif node is GPUParticles3D:
		for pass_index in (node as GPUParticles3D).draw_passes:
			meshes.append((node as GPUParticles3D).get_draw_pass_mesh(pass_index))
	elif node is CPUParticles3D:
		meshes.append((node as CPUParticles3D).mesh)
	elif node is SpriteBase3D:
		# Material interno do sprite/Label3D: assinatura pelos modos do nó.
		result.append(node)
	for mesh in meshes:
		if mesh is Mesh:
			for surface in mesh.get_surface_count(): result.append(mesh.surface_get_material(surface))
	var expanded: Array = []
	for material in result:
		var current: Variant = material
		var depth := 0
		while current != null and depth < 4:
			expanded.append(current)
			current = current.next_pass if current is Material else null
			depth += 1
	return expanded

## Aproxima a MaterialKey do motor: bools/enums e presença de texturas mudam o
## código do shader; cores e floats são uniforms e não geram versão nova.
func _signature(material: Object, node: Node) -> String:
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader == null: return "ShaderMaterial:null"
		return "ShaderMaterial:" + (shader.resource_path if not shader.resource_path.is_empty() else str(shader.code.hash()))
	var parts: PackedStringArray = [material.get_class()]
	for property in material.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE): continue
		var value: Variant = material.get(property.name)
		match typeof(value):
			TYPE_BOOL, TYPE_INT: parts.append("%s=%s" % [property.name, value])
			TYPE_OBJECT:
				if property.name != "next_pass" and property.name != "script": parts.append("%s=%s" % [property.name, value != null])
	if material is SpriteBase3D: parts.append("node")
	return "|".join(parts)

func _describe(node: Node, material: Object) -> Dictionary:
	var owner_script := ""
	var cursor := node
	while cursor != null and owner_script.is_empty():
		var script: Variant = cursor.get_script()
		if script != null: owner_script = str(script.resource_path) + " @" + str(cursor.name)
		cursor = cursor.get_parent()
	var mesh_path := ""
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null: mesh_path = (node as MeshInstance3D).mesh.resource_path
	return {"node":str(node.get_path()), "class":node.get_class(), "owner_script":owner_script, "mesh":mesh_path,
		"material_class":material.get_class(), "material_path":material.resource_path if material is Resource else "",
		"material_name":material.resource_name if material is Resource else ""}

func _keys() -> PackedStringArray:
	var result: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(cache_dir): return result
	for group in DirAccess.get_directories_at(cache_dir):
		for file in DirAccess.get_files_at(cache_dir.path_join(group)):
			result.append(group.left(8) + "/" + file.get_basename().get_basename())
	return result

func export_report() -> Dictionary:
	return {"reports":reports, "listing_usec":listing_usec, "walk_usec":walk_usec, "signatures":seen.size(),
		"scope":"Assinatura aproxima MaterialKey; candidato = assinatura nova nos 3 quadros anteriores à chave. Coincidência, não prova; confirmar renderizando o material isolado."}
