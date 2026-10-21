@tool
extends VBoxContainer
const DATA := preload("res://world/editing/WorldEditData.gd")
const PROTOCOL := preload("res://addons/geteco_world_editor/WorldPreviewProtocol.gd")
signal focus_requested
signal view_moved(at: Vector2)
signal units_ready(area: String, rows: Array)
signal activity(text: String, level: String)
signal interior_units_ready(id: String, rows: Array)
signal interior_validation_ready(id: String, error: String, document: Dictionary, floor_index: int)
signal topo_ready(area: String, terrain_revision: String, tiles: Array)
var viewport: SubViewport
var camera: Camera3D
var scene_root: Node3D
var geometry: Node3D
var surface: SubViewportContainer
var message: Label
var timer: Timer
var worker_pid := -1
var folder := ""
var revision := 0
var applied_revision := 0
var consumed_revision := 0
var desired := {}
var submitted := {}
var ready_at := 0
var loading_path := ""
var loading_response := {}
var focus := Vector3(45,0,110)
var yaw := 0.0
var pitch := .88
var view_size := 55.0
var orbiting := false
var panning := false
var last_build_ms := 0
var heartbeat_at := 0
var recovery_attempted := false
var built_center := Vector2.INF
var built_area := ""
var request_started := 0
var redraw_frames := 0
var edit_control
var editor_owner
## Alcance da prévia: células ao redor do foco (0 = padrão 3×3, -1 = região inteira).
const REACH_NAMES := ["Perto","Médio","Grande","Mapa inteiro"]
const REACH_RADIUS := [0,3,6,-1]
const REACH_VIEW := [55.0,130.0,260.0,700.0]
var reach := 0
var reach_menu: OptionButton
var refresh_count := 0
var stale := false
var built_radius := 0
var built_refresh := 0
var built_document := {}
var last_progress_at := 0
var progress_stamp := -1
var progress_phase := ""
var resource_fraction := -1.0
var assembling: Node3D
var part_index := -1
var applying_snapshot := false
var assembly_epoch := 0
var assembly_started := 0
var assembly_metrics := {}
var last_protocol_error := ""
var manifest_read_count := 0
var retire_collector: Node
var selected_interior := ""
var selected_floor := 0
var built_interior := ""
var built_floor := 0
var region_bounds_visible := true
var boundary_overlay: MeshInstance3D
var terrain_candidates: Array = []
var terrain_cursor: MeshInstance3D
var terrain_cursor_radius := -1.0
var topography_cache := {}
var lod_entries: Array = []
var lod_size := -1.0
var lod_pixel_height := -1.0
var lod_active := false
var lod_selected := ""
var lod_revision := 0
var lod_updating := false
var lod_metrics := {}
const INACTIVITY_TIMEOUT_MS := 90000

func _announce(text: String, level := "info") -> void:
	if level == "error":
		var diagnostic := _worker_error()
		if not diagnostic.is_empty(): text += "\n"+diagnostic
	message.text = text
	message.tooltip_text = text+"\nLog: "+ProjectSettings.globalize_path(folder+"/worker.log") if not folder.is_empty() else text
	activity.emit(text,level)

func _worker_error() -> String:
	if folder.is_empty() or not FileAccess.file_exists(folder+"/worker.log"): return ""
	var file := FileAccess.open(folder+"/worker.log",FileAccess.READ)
	if file == null: return ""
	file.seek(maxi(0,file.get_length()-12000))
	var lines := file.get_buffer(file.get_length()-file.get_position()).get_string_from_utf8().split("\n")
	for index in range(lines.size()-1,-1,-1):
		if "SCRIPT ERROR:" not in lines[index] and "ERROR:" not in lines[index]: continue
		var diagnostic := lines[index].strip_edges()
		for follow in range(index+1,mini(lines.size(),index+3)):
			diagnostic += " "+lines[follow].strip_edges()
		return diagnostic.left(700)
	return ""

func retry() -> void:
	var pending := desired.duplicate(true)
	stop()
	recovery_attempted = false
	refresh_count += 1
	request_started = 0
	last_progress_at = 0
	submitted = {}
	desired = {}
	if not pending.is_empty(): request(pending.document,Vector2(pending.focus[0],pending.focus[1]),str(pending.area),str(pending.get("interior_id","")),int(pending.get("interior_floor",0)))
	elif editor_owner != null: request(editor_owner.document,Vector2(focus.x,focus.z),editor_owner.region,selected_interior,selected_floor)

func cancel_loading() -> void:
	stop()
	desired = {}
	submitted = {}
	request_started = 0
	_announce("Carregamento cancelado · alterações preservadas")

