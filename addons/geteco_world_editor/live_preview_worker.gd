extends SceneTree
## Persistent, headless geometry builder. Never starts gameplay or resolves a save.
const DATA := preload("res://world/editing/WorldEditData.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const GARAGE_FACADE := preload("res://assets/maciota/GarageFacade.gd")
var folder := ""
var last_revision := 0
var parent_pid := 0
var progress_at := 0

func cancelled() -> bool:
	return FileAccess.file_exists(folder+"/stop") or not parent_alive() or int(read_json(folder+"/request.json").get("revision",last_revision)) > last_revision

func progress(phase: String, done := 0, total := 0, force := false) -> void:
	var now := Time.get_ticks_msec()
	if not force and now-progress_at < 300: return
	progress_at = now
	var file := FileAccess.open(folder+"/progress.tmp",FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"revision":last_revision,"phase":phase,"done":done,"total":total,"updated":now}))
	file.close()
	DirAccess.rename_absolute(folder+"/progress.tmp",folder+"/progress.json")
	if force: print("WORLD_PREVIEW revision=",last_revision," phase=",phase," cells=",done,"/",total)
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
	return preload("res://addons/geteco_world_editor/WorldPreviewProtocol.gd").read(path).data

func build(request: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	progress("Preparando dados",0,0,true)
	var error := DATA.validate_document(request.get("document",{}))
	if not error.is_empty(): respond({"revision":last_revision,"error":error}); return
	var at: Array = request.get("focus",[45,110])
	var focus := Vector3(float(at[0]),0,float(at[1]))
	var area := str(request.get("area","harbor"))
	if area not in ["harbor","mountain","desert"]: respond({"revision":last_revision,"error":"Região inválida"}); return
	Engine.set_meta("geteco_world_edit_document",request.document)
	if not str(request.get("interior_id","")).is_empty():
		await build_interior(request)
		return
	var region: Node3D = REGION.build_region(area,focus)
	if region==null:
		respond({"revision":last_revision,"error":"O cenário tem erros de script. Corrija-os antes de atualizar a prévia."})
		return
	root.add_child(region)
	if cancelled(): region.free(); return
	if region.terrain != null: focus.y = region.terrain.surface_height_at(Vector2(focus.x,focus.z))
	elif area == "desert": focus.y = region._ground_height(Vector2(focus.x,focus.z))
	var radius := int(request.get("radius",0))
	if radius != 0 and not await load_radius(region,area,focus,radius): region.free(); return
	progress("Finalizando cenário",0,0,true)
	for i in 1800:
		await process_frame
		if region.is_streaming_idle(): break
		progress("Finalizando cenário")
		if cancelled(): region.free(); return
	if not region.is_streaming_idle():
		region.free()
		respond({"revision":last_revision,"error":"A região não terminou de carregar."})
		return
	finish_static_builders(region)
	# ProductionWorld owns this facade separately from NativeRegion. Include only
	# its authored exterior here; never instantiate the garage gameplay/interior.
	if area == "harbor":
		var transit := preload("res://runtime/UrbanTransitPresentation.gd").new()
		transit.configure(null)
		for definition in transit.definitions:
			if definition.get("deleted",false): continue
			if preload("res://addons/geteco_world_editor/WorldSessionContext.gd").preview_in_range(focus,definition.position,transit.UNLOAD_DISTANCE,radius,area):
				transit.build_geometry(region,definition)
		transit.free()
		var garage := GARAGE_FACADE.new()
		garage.name = "MaciotaFacade"
		# ProductionWorld exterior_origin plus MaciotaPlace's facade offset.
		garage.position = preload("res://world/maciota/MaciotaPlace.gd").INDUSTRIAL_ORIGIN+Vector3(-.5,0,0)
		garage.set_meta("editor_id","building/Garage")
		region.add_child(garage)
	# Duplicate built geometry, then strip behaviour before it can enter the editor.
	progress("Montando locais e acessos",0,0,true)
	preload("res://addons/geteco_world_editor/WorldSessionContext.gd").build_preview(region,area,focus,radius)
	finish_static_builders(region)
	if cancelled(): region.free(); return
	# Lugares da sessão (Vértice, Torque, descida...) também viram peças, como no jogo.
	var session_edits := preload("res://world/editing/WorldSessionEdits.gd")
	var area_edits: Dictionary = request.document.get("regions",{}).get(area,{})
	session_edits.finalize_places(region,area,area_edits)
	# Mobiliário urbano em lote: uma malha por instância para a visão 3D poder selecionar.
	preload("res://world/editing/WorldPlacements.gd").explode_preview(region)
	progress("Indexando objetos editáveis",0,0,true)
	tag_terrain(region)
	# Peças automáticas (pedra, poste, fio...): o editor as lista a partir daqui, sem catálogo.
	var units: Array = preload("res://world/editing/WorldUnits.gd").manifest(region)
	preload("res://addons/geteco_world_editor/WorldPreviewUnitFootprints.gd").refine(region,units)
	var ground := Callable(region.terrain,"surface_height_at") if region.terrain != null else (Callable(region,"_ground_height") if area == "desert" else Callable())
	tag_ground(region,ground)
	var terrain_paths: Array[String] = []
	collect_terrain_paths(region,region,terrain_paths)
	var topography: Array = await preload("res://addons/geteco_world_editor/WorldTerrainMap.gd").write(region,terrain_paths,folder,last_revision,area,self,progress,cancelled,request.document)
	if cancelled(): region.free(); return
	if not topography.is_empty():
		topography[0]["foreground"] = preload("res://addons/geteco_world_editor/WorldContextCatalog.gd").terrain_foreground(region)
		topography[0]["units"] = units
		progress("Conciliando catálogo 2D",0,0,true)
		preload("res://addons/geteco_world_editor/WorldTerrainLegacy.gd").bind(region,area,topography,units)
	var topography_revision := str(request.get("terrain_revision",preload("res://addons/geteco_world_editor/WorldTerrainMap.gd").revision(request.document,area)))
	if request.get("topography_only",false):
		region.free()
		respond({"revision":last_revision,"error":"","topography_only":true,"topography":topography,"terrain_revision":topography_revision,"area":area,"radius":radius,"build_ms":Time.get_ticks_msec()-started})
		return
	var bounds: Array = preview_bounds(region,area,units,ground) if radius < 0 else []
	var snapshot: Node3D = region.duplicate(0)
	snapshot.name = "WorldPreviewGeometry"
	clean(snapshot,snapshot)
	snapshot.process_mode = Node.PROCESS_MODE_DISABLED
	progress("Preparando geometria 3D",0,0,true)
	var export_result: Dictionary = await preload("res://addons/geteco_world_editor/WorldPreviewParts.gd").write(snapshot,folder,last_revision,self,progress,cancelled)
	snapshot.free()
	region.free()
	await process_frame
	if cancelled(): return
	if int(export_result.error) != OK: respond({"revision":last_revision,"error":"Não foi possível preparar a visão 3D (erro %d)." % int(export_result.error)}); return
	respond({"revision":last_revision,"path":export_result.path,"parts":export_result.parts,"nodes":export_result.nodes,"bounds":bounds,"height":focus.y,"build_ms":Time.get_ticks_msec()-started,"error":"","units":units,"terrain_paths":terrain_paths,"topography":topography,"terrain_revision":topography_revision,"area":area,"radius":int(request.get("radius",0))})

func finish_static_builders(node: Node) -> void:
	# Region streaming can be idle while a procedural course is still assembling.
	# The editor snapshot must include those surfaces rather than freeze it empty.
	if node.has_method("finish_build"): node.call("finish_build")
	for child in node.get_children(): finish_static_builders(child)

func tag_terrain(node: Node) -> void:
	if node is MeshInstance3D and (str(node.name) in ["QuarryHills","DirtTrack","SculptedBanks","MountainTerrain","Land","LandOutsideUnifiedBridge","SerenoForestFloor","OriginalPortSurface"] or str(node.name).begins_with("Canyon_") or node.get_meta("desert_base_ground",false)):
		node.set_meta("editor_terrain_surface",true)
	for child in node.get_children(): tag_terrain(child)

func collect_terrain_paths(node: Node, snapshot_root: Node, result: Array[String]) -> void:
	if node is Node3D and not node.visible: return
	if node is MeshInstance3D and node.get_meta("editor_terrain_surface",false) and not node.get_meta("desert_base_ground",false): result.append(str(snapshot_root.get_path_to(node)))
	for child in node.get_children(): collect_terrain_paths(child,snapshot_root,result)

func build_interior(request: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var id := str(request.interior_id)
	progress("Montando interior · "+id,0,0,true)
	var holder := Node3D.new()
	root.add_child(holder)
	var built := preload("res://addons/geteco_world_editor/WorldInteriorCatalog.gd").build_preview(holder,id,int(request.get("interior_floor",0)))
	if not str(built.get("error","")).is_empty():
		holder.free()
		respond({"revision":last_revision,"interior_id":id,"error":str(built.error),"interior_validation_error":str(built.error)})
		return
	var edits = load("res://world/editing/WorldInteriorEdits.gd")
	if edits == null:
		holder.free()
		respond({"revision":last_revision,"interior_id":id,"error":"O adaptador de interiores não está disponível.","interior_validation_error":"O adaptador de interiores não está disponível."})
		return
	var prepared: Dictionary = edits.prepare(built.place,id,request.document)
	# Inventory uses original sibling indices, including protected residents. Remove
	# actors only after permanent editor identities match the gameplay scene.
	preload("res://addons/geteco_world_editor/WorldInteriorCatalog.gd").strip_actors(built.root)
	var target: Vector3 = built.root.to_local(built.place.camera_target)
	var camera_size: float = built.place.camera_size
	var snapshot: Node3D = built.root.duplicate(0)
	# Each selected storey uses room-local editor coordinates. Its authored
	# elevation returns naturally when runtime mounts it on the building floor.
	snapshot.transform = Transform3D.IDENTITY
	snapshot.name = "WorldPreviewGeometry"
	clean(snapshot,snapshot)
	snapshot.process_mode = Node.PROCESS_MODE_DISABLED
	var result: Dictionary = await preload("res://addons/geteco_world_editor/WorldPreviewParts.gd").write(snapshot,folder,last_revision,self,progress,cancelled)
	snapshot.free()
	holder.free()
	if cancelled(): return
	if int(result.error) != OK:
		respond({"revision":last_revision,"interior_id":id,"error":"Não foi possível preparar a sala em 3D.","interior_validation_error":"Não foi possível preparar a sala em 3D."})
		return
	respond({"revision":last_revision,"path":result.path,"parts":result.parts,"nodes":result.nodes,"height":0.0,"build_ms":Time.get_ticks_msec()-started,"error":"","units":[],"area":str(request.get("area","harbor")),"radius":int(request.get("radius",0)),"interior_id":id,"interior_floor":int(request.get("interior_floor",0)),"interior_units":prepared.get("rows",[]),"interior_bounds":prepared.get("bounds",[]),"interior_spawn":prepared.get("spawn",[]),"interior_validation_error":str(prepared.get("error","")),"camera_focus":[target.x,target.y,target.z],"camera_size":camera_size})

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
	var total := (high.x-low.x+1)*(high.y-low.y+1)
	progress("Construindo trechos",0,total,true)
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			var key := Vector2i(x,z)
			if area == "desert":
				region._ensure_chunk_surfaces(key)
				# A cell can contain thousands of pieces. Yield during its build so
				# progress and cancellation remain observable, even on a full map.
				while not region.build_jobs.is_empty():
					var slice_started := Time.get_ticks_msec()
					while not region.build_jobs.is_empty() and Time.get_ticks_msec()-slice_started < 15:
						region._run_build_job(region.build_jobs[0],4000.0)
					progress("Construindo trechos",built,total)
					await process_frame
					if cancelled(): return false
			else: region._ensure_chunk(key)
			built += 1
			progress("Construindo trechos",built,total)
			await process_frame
			if cancelled(): return false
	progress("Construindo trechos",built,total,true)
	return true

func tag_ground(node: Node, ground: Callable) -> void:
	if node is Node3D and (node.has_meta("editor_id") or node.has_meta("world_edit_piece_id")):
		var at: Vector2 = node.get_meta("world_snapshot_ground_anchor",Vector2(node.global_position.x,node.global_position.z))
		node.set_meta("world_snapshot_ground_height",float(ground.call(at)) if ground.is_valid() else 0.0)
	for child in node.get_children(): tag_ground(child,ground)

func preview_bounds(region: Node3D, area: String, units: Array, ground: Callable) -> Array:
	# Geography comes from authored cells and sites, never the ocean/horizon mesh.
	var bounds: Rect2 = region.LAYOUT.BOUNDS if area == "desert" else preload("res://world/regions/DeveloperViewCells.gd").record_bounds(region.records,64.0)
	var low := -8.0
	var high := 64.0
	var rows: Array = units.duplicate()
	if area in ["harbor","mountain"]:
		var supplement := preload("res://addons/geteco_world_editor/WorldSessionContext.gd").read()
		rows.append_array(supplement.get("context" if area == "harbor" else "mountain_context",{}).values())
	for row in rows:
		if row.get("position") is Array and row.get("size") is Array:
			var at := DATA.point(row.position)
			var size := DATA.point(row.size)
			var rect := Rect2(at-size*.5,size)
			bounds = bounds.merge(rect) if bounds.has_area() else rect
		high = maxf(high,float(row.get("selection_height",0.0)))
		for part in row.get("parts",[]):
			if part is Array and part.size() > 4: high = maxf(high,float(part[4]))
	if ground.is_valid():
		for x in 17:
			for z in 17:
				var at := bounds.position+bounds.size*Vector2(x/16.0,z/16.0)
				var height := float(ground.call(at))
				low = minf(low,height-8.0)
				high = maxf(high,height+48.0)
	return [bounds.position.x,low,bounds.position.y,bounds.size.x,high-low,bounds.size.y]

func clean(node: Node, owner_root: Node) -> void:
	if node is StaticBody3D:
		node.set_meta("world_snapshot_collision_layer",node.collision_layer)
		node.set_meta("world_snapshot_collision_mask",node.collision_mask)
	if node.has_meta("world_edit_piece_id"):
		node.set_meta("editor_id","piece/"+str(node.get_meta("world_edit_piece_id")))
	node.set_script(null)
	node.scene_file_path = ""
	if node != owner_root: node.owner = owner_root
	for key in node.get_meta_list():
		if key not in [&"editor_id",&"preview_instance_transforms",&"preview_instance_colors",&"world_snapshot_collision_layer",&"world_snapshot_collision_mask",&"world_snapshot_ground_height",&"editor_terrain_surface"]: node.remove_meta(key)
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
	if DirAccess.rename_absolute(folder+"/response.tmp",folder+"/response.json") != OK:
		printerr("ERROR: Não foi possível publicar a geometria da prévia em "+folder)
		return
	# The host polls this tiny marker instead of reparsing a potentially enormous
	# scene manifest on every timer tick while the editor is idle.
	file = FileAccess.open(folder+"/response_ready.tmp",FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"revision":int(value.get("revision",0))}))
	file.close()
	DirAccess.rename_absolute(folder+"/response_ready.tmp",folder+"/response_ready.json")
