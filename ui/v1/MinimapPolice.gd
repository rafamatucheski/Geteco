extends RefCounted
## Camada de polícia do minimapa (perseguição estilo GTA): viaturas, policiais a pé e helicóptero
## como pontos piscando azul/vermelho, e, na BUSCA, o círculo da área e os cones de visão das
## viaturas (PursuitRules). Só lê o despacho e o Gameplay; desenha no canvas do minimapa.

const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const RED := Color("e0473c")
const BLUE := Color("3f7fe6")
const CONE := Color(0.88, 0.28, 0.24, 0.20)
const SEARCH_FILL := Color(0.25, 0.5, 0.9, 0.10)
const SEARCH_LINE := Color(0.35, 0.6, 1.0, 0.55)
const CONE_SEGMENTS := 6

## Algo a desenhar? (o minimapa redesenha a cada atualização enquanto houver).
static func active(world: Node) -> bool:
	if not PURSUIT.enabled or not is_instance_valid(world): return false
	var gameplay: Variant = world.get("gameplay")
	if gameplay == null or not is_instance_valid(gameplay): return false
	if int(gameplay.stars) > 0: return true
	var dispatch: Variant = world.get("dispatch")
	return dispatch != null and is_instance_valid(dispatch) and dispatch.units.any(func(unit): return unit.is_police() and not unit.finished)

## `minimap` fornece project() e o retângulo visível (`map_area`, em metros no plano XZ).
static func draw(target: Control, minimap: Control, world: Node, map_area: Rect2, clock: float) -> void:
	var gameplay: Variant = world.get("gameplay")
	if gameplay == null or not is_instance_valid(gameplay): return
	var dispatch: Variant = world.get("dispatch")
	var searching: bool = int(gameplay.stars) > 0 and float(gameplay.contact_age) > 1.0 and bool(gameplay.last_known_valid)
	var scale: float = minimap.map_scale
	if searching:
		var center := Vector2(gameplay.last_known.x, gameplay.last_known.z)
		var radius: float = gameplay.police_search_radius() if gameplay.has_method("police_search_radius") else 0.0
		if radius > 0.0 and map_area.grow(radius).has_point(center):
			target.draw_circle(minimap.project(center), radius * scale, SEARCH_FILL)
			target.draw_arc(minimap.project(center), radius * scale, 0.0, TAU, 48, SEARCH_LINE, 1.5, true)
	var flash := fposmod(clock * 2.5, 1.0) < 0.5
	if dispatch != null and is_instance_valid(dispatch):
		for unit in dispatch.units:
			if not unit.is_police() or unit.finished or unit.suspended or not is_instance_valid(unit.vehicle): continue
			var car: Node3D = unit.vehicle
			var point := Vector2(car.global_position.x, car.global_position.z)
			if not map_area.grow(PURSUIT.VISION_FRONT).has_point(point): continue
			var forward := -car.global_basis.z
			if searching and unit.state == "enroute": _cone(target, minimap, point, Vector2(forward.x, forward.z), scale)
			if map_area.has_point(point): _blip(target, minimap.project(point), 3.6, flash)
			for officer in unit.officers:
				if is_instance_valid(officer) and not officer.dead: _person(target, minimap, map_area, officer, flash)
	for officer in gameplay.police:
		if is_instance_valid(officer) and not officer.dead: _person(target, minimap, map_area, officer, flash)
	var air: Variant = gameplay.get("police_air")
	if air != null and is_instance_valid(air) and is_instance_valid(air.helicopter):
		var heli: Node3D = air.helicopter
		var heli_point := Vector2(heli.global_position.x, heli.global_position.z)
		if map_area.has_point(heli_point):
			var at: Vector2 = minimap.project(heli_point)
			target.draw_circle(at, 6.0, Color(0, 0, 0, 0.55))
			target.draw_arc(at, 4.5, 0.0, TAU, 16, BLUE if flash else RED, 1.6, true)
			target.draw_line(at - Vector2(4, 0), at + Vector2(4, 0), Color.WHITE, 1.2)

static func _blip(target: Control, at: Vector2, radius: float, flash: bool) -> void:
	target.draw_circle(at, radius + 1.4, Color(0, 0, 0, 0.6))
	target.draw_circle(at, radius, RED if flash else BLUE)

static func _person(target: Control, minimap: Control, map_area: Rect2, officer: Node3D, flash: bool) -> void:
	var point := Vector2(officer.global_position.x, officer.global_position.z)
	if map_area.has_point(point): _blip(target, minimap.project(point), 2.2, not flash)

## Cone de visão da viatura (PursuitRules.VISION_FRONT / VISION_HALF_ANGLE) e o raio curto.
static func _cone(target: Control, minimap: Control, point: Vector2, forward: Vector2, scale: float) -> void:
	if forward.length_squared() < 0.0001: return
	var at: Vector2 = minimap.project(point)
	var heading := forward.angle()
	var polygon := PackedVector2Array([at])
	for index in CONE_SEGMENTS + 1:
		var angle := heading - PURSUIT.VISION_HALF_ANGLE + 2.0 * PURSUIT.VISION_HALF_ANGLE * float(index) / CONE_SEGMENTS
		polygon.append(at + Vector2.from_angle(angle) * PURSUIT.VISION_FRONT * scale)
	target.draw_colored_polygon(polygon, CONE)
	target.draw_circle(at, PURSUIT.VISION_NEAR * scale, Color(CONE, CONE.a * 0.6))
