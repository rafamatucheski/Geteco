extends RefCounted
## Corte da cidade sobre o Túnel do canal. Enquanto o alvo da câmera está no fundo do
## túnel, o que fica entre a câmera e o tubo (laje do cais e da esplanada, prédios,
## postes, guindastes, árvores) vira quase transparente; ao sair, tudo volta ao normal.
##
## O renderizador é o Mobile, que ignora `GeometryInstance3D.transparency`. Por isso o
## fade troca o material por uma cópia com alfa, uma cópia por material de origem
## (dezenas, não milhares): um único valor de alfa por quadro atualiza todas. Nós com
## `ShaderMaterial` (mar, pintura de parede do túnel, atores) não entram: ficam opacos.
##
## Seleção: o corredor do túnel (janela em X em volta do foco) varrido em direção à
## câmera. Coisa baixa (chão, asfalto, calçada) só some sobre o trecho coberto, senão
## revelaria o vazio sob o chão ao lado da vala. Sem sombra enquanto está apagado: a
## sombra da laje escureceria justamente o tubo que o corte quer mostrar.

const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Entrar no túnel travava 400–950 ms (log 2026-10-12, x 163–315): varrer todos os chunks e trocar
## centenas de materiais num único quadro. O trabalho agora cabe num orçamento por quadro e o
## resto continua no seguinte; o cache de caixas é aquecido antes de o corte começar.
const FRAME_BUDGET_USEC := 2000
## Mínimo por quadro mesmo estourando o orçamento: a primeira troca paga custo de partida a frio.
## Em jogo a câmera baixa isto: cada troca custou ~6 ms no release (fade_batch de 95 ms com 16).
var min_fades_per_frame := 16

const MIN_ALPHA := 0.14
const MAX_KEPT_COPIES := 192
const RESCAN_SECONDS := 0.4
const CACHE_SECONDS := 3.0
## Abaixo disto o topo do nó é "chão": só entra sobre o trecho coberto.
const FLAT_TOP := 0.5
const SWEEP_LENGTH := 46.0
const SWEEP_STEPS := 8
## Peças do próprio túnel que podem sumir: a laje e o teto dos trechos cobertos.
const TUNNEL_COVER := ["CanalTunnelBatch_roof_top", "CanalTunnelBatch_ceiling"]

## id do material de origem -> {"copy", "alpha", "source" (WeakRef), "used"}. As cópias sobrevivem ao
## `release()`: a primeira atribuição de um material com alfa custa ~25 ms (variante de shader nova,
## medido em 2026-10-13) e o shader é liberado junto com a última cópia, então descartá-las fazia
## toda passagem pelo túnel pagar de novo (fade_node de ~20 ms cada no release).
var _copies: Dictionary = {}
var _states: Dictionary = {} # id do nó -> estado original
var _cache: Dictionary = {} # id do chunk -> {"count": int, "time": float, "items": Array}
var _clock := 0.0
var _last_scan := -100.0
var _alpha := 1.0
## Nós escolhidos pela varredura, ainda esperando a troca de material (id -> nó).
var _pending: Dictionary = {}
var _scan_incomplete := false
var _missing_items := false

## `chunks`: nós de chunk da região. `to_camera`: direção do foco para a câmera.
## `strength`: 0 fora do túnel, 1 no fundo.
func update(chunks: Array, focus: Vector3, to_camera: Vector3, half_width: float, strength: float, delta: float) -> void:
	_clock += maxf(delta, 0.0)
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.0:
		if not _states.is_empty(): release()
		return
	_alpha = lerpf(1.0, MIN_ALPHA, strength)
	var began := STALL_WORK.begin()
	var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
	if _scan_incomplete or _clock - _last_scan >= RESCAN_SECONDS:
		_last_scan = _clock
		var scan_began := STALL_WORK.begin()
		_rescan(chunks, focus, to_camera, half_width, deadline)
		STALL_WORK.finish_slow("tunnel.cutaway.rescan", scan_began, 1500)
	_drain_pending(deadline)
	for entry in _copies.values():
		if not entry.used: continue
		var copy: StandardMaterial3D = entry.copy
		var color := copy.albedo_color
		color.a = float(entry.alpha) * _alpha
		copy.albedo_color = color

## Esquenta o cache de caixas dos chunks sob a janela do túnel antes de o corte começar.
func prewarm(chunks: Array) -> void:
	var began := STALL_WORK.begin()
	var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
	for chunk in chunks:
		if Time.get_ticks_usec() >= deadline: break
		if is_instance_valid(chunk): _items(chunk, deadline)
	STALL_WORK.finish_slow("tunnel.cutaway.prewarm", began, 1500)

