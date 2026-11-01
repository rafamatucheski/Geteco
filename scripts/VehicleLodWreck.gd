extends RefCounted
## LOD de passos do trânsito ambiente longe da câmera (_lod_stride/_lod_gate), vida e sumiço da
## carcaça (_tick_wreck/_begin_wreck_fade) e o sumiço do carro de trânsito aposentado
## (fade_traffic_retirement). Separado de scripts/Vehicle.gd em 01/11 (Onda 3) só para o dono caber
## na leitura. O dono mantém cada função antiga como delegação de uma linha com a mesma assinatura
## (testes chamam _lod_stride/_lod_gate/_tick_wreck e o DispatchController chama _begin_wreck_fade)
## e reexporta as constantes LOD_*, WRECK_* e RETIRE_SINK_DEPTH.
## O estado lido de fora (_lod_skipped/_lod_pending, que TrafficRails e testes escrevem; _wreck_*,
## _traffic_retirement_meshes, _retire_sunk) continua no Vehicle; as `static var` dele
## (WRECK_SINK_ENABLED, RETIRE_SINK_ENABLED) são lidas por `g.get_script()`. As `static var` da câmera
## do LOD (_lod_camera/_lod_player/_lod_frustum e os quadros) não têm leitor fora do bloco e moram
## aqui: continuam uma por processo, como antes, e o caminho quente não as busca pelo dono.
## `g` fica como CharacterBody3D, e não como o script do dono, para não criar preload cíclico.
## Caminho quente: _lod_gate roda por carro de trânsito e por passo de física, inclusive nos passos
## pulados. Nada aqui aloca por passo; _wreck_expires (sobrescrita em DispatchVehicle e
## DesertHeistTruck) passa por `g.`, e _lod_stride/_begin_wreck_fade, sem sobrescrita, são diretas.

var g: CharacterBody3D

func _init(host: CharacterBody3D) -> void:
	g = host

const LOD_NEAR := 60.0
const LOD_FAR := 110.0
const LOD_OFFSCREEN_NEAR := 45.0
const LOD_VIEW_MARGIN := 12.0
static var _lod_camera: Camera3D
static var _lod_camera_frame := -1
static var _lod_player: Node3D
static var _lod_frustum: Array[Plane] = []
static var _lod_frustum_frame := -1

func _lod_stride() -> int:
	var frame := Engine.get_physics_frames()
	if _lod_camera_frame != frame:
		_lod_camera_frame = frame
		_lod_camera = g.get_viewport().get_camera_3d()
		_lod_player = g.get_parent().get("player") as Node3D
	if not is_instance_valid(_lod_camera): return 1
	var distance_squared := _lod_camera.global_position.distance_squared_to(g.global_position)
	if distance_squared > LOD_FAR*LOD_FAR: return 4
	# Só carros ambientes fora da tela entram mais cedo na simulação de 4 passos existente.
	# Mantém uma borda generosa para o carro, as luzes e a câmera se aproximando; o trânsito
	# visível mantém a cadência original. Varreduras/apoio de física continuam ativos.
	if distance_squared > LOD_OFFSCREEN_NEAR*LOD_OFFSCREEN_NEAR and is_instance_valid(_lod_player) and _lod_player.global_position.distance_squared_to(g.global_position) > LOD_OFFSCREEN_NEAR*LOD_OFFSCREEN_NEAR:
		if _lod_frustum_frame != frame:
			_lod_frustum_frame = frame
			_lod_frustum = _lod_camera.get_frustum()
		var radius: float = g.half_length + LOD_VIEW_MARGIN
		for plane in _lod_frustum:
			if plane.distance_to(g.global_position) > radius: return 4
	return 2 if distance_squared > LOD_NEAR*LOD_NEAR else 1

