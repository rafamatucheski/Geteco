extends Control
## V1 cached-vector minimap composition over the current 3D region data.

class MapCanvas extends Control:
	var minimap: Control
	func _draw() -> void:
		if is_instance_valid(minimap): minimap.draw_map(self)

const STYLE := preload("res://ui/GameStyle.gd")
const CARTOGRAPHY := preload("res://ui/hud/Cartography.gd")
const MAP_SIZE := Vector2(180, 180)
const PANEL_SIZE := MAP_SIZE + Vector2(8, 8)
const SCALE := 1.54 # Preserve the previous ground coverage inside a smaller panel.
const NAVIGATION := preload("res://ui/v1/NavigationRoute.gd")
const POLICE := preload("res://ui/v1/MinimapPolice.gd")
const FONT := STYLE.STRONG
const GLYPHS := preload("res://ui/hud/VectorGlyphs.gd")
const CONDITIONS := preload("res://ui/hud/WorldConditions.gd")
const PLACES := preload("res://ui/hud/NavigationPlaces.gd")
const SYMBOLS := preload("res://ui/hud/MapSymbols.gd")

var world: Node
var canvas: MapCanvas
var caption: Label
var compass_label: Label
var weekday_label: Label
var weather_icon: Control
var center := Vector2.ZERO
var heading := 0.0
var objective_target := Vector2.ZERO
var destination: Dictionary = {}
var _places: Array[Dictionary] = []
var _harbor_places_cached := false
var drawn_places: Array[Dictionary] = []
var _tick := 0.0
var _conditions_tick := 1.0
var _cached_regions: Dictionary = {}
var _cached_connection := false
var _roads: Array[Dictionary] = []
var _buildings: Array[Rect2] = []
var _entries := PackedVector2Array()
var _rail_stations: Array[Dictionary] = []
var _drawn_center := Vector2(INF, INF)
var _drawn_heading := INF
var _drawn_objective := Vector2(INF, INF)
var _redraw_required := true
var map_scale := SCALE
var _drawn_scale := SCALE
var _refresh_delta := 0.033
var _route_clock := 1.0
var navigation := NAVIGATION.new()
var route_points := PackedVector2Array()
var background: Panel

func _ready() -> void:
	if "--railway-baseline" not in OS.get_cmdline_user_args():
		_rail_stations = preload("res://world/railway/RailwayNetwork.gd").stations()
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = PANEL_SIZE
	size = custom_minimum_size
	background = Panel.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = STYLE.INK
	frame.border_color = STYLE.ACCENT
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(44)
	frame.corner_detail = 16
	frame.anti_aliasing = true
	frame.shadow_size = 4
	frame.shadow_color = Color(0, 0, 0, .45)
	background.add_theme_stylebox_override("panel", frame)
	background.size = size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var clip := Control.new()
	clip.position = Vector2(4, 4)
	clip.size = MAP_SIZE
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(clip)
	canvas = MapCanvas.new()
	canvas.minimap = self
	canvas.size = MAP_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(canvas)
	caption = Label.new()
	caption.name = "NavigationDestination"
	caption.position = Vector2(0, -28)
	caption.size = Vector2(PANEL_SIZE.x, 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.add_theme_font_override("font", FONT)
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", Color("eee9e2"))
	caption.add_theme_color_override("font_outline_color",STYLE.INK)
	caption.add_theme_constant_override("outline_size",1)
	caption.add_theme_color_override("font_shadow_color",Color(0,0,0,.7))
	caption.add_theme_constant_override("shadow_offset_y",1)
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.hide()
	add_child(caption)
	compass_label = Label.new()
	compass_label.name = "Compass"
	compass_label.text = "N"
	compass_label.position = Vector2(PANEL_SIZE.x*.5-9, -7)
	compass_label.size = Vector2(18, 20)
	compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_label.add_theme_font_override("font", FONT)
	compass_label.add_theme_font_size_override("font_size", 12)
	compass_label.add_theme_color_override("font_color", STYLE.ACCENT)
	compass_label.add_theme_stylebox_override("normal",STYLE.compact(false,6,Vector2(3,0)))
	compass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(compass_label)
	weekday_label = Label.new()
	weekday_label.name = "Weekday"
	weekday_label.position = Vector2(PANEL_SIZE.x + 12, 42)
	weekday_label.size = Vector2(78, 72)
	weekday_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	weekday_label.add_theme_font_override("font", FONT)
	weekday_label.add_theme_font_size_override("font_size", 12)
	weekday_label.add_theme_color_override("font_color", Color("c3c8cbd9"))
	weekday_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .65))
	weekday_label.add_theme_constant_override("shadow_offset_y", 1)
	weekday_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(weekday_label)
	weather_icon = preload("res://ui/v1/WeatherIcon.gd").new()
	weather_icon.name = "Weather"
	weather_icon.size = Vector2(20,20)
	weather_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(weather_icon)

