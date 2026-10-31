extends SceneTree
## Diagnóstico renderizado no Main/.NET. Ritmo normal, sem save e sem edições na produção.
## -- --no-save --skip-arrival --population=24 --label=before
## Trinta segundos de cronometragem vêm antes de todas as capturas e sondas de deformação da pele.

const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")
const OUT := "res://evidence/dante-idle-grounding-20261011/"
var world
var player
var folder := ""
var label := "before"
var phase := "setup"
var failures: Array[String] = []
var checks := 0
var finished := false
var capture_rows: Array[Dictionary] = []
var temporal_rows: Array[Dictionary] = []
var frame_ms: Array[float] = []
var collecting := false
var last_usec := 0
var observation_began := 0
var report: Dictionary = {}
var bind_bones: Array[int] = []
var bind_poses: Array[Transform3D] = []
var surfaces: Array[Dictionary] = []
var foot_bones: Dictionary = {}
var sole_selection: Dictionary = {}
var detail: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	print("IDLE_GROUND ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func _v(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

func _save(name: String, value: Dictionary) -> void:
	if folder.is_empty(): return
	var file := FileAccess.open(folder.path_join(name + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "\t"))

func _release() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(action)

func _finish(code: int) -> void:
	if finished: return
	finished = true
	collecting = false
	_release()
	report.merge({"label":label,"checks":checks,"failures":failures,"ok":code==0 and failures.is_empty(),"captures":capture_rows,"temporal_samples":temporal_rows,"completed_utc":Time.get_datetime_string_from_system(true)},true)
	_save("grounding",report)
	print("DANTE_IDLE_GROUNDING ", JSON.stringify({"label":label,"checks":checks,"failures":failures,"exit_code":code,"folder":folder}))
	quit(code)

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < end and not finished: await process_frame

func _frame() -> void:
	if not collecting or not is_instance_valid(player): return
	var now := Time.get_ticks_usec()
	if last_usec > 0 and phase == "timing": frame_ms.append(float(now-last_usec)/1000.0)
	last_usec = now
	var row := {"usec":now,"elapsed":float(now-observation_began)/1000000.0,"phase":phase,"actor":_v(player.global_position),"visual_local":_v(player.visual.position),"velocity":_v(player.velocity),"on_floor":player.is_on_floor(),"floor_normal":_v(player.get_floor_normal()),"locomotion_weight":player._locomotion_weight,"run_weight":player._run_weight,"focused":root.has_focus()}
	for side in foot_bones:
		row[side+"_ankle"] = _v(player.skeleton.to_global(player.skeleton.get_bone_global_pose(int(foot_bones[side])).origin))
	temporal_rows.append(row)

func _ground(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.6,point-Vector3.UP*2.0,1)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"hit":false}
	return {"hit":true,"point":_v(hit.position),"y":hit.position.y,"normal":_v(hit.normal),"flat":hit.normal.dot(Vector3.UP)>.999,"collider":str(hit.collider.get_path())}

