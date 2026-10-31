extends "res://tests/test_vertice_depth.gd"
## Sala nativa desert_digo renderizada, rigs reais de jogador/NPC e máscaras pareadas.
## Isto é evidência de profundidade, nunca substituto de amostras de ciclo de vida do Main ou de FPS.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ROOM_OFFSET := Vector3(0,18,15)
var destination := "res://artifacts/digo-workshop-refresh-20261019/depth-props-control"
var _started := 0
var _completed := false
var _room: Node3D
var _camera: Camera3D

func check(ok: bool, label: String) -> void:
	checks += 1
	print("DIGO_ROOM_DEPTH ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Digo workshop depth requires the real rendered viewport; headless is not evidence")
		quit(2)
		return
	_started = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): destination = argument.trim_prefix("--out-dir=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination)) != OK:
		push_error("Cannot create Digo room depth evidence folder")
		quit(2)
		return
	create_timer(180).timeout.connect(_timeout)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.msaa_3d = root.msaa_3d
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("9da9ad")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d9dce0")
	settings.ambient_light_energy = .55
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-25,0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = .8
	stage.add_child(sun)
	_room = PLACES.create_place("desert_digo")
	if _room == null:
		check(false,"PlaceCatalog creates the actual desert_digo interior")
		stage.free()
		viewport.free()
		quit(1)
		return
	stage.add_child(_room)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _room.camera_size
	_camera.near = .05
	_camera.far = 100.0
	stage.add_child(_camera)
	_camera.global_position = _room.camera_target+ROOM_OFFSET
	_camera.look_at(_room.camera_target)
	_camera.make_current()
	for frame in 3: await physics_frame
	check(_room.model.get_node_or_null("DigoFurnitureDetails") != null,"Actual native room contains the refined furniture batch")
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var probes := [
		{"id":"bench-front","point":Vector3(-9.7,.04,-4.25),"partial":false},
		{"id":"bench-side","point":Vector3(-7.15,.04,-5.4),"partial":false},
		{"id":"bench-behind","point":Vector3(-9.7,.04,-6.52),"partial":true},
		{"id":"desk-front","point":Vector3(7.65,.04,1.25),"partial":false},
		{"id":"desk-side","point":Vector3(6.3,.04,.05),"partial":false},
		{"id":"desk-behind","point":Vector3(7.65,.04,-1.25),"partial":true},
		{"id":"shelf-front","point":Vector3(5,.04,-6.9),"partial":false},
		{"id":"shelf-side","point":Vector3(3.65,.04,-7.65),"partial":false},
		# O vão central de .44m atrás desta prateleira não comporta a cápsula de .60m.
		# Usa a borda traseira acessível; nunca põe um ator dentro de um sólido reservado.
		{"id":"shelf-behind-edge","point":Vector3(3.785,.04,-8.42),"partial":false},
	]
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.position = probes[0].point
		actor.rotation.y = PI
		for frame in 20: await process_frame
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var who := "player" if player else "npc"
		# Materiais reais antes da sobrescrita de diagnóstico, usando a câmera da sala
		# inalterada. Estas fotos são explicitamente uma fixture de sala nativa isolada.
		for setup in probes:
			if not str(setup.id).ends_with("front"): continue
			actor.position = setup.point
			actor.reset_physics_interpolation()
			var natural := await capture()
			var filename := who+"-"+str(setup.id)+"-natural.png"
			check(natural.save_png(destination.path_join(filename)) == OK,filename+" saved")
		mask_meshes(actor.visual,diagnostic)
		for setup in probes:
			actor.position = setup.point
			actor.reset_physics_interpolation()
			var id := who+"-"+str(setup.id)
			await physics_frame
			var clear := not actor.test_move(actor.global_transform,Vector3.UP*.002,null,.001,true)
			check(clear,id+" complete capsule lies outside all furniture and walls")
			var floor_query := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.18,actor.global_position-Vector3.UP*.4,1,[actor.get_rid()])
			var floor_hit := stage.get_world_3d().direct_space_state.intersect_ray(floor_query)
			var supported: bool = not floor_hit.is_empty() and absf(float(floor_hit.position.y)+.02)<.025 and floor_hit.normal.y>.8
			check(supported,id+" support ray reaches the authored native floor")
			await _depth_pair(actor,id,bool(setup.partial),clear,supported)
		actor.free()
		await physics_frame
	_completed = true
	_write_report(false)
	print("DIGO_WORKSHOP_DEPTH checks=",checks," failures=",failures," output=",destination)
	stage.free()
	viewport.free()
	for frame in 3: await process_frame
	quit(0 if failures.is_empty() else 1)

