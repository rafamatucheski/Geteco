extends SceneTree

const PREVIEW := preload("res://world/harbor/HarborPreview.tscn")
const NETWORK := preload("res://world/harbor/HarborRoadNetwork.gd")
const BOUNDARY_AUDIT := preload("res://tests/support/RoadBoundaryAudit.gd")
var failures: Array[String] = []
var boundary_segments := 0
var closed_contours := 0
var captures_written := 0

class CurveFixture extends Node2D:
	func get_road_graph_definitions() -> Array[Dictionary]:
		return [
			{"id": "curved_street", "width": 72.0, "points": PackedVector2Array([Vector2(0, 0), Vector2(280, 110), Vector2(560, -110), Vector2(820, 0)]), "open_start": true, "open_end": true},
			{"id": "cross_street", "width": 72.0, "points": PackedVector2Array([Vector2(280, -260), Vector2(280, 380)]), "open_start": true, "open_end": true},
		]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := PREVIEW.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await physics_frame
	var network := scene.get_node("RoadNetwork")
	_audit_network(network, "district")
	var audit: Dictionary = network.get_road_edge_audit()
	_check(network.get_validation_errors().is_empty(), "Harbor graph and surface validation stays empty")
	_audit_secret_drive(scene, network, audit)
	_audit_court_seams(network)
	_audit_hole_and_island(network)
	_audit_alley_mouths(scene, network, audit)
	_check(not audit.openings.is_empty(), "Actual access/crosswalk openings must be represented")
	_check(network.find_children("*", "StaticBody2D", true, false).is_empty(), "Road contour pass must never add physical guard rails")
	var previous_builds := int(audit.builds)
	for _repeat in 3:
		var cached: Dictionary = network.get_road_edge_audit()
		_check(int(cached.builds) == previous_builds, "Union boundaries must stay cached while routing revision is unchanged")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_edges(scene)
		_check(captures_written==2,"Both rendered edge captures must complete without script errors")
	# The authored district is mostly straight; explicitly verify the same local
	# contour algorithm on a spline rather than assuming its curves are correct.
	var fixture := Node2D.new()
	root.add_child(fixture)
	var provider := CurveFixture.new()
	provider.name = "Curve"
	fixture.add_child(provider)
	var curved_network := NETWORK.new()
	curved_network.provider_paths = [NodePath("../Curve")]
	fixture.add_child(curved_network)
	await physics_frame
	_audit_network(curved_network, "curve")
	print("HARBOR_ROAD_EDGES_RESULT failures=%d boundary_segments=%d closed_contours=%d access_masks=%d" % [failures.size(), boundary_segments, closed_contours, audit.openings.size()])
	for failure in failures:
		push_error("HARBOR_ROAD_EDGES: " + failure)
	fixture.queue_free()
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _audit_network(network: Node2D, label: String) -> void:
	var audit: Dictionary = network.get_road_edge_audit()
	_check(audit.layers.size() == 2, label + " must outline both curb and outside sidewalk")
	for layer_name in audit.layers:
		var layer: Dictionary = audit.layers[layer_name]
		var regions := BOUNDARY_AUDIT.prepare(layer.sources)
		_check(int(layer.open_chains) == 0, "%s/%s has broken boundary chains: %d" % [label, layer_name, layer.open_chains])
		_check(not layer.contours.is_empty(), label + "/" + layer_name + " has no complete contours")
		for contour: PackedVector2Array in layer.contours:
			closed_contours += 1
			_check(contour.size() >= 4 and contour[0].distance_to(contour[-1]) < 0.02, "Union contour must close exactly")
			var polygon := contour.slice(0, contour.size() - 1)
			_check(not Geometry2D.triangulate_polygon(polygon).is_empty(), label + " boundary loop must be a valid simple polygon")
		for segment: PackedVector2Array in layer.segments:
			boundary_segments += 1
			var middle := (segment[0] + segment[1]) * 0.5
			_check(BOUNDARY_AUDIT.is_boundary(segment, regions), "%s/%s contains an internal seam or detached contour at %s" % [label, layer_name, middle])
		for segment: PackedVector2Array in layer.visible_segments:
			for index in range(segment.size() - 1):
				for fraction in [0.2, 0.5, 0.8]:
					var point := segment[index].lerp(segment[index + 1], float(fraction))
					_check(not _inside(point, layer.openings), "%s painted contour crosses an access, alley or zebra at %s" % [label, point])