## Aplica as trocas de material pendentes dentro do orçamento do quadro.
func _drain_pending(deadline: int) -> void:
	if _pending.is_empty(): return
	var began := STALL_WORK.begin()
	var done := 0
	for id in _pending.keys():
		if done >= min_fades_per_frame and Time.get_ticks_usec() >= deadline: break
		var node: Variant = _pending[id]
		_pending.erase(id)
		if is_instance_valid(node) and not _states.has(id):
			var node_began := STALL_WORK.begin()
			_fade(node)
			# Com classe, malhas e superfícies: cada troca custou 8-18 ms no release e não sabemos por quê.
			if node_began != 0 and Time.get_ticks_usec() - node_began >= 2000:
				var detail := {"class": node.get_class(), "name": String(node.name)}
				if node is MeshInstance3D and node.mesh != null: detail["surfaces"] = node.mesh.get_surface_count()
				if node is MultiMeshInstance3D and node.multimesh != null: detail["instances"] = node.multimesh.instance_count
				STALL_WORK.finish("tunnel.cutaway.fade_node", node_began, detail)
		done += 1
	STALL_WORK.finish_slow("tunnel.cutaway.fade_batch", began, 1500)

## Devolve todos os nós ao estado original.
func release() -> void:
	_pending.clear()
	_scan_incomplete = false
	for id in _states.keys():
		_restore(id)
	_states.clear()
	for key in _copies.keys():
		var entry: Dictionary = _copies[key]
		entry.used = false
		# Origem já destruída (chunk liberado): a cópia não será reaproveitada. Limite evita crescer sem fim.
		if _copies.size() > MAX_KEPT_COPIES and entry.source.get_ref() == null: _copies.erase(key)
	_last_scan = -100.0
	_alpha = 1.0

func faded_count() -> int:
	return _states.size()

func _rescan(chunks: Array, focus: Vector3, to_camera: Vector3, half_width: float, deadline: int) -> void:
	var direction := to_camera.normalized() if to_camera.length_squared() > 0.0001 else Vector3(0, 0.94, 0.34)
	if direction.y < 0.2: direction = Vector3(direction.x, 0.2, direction.z).normalized()
	var base := AABB(Vector3(focus.x - half_width, -8.0, TUNNEL.outer_north() - 0.5), Vector3(half_width * 2.0, 8.0, TUNNEL.outer_south() - TUNNEL.outer_north() + 1.0))
	var sweep: Array[AABB] = []
	for step in SWEEP_STEPS + 1:
		var moved := base
		moved.position += direction * (SWEEP_LENGTH * float(step) / SWEEP_STEPS)
		sweep.append(moved)
	# Trecho fechado por cima: coberto sob o cais/esplanada e o tubo sob o canal (onde
	# ficam o Northstar atracado e a lâmina de água). Nas rampas abertas não há o que tirar.
	var closed := Rect2(TUNNEL.W_PORTAL, TUNNEL.outer_north(), TUNNEL.E_PORTAL - TUNNEL.W_PORTAL, TUNNEL.outer_south() - TUNNEL.outer_north()).grow(-0.05)
	var window := Rect2(base.position.x, base.position.z, base.size.x, base.size.z)
	var wanted := {}
	_missing_items = false
	for chunk in chunks:
		if not is_instance_valid(chunk): continue
		for item in _items(chunk, deadline):
			if not is_instance_valid(item.node): continue
			var node: GeometryInstance3D = item.node
			if not node.is_visible_in_tree(): continue
			var box: AABB = item.box
			if box.end.x < base.position.x or box.position.x > base.end.x: continue
			var picked := false
			if bool(item.tunnel):
				picked = item.name in TUNNEL_COVER and _over_cover(box, closed, window)
			elif box.end.y < FLAT_TOP:
				picked = _over_cover(box, closed, window)
			else:
				for moved in sweep:
					if moved.intersects(box):
						picked = true
						break
			if picked: wanted[node.get_instance_id()] = node
	# Chunk ainda sem cache e sem orçamento: o resultado é parcial, então nada é devolvido
	# agora (restauraria nós de chunks não varridos) e a varredura repete no próximo quadro.
	_scan_incomplete = _missing_items
	if not _missing_items:
		for id in _states.keys():
			if not wanted.has(id):
				_restore(id)
				_states.erase(id)
		for id in _pending.keys():
			if not wanted.has(id): _pending.erase(id)
	for id in wanted:
		if not _states.has(id): _pending[id] = wanted[id]

