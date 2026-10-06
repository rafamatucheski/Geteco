extends RefCounted
## Frozen, reversible light-parameter experiment; never a proposed global runtime setting.
static func capture_existing(tree: SceneTree,main: Node3D,folder: String) -> Dictionary:
	var camera := main.get_viewport().get_camera_3d()
	var sun: DirectionalLight3D=main.production.sun
	if camera==null or sun==null: return {"error":"Missing active camera or production sun"}
	var original := sun.shadow_normal_bias
	var depth_bias := sun.shadow_bias
	var original_pause := tree.paused
	var states: Array[Dictionary]=[]
	tree.paused=true
	states.append(await _photo(tree,sun,folder,"normal-bias-baseline"))
	var focused := "--focused-final-diagnostic" in OS.get_cmdline_user_args()
	if not focused:
		for candidate in [{"value":0.0,"id":"normal-bias-000"},{"value":.25,"id":"normal-bias-025"},{"value":.5,"id":"normal-bias-050"}]:
			sun.shadow_normal_bias=float(candidate.value)
			states.append(await _photo(tree,sun,folder,str(candidate.id)))
	sun.shadow_normal_bias=original
	var caster_report: Dictionary={"not_repeated":"Existing bias/caster controls were inconclusive or worse"}
	if not focused:
		states.append(await _photo(tree,sun,folder,"normal-bias-restored"))
		caster_report=await _caster_control(tree,main,folder,sun)
	var receiver_report := await _receiver_control(tree,main,folder,sun)
	var camera_report := await _camera_control(tree,main,folder,sun)
	var report := {"id":"canyon_shadow_normal_bias_diagnostic","original_normal_bias":original,"original_depth_bias":depth_bias,"restored":is_equal_approx(sun.shadow_normal_bias,original) and is_equal_approx(sun.shadow_bias,depth_bias),"camera_position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],"camera_rotation":[camera.global_rotation_degrees.x,camera.global_rotation_degrees.y,camera.global_rotation_degrees.z],"camera_size":camera.size,"captures":states,"scope":"Frozen A/B/A of sun normal bias only. Depth bias, geometry, original shader normals/materials, light direction and energy unchanged. Diagnostic only; no global runtime setting or performance approval."}
	report["caster_up_control"]=caster_report
	report["receiver_offsets_control"]=receiver_report
	report["camera_candidate_control"]=camera_report
	tree.paused=original_pause
	FileAccess.open(folder.path_join("canyon-normal-bias-diagnostic.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	return report

static func _receiver_control(tree: SceneTree,main: Node3D,folder: String,sun: DirectionalLight3D) -> Dictionary:
	var terrain := main.find_child("DesertCanyonTerrain",true,false)
	if terrain==null: return {"error":"Missing terrain for receiver control"}
	var originals: Dictionary={}
	for mesh in terrain.get_children():
		if mesh is MeshInstance3D: originals[mesh]=mesh.material_override
	var captures: Array[Dictionary]=[]
	for offset in [.3,.6]:
		var cache: Dictionary={}
		for mesh in originals:
			var material := originals[mesh] as ShaderMaterial
			if material==null or material.shader==null: continue
			var key := material.get_instance_id()
			if not cache.has(key):
				var source := material.shader.code
				var end := _function_end(source,"void fragment()")
				if end<0: continue
				var injection := "\n vec3 diagnostic_face = normalize(cross(dFdx(VERTEX),dFdy(VERTEX)));\n if (dot(diagnostic_face,NORMAL)<0.0) diagnostic_face=-diagnostic_face;\n float diagnostic_wall=smoothstep(8.0,12.0,world_pos.y)*smoothstep(0.15,0.35,1.0-normalize(world_normal).y);\n LIGHT_VERTEX=VERTEX+diagnostic_face*"+str(float(offset))+"*diagnostic_wall;\n"
				var shader := Shader.new()
				shader.code=source.substr(0,end)+injection+source.substr(end)
				var clone := material.duplicate() as ShaderMaterial
				clone.shader=shader
				for uniform in material.shader.get_shader_uniform_list():
					var name := str(uniform.get("name",""))
					var value: Variant=material.get_shader_parameter(name)
					if value!=null: clone.set_shader_parameter(name,value)
				cache[key]=clone
			mesh.material_override=cache[key]
		captures.append(await _photo(tree,sun,folder,"receiver-wall-030" if float(offset)<.5 else "receiver-wall-060"))
		for mesh in originals: mesh.material_override=originals[mesh]
	captures.append(await _photo(tree,sun,folder,"receiver-wall-restored"))
	var restored := true
	for mesh in originals: restored=restored and mesh.material_override==originals[mesh]
	return {"captures":captures,"restored":restored,"scope":"Independent original shaders, vertex normals unchanged, global bias unchanged. Receiver offset0.3/0.6m only above8m and normal slope greater0.15, smoothly weighted to12m/0.35. Diagnostic only; inspect car/rock contact shadows before considering any runtime offset."}

static func _caster_control(tree: SceneTree,main: Node3D,folder: String,sun: DirectionalLight3D) -> Dictionary:
	var terrain := main.find_child("DesertCanyonTerrain",true,false)
	if terrain==null: return {"error":"Missing terrain for caster control"}
	var originals: Dictionary={}
	var replacements: Dictionary={}
	var cache: Dictionary={}
	for mesh in terrain.get_children():
		if not mesh is MeshInstance3D: continue
		var material := mesh.material_override as ShaderMaterial
		if material==null or material.shader==null: return {"error":"Unexpected terrain material"}
		originals[mesh]=material
		var key := material.get_instance_id()
		if not cache.has(key):
			var source := material.shader.code
			var vertex_end := _function_end(source,"void vertex()")
			if vertex_end<0 or not source.contains("world_normal="): return {"error":"Cannot preserve authored world normal"}
			source=source.substr(0,vertex_end)+"\n NORMAL = vec3(0.0,1.0,0.0);\n"+source.substr(vertex_end)
			var fragment_at := source.find("void fragment()")
			var opening := source.find("{",fragment_at)
			if fragment_at<0 or opening<0: return {"error":"Missing fragment body"}
			source=source.substr(0,opening+1)+"\n NORMAL = normalize((VIEW_MATRIX * vec4(world_normal,0.0)).xyz);\n"+source.substr(opening+1)
			var clone := material.duplicate() as ShaderMaterial
			var shader := Shader.new()
			shader.code=source
			clone.shader=shader
			for uniform in material.shader.get_shader_uniform_list():
				var name := str(uniform.get("name",""))
				var value: Variant=material.get_shader_parameter(name)
				if value!=null: clone.set_shader_parameter(name,value)
			cache[key]=clone
		replacements[mesh]=cache[key]
	for mesh in originals: mesh.material_override=replacements[mesh]
	var candidate := await _photo(tree,sun,folder,"caster-up-normal")
	for mesh in originals: mesh.material_override=originals[mesh]
	var restored_photo := await _photo(tree,sun,folder,"caster-up-restored")
	var restored := true
	for mesh in originals: restored=restored and mesh.material_override==originals[mesh]
	return {"candidate":candidate,"restored_photo":restored_photo,"materials_restored":restored,"scope":"Vertex NORMAL=UP after authored world_normal recorded; fragment restores authored view normal before original shader. Original global bias, ALBEDO, geometry and collision retained."}

static func _camera_control(tree: SceneTree,main: Node3D,folder: String,sun: DirectionalLight3D) -> Dictionary:
	var camera: Camera3D=main.camera
	var pose := camera.global_transform
	var size := camera.size
	var processing := camera.is_processing()
	var focus: Vector3=main.camera.focus
	var nominal: Vector3=main.camera.offset.rotated(Vector3.UP,float(main.camera.heading))
	var target: Vector3=main.camera.target.global_position if is_instance_valid(main.camera.target) else focus
	var view := Vector2(size*camera.get_viewport().get_visible_rect().size.aspect(),size)
	var helper := preload("res://tests/capture/DesertTerrainCameraCandidate.gd").new()
	var began := Time.get_ticks_usec()
	var offset: Vector3=helper.offset_for(focus,nominal,.1,true,true,view,camera.near,target,3.4,Vector3.ZERO)
	var solve_usec := Time.get_ticks_usec()-began
	camera.set_process(false)
	camera.global_position=focus+offset
	camera.look_at(focus)
	var candidate := await _photo(tree,sun,folder,"camera-frustum-candidate")
	var diagnostics: Dictionary=helper.diagnostics()
	candidate["position"]=[camera.global_position.x,camera.global_position.y,camera.global_position.z]
	candidate["rotation"]=[camera.global_rotation_degrees.x,camera.global_rotation_degrees.y,camera.global_rotation_degrees.z]
	camera.global_transform=pose
	camera.size=size
	var restored := await _photo(tree,sun,folder,"camera-frustum-restored")
	camera.set_process(processing)
	return {"candidate":candidate,"restored_photo":restored,"diagnostics":diagnostics,"first_solve_usec_not_fps":solve_usec,"restored":camera.global_transform.is_equal_approx(pose) and is_equal_approx(camera.size,size),"scope":"Fixture-only copied camera candidate, first frozen pose solve. Original normal bias/materials restored before this case. Not temporal or performance approval."}

static func _function_end(source: String,signature: String) -> int:
	var function_at := source.find(signature)
	if function_at<0: return -1
	var opening := source.find("{",function_at)
	var depth := 0
	for i in range(opening,source.length()):
		if source[i]=="{": depth+=1
		elif source[i]=="}":
			depth-=1
			if depth==0: return i
	return -1

static func _photo(tree: SceneTree,sun: DirectionalLight3D,folder: String,id: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(folder.path_join(id+".png"))
	return {"id":id,"normal_bias":sun.shadow_normal_bias,"depth_bias":sun.shadow_bias,"energy":sun.light_energy,"enabled":sun.shadow_enabled}