func _prepare_skin() -> bool:
	var mesh: MeshInstance3D = player._combat_skin
	if mesh == null or mesh.skin == null or mesh.mesh == null: return false
	for side in ["Left","Right"]:
		var index: int = player.skeleton.find_bone(side+"Foot")
		if index < 0: return false
		foot_bones[side] = index
	for index in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(index)
		if bone < 0: bone = player.skeleton.find_bone(mesh.skin.get_bind_name(index))
		if bone < 0: return false
		bind_bones.append(bone)
		bind_poses.append(mesh.skin.get_bind_pose(index))
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or weights.is_empty(): continue
		var influences := int(weights.size()/vertices.size())
		var candidates := {"Left":[],"Right":[]}
		for vertex in vertices.size():
			var side_weights := {"Left":0.0,"Right":0.0}
			for influence in influences:
				var offset := vertex*influences+influence
				var name: String = player.skeleton.get_bone_name(bind_bones[bones[offset]])
				for side in side_weights:
					if name.begins_with(side) and ("Foot" in name or "Toe" in name): side_weights[side] += weights[offset]
			for side in candidates:
				if float(side_weights[side])>.25: candidates[side].append(vertex)
		surfaces.append({"vertices":vertices,"bones":bones,"weights":weights,"influences":influences,"candidates":candidates})
	# Seleciona a sola UMA vez na pose de repouso importada. Selecionar o Y mínimo
	# atual acusaria a ponta do pé no chão enquanto esconde um calcanhar erguido.
	var rests: Array[Transform3D] = []
	for index in bind_bones.size(): rests.append(player.skeleton.get_bone_global_rest(bind_bones[index])*bind_poses[index])
	var scale_y: float = player.skeleton.global_basis.y.length()
	for side in ["Left","Right"]:
		var toe := -1
		for bone in player.skeleton.get_bone_count():
			var bone_name: String = player.skeleton.get_bone_name(bone)
			if bone_name.begins_with(side) and "Toe" in bone_name:
				toe=bone; break
		if toe<0: return false
		var ankle_rest: Vector3 = player.skeleton.get_bone_global_rest(int(foot_bones[side])).origin
		var toe_rest: Vector3 = player.skeleton.get_bone_global_rest(toe).origin
		var forward := toe_rest-ankle_rest
		forward.y=0
		if forward.length()<.001: return false
		forward=forward.normalized()
		var candidates: Array[Dictionary] = []
		var bottom := INF
		for surface_index in surfaces.size():
			var surface: Dictionary = surfaces[surface_index]
			for vertex in surface.candidates[side]:
				var point := _skin_vertex(surface,int(vertex),rests)
				bottom=minf(bottom,point.y)
				candidates.append({"surface":surface_index,"vertex":vertex,"rest":point,"axis":point.dot(forward)})
		var selected: Array[Dictionary] = []
		var axis_min := INF
		var axis_max := -INF
		for candidate in candidates:
			if (float(candidate.rest.y)-bottom)*scale_y<=.006:
				selected.append(candidate)
				axis_min=minf(axis_min,candidate.axis)
				axis_max=maxf(axis_max,candidate.axis)
		if selected.is_empty() or axis_max-axis_min<.02: return false
		for candidate in selected:
			candidate.region="heel" if float(candidate.axis)<(axis_min+axis_max)*.5 else "forefoot"
		sole_selection[side]={"vertices":selected,"rest_bottom_local_y":bottom,"toe_bone":player.skeleton.get_bone_name(toe),"forward_rest":_v(forward),"rest_axis_range":[axis_min,axis_max],"band_m":.006}
	return not surfaces.is_empty()

func _skin_vertex(surface: Dictionary, vertex: int, matrices: Array[Transform3D]) -> Vector3:
	var point := Vector3.ZERO
	for influence in int(surface.influences):
		var index := vertex*int(surface.influences)+influence
		point += (matrices[surface.bones[index]]*surface.vertices[vertex])*surface.weights[index]
	return point

