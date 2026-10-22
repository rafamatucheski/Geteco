extends SceneTree
const NAV := preload("res://ui/v1/NavigationRoute.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")

class Production extends Node:
	var traffic_routes := ROUTES.new()
	var _route_cache := {}
	func _route_key() -> String: return "harbor"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var production := Production.new()
	root.add_child(production)
	var roads := [
		{"id":"coast","width":8,"points":PackedVector3Array([Vector3.ZERO,Vector3(50,0,0)])},
		{"id":"climb","width":8,"points":PackedVector3Array([Vector3(50,0,0),Vector3(50,30,100)])}
	]
	production.traffic_routes.configure([roads[0]])
	var all := ROUTES.new()
	all.configure(roads)
	production._route_cache["harbor,mountain"]={"traffic":[all.segments,all.vertices,all.edges,all._vertex_ids]}
	var source := NAV.source(production)
	assert(source.routes.vertices.size()>production.traffic_routes.vertices.size(),"GPS includes prepared unmounted mountain")
	assert(NAV.source(production).routes==source.routes,"the complete graph is retained between refreshes")
	var goal := NAV.goal_on_surface(source.routes,Vector2(50,90))
	assert(is_equal_approx(goal.y,27.0),"2D map pin resolves authored mountain altitude")
	var nav := NAV.new()
	nav.update(source.routes,source.revision,Vector3(10,0,0),goal,true,Vector3.RIGHT)
	assert(nav.points.size()>=3,"a pin produces a connected route around the corner")
	assert(nav.points[-1].is_equal_approx(Vector2(50,90)),"route reaches the selected road position")
	var before := nav.points.duplicate()
	assert(not nav.update(source.routes,source.revision,Vector3(10,0,0),goal,true,Vector3.RIGHT),"unchanged GPS does not rebuild a path")
	assert(nav.points==before and production.traffic_routes.vertices.size()==2,"navigation preserves resident traffic data")
	nav.clear()
	assert(nav.points.is_empty(),"clearing the destination clears the route")
	production.free()
	print("MAP_NAVIGATION_REVISION PASS 8 checks")
	quit()
