extends SceneTree
## Fast visual QA only: production MapUI and prepared production geography.
## Does not mount Main, chunks, traffic or the C# navigation runtime. No FPS claim.
const MAP := preload("res://ui/hud/MapUI.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const STATE := preload("res://runtime/GameState.gd")
const REGIONS := ["world","harbor","mountain","desert"]

class Production extends RefCounted:
	var regions := {}
	var _region_cache := {}
	var world_sea: Node3D

class World extends Node3D:
	var production := Production.new()
	var maciota_place: Node3D
	var player: Node3D

class Mission extends RefCounted:
	func target_position() -> Vector3: return Vector3.ZERO

class Session extends RefCounted:
	var modal := true
	var freight_active := false
	var desert = null
	var mission_world := Mission.new()
	func close_menu() -> void: modal=false
	func navigation_destination() -> Dictionary: return {}

var output := ""
var report := {}

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): fail("WORLD_MAP_DESIGN timeout",3))
	run.call_deferred()

func fail(message: String, code := 1) -> void:
	report.status="failed"; report.failure=message; save_report()
	push_error(message); quit(code)

func save_report() -> void:
	if output.is_empty(): return
	var file := FileAccess.open(output.path_join("capture-index.json"),FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify(report,"\t")); file.close()

func capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(label+".png"))
	if result!=OK: fail("WORLD_MAP_DESIGN capture failed: "+label); return
	report.captures.append(label+".png"); save_report()
	print("WORLD_MAP_DESIGN_CAPTURE ",label)

func focus_region(map, region: String) -> void:
	map.focus_region(region)
	map.center=map.target_center; map.zoom=map.target_zoom; map._redraw()

func marker_index(map, title: String) -> int:
	for i in map._markers.size():
		if map._markers[i].title==title: return i
	return -1

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args():
		fail("WORLD_MAP_DESIGN requires rendered Godot .NET and --no-save",2); return
	output=FIXTURE.output_dir("world-map-design")
	if output.is_empty(): fail("WORLD_MAP_DESIGN cannot create evidence directory"); return
	report={"status":"running","evidence_kind":"UI with real prepared geography","main_scene_loaded":false,"performance_valid":false,"limitations":"Visual QA of production MapUI only. No Main scene, live population, streaming, C# navigation or session-only activity markers. Use measure_world_map.gd for integration and performance.","engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"captures":[],"regions":{}}
	save_report()
	root.mode=Window.MODE_WINDOWED
	# Match the selected concept without changing the user's persisted language.
	TranslationServer.set_locale("pt_BR")
	root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720)
	var world := World.new(); root.add_child(world)
	world.player=Node3D.new(); world.add_child(world.player); world.player.position=Vector3(80,.12,80)
	var state := STATE.new()
	if not state.restore_snapshot(FIXTURE.full_snapshot(world.player.position,true)):
		fail("WORLD_MAP_DESIGN invalid isolated state"); return
	for id: String in ["harbor","mountain","desert"]:
		var region = EDITABLE.build_region(id)
		region.prepare_data()
		if region.is_inside_tree() or not region.chunks.is_empty():
			fail("WORLD_MAP_DESIGN unexpectedly mounted a region"); return
		world.production._region_cache[id]=region
		report.regions[id]={"roads":region.map_routes().size(),"entries":region.entries.size(),"mounted":false}
	# Mar do mundo (mundo orgânico, etapa 1): o mapa 3D reaproveita as malhas dele.
	var sea := preload("res://world/shape/WorldSea.gd").new()
	sea.configure(world.production)
	world.add_child(sea)
	await sea.build_sliced(self)
	world.production.world_sea = sea
	var map := MAP.new()
	map.controller={"state":state,"world":world,"region":world.production._region_cache.harbor,"session":Session.new()}
	var opened := Time.get_ticks_usec()
	root.add_child(map)
	# Primeira abertura monta o cache das malhas do 3D; as seguintes só recriam os nós.
	report.map_open_first_usec=Time.get_ticks_usec()-opened
	var again := MAP.new()
	again.controller=map.controller
	opened=Time.get_ticks_usec()
	root.add_child(again)
	report.map_open_cached_usec=Time.get_ticks_usec()-opened
	again.queue_free()
	print("WORLD_MAP_OPEN primeira %.1f ms, com cache %.1f ms" % [report.map_open_first_usec/1000.0, report.map_open_cached_usec/1000.0])
	report.relief={"preparation_usec":map.atlas.relief.preparation_usec,"triangle_count":map.atlas.relief.triangle_count}
	save_report()
	print("WORLD_MAP_DESIGN_READY ",output)
	for viewport_size: Vector2i in [Vector2i(1280,720),Vector2i(800,600)]:
		root.content_scale_size=viewport_size; root.size=viewport_size
		await process_frame
		await process_frame
		var suffix := "" if viewport_size.x==1280 else "-compact"
		for region: String in REGIONS:
			map.select_marker(-1); focus_region(map,region)
			await capture(("city" if region=="harbor" else region)+suffix)
			if region=="world": continue
			var title: String={"harbor":"Union","mountain":"Forja da Serra","desert":"Digo"}[region]
			var index := marker_index(map,title)
			if index<0: fail("WORLD_MAP_DESIGN missing authored marker: "+title); return
			map.select_marker(index)
			if region=="desert": await capture("desert-digo-region"+suffix)
			if region=="desert":
				map._mark_selected()
				await capture("desert-marked"+suffix)
				map._clear_waypoint()
			map._locate_selected(); map.center=map.target_center; map.zoom=map.target_zoom; map._redraw()
			await capture(region+"-selected"+suffix)
			var kind: String={"harbor":"hospital","mountain":"cave","desert":"workshop"}[region]
			map._set_filter(kind); focus_region(map,region)
			await capture(region+"-filtered"+suffix)
			if not map._legend.visible: map._toggle_filters()
			await capture(region+"-filters-open"+suffix)
			map._toggle_filters(); map._set_filter(kind)
	# Maquete 3D girada e a vista 2D de antes, no mundo inteiro.
	root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720)
	map.select_marker(-1); focus_region(map,"world")
	map._yaw=.55; map._redraw()
	await capture("world-3d-girado")
	map._yaw=0.0; map._set_3d(false); focus_region(map,"world")
	await capture("world-2d")
	map._set_3d(true)
	report.status="complete"; save_report()
	print("WORLD_MAP_DESIGN_DONE ",output)
	map.free()
	for region in world.production._region_cache.values(): region.free()
	world.free(); quit()
