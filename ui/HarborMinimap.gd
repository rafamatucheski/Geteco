extends CanvasLayer
## Cached vector map: no extra world camera, viewport or duplicate simulation.
const MAP_SIZE := Vector2(184,184)
const PANEL_SIZE := MAP_SIZE + Vector2(8,8)
const SCALE := 0.12
var world: Node2D
var panel: Control
var canvas: Control
var caption: Label
var _roads: Array[Dictionary] = []
var _buildings: Array[Rect2] = []
var _mountain_cached := false
var _dirt_paths: Array[Dictionary] = []
var _tick := 0.0
var objective_target := Vector2.ZERO
var objective_marker := Vector2.ZERO
var available_mission_target := Vector2.ZERO
var route_points := PackedVector2Array()
var _route_clock := 0.0
var _route_graph = preload("res://ui/StreetRoute.gd").new()
var _route_road_count := 0
var _route_building := false
var center := Vector2.ZERO
var car_map_position := Vector2.ZERO
var car_marker := Vector2.ZERO
var car_offscreen := false
var show_car := false
var service_marker := Vector2.ZERO
var heading := 0.0
var motorsport_route := false
var has_waypoint := false
var waypoint := Vector2.ZERO
var waypoint_route := PackedVector2Array()
var full_map: CanvasLayer

func set_waypoint(point: Vector2) -> void:
	waypoint = point
	has_waypoint = true
	waypoint_route = _route_graph.route(center, waypoint)
	if _route_road_count != _roads.size() and not _route_building:
		_build_route_graph()
	canvas.queue_redraw()

func clear_waypoint() -> void:
	has_waypoint = false
	waypoint_route = PackedVector2Array()
	canvas.queue_redraw()
## Contrato lido (não alterado) de Player.gd: `velocity: Vector2`, a
## velocidade atual do pedestre em px/s (ver Player.gd:796). Abaixo deste
## módulo, tratamos o pedestre como parado e conservamos o último heading.
const PEDESTRIAN_HEADING_MIN_SPEED := 8.0
func _ready() -> void:
	add_to_group("minimap")
	layer = 24
	world = get_parent()
	panel = Control.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24
	panel.offset_top = -24-PANEL_SIZE.y
	panel.offset_right = 24+PANEL_SIZE.x
	panel.offset_bottom = -24
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.color = Color("08090b")
	background.size = PANEL_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(background)
	var clip := Control.new()
	clip.position = Vector2(4,4)
	clip.size = MAP_SIZE
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(clip)
	canvas = Control.new()
	canvas.size = MAP_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(canvas)
	canvas.draw.connect(_draw_map)
	caption = Label.new()
	caption.position = Vector2(8,MAP_SIZE.y-18)
	caption.add_theme_font_size_override("font_size",11)
	caption.add_theme_color_override("font_color",Color("ffb565"))
	panel.add_child(caption)
	for road: Dictionary in world.get_node("RoadNetwork")._roads:
		var points := PackedVector2Array()
		for point: Vector2 in road.points: points.append(world.get_node("RoadNetwork").to_global(point))
		_roads.append({"points":points,"width":float(road.get("width",100))})
	for route in preload("res://world/harbor/HarborNorthAccess.gd").curves():
		var points := PackedVector2Array()
		for point in route.get_baked_points(): points.append(world.to_global(point))
		_roads.append({"points":points,"width":96.0})
	for path in ["District","EastDistrict","NorthDistrict","SouthPort"]:
		var district: Node2D = world.get_node(path)
		for site: Dictionary in district.sites:
			_buildings.append(Rect2(district.to_global(site.bounds.position),site.bounds.size))
	for yard in get_tree().get_nodes_in_group("chop_shop"):
		_roads.append(yard.access_road())
	refresh()
	full_map = preload("res://ui/WorldMap.gd").new()
	add_child(full_map)
