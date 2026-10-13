extends SceneTree
## Persistent, headless geometry builder. Never starts gameplay or resolves a save.
const DATA := preload("res://world/editing/WorldEditData.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const GARAGE_FACADE := preload("res://assets/maciota/GarageFacade.gd")
var folder := ""
var last_revision := 0
var parent_pid := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--folder="): folder = arg.trim_prefix("--folder=")
		if arg.begins_with("--parent="): parent_pid = arg.trim_prefix("--parent=").to_int()
	if not folder.begins_with("res://.godot/world_live_") or parent_pid <= 0: quit(2); return
	Engine.max_fps = 30
	Engine.set_meta("geteco_live_preview_build",true)
	while parent_alive() and not FileAccess.file_exists(folder+"/stop"):
		var request := read_json(folder+"/request.json")
		if int(request.get("revision",0)) > last_revision:
			last_revision = int(request.revision)
			await build(request)
		await create_timer(.1).timeout
	quit()

func parent_alive() -> bool:
	# On Windows OS.is_process_running() tracks spawned children, not the parent.
	return Time.get_unix_time_from_system()-FileAccess.get_modified_time(folder+"/heartbeat") < 60

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func build(request: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var error := DATA.validate_document(request.get("document",{}))
	if not error.is_empty(): respond({"revision":last_revision,"error":error}); return
	var at: Array = request.get("focus",[45,110])
	var focus := Vector3(float(at[0]),0,float(at[1]))
	var area := str(request.get("area","harbor"))
	if area not in ["harbor","mountain","desert"]: respond({"revision":last_revision,"error":"Região inválida"}); return
	Engine.set_meta("geteco_world_edit_document",request.document)
	var region: Node3D = REGION.build_region(area,focus)
	if region==null:
		respond({"revision":last_revision,"error":"O cenário tem erros de script. Corrija-os antes de atualizar a prévia."})
		return
	root.add_child(region)
	if region.terrain != null: focus.y = region.terrain.surface_height_at(Vector2(focus.x,focus.z))
	elif area == "desert": focus.y = region._ground_height(Vector2(focus.x,focus.z))
	var radius := int(request.get("radius",0))
	if radius != 0 and not await load_radius(region,area,focus,radius): region.free(); return
	for i in 1800:
		await process_frame
		if region.is_streaming_idle(): break
		if FileAccess.file_exists(folder+"/stop") or not parent_alive(): region.free(); return
	if not region.is_streaming_idle():
		region.free()
		respond({"revision":last_revision,"error":"A região não terminou de carregar."})
		return
	# ProductionWorld owns this facade separately from NativeRegion. Include only
	# its authored exterior here; never instantiate the garage gameplay/interior.
	if area == "harbor":
		var transit := preload("res://runtime/UrbanTransitPresentation.gd").new()
		transit.configure(null)
		for definition in transit.definitions:
			if definition.get("deleted",false): continue
			if (definition.position as Vector3).distance_to(focus) <= transit.UNLOAD_DISTANCE:
				transit.build_geometry(region,definition)
		transit.free()
		var garage := GARAGE_FACADE.new()
		garage.name = "MaciotaFacade"
		# ProductionWorld exterior_origin plus MaciotaPlace's facade offset.
		garage.position = preload("res://world/maciota/MaciotaPlace.gd").INDUSTRIAL_ORIGIN+Vector3(-.5,0,0)
		garage.set_meta("editor_id","building/Garage")
		region.add_child(garage)
	# Duplicate built geometry, then strip behaviour before it can enter the editor.
	preload("res://addons/geteco_world_editor/WorldSessionContext.gd").build_preview(region,area,focus)
	# Lugares da sessão (Vértice, Torque, descida...) também viram peças, como no jogo.
	var session_edits := preload("res://world/editing/WorldSessionEdits.gd")
	var area_edits: Dictionary = request.document.get("regions",{}).get(area,{})
	for place_node in region.get_children():
		if not place_node is Node3D: continue
		var place: Array = session_edits.place_of(place_node)
		if not place.is_empty() and place[0] == area: preload("res://world/editing/WorldUnits.gd").finalize_session(place_node,area,str(place[1]),area_edits,Callable())
	# Mobiliário urbano em lote: uma malha por instância para a visão 3D poder selecionar.
	preload("res://world/editing/WorldPlacements.gd").explode_preview(region)
	# Peças automáticas (pedra, poste, fio...): o editor as lista a partir daqui, sem catálogo.
	var units: Array = preload("res://world/editing/WorldUnits.gd").manifest(region)
	var snapshot: Node3D = region.duplicate(0)
	snapshot.name = "WorldPreviewGeometry"
	clean(snapshot,snapshot)
	snapshot.process_mode = Node.PROCESS_MODE_DISABLED
	var packed := PackedScene.new()
	var packed_error := packed.pack(snapshot)
	var path := folder+"/view_%d.scn" % last_revision
	if packed_error == OK: packed_error = ResourceSaver.save(packed,path)
	snapshot.free()
	region.free()
	await process_frame
	if packed_error != OK: respond({"revision":last_revision,"error":"Não foi possível preparar a visão 3D."}); return
	respond({"revision":last_revision,"path":path,"height":focus.y,"build_ms":Time.get_ticks_msec()-started,"error":"","units":units,"area":area,"radius":int(request.get("radius",0))})

## Alcance maior que o padrão: `radius` células ao redor do foco (3×3 é o normal) ou, com -1, a região
## inteira. Constrói tudo de uma vez e impede o descarregamento; o custo cresce com o número de chunks.
func load_radius(region: Node3D, area: String, focus: Vector3, radius: int) -> bool:
	var cell_size := 96.0 if area == "desert" else 64.0
	var center := Vector2i(floori(focus.x/cell_size),floori(focus.z/cell_size))
	var low := center-Vector2i.ONE*radius
	var high := center+Vector2i.ONE*radius
	if radius < 0:
		if area == "desert":
			var bounds: Rect2 = region.LAYOUT.BOUNDS
			low = Vector2i(floori(bounds.position.x/cell_size),floori(bounds.position.y/cell_size))
			high = Vector2i(floori(bounds.end.x/cell_size),floori(bounds.end.y/cell_size))
		else:
			var first := true
			for key in region.records:
				if first: low = key; high = key; first = false
				else:
					low = Vector2i(mini(low.x,key.x),mini(low.y,key.y))
					high = Vector2i(maxi(high.x,key.x),maxi(high.y,key.y))
			low -= Vector2i.ONE
			high += Vector2i.ONE
	region.set("retention_radius",100000)
	var built := 0
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			var key := Vector2i(x,z)
			if area == "desert":
				region._ensure_chunk_surfaces(key)
				for guard in 4000:
					if region.build_jobs.is_empty(): break
					region._run_build_job(region.build_jobs[0],INF)
			else: region._ensure_chunk(key)
			built += 1
			if built%6 == 0:
				await process_frame
				if FileAccess.file_exists(folder+"/stop") or not parent_alive(): return false
	return true

func clean(node: Node, owner_root: Node) -> void:
	if node.has_meta("world_edit_piece_id"):
		node.set_meta("editor_id","piece/"+str(node.get_meta("world_edit_piece_id")))
	node.set_script(null)
	node.scene_file_path = ""
	if node != owner_root: node.owner = owner_root
	for key in node.get_meta_list():
		if key not in [&"editor_id",&"preview_instance_transforms",&"preview_instance_colors"]: node.remove_meta(key)
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is AnimationPlayer: node.stop()
	if node is GPUParticles3D or node is CPUParticles3D: node.emitting = false
	for child in node.get_children(): clean(child,owner_root)

func respond(value: Dictionary) -> void:
	var file := FileAccess.open(folder+"/response.tmp",FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(folder+"/response.tmp",folder+"/response.json")