func _range(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	return {"count":values.size(),"min":values[0],"p50":values[int((values.size()-1)*.5)],"p95":values[int((values.size()-1)*.95)],"max":values.back()}

func _soles() -> Dictionary:
	# Mesma reconstrução ponderada do bind de Skin da foot_probe anterior. Usa as transformações
	# reais de mundo do esqueleto, incluindo escala do ator/modelo e deslocamento visual.
	var matrices: Array[Transform3D] = []
	for index in bind_bones.size(): matrices.append(player.skeleton.get_bone_global_pose(bind_bones[index])*bind_poses[index])
	var result := {}
	for side in ["Left","Right"]:
		var lowest := Vector3(0,INF,0)
		var count := 0
		for surface in surfaces:
			for vertex in surface.candidates[side]:
				var point: Vector3 = player.skeleton.to_global(_skin_vertex(surface,int(vertex),matrices))
				if point.y < lowest.y: lowest = point
				count += 1
		var ground := _ground(lowest) if count>0 else {"hit":false}
		var value := {"vertices":count,"lowest_any_foot_vertex":_v(lowest) if count>0 else [],"ground":ground,"regions":{}}
		if ground.hit:
			value.minimum_any_foot_gap_m = lowest.y-float(ground.y)
		var all_gaps: Array[float] = []
		var all_y: Array[float] = []
		var contact := true
		for region in ["heel","forefoot"]:
			var points: Array[Vector3] = []
			var center := Vector3.ZERO
			for vertex in sole_selection[side].vertices:
				if vertex.region!=region: continue
				var point: Vector3 = player.skeleton.to_global(_skin_vertex(surfaces[vertex.surface],int(vertex.vertex),matrices))
				points.append(point)
				center+=point
			if points.is_empty():
				contact=false
				continue
			center/=float(points.size())
			var region_ground := _ground(center)
			var gaps: Array[float] = []
			var heights: Array[float] = []
			for point in points:
				heights.append(point.y)
				all_y.append(point.y)
				if region_ground.hit:
					gaps.append(point.y-float(region_ground.y))
					all_gaps.append(point.y-float(region_ground.y))
			var gap_stats := _range(gaps)
			contact=contact and bool(region_ground.get("flat",false)) and not gap_stats.is_empty()
			if not gap_stats.is_empty(): contact=contact and float(gap_stats.min)>=-.01 and float(gap_stats.max)<=.01
			value.regions[region]={"center":_v(center),"ground":region_ground,"y_m":_range(heights),"gap_m":gap_stats}
		value.base_y_m=_range(all_y)
		value.gap_m=_range(all_gaps)
		value.contact_ok=contact
		result[side] = value
	return result

func _aim_detail() -> void:
	var origin: Vector3 = player.global_position
	var side: Vector3 = player.visual.global_basis.x.normalized()
	var front: Vector3 = -player.visual.global_basis.z.normalized()
	detail.global_position = origin+side*3.6+front*.65+Vector3.UP*.92
	detail.look_at(origin+Vector3.UP*.82)

func _capture(name: String) -> void:
	phase = name
	_aim_detail()
	await RenderingServer.frame_post_draw
	var begin := Time.get_ticks_usec()
	var image := root.get_texture().get_image()
	var error := image.save_png(folder.path_join(name+".png"))
	var soles := _soles()
	var row := {"name":name,"utc":Time.get_datetime_string_from_system(true),"usec":begin,"actor":_v(player.global_position),"visual_local":_v(player.visual.position),"on_floor":player.is_on_floor(),"actor_ground":_ground(player.global_position),"soles":soles,"camera_position":_v(detail.global_position),"camera_size":detail.size,"capture_and_skin_usec":Time.get_ticks_usec()-begin}
	capture_rows.append(row)
	_check(error==OK,name+" PNG saved")
	_check(player.is_on_floor(),name+" body supported")
	for side in soles:
		var item: Dictionary = soles[side]
		_check(bool(item.get("contact_ok",false)),"%s %s flat sole gap within [-.01,+.01] m: %s" % [name,side,str(item.get("gap_m","no floor/foot"))])
	_save("grounding-progress",{"captures":capture_rows,"failures":failures})

func _timing_summary() -> Dictionary:
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in frame_ms:
		total += value
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	if sorted.is_empty(): return {"valid":false}
	return {"valid":total>=30000.0,"frames":frame_ms.size(),"seconds":total/1000.0,"fps":frame_ms.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted.back(),"over33":over33,"over66":over66,"samples_ms":frame_ms,"capture_during_measurement":false,"scope":"Normal settings, main gameplay camera, lightweight bone/body observer; population/city remain live. Not universal performance approval."}

func _move_and_stop(action: String, sprinting: bool, name: String) -> void:
	phase = name+"-moving"
	var start: Vector3 = player.global_position
	Input.action_press(action)
	if sprinting: Input.action_press("sprint")
	await _wait(.65)
	_release()
	var distance: float = Vector2(player.global_position.x-start.x,player.global_position.z-start.z).length()
	_check(distance>(.65 if sprinting else .4),name+" moved with real Input: %.4f m" % distance)
	phase = name+"-settling"
	await _wait(1.0)
	_check(player._locomotion_weight<=.01,name+" returned to idle")
	await _capture(name+"-stopped")
	await _wait(1.0)
	await _capture(name+"-stopped-plus1s")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-save" not in args or "--skip-arrival" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Requires rendered Godot .NET, --no-save --skip-arrival and native C# enabled")
		quit(2); return
	for argument in args:
		if argument.begins_with("--label="): label=argument.trim_prefix("--label=").validate_filename()
	if label.is_empty(): quit(2); return
	folder=OUT+label
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		push_error("Refusing to overwrite "+folder); quit(2); return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))!=OK: quit(2); return
	create_timer(180.0).timeout.connect(func():
		if not finished:
			_check(false,"180 s total watchdog")
			_finish(3))
	# Mantém o caminho real das ações de Input enquanto impede a entrada física do usuário
	# de dirigir este processo de diagnóstico isolado.
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	seed(11102026)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	while not finished:
		await process_frame
		if world.session!=null and world.session.ready_for_play and world.production.ready_for_play and not root.has_node("LoadingCurtain") and not world.has_node("LoadingCurtain"): break
	if finished: return
	if not world.production.no_save:
		_check(false,"Main no_save active"); _finish(2); return
	var router := ROUTER.new()
	router.configure(world.production.traffic_routes)
	var native: RefCounted = router._native_graph()
	_check(native!=null,"native C# route implementation loaded")
	if native==null: _finish(2); return
	player=world.player
	world.production.set_population(24)
	world.session.weather.time_of_day=.36
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	if not _prepare_skin():
		_check(false,"weighted foot vertices available"); _finish(2); return
	report={"engine":Engine.get_version_info(),"native_script":native.get_script().resource_path,"actor_sha256":FileAccess.get_sha256("res://scripts/Actor.gd"),"harness_sha256":FileAccess.get_sha256("res://tests/capture/capture_dante_idle_grounding.gd"),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[root.size.x,root.size.y],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"population_requested":24,"population_effective":world.population,"start_position":_v(player.global_position),"no_save":world.production.no_save,"sole_tolerance_m":.01,"rest_sole_band_m":.006,"limits":["The ankle bone and lowest toe do not establish sole contact. Fixed vertices selected in the imported rest-pose bottom 6 mm are split by ankle-to-toe axis into heel/forefoot; each region reports min/p50/p95/max height and physical-floor gap. All selected vertices must stay within the fixed [-10,+10] mm envelope on a flat floor.","Raycast validates physical floor; visual pavement and shadow contact require PNG review.","No geometry deformation or image readback occurs in the 30 s timing window.","City population remains active and can vary. PNG readback timing is not gameplay performance."]}
	await _wait(10.0)
	phase="timing"
	observation_began=Time.get_ticks_usec()
	last_usec=0
	collecting=true
	process_frame.connect(_frame)
	await _wait(30.1)
	collecting=false
	var timing := _timing_summary()
	timing.configuration=report.duplicate()
	_save("normal-settings",timing)
	report.timing_file="normal-settings.json"
	detail=Camera3D.new()
	detail.name="IdleGroundingDetailCamera"
	detail.projection=Camera3D.PROJECTION_ORTHOGONAL
	detail.size=2.35
	detail.near=.03
	detail.far=120.0
	world.add_child(detail)
	_aim_detail()
	detail.make_current()
	phase="idle"
	collecting=true
	last_usec=0
	await _capture("idle-0s")
	await _wait(1.0)
	await _capture("idle-1s")
	await _wait(1.0)
	await _capture("idle-2s")
	await _move_and_stop("move_right",false,"walk")
	await _move_and_stop("move_left",true,"run")
	collecting=false
	_finish(0 if failures.is_empty() else 1)