func map_world_position(actor: Node2D) -> Vector2:
	# A porta de origem prevalece sobre qualquer retângulo de sala isolada.
	if actor.has_meta("police_exterior_position"): return actor.get_meta("police_exterior_position")
	if actor.has_meta("service_safe_position"): return actor.get_meta("service_safe_position")
	var residence := get_tree().get_first_node_in_group("residence_manager")
	if is_instance_valid(residence) and residence.has_method("map_position_for_actor"):
		var residence_position: Variant = residence.map_position_for_actor(actor)
		if residence_position is Vector2:
			return residence_position
	var interiors: Node = world.get_node("Interiors")
	for path in interiors._door_configs:
		var room: Node = interiors._door_configs[path].interior
		if room.get_camera_rect().has_point(actor.global_position):
			return world.get_node(String(path)+"/OutsideReturn").global_position
	return actor.global_position
func project(point: Vector2) -> Vector2: return MAP_SIZE*0.5+(point-center)*SCALE
func edge_marker(point: Vector2) -> Vector2:
	var offset := project(point)-MAP_SIZE*0.5
	var factor := maxf(absf(offset.x)/(MAP_SIZE.x*0.5-12),absf(offset.y)/(MAP_SIZE.y*0.5-12))
	return MAP_SIZE*0.5+offset/maxf(1,factor)
## Dirigindo: usa a orientação real do veículo (o carro gira de verdade).
## A pé: Player.gd mantém `rotation = 0.0` sempre (o corpo 3D gira, não o nó
## 2D), então `global_rotation` não serve para o pedestre -- em vez disso
## seguimos a direção real do deslocamento via `velocity.angle()`. Abaixo de
## PEDESTRIAN_HEADING_MIN_SPEED tratamos como "parado" e conservamos o
## último heading (não há salto para uma direção arbitrária ao frear).
func _compute_heading(actor: Node2D, is_driving: bool) -> float:
	if is_driving:
		return actor.global_rotation
	var vel = actor.get("velocity")
	if vel is Vector2 and vel.length() > PEDESTRIAN_HEADING_MIN_SPEED:
		return vel.angle()
	return heading
