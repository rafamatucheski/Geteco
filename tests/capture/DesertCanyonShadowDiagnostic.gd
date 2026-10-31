extends RefCounted
## Temporary material-only A/B/A comparison on the real canyon. Never a runtime fix.
static func capture_existing(tree: SceneTree,main: Node3D,folder: String) -> Dictionary:
	var terrain := main.find_child("DesertCanyonTerrain",true,false)
	var camera := main.get_viewport().get_camera_3d()
	if terrain==null or camera==null: return {"error":"Canyon terrain or camera missing"}
	var originals: Dictionary={}
	var meshes: Array[Dictionary]=[]
	for child in terrain.get_children():
		if not child is MeshInstance3D: continue
		var material := child.material_override as ShaderMaterial
		if material==null or material.shader==null: return {"error":"Canyon material is not the expected shader"}
		if child.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return {"error":"Canyon shadow casting is already disabled"}
		originals[child]=material
		meshes.append({"path":str(child.get_path()),"material_id":material.get_instance_id(),"shader_sha256":material.shader.code.sha256_text(),"cast_shadow":child.cast_shadow})
	if originals.is_empty(): return {"error":"No canyon mesh materials"}
	# Monta os candidatos antes de pausar. Todo clone mantém o albedo e os uniforms existentes.
	var variants: Array[Dictionary]=[]
	for candidate in [{"id":"shadow-face-normal","tail":"NORMAL = canyon_diagnostic_face;"},{"id":"shadow-light-vertex-002","tail":"LIGHT_VERTEX = VERTEX + canyon_diagnostic_face * 0.02;"},{"id":"shadow-light-vertex-006","tail":"LIGHT_VERTEX = VERTEX + canyon_diagnostic_face * 0.06;"}]:
		var replacements: Dictionary={}
		var cache: Dictionary={}
		for mesh in originals:
			var material: ShaderMaterial=originals[mesh]
			var key := material.get_instance_id()
			if not cache.has(key):
				var clone := material.duplicate() as ShaderMaterial
				var shader := Shader.new()
				var injected := _inject(material.shader.code,str(candidate.tail))
				if injected.is_empty(): return {"error":"Cannot find fragment closing brace safely"}
				shader.code=injected
				clone.shader=shader
				for uniform in material.shader.get_shader_uniform_list():
					var uniform_name := str(uniform.get("name",""))
					var value: Variant=material.get_shader_parameter(uniform_name)
					if value!=null: clone.set_shader_parameter(uniform_name,value)
				cache[key]=clone
			replacements[mesh]=cache[key]
		variants.append({"id":candidate.id,"materials":replacements})
	var sun: DirectionalLight3D=main.production.sun
	var was_paused := tree.paused
	tree.paused=true
	await _photo(tree,folder,"shadow-baseline")
	for candidate in variants:
		for mesh in originals: mesh.material_override=candidate.materials[mesh]
		await _photo(tree,folder,str(candidate.id))
	for mesh in originals: mesh.material_override=originals[mesh]
	await _photo(tree,folder,"shadow-restored")
	var restored := true
	for mesh in originals: restored=restored and mesh.material_override==originals[mesh]
	var report := {"id":"canyon_local_shadow_diagnostic","meshes":meshes,"sun":{"bias":sun.shadow_bias,"normal_bias":sun.shadow_normal_bias,"enabled":sun.shadow_enabled,"reverse_cull":sun.shadow_reverse_cull_face,"blur":sun.shadow_blur,"max_distance":sun.directional_shadow_max_distance,"rotation_degrees":_v3(sun.rotation_degrees),"energy":sun.light_energy},"camera":{"position":_v3(camera.global_position),"rotation_degrees":_v3(camera.global_rotation_degrees),"size":camera.size,"projection":camera.projection},"restored_materials":restored,"original_pause":was_paused,"source_shader_unchanged":true,"geometry_and_colliders_unchanged":true,"global_light_unchanged":true,"scope":"Frozen material-only A/B/A. Same original ALBEDO and uniforms in every candidate. Case1 geometric fragment normal; cases2/3 independent receiver-position offsets0.02/0.06m. No runtime fix, physics, performance or temporal validation."}
	tree.paused=was_paused
	FileAccess.open(folder.path_join("canyon-shadow-diagnostic.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	return report

static func _inject(source: String,tail: String) -> String:
	var start := source.find("void fragment()")
	if start<0: return ""
	var opening := source.find("{",start)
	var depth := 0
	for i in range(opening,source.length()):
		if source[i]=="{": depth+=1
		elif source[i]=="}":
			depth-=1
			if depth==0:
				var code := "\n\tvec3 canyon_diagnostic_face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));\n\tif (dot(canyon_diagnostic_face, NORMAL) < 0.0) canyon_diagnostic_face = -canyon_diagnostic_face;\n\t"+tail+"\n"
				return source.substr(0,i)+code+source.substr(i)
	return ""

static func _photo(tree: SceneTree,folder: String,id: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(folder.path_join(id+".png"))

static func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
