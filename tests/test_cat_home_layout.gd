extends SceneTree
const LAYOUT := preload("res://runtime/cats/CatHomeLayout.gd")
var checks := 0
var failures: Array[String] = []

class FloorFixture extends Node3D:
	var definition := {"size":Vector2(8, 8)}
	var interaction_points := {}
	var solids: Array[Rect2] = []
	var spawn_position: Vector3:
		get: return to_global(Vector3(0, 0, 3))
	var exit_position: Vector3:
		get: return to_global(Vector3(0, 0, 3.4))
	func is_floor_clear(point: Vector3, radius := .32) -> bool:
		for rect in solids:
			if rect.grow(radius).has_point(Vector2(point.x, point.z)): return false
		return true

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CAT_LAYOUT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var room := FloorFixture.new()
	root.add_child(room)
	room.position = Vector3(53, 7, -21)
	room.rotation.y = PI * .5
	room.solids.assign([Rect2(-4, -.15, 3.4, .3), Rect2(.6, -.15, 3.4, .3), Rect2(-2.7, -2.0, 1.2, .7)])
	room.interaction_points = {"wardrobe":room.to_global(Vector3(-2, 0, -2.8)), "food":room.to_global(Vector3(2, 0, -2.8)), "save":room.to_global(Vector3(2, 0, 2.8))}
	var paths := LAYOUT.protected_paths(room)
	check(not paths.is_empty() and room.get_meta("cat_layout_unreachable_stations").is_empty(), "BFS encontra caminho até todas as interações através da única porta")
	var free := true
	var door_reserved := false
	var unique := {}
	for point in paths:
		var local := room.to_local(point)
		free = free and room.is_floor_clear(local, .36)
		door_reserved = door_reserved or (absf(local.x) < .15 and absf(local.z) < .15)
		unique[point] = true
	check(free, "reservas respeitam sólidos e raio completo do jogador")
	check(door_reserved, "passagem estreita indispensável fica reservada")
	check(unique.size() == paths.size(), "rotas compartilhadas não duplicam posições")
	check(_contains(paths, room.spawn_position) and _contains(paths, room.exit_position), "spawn e saída são protegidos em coordenadas world")
	for id in room.interaction_points:
		var nearest := INF
		for point in paths: nearest = minf(nearest, point.distance_to(room.interaction_points[id]))
		check(nearest < .46, "rota alcança a aproximação de " + id)
	var doorway_prop := Rect2(-.25, -.25, .5, .5).grow(.4)
	var blocked := false
	for point in paths:
		var local := room.to_local(point)
		blocked = blocked or doorway_prop.has_point(Vector2(local.x, local.z))
	check(blocked, "móvel candidato que fecharia a porta cruza a reserva")
	room.solids.append(Rect2(-.6, -.15, 1.2, .3))
	var closed := LAYOUT.protected_paths(room)
	var unreachable: Array = room.get_meta("cat_layout_unreachable_stations")
	check("food" in unreachable and "wardrobe" in unreachable, "estações isoladas são reportadas sem caminho inventado atravessando parede")
	check(closed.size() > paths.size(), "caminho impossível reserva conservadoramente o componente alcançável")
	room.solids.assign([Rect2(-4, -.2, 6.375, .4), Rect2(3.375, -.2, .625, .4)])
	room.interaction_points = {"backpack":room.to_global(Vector3(2.9, 0, -2))}
	var shifted := LAYOUT.protected_paths(room)
	check(not shifted.is_empty() and room.get_meta("cat_layout_unreachable_stations").is_empty(), "fase alternativa encontra corredor real entre amostras sem reduzir raio do ator")
	room.queue_free()
	print("CAT_LAYOUT_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _contains(points: Array[Vector3], target: Vector3) -> bool:
	for point in points:
		if point.distance_to(target) < .001: return true
	return false
