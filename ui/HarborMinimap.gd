extends CanvasLayer
## Cached vector map: no extra world camera, viewport or duplicate simulation.
const MAP_SIZE := Vector2(208,164)
const SCALE := 0.12
var world: Node2D
var panel: Control
var canvas: Control
var caption: Label
var _roads: Array[Dictionary] = []
var _buildings: Array[Rect2] = []
var _mountain_cached := false
var _tick := 0.0
var objective_target := Vector2.ZERO
var objective_marker := Vector2.ZERO
var route_points := PackedVector2Array()
var _route_clock := 0.0
var _route_graph = preload("res://ui/StreetRoute.gd").new()
var _route_road_count := 0
var center := Vector2.ZERO
var car_map_position := Vector2.ZERO
var car_marker := Vector2.ZERO
var car_offscreen := false
var show_car := false
var service_marker := Vector2.ZERO
var heading := 0.0
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
	panel.offset_top = -226
	panel.offset_right = 240
	panel.offset_bottom = -24
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.color = Color("101e28")
	background.size = Vector2(216,202)
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
	caption.position = Vector2(8,170)
	caption.add_theme_font_size_override("font_size",11)
	caption.add_theme_color_override("font_color",Color("ffb565"))
	panel.add_child(caption)
	for road: Dictionary in world.get_node("RoadNetwork")._roads:
		var points := PackedVector2Array()
		for point: Vector2 in road.points: points.append(world.get_node("RoadNetwork").to_global(point))
		_roads.append({"points":points,"width":float(road.get("width",100))})
	for path in ["District","EastDistrict","NorthDistrict"]:
		var district: Node2D = world.get_node(path)
		for site: Dictionary in district.sites:
			_buildings.append(Rect2(district.to_global(site.bounds.position),site.bounds.size))
	refresh()
func map_world_position(actor: Node2D) -> Vector2:
	# A porta de origem prevalece sobre qualquer retângulo de sala isolada.
	if actor.has_meta("police_exterior_position"): return actor.get_meta("police_exterior_position")
	if actor.has_meta("service_safe_position"): return actor.get_meta("service_safe_position")
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
	heading = _compute_heading(actor, driven != null)
	var manager: Node = world.get_node("PersonalCarManager")
	show_car = is_instance_valid(manager.car) and manager.car.unlocked and not manager.car.is_driven_by_player
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
		_mountain_cached = true
	var campaign: Node = world.get_node_or_null("CobraCampaign")
	var arrival: Node = world.get_node_or_null("ArrivalMission")
	objective_target = Vector2.ZERO
	if campaign != null and get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete"):
		objective_target = campaign.navigation_target
	elif arrival != null:
		objective_target = arrival.navigation_target
	objective_marker = edge_marker(objective_target)
	_route_clock += 0.1
	if _route_clock >= 0.75:
		_route_clock = 0
		if _route_road_count != _roads.size():
			_route_graph.build(_roads)
			_route_road_count = _roads.size()
		route_points = _route_graph.route(center,objective_target) if objective_target != Vector2.ZERO else PackedVector2Array()
	if objective_target != Vector2.ZERO: caption.text = ("DESTINO / " if not TranslationServer.get_locale().begins_with("en") else "DESTINATION / ")+str(roundi(center.distance_to(objective_target)/16.6))+" m"
	panel.visible = not get_tree().paused and not player.is_dead and not player.is_in_dialogue and not player.is_control_disabled and map_world_position(player).distance_to(player.global_position)<500
	canvas.queue_redraw()
func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.1: return
	_tick = 0
	refresh()
func _draw_map() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),Color("263940"))
	for rect in _buildings:
		canvas.draw_rect(Rect2(project(rect.position),rect.size*SCALE),Color("46595c"))
	for road in _roads:
		var points := PackedVector2Array()
		for point: Vector2 in road.points: points.append(project(point))
		if points.size()>1: canvas.draw_polyline(points,Color("a8b4b0"),maxf(2,road.width*SCALE*0.45),true)
	if get_node("/root/SettingsManager").route_visible and objective_target != Vector2.ZERO:
		var line := PackedVector2Array()
		for point in route_points: line.append(project(point))
		if line.size()>1: canvas.draw_polyline(line,Color("ff914d"),3.0,true)
		var p := objective_marker
		canvas.draw_circle(p,10,Color("101820"))
		canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(7,0),p+Vector2(0,7),p+Vector2(-7,0)]),Color("ff914d"))
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

	canvas.draw_circle(service_marker,11,Color("152b2a"))
	canvas.draw_rect(Rect2(service_marker+Vector2(-5,-2),Vector2(7,10)),Color("edf4ee"))
	canvas.draw_line(service_marker+Vector2(-4,-3),service_marker+Vector2(1,-3),Color("edf4ee"),2)
	canvas.draw_rect(Rect2(service_marker+Vector2(-3,-6),Vector2(4,3)),Color("edf4ee"))
	canvas.draw_line(service_marker+Vector2(-4,2),service_marker+Vector2(1,2),Color("72e6bb"),2)
	for tip in [Vector2(7,-8),Vector2(8,-5),Vector2(7,-2)]:
		canvas.draw_line(service_marker+Vector2(3,-5),service_marker+tip,Color("72e6bb"),1,true)
	var middle := MAP_SIZE*0.5
	var pointer := PackedVector2Array()
	for p in [Vector2(8,0),Vector2(-5,-5),Vector2(-2,0),Vector2(-5,5)]: pointer.append(middle+p.rotated(heading))
	canvas.draw_colored_polygon(pointer,Color.WHITE)
	if show_car:
		canvas.draw_circle(car_marker,9,Color("14202b"))
		canvas.draw_rect(Rect2(car_marker-Vector2(4,6),Vector2(8,12)),Color("ffaa4e"))
		canvas.draw_line(car_marker+Vector2(-3,-2),car_marker+Vector2(3,-2),Color("243644"),2)
		if car_offscreen:
			var direction := (car_marker-middle).normalized()
			canvas.draw_line(car_marker+direction*10,car_marker+direction*14,Color("ffaa4e"),2)