func refresh() -> void:
	var player: Node2D = world.get_node("Player")
	var driven := get_node("/root/RegionTravel").controlled_car() as Node2D
	var actor: Node2D = driven if driven != null else player
	center = map_world_position(actor)
	if has_waypoint and center.distance_to(waypoint) < 65.0:
		clear_waypoint()
	heading = _compute_heading(actor, driven != null)
	var manager: Node = world.get_node("PersonalCarManager")
	show_car = is_instance_valid(manager.car) and manager.car.unlocked and not manager.impounded and not manager.car.is_driven_by_player
	if show_car:
		car_map_position = map_world_position(manager.car)
		var raw := project(car_map_position)
		var offset := raw-MAP_SIZE*0.5
		var factor := maxf(absf(offset.x)/(MAP_SIZE.x*0.5-12),absf(offset.y)/(MAP_SIZE.y*0.5-12))
		car_offscreen = factor>1
		car_marker = MAP_SIZE*0.5+offset/maxf(1,factor)
		caption.text = "MONALIZA / %d m" % int(center.distance_to(car_map_position)/16.6)
	else:
		car_offscreen = false
		caption.text = "N ↑"
	var service: Node2D = world.get_node("PayNSpray")
	service_marker = edge_marker(service.global_position)
	if show_car and service_marker.distance_to(car_marker)<20: service_marker.y = clampf(service_marker.y+20,10,MAP_SIZE.y-10)
	var stream: Node = world.get_node_or_null("ContinuousWorld")
	if not _mountain_cached and stream != null and stream.ready_for_crossing:
		var points := PackedVector2Array()
		for point: Vector2 in stream.mountain.road.smooth_points: points.append(stream.mountain.road.to_global(point))
		_roads.append({"points":points,"width":140.0})
		_cache_dirt_paths(stream.mountain)
		_mountain_cached = true
	var campaign: Node = world.get_node_or_null("CobraCampaign")
	var arrival: Node = world.get_node_or_null("ArrivalMission")
	objective_target = Vector2.ZERO
	available_mission_target = Vector2.ZERO
	if campaign != null and get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete"):
		if not String(campaign.runtime.active_id).is_empty():
			objective_target = campaign.navigation_target
		elif campaign.story_start_block_reason().is_empty():
			for id in campaign.LEDGER.MISSION_IDS:
				if campaign.ledger.get_status(id).available:
					available_mission_target = world.get_node("District/Garage/Entrance").global_position
					break # All these jobs start at Maciota's board: one shared M.
	elif arrival != null:
		if arrival.phase == "board":
			for row in arrival.garage.mission_board.campaign_missions:
				if row.enabled and not row.completed:
					available_mission_target = world.get_node("District/Garage/Entrance").global_position
					break
		else:
			objective_target = arrival.navigation_target
	motorsport_route = false
	for yard in get_tree().get_nodes_in_group("chop_shop"):
		var salvage_target: Vector2=yard.navigation_target()
		if salvage_target != Vector2.ZERO: objective_target=salvage_target
	for race in get_tree().get_nodes_in_group("night_race"):
		if race._state == race.State.RUNNING:
			objective_target = race._get_current_target_position()
			motorsport_route = true
	objective_marker = edge_marker(objective_target)
	for taxi in get_tree().get_nodes_in_group("taxi_service"):
		if taxi.state == "riding":
			objective_target = taxi.destination
			objective_marker = edge_marker(objective_target)
	# Authored campaign navigation wins over optional jobs, except an actual
	# passenger taxi ride whose driver needs the selected destination.
	var cobra_route := PackedVector2Array()
	if campaign != null and campaign.runtime.active_id == "cobra_race":
		var status: Dictionary = campaign.runtime.get_status()
		if status.get("race_phase", "approach") != "approach":
			cobra_route = status.get("route", PackedVector2Array())
			motorsport_route = true
			objective_target = status.get("target", Vector2.ZERO)
			objective_marker = edge_marker(objective_target)
	_route_clock += 0.1
	if _route_clock >= 0.75:
		_route_clock = 0
		if _route_road_count != _roads.size() and not _route_building:
			_build_route_graph()
		route_points = _route_graph.route(center,objective_target) if objective_target != Vector2.ZERO else PackedVector2Array()
		waypoint_route = _route_graph.route(center,waypoint) if has_waypoint else PackedVector2Array()
		if arrival != null and arrival.phase == "city_tour" and is_instance_valid(arrival.story_arrival.car):
			var tour_car: Node = arrival.story_arrival.car
			route_points = tour_car.route.slice(maxi(0,tour_car.cursor-1))
	if not cobra_route.is_empty(): route_points = cobra_route
	caption.text = ""
	if has_waypoint:
		caption.text = "GPS · %d m" % int(center.distance_to(waypoint)/16.6)
	if not has_waypoint and stream != null and stream.ready_for_crossing and stream.current_region == "mountain":
		var local_position: Vector2 = stream.mountain.to_local(center)
		caption.text = "%d m" % int(clampf(680.0 + (400.0 - local_position.y) * 0.62, 680.0, 2780.0))
	panel.visible = not get_tree().paused and not player.is_dead and not player.is_in_dialogue and not player.is_control_disabled and map_world_position(player).distance_to(player.global_position)<500
	if arrival != null and arrival.phase == "city_tour":
		panel.visible = not get_tree().paused and not player.is_dead
	canvas.queue_redraw()
func _cache_dirt_paths(region: Node) -> void:
	_dirt_paths.clear()
	for path in region.find_children("*", "Line2D", true, false):
		if not path.get_meta("minimap_dirt_path", false): continue
		var points := PackedVector2Array()
		for point: Vector2 in path.points: points.append(path.to_global(point))
		if points.size() < 2: continue
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point: Vector2 in points: bounds = bounds.expand(point)
		_dirt_paths.append({"points": points, "width": path.width, "bounds": bounds.grow(path.width)})

