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
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
## Estoque de blocos (16/10): cada bloco novo criava um MultiMesh e o bloco que saía destruía o dele, o
## que na emenda da ponte vira criação/destruição de buffers de vídeo a cada passo (o driver segura a
## thread principal ao destruir). Com capacidade fixa (o máximo de tufos de um bloco) o buffer é o mesmo
## e só o conteúdo muda. GETECO_GRASS_POOL=0 volta ao comportamento antigo.
const POOL_LIMIT := 48
## int(TILE / SPACING) ao quadrado: o laço de _build_tile tenta no máximo 18 x 18 tufos.
const CAPACITY := 324
static var _pooling := OS.get_environment("GETECO_GRASS_POOL") != "0"
## Montagem fatiada (17/10): cada bloco testa até 324 pontos (reserva, altura e um raio de física cada) e
## eram 2 blocos inteiros por passo de física, sem span. Na rota da serra, nos trechos sem neve, isso dava
## um passo de física de 28-45 ms a cada fileira nova de blocos (EXE de 17/10, 15-38 quadros > 33 ms por
## rodada). Agora os pontos são testados em fatias de BUILD_BUDGET_USEC por passo e o bloco só aparece
## quando termina. GETECO_GRASS_SLICED=0 volta aos 2 blocos inteiros por passo (A/B).
const BUILD_BUDGET_USEC := 2000
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
static var _sliced := OS.get_environment("GETECO_GRASS_SLICED") != "0"
var _job: Dictionary = {}

var controller
var _tiles: Dictionary = {} # Vector2i -> MultiMeshInstance3D
var _pool: Array[MultiMeshInstance3D] = []
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
		_job = {}
		return
	if region != _region:
		_clear()
		_region = region
	# Drop vegetation with its supporting chunk, including unload/reload of the same cell.
	for key in _tiles.keys():
		var chunk: Node3D = _support_chunk(key)
		if not is_instance_valid(chunk) or chunk.get_instance_id() != int(_tiles[key].get_meta("support_chunk", 0)):
			_release_tile(key)
	var traced := STALL_WORK.begin()
	if _sliced: _advance_build(Time.get_ticks_usec())
	else:
		var built := 0
		var remaining: Array[Vector2i] = []
		for key in _queue:
			if built >= TILES_PER_FRAME or not is_instance_valid(_support_chunk(key)):
				remaining.append(key)
				continue
			if not _tiles.has(key): _build_tile(key)
			built += 1
		_queue = remaining
	STALL_WORK.finish_slow("mountain.grass.build", traced, 2000)
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
			_release_tile(key)
	_queue.assign(_queue.filter(func(k): return wanted.has(k)))
	if not _job.is_empty() and not wanted.has(_job.key): _job = {}
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
	for key in _tiles.keys(): _release_tile(key)
	_queue.clear()
	_job = {}

## Bloco que sai: volta escondido ao estoque (buffer de vídeo mantido) ou sai pela fila gradual.
func _release_tile(key: Vector2i) -> void:
	var tile: MultiMeshInstance3D = _tiles[key]
	_tiles.erase(key)
	if not is_instance_valid(tile): return
	if _pooling and _pool.size() < POOL_LIMIT and tile.multimesh != null and tile.multimesh.instance_count == CAPACITY:
		tile.visible = false
		tile.set_meta("support_chunk", 0)
		_pool.append(tile)
	else:
		GPU_RELEASE.retire(tile)

func _build_tile(key: Vector2i) -> void:
	var job := _begin_tile(key)
	if job.is_empty(): return
	_sample_tile(job, 0, INF)
	_commit_tile(job)

## Fatias: o bloco da frente da fila é amostrado até o orçamento acabar; sobra para o próximo passo.
func _advance_build(began: int) -> void:
	while Time.get_ticks_usec() - began < BUILD_BUDGET_USEC:
		if _job.is_empty():
			var next := -1
			for index in _queue.size():
				if not _tiles.has(_queue[index]) and is_instance_valid(_support_chunk(_queue[index])):
					next = index
					break
			if next < 0: return
			_job = _begin_tile(_queue[next])
			_queue.remove_at(next)
			if _job.is_empty(): continue
		if not _sample_tile(_job, began, BUILD_BUDGET_USEC): return
		# O trecho de apoio pode ter saído ou sido trocado enquanto o bloco era amostrado.
		var chunk := _support_chunk(_job.key)
		if is_instance_valid(chunk) and chunk.get_instance_id() == int(_job.chunk_id) and not _tiles.has(_job.key): _commit_tile(_job)
		_job = {}

func _begin_tile(key: Vector2i) -> Dictionary:
	var chunk := _support_chunk(key)
	if not is_instance_valid(chunk): return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var transforms: Array[Transform3D] = []
	return {"key": key, "chunk_id": chunk.get_instance_id(), "corner": Vector2(key) * TILE, "rng": rng, "steps": int(TILE / SPACING), "next": 0, "transforms": transforms}

## Testa pontos do bloco a partir de job.next; devolve true quando acabou. A ordem dos pontos e das chamadas ao
## gerador é a mesma da montagem inteira, então o bloco sai igual com ou sem fatias.
func _sample_tile(job: Dictionary, began: int, budget_usec: float) -> bool:
	var terrain = _region.terrain
	var corner: Vector2 = job.corner
	var rng: RandomNumberGenerator = job.rng
	var steps: int = job.steps
	var transforms: Array[Transform3D] = job.transforms
	var space := get_world_3d().direct_space_state
	while int(job.next) < steps * steps:
		if Time.get_ticks_usec() - began >= budget_usec: return false
		var ix := int(job.next) / steps
		var iz := int(job.next) % steps
		job.next = int(job.next) + 1
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
		var local_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
		transforms.append(Transform3D(local_basis, Vector3(at.x, y, at.y)))
	return true

func _commit_tile(job: Dictionary) -> void:
	var key: Vector2i = job.key
	var corner: Vector2 = job.corner
	var transforms: Array[Transform3D] = job.transforms
	var instance: MultiMeshInstance3D = _pool.pop_back() if _pooling and not _pool.is_empty() else null
	var multimesh: MultiMesh = instance.multimesh if instance != null else null
	if instance == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _mesh
		# Capacidade fixa com estoque: o mesmo buffer serve qualquer bloco; só visible_instance_count muda.
		multimesh.instance_count = CAPACITY if _pooling else transforms.size()
		instance = MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = _material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	var count := mini(transforms.size(), multimesh.instance_count)
	for i in count: multimesh.set_instance_transform(i, transforms[i])
	multimesh.visible_instance_count = count if _pooling else -1
	# Caixa só dos tufos deste bloco: os que sobram no buffer além de visible_instance_count são de um bloco
	# antigo e alargariam a caixa calculada (bloco desenhado fora da tela).
	if _pooling:
		var bounds := AABB(Vector3(corner.x, 0.0, corner.y), Vector3(TILE, 0.0, TILE))
		for i in count: bounds = bounds.expand(transforms[i].origin)
		instance.custom_aabb = bounds.grow(1.5)
	instance.name = "GrassTile_%d_%d" % [key.x, key.y]
	instance.set_meta("support_chunk", int(job.chunk_id))
	instance.visible = true
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