func enable_editing(editor) -> void:
	editor_owner = editor
	edit_control = preload("res://addons/geteco_world_editor/World3DEdit.gd").new()
	surface.add_child(edit_control)
	edit_control.setup(editor,self)
	var modes := OptionButton.new()
	for label in ["Mover","Girar","Tamanho"]: modes.add_item(label)
	modes.item_selected.connect(edit_control.set_mode)
	get_child(0).add_child(modes)
	surface.tooltip_text = "Esquerdo: selecionar e arrastar · Shift: encaixar · Esc: cancelar · Direito: câmera · Meio: mover · Roda: zoom"

func _ready() -> void:
	set_process(false)
	retire_collector = preload("res://addons/geteco_world_editor/PreviewNodeRetire.gd").new()
	preload("res://addons/geteco_world_editor/PreviewNodeRetire.gd").install.call_deferred(weakref(retire_collector),get_tree())
	custom_minimum_size = Vector2(260,200)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HFlowContainer.new()
	add_child(bar)
	var title := Label.new()
	title.text = "Visão 3D"
	bar.add_child(title)
	var button := Button.new()
	button.text = "Focar seleção"
	button.pressed.connect(func(): focus_requested.emit())
	bar.add_child(button)
	reach_menu = OptionButton.new()
	for label in REACH_NAMES: reach_menu.add_item(label)
	reach_menu.tooltip_text = "Quanto do mapa a visão 3D carrega. Maiores demoram mais para montar; edições não reconstroem tudo (use Atualizar)."
	reach_menu.item_selected.connect(func(index):
		reach = index
		view_size = REACH_VIEW[index]
		if editor_owner != null: request(editor_owner.document,Vector2(focus.x,focus.z),built_area if not built_area.is_empty() else editor_owner.region,selected_interior,selected_floor)
		_pose())
	bar.add_child(reach_menu)
	var refresh := Button.new()
	refresh.text = "Atualizar"
	refresh.tooltip_text = "Reconstrói a visão 3D com as alterações atuais"
	refresh.pressed.connect(func():
		refresh_count += 1
		if editor_owner != null: request(editor_owner.document,Vector2(focus.x,focus.z),built_area if not built_area.is_empty() else editor_owner.region,selected_interior,selected_floor))
	bar.add_child(refresh)
	var retry_button := Button.new()
	retry_button.text = "Tentar novamente"
	retry_button.pressed.connect(retry)
	bar.add_child(retry_button)
	var cancel_button := Button.new()
	cancel_button.text = "Cancelar carga"
	cancel_button.pressed.connect(cancel_loading)
	bar.add_child(cancel_button)
	var frame_button := Button.new()
	frame_button.text = "Enquadrar mapa"
	frame_button.pressed.connect(func():
		if editor_owner == null: return
		var bounds: Rect2 = editor_owner.region_bounds(editor_owner.region) if editor_owner.has_method("region_bounds") else Rect2()
		frame_region(editor_owner.region,bounds))
	bar.add_child(frame_button)
	var reset := Button.new()
	reset.text = "Recentrar"
	reset.pressed.connect(func(): yaw = 0; pitch = .88; view_size = REACH_VIEW[reach]; _pose())
	bar.add_child(reset)
	surface = SubViewportContainer.new()
	surface.stretch = true
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.tooltip_text = "Botão direito: girar · Botão do meio: mover · Roda: zoom"
	surface.gui_input.connect(_camera_input)
	add_child(surface)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.handle_input_locally = false
	surface.add_child(viewport)
	scene_root = Node3D.new()
	viewport.add_child(scene_root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("829da6")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c0d0e2")
	env.environment.ambient_light_energy = .65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_color = Color("fffdf5")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	scene_root.add_child(sun)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 9000
	scene_root.add_child(camera)
	camera.make_current()
	message = Label.new()
	message.text = "Preparando visão 3D…"
	message.clip_text = true
	add_child(message)
	timer = Timer.new()
	timer.wait_time = .15
	timer.timeout.connect(_poll)
	add_child(timer)
	visibility_changed.connect(_visibility)
	surface.resized.connect(_render_once)
	_pose()

func request(document: Dictionary, at: Vector2, area: String, interior_id := "", interior_floor := 0) -> void:
	selected_interior = interior_id
	selected_floor = interior_floor
	var next := {"document":document,"focus":[at.x,at.y],"area":area,"radius":REACH_RADIUS[reach],"refresh":refresh_count,"interior_id":interior_id,"interior_floor":interior_floor,"terrain_revision":terrain_revision(document,area)}
	if next == desired: return
	# Full-region geometry is independent of its camera center, including while
	# the worker is still building it. Keep the submitted payload immutable so a
	# pan cannot supersede hundreds of cells of otherwise identical work.
	if _same_whole_content(next):
		focus = Vector3(at.x,focus.y,at.y)
		_pose()
		return
	var changes: Array[String] = []
	for key in ["area","focus","radius","refresh","document","interior_id","interior_floor"]:
		if next.get(key) != desired.get(key): changes.append(key)
	print("WORLD_PREVIEW_REQUEST ",JSON.stringify({"changes":changes,"area":area,"focus":[at.x,at.y],"radius":REACH_RADIUS[reach],"refresh":refresh_count,"document_hash":document.hash()}))
	# Editar nunca reconstrói a prévia: mover, girar, esticar e excluir já foram aplicados na cena que
	# está na tela (ver after_commit). Só se reconstrói ao trocar de região/alcance, ao sair da área
	# carregada ou ao pedir (Atualizar, peça nova, desfazer/refazer). A câmera apenas acompanha.
	var limit: float = 48.0 if REACH_RADIUS[reach] == 0 else REACH_RADIUS[reach]*40.0
	if is_instance_valid(geometry) and applied_revision == revision and area == built_area and interior_id == built_interior and interior_floor == built_floor and REACH_RADIUS[reach] == built_radius and refresh_count == built_refresh and (REACH_RADIUS[reach] < 0 or at.distance_to(built_center) < limit):
		desired = next.duplicate(true)
		submitted = next.duplicate(true)
		focus = Vector3(at.x,focus.y,at.y)
		message.text = "Há alterações que só aparecem depois de Atualizar (vias, cores, modelos)." if stale else "Atualizada · Direito: girar · Meio: mover · Roda: zoom"
		_pose()
		return
	# Harbor is flat; focus nearby objects immediately within the loaded cells.
	# Mountain changes also request the terrain height from the builder.
	if is_instance_valid(geometry) and applied_revision == revision and area == "harbor" and area == built_area and interior_id == built_interior and interior_floor == built_floor and REACH_RADIUS[reach] == built_radius and refresh_count == built_refresh and at.distance_to(built_center) < 48 and document == submitted.get("document",{}):
		desired = next.duplicate(true)
		submitted = next.duplicate(true)
		focus = Vector3(at.x,0,at.y)
		_pose()
		return
	desired = next.duplicate(true)
	ready_at = Time.get_ticks_msec()+450
	message.text = "Atualização pendente…"
	if not timer.is_stopped(): return
	timer.start()

static func terrain_revision(document: Dictionary, area: String) -> String:
	return preload("res://addons/geteco_world_editor/WorldTerrainMap.gd").revision(document,area)

func _same_whole_content(next: Dictionary) -> bool:
	if desired.is_empty() or int(next.get("radius",0)) >= 0 or int(desired.get("radius",0)) >= 0: return false
	for key in ["document","area","radius","refresh","interior_id","interior_floor","terrain_revision"]:
		if next.get(key) != desired.get(key): return false
	return bool(next.get("topography_only",false)) == bool(desired.get("topography_only",false))

func request_topography(document: Dictionary, at: Vector2, area: String, content_revision := "") -> void:
	var signature := content_revision if not content_revision.is_empty() else terrain_revision(document,area)
	var key := area+"/"+signature
	if topography_cache.has(key):
		topo_ready.emit(area,signature,topography_cache[key])
		return
	var next := {"document":document,"focus":[at.x,at.y],"area":area,"radius":-1,"refresh":0,"interior_id":"","interior_floor":0,"topography_only":true,"terrain_revision":signature}
	if _same_whole_content(next): return
	desired = next.duplicate(true)
	ready_at = Time.get_ticks_msec()+450
	_announce("Preparando relevo 2D · "+area+"…")
	if timer.is_stopped(): timer.start()

func _publish_topography(response: Dictionary) -> void:
	if not response.has("topography"): return
	preload("res://addons/geteco_world_editor/WorldTerrainMapImport.gd").run(weakref(self),response,get_tree())

func start() -> void:
	if worker_pid > 0: return
	folder = "res://.godot/world_live_%d_%d" % [OS.get_process_id(),get_instance_id()]
	DirAccess.make_dir_recursive_absolute(folder)
	for filename in ["request.json","response.json","response_ready.json","progress.json","stop"]:
		DirAccess.remove_absolute(folder+"/"+filename)
	_heartbeat()
	worker_pid = OS.create_process(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/geteco_world_editor/live_preview_worker.gd","--log-file",ProjectSettings.globalize_path(folder+"/worker.log"),"--","--no-save","--folder="+folder,"--parent="+str(OS.get_process_id())]))
	if worker_pid <= 0: _announce("Não foi possível abrir a visão 3D.","error"); return
	timer.start()

func _poll() -> void:
	if not folder.is_empty() and Time.get_ticks_msec()-heartbeat_at > 1000: _heartbeat()
	if edit_control != null and edit_control.dragging: return
	if edit_control != null and edit_control.editor.junction_editor.dragging: return
	if not is_visible_in_tree() and not desired.get("topography_only",false): return
	if applying_snapshot: return
	if worker_pid <= 0: start()
	if worker_pid <= 0: return
	if not OS.is_process_running(worker_pid):
		if not recovery_attempted:
			recovery_attempted = true
			stop()
			submitted = {}
			request_started = 0
			ready_at = 0
			message.text = "Reconectando a prévia…"
			start()
			return
		_announce("A prévia encerrou. Use Tentar novamente; consulte o log.","error")
		timer.stop()
		return
	_read_progress()
	if request_started > 0 and applied_revision < revision and Time.get_ticks_msec()-maxi(request_started,last_progress_at) > INACTIVITY_TIMEOUT_MS:
		_announce("Prévia sem progresso por 90 s. Use Tentar novamente; consulte o log."+("\n"+last_protocol_error if not last_protocol_error.is_empty() else ""),"error")
		stop()
		return
	if not loading_path.is_empty():
		_advance_loading()
		return
	if desired != submitted and not desired.is_empty() and Time.get_ticks_msec() >= ready_at:
		revision += 1
		# Old manifests can be megabytes. Discard their notification before the
		# next request, and never parse a manifest until its tiny ready marker agrees.
		DirAccess.remove_absolute(folder+"/response_ready.json")
		DirAccess.remove_absolute(folder+"/response.json")
		var payload := desired.duplicate(true)
		payload.revision = revision
		var file := FileAccess.open(folder+"/request.tmp",FileAccess.WRITE)
		if file == null: message.text = "Não foi possível atualizar a prévia."; return
		file.store_string(JSON.stringify(payload))
		file.close()
		if DirAccess.rename_absolute(folder+"/request.tmp",folder+"/request.json") != OK: return
		submitted = desired.duplicate(true)
		request_started = Time.get_ticks_msec()
		last_progress_at = request_started
		progress_stamp = -1
		progress_phase = ""
		last_protocol_error = ""
		_announce("Preparando "+str(payload.area)+"…")
	if consumed_revision >= revision: return
	var marker := PROTOCOL.read(folder+"/response_ready.json")
	if int((marker.data as Dictionary).get("revision",0)) != revision: return
	var path := folder+"/response.json"
	if not FileAccess.file_exists(path): return
	manifest_read_count += 1
	var decoded := PROTOCOL.read(path)
	if not str(decoded.error).is_empty():
		last_protocol_error = str(decoded.error)
		return
	if last_protocol_error.contains(path): last_protocol_error = ""
	var response: Dictionary = decoded.data
	if response is Dictionary: _cleanup_snapshots(int(response.get("revision",0)))
	if not response is Dictionary or int(response.get("revision",0)) != revision or consumed_revision >= revision: return
	# A loaded snapshot may be superseded during debounce. It has already been
	# collected/deleted and must never be requested again from the old response.
	consumed_revision = revision
	if not str(response.get("error","")).is_empty():
		request_started = 0
		if not str(response.get("interior_id","")).is_empty(): interior_validation_ready.emit(str(response.interior_id),str(response.get("interior_validation_error",response.error)),submitted.get("document",{}).duplicate(true),int(response.get("interior_floor",submitted.get("interior_floor",0))))
		_announce(str(response.error),"error")
		return
	if response.get("topography_only",false):
		_publish_topography(response)
		request_started = 0
		if (response.get("topography",[]) as Array).is_empty(): _announce("Nenhuma superfície de relevo 2D foi encontrada · "+str(response.get("area","")),"warning")
		else: _announce("Relevo 2D pronto · "+str(response.get("area","")))
		return
	loading_response = response
	part_index = -1
	assembly_epoch += 1
	assembly_started = Time.get_ticks_usec()
	assembly_metrics = {"parts":response.get("parts",[]).size(),"instantiate_max_ms":0.0,"attach_max_ms":0.0,"restore_max_ms":0.0,"merge_ms":0.0,"index_ms":0.0}
	_announce("Carregando geometria 3D…")
	_begin_resource(str(response.path))

func _begin_resource(path: String) -> void:
	loading_path = path
	resource_fraction = -1.0
	last_progress_at = Time.get_ticks_msec()
	set_process(true)
	if ResourceLoader.load_threaded_request(path,"PackedScene",false,ResourceLoader.CACHE_MODE_IGNORE) != OK:
		loading_path = ""
		request_started = 0
		_discard_assembly()
		_announce("Não foi possível carregar a visão 3D. Use Tentar novamente.","error")

func _retire(node: Node) -> void:
	if not is_instance_valid(node): return
	if is_instance_valid(retire_collector) and retire_collector.is_inside_tree(): retire_collector.take(node)
	else: node.free()

func _discard_assembly() -> void:
	if is_instance_valid(assembling): _retire(assembling)
	assembling = null

func _advance_loading() -> void:
	if applying_snapshot or loading_path.is_empty(): return
	var resource_progress: Array = []
	var state := ResourceLoader.load_threaded_get_status(loading_path,resource_progress)
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not resource_progress.is_empty() and float(resource_progress[0]) > resource_fraction:
			resource_fraction = float(resource_progress[0])
			last_progress_at = Time.get_ticks_msec()
		message.text = "Montando 3D · %d/%d partes · %.0f s" % [maxi(0,part_index),loading_response.get("parts",[]).size(),(Time.get_ticks_msec()-request_started)/1000.0]
		return
	if state != ResourceLoader.THREAD_LOAD_LOADED:
		loading_path = ""
		request_started = 0
		_discard_assembly()
		_announce("Não foi possível carregar a visão 3D. Use Tentar novamente.","error")
		return
	var packed := ResourceLoader.load_threaded_get(loading_path) as PackedScene
	DirAccess.remove_absolute(loading_path)
	loading_path = ""
	if packed == null or int(loading_response.revision) != revision or desired != submitted:
		_discard_assembly()
		return
	var began := Time.get_ticks_usec()
	var part := packed.instantiate() as Node3D
	assembly_metrics.instantiate_max_ms = maxf(float(assembly_metrics.instantiate_max_ms),(Time.get_ticks_usec()-began)/1000.0)
	if part == null:
		request_started = 0
		_discard_assembly()
		_announce("A prévia recebida é inválida. A visão anterior foi preservada.","error")
		return
	began = Time.get_ticks_usec()
	_restore_instance_transforms(part)
	assembly_metrics.restore_max_ms = maxf(float(assembly_metrics.restore_max_ms),(Time.get_ticks_usec()-began)/1000.0)
	began = Time.get_ticks_usec()
	var parts: Array = loading_response.get("parts",[])
	if part_index < 0:
		assembling = part
		assembling.hide()
		scene_root.add_child(assembling)
	else:
		var parent := assembling.get_node_or_null(str(parts[part_index].parent))
		if parent == null:
			part.free()
			request_started = 0
			_discard_assembly()
			_announce("Hierarquia 3D incompleta; a visão anterior foi preservada.","error")
			return
		preload("res://addons/geteco_world_editor/WorldPreviewParts.gd").attach(part,parent)
		part.free()
	assembly_metrics.attach_max_ms = maxf(float(assembly_metrics.attach_max_ms),(Time.get_ticks_usec()-began)/1000.0)
	part_index += 1
	last_progress_at = Time.get_ticks_msec()
	if part_index < parts.size():
		_begin_resource(str(parts[part_index].path))
		return
	applying_snapshot = true
	_announce("Indexando objetos editáveis…")
	preload("res://addons/geteco_world_editor/PreviewAssemblyFinish.gd").run(weakref(self),assembly_epoch,get_tree())

func _complete_assembly(epoch: int, indexed: bool) -> void:
	if epoch != assembly_epoch or not indexed or not is_instance_valid(assembling):
		applying_snapshot = false
		_discard_assembly()
		return
	var previous := geometry
	var swap_started := Time.get_ticks_usec()
	geometry = assembling
	assembling = null
	geometry.show()
	terrain_candidates.clear()
	for path in loading_response.get("terrain_paths",[]):
		var surface_node := geometry.get_node_or_null(str(path)) as MeshInstance3D
		if surface_node != null and surface_node.mesh != null: terrain_candidates.append({"node":surface_node,"bounds":surface_node.mesh.get_aabb()})
	if is_instance_valid(terrain_cursor): terrain_cursor.hide()
	if is_instance_valid(previous): _retire(previous)
	assembly_metrics.visibility_swap_ms = (Time.get_ticks_usec()-swap_started)/1000.0
	applied_revision = revision
	var fit_whole := int(submitted.get("radius",0)) < 0 and (built_radius >= 0 or built_area != str(submitted.area))
	var keep_room_height := not str(loading_response.get("interior_id","")).is_empty() and built_interior == str(loading_response.get("interior_id","")) and built_floor == int(submitted.get("interior_floor",0))
	var focus_height := focus.y if (int(submitted.get("radius",0)) < 0 and not fit_whole) or keep_room_height else float(loading_response.height)
	focus = Vector3(focus.x,focus_height,focus.z) if int(submitted.get("radius",0)) < 0 else Vector3(submitted.focus[0],focus_height,submitted.focus[1])
	if fit_whole: _fit_bounds(loading_response.get("bounds",[]))
	var next_interior := str(loading_response.get("interior_id",""))
	if not next_interior.is_empty() and (built_interior != next_interior or built_floor != int(submitted.get("interior_floor",0))):
		var room_focus: Array = loading_response.get("camera_focus",[0,0,0])
		focus = Vector3(float(room_focus[0]),float(room_focus[1]),float(room_focus[2]))
		view_size = float(loading_response.get("camera_size",20.0))
		yaw = 0.0
		pitch = atan2(18.0,15.0)
	last_build_ms = int(loading_response.build_ms)
	built_center = Vector2(focus.x,focus.z)
	built_area = str(submitted.area)
	built_radius = int(submitted.get("radius",0))
	built_refresh = int(submitted.get("refresh",0))
	built_document = submitted.document.duplicate(true)
	built_interior = next_interior
	built_floor = int(submitted.get("interior_floor",0))
	if not built_interior.is_empty(): interior_validation_ready.emit(built_interior,str(loading_response.get("interior_validation_error","")),built_document.duplicate(true),built_floor)
	_update_boundaries()
	_publish_topography(loading_response)
	stale = false
	request_started = 0
	applying_snapshot = false
	assembly_metrics.total_ms = (Time.get_ticks_usec()-assembly_started)/1000.0
	print("WORLD_PREVIEW_ASSEMBLY ",JSON.stringify(assembly_metrics))
	_announce("Atualizada · construção %.1f s · %d partes · Direito: girar · Meio: mover · Roda: zoom" % [last_build_ms/1000.0,loading_response.get("parts",[]).size()])
	if not built_interior.is_empty() and not str(loading_response.get("interior_validation_error","")).is_empty():
		_announce("Alterações visíveis · "+str(loading_response.interior_validation_error),"error")
	_pose()

func _fit_bounds(values: Array) -> void:
	if values.size() != 6: return
	var box := AABB(Vector3(float(values[0]),float(values[1]),float(values[2])),Vector3(float(values[3]),float(values[4]),float(values[5])))
	if box.size.x <= 0.0 or box.size.z <= 0.0: return
	var right := Vector3(cos(yaw),0,-sin(yaw))
	var up := Vector3(-sin(yaw)*sin(pitch),cos(pitch),-cos(yaw)*sin(pitch))
	var width := right.abs().dot(box.size)
	var height := up.abs().dot(box.size)
	var aspect := maxf(.1,surface.size.x/maxf(1.0,surface.size.y))
	focus = box.get_center()
	view_size = maxf(height,width/aspect)*1.12

func frame_region(area: String, bounds: Rect2) -> void:
	if editor_owner == null: return
	if not selected_interior.is_empty():
		var room: Array = loading_response.get("interior_bounds",[])
		if room.size() == 4:
			_fit_bounds([room[0],0.0,room[1],room[2],5.0,room[3]])
			_pose()
		return
	reach = 3
	reach_menu.select(3)
	var at := bounds.get_center() if bounds.has_area() else Vector2(focus.x,focus.z)
	if bounds.has_area(): _fit_bounds([bounds.position.x,0.0,bounds.position.y,bounds.size.x,64.0,bounds.size.y])
	request(editor_owner.document,at,area)
	_pose()

func set_region_bounds_visible(value: bool) -> void:
	region_bounds_visible = value
	_update_boundaries()
	_render_once()

func _update_boundaries() -> void:
	if scene_root == null: return
	if not is_instance_valid(boundary_overlay):
		boundary_overlay = MeshInstance3D.new()
		boundary_overlay.name = "EditorMapBoundaries"
		boundary_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene_root.add_child(boundary_overlay)
	boundary_overlay.visible = region_bounds_visible
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	var rectangles: Array = []
	if not built_interior.is_empty():
		var room: Array = loading_response.get("interior_bounds",[])
		if room.size() == 4: rectangles.append([Rect2(room[0],room[1],room[2],room[3]),Color("f3d58a")])
	elif is_instance_valid(editor_owner) and editor_owner.has_method("region_bounds"):
		for area in ["harbor","mountain","desert"]:
			rectangles.append([editor_owner.region_bounds(area),{"harbor":Color("7be5b0"),"mountain":Color("a0caff"),"desert":Color("f4c77f")}[area]])
	var has_vertices := false
	for entry in rectangles:
		var rect: Rect2 = entry[0]
		if not rect.has_area(): continue
		if not has_vertices:
			mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
			has_vertices = true
		mesh.surface_set_color(entry[1])
		var points := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for index in 4:
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index+1)%4]
			mesh.surface_add_vertex(Vector3(a.x,.08,a.y))
			mesh.surface_add_vertex(Vector3(b.x,.08,b.y))
	if has_vertices: mesh.surface_end()
	boundary_overlay.mesh = mesh if has_vertices else null

