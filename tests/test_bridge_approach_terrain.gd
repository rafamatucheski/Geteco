extends SceneTree
## Propriedade territorial do terreno: MountainTerrain nunca cobre via, calçada ou chão
## autorado de Harbor; a serra real, a costura, o tabuleiro e os guarda-corpos permanecem.
## Piso físico (colisores sob o ponto) e piso visual (malhas sobre o ponto) são checados
## separadamente: um pode estar certo com o outro errado.

const REGION = preload("res://world/regions/NativeRegion.gd")
const CONNECTION = preload("res://world/regions/WorldConnection3D.gd")
const WATER_WORDS := ["Ocean", "Water", "Wash", "Sea"]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _is_water(path: String) -> bool:
	for word in WATER_WORDS:
		if path.contains(word): return true
	return false

## Todos os colisores de piso sob o ponto, do mais alto ao mais baixo.
func _floor_hits(point: Vector3) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var exclude: Array[RID] = []
	for _i in 8:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 12.0, point + Vector3.DOWN * 3.0, 1, exclude)
		var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		hits.append({"path": str(hit.collider.get_path()), "y": float(hit.position.y)})
		exclude.append(hit.rid)
	return hits

## Malhas visíveis cujo AABB global cobre o ponto em XZ, com o topo do AABB.
func _visual_cover(region: Node3D, point: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mesh in region.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if point.x < box.position.x or point.x > box.end.x or point.z < box.position.z or point.z > box.end.z: continue
		result.append({"path": str(mesh.get_path()), "name": str(mesh.name), "top": box.end.y})
	return result

func _terrain_cover(mountain: Node3D, point: Vector3) -> int:
	var count := 0
	for item in _visual_cover(mountain, point):
		if item.name == "MountainTerrain": count += 1
	return count

func _terrain_meshes(mountain: Node3D, key: Vector2i) -> int:
	var chunk: Node3D = mountain.chunks.get(key)
	if chunk == null: return 0
	return chunk.find_children("MountainTerrain", "MeshInstance3D", true, false).size()

func _mount_pair(focus: Vector3, with_connection := false) -> Array:
	var harbor: Node3D = REGION.build_region("harbor", focus)
	var mountain: Node3D = REGION.build_region("mountain", focus)
	root.add_child(harbor)
	root.add_child(mountain)
	var connection: Node3D = null
	if with_connection:
		connection = CONNECTION.new()
		root.add_child(connection)
	for _frame in 4: await physics_frame
	return [harbor, mountain, connection]

func _free_pair(pair: Array) -> void:
	for node in pair:
		if node != null and is_instance_valid(node): node.free()
	await physics_frame

## Acesso de Harbor com as duas regiões residentes.
func _check_harbor_access(point: Vector3, label: String) -> void:
	var pair: Array = await _mount_pair(point)
	var harbor: Node3D = pair[0]
	var mountain: Node3D = pair[1]
	check(mountain.chunks.has(mountain._cell(point)), label + ": Mountain streamed the cell (both regions resident)")
	# Físico
	var hits := _floor_hits(point)
	check(not hits.is_empty(), label + " [físico]: ground exists")
	for hit in hits:
		check(not str(hit.path).contains("MountainNativeRegion"), label + " [físico]: no Mountain collider (" + str(hit.path) + ")")
	if not hits.is_empty():
		check(str(hits[0].path).contains("HarborNativeRegion"), label + " [físico]: top floor is Harbor (" + str(hits[0].path) + ")")
		check(absf(float(hits[0].y)) <= 0.06, label + " [físico]: floor level with authored road (" + str(hits[0].y) + ")")
	# Visual
	check(_terrain_cover(mountain, point) == 0, label + " [visual]: no MountainTerrain mesh over the point")
	var harbor_surface := false
	for item in _visual_cover(harbor, point):
		if absf(float(item.top)) <= 0.08 and not _is_water(str(item.path)): harbor_surface = true
	check(harbor_surface, label + " [visual]: Harbor surface mesh at road level")
	await _free_pair(pair)

## Células da fronteira: (7,-2) é quase toda Harbor lógica; a coluna 7 guarda 8 m a
## oeste da costura, onde Harbor não pode ter chão, via ou calçada sob o terreno.
func _check_border_cells() -> void:
	var pair: Array = await _mount_pair(Vector3(480.0, 0.0, -150.0))
	var harbor: Node3D = pair[0]
	var mountain: Node3D = pair[1]
	for key in [Vector2i(7, -2), Vector2i(8, -2)]:
		# Vizinhos são construídos em fatias: garante o chunk completo antes de inspecionar.
		mountain.prepare_collision_at(Vector3((key.x + .5) * 64.0, 0, (key.y + .5) * 64.0))
		check(_terrain_meshes(mountain, key) == 0, "border %s: Harbor-majority cell has no Mountain terrain" % str(key))
	await _free_pair(pair)
	for row in [-3, -4, -6, -7]:
		var key := Vector2i(7, row)
		var focus := Vector3(480.0, 0.0, (row + .5) * 64.0)
		pair = await _mount_pair(focus)
		harbor = pair[0]
		mountain = pair[1]
		check(_terrain_meshes(mountain, key) == 1, "border %s: Mountain side keeps terrain" % str(key))
		for x in [448.5, 452.0, 455.5]:
			for step in 8:
				var point := Vector3(x, 0.0, row * 64.0 + 4.0 + step * 8.0)
				for hit in _floor_hits(point):
					var path := str(hit.path)
					check(not path.contains("HarborNativeRegion") or _is_water(path), "border %s [físico]: Harbor ground under Mountain terrain at %s (%s)" % [str(key), str(point), path])
				for item in _visual_cover(harbor, point):
					var path := str(item.path)
					check(_is_water(path) or not path.contains("/Chunk_"), "border %s [visual]: Harbor mesh under Mountain terrain at %s (%s)" % [str(key), str(point), path])
		await _free_pair(pair)

## Terreno montanhoso real, fora das vias, continua com malha e colisão.
func _check_mountain_hill(key: Vector2i, label: String) -> void:
	var rect := Rect2(Vector2(key) * 64.0, Vector2.ONE * 64.0)
	var mountain: Node3D = REGION.build_region("mountain", Vector3(rect.get_center().x, 0.0, rect.get_center().y))
	root.add_child(mountain)
	for _frame in 3: await physics_frame
	check(_terrain_meshes(mountain, key) == 1, label + " [visual]: Mountain terrain mesh present")
	var best := Vector2.ZERO
	var best_height := -INF
	for x in range(4, 61, 4):
		for z in range(4, 61, 4):
			var sample := rect.position + Vector2(x, z) + Vector2(1.3, 1.7)
			var height: float = mountain.terrain.surface_height_at(sample)
			if height > best_height and not mountain.terrain.is_reserved(sample, 2.0):
				best_height = height
				best = sample
	check(best_height > 1.0, label + ": off-road hill higher than 1 m (" + str(best_height) + ")")
	var point := Vector3(best.x, best_height, best.y)
	check(_terrain_cover(mountain, point) >= 1, label + " [visual]: terrain mesh covers the hill point")
	var hits := _floor_hits(point)
	check(not hits.is_empty() and str(hits[0].path).contains("MountainTerrain"), label + " [físico]: hill collider is Mountain terrain")
	if not hits.is_empty():
		check(absf(float(hits[0].y) - best_height) <= 0.05, label + " [físico]: collider matches visual terrain height")
	mountain.free()
	await physics_frame

## Costura, tabuleiro e guarda-corpos com Harbor, Mountain e a conexão residentes.
func _check_bridge_seam() -> void:
	var pair: Array = await _mount_pair(Vector3(452.0, 0.0, -285.0), true)
	var gap := CONNECTION.inner_gap_polygon()
	for x in [413.0, 430.0, 445.0]:
		check(Geometry2D.is_point_in_polygon(Vector2(x, CONNECTION.CENTER_Z), gap),
			"approach [visual]: asphalt covers the driving median at x=%s" % x)
	var deck: MeshInstance3D = pair[2].find_child("ContinuousBridgeDeck", true, false)
	check(deck != null and (deck.global_transform * deck.get_aabb()).end.y < -0.015,
		"deck [visual]: structural concrete stays below the mountain asphalt")
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.88
	actor.add_child(shape)
	root.add_child(actor)
	actor.global_position = Vector3(449.0, 0.0, -285.0)
	var collision = actor.move_and_collide(Vector3(10.0, 0.0, 0.0), true)
	check(collision == null, "seam [físico]: Harbor deck to Mountain road has no raised collision lip")
	actor.free()
	for x in [452.0, 462.0, 490.0, 530.0]:
		for z in [-283.0, -287.0]:
			var hits := _floor_hits(Vector3(x, 0.0, z))
			check(not hits.is_empty() and absf(float(hits[0].y)) <= 0.06, "deck [físico]: level floor at (%s, %s)" % [x, z])
			for hit in hits:
				check(not str(hit.path).contains("MountainTerrain"), "deck [físico]: no Mountain terrain under the deck at (%s, %s)" % [x, z])
	var mountain: Node3D = pair[1]
	for x in [470.0, 520.0]:
		check(_terrain_cover(mountain, Vector3(x, 0.0, -285.0)) == 0, "deck [visual]: no MountainTerrain mesh over the deck at x=%s" % x)
	for side in [-1.0, 1.0]:
		var rail_hit := false
		var query := PhysicsRayQueryParameters3D.create(Vector3(500.0, 0.68, -285.0), Vector3(500.0, 0.68, -285.0 + side * 9.0), 1)
		var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
		# O segundo guarda-corpo recebe nome automático (mesmo nome no mesmo pai): vale a posição.
		if not hit.is_empty() and str(hit.collider.get_path()).contains("HarborMountainConnection") \
				and absf(absf(float(hit.position.z) - CONNECTION.CENTER_Z) - CONNECTION.BRIDGE_HALF_WIDTH) <= 0.3:
			rail_hit = true
		check(rail_hit, "deck [físico]: guard rail stops lateral exit on side %s" % side)
	await _free_pair(pair)

func run() -> void:
	await _check_harbor_access(Vector3(292.64, 0.0, -114.15), "island esplanade")
	await _check_harbor_access(Vector3(320.6146, 0.0, -123.0074), "northbank gateway avenue")
	await _check_harbor_access(Vector3(403.0622, 0.0, -97.92917), "eastgate drive")
	await _check_harbor_access(Vector3(382.3698, 0.0, -158.8183), "map2 highway bridge approach")
	await _check_border_cells()
	await _check_bridge_seam()
	await _check_mountain_hill(Vector2i(8, -7), "mountain north of bridge")
	await _check_mountain_hill(Vector2i(11, -6), "mountain east of tunnel")
	for failure in failures: push_error(failure)
	print("BRIDGE_APPROACH_TERRAIN ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