func _over_cover(box: AABB, closed: Rect2, window: Rect2) -> bool:
	var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	return footprint.intersects(window) and footprint.intersects(closed)

## Nós visuais do chunk com a caixa no mundo, recalculados quando o chunk ganha filhos
## (o chunk é montado em fatias) ou a cada `CACHE_SECONDS`.
func _items(chunk: Node3D, deadline: int = 0) -> Array:
	var id := chunk.get_instance_id()
	var count := chunk.get_child_count()
	var cached: Variant = _cache.get(id)
	if cached is Dictionary and int(cached.count) == count and _clock - float(cached.time) < CACHE_SECONDS:
		return cached.items
	# Sem orçamento: reaproveita a lista velha (caixas de geometria estática); sem lista, pula.
	if deadline > 0 and Time.get_ticks_usec() >= deadline:
		if cached is Dictionary: return cached.items
		_missing_items = true
		return []
	var began := STALL_WORK.begin()
	var items: Array = []
	for found in chunk.find_children("*", "GeometryInstance3D", true, false):
		var node := found as GeometryInstance3D
		if node == null or not (node is MeshInstance3D or node is MultiMeshInstance3D or node is Label3D): continue
		var parent := node.get_parent()
		items.append({"node": node, "box": node.global_transform * node.get_aabb(), "name": String(node.name), "tunnel": parent != null and parent.is_in_group("canal_tunnel")})
	_cache[id] = {"count": count, "time": _clock, "items": items}
	STALL_WORK.finish_slow("tunnel.cutaway.items", began, 1500)
	return items

func _fade(node: GeometryInstance3D) -> bool:
	var state := {"node": node, "shadow": node.cast_shadow}
	var changed := false
	if node is Label3D:
		var label := node as Label3D
		state["modulate"] = label.modulate
		changed = true
	elif node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null: return false
		state["override"] = mesh_node.material_override
		if mesh_node.material_override != null:
			var replaced := _copy_of(mesh_node.material_override)
			if replaced != null:
				mesh_node.material_override = replaced
				changed = true
		else:
			var surfaces: Array = []
			for surface in mesh_node.mesh.get_surface_count():
				surfaces.append(mesh_node.get_surface_override_material(surface))
				var replaced := _copy_of(mesh_node.get_active_material(surface))
				if replaced != null:
					mesh_node.set_surface_override_material(surface, replaced)
					changed = true
			state["surfaces"] = surfaces
	elif node is MultiMeshInstance3D:
		var multi := node as MultiMeshInstance3D
		state["override"] = multi.material_override
		var source: Material = multi.material_override
		if source == null and multi.multimesh != null and multi.multimesh.mesh != null and multi.multimesh.mesh.get_surface_count() == 1:
			source = multi.multimesh.mesh.surface_get_material(0)
		var replaced := _copy_of(source)
		if replaced != null:
			multi.material_override = replaced
			changed = true
	if not changed: return false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_states[node.get_instance_id()] = state
	if node is Label3D:
		var label := node as Label3D
		var color := label.modulate
		color.a = float(state["modulate"].a) * _alpha
		label.modulate = color
	return true

## Cópia com alfa do material (uma por material de origem). Só StandardMaterial3D.
## Cópia com alfa idêntica à usada no corte: o shader é compartilhado por código, então ela serve
## tanto no corte quanto no pré-aquecimento.
static func make_alpha_copy(source: StandardMaterial3D) -> StandardMaterial3D:
	var copy: StandardMaterial3D = source.duplicate()
	copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return copy