func terrain_point(at: Vector2) -> Variant:
	if edit_control == null or camera == null or not built_interior.is_empty(): return null
	var origin := camera.project_ray_origin(at)
	var end := origin+camera.project_ray_normal(at)*camera.far
	var found: Variant = null
	var distance := INF
	var candidates: Array = terrain_candidates if not terrain_candidates.is_empty() else edit_control.meshes
	for item in candidates:
		var node: MeshInstance3D = item.node
		if not is_instance_valid(node) or not node.is_visible_in_tree() or not node.get_meta("editor_terrain_surface",false): continue
		var inverse := node.global_transform.affine_inverse()
		if (item.bounds as AABB).intersects_segment(inverse*origin,inverse*end) == null: continue
		var triangles: TriangleMesh = edit_control._triangle_mesh(node.mesh)
		if triangles == null: continue
		var hit := triangles.intersect_ray(inverse*origin,inverse*end-inverse*origin)
		if hit.is_empty(): continue
		var point: Vector3 = node.global_transform*hit.position
		var next := origin.distance_squared_to(point)
		if next < distance:
			distance = next
			found = point
	return found

func _terrain_hover(at: Vector2) -> void:
	if not is_instance_valid(editor_owner) or not bool(editor_owner.get("terrain_mode")):
		if is_instance_valid(terrain_cursor) and terrain_cursor.visible:
			terrain_cursor.hide()
			_render_once()
		return
	var point: Variant = terrain_point(at)
	if point == null:
		hide_terrain_cursor()
		return
	var settings: Dictionary = editor_owner.get("terrain_settings")
	var radius := float(settings.get("radius",16.0))
	if not is_instance_valid(terrain_cursor):
		terrain_cursor = MeshInstance3D.new()
		terrain_cursor.name = "EditorTerrainBrush"
		terrain_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain_cursor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		scene_root.add_child(terrain_cursor)
	if not is_equal_approx(radius,terrain_cursor_radius):
		var mesh := ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("ffc86c")
		material.no_depth_test = true
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,material)
		for index in 65:
			var angle := index*TAU/64.0
			mesh.surface_add_vertex(Vector3(cos(angle)*radius,0,sin(angle)*radius))
		mesh.surface_end()
		terrain_cursor.mesh = mesh
		terrain_cursor_radius = radius
	terrain_cursor.position = (point as Vector3)+Vector3.UP*.12
	terrain_cursor.show()
	_render_once()

