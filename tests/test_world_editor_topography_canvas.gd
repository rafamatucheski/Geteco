extends SceneTree
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var canvas := CANVAS.new()
	root.add_child(canvas)
	canvas.size = Vector2(800,600)
	canvas.zoom = .1
	canvas.center = Vector2(20,20)
	var image := Image.create_empty(4,4,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(1,1,Color("9bb29c"))
	var texture := ImageTexture.create_from_image(image)
	var owner := "piece/course"
	canvas.objects[owner] = {"id":owner,"type":"piece","position":[20,20],"size":[40,40],"parts":[[0,0,40,40,3,"859591",[[0,0],[40,0],[40,40],[0,40]],true],[10,10,2,2,4,"aabbcc"]]}
	canvas.rebuild_context()
	var before := canvas.overview_revision
	canvas.set_terrain_topography("mountain",[{"texture":texture,"bounds":[640,-384,64,64],"source_ids":["piece/mountain"]}])
	check(canvas.overview_revision==before,"An inactive map tile does not invalidate the active map")
	check(canvas.terrain_topography_tiles().is_empty(),"Cached tiles stay in their own map")
	var front := {owner:{"parts":[[10,10,2,2,4,"aabbcc"]]}}
	canvas.set_terrain_topography("harbor",[{"texture":texture,"bounds":[0,0,64,64],"source_ids":[owner],"foreground":front},{"texture":texture,"bounds":[0,0,-1,64]},{"bounds":[0,0,64,64]}])
	check(canvas.terrain_topography_tiles().size()==1,"Invalid tile bounds or missing textures are rejected")
	check(canvas.overview_revision>before,"New terrain invalidates the retained panorama")
	var tile: Dictionary = canvas.terrain_topography_tiles()[0]
	check(tile.bounds==Rect2(0,0,64,64),"Tile bounds remain exact world coordinates")
	check(tile.texture==texture and image.get_pixel(0,0).a==0,"Raster alpha preserves the real terrain boundary")
	check(canvas.world_bounds().encloses(Rect2(0,0,64,64)),"Fit world includes the raster's real extent")
	check(canvas._overview_mesh()==null,"The flat owner footprint does not cover the topography")
	canvas._rebuild_context_mesh([0,1])
	var replacement: ArrayMesh = canvas.terrain_topography_foreground_meshes.harbor
	check(canvas.context_mesh==null and replacement!=null and replacement.surface_get_array_len(0)==6,"Only terrain is replaced; furniture remains in the separate foreground mesh")
	check(canvas.context_parts.size()==2 and canvas.pick(canvas.screen(Vector2(5,5)))==owner,"Raster replacement preserves precise editing and picking data")
	canvas.queue_redraw()
	for frame in 3: await process_frame
	var records := canvas.overview_record_count
	canvas.center += Vector2(10,5)
	canvas.zoom = .12
	canvas.queue_redraw()
	for frame in 2: await process_frame
	check(canvas.overview_record_count==records,"Terrain tiles remain retained during camera movement")
	canvas.set_terrain_topography_visible(false)
	check(canvas.terrain_topography_tiles().is_empty(),"Interior mode hides exterior terrain tiles")
	check(canvas._overview_mesh()!=null,"Hiding topography restores original context rendering")
	canvas.set_terrain_topography_visible(true)
	canvas.region = "mountain"
	check(canvas.terrain_topography_tiles()[0].bounds==Rect2(640,-384,64,64),"Changing maps selects that map's cached bounds")
	canvas.free()
	print("WORLD_EDITOR_TOPOGRAPHY_CANVAS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