func _process(delta: float) -> void:
	_tick += delta
	_conditions_tick += delta
	_route_clock += delta
	if _tick < 1.0 / 30.0: return
	_refresh_delta = _tick
	_tick = 0.0
	refresh()

func refresh() -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player) or not is_instance_valid(world.production) or not is_instance_valid(world.session):
		hide()
		return
	# Session creation spans frames; calendar data becomes available with weather.
	if not world.session.ready_for_play or not is_instance_valid(world.session.weather):
		hide()
		return
	var was_visible := visible
	# Boarding temporarily owns movement but remains in the same outdoor world.
	# Keep navigation stable through approach/door/seat, without revealing it in
	# menus, rescue or unrelated scripted movement locks.
	var boarding: bool = is_instance_valid(world.driving) and world.driving.is_body_transition_active()
	var skate: Variant = world.session.get("skate")
	var skating: bool = is_instance_valid(skate) and skate.controls_locked()
	var blocked := bool(world.session.get("modal")) or get_tree().paused or bool(world.session.get("rescue_pending")) or bool(world.session.get("arrest_pending")) or (bool(world.player.get("input_locked")) and not boarding and not skating) or not str(world.session.state.place_id).is_empty()
	visible = not blocked
	if not visible: return
	# The existing persisted calendar starts on day 2; its first day is Monday.
	if _conditions_tick >= 1.0 or weekday_label.text.is_empty() or not was_visible:
		_conditions_tick = 0.0
		var weather: Variant = world.session.weather
		var conditions := CONDITIONS.vertical_text(int(world.session.state.world_state.get("moon_day", 2)), float(weather.time_of_day), str(world.session.state.region_id), int(weather.weather_state), weather.mountain_weather)
		if weekday_label.text != conditions: weekday_label.text = conditions
		weather_icon.position = weekday_label.position + Vector2(0,maxf(74,weekday_label.get_combined_minimum_size().y+4))
		var icon := CONDITIONS.icon(float(weather.time_of_day),str(world.session.state.region_id),int(weather.weather_state),weather.mountain_weather)
		if weather_icon.state != icon:
			weather_icon.state = icon
			weather_icon.queue_redraw()
	var actor: Node3D = world.driving.car if is_instance_valid(world.driving) and bool(world.driving.get("occupied")) else world.player
	if skating and skate.mounted and is_instance_valid(skate.player_board): actor = skate.player_board
	if not is_instance_valid(actor): actor = world.player
	center = Vector2(actor.global_position.x, actor.global_position.z)
	_cache_region()
	var velocity: Variant = actor.get("velocity")
	var speed := Vector2(velocity.x, velocity.z).length() if velocity is Vector3 else 0.0
	var desired_scale := lerpf(SCALE, .85, clampf(speed / 24.0, 0, 1)) if actor != world.player else SCALE
	map_scale = lerpf(map_scale, desired_scale, 1.0 - exp(-3.0 * _refresh_delta))
	if velocity is Vector3 and Vector2(velocity.x, velocity.z).length() > 0.15:
		heading = Vector2(velocity.x, velocity.z).angle()
	elif actor != world.player:
		var forward := -actor.global_basis.z
		heading = Vector2(forward.x, forward.z).angle()
	var selected: Dictionary = world.session.navigation_destination()
	if str(selected.get("title",""))!=str(destination.get("title","")) or str(selected.get("kind",""))!=str(destination.get("kind","")) or str(selected.get("source",""))!=str(destination.get("source","")): _redraw_required=true
	destination = selected
	objective_target = Vector2(destination.point.x,destination.point.z) if not destination.is_empty() else Vector2.ZERO
	_sync_navigation(actor)
	# Viaturas e cones se movem sozinhos: com polícia em jogo o mapa redesenha a cada atualização (30 Hz).
	if POLICE.active(world): _redraw_required = true
	if not was_visible or _redraw_required or center.distance_squared_to(_drawn_center) > 0.0025 or absf(angle_difference(heading, _drawn_heading)) > 0.01 or absf(map_scale - _drawn_scale) > .002 or not objective_target.is_equal_approx(_drawn_objective):
		_drawn_center = center
		_drawn_heading = heading
		_drawn_objective = objective_target
		_drawn_scale = map_scale
		_redraw_required = false
		canvas.queue_redraw()