func _depth_pair(actor: CharacterBody3D, id: String, partial: bool, clear: bool, supported: bool) -> void:
	var body_area := _projected_area(actor.global_position,AABB(Vector3(-.68,-.04,-.45),Vector3(1.36,2.12,.90)))
	var furniture := _room.model.get_node("DigoFurnitureDetails") as MeshInstance3D
	var actual := await capture()
	# Isola a profundidade da mobília sem remover telhado, paredes, luzes nem piso.
	# A mesma oclusão intencional da treliça existe portanto nas duas imagens.
	furniture.hide()
	var control := await capture()
	furniture.show()
	var head := _head_region(actor,control,body_area)
	var head_area: Rect2i = head.area
	# Só diagnóstico separado: mantém toda a mobília e remove apenas as duas treliças
	# do telhado para quantificar a contribuição delas. Isto nunca muda o produto.
	var trusses: Array[Node] = _room.model.find_children("RoofTruss*","MeshInstance3D",true,false)
	for truss: MeshInstance3D in trusses: truss.hide()
	var truss_diagnostic := await capture()
	for truss: MeshInstance3D in trusses: truss.show()
	var visible := _count_area(actual,body_area)
	var unobstructed := _count_area(control,body_area)
	var head_visible := _count_area(actual,head_area)
	var head_control := _count_area(control,head_area)
	var ratio := float(visible)/maxf(1.0,float(unobstructed))
	var head_ratio := float(head_visible)/maxf(1.0,float(head_control))
	check(actual.save_png(destination.path_join(id+".png")) == OK,id+" actual depth image saved")
	check(control.save_png(destination.path_join(id+"-props-control.png")) == OK,id+" furniture-only positive control saved with roof unchanged")
	check(truss_diagnostic.save_png(destination.path_join(id+"-truss-diagnostic.png")) == OK,id+" separate roof contribution diagnostic saved")
	check(unobstructed>150,id+" positive control contains the actual rig")
	if partial:
		check(ratio>.05 and ratio<.97,id+" real furniture occludes part of the body ratio="+str(ratio))
	else:
		check(ratio>.90,id+" front/side preserves the visible actor ratio="+str(ratio))
	check(head_control>20,id+" head has positive control pixels")
	check(head_ratio>.70,id+" head remains readable ratio="+str(head_ratio))
	records.append({"id":id,"position":str(actor.position),"expected":"partial" if partial else "clear","capsule_clear":clear,"floor_supported":supported,"visible_pixels":visible,"prop_control_pixels":unobstructed,"visible_ratio":ratio,"head_visible_pixels":head_visible,"head_control_pixels":head_control,"head_ratio":head_ratio,"head_source":head.source,"head_world_point":head.get("point","control-mask upper silhouette"),"body_roi":str(body_area),"head_roi":str(head_area),"truss_diagnostic_pixels":_count_area(truss_diagnostic,body_area),"truss_hidden_delta_pixels":_count_area(truss_diagnostic,body_area)-visible})

