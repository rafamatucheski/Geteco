extends SceneTree
## Captura localizada no Main real, sem save pessoal. Não comprova passagem física.
## Pela fila Godot .NET, após compilar Harbor.csproj:
## --script res://tests/capture/capture_unified_bridge.gd -- --no-save [--completed] [--night] [--rain] [--temporal] [--temporal-only] [--temporal-jpeg]
## --temporal cruza tronco/curva, encontros leste e braço norte em três sequências
## de 30 s por interpolação visual. Readback/PNG afeta cadência; não comprova física/FPS.
## --temporal-only implica --temporal e pula fotos estaticas, panoramas e inventario.
## --temporal-jpeg implica --temporal e usa JPEG 0.95 so nas sequencias; fotos estaticas seguem PNG.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const KIT := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const NORTH_LAYOUT := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const CAPTURE_STATE := preload("res://runtime/GameState.gd")
const DESERT_STORY := preload("res://runtime/desert/DesertStoryState.gd")
const ARRAY_CACHE := preload("res://world/chunk_bake/MeshArrayCache.gd")
var world
var folder := ""
var samples: Array = []
var sequences: Array[Dictionary] = []
var temporal := false
var temporal_only := false
var temporal_jpeg := false
var viewport_configuration: Dictionary = {}
var completed := false
var night := false
var rain := false
var checkpoint_flags: Dictionary = {}