func hide_terrain_cursor() -> void:
	if is_instance_valid(terrain_cursor) and terrain_cursor.visible:
		terrain_cursor.hide()
		_render_once()

func _read_progress() -> void:
	if folder.is_empty() or request_started <= 0: return
	var decoded := PROTOCOL.read(folder+"/progress.json")
	if not str(decoded.error).is_empty():
		last_protocol_error = str(decoded.error)
		return
	if last_protocol_error.contains(folder+"/progress.json"): last_protocol_error = ""
	var value: Dictionary = decoded.data
	if int(value.get("revision",0)) != revision: return
	var stamp := int(value.get("updated",0))
	if stamp != progress_stamp:
		progress_stamp = stamp
		last_progress_at = Time.get_ticks_msec()
	if not loading_path.is_empty() or applying_snapshot: return
	var phase := str(value.get("phase","Construindo cenário"))
	var elapsed := (Time.get_ticks_msec()-request_started)/1000.0
	var total := int(value.get("total",0))
	var counts := " · %d/%d trechos" % [int(value.get("done",0)),total] if total > 0 else ""
	message.text = phase+counts+" · %.0f s" % elapsed
	message.tooltip_text = message.text+"\nLog: "+ProjectSettings.globalize_path(folder+"/worker.log")
	if phase != progress_phase:
		progress_phase = phase
		activity.emit(message.text,"info")

