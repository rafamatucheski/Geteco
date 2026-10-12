extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Native Main diagnostic: --market --camera-preview --night --seconds=30 --no-save.
## Temporary owned-overlay replacements and screenshots INVALIDATE all FPS results.
const CITY_LOOK_SCRIPT := preload("res://world/city_look/CityLook.gd")
const OWNED_SHADER := preload("res://world/city_look/occluded_silhouette.gdshader")
const PARAMETERS := ["tint","bias","target_inverse","box_min","box_max","minimum_occluder_height"]
const PHASES := ["default","magenta_same_depth","white_no_depth","without_selfbox","without_height","bias_zero","restored"]
var _branch_look: Node
var _branch_shaders: Dictionary = {}
var _branch_overlays: Array[Dictionary] = []
var _branch_records: Array[Dictionary] = []
var _branch_invalid: Array[String] = []
var _branch_index := 0
var _branch_busy := false
var _branch_started := false
var _branch_next_usec := 0
var _branch_stopped := false

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--walk" in args or "--profile" in args or "--reveal-on" in args:
		push_error("SILHOUETTE_BRANCH_DIAGNOSTIC_REQUIRES_STATIONARY_NO_PROFILE_NO_REVEAL")
		quit(7)
		return
	if not _prepare_branch_shaders():
		quit(7)
		return
	await super.run()
	_restore_branch_overlays()
	_export_branches()

func _prepare_branch_shaders() -> bool:
	var code := OWNED_SHADER.code.replace("\r\n","\n")
	var selfbox := "\tif (all(greaterThanEqual(local, box_min)) && all(lessThanEqual(local, box_max))) {\n\t\tdiscard;\n\t}"
	var height := "\tif (local.y < minimum_occluder_height) {\n\t\tdiscard;\n\t}"
	var bias := "uniform float bias = 0.004;"
	var color := "\tALBEDO = tint.rgb;\n\tALPHA = tint.a * (0.08 + 0.92 * pow(rim, 2.5));"
	for fragment in [selfbox,height,bias,color]:
		if code.count(fragment) != 1:
			push_error("SILHOUETTE_BRANCH_SOURCE_CONTRACT_CHANGED")
			return false
	var sources := {
		"magenta_same_depth":code.replace(color,"\tALBEDO = vec3(1.0, 0.0, 1.0);\n\tALPHA = 1.0;"),
		"white_no_depth":"shader_type spatial;\nrender_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, blend_mix;\nvoid fragment() { ALBEDO = vec3(1.0); ALPHA = 1.0; }",
		"without_selfbox":code.replace(selfbox,"\t// Diagnostic: self-box discard omitted."),
		"without_height":code.replace(height,"\t// Diagnostic: minimum-height discard omitted."),
		"bias_zero":code.replace(bias,"uniform float bias = 0.0;")}
	for key in sources:
		var shader := Shader.new()
		shader.code = sources[key]
		_branch_shaders[key] = shader
	return true

func apply_load(now: int) -> void:
	super.apply_load(now)
	if _branch_stopped: return
	if not _branch_started:
		if frames.is_empty(): return
		for child in world.get_children():
			if child.get_script() == CITY_LOOK_SCRIPT:
				_branch_look = child
				break
		if _branch_look == null:
			_branch_invalid.append("city_look_not_found")
			_branch_stopped = true
			return
		_branch_started = true
		_branch_next_usec = now
	# CityLook continues updating its owned originals; keep duplicated uniforms
	# synchronized without adopting its callbacks or changing its registry.
	for row in _branch_overlays:
		if not is_instance_valid(row.geometry): continue
		if row.geometry.material_overlay != row.temporary:
			_branch_invalid.append("overlay_replaced_externally:"+str(row.geometry.get_path()))
			continue
		if row.phase == "white_no_depth": continue
		for parameter in PARAMETERS:
			row.temporary.set_shader_parameter(parameter,0.0 if row.phase == "bias_zero" and parameter == "bias" else row.original.get_shader_parameter(parameter))
	if not _branch_busy and _branch_index < PHASES.size() and now >= _branch_next_usec:
		_capture_branch()

func _capture_branch() -> void:
	_branch_busy = true
	await RenderingServer.frame_post_draw
	if _branch_stopped:
		_branch_busy = false
		return
	var phase: String = PHASES[_branch_index]
	var path := output.path_join(label+"-silhouette-"+phase+".png")
	DirAccess.make_dir_recursive_absolute(output)
	var began := Time.get_ticks_usec()
	var result := root.get_texture().get_image().save_png(path)
	var record := _branch_snapshot()
	record.merge({"phase":phase,"capture_start_usec":began,"capture_end_usec":Time.get_ticks_usec(),
		"image":path,"image_error":result,"temporary_overlays":_branch_overlays.size()})
	_branch_records.append(record)
	print("SILHOUETTE_BRANCH_CAPTURE ",JSON.stringify({"phase":phase,"image":path,"overlays":_branch_overlays.size()}))
	_restore_branch_overlays()
	_branch_index += 1
	if _branch_index < PHASES.size():
		var next: String = PHASES[_branch_index]
		if next != "restored": _install_branch(next)
		_branch_next_usec = Time.get_ticks_usec()+4000000
	else:
		_branch_stopped = true
		_export_branches()
	_branch_busy = false