func _initialize() -> void:
	# Limite independente para não manter a fila presa em erro de carregamento.
	create_timer(600,true,false,true).timeout.connect(func():
		push_error("Captura excedeu 600 s")
		quit(3))
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args:
		push_error("Captura exige --no-save e usa checkpoint isolado em evidence")
		quit(2)
		return
	temporal_only = "--temporal-only" in args
	temporal_jpeg = "--temporal-jpeg" in args
	temporal = "--temporal" in args or temporal_only or temporal_jpeg
	completed = "--completed" in args
	night = "--night" in args
	rain = "--rain" in args
	folder = FIXTURE.output_dir("unified-bridge-capture")
	# A captura seleciona um checkpoint posterior às conversas, sem esconder HUD
	# nem alterar o fluxo produtivo que apresenta epílogo e primeira chegada.
	var capture_state := CAPTURE_STATE.new()
	var restore_result: bool = capture_state.restore_snapshot(FIXTURE.full_snapshot(Vector3(364.55,.12,-254),completed))
	if not restore_result:
		push_error("Checkpoint inicial da captura inválido")
		quit(2)
		return
	if completed and not capture_state.campaign.complete_aftermath_call():
		push_error("Checkpoint concluído não admitiu o término do epílogo")
		quit(2)
		return
	if not DESERT_STORY.mark(capture_state.world_state,"arrived"):
		push_error("Checkpoint não admitiu primeira chegada ao deserto")
		quit(2)
		return
	var capture_snapshot: Dictionary = capture_state.snapshot()
	if not CAPTURE_STATE.new().restore_snapshot(capture_snapshot):
		push_error("Checkpoint pós-diálogos da captura inválido")
		quit(2)
		return
	checkpoint_flags = {"restore_validated":restore_result,
		"aftermath_call_complete":capture_snapshot.campaign.get("aftermath",{}).get("call_complete",false),
		"desert_arrived":DESERT_STORY.data(capture_state.world_state).arrived,
		"fixture_stage":"Após epílogo quando campanha concluída e após primeira chegada ao deserto; conversas não exercitadas nesta captura"}
	var checkpoint := FIXTURE.write_fixture(folder,"checkpoint.json",capture_snapshot)
	if checkpoint.is_empty(): quit(2); return
	print("UNIFIED_BRIDGE_CAPTURE_START ",ProjectSettings.globalize_path(folder))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",checkpoint)
	root.add_child(world)
	var ready_deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<ready_deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play and world.production.ready_for_play: break
	if world.session==null or not world.session.ready_for_play or not world.production.ready_for_play:
		push_error("Main não ficou jogável")
		quit(2)
		return
	if not world.production.no_save or world.production.store.path!=checkpoint:
		push_error("Captura interrompida: isolamento do checkpoint não confirmado")
		quit(2)
		return
	if temporal and not await configure_temporal_viewport(): quit(2); return
	# O roteador produtivo cria o espelho nativo na primeira consulta; o JIT de
	# startup usa uma instância descartável. Exercitar a rota antes de conferir.
	var native_route: Dictionary = world.dispatch.router.plan(Vector3(382.5,0,-200),Vector3(440,0,-281.3),Vector3.FORWARD)
	if not native_route.get("ok",false) or world.dispatch.router._native==null:
		push_error("Captura exige o caminho C# compilado, sem fallback")
		quit(2)
		return
	world.player.controlled_automatically = true
	var weather = world.session.weather
	# Estado climático fixado; continuam ativos tráfego, streaming e atualização
	# produtiva de atmosfera. As fixtures apenas selecionam o estado da campanha.
	weather.time_of_day = 22.0/24.0 if night else .5
	weather.weather_state = 2 if rain else 0
	weather.weather_timer = 1.0e9
	weather.weather_locked = true
	weather.time_scale = 0.0
	if rain:
		weather.rain_intensity = 1.0
		weather.rain_level = 1.0
		weather.coastal_wetness = 1.0
	# A troca forçada já fixa a densidade da chuva. Fixar também a nuvem da
	# fixture evita confundir a chegada temporal da frente com uma emenda espacial.
	weather._sync_external_state()
	weather._visual_clouds = weather._harbor_overcast()
	var shots := {
		"inicio_tronco":Vector3(382.5,.12,-140),
		"tronco":Vector3(382.5,.12,-210),
		"curva":Vector3(385,.12,-281),
		"entrada":Vector3(364.55,.12,-254),
		"conector":Vector3(440,.12,-285),
		"vao_leste":Vector3(508,.12,-285),
		"entrada_tunel":Vector3(575,.12,-285),
		"interior_tunel":Vector3(605,.12,-285),
		"saida_tunel":Vector3(635,.12,-285),
		"norte_obra":Vector3(342.5,2.55,-277),
	}
	if completed:
		shots["norte_cabeceira"] = Vector3(342.5,2.55,-368)
		shots["encontro_deserto"] = Vector3(342.5,2.55,-380)
	if temporal_only: shots.clear()
	for id in shots:
		world.player.teleport(shots[id])
		world.production.region.set_focus(shots[id],true)
		var stream_deadline := Time.get_ticks_msec()+45000
		while Time.get_ticks_msec()<stream_deadline:
			await process_frame
			if world.production.region.is_streaming_idle(): break
		if not world.production.region.is_streaming_idle():
			push_error("Streaming não terminou: %s"%id)
			quit(2)
			return
		for frame in 90: await process_frame
		await RenderingServer.frame_post_draw
		if not capture_frame(str(id),0,0,0.0): quit(2); return
		print("UNIFIED_BRIDGE_CAPTURE_SHOT ",id," frames=1")
	if temporal and not await capture_temporal_routes():
		quit(2)
		return
	var panorama_path := ""
	var trunk_panorama_path := ""
	var trunk_near1_path := ""
	var panorama_camera_ab: Dictionary = {}
	var surface_inventory: Dictionary = {"skipped":true,"reason":"--temporal-only"}
	if not temporal_only:
		# Vista livre adicional: documenta o conjunto; câmera de gameplay já capturada.
		world.player.teleport(Vector3(490,.12,-285))
		world.production.region.set_focus(Vector3(490,0,-285),true)
		for frame in 180: await process_frame
		var panorama := Camera3D.new()
		panorama.near = .05
		panorama.far = 700.0
		panorama.fov = 65.0
		world.add_child(panorama)
		panorama.global_position = Vector3(490,165,-425)
		panorama.look_at(Vector3(490,0,-245))
		panorama.make_current()
		for frame in 30: await process_frame
		panorama_path = folder.path_join("panorama.png")
		if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(panorama_path))!=OK:
			quit(2)
			return
		# Segundo ângulo mantém o tronco e a bifurcação legíveis sem depender do
		# streaming distante da montanha na visão geral anterior.
		world.player.teleport(Vector3(377,.12,-230))
		world.production.region.set_focus(Vector3(377,0,-230),true)
		for frame in 180: await process_frame
		panorama.global_position = Vector3(300,125,-160)
		panorama.look_at(Vector3(395,0,-245))
		for frame in 30: await process_frame
		await RenderingServer.frame_post_draw
		trunk_panorama_path = folder.path_join("panorama_tronco_bifurcacao.png")
		if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(trunk_panorama_path))!=OK:
			quit(2)
			return
		var near_original_frame := Engine.get_frames_drawn()
		# A/B apenas desta camera diagnostica: mesmo foco/transform e mesmo mundo.
		# A camera produtiva e seus planos de corte permanecem intactos.
		panorama.near = 1.0
		for frame in 30: await process_frame
		await RenderingServer.frame_post_draw
		trunk_near1_path = folder.path_join("panorama_tronco_near1.png")
		if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(trunk_near1_path))!=OK:
			quit(2)
			return
		var near1_frame := Engine.get_frames_drawn()
		surface_inventory = inventory_trunk_surfaces(panorama)
		panorama_camera_ab = {"position":[300,125,-160],"look_at":[395,0,-245],"far":700.0,"fov":65.0,
			"variants":[{"near":.05,"path":trunk_panorama_path,"rendered_frame":near_original_frame},{"near":1.0,"path":trunk_near1_path,"rendered_frame":near1_frame}]}
	var report := {"completed":completed,"night":night,"rain":rain,"temporal":temporal,
		"temporal_image_format":"jpeg" if temporal_jpeg else "png","temporal_jpeg_quality":0.95 if temporal_jpeg else null,
		"checkpoint_flags":checkpoint_flags,
		"temporal_only":temporal_only,"static_captures_skipped":temporal_only,"panoramas_skipped":temporal_only,
		"viewport_configuration":viewport_configuration,
		"panorama":panorama_path,
		"panorama_tronco_bifurcacao":trunk_panorama_path,
		"panorama_tronco_near1":trunk_near1_path,
		"panorama_tronco_camera_ab":panorama_camera_ab,
		"main_trunk_surface_inventory":surface_inventory,
		"scope":"Capturas localizadas e travessias por interpolação visual da fixture; não comprovam passagem física nem FPS. Readback/PNG afeta cadência. Player físico suspenso apenas nas sequências; câmera, streaming, clima e demais sistemas produtivos ativos.",
		"sequences":sequences,
		"native_dispatch_router":world.dispatch.router._native!=null,
		"engine":Engine.get_version_info(),"viewport":str(root.size),"samples":samples}
	var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("UNIFIED_BRIDGE_CAPTURE ",ProjectSettings.globalize_path(folder)," frames=",samples.size())
	quit(0)