## Chamado a cada alteração aceita do documento. Aplica o efeito na cena que já está na tela; só pede
## reconstrução quando não há como (peça nova, mudança de modelo/cor). Vias ficam marcadas como
## desatualizadas (o desenho delas já aparece como contorno na visão 3D).
func after_commit(previous: Dictionary, row: Dictionary) -> void:
	if edit_control == null or edit_control.synchronizing: return
	if str(row.get("type","")) == "terrain":
		refresh()
		return
	if not selected_interior.is_empty():
		if row.get("deleted",false): hide_deleted(str(row.id))
		elif not previous.is_empty(): edit_control.apply_row_change(previous,row)
		refresh()
		return
	if row.get("deleted",false):
		hide_deleted(str(row.id))
		return
	if str(row.get("type","")) == "road":
		stale = true
		return
	if previous.is_empty() or not edit_control.apply_row_change(previous,row): refresh()

## Reconstrói a prévia com o documento atual.
func refresh() -> void:
	refresh_count += 1

func hide_deleted(id: String) -> void:
	if edit_control == null or not edit_control.groups.has(id): return
	for node in edit_control.groups[id]:
		if is_instance_valid(node): node.visible = false
	edit_control.remove_group(id)
	_render_once()

func _pose() -> void:
	if camera == null: return
	camera.size = view_size
	camera.position = focus+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*maxf(180.0,view_size*1.5)
	camera.look_at(focus)
	preload("res://addons/geteco_world_editor/WorldPreviewLOD.gd").request(self)
	if edit_control != null: edit_control.queue_redraw()
	_render_once()