func _install_branch(phase: String) -> void:
	var owners: Dictionary = _branch_look.get("_silhouettes")
	for target in owners:
		if not is_instance_valid(target): continue
		var original := owners[target] as ShaderMaterial
		if original == null or original.shader != OWNED_SHADER: continue
		var temporary := original.duplicate() as ShaderMaterial
		temporary.shader = _branch_shaders[phase]
		if phase == "bias_zero": temporary.set_shader_parameter("bias",0.0)
		for node in target.find_children("*","GeometryInstance3D",true,false):
			if node.material_overlay != original: continue
			_branch_overlays.append({"geometry":node,"original":original,"temporary":temporary,"phase":phase})
			node.material_overlay = temporary
	if _branch_overlays.is_empty(): _branch_invalid.append("no_owned_overlays:"+phase)

func _restore_branch_overlays() -> void:
	for row in _branch_overlays:
		if is_instance_valid(row.geometry) and row.geometry.material_overlay == row.temporary:
			row.geometry.material_overlay = row.original
	_branch_overlays.clear()

func _material_state(material: Material) -> Dictionary:
	if material == null: return {}
	var result := {"id":material.get_instance_id(),"class":material.get_class()}
	if material is ShaderMaterial:
		result.shader_id = material.shader.get_instance_id() if material.shader != null else 0
		result.shader_path = material.shader.resource_path if material.shader != null else ""
		for parameter in PARAMETERS: result[parameter] = str(material.get_shader_parameter(parameter))
	return result

func _branch_snapshot() -> Dictionary:
	var camera: Camera3D = world.camera
	var meshes: Array[Dictionary] = []
	for node in world.player.find_children("*","GeometryInstance3D",true,false):
		var geometry := node as GeometryInstance3D
		meshes.append({"path":str(geometry.get_path()),"id":geometry.get_instance_id(),
			"visible":geometry.visible,"visible_in_tree":geometry.is_visible_in_tree(),
			"aabb":str(geometry.get_aabb()),"global_aabb":str(geometry.global_transform*geometry.get_aabb()),
			"transform":str(geometry.global_transform),"layers":geometry.layers,
			"overlay":_material_state(geometry.material_overlay)})
	var owners: Array[Dictionary] = []
	var registry: Dictionary = _branch_look.get("_silhouettes")
	for target in registry:
		owners.append({"target":str(target.get_path()) if is_instance_valid(target) else "invalid",
			"material":_material_state(registry[target])})
	var targets: Array[String] = []
	for target in _branch_look.get("_silhouette_targets"):
		targets.append(str(target.get_path()) if is_instance_valid(target) else "invalid")
	return {"usec":Time.get_ticks_usec(),"focused":DisplayServer.window_is_focused(),"state":state(),
		"camera":{"near":camera.near,"far":camera.far,"projection":camera.projection,
			"size":camera.size,"transform":str(camera.global_transform),"cull_mask":camera.cull_mask,
			"player_screen":str(camera.unproject_position(world.player.global_position+Vector3.UP))},
		"city_look":{"targets":targets,"registry":owners,"inside":_branch_look.get("_silhouette_inside"),
			"player_visible":_branch_look.get("_silhouette_player_visible")},"player_meshes":meshes}

func stats(values: Array[float]) -> Dictionary:
	_branch_stopped = true
	_restore_branch_overlays()
	var summary := super.stats(values)
	summary["invalid_for_fps"] = true
	summary["reason"] = "Temporary shader branches, compilation and screenshot readbacks contaminate performance."
	return summary

func _export_branches() -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	var report := {"label":label,"invalid_for_fps":true,"invalid":_branch_invalid,
		"records":_branch_records,"expected_phases":PHASES,"restored":_branch_overlays.is_empty(),
		"scope":"Shader branch diagnosis only. Screenshots, shader compilation and temporary overlays invalidate every FPS summary from this run. Native Main callbacks, CityLook registry and original shader files remain unchanged. Only geometry with an exact owned material/shader receives a duplicated temporary overlay; previous overlays are restored. Live traffic and pose continue; each variant lasts at least4s."}
	FileAccess.open(output.path_join(label+"-silhouette-branches.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
