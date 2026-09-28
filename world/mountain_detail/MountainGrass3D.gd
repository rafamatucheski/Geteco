extends Node3D
## Capim 3D do chão de Mountain, em volta do jogador.
##
## O chão só tinha cor e parecia imagem esticada vista de perto (relato do jogador
## em 2026-09-24). Aqui tufos de folhas finas cobrem o chão sem neve num raio de
## RADIUS: blocos de TILE metros, cada um uma MultiMesh (uma chamada de desenho),
## montados no máximo TILES_PER_FRAME por quadro e soltos quando o jogador se
## afasta. A neve é decidida no shader com a mesma função do terreno.
##
## Não nasce capim: na estrada e na trilha (até a borda da trilha), dentro da
## bacia dos lagos, e onde há algo em cima do chão (casa, pedra: raio acha outra
## coisa acima do terreno).

const SHADER := preload("res://world/mountain_detail/mountain_grass.gdshader")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const TILE := 16.0
const RADIUS := 44.0
const SPACING := 0.85
const TILES_PER_FRAME := 2
const FOOTPRINT := 0.65 # Includes the tallest tuft's lean and wind displacement.

var controller
var _tiles: Dictionary = {} # Vector2i -> MultiMeshInstance3D
var _queue: Array[Vector2i] = []
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _region
var _clock := 0.0

func _ready() -> void:
	name = "MountainGrass"
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	CONNECTION.configure_ground_material(_material)
	_mesh = _tuft_mesh()

func _physics_process(delta: float) -> void:
	var region = controller.regions.get("mountain") if controller != null else null
	var outdoors: bool = controller != null and controller.state.place_id.is_empty()
	visible = outdoors
	if not outdoors or not is_instance_valid(region) or region.get("terrain") == null:
		if not _tiles.is_empty(): _clear()
		_queue.clear()
		return
	if region != _region:
		_clear()
		_region = region
	# Drop vegetation with its supporting chunk, including unload/reload of the same cell.
	for key in _tiles.keys():
		var chunk: Node3D = _support_chunk(key)
		if not is_instance_valid(chunk) or chunk.get_instance_id() != int(_tiles[key].get_meta("support_chunk", 0)):
			_tiles[key].queue_free()
			_tiles.erase(key)
	var built := 0
	var remaining: Array[Vector2i] = []
	for key in _queue:
		if built >= TILES_PER_FRAME or not is_instance_valid(_support_chunk(key)):
			remaining.append(key)
			continue
		if not _tiles.has(key): _build_tile(key)
		built += 1
	_queue = remaining
	_clock += delta
	if _clock < 0.3: return
	_clock = 0.0
	# Interiors move the player to a separate part of the world. NativeRegion
	# keeps the exterior focus there, so preserve its tiles for the return trip.
	var focus: Vector3 = region.focus
	var center := Vector2i(floori(focus.x / TILE), floori(focus.z / TILE))
	var reach := ceili(RADIUS / TILE)
	var wanted := {}
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			var key := center + Vector2i(x, z)
			var middle := (Vector2(key) + Vector2(0.5, 0.5)) * TILE
			if middle.distance_to(Vector2(focus.x, focus.z)) > RADIUS + TILE * 0.7: continue
			if not region._mountain_owns_terrain(region._cell(Vector3(middle.x, 0, middle.y))): continue
			wanted[key] = true
			if not _tiles.has(key) and key not in _queue: _queue.append(key)
	for key in _tiles.keys():
		if not wanted.has(key):
			_tiles[key].queue_free()
			_tiles.erase(key)
	_queue.assign(_queue.filter(func(k): return wanted.has(k)))
	_queue.sort_custom(func(a, b): return Vector2(a - center).length_squared() < Vector2(b - center).length_squared())

func _support_chunk(key: Vector2i) -> Node3D:
	var corner := Vector2(key) * TILE
	var cell: Vector2i = _region._cell(Vector3(corner.x, 0, corner.y))
	if not _region._mountain_owns_terrain(cell): return null
	var chunk: Node3D = _region.chunks.get(cell)
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return null
	# Wait for authored buildings and their physics bodies, not only the ground stage.
	if int(chunk.get_meta("vegetation_ready_frame", Engine.get_physics_frames())) >= Engine.get_physics_frames(): return null
	return chunk

func _clear() -> void:
	for tile in _tiles.values(): tile.queue_free()
	_tiles.clear()
	_queue.clear()

func _build_tile(key: Vector2i) -> void:
	var terrain = _region.terrain
	var corner := Vector2(key) * TILE
	var chunk := _support_chunk(key)
	if not is_instance_valid(chunk): return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var space := get_world_3d().direct_space_state
	var transforms: Array[Transform3D] = []
	var steps := int(TILE / SPACING)
	for ix in steps:
		for iz in steps:
			var at := corner + (Vector2(ix, iz) + Vector2(rng.randf(), rng.randf())) * SPACING
			# Shared spatial reservations cover complete road segments, water and rooms,
			# even before their meshes exist. A nearby road vertex is not sufficient.
			if terrain.is_reserved(at, FOOTPRINT): continue
			var y: float = terrain.surface_height_at(at)
			# Rampa da bacia de lago: capim até perto da água (linha d'água em -0,2);
			# só a beira molhada fica sem.
			if y < -0.1: continue
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, y + 6.0, at.y), Vector3(at.x, y - 1.0, at.y), 1))
			# Fail closed: empty space, pavement, furniture and walls are never soil.
			if hit.is_empty() or not hit.collider.get_meta("mountain_terrain", false): continue
			if absf(float(hit.position.y) - y) > 0.08 or hit.normal.y < 0.8: continue
			var s := rng.randf_range(0.7, 1.35)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
			transforms.append(Transform3D(basis, Vector3(at.x, y, at.y)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size(): multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "GrassTile_%d_%d" % [key.x, key.y]
	instance.multimesh = multimesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("support_chunk", chunk.get_instance_id())
	add_child(instance)
	# Canto do chunk de 64 m, como o terreno: mesma coordenada de ruído.
	instance.set_instance_shader_parameter("origin", (corner / 64.0).floor() * 64.0)
	_tiles[key] = instance

## Tufo: 9 folhas finas em leque, cada uma um triângulo com leve curva.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719
	for i in 9:
		var angle := TAU * float(i) / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-out.z, 0, out.x)
		var height := rng.randf_range(0.22, 0.42)
		var lean := rng.randf_range(0.06, 0.16)
		var width := rng.randf_range(0.025, 0.04)
		var root := out * rng.randf_range(0.0, 0.07)
		var mid := root + out * lean * 0.4 + Vector3.UP * height * 0.55
		var tip := root + out * lean + Vector3.UP * height
		# Duas faixas (base→meio→ponta) para a folha curvar em vez de ser um triângulo reto.
		var quads := [[root - side * width, root + side * width, mid + side * width * 0.6, mid - side * width * 0.6, 0.0, 0.55]]
		for q in quads:
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(0, q[4] if idx < 2 else q[5]))
				st.set_normal(Vector3.UP)
				st.add_vertex(q[idx])
		for v in [[mid - side * width * 0.6, 0.55], [mid + side * width * 0.6, 0.55], [tip, 1.0]]:
			st.set_uv(Vector2(0, v[1]))
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	return st.commit()
