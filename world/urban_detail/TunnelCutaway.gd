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

const MIN_ALPHA := 0.14
const RESCAN_SECONDS := 0.4
const CACHE_SECONDS := 3.0
## Abaixo disto o topo do nó é "chão": só entra sobre o trecho coberto.
const FLAT_TOP := 0.5
const SWEEP_LENGTH := 46.0
const SWEEP_STEPS := 8
## Peças do próprio túnel que podem sumir: a laje e o teto dos trechos cobertos.
const TUNNEL_COVER := ["CanalTunnelBatch_roof_top", "CanalTunnelBatch_ceiling"]

var _copies: Dictionary = {} # id do material de origem -> {"copy": StandardMaterial3D, "alpha": float}
var _states: Dictionary = {} # id do nó -> estado original
var _cache: Dictionary = {} # id do chunk -> {"count": int, "time": float, "items": Array}
var _clock := 0.0
var _last_scan := -100.0
var _alpha := 1.0

## `chunks`: nós de chunk da região. `to_camera`: direção do foco para a câmera.
## `strength`: 0 fora do túnel, 1 no fundo.
func update(chunks: Array, focus: Vector3, to_camera: Vector3, half_width: float, strength: float, delta: float) -> void:
	_clock += maxf(delta, 0.0)
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.0:
		if not _states.is_empty(): release()
		return
	_alpha = lerpf(1.0, MIN_ALPHA, strength)
	if _clock - _last_scan >= RESCAN_SECONDS:
		_last_scan = _clock
		_rescan(chunks, focus, to_camera, half_width)
	for entry in _copies.values():
		var copy: StandardMaterial3D = entry.copy
		var color := copy.albedo_color
		color.a = float(entry.alpha) * _alpha
		copy.albedo_color = color

## Devolve todos os nós ao estado original.
func release() -> void:
	for id in _states.keys():
		_restore(id)
	_states.clear()
	_copies.clear()
	_last_scan = -100.0
	_alpha = 1.0

func faded_count() -> int:
	return _states.size()

func _rescan(chunks: Array, focus: Vector3, to_camera: Vector3, half_width: float) -> void:
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
	for chunk in chunks:
		if not is_instance_valid(chunk): continue
		for item in _items(chunk):
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
	for id in _states.keys():
		if not wanted.has(id):
			_restore(id)
			_states.erase(id)
	for id in wanted:
		if not _states.has(id): _fade(wanted[id])

func _over_cover(box: AABB, closed: Rect2, window: Rect2) -> bool:
	var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	return footprint.intersects(window) and footprint.intersects(closed)

## Nós visuais do chunk com a caixa no mundo, recalculados quando o chunk ganha filhos
## (o chunk é montado em fatias) ou a cada `CACHE_SECONDS`.
func _items(chunk: Node3D) -> Array:
	var id := chunk.get_instance_id()
	var count := chunk.get_child_count()
	var cached: Variant = _cache.get(id)
	if cached is Dictionary and int(cached.count) == count and _clock - float(cached.time) < CACHE_SECONDS:
		return cached.items
	var items: Array = []
	for found in chunk.find_children("*", "GeometryInstance3D", true, false):
		var node := found as GeometryInstance3D
		if node == null or not (node is MeshInstance3D or node is MultiMeshInstance3D or node is Label3D): continue
		var parent := node.get_parent()
		items.append({"node": node, "box": node.global_transform * node.get_aabb(), "name": String(node.name), "tunnel": parent != null and parent.is_in_group("canal_tunnel")})
	_cache[id] = {"count": count, "time": _clock, "items": items}
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
func _copy_of(source: Material) -> StandardMaterial3D:
	if not source is StandardMaterial3D: return null
	var key := source.get_instance_id()
	if _copies.has(key): return _copies[key].copy
	var copy: StandardMaterial3D = source.duplicate()
	copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var entry := {"copy": copy, "alpha": copy.albedo_color.a}
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