func configure_temporal_viewport() -> bool:
	# Settings aplica a janela salva na inicializacao. Esperar a admissao final
	# e alguns frames antes do override mantem a preferencia pessoal no disco.
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		if world.production.ready_for_play and world.session.ready_for_play and not world.player.input_locked and world.get_node_or_null("LoadingCurtain")==null and root.get_node_or_null("LoadingCurtain")==null: break
		await process_frame
	if not world.production.ready_for_play or not world.session.ready_for_play or world.player.input_locked or world.get_node_or_null("LoadingCurtain")!=null or root.get_node_or_null("LoadingCurtain")!=null:
		push_error("Admissao final nao terminou antes de fixar janela temporal")
		return false
	for frame in 30: await process_frame
	var before_size := root.size
	var before_mode := root.mode
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	for frame in 60: await process_frame
	await RenderingServer.frame_post_draw
	var texture_size := Vector2i(root.get_texture().get_size())
	var matches: bool = root.mode==Window.MODE_WINDOWED and root.size==Vector2i(1280,720) and texture_size==Vector2i(1280,720)
	viewport_configuration = {"temporal_override":true,"saved_settings_written":false,
		"requested_window_size":[1280,720],"before_window_size":[before_size.x,before_size.y],"before_mode":before_mode,
		"effective_window_size":[root.size.x,root.size.y],"effective_texture_size":[texture_size.x,texture_size.y],
		"effective_mode":root.mode,"render_scale":root.scaling_3d_scale,"msaa_3d":root.msaa_3d,"verified":matches}
	print("UNIFIED_BRIDGE_CAPTURE_VIEWPORT ",JSON.stringify(viewport_configuration))
	if not matches: push_error("Janela/framebuffer temporal nao fixou 1280x720 em modo janela")
	return matches