func refresh_lod_selection() -> void:
	preload("res://addons/geteco_world_editor/WorldPreviewLOD.gd").request(self)

func _restore_instance_transforms(node: Node) -> void:
	if node is MultiMeshInstance3D and node.has_meta("preview_instance_transforms"):
		var transforms: Array = node.get_meta("preview_instance_transforms")
		for index in mini(transforms.size(),node.multimesh.instance_count):
			node.multimesh.set_instance_transform(index,transforms[index])
		node.remove_meta("preview_instance_transforms")
		var colors: Array = node.get_meta("preview_instance_colors",[])
		if node.multimesh.use_colors:
			for index in mini(colors.size(),node.multimesh.instance_count): node.multimesh.set_instance_color(index,colors[index])
		node.remove_meta("preview_instance_colors")
	for child in node.get_children(): _restore_instance_transforms(child)

func _render_once() -> void:
	if viewport != null and is_visible_in_tree():
		# Newly instanced meshes/shaders need a few render frames before freezing.
		redraw_frames = 4
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		set_process(true)

func _process(_delta: float) -> void:
	if not loading_path.is_empty(): _advance_loading()
	redraw_frames -= 1
	if redraw_frames <= 0:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if loading_path.is_empty() and not applying_snapshot: set_process(false)

func _visibility() -> void:
	if not is_visible_in_tree():
		if edit_control != null: edit_control.cancel()
		set_process(false)
		orbiting = false
		panning = false
		if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else: _render_once()

