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
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: push_error(message); quit(1)
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
	var controller := {"state":state,"world":world,"region":source}
	var atlas := ATLAS.new(); atlas.collect(controller)
	check(atlas.region_bounds.size()==3,"all prepared regions visible without mounting")
	check(atlas.markers.any(func(m): return m.kind=="lock"),"unfinished campaign marks north gate")
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
	for kind in ["plane","zoo","jeep","race","mine","ski","lift","bank","hospital","weapons"]:
		check(atlas.markers.any(func(m): return m.kind==kind),"specific symbol: "+kind)
	var before: Array=[]
	for road in atlas.roads: before.append(road.points)
	check(state.restore_snapshot(FIXTURE.full_snapshot(Vector3(80,0,80),true)),"completed state")
	var unlocked := ATLAS.new(); unlocked.collect(controller)
	check(not unlocked.markers.any(func(m): return m.id=="north_gate"),"gate follows actual final campaign completion")
	check(unlocked.roads.size()==before.size(),"unlock does not change east mountain access")
	for i in before.size(): check(before[i]==unlocked.roads[i].points,"map never mutates progression geometry")
	for active in ["mountain","desert"]:
		state.region_id=active; controller.region=world.production._region_cache[active]
		var from_region := ATLAS.new(); from_region.collect(controller)
		check(from_region.roads.size()==unlocked.roads.size(),"same full atlas from "+active)
		check(from_region.markers.size()==unlocked.markers.size(),"same places from "+active)
	for region in world.production._region_cache.values(): region.free()
	world.free()
	print("WORLD_MAP_ATLAS PASS ",checks," checks")
	quit()