func capture_frame(id: String, index: int, started_at: int, progress: float, requested_position: Vector3 = Vector3.INF) -> bool:
	var captured_at := Time.get_ticks_usec()
	var jpeg_frame: bool = temporal_jpeg and started_at>0
	var path := folder.path_join("%s_%06d.%s"%[id,index,"jpg" if jpeg_frame else "png"])
	var readback_started := Time.get_ticks_usec()
	var picture := root.get_texture().get_image()
	var readback_usec := Time.get_ticks_usec()-readback_started
	if temporal and picture.get_size()!=Vector2i(1280,720):
		push_error("Frame temporal fora de 1280x720: %s"%picture.get_size())
		return false
	var save_started := Time.get_ticks_usec()
	var save_result := picture.save_jpg(ProjectSettings.globalize_path(path),0.95) if jpeg_frame else picture.save_png(ProjectSettings.globalize_path(path))
	var save_usec := Time.get_ticks_usec()-save_started
	if save_result!=OK:
		push_error("Erro gravando frame: %s"%path)
		return false
	var point: Vector3 = world.player.global_position
	var camera_point: Vector3 = world.camera.global_position
	var env: Environment = world.production.environment.environment
	var weather = world.session.weather
	var bridge_lights: Array[Dictionary] = []
	var connection = world.production.connection
	if is_instance_valid(connection):
		for lamp: OmniLight3D in connection.bridge_lamps:
			if not is_instance_valid(lamp):
				bridge_lights.append({"valid":false})
				continue
			var lamp_point := lamp.global_position
			bridge_lights.append({"valid":true,"energy":lamp.light_energy,"visible":lamp.visible,
				"is_visible_in_tree":lamp.is_visible_in_tree(),"omni_range":lamp.omni_range,
				"global_position":[lamp_point.x,lamp_point.y,lamp_point.z],"actor_distance":lamp_point.distance_to(point)})
	samples.append({"shot":id,"frame":index,"timestamp_usec":captured_at,
		"image_format":"jpeg" if jpeg_frame else "png","jpeg_quality":0.95 if jpeg_frame else null,
		"get_image_usec":readback_usec,"image_save_usec":save_usec,"image_acquisition_usec":readback_usec+save_usec,
		"bridge_lights":bridge_lights,
		"rendered_frame":Engine.get_frames_drawn(),
		"image_size":[picture.get_width(),picture.get_height()],
		"elapsed_seconds":0.0 if started_at==0 else float(captured_at-started_at)/1000000.0,
		"route_progress":progress,"path":path,"position":[point.x,point.y,point.z],
		"requested_position":[] if not requested_position.is_finite() else [requested_position.x,requested_position.y,requested_position.z],
		"camera_position":[camera_point.x,camera_point.y,camera_point.z],
		"mountain_weight":ATMOSPHERE.weights_at(point).mountain,
		"desert_weight":ATMOSPHERE.desert_weight(point),
		"sun_energy":world.production.sun.light_energy,"ambient_energy":env.ambient_light_energy,
		"rain_visible":weather.precipitation.visible,"snow_visible":weather.snow.visible,
		"cold_visible":world.session.cold.status().visible})
	return true