func _sync_navigation(actor: Node3D) -> void:
	var has_target := not destination.is_empty()
	caption.visible=has_target
	if has_target:
		var distance := center.distance_to(objective_target)
		caption.text = "%s · %s" % [destination.title,"Chegou" if distance < 3 else ("%.1f km" % (distance/1000.0) if distance >= 1000 else "%d m" % roundi(distance))]
	# Keep destination identity above the map and weather below it without resizing.
	var extent := PANEL_SIZE
	if size != extent:
		custom_minimum_size = extent
		size = extent
		background.size = extent
	if not has_target:
		if not route_points.is_empty(): _redraw_required = true
		navigation.clear()
		route_points.clear()
		return
	if center.distance_to(objective_target) < 3.0:
		if not route_points.is_empty(): _redraw_required = true
		navigation.clear()
		route_points.clear()
		return
	if _route_clock >= .75 or not objective_target.is_equal_approx(_drawn_objective):
		_route_clock = 0.0
		var source := NAVIGATION.source(world.production)
		if source.routes != null:
			var goal := NAVIGATION.goal_on_surface(source.routes,objective_target)
			if navigation.update(source.routes, source.revision, actor.global_position, goal, actor != world.player, -actor.global_basis.z): _redraw_required = true
	var remaining := navigation.remaining(center)
	if remaining != route_points:
		route_points = remaining
		_redraw_required = true

func _cache_region() -> void:
	if not _harbor_places_cached:
		_places.append_array(PLACES.harbor(world.session))
		_harbor_places_cached=true
	# Keep lightweight geography after streaming unloads its 3D region. The map
	# must not replace half the crossing when the logical region changes.
	for region: Node in world.production.regions.values():
		if not is_instance_valid(region) or _cached_regions.has(region.region_id): continue
		_cached_regions[region.region_id] = true
		_cache_geography(region)
	if not _cached_connection:
		_cached_connection = true
		for source in preload("res://world/regions/WorldConnection3D.gd").traffic_connectors():
			_cache_road(source)

func _cache_road(source: Dictionary) -> void:
	var points := PackedVector2Array()
	var bounds := Rect2()
	for point: Vector3 in source.points:
		var mapped := Vector2(point.x, point.z)
		points.append(mapped)
		bounds = Rect2(mapped, Vector2.ZERO) if points.size() == 1 else bounds.expand(mapped)
	_roads.append({"points": points, "width": float(source.get("width", 2.0)), "bounds": bounds})
	_redraw_required = true

func _cache_geography(region: Node) -> void:
	_redraw_required = true
	for source in region.map_routes():
		_cache_road(source)
	for source in region.buildings:
		var point: Vector3 = source.position
		var dimensions: Vector2 = source.size
		_buildings.append(Rect2(Vector2(point.x, point.z) - dimensions * 0.5, dimensions))
	for source in region.entries:
		var point: Vector3 = source.position
		_entries.append(Vector2(point.x, point.z))
		var place: Dictionary=PLACES.entrance(source,str(region.region_id))
		if not _places.any(func(existing): return existing.region==place.region and existing.id==place.id): _places.append(place)

static func place_key(place: Dictionary) -> String:
	return "%s:%s" % [place.get("region",""), place.get("id","")]

## Quais ícones de lugar desenhar (até MAX_ICONS), sem nomes. Antes a ordem era só
## pela distância, refeita 30 vezes por segundo: andando, dois ícones a menos de 17 px trocavam de
## lugar na fila e piscavam um no lugar do outro, e as etiquetas pulavam (playtest de 26/10). Agora
## quem já estava na tela tem a vez: só sai quando deixa o mapa, encosta na seta do jogador ou perde a
## vaga para um lugar com nome; o novo só entra onde houver espaço. A seta tem folga diferente para
## entrar (14 px) e sair (10 px), para o ícone não piscar ao passar por cima do lugar.
const MAX_ICONS := 8
## Folga da borda, em px, para quem já está na tela (meio ícone some no recorte).
const KEEP_MARGIN := 10.0
const ICON_SPACING := 17.0
const PLAYER_CLEAR_ENTER := 14.0
const PLAYER_CLEAR_LEAVE := 10.0
const NAMED_PLACES := ["neco","ferrugem","maciota"]
var _shown_places: Dictionary = {}