func _audit_alley_mouths(scene: Node2D, network: Node2D, audit: Dictionary) -> void:
	var alleys := scene.get_node_or_null("Alleys") as Node2D
	_check(alleys != null, "Preview must include its pedestrian alley provider")
	if alleys == null:
		return
	var definitions: Array = alleys.call("get_alley_definitions")
	var roads: Array = scene.get_node("RoadLayout").get_road_graph_definitions()
	var checked := 0
	for alley in definitions:
		var points: PackedVector2Array = alley.points
		for endpoint in [points[0], points[-1]]:
			var point := network.to_local(alleys.to_global(endpoint))
			var joined := false
			for road in roads:
				var road_points: PackedVector2Array = road.points
				for index in range(road_points.size() - 1):
					var nearest := Geometry2D.get_closest_point_to_segment(point, road_points[index], road_points[index + 1])
					var offset := point.distance_to(nearest)
					var half_width := float(road.width) * 0.5
					if offset <= half_width + 8.0 or offset >= half_width + 42.0:
						continue
					joined = true
					var normal := (point - nearest).normalized()
					var mouth := nearest + normal * (half_width + 42.0)
					for segment: PackedVector2Array in audit.layers.sidewalk.visible_segments:
						var closest := Geometry2D.get_closest_point_to_segment(mouth, segment[0], segment[-1])
						_check(closest.distance_to(mouth) >= float(alley.width) * 0.45, "Sidewalk outline seals alley entrance %s" % mouth)
					# The extra footway masks must not reach the asphalt curb.
					var curb := nearest + normal * (half_width + 5.0)
					for opening: PackedVector2Array in audit.layers.sidewalk.openings:
						# Exclude the existing access/zebra masks; the difference is
						# the new footway-only masks, independent of scene ordering.
						if audit.layers.curb.openings.has(opening):
							continue
						if Geometry2D.is_point_in_polygon(mouth, opening):
							_check(not Geometry2D.is_point_in_polygon(curb, opening), "Pedestrian alley must not remove the asphalt curb")
			_check(joined, "Alley endpoint must join the existing sidewalk: %s" % point)
			checked += 1
	_check(checked == 4, "Expected four open pedestrian alley mouths")


func _audit_secret_drive(scene: Node2D, network: Node2D, audit: Dictionary) -> void:
	var neighborhood := scene.get_node("CobraNeighborhood")
	var drive: PackedVector2Array = neighborhood.get_secret_drive()
	var terminal := network.to_local(neighborhood.to_global(drive[-1]))
	for layer_name in ["curb", "sidewalk"]:
		var offset := 47.0 if layer_name == "curb" else 84.0
		var layer: Dictionary = audit.layers[layer_name]
		var driveway_masks: Array[PackedVector2Array] = []
		var prior_masks: Array[PackedVector2Array] = []
		for opening: PackedVector2Array in layer.openings:
			var bounds := Rect2(opening[0],Vector2.ZERO)
			for point in opening:
				bounds = bounds.expand(point)
			if is_equal_approx(bounds.size.x,64.0) and is_equal_approx(bounds.size.y,drive[-2].distance_to(drive[-1])):
				driveway_masks.append(opening)
			else:
				prior_masks.append(opening)
		_check(driveway_masks.size()==1,"One exact64px terminal driveway mask per layer")
		var prior_segments: Array = network._visible_edge_segments(layer.segments,prior_masks)
		_check(_edge_distance(terminal+Vector2(0,offset),prior_segments)<0.1,"Driveway center was a painted barrier before its dedicated opening")
		for x in [-30.0, 0.0, 30.0]:
			var south := terminal + Vector2(x, offset)
			_check(_inside(south, driveway_masks), "%s driveway opening covers full authored64px on south" % layer_name)
			_check(_edge_distance(south, layer.visible_segments) > 1.0, "%s guide must not cross secret driveway" % layer_name)
			var north := terminal + Vector2(x, -offset)
			_check(not _inside(north, driveway_masks), "%s opening must not erase opposite north border" % layer_name)
			# An existing zebra intersects the eastern sample: preserve its mask,
			# comparing the visible north boundary against the pre-driveway pass.
			_check(is_equal_approx(_edge_distance(north,layer.visible_segments),_edge_distance(north,prior_segments)), "%s opposite north border is unchanged" % layer_name)
		for x in [-40.0,40.0]:
			var outside := terminal+Vector2(x,offset)
			_check(is_equal_approx(_edge_distance(outside,layer.visible_segments),_edge_distance(outside,prior_segments)),"%s south opening stays local to64px driveway" % layer_name)


