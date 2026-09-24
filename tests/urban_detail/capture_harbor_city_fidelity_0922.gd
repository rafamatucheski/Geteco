extends SceneTree
## Isolated visual validator for the V1/V2 city comparison. Requires --no-save,
## writes only to the explicit --out-dir supplied by the caller, and is not a
## benchmark.

var region: Node3D
var camera: Camera3D
var out_dir := ""
var only := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args:
		push_error("Harbor city capture refuses to run without --no-save")
		quit(2)
		return
	for arg in args:
		if arg.begins_with("--out-dir="): out_dir=arg.trim_prefix("--out-dir=").trim_suffix("/")
		if arg.begins_with("--only="): only=arg.trim_prefix("--only=")
	if out_dir.is_empty() or not DirAccess.dir_exists_absolute(out_dir):
		push_error("Harbor city capture requires an existing isolated --out-dir")
		quit(2)
		return
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size=Vector2i(2000,1100)
	var fixture:=Node3D.new()
	root.add_child(fixture)
	var world_environment:=WorldEnvironment.new()
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("82939a")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("d5d1bd")
	environment.ambient_light_energy=.92
	world_environment.environment=environment
	fixture.add_child(world_environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-62,-32,0)
	sun.light_color=Color("ffe0ac")
	sun.light_energy=1.35
	sun.shadow_enabled=true
	fixture.add_child(sun)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees=Vector3(-90,0,0)
	camera.near=.1
	camera.far=400
	fixture.add_child(camera)
	camera.make_current()
	region=preload("res://world/regions/NativeRegion.gd").build_region("harbor",Vector3(1030,0,1800)/16.0)
	fixture.add_child(region)
	for frame in 40: await process_frame
	if only=="bridge":
		await _shot("v2-pair-bridge",Vector2(3790,420),1100.0/.90/16.0)
		await _shot_oblique("v2-bridge-oblique",Vector2(3790,400),48.0)
		quit(0)
		return
	await _shot("v2-westgate-commercial",Vector2(1030,1200),1100.0/.72/16.0)
	await _shot("v2-market",Vector2(1620,900),1100.0/.85/16.0)
	await _shot("v2-northbank",Vector2(5530,1230),1100.0/.60/16.0)
	await _shot("v2-north-expansion",Vector2(5550,-1070),1100.0/.47/16.0)
	await _shot("v2-north-highway",Vector2(6000,-3400),160.0)
	await _shot("v2-cobra",Vector2(7700,1700),1100.0/.45/16.0)
	await _shot("v2-south-port",Vector2(4750,4450),1100.0/.36/16.0)
	await _shot_oblique("v2-westgate-commercial-oblique",Vector2(830,890),34.0)
	await _shot_oblique("v2-market-oblique",Vector2(1750,665),38.0)
	await _shot_oblique("v2-cobra-oblique",Vector2(7700,1700),52.0)
	await _shot_oblique("v2-south-port-oblique",Vector2(4750,4450),62.0)
	# Exact centers and apparent scales used by the productive V1 captures.
	for shot in [
		["market",Vector2(1620,900),.85],["port",Vector2(3050,1380),.60],
		["garage",Vector2(1030,1800),.90],["bridge",Vector2(3790,420),.90],
		["northbank",Vector2(5530,1230),.60],["viaduct",Vector2(2110,1050),.90],
		["tunnel",Vector2(3100,2870),.75],["alleys",Vector2(850,840),1.0],
		["local-streets",Vector2(5100,1470),.72],["north-expansion",Vector2(5550,-1070),.47],
		["highway",Vector2(6000,-2990),.36],["gateway-entrance",Vector2(6000,-1960),.82],
		["ammunation",Vector2(1550,140),1.20],["northstar",Vector2(3570,1500),.55],
		["south-port",Vector2(4750,4450),.36],["salvage",Vector2(-750,550),.80],
		["cemetery",Vector2(-650,1740),.70],["cobra",Vector2(7700,1700),.50],
		["access-port-boss",Vector2(5515,5870),1.0],["access-sewer",Vector2(1182,2114),1.65],
		["restaurant-anchor",Vector2(620,1132),1.55],["restaurant-tideline",Vector2(5790,1644),1.55],
		["restaurant-early-shift",Vector2(6200,-1238),1.55],
	]:
		await _shot("v2-pair-%s"%shot[0],shot[1],1100.0/float(shot[2])/16.0)
	quit(0)


func _shot(label: String, source_center: Vector2, size: float) -> void:
	var point:=Vector3(source_center.x/16.0,0,source_center.y/16.0)
	region.set_focus(point)
	for frame in 32: await process_frame
	_ensure_capture_coverage(point,size)
	camera.size=size
	camera.position=point+Vector3(0,180,0)
	camera.rotation_degrees=Vector3(-90,0,0)
	camera.reset_physics_interpolation()
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var path:="%s/%s.png"%[out_dir,label]
	var result:=root.get_texture().get_image().save_png(path)
	assert(result==OK)
	print("HARBOR_CITY_CAPTURE ",path)


func _shot_oblique(label: String, source_center: Vector2, size: float) -> void:
	var point:=Vector3(source_center.x/16.0,0,source_center.y/16.0)
	region.set_focus(point)
	for frame in 32: await process_frame
	_ensure_capture_coverage(point,size)
	camera.size=size
	camera.position=point+Vector3(0,28,22)
	camera.look_at(point)
	camera.reset_physics_interpolation()
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var path:="%s/%s.png"%[out_dir,label]
	var result:=root.get_texture().get_image().save_png(path)
	assert(result==OK)
	print("HARBOR_CITY_CAPTURE ",path)


func _ensure_capture_coverage(point: Vector3,size: float)->void:
	# The production camera is capped at 52 m and is fully covered by the normal
	# 3x3 residency contract. Wide V1 comparison shots exceed that gameplay view;
	# mount every cell visible to this isolated validator so streaming is not
	# mistaken for missing source geometry.
	var half_z:=size*.5
	var half_x:=half_z*float(root.size.x)/float(root.size.y)
	var minimum:=Vector2(point.x-half_x,point.z-half_z)
	var maximum:=Vector2(point.x+half_x,point.z+half_z)
	for x in range(floori(minimum.x/64.0),floori(maximum.x/64.0)+1):
		for z in range(floori(minimum.y/64.0),floori(maximum.y/64.0)+1):
			var key:=Vector2i(x,z)
			if not region.chunks.has(key): region._build_chunk(key)