static func choose_places(nearby: Array[Dictionary], icons: Array[Vector2], focus: Vector2, shown: Dictionary, _labeled: Dictionary) -> Dictionary:
	var order: Array = range(nearby.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var named_a: bool = nearby[a].id in NAMED_PLACES
		var named_b: bool = nearby[b].id in NAMED_PLACES
		if named_a != named_b: return named_a
		var kept_a: bool = shown.has(place_key(nearby[a]))
		var kept_b: bool = shown.has(place_key(nearby[b]))
		if kept_a != kept_b: return kept_a
		var da := focus.distance_squared_to(nearby[a].point)
		var db := focus.distance_squared_to(nearby[b].point)
		return da < db if da != db else place_key(nearby[a]) < place_key(nearby[b]))
	var middle := MAP_SIZE * .5
	var chosen: Array[int] = []
	for index: int in order:
		var icon: Vector2 = icons[index]
		var clear := PLAYER_CLEAR_LEAVE if shown.has(place_key(nearby[index])) else PLAYER_CLEAR_ENTER
		if icon.distance_to(middle) < clear: continue
		if chosen.any(func(other: int) -> bool: return icons[other].distance_to(icon) < ICON_SPACING): continue
		chosen.append(index)
		if chosen.size() >= MAX_ICONS: break
	return {"shown": chosen, "labels": []}

func project(point: Vector2) -> Vector2:
	return MAP_SIZE * 0.5 + (point - center) * map_scale

func edge_marker(point: Vector2) -> Vector2:
	var offset := project(point) - MAP_SIZE * 0.5
	var factor := offset.length() / (MAP_SIZE.x * .5 - 13)
	return MAP_SIZE * 0.5 + offset / maxf(1.0, factor)

func draw_map(target: Control) -> void:
	# Keep the navigation background quiet while panning and changing zoom.
	# Decorative contours are reserved for the full-size map.
	if not is_instance_valid(world) or not is_instance_valid(world.production) or not is_instance_valid(world.production.region): return
	var map_area := Rect2(center - MAP_SIZE / (2.0 * map_scale), MAP_SIZE / map_scale)
	for rect in _buildings:
		if map_area.intersects(rect): target.draw_rect(Rect2(project(rect.position), rect.size * map_scale), STYLE.LINE.darkened(.38))
	for road in _roads:
		if not map_area.intersects(road.bounds.grow(maxf(2.0 / map_scale, road.width))): continue
		var points := PackedVector2Array()
		for point: Vector2 in road.points: points.append(project(point))
		if points.size() > 1:
			target.draw_polyline(points, STYLE.MAP_ROAD, maxf(1.4, road.width * map_scale * 0.35), true)
	if route_points.size() > 1:
		# Clip segments before submitting, avoiding giant polylines outside HUD.
		var bounds := Rect2(Vector2.ZERO, MAP_SIZE)
		for i in route_points.size()-1:
			var a := project(route_points[i])
			var b := project(route_points[i+1])
			if not bounds.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(4), true): continue
			target.draw_line(a, b, STYLE.INK, 4, true)
			target.draw_line(a, b, STYLE.WAYPOINT, 1.5, true)
	# Bounded nearby service icons; the selected mission remains on top.
	drawn_places.clear()
	var nearby: Array[Dictionary] = []
	var icons: Array[Vector2] = []
	# Quem já está na tela continua até sair um pouco além da borda (o recorte esconde a sobra).
	var keep_area := map_area.grow(KEEP_MARGIN / map_scale)
	for place in _places:
		if place.kind=="place": continue
		if not map_area.has_point(place.point) and not (_shown_places.has(place_key(place)) and keep_area.has_point(place.point)): continue
		nearby.append(place)
		icons.append(project(place.point))
	var picked := choose_places(nearby, icons, center, _shown_places, {})
	_shown_places = {}
	for index: int in picked.shown:
		var place: Dictionary = nearby[index]
		var icon: Vector2 = icons[index]
		SYMBOLS.draw(target,icon,place.kind,6.0)
		drawn_places.append(place)
		_shown_places[place_key(place)] = true
	for station in _rail_stations:
		var entry: Vector3 = station.entry
		var point := Vector2(entry.x,entry.z)
		if map_area.has_point(point): preload("res://ui/hud/MapSymbols.gd").draw(target,project(point),"train",7.0)
	var fishing_entry := preload("res://runtime/FishingLocation.gd").ENTRY
	var fishing_point := Vector2(fishing_entry.x,fishing_entry.z)
	if map_area.has_point(fishing_point): preload("res://ui/hud/MapSymbols.gd").draw(target,project(fishing_point),"fishing",7.0)
	if POLICE.active(world): POLICE.draw(target, self, world, map_area, Time.get_ticks_msec() / 1000.0)
	if not destination.is_empty():
		var marker := edge_marker(objective_target)
		var direction := (objective_target-center).normalized()
		if not map_area.has_point(objective_target): target.draw_line(marker,marker+direction*10,STYLE.ACCENT,2,true)
		SYMBOLS.draw(target,marker,str(destination.kind),8.0,true)
	var middle := MAP_SIZE * 0.5
	GLYPHS.draw_rotated(target,"player",middle,25.0,heading,STYLE.INK)
	GLYPHS.draw_rotated(target,"player",middle,19.2,heading,STYLE.COLD)
