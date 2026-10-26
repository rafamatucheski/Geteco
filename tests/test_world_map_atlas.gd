extends SceneTree
const ATLAS := preload("res://ui/hud/WorldMapData.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
class Production extends RefCounted:
	var regions := {}
	var _region_cache := {}
class World extends Node:
	var production := Production.new()
	var maciota_place: Node3D
var checks := 0
var failures: Array[String]=[]
func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := World.new()
	var state := preload("res://runtime/GameState.gd").new()
	check(state.restore_snapshot(FIXTURE.full_snapshot(Vector3(80,0,80),false)),"valid isolated state")
	for id in ["harbor","mountain","desert"]:
		var region = preload("res://world/editing/EditableRegion.gd").build_region(id)
		region.prepare_data()
		world.production._region_cache[id]=region
	var source=world.production._region_cache.harbor
	var mountain=world.production._region_cache.mountain
	var forge_paths: Array=mountain.walkways.filter(func(path): return path.id=="mountain_forge_walk")
	check(forge_paths.size()==1,"retired zoo edit resolves to exactly one current forge approach")
	check(not mountain.walkways.any(func(path): return path.id=="mountain_zoo_walk"),"obsolete zoo path cannot return as a duplicate map road")
	if forge_paths.size()==1:
		var approach: Dictionary=preload("res://world/mountain_detail/forge/MountainForge.gd").approach()
		check(forge_paths[0].points[0].is_equal_approx(approach.points[0]) and forge_paths[0].points[-1].is_equal_approx(approach.points[-1]),"edited forge path joins the real road and forge gate")
		check(forge_paths[0].points.has(Vector3(716,0,-334)) and forge_paths[0].points.has(Vector3(716,0,-338)),"updating the path identity preserves authored control points")
	check(not mountain.roads.any(func(road): return str(road.id).contains("forge_walk")),"forge pedestrian approach must not become a traffic lane")
	var controller := {"state":state,"world":world,"region":source}
	var atlas := ATLAS.new(); atlas.collect(controller)
	check(atlas.region_bounds.size()==3,"all prepared regions visible without mounting")
	check(atlas.markers.any(func(m): return m.kind=="lock"),"unfinished campaign marks north gate")
	check(not atlas.relief_cache_hit,"a new world prepares its own relief package")
	var reopened := ATLAS.new(); reopened.collect(controller)
	check(reopened.relief_cache_hit and reopened.relief==atlas.relief,"reopening the same world data reuses the prepared relief instance")
	check(reopened.markers.any(func(m): return m.id=="north_gate"),"a relief cache hit still collects the current campaign markers")
	for id in world.production._region_cache:
		var region=world.production._region_cache[id]
		check(not region.is_inside_tree() and region.chunks.is_empty(),"map must not load distant chunks")
		for road in region.map_routes():
			var matches := atlas.roads.filter(func(r): return r.region==id and r.id==str(road.id))
			check(matches.size()==1,"each production road/path appears once: "+str(road.id))
			if matches.size()!=1: continue
			check(matches[0].points.size()==road.points.size(),"no invented/simplified road vertices")
			for i in road.points.size():
				if matches[0].points[i]!=ATLAS.planar(road.points[i]): check(false,"road coordinate drift"); break
	check(atlas.markers.any(func(m): return m.title=="Union" and m.kind=="clothing"),"authored clothing identity")
	for kind in ["plane","forge","jeep","race","mine","ski","lift","bank","hospital","weapons"]:
		check(atlas.markers.any(func(m): return m.kind==kind),"specific symbol: "+kind)
	var before: Array=[]
	for road in atlas.roads: before.append(road.points)
	check(state.restore_snapshot(FIXTURE.full_snapshot(Vector3(80,0,80),true)),"completed state")
	var unlocked := ATLAS.new(); unlocked.collect(controller)
	check(not unlocked.markers.any(func(m): return m.id=="north_gate"),"gate follows actual final campaign completion")
	check(atlas.markers.any(func(m): return m.id=="north_gate"),"recollecting progression does not mutate the prior map snapshot")
	var unlocked_reopened := ATLAS.new(); unlocked_reopened.collect(controller)
	check(unlocked_reopened.relief_cache_hit and unlocked_reopened.relief==unlocked.relief,"reopening the updated world also reuses its relief instance")
	check(not unlocked_reopened.markers.any(func(m): return m.id=="north_gate"),"cached presentation does not restore the completed campaign barrier")
	check(unlocked.roads.size()==before.size(),"unlock does not change east mountain access")
	for i in before.size(): check(before[i]==unlocked.roads[i].points,"map never mutates progression geometry")
	for active in ["mountain","desert"]:
		state.region_id=active; controller.region=world.production._region_cache[active]
		var from_region := ATLAS.new(); from_region.collect(controller)
		check(from_region.roads.size()==unlocked.roads.size(),"same full atlas from "+active)
		check(from_region.markers.size()==unlocked.markers.size(),"same places from "+active)
		check(from_region.relief_cache_hit and from_region.relief==unlocked.relief,"changing the active region reuses the same session relief: "+active)
	for region in world.production._region_cache.values():
		check(not region.is_inside_tree() and region.chunks.is_empty(),"repeated map collection never mounts regions or chunks")
	# The printed street map uses the same navigation snapshot without sampling
	# the terrain into a low-resolution relief or mounting any scene.
	var printed := ATLAS.new(); printed.collect(controller,false)
	check(printed.roads==unlocked.roads and printed.region_bounds==unlocked.region_bounds,"printed atlas preserves road and navigation coordinates")
	check(not printed.relief_cache_hit and printed.relief.triangle_count==0,"printed atlas skips unused height raster/relief preparation")
	var before_lands: Array=printed.lands.duplicate(true)
	var paper := preload("res://ui/hud/PaperAtlas.gd").new()
	paper.prepare(printed.lands)
	check(paper.regions.size()==3 and not paper.polygons.is_empty(),"printed atlas covers all three prepared regions")
	check(printed.lands==before_lands,"joining cartographic coastlines never edits world footprints")
	for region in world.production._region_cache.values():
		region.free()
	world.free()
	if failures.is_empty(): print("WORLD_MAP_ATLAS PASS ",checks," checks")
	else: print("WORLD_MAP_ATLAS FAIL ",failures.size()," of ",checks," checks")
	quit(0 if failures.is_empty() else 1)