func capture_temporal_routes() -> bool:
	var trunk := PackedVector3Array()
	for section in KIT.east_sections():
		var point: Vector3 = section.point
		if point.x>=440.0: break
		trunk.append(point+Vector3.UP*.12)
	trunk.append(Vector3(440,.12,-285))
	if not await capture_motion("temporal_tronco_curva",trunk): return false
	var east := PackedVector3Array([Vector3(440,.12,-285),Vector3(635,.12,-285)])
	if not await capture_motion("temporal_encontros_leste",east): return false
	var north := PackedVector3Array()
	if completed:
		for z in range(-280,-382,-2):
			var height: float = 2.4 if z>=NORTH_LAYOUT.END_Z else DESERT.surface_height(Vector2(342.5,z))
			north.append(Vector3(342.5,height+.12,z))
	else:
		# A fixture jamais ultrapassa a barreira fechada nem mostra o vão como livre.
		for point: Vector3 in NORTH_LAYOUT.centerline():
			if point.z<NORTH_LAYOUT.WORK_POSITION.z+1.5: break
			north.append(point+Vector3.UP*.12)
		north.append(NORTH_LAYOUT.WORK_POSITION+Vector3(0,.12,1.5))
	return await capture_motion("temporal_norte_concluido" if completed else "temporal_aproximacao_obra",north)

func capture_motion(id: String, path: PackedVector3Array) -> bool:
	var distances := PackedFloat32Array([0.0])
	for i in range(1,path.size()): distances.append(distances[-1]+path[i-1].distance_to(path[i]))
	if path.size()<2 or distances[-1]<=0.0:
		push_error("Trajeto visual vazio: "+id)
		return false
	var physics_before: bool = world.player.is_physics_processing()
	var interpolation_before: int = world.player.physics_interpolation_mode
	world.player.set_physics_process(false)
	# A câmera produtiva consulta get_global_transform_interpolated: sem física,
	# deixar essa interpolação ligada usaria a pose antiga em vez da trajetória.
	world.player.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.player.teleport(path[0])
	world.production.region.set_focus(path[0],true)
	var stream_deadline := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<stream_deadline:
		await process_frame
		if world.production.region.is_streaming_idle(): break
	if not world.production.region.is_streaming_idle():
		restore_capture_actor(physics_before,interpolation_before)
		push_error("Streaming não terminou antes da sequência: "+id)
		return false
	for frame in 90: await process_frame
	var began := Time.get_ticks_usec()
	var index := 0
	var last_rendered := -1
	var omitted := 0
	var segment := 1
	var duration := 30.0
	while true:
		await process_frame
		var elapsed: float = 0.0 if index==0 else float(Time.get_ticks_usec()-began)/1000000.0
		var progress := clampf(elapsed/duration,0.0,1.0)
		var distance: float = distances[-1]*progress
		while segment<path.size()-1 and distances[segment]<distance: segment+=1
		var length: float = distances[segment]-distances[segment-1]
		var weight: float = 0.0 if length<=.000001 else (distance-distances[segment-1])/length
		var point: Vector3 = path[segment-1].lerp(path[segment],weight)
		# Deslocamento explícito da fixture; nenhuma entrada de condução é simulada.
		world.player.global_position=point
		world.player.velocity=Vector3.ZERO
		world.production.region.set_focus(point)
		await RenderingServer.frame_post_draw
		var rendered: int = Engine.get_frames_drawn()
		if last_rendered>=0: omitted+=maxi(0,rendered-last_rendered-1)
		last_rendered=rendered
		if not capture_frame(id,index,began,progress,point):
			restore_capture_actor(physics_before,interpolation_before)
			return false
		index+=1
		if progress>=1.0: break
	restore_capture_actor(physics_before,interpolation_before)
	sequences.append({"id":id,"requested_seconds":duration,
		"elapsed_seconds":float(Time.get_ticks_usec()-began)/1000000.0,
		"frames":index,"omitted_rendered_frames":omitted,"distance_meters":distances[-1],
		"start":[path[0].x,path[0].y,path[0].z],"end":[path[-1].x,path[-1].y,path[-1].z],
		"interpolated_fixture":true,"physical_passage_verified":false})
	print("UNIFIED_BRIDGE_CAPTURE_SEQUENCE ",JSON.stringify(sequences[-1]))
	return true