func _build_route_graph() -> void:
	_route_building = true
	var road_count := _roads.size()
	var pending := preload("res://ui/StreetRoute.gd").new()
	await pending.build(_roads.duplicate(true), get_tree())
	_route_graph = pending
	_route_road_count = road_count
	_route_building = false
	if has_waypoint:
		waypoint_route = _route_graph.route(center,waypoint)
		canvas.queue_redraw()
		if is_instance_valid(full_map) and full_map.screen.visible:
			full_map._update_status()
			full_map.surface.queue_redraw()

func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.1: return
	_tick = 0
	refresh()
func _draw_map() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),Color("263940"))
	var map_area := Rect2(center-MAP_SIZE/(2.0*SCALE),MAP_SIZE/SCALE)
	for port in get_tree().get_nodes_in_group("south_port"):
		var layout := preload("res://world/harbor/HarborSouthPortLayout.gd")
		for rect in [layout.LAND,layout.WALKWAY,layout.SHIP,layout.SHIP_GANGWAY]:
			canvas.draw_rect(Rect2(project(rect.position),rect.size*SCALE),Color("697d7b"))
		for rect in layout.containers():
			canvas.draw_rect(Rect2(project(rect.position),rect.size*SCALE),Color("b29869"))
		for rect in layout.PIERS:
			canvas.draw_rect(Rect2(project(rect.position),rect.size*SCALE),Color("a4a78b"))
	for yard in get_tree().get_nodes_in_group("chop_shop"):
		var land: Rect2=yard.LOCATION.LAND
		canvas.draw_rect(Rect2(project(yard.to_global(land.position)),land.size*SCALE),Color("4e6345"))
		canvas.draw_rect(Rect2(project(yard.global_position+Vector2(-344,-196)),Vector2(688,392)*SCALE),Color("89836a"))
	for rect in _buildings:
		if not map_area.intersects(rect): continue
		canvas.draw_rect(Rect2(project(rect.position),rect.size*SCALE),Color("46595c"))
	for road in _roads:
		if not road.has("minimap_bounds"):
			var bounds := Rect2()
			if not road.points.is_empty():
				bounds = Rect2(road.points[0],Vector2.ZERO)
				for point: Vector2 in road.points: bounds = bounds.expand(point)
			road.minimap_bounds = bounds.grow(maxf(2.0/SCALE,float(road.width)))
		if not map_area.intersects(road.minimap_bounds): continue
		var points := PackedVector2Array()
		for point: Vector2 in road.points: points.append(project(point))
		if points.size()>1: canvas.draw_polyline(points,Color("a8b4b0"),maxf(2,road.width*SCALE*0.45),true)
	for path in _dirt_paths:
		if not map_area.intersects(path.bounds): continue
		var points := PackedVector2Array()
		for point: Vector2 in path.points: points.append(project(point))
		canvas.draw_polyline(points, Color("b18b59"), clampf(float(path.width)*SCALE*0.36,1.5,3.2), true)
	if get_node("/root/SettingsManager").route_visible and objective_target != Vector2.ZERO:
		var line := PackedVector2Array()
		for point in route_points: line.append(project(point))
		if line.size()>1: canvas.draw_polyline(line,Color("59dce8") if motorsport_route else Color("ff914d"),3.0,true)

	for group in ["drift_zone","night_race"]:
		for event in get_tree().get_nodes_in_group(group):
			var p := project(event.global_position if group == "drift_zone" else event.to_global(event.start_pos))
			if not Rect2(Vector2(12,12),MAP_SIZE-Vector2(24,24)).has_point(p): continue
			var color := Color("ffb347") if group == "drift_zone" else Color("59dce8") if event._is_night() else Color("7e939e")
			canvas.draw_circle(p,11,Color("101c29"))
			if group == "drift_zone":
				for x in [-3,3]: canvas.draw_arc(p+Vector2(x,0),5,-1.4,1.7,12,color,2,true)
			else:
				canvas.draw_line(p+Vector2(-5,6),p+Vector2(-5,-7),color,2)
				for y in 2:
					for x in 3: canvas.draw_rect(Rect2(p+Vector2(-3+x*3,-7+y*3),Vector2(3,3)),color if (x+y)%2==0 else Color("101c29"))
	# Small aerosol silhouette: body, shoulder, nozzle and three spray rays.
	for shop in get_tree().get_nodes_in_group("clothing_shop"):
		var p := project(shop.global_position)
		if Rect2(Vector2(8,8),MAP_SIZE-Vector2(16,16)).has_point(p):
			canvas.draw_circle(p,9,Color("25303b"))
			canvas.draw_polyline(PackedVector2Array([p+Vector2(-6,-3),p+Vector2(-3,-6),p+Vector2(3,-6),p+Vector2(6,-3),p+Vector2(3,-1),p+Vector2(3,5),p+Vector2(-3,5),p+Vector2(-3,-1),p+Vector2(-6,-3)]),Color("c6d8e2"),1.5)

	for shop in get_tree().get_nodes_in_group('weapon_shop'):
		var p := project(shop.global_position)
		if Rect2(Vector2(8,8),MAP_SIZE-Vector2(16,16)).has_point(p):
			canvas.draw_circle(p,9,Color('29343a'))
			canvas.draw_rect(Rect2(p+Vector2(-6,-4),Vector2(12,4)),Color('dfa67b'))
			canvas.draw_line(p+Vector2(-2,-1),p+Vector2(-4,5),Color('dfa67b'),3)
	for residence in get_tree().get_nodes_in_group("residence_property"):
		var p := project(residence.minimap_position())
		if not Rect2(Vector2(8,8), MAP_SIZE-Vector2(16,16)).has_point(p):
			continue
		var color := Color("71d3a0") if residence.active else Color("e8b77d")
		canvas.draw_circle(p, 9, Color("18262d"))
		canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-6,-1),p+Vector2(0,-7),p+Vector2(6,-1)]), color)
		canvas.draw_rect(Rect2(p+Vector2(-5,-1),Vector2(10,7)),color)
		canvas.draw_rect(Rect2(p+Vector2(-1,2),Vector2(3,4)),Color("18262d"))
	for group in ["bank_entrance","fuel_entrance"]:
		for entrance in get_tree().get_nodes_in_group(group):
			var p := project(entrance.global_position)
			if not Rect2(Vector2(8,8),MAP_SIZE-Vector2(16,16)).has_point(p): continue
			canvas.draw_circle(p,9,Color("29343a"))
			if group=="bank_entrance":
				canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-6,-3),p+Vector2(0,-7),p+Vector2(6,-3)]),Color("d8c598"))
				for x in [-4,0,4]: canvas.draw_line(p+Vector2(x,-1),p+Vector2(x,5),Color("d8c598"),2)
			else:
				canvas.draw_rect(Rect2(p+Vector2(-4,-6),Vector2(7,12)),Color("dda27d"))
				canvas.draw_rect(Rect2(p+Vector2(-2,-4),Vector2(3,3)),Color("273d43"))

	for stop in get_tree().get_nodes_in_group("urban_bus_stop"):
		var marker := project(stop.global_position)
		if Rect2(Vector2(10,10),MAP_SIZE-Vector2(20,20)).has_point(marker):
			canvas.draw_rect(Rect2(marker-Vector2(5,7),Vector2(10,14)),Color("c83a43") if stop.operating else Color("637078"))
			canvas.draw_line(marker+Vector2(-3,-3),marker+Vector2(3,-3),Color.WHITE,2)
	canvas.draw_circle(service_marker,11,Color("152b2a"))
	for yard in get_tree().get_nodes_in_group("chop_shop"):
		var marker:=edge_marker(yard.global_position)
		canvas.draw_circle(marker,13,Color("172c2a"))
		preload("res://cars/salvage/SalvageSign.gd").icon(canvas,marker,.85,Color("f5c86d"))
	canvas.draw_rect(Rect2(service_marker+Vector2(-5,-2),Vector2(7,10)),Color("edf4ee"))
	canvas.draw_line(service_marker+Vector2(-4,-3),service_marker+Vector2(1,-3),Color("edf4ee"),2)
	canvas.draw_rect(Rect2(service_marker+Vector2(-3,-6),Vector2(4,3)),Color("edf4ee"))
	canvas.draw_line(service_marker+Vector2(-4,2),service_marker+Vector2(1,2),Color("72e6bb"),2)
	for tip in [Vector2(7,-8),Vector2(8,-5),Vector2(7,-2)]:
		canvas.draw_line(service_marker+Vector2(3,-5),service_marker+tip,Color("72e6bb"),1,true)
	var middle := MAP_SIZE*0.5
	if has_waypoint:
		var gps_line := PackedVector2Array()
		for point in waypoint_route: gps_line.append(project(point))
		if gps_line.size() > 1: canvas.draw_polyline(gps_line,Color("67e8cf"),3.0,true)
		var pin := edge_marker(waypoint)
		canvas.draw_circle(pin,7,Color("102a29"))
		canvas.draw_arc(pin,5,0,TAU,20,Color("67e8cf"),2,true)
		canvas.draw_circle(pin,2,Color("67e8cf"))
	_draw_police_contacts()
	for marker in get_tree().get_nodes_in_group("collectible_quest_marker"):
		if not is_instance_valid(marker): continue
		var marker_position := project(marker.global_position)
		if Rect2(Vector2(8,8),MAP_SIZE-Vector2(16,16)).has_point(marker_position):
			canvas.draw_rect(Rect2(marker_position+Vector2(-4,-4),Vector2(9,9)),Color("#ffd36a"))
			canvas.draw_line(marker_position+Vector2(-4,-4), marker_position+Vector2(4,4), Color("fff4c6"),2)
			canvas.draw_line(marker_position+Vector2(-4,4), marker_position+Vector2(4,-4), Color("fff4c6"),2)
	if show_car:
		canvas.draw_circle(car_marker,9,Color("14202b"))
		canvas.draw_rect(Rect2(car_marker-Vector2(4,6),Vector2(8,12)),Color("ffaa4e"))
		canvas.draw_line(car_marker+Vector2(-3,-2),car_marker+Vector2(3,-2),Color("243644"),2)
		if car_offscreen:
			var direction := (car_marker-middle).normalized()
			canvas.draw_line(car_marker+direction*10,car_marker+direction*14,Color("ffaa4e"),2)
	# Mission icons stay readable over services and do not depend on route guidance.
	if available_mission_target != Vector2.ZERO:
		var p := edge_marker(available_mission_target)
		canvas.draw_circle(p,12,Color("101820"))
		canvas.draw_circle(p,10,Color("ffcf4d"))
		var glyph_width := ThemeDB.fallback_font.get_string_size("M",HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		canvas.draw_string(ThemeDB.fallback_font,p+Vector2(-glyph_width*0.5,6),"M",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("101820"))
	if objective_target != Vector2.ZERO:
		var p := objective_marker
		canvas.draw_circle(p,10,Color("101820"))
		canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(7,0),p+Vector2(0,7),p+Vector2(-7,0)]),Color("59dce8") if motorsport_route else Color("ffcf4d"))
	var pointer := PackedVector2Array()
	for p in [Vector2(8,0),Vector2(-5,-5),Vector2(-2,0),Vector2(-5,5)]: pointer.append(middle+p.rotated(heading))
	canvas.draw_colored_polygon(pointer,Color.WHITE)
	canvas.draw_rect(Rect2(Vector2(MAP_SIZE.x*0.5-7,1),Vector2(14,16)),Color("101820"))
	canvas.draw_string(ThemeDB.fallback_font,Vector2(MAP_SIZE.x*0.5-5,13),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)


func _draw_police_contacts() -> void:
	preload("res://ui/PoliceMapContacts.gd").draw_contacts(self)