## Materiais que `_fade` trocaria neste nó (mesma escolha de `_fade`).
static func _fadeable_materials(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null: return found
		if mesh_node.material_override != null: found.append(mesh_node.material_override)
		else:
			for surface in mesh_node.mesh.get_surface_count(): found.append(mesh_node.get_active_material(surface))
	elif node is MultiMeshInstance3D:
		var multi := node as MultiMeshInstance3D
		var source: Material = multi.material_override
		if source == null and multi.multimesh != null and multi.multimesh.mesh != null and multi.multimesh.mesh.get_surface_count() == 1:
			source = multi.multimesh.mesh.surface_get_material(0)
		found.append(source)
	return found

static var _primed: Dictionary = {}

## Área do chão cujos chunks o corte pode apagar (janela do túnel coberto mais a varredura).
static func corridor_rect() -> Rect2:
	return Rect2(TUNNEL.W_PORTAL - 70.0, TUNNEL.outer_north() - 70.0, TUNNEL.E_PORTAL - TUNNEL.W_PORTAL + 140.0, TUNNEL.outer_south() - TUNNEL.outer_north() + 140.0)
static var _primer: MeshInstance3D

## Pré-aquece as variantes de shader do corte: a primeira atribuição de um material com alfa custa
## ~25 ms (variante nova) e só os chunks do corredor do túnel interessam. Chamado atrás da tela
## de carregamento, uma vez por chunk aquecido; as cópias ficam vivas para o shader não morrer.
static func prime(chunk: Node3D, holder: Node, cell_rect: Rect2) -> void:
	var began := STALL_WORK.begin()
	if not corridor_rect().intersects(cell_rect): return
	if not is_instance_valid(_primer):
		_primer = MeshInstance3D.new()
		_primer.name = "TunnelCutawayPrimer"
		_primer.mesh = BoxMesh.new()
		_primer.position = Vector3(0, -2000.0, 0)
		holder.add_child(_primer)
	var primed := 0
	for found in chunk.find_children("*", "GeometryInstance3D", true, false):
		for source in _fadeable_materials(found):
			if not source is StandardMaterial3D: continue
			var key: int = source.get_instance_id()
			if _primed.has(key) and _primed[key].source.get_ref() == source: continue
			var copy := make_alpha_copy(source)
			_primer.material_override = copy
			_primed[key] = {"copy": copy, "source": weakref(source)}
			primed += 1
	STALL_WORK.finish("tunnel.cutaway.prime", began, {"chunk": String(chunk.name), "materials": primed})

## Pré-aquece só estes materiais (os da fusão por trecho, compartilhados entre trechos). prime() varre o
## trecho inteiro e, chamado depois de cada fusão em jogo, recompilava material de trecho recém-montado:
## picos de até 322 ms no log de 15/10.
static func prime_materials(materials: Array, holder: Node, cell_rect: Rect2) -> void:
	if not corridor_rect().intersects(cell_rect) or materials.is_empty(): return
	var began := STALL_WORK.begin()
	if not is_instance_valid(_primer):
		_primer = MeshInstance3D.new()
		_primer.name = "TunnelCutawayPrimer"
		_primer.mesh = BoxMesh.new()
		_primer.position = Vector3(0, -2000.0, 0)
		holder.add_child(_primer)
	var primed := 0
	for source in materials:
		if not source is StandardMaterial3D: continue
		var key: int = source.get_instance_id()
		if _primed.has(key) and _primed[key].source.get_ref() == source: continue
		var copy := make_alpha_copy(source)
		_primer.material_override = copy
		_primed[key] = {"copy": copy, "source": weakref(source)}
		primed += 1
	if primed > 0: STALL_WORK.finish("tunnel.cutaway.prime_materials", began, {"materials": primed})

func _copy_of(source: Material) -> StandardMaterial3D:
	if not source is StandardMaterial3D: return null
	var key := source.get_instance_id()
	if _copies.has(key):
		var known: Dictionary = _copies[key]
		# O id pode ser reaproveitado depois que o material de origem morre: só vale a mesma instância.
		if known.source.get_ref() == source:
			known.used = true
			var reused: StandardMaterial3D = known.copy
			var tint := reused.albedo_color
			tint.a = float(known.alpha) * _alpha
			reused.albedo_color = tint
			return reused
		_copies.erase(key)
	var copy := make_alpha_copy(source)
	var entry := {"copy": copy, "alpha": copy.albedo_color.a, "source": weakref(source), "used": true}
	var color := copy.albedo_color
	color.a = float(entry.alpha) * _alpha
	copy.albedo_color = color
	_copies[key] = entry
	return copy

func _restore(id: int) -> void:
	var state: Dictionary = _states[id]
	if not is_instance_valid(state.node): return
	var node: GeometryInstance3D = state.node
	node.cast_shadow = state.shadow
	if node is Label3D:
		(node as Label3D).modulate = state.modulate
	elif node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_node.material_override = state.override
		if state.has("surfaces"):
			var surfaces: Array = state.surfaces
			for surface in surfaces.size():
				mesh_node.set_surface_override_material(surface, surfaces[surface])
	elif node is MultiMeshInstance3D:
		(node as MultiMeshInstance3D).material_override = state.override