func restore_capture_actor(physics_before: bool, interpolation_before: int) -> void:
	world.player.physics_interpolation_mode=interpolation_before
	world.player.reset_physics_interpolation()
	world.player.set_physics_process(physics_before)

## Nunca chamar arrays_of aqui: cache miss desse helper faz readback da GPU.
## Uma superficie ausente do cache e pendencia explicita, nao ausencia de piso.
func cached_inventory_arrays(mesh: Mesh, surface: int) -> Array:
	if mesh is PrimitiveMesh:
		var known: Variant = ARRAY_CACHE._primitive_keys.get(mesh.get_instance_id())
		if known != null and known.ref.get_ref()==mesh:
			var arrays: Variant = ARRAY_CACHE._primitives.get(known.key)
			if arrays is Array: return arrays
		return []
	var key := "%d:%d" % [mesh.get_instance_id(),surface]
	var entry: Variant = ARRAY_CACHE._meshes.get(key)
	if entry==null or entry.ref.get_ref()!=mesh: return []
	if mesh is ArrayMesh:
		if int(entry.length)!=mesh.surface_get_array_len(surface) or int(entry.index_length)!=mesh.surface_get_array_index_len(surface): return []
	return entry.arrays

func inventory_aabb_contains(bounds: AABB, point: Vector3) -> bool:
	return bounds.position.x-.001<=point.x and bounds.end.x+.001>=point.x and bounds.position.z-.001<=point.z and bounds.end.z+.001>=point.z and bounds.position.y<=point.y+.15 and bounds.end.y>=point.y-.15

func inventory_trunk_surfaces(camera: Camera3D) -> Dictionary:
	var points := PackedVector3Array([Vector3(375.319,0,-180.137),Vector3(382.319,0,-210.137),Vector3(378.319,0,-240.137)])
	var samples: Array[Dictionary] = []
	for point in points: samples.append({"point":[point.x,point.y,point.z],"hits":[]})
	var missing: Array[Dictionary] = []
	var scanned := 0
	for node: MeshInstance3D in world.find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree() or node.mesh==null or (node.layers&camera.cull_mask)==0: continue
		var bounds: AABB = node.global_transform*node.get_aabb()
		var relevant := false
		for point in points: relevant = relevant or inventory_aabb_contains(bounds,point)
		if not relevant: continue
		scanned += 1
		inventory_instance_surfaces(node,node.mesh,node.global_transform,-1,points,samples,missing)
	for node: MultiMeshInstance3D in world.find_children("*","MultiMeshInstance3D",true,false):
		if not node.is_visible_in_tree() or node.multimesh==null or node.multimesh.mesh==null or (node.layers&camera.cull_mask)==0: continue
		var bounds: AABB = node.global_transform*node.get_aabb()
		var relevant := false
		for point in points: relevant = relevant or inventory_aabb_contains(bounds,point)
		if not relevant: continue
		var count: int = node.multimesh.instance_count if node.multimesh.visible_instance_count<0 else mini(node.multimesh.instance_count,node.multimesh.visible_instance_count)
		for index in count:
			var transform: Transform3D = node.global_transform*node.multimesh.get_instance_transform(index)
			var instance_bounds: AABB = transform*node.multimesh.mesh.get_aabb()
			var touches := false
			for point in points: touches = touches or inventory_aabb_contains(instance_bounds,point)
			if not touches: continue
			scanned += 1
			inventory_instance_surfaces(node,node.multimesh.mesh,transform,index,points,samples,missing)
	for i in samples.size():
		var sample: Dictionary = samples[i]
		sample["hit_count"] = sample.hits.size()
		sample["shared_asphalt_hits"] = 0
		for hit in sample.hits:
			if hit.material_is_shared_asphalt: sample.shared_asphalt_hits += 1
		sample["complete"] = true
		for unknown in missing:
			if i in unknown.candidate_samples: sample["complete"] = false
	var result := {"complete":missing.is_empty(),"array_source":"existing MeshArrayCache entries only; no GPU readback on cache miss",
		"scope":"visible MeshInstance3D and MultiMeshInstance3D; |normal.y|>=0.7; sample height +/-0.15m; uncached surfaces are unknown",
		"scanned_instances":scanned,"uncached_surface_count":missing.size(),"uncached_surfaces":missing,"samples":samples,
		"rendered_frame":Engine.get_frames_drawn(),"timestamp_usec":Time.get_ticks_usec()}
	print("UNIFIED_BRIDGE_MAIN_SURFACE_INVENTORY ",JSON.stringify(result))
	return result