func _camera_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not orbiting and not panning: _terrain_hover(event.position)
	if not applying_snapshot and edit_control != null and edit_control.input_event(event):
		surface.accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if panning and not event.pressed: view_moved.emit(Vector2(focus.x,focus.z))
			panning = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			view_size = clampf(view_size*(.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/.85),12,100 if reach == 0 else 2500)
			_pose()
	elif event is InputEventMouseMotion:
		if orbiting:
			yaw -= event.relative.x*.008
			pitch = clampf(pitch+event.relative.y*.006,.3,1.45)
			_pose()
		elif panning:
			var right := Vector3(cos(yaw),0,-sin(yaw))
			var back := Vector3(sin(yaw),0,cos(yaw))
			focus -= (right*event.relative.x+back*event.relative.y)*view_size/maxf(1,surface.size.y)
			_pose()

func stop() -> void:
	assembly_epoch += 1
	applying_snapshot = false
	if edit_control != null: edit_control.index_revision += 1
	if is_instance_valid(editor_owner) and bool(editor_owner.get("_merging_units")):
		editor_owner.unit_index_generation += 1
		if is_instance_valid(editor_owner.canvas): editor_owner.canvas.context_index_revision += 1
		editor_owner._merging_units = false
		if editor_owner.is_inside_tree(): editor_owner._refresh_controls()
	_discard_assembly()
	set_process(false)
	if timer != null: timer.stop()
	if worker_pid > 0 and OS.is_process_running(worker_pid): OS.kill(worker_pid)
	worker_pid = -1
	_cleanup_snapshots(revision if not loading_path.is_empty() else 2147483647)
	# Never block the UI waiting on a threaded load that belongs to a closed panel.
	if not loading_path.is_empty():
		var state := ResourceLoader.load_threaded_get_status(loading_path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS and is_inside_tree():
			if is_instance_valid(retire_collector) and retire_collector.is_inside_tree():
				var drain := preload("res://addons/geteco_world_editor/PreviewResourceDrain.gd").new()
				drain.resource_path = loading_path
				drain.cleanup_folder = folder
				drain.cleanup_revision = revision
				retire_collector.add_child(drain)
			else:
				# Only possible when created/closed before the first editor frame.
				# No deferred unparented Node may survive an immediate process quit.
				ResourceLoader.load_threaded_get(loading_path)
				loading_path = ""
				_cleanup_snapshots(2147483647)
		elif state == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(loading_path)
			DirAccess.remove_absolute(loading_path)
			loading_path = ""
			_cleanup_snapshots(2147483647)
		loading_path = ""
	if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _heartbeat() -> void:
	var file := FileAccess.open(folder+"/heartbeat",FileAccess.WRITE)
	if file != null: file.store_string("active")
	heartbeat_at = Time.get_ticks_msec()

func _cleanup_snapshots(older_than: int) -> void:
	if not folder.begins_with("res://.godot/world_live_%d_" % OS.get_process_id()): return
	for filename in DirAccess.get_files_at(folder):
		if filename.begins_with("topo_") and filename.ends_with(".png"):
			if filename.trim_prefix("topo_").get_slice("_",0).to_int() < older_than: DirAccess.remove_absolute(folder+"/"+filename)
			continue
		if not filename.begins_with("view_") or not (filename.ends_with(".scn") or filename.ends_with(".res")): continue
		if filename.trim_prefix("view_").get_slice("_",0).trim_suffix(".scn").to_int() >= older_than: continue
		var path := folder+"/"+filename
		if path != loading_path: DirAccess.remove_absolute(path)

func _exit_tree() -> void:
	stop()
	# The panel itself can be freed immediately. Its detached SubViewport keeps
	# the passive scene alive only while a collector retires nodes in short slices.
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(retire_collector) and retire_collector.is_inside_tree():
			retire_collector.take(viewport)
			retire_collector.keep_alive = false
		else:
			# Created and closed in the same frame: the viewport is still empty,
			# and synchronous deletion is preferable to any unparented resource.
			viewport.free()
			if is_instance_valid(retire_collector): retire_collector.free()
		viewport = null
		geometry = null