func _lod_gate(delta: float) -> float:
	if not g.traffic or g.controlled or g.health <= 0 or not g.is_on_floor() or g.has_meta("crash_stun") or g.has_meta("awaiting_ground"):
		g._lod_skipped = -1
		g._lod_pending = 0.0
		return 1.0
	var stride := _lod_stride()
	if stride == 1:
		# Recupera o tempo de trânsito decorrido ao voltar para a simulação próxima.
		# Controle, impactos e estado no ar acima o descartam de propósito.
		var steps: float = (g._lod_pending + delta)/maxf(delta,0.0001)
		g._lod_skipped = -1
		g._lod_pending = 0.0
		return steps
	if g._lod_skipped < 0: g._lod_skipped = g.get_instance_id() % stride
	g._lod_pending += delta
	g._lod_skipped += 1
	if g._lod_skipped < stride: return 0.0
	var steps: float = g._lod_pending/maxf(delta,0.0001)
	g._lod_skipped = 0
	g._lod_pending = 0.0
	return steps

const WRECK_LIFETIME := 10.0
const WRECK_FADE := 2.0
const WRECK_SINK_DEPTH := 2.2

func _tick_wreck(delta: float) -> bool:
	if g._wreck_fade < 0.0:
		if not g._wreck_expires(): return false
		g._wreck_age += delta
		if g._wreck_age < WRECK_LIFETIME: return false
		var world := g.get_parent()
		var driving: Variant = world.get("driving") if is_instance_valid(world) else null
		if driving != null and driving.get("car") == g and driving.get("occupied") == true: return false
		_begin_wreck_fade()
		return false
	g._wreck_fade += delta
	var amount := clampf(g._wreck_fade / WRECK_FADE, 0.0, 1.0)
	if g.get_script().WRECK_SINK_ENABLED:
		# Desce sem colisão (desligada em _begin_wreck_fade); o fogo e a fumaça filhos descem junto.
		var sunk := WRECK_SINK_DEPTH * amount * amount
		g.global_position.y += g._wreck_sunk - sunk
		g._wreck_sunk = sunk
	else:
		for mesh in g._wreck_meshes:
			if is_instance_valid(mesh): mesh.transparency = amount
	if amount >= 1.0:
		g.queue_free()
		return true
	return false

func _begin_wreck_fade() -> void:
	g.invalidate_shadow_proxy()
	g._wreck_fade = 0.0
	preload("res://runtime/PipelineProbe.gd").note("wreck_sink" if g.get_script().WRECK_SINK_ENABLED else "wreck_fade", g)
	# Já não bloqueia ninguém enquanto some.
	var pending: Array[Node] = [g]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D:
			g._wreck_collision_state.append({"node": node, "layer": node.collision_layer, "mask": node.collision_mask})
			(node as CollisionObject3D).collision_layer = 0
			(node as CollisionObject3D).collision_mask = 0
		if node is MeshInstance3D: g._wreck_meshes.append(node)
		if node is Light3D:
			g._wreck_lights.append({"node": node, "visible": node.visible})
			(node as Light3D).visible = false
		for child in node.get_children(): pending.append(child)

const RETIRE_SINK_DEPTH := 2.4

func fade_traffic_retirement(alpha: float) -> void:
	if alpha > 0.0: g.invalidate_shadow_proxy()
	if g.get_script().RETIRE_SINK_ENABLED:
		if not is_instance_valid(g.visual): return
		var sunk := RETIRE_SINK_DEPTH * clampf(alpha, 0.0, 1.0)
		g.visual.position.y += g._retire_sunk - sunk
		g._retire_sunk = sunk
		return
	if alpha<=0:
		for record in g._traffic_retirement_meshes:
			if is_instance_valid(record.node): record.node.transparency=record.original
		g._traffic_retirement_meshes.clear()
		return
	if g._traffic_retirement_meshes.is_empty() and is_instance_valid(g.visual):
		for mesh in g.visual.find_children("*","MeshInstance3D",true,false):
			g._traffic_retirement_meshes.append({"node":mesh,"original":mesh.transparency})
	for record in g._traffic_retirement_meshes:
		if is_instance_valid(record.node): record.node.transparency=maxf(record.original,alpha)