func _edge_distance(point: Vector2, segments: Array) -> float:
	var distance := INF
	for segment: PackedVector2Array in segments:
		distance = minf(distance,Geometry2D.get_closest_point_to_segment(point,segment[0],segment[-1]).distance_to(point))
	return distance


func _audit_hole_and_island(network: Node2D) -> void:
	var polygons: Array[PackedVector2Array] = []
	for rect in [Rect2(0,0,300,20),Rect2(0,280,300,20),Rect2(0,20,20,260),Rect2(280,20,20,260),Rect2(120,120,40,40),Rect2(20,80,60,120)]:
		polygons.append(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]))
	var union: Dictionary = network._union_boundary(polygons)
	var regions := BOUNDARY_AUDIT.prepare(polygons)
	_check(union.contours.size()==3,"Native union preserves outer loop, courtyard hole and island inside hole")
	for edge: PackedVector2Array in union.segments:
		_check(BOUNDARY_AUDIT.is_boundary(edge,regions),"Hole/island contour is a real boundary, not filled void")


func _audit_court_seams(network: Node2D) -> void:
	var seams := 0
	for junction in network.get("_junctions"):
		if str(junction.road_ids).contains("cobra_court"):
			var debug_geometry: Dictionary = network._build_junction_surface_geometry(junction,0.0)
			print("COURT_SEAM roads=%s count=%d arms=%d construction=%s debug=%s" % [junction.road_ids,junction.roads.size(),debug_geometry.arms.size(),debug_geometry.construction,debug_geometry.get("curve_debug",{})])
		for extra in [0.0,4.0,10.0,84.0]:
			var geometry: Dictionary = network._build_junction_surface_geometry(junction,extra)
			if geometry.construction != "authored_curve_continuation":
				continue
			if extra == 0.0:
				seams += 1
			_check(geometry.arms.size()==2 and geometry.component_count==1,"Curved seam retains two arms and one audited component")
			var half: float = (84.0+extra)*0.5
			for point: Vector2 in geometry.polygon:
				var radius := point.distance_to(Vector2(7700,1700))
				_check(radius <= 300.0+half+1.0 and radius >= 300.0-half-1.0,"Degree2 curve patch must not bulge beyond its authored ribbon: %.3f" % radius)
	_check(seams==3,"Exactly three degree2 court seams use curved patch; entrance junction keeps shared behavior")


func _capture_edges(scene: Node2D) -> void:
	var ui := scene.get_node_or_null("ReviewUI") as CanvasLayer
	if ui:
		ui.hide()
	var camera := Camera2D.new()
	camera.zoom = Vector2(2,2)
	scene.add_child(camera)
	camera.make_current()
	for shot in [{"position":Vector2(7220,1730),"path":"D:/geteco/road-edge-secret-drive.png"},{"position":Vector2(7700,1400),"path":"D:/geteco/road-edge-court-seam.png"}]:
		camera.position = shot.position
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var saved := root.get_texture().get_image().save_png(shot.path)==OK
		_check(saved,"Edge screenshot saved")
		if saved:
			captures_written += 1


func _inside(point: Vector2, polygons: Array) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
