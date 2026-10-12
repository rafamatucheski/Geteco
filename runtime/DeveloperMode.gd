extends Node
## Session-local tools. No campaign writes; only our own NPCs are removable.
const ACTOR := preload("res://scripts/Actor.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const MAX_CIVILIANS := 20
signal changed
var world: Node3D
var active := false
var flying := false
var busy := false
var speed_multiplier := 1.0
var flight_speed := 25.0
var invincible := false
var message := "Ative o modo para usar as ferramentas."
var anchor := Vector3.INF
var anchor_region := ""
var civilians: Array[Node] = []
var _original_no_save := false
var _original_god := false
var _flight_state: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -20
	set_physics_process(false)

func report(text: String, event := "") -> void:
	if text == message and event.is_empty(): return
	message = text
	if not event.is_empty(): print("DEVELOPER ", event, " ", text)
	changed.emit()

func set_active(value: bool) -> bool:
	if value == active: return true
	if busy: return false
	if value:
		if not is_instance_valid(world.player) or world.session == null or not world.session.ready_for_play:
			report("Aguarde o carregamento da partida."); return false
		_original_no_save = world.production.no_save
		_original_god = world.gameplay.god_mode
		world.production.no_save = true
		world.set_meta("developer_mode_active", true)
		active = true
		report("Modo ativo · salvamento suspenso.", "enabled")
	else:
		if flying and not land(): return false
		clear_civilians()
		world.player.remove_meta("developer_speed_multiplier")
		world.remove_meta("developer_mode_active")
		world.production.no_save = _original_no_save
		world.gameplay.god_mode = _original_god
		speed_multiplier = 1.0
		invincible = false
		active = false
		report("Modo desligado · controles normais restaurados.", "disabled")
	return true

func set_speed(value: float) -> void:
	if not active: return
	speed_multiplier = clampf(value, 1.0, 10.0)
	world.player.set_meta("developer_speed_multiplier", speed_multiplier)
	report(String(TranslationServer.translate("Velocidade a pé: %.0f×.")) % speed_multiplier, "speed")

func set_invincible(value: bool) -> void:
	if not active: return
	invincible = value
	world.gameplay.god_mode = _original_god or invincible or flying
	report("Invulnerabilidade " + ("ligada." if value else "desligada."), "invincible")

func movement_block_reason() -> String:
	if not active: return "Ative o modo desenvolvedor."
	if busy: return "Aguarde a operação atual."
	if not world.session.ready_for_play or world.session.is_transition_blocked(): return "Aguarde a transição terminar."
	if world.driving.occupied or world.player.seated: return "Desembarque antes de usar esta ferramenta."
	if world.player.dead or world.gameplay.health <= 0: return "Aguarde o retorno de Dante."
	if not world.session.state.place_id.is_empty(): return "Saia do interior para usar voo ou teletransporte."
	if world.session.modal: return "Feche a conversa ou interação atual."
	if not flying and (world.player.input_locked or not world.player.is_physics_processing()): return "Encerre a atividade que controla Dante."
	if world.session.blocks_driving_change(): return "Encerre a atividade atual."
	return ""

func begin_flight() -> bool:
	if flying: return true
	var reason := movement_block_reason()
	if not reason.is_empty(): report(reason); return false
	var p = world.player
	anchor = p.global_position
	anchor_region = world.session.state.region_id
	_flight_state = {"layer":p.collision_layer,"mask":p.collision_mask,"physics":p.is_physics_processing(),
		"locked":p.input_locked,"protected":p.get_meta("invulnerable") if p.has_meta("invulnerable") else null}
	p.set_meta("developer_free_flight",true)
	p.set_meta("invulnerable",true)
	p.collision_layer = 0
	p.collision_mask = 0
	p.input_locked = true
	p.velocity = Vector3.ZERO
	p.set_physics_process(false)
	world.gameplay.god_mode = true
	flying = true
	set_physics_process(true)
	report("Voo: WASD · Espaço sobe · Ctrl desce · Shift acelera · F10 painel.", "flight_start")
	return true

func _physics_process(delta: float) -> void:
	if not flying or busy or get_tree().paused: return
	var axis: Vector2 = get_node("/root/GameInput").movement()
	var right: Vector3 = world.camera.global_basis.x
	var back: Vector3 = world.camera.global_basis.z
	right.y = 0; back.y = 0
	var direction := right.normalized()*axis.x + back.normalized()*axis.y
	direction.y = float(Input.is_physical_key_pressed(KEY_SPACE))-float(Input.is_physical_key_pressed(KEY_CTRL))
	var point: Vector3 = world.player.global_position + direction.limit_length()*flight_speed*(3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)*delta
	# Region changes use the normal travel/streaming admission, never an accidental fly-through.
	if CONNECTION.logical_region(point) != world.session.state.region_id:
		report("Use o teletransporte de região no painel.")
		return
	point.y = clampf(point.y, -100.0, 1000.0)
	world.player.global_position = point
	world.player.last_position = point

func _ground(point: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2.0,point-Vector3.UP*2000.0,1)
	ray.exclude = [world.player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < .65: return Vector3.INF
	var candidate: Vector3 = hit.position + Vector3.UP*.08
	return candidate if world.session.position_clear(candidate) else Vector3.INF

func land() -> bool:
	if not flying: return true
	if busy: return false
	var point := _ground(world.player.global_position)
	if not point.is_finite():
		report("Sem chão livre abaixo. Mova-se ou use Voltar ao início do voo."); return false
	world.player.teleport(point)
	_restore_flight()
	report("Voo desligado · colisão e gravidade restauradas.", "flight_end")
	return true

func _restore_flight() -> void:
	if not flying: return
	var p = world.player
	p.collision_layer = _flight_state.layer
	p.collision_mask = _flight_state.mask
	p.input_locked = _flight_state.locked
	p.set_physics_process(_flight_state.physics)
	p.remove_meta("developer_free_flight")
	if _flight_state.protected == null: p.remove_meta("invulnerable")
	else: p.set_meta("invulnerable",_flight_state.protected)
	p.velocity = Vector3.ZERO
	world.gameplay.god_mode = _original_god or invincible
	flying = false
	set_physics_process(false)

func teleport_to(point: Vector3) -> bool:
	var reason := movement_block_reason()
	if not reason.is_empty(): report(reason); return false
	if not point.is_finite() or absf(point.x)>10000 or absf(point.z)>10000 or absf(point.y)>2000:
		report("Coordenadas inválidas ou fora do limite do mapa."); return false
	if CONNECTION.logical_region(point) != world.session.state.region_id:
		report("Para mudar de mapa, use os destinos de região."); return false
	busy = true
	var paused_before := get_tree().paused
	get_tree().paused = true
	world.production.region.prepare_collision_at(point)
	for i in 3: await get_tree().physics_frame
	var destination := _ground(point)
	if destination.is_finite():
		world.player.teleport(destination)
		world.production.region.set_focus(destination,true)
		world.camera.initialized = false
	get_tree().paused = paused_before
	busy = false
	report(String(TranslationServer.translate("Destino: %.1f, %.1f, %.1f.")) % [destination.x,destination.y,destination.z] if destination.is_finite() else "Destino sem chão livre. Teletransporte cancelado.", "teleport")
	return destination.is_finite()

func return_to_anchor() -> bool:
	if not flying or not anchor.is_finite(): return false
	if world.session.state.region_id != anchor_region: report("O ponto pertence a outra região."); return false
	if not await teleport_to(anchor): return false
	return land()

func travel_to(region_id: String) -> bool:
	var reason := movement_block_reason()
	if not reason.is_empty(): report(reason); return false
	if flying: report("Pouse antes de trocar de região."); return false
	if region_id == world.session.state.region_id: return await teleport_to(world.production.region.spawn_position)
	if not world.production.travel(region_id): report("Viagem indisponível. Verifique a progressão e a atividade atual."); return false
	busy = true
	while world.production.travel_busy: await get_tree().physics_frame
	busy = false
	var arrived: bool = world.session.state.region_id == region_id
	if arrived: clear_civilians()
	report("Região: " + world.session.state.region_id if arrived else "Destino indisponível; origem preservada.","region")
	return arrived

func spawn_civilian() -> Node:
	var reason := movement_block_reason()
	if not reason.is_empty(): report(reason); return null
	if flying: report("Pouse antes de colocar pessoas."); return null
	civilians = civilians.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
	if civilians.size() >= MAX_CIVILIANS: report("Limite de 20 civis de teste. Remova alguns primeiro."); return null
	var point := Vector3.INF
	for i in 16:
		var angle := float(i)*TAU/16.0
		var candidate: Vector3 = world.player.global_position+Vector3(cos(angle),0,sin(angle))*(2.5+float(i%3))
		point = _ground(candidate)
		if point.is_finite(): break
	if not point.is_finite(): report("Não há chão livre próximo para o civil."); return null
	var actor = ACTOR.new()
	actor.identity = 900000+civilians.size()
	actor.position = point
	actor.set_meta("developer_spawned",true)
	actor.set_meta("region_id",world.session.state.region_id)
	actor.add_to_group("developer_civilians")
	world.add_child(actor)
	civilians.append(actor)
	report(String(TranslationServer.translate("Civil de teste criado (%d/%d).")) % [civilians.size(),MAX_CIVILIANS],"spawn")
	return actor

func remove_last_civilian() -> void:
	while not civilians.is_empty():
		var actor = civilians.pop_back()
		if is_instance_valid(actor): actor.queue_free(); break
	report("Último civil de teste removido.","remove")

func clear_civilians() -> void:
	for actor in civilians:
		if is_instance_valid(actor): actor.queue_free()
	civilians.clear()
	report("Civis de teste removidos.","clear")

func _exit_tree() -> void:
	if is_instance_valid(world) and is_instance_valid(world.player) and is_instance_valid(world.gameplay):
		_restore_flight()
		if active:
			world.player.remove_meta("developer_speed_multiplier")
			world.gameplay.god_mode = _original_god
			world.remove_meta("developer_mode_active")
			if is_instance_valid(world.production): world.production.no_save = _original_no_save
	for actor in civilians:
		if is_instance_valid(actor): actor.queue_free()