func _head_region(actor: CharacterBody3D, control: Image, body_area: Rect2i) -> Dictionary:
	var visual: Node3D = actor.get("visual")
	var skeletons := visual.find_children("*","Skeleton3D",true,false)
	for candidate in skeletons:
		var skeleton := candidate as Skeleton3D
		var bone := skeleton.find_bone("Head")
		if bone < 0:
			for index in skeleton.get_bone_count():
				if str(skeleton.get_bone_name(index)).to_lower().ends_with("head"): bone = index; break
		if bone < 0: continue
		var point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)+Vector3.UP*.10
		return _head_rect(point,"Skeleton3D:"+str(skeleton.get_bone_name(bone)))
	var head_node := visual.find_child("Head",true,false) as Node3D
	if head_node != null: return _head_rect(head_node.global_position+Vector3.UP*.10,"authored Head joint")
	# Corpos civis importados podem não ter uma junta semântica de cabeça. A silhueta
	# superior de um ator estático neutro passa a ser a região independente de controle positivo;
	# mantém só os 22% de cima, em vez da ROI antiga que incluía os ombros.
	var bounds := Rect2i()
	var found := false
	for y in range(body_area.position.y,body_area.end.y):
		for x in range(body_area.position.x,body_area.end.x):
			var color := control.get_pixel(x,y)
			if color.r>.55 and color.b>.55 and color.g<.2:
				if not found: bounds = Rect2i(Vector2i(x,y),Vector2i.ONE); found = true
				else: bounds = bounds.expand(Vector2i(x,y))
	if not found: return {"area":Rect2i(),"source":"missing control silhouette"}
	bounds.size.y = maxi(1,ceili(float(bounds.size.y)*.22))
	return {"area":bounds.grow(1).intersection(Rect2i(Vector2i.ZERO,viewport.size)),"source":"upper 22% of neutral control silhouette"}

func _head_rect(point: Vector3, source: String) -> Dictionary:
	var center := _camera.unproject_position(point)
	var extent: float = float(viewport.size.y)/_camera.size*.15
	var area := Rect2i(Vector2i((center-Vector2.ONE*extent).floor()),Vector2i.ONE*ceili(extent*2.0))
	return {"area":area.intersection(Rect2i(Vector2i.ZERO,viewport.size)),"source":source,"point":str(point)}

func _projected_area(origin: Vector3, bounds: AABB) -> Rect2i:
	var points: Array[Vector2] = []
	for x in [bounds.position.x,bounds.end.x]:
		for y in [bounds.position.y,bounds.end.y]:
			for z in [bounds.position.z,bounds.end.z]:
				points.append(_camera.unproject_position(origin+Vector3(x,y,z)))
	var area := Rect2(points[0],Vector2.ZERO)
	for point in points: area = area.expand(point)
	area = area.grow(4.0)
	return Rect2i(Vector2i(area.position.floor()),Vector2i(area.size.ceil())).intersection(Rect2i(Vector2i.ZERO,viewport.size))

func _count_area(image: Image, area: Rect2i) -> int:
	var count := 0
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var color := image.get_pixel(x,y)
			if color.r>.55 and color.b>.55 and color.g<.2: count += 1
	return count

func _timeout() -> void:
	if _completed: return
	failures.append("180s finite capture deadline exceeded")
	_write_report(true)
	quit(3)

func _write_report(timed_out: bool) -> void:
	var file := FileAccess.open(destination.path_join("results.json"),FileAccess.WRITE)
	if file == null: push_error("Digo workshop depth report unavailable"); return
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"timed_out":timed_out,"seconds":float(Time.get_ticks_msec()-_started)/1000.0,"place":"desert_digo","creation":"PlaceCatalog.create_place","engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":[1280,720],"msaa":viewport.msaa_3d,"camera_offset":str(ROOM_OFFSET),"camera_size":_camera.size,"camera_transform":str(_camera.global_transform),"records":records,"control_kind":"Only DigoFurnitureDetails is hidden; roof, walls, lights, floor, camera and actor pose remain unchanged.","not_applicable":[{"probe":"shelf-behind-central","reason":"Rear gap .44m is smaller than the real .60m capsule diameter; no legal central behind pose exists."}],"limitations":["Native interior fixture; actual Main lifecycle and performance require separate evidence.","Natural photos use the fixture ambient/sun and the room's real local lights, not Main weather.","The shelf rear-edge probe is physically accessible and expected clear; it does not certify occlusion behind the inaccessible rack centre.","Roof trusses intentionally occlude portions of the body. Separate diagnostic images quantify that contribution without hiding structure in production.","Static full-body clearance and support are checked at probes; this does not replace swept navigation tests."]},"\t"))
