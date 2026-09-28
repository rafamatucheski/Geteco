@tool
extends VBoxContainer
const DATA := preload("res://world/editing/WorldEditData.gd")
signal focus_requested
signal view_moved(at: Vector2)
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
	var reset := Button.new()
	reset.text = "Recentrar"
	reset.pressed.connect(func(): yaw = 0; pitch = .88; view_size = 55; _pose())
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
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 2000
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

func request(document: Dictionary, at: Vector2, area: String) -> void:
	var next := {"document":document,"focus":[at.x,at.y],"area":area}
	if next == desired: return
	# Harbor is flat; focus nearby objects immediately within the loaded cells.
	# Mountain changes also request the terrain height from the builder.
	if is_instance_valid(geometry) and applied_revision == revision and area == "harbor" and area == built_area and at.distance_to(built_center) < 48 and document == submitted.get("document",{}):
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

func start() -> void:
	if worker_pid > 0: return
	folder = "res://.godot/world_live_%d_%d" % [OS.get_process_id(),get_instance_id()]
	DirAccess.make_dir_recursive_absolute(folder)
	_heartbeat()
	worker_pid = OS.create_process(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/geteco_world_editor/live_preview_worker.gd","--log-file",ProjectSettings.globalize_path(folder+"/worker.log"),"--","--no-save","--folder="+folder,"--parent="+str(OS.get_process_id())]))
	if worker_pid <= 0: message.text = "Não foi possível abrir a visão 3D."; return
	timer.start()

func _poll() -> void:
	if not folder.is_empty() and Time.get_ticks_msec()-heartbeat_at > 1000: _heartbeat()
	if edit_control != null and edit_control.dragging: return
	if edit_control != null and edit_control.editor.junction_editor.dragging: return
	if not is_visible_in_tree(): return
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
		message.text = "A prévia encerrou. Desative e ative 2D + 3D para tentar novamente."
		timer.stop()
		return
	if request_started > 0 and applied_revision < revision and Time.get_ticks_msec()-request_started > 90000:
		message.text = "A prévia demorou para atualizar. Desative e ative 2D + 3D para tentar novamente."
		stop()
		return
	if not loading_path.is_empty():
		var state := ResourceLoader.load_threaded_get_status(loading_path)
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(loading_path) as PackedScene
			DirAccess.remove_absolute(loading_path)
			loading_path = ""
			if packed != null and int(loading_response.revision) == revision and desired == submitted:
				if is_instance_valid(geometry): geometry.free()
				geometry = packed.instantiate()
				_restore_instance_transforms(geometry)
				scene_root.add_child(geometry)
				if edit_control != null: edit_control.rebuild()
				applied_revision = revision
				focus = Vector3(desired.focus[0],float(loading_response.height),desired.focus[1])
				last_build_ms = int(loading_response.build_ms)
				built_center = Vector2(focus.x,focus.z)
				built_area = str(desired.area)
				message.text = "Atualizada · Direito: girar · Meio: mover · Roda: zoom"
				_pose()
		elif state == ResourceLoader.THREAD_LOAD_FAILED:
			loading_path = ""
			message.text = "Não foi possível carregar a visão 3D."
		return
	if desired != submitted and not desired.is_empty() and Time.get_ticks_msec() >= ready_at:
		revision += 1
		var payload := desired.duplicate(true)
		payload.revision = revision
		var file := FileAccess.open(folder+"/request.tmp",FileAccess.WRITE)
		if file == null: message.text = "Não foi possível atualizar a prévia."; return
		file.store_string(JSON.stringify(payload))
		file.close()
		if DirAccess.rename_absolute(folder+"/request.tmp",folder+"/request.json") != OK: return
		submitted = desired.duplicate(true)
		request_started = Time.get_ticks_msec()
		message.text = "Atualizando 3D…"
	var path := folder+"/response.json"
	if not FileAccess.file_exists(path): return
	var response: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if response is Dictionary: _cleanup_snapshots(int(response.get("revision",0)))
	if not response is Dictionary or int(response.get("revision",0)) != revision or consumed_revision >= revision: return
	# A loaded snapshot may be superseded during debounce. It has already been
	# collected/deleted and must never be requested again from the old response.
	consumed_revision = revision
	if not str(response.get("error","")).is_empty(): message.text = response.error; return
	loading_response = response
	loading_path = str(response.path)
	if ResourceLoader.load_threaded_request(loading_path,"PackedScene",false,ResourceLoader.CACHE_MODE_IGNORE) != OK:
		loading_path = ""
		message.text = "Não foi possível carregar a visão 3D."

func _pose() -> void:
	if camera == null: return
	camera.size = view_size
	camera.position = focus+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*180
	camera.look_at(focus)
	if edit_control != null: edit_control.queue_redraw()
	_render_once()

func _restore_instance_transforms(node: Node) -> void:
	if node is MultiMeshInstance3D and node.has_meta("preview_instance_transforms"):
		var transforms: Array = node.get_meta("preview_instance_transforms")
		for index in mini(transforms.size(),node.multimesh.instance_count):
			node.multimesh.set_instance_transform(index,transforms[index])
		node.remove_meta("preview_instance_transforms")
	for child in node.get_children(): _restore_instance_transforms(child)

func _render_once() -> void:
	if viewport != null and is_visible_in_tree():
		# Newly instanced meshes/shaders need a few render frames before freezing.
		redraw_frames = 4
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		set_process(true)

func _process(_delta: float) -> void:
	redraw_frames -= 1
	if redraw_frames <= 0:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)

func _visibility() -> void:
	if not is_visible_in_tree():
		if edit_control != null: edit_control.cancel()
		set_process(false)
		orbiting = false
		panning = false
		if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else: _render_once()

func _camera_input(event: InputEvent) -> void:
	if edit_control != null and edit_control.input_event(event):
		surface.accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if panning and not event.pressed: view_moved.emit(Vector2(focus.x,focus.z))
			panning = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			view_size = clampf(view_size*(.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/.85),12,100)
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
	set_process(false)
	if timer != null: timer.stop()
	if worker_pid > 0 and OS.is_process_running(worker_pid): OS.kill(worker_pid)
	worker_pid = -1
	# Drain an already-started resource read before releasing the panel. Otherwise
	# a threaded request that nobody collects can retain its snapshot resources.
	if not loading_path.is_empty():
		var state := ResourceLoader.load_threaded_get_status(loading_path)
		if state in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
			ResourceLoader.load_threaded_get(loading_path)
		loading_path = ""
	_cleanup_snapshots(2147483647)
	if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _heartbeat() -> void:
	var file := FileAccess.open(folder+"/heartbeat",FileAccess.WRITE)
	if file != null: file.store_string("active")
	heartbeat_at = Time.get_ticks_msec()

func _cleanup_snapshots(older_than: int) -> void:
	if not folder.begins_with("res://.godot/world_live_%d_" % OS.get_process_id()): return
	for filename in DirAccess.get_files_at(folder):
		if not filename.begins_with("view_") or not filename.ends_with(".scn"): continue
		if filename.trim_prefix("view_").trim_suffix(".scn").to_int() >= older_than: continue
		var path := folder+"/"+filename
		if path != loading_path: DirAccess.remove_absolute(path)

func _exit_tree() -> void: stop()
