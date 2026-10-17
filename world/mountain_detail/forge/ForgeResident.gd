extends Node3D
## Um morador da pista da forja (ferreiro, eremita, minerador): nasce quando o jogador
## chega perto do lugar, é um Actor comum (combate, emergência e morte normais) e, morto
## ou removido, continua ausente até o jogador sair do raio e voltar. Mesmo ciclo do
## antigo caixa do zoológico, que os testes de atores removidos já cobriam.
const ACTOR := preload("res://scripts/Actor.gd")
const NEAR_RADIUS := 65.0
## Distância do jogador ao morador para oferecer a conversa.
const TALK_RADIUS := 2.6
var site_id := ""
var speaker := ""
var identity := 700
## Posição e rumo locais ao lugar (o nó pai é o lugar).
var stand := Vector3.ZERO
var facing := 0.0
var actor: CharacterBody3D
var session
var _initialized := false
var _clock := 1.0

# Actor encaminha morte, ferimento e atropelamento pelo dono imediato.
var gameplay:
	get:
		if not _session_ready(): return null
		return session.world.gameplay

func _session_ready() -> bool:
	if session == null or not is_instance_valid(session):
		session = null
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor.get("session") != null:
				session = ancestor.session
				break
			ancestor = ancestor.get_parent()
	return session != null and is_instance_valid(session) and session.get("world") != null

func available() -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and not actor.dead

## Vivo e ao alcance da conversa, sem olhar se a sessão está num menu.
func in_reach() -> bool:
	if not _session_ready() or not available(): return false
	return actor.global_position.distance_to(session.world.player.global_position) <= TALK_RADIUS

func nearest_action() -> Dictionary:
	if not _session_ready() or not session.ready_for_play or session.modal or not session.state.place_id.is_empty(): return {}
	if session.world.driving.occupied or session.world.gameplay.health <= 0 or not in_reach(): return {}
	return {"id":"blade_forge", "target":site_id, "label":String(TranslationServer.translate("Falar com %s")) % speaker, "provider":self}

func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock < .25: return
	_clock = 0.0
	if not _session_ready() or not session.ready_for_play: return
	var player: Node3D = session.world.player
	var near: bool = global_position.distance_to(player.global_position) < NEAR_RADIUS and session.state.place_id.is_empty()
	if not near:
		if _initialized: _clear()
		return
	if not _initialized: _spawn()
	if available():
		# Parado no posto, virado para o trabalho; vira para o jogador quando ele chega perto.
		actor.automatic_direction = Vector3.ZERO
		var to_player: Vector3 = player.global_position - actor.global_position
		to_player.y = 0
		# O visual do Actor olha para −Z (o caixa do zoológico usava PI para olhar +Z).
		if to_player.length() < 4.0 and to_player.length() > .2: actor.visual.rotation.y = atan2(-to_player.x, -to_player.z) - actor.global_rotation.y
		else: actor.visual.rotation.y = facing

func _spawn() -> void:
	# Morto ou removido continua ausente até o ciclo de residência terminar.
	if _initialized: return
	_initialized = true
	actor = ACTOR.new()
	actor.name = "Forge" + site_id.capitalize().replace(" ", "")
	actor.identity = identity
	actor.controlled_automatically = true
	actor.position = stand
	add_child(actor)
	actor.visual.rotation.y = facing
	actor.automatic_direction = Vector3.ZERO

func set_talking(value: bool) -> void:
	if available() and actor.has_method("set_talking"): actor.set_talking(value)

func _clear() -> void:
	if is_instance_valid(actor): actor.queue_free()
	actor = null
	_initialized = false

func _exit_tree() -> void:
	_clear()