func inventory_instance_surfaces(node: GeometryInstance3D, mesh: Mesh, transform: Transform3D, instance: int, points: PackedVector3Array, samples: Array[Dictionary], missing: Array[Dictionary]) -> void:
	var bounds: AABB = transform*mesh.get_aabb()
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays: Array = cached_inventory_arrays(mesh,surface)
		var finish: Material = node.material_override if node.material_override!=null else mesh.surface_get_material(surface)
		var metadata := {"path":str(node.get_path()),"mesh_id":mesh.get_instance_id(),"mesh_path":mesh.resource_path,"instance":instance,"surface":surface,
			"material_id":finish.get_instance_id() if finish!=null else 0,"material_path":finish.resource_path if finish!=null else "",
			"material_class":finish.get_class() if finish!=null else "null","material_is_shared_asphalt":finish==KIT.material("asphalt")}
		if arrays.is_empty() or arrays.size()<=Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			var unknown: Dictionary = metadata.duplicate()
			unknown["reason"] = "surface absent/stale in CPU cache; geometry not read"
			unknown["candidate_samples"] = []
			for i in points.size():
				if inventory_aabb_contains(bounds,points[i]): unknown.candidate_samples.append(i)
			missing.append(unknown)
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX] if arrays.size()>Mesh.ARRAY_INDEX else null
		var count: int = indices.size() if indices is PackedInt32Array and not indices.is_empty() else vertices.size()
		for offset in range(0,count-2,3):
			var triangle := PackedVector3Array()
			for corner in 3:
				var index: int = indices[offset+corner] if indices is PackedInt32Array and not indices.is_empty() else offset+corner
				triangle.append(transform*vertices[index])
			var normal: Vector3 = (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
			if absf(normal.y)<.7: continue
			var a := Vector2(triangle[0].x,triangle[0].z)
			var b := Vector2(triangle[1].x,triangle[1].z)
			var c := Vector2(triangle[2].x,triangle[2].z)
			var denominator := (b-a).cross(c-a)
			if absf(denominator)<.0000001: continue
			for i in points.size():
				var point := Vector2(points[i].x,points[i].z)
				var u := (point-a).cross(c-a)/denominator
				var v := (b-a).cross(point-a)/denominator
				if u<-.000001 or v<-.000001 or u+v>1.000001: continue
				var height: float = triangle[0].y+(triangle[1].y-triangle[0].y)*u+(triangle[2].y-triangle[0].y)*v
				if absf(height-points[i].y)>.15: continue
				var hit: Dictionary = metadata.duplicate()
				hit["height"] = height
				hit["triangle"] = offset/3
				hit["normal"] = [normal.x,normal.y,normal.z]
				hit["on_triangle_boundary"] = minf(minf(absf(u),absf(v)),absf(1-u-v))<.000001
				samples[i].hits.append(hit)
