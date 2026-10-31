extends RefCounted
## Controles independentes, não cumulativos: distância da câmera, culling visual e depois culling de projetores de sombra.
static func capture_existing(tree: SceneTree,main: Node3D,folder: String) -> Dictionary:
	var terrain := main.find_child("DesertCanyonTerrain",true,false)
	var camera := main.get_viewport().get_camera_3d()
	if terrain==null or camera==null: return {"error":"Missing camera/canyon"}
	if camera.projection!=Camera3D.PROJECTION_ORTHOGONAL: return {"error":"Requires the normal orthographic camera"}
	var originals: Dictionary={}
	var shadow_modes: Dictionary={}
	var double_materials: Dictionary={}
	var cache: Dictionary={}
	for child in terrain.get_children():
		if not child is MeshInstance3D: continue
		var material := child.material_override as ShaderMaterial
		if material==null or material.shader==null: return {"error":"Unexpected canyon material"}
		originals[child]=material
		shadow_modes[child]=child.cast_shadow
		var key := material.get_instance_id()
		if not cache.has(key):
			var clone := material.duplicate() as ShaderMaterial
			var shader := Shader.new()
			var code := material.shader.code
			if code.contains("cull_back") or code.contains("cull_front"):
				code=code.replace("cull_back","cull_disabled").replace("cull_front","cull_disabled")
			elif not code.contains("cull_disabled"):
				var mode_at := code.find("render_mode ")
				if mode_at>=0: code=code.substr(0,mode_at)+"render_mode cull_disabled, "+code.substr(mode_at+12)
				else: code=code.replace("shader_type spatial;","shader_type spatial;\nrender_mode cull_disabled;")
			shader.code=code
			clone.shader=shader
			for uniform in material.shader.get_shader_uniform_list():
				var name := str(uniform.get("name",""))
				var value: Variant=material.get_shader_parameter(name)
				if value!=null: clone.set_shader_parameter(name,value)
			cache[key]=clone
		double_materials[child]=cache[key]
	var old_pose := camera.global_transform
	var old_size := camera.size
	var old_processing := camera.is_processing()
	var was_paused := tree.paused
	var focus: Vector3=main.camera.focus
	var states: Array[Dictionary]=[]
	tree.paused=true
	camera.set_process(false)
	states.append(await _photo(tree,camera,folder,"frustum-baseline"))
	# Mesma direção de visão, tamanho e projeção ortogonal: pura translação ao longo do eixo óptico.
	camera.global_position=focus+(old_pose.origin-focus)*2.0
	states.append(await _photo(tree,camera,folder,"frustum-distance-2x"))
	camera.global_transform=old_pose
	for mesh in originals: mesh.material_override=double_materials[mesh]
	states.append(await _photo(tree,camera,folder,"frustum-cull-disabled-only"))
	for mesh in originals:
		mesh.material_override=originals[mesh]
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	states.append(await _photo(tree,camera,folder,"frustum-double-sided-cast-only"))
	for mesh in originals: mesh.cast_shadow=shadow_modes[mesh]
	states.append(await _photo(tree,camera,folder,"frustum-restored"))
	var restored := camera.global_transform.is_equal_approx(old_pose) and is_equal_approx(camera.size,old_size)
	for mesh in originals: restored=restored and mesh.material_override==originals[mesh] and mesh.cast_shadow==shadow_modes[mesh]
	camera.set_process(old_processing)
	tree.paused=was_paused
	var report := {"id":"canyon_ortho_frustum_diagnostic","focus":_v3(focus),"mesh_count":originals.size(),"captures":states,"restored":restored,"scope":"Three independent controls from original state: camera translation2x, terrain visual cull_disabled, terrain double-sided shadow casting. Original shader colours/light/geometry/physics unchanged. Camera translation can also affect directional shadow cascade allocation; compare silhouette and clipping separately from shadow detail. No runtime fix or performance approval."}
	FileAccess.open(folder.path_join("canyon-frustum-diagnostic.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	return report

static func _photo(tree: SceneTree,camera: Camera3D,folder: String,id: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(folder.path_join(id+".png"))
	return {"id":id,"position":_v3(camera.global_position),"rotation_degrees":_v3(camera.global_rotation_degrees),"projection":camera.projection,"size":camera.size,"near":camera.near,"far":camera.far}

static func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
