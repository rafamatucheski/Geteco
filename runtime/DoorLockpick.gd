extends Node
## Porta da frente trancada (playtest 29/10): toda casa/prédio particular exige lockpick
## para entrar. Abrem sem lockpick: polícia, bombeiros, hospital e lojas/comércio (e
## lugares públicos ou de história). A regra sai do catálogo (tipo do lugar), não de lista
## de prédios. A porta arrombada fica aberta no save ("door_lockpicks").
##
## Quem consulta: HarborBuildingRuntime (prédios do catálogo, entrada contínua) e
## WeaponShopEntrance (portas de empurrar). Sem arrombar, a fachada continua fechada e o
## corpo bate na porta. GETECO_DOOR_LOCKS=0 desliga a regra (A/B e testes antigos).
const BUILDINGS := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const LOCKPICK := preload("res://runtime/BankLockpick.gd")
const STATE_KEY := "door_lockpicks"
## Prédios do catálogo de interiores abertos ao público: lojas, bares/cafés e cívicos.
const PUBLIC_ARCHETYPES := ["retail", "hospitality", "civic"]
## Lugares do PlaceCatalog que são casa de alguém (o resto é loja, serviço, história ou público).
const PRIVATE_SERVICES := ["shelter", "village_home"]
## Casas do catálogo que continuam abertas: abrigo dos lenhadores e posto florestal são
## públicos (refúgio do frio); a Casa do Zelador é onde o zelador dá a missão do cemitério.
## As casas à venda (ResidenceCatalog) já têm a trava própria: só o dono entra.
const PUBLIC_IDS := ["lumberjack_shelter", "mountain_cabin_forest", "cemetery_keeper"]
const REACH := 1.6

var session
var lockpick: CanvasLayer
var _target := ""
var _owns_modal := false
var _doors: Array[Dictionary] = []
var _doors_region := ""

static func enabled() -> bool:
	return OS.get_environment("GETECO_DOOR_LOCKS") != "0"

## Resposta por id: PlaceCatalog.get_definition monta o catálogo inteiro a cada chamada, e a
## porta de empurrar pergunta todo quadro perto dela. O tipo do lugar não muda no jogo.
static var _required := {}
static var _services := {}

## A regra pelo catálogo: true se a porta deste lugar é trancada.
static func requires_lockpick(id: String) -> bool:
	if _required.has(id): return _required[id]
	var result := false
	if BUILDINGS.is_building(id):
		var building: Dictionary = BUILDINGS.find(id)
		result = not building.is_empty() and str(building.get("archetype", "")) not in PUBLIC_ARCHETYPES
	elif id not in PUBLIC_IDS:
		# Um só passe pelo catálogo (montá-lo custa caro) para todos os ids.
		if _services.is_empty():
			for place in PLACES.definitions(true): _services[str(place.id)] = str(place.get("service", ""))
		result = str(_services.get(id, "")) in PRIVATE_SERVICES
	_required[id] = result
	return result

static func valid_saved(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 512: return false
	for id in value:
		if not id is String or str(id).length() > 128 or not value[id] is bool: return false
		if not requires_lockpick(str(id)): return false
	return true

func _ready() -> void:
	lockpick = LOCKPICK.new()
	lockpick.lock_title = "FECHADURA"
	lockpick.instruction_text = "ESPAÇO / CLIQUE — travar na faixa verde\nESC — desistir"
	add_child(lockpick)
	lockpick.unlocked.connect(_unlocked)
	lockpick.cancelled.connect(_cancelled)
	set_process(false)
	PaintedFacadeKit.door_locked = _painted_leaf_locked
	# Monta o mapa de tipos agora, no carregamento da sessão, e não no primeiro quadro
	# em que o jogador chega perto de uma porta de empurrar.
	if enabled(): requires_lockpick("mountain_cabin")

func _exit_tree() -> void:
	if PaintedFacadeKit.door_locked == _painted_leaf_locked: PaintedFacadeKit.door_locked = Callable()

## Folha pintada da entrada: acha o lugar pelo BuildingAccess do prédio (uma vez por folha).
func _painted_leaf_locked(leaf: Node) -> bool:
	if not enabled(): return false
	if not leaf.has_meta("lock_place_id"):
		var id := ""
		var node := leaf.get_parent()
		while node != null and id.is_empty():
			var access := node.get_node_or_null("BuildingAccess")
			if access != null: id = str(access.get_meta("place_id", ""))
			node = node.get_parent()
		# Sem BuildingAccess (ainda) não guarda: tenta de novo na próxima entrada.
		if id.is_empty(): return false
		leaf.set_meta("lock_place_id", id)
	var place := str(leaf.get_meta("lock_place_id"))
	return not place.is_empty() and not allows(place)

func is_unlocked(id: String) -> bool:
	if session == null: return true
	return bool(session.state.world_state.get(STATE_KEY, {}).get(id, false))

## A porta deixa passar? (sem regra, lugar público ou já arrombada)
func allows(id: String) -> bool:
	if not enabled() or not requires_lockpick(id): return true
	return is_unlocked(id)

func _door_points() -> Array[Dictionary]:
	var region := str(session.state.region_id)
	if region == _doors_region and not _doors.is_empty(): return _doors
	_doors.clear()
	_doors_region = region
	for definition in BUILDINGS.definitions():
		if definition.region != region or not requires_lockpick(definition.id): continue
		# entry_position fica 0,9 m fora da porta; a ação vale na soleira.
		_doors.append({"id": definition.id, "point": definition.entry_position})
	var walk = session.get("weapon_shop_entrance")
	if walk != null:
		for id in preload("res://runtime/WeaponShopEntrance.gd").IDS:
			if not requires_lockpick(id): continue
			var definition: Dictionary = walk._definition_for(id)
			if definition.is_empty() or definition.region != region: continue
			_doors.append({"id": id, "point": walk._door_position(id, definition)})
	return _doors

func nearest_action() -> Dictionary:
	if not enabled() or session == null or session.modal or session.is_transition_blocked(): return {}
	if not session.state.place_id.is_empty() or session.world.driving.occupied or session.world.gameplay.health <= 0: return {}
	var player: Vector3 = session.world.player.global_position
	var best := ""
	var best_distance := REACH
	for door in _door_points():
		var distance := Vector2(player.x - door.point.x, player.z - door.point.z).length()
		if distance < best_distance and absf(player.y - door.point.y) < 1.5 and not is_unlocked(door.id):
			best = door.id
			best_distance = distance
	if best.is_empty(): return {}
	return {"id": "door_lockpick", "provider": self, "target": best, "label": "Arrombar fechadura · 1 lockpick"}

func perform(action: Dictionary = {}) -> bool:
	var current := nearest_action()
	if current.is_empty() or current.target != action.get("target", current.target): return false
	if int(session.state.economy.inventory.get("lockpick", 0)) < 1:
		session.show_message("Porta trancada. É necessário um lockpick.")
		return false
	_target = str(current.target)
	session.modal = true
	session.world.player.input_locked = true
	_owns_modal = true
	lockpick.begin()
	set_process(true)
	return true

func _process(_delta: float) -> void:
	if not _owns_modal: return
	if session == null or session.world.gameplay.health <= 0 or session.is_transition_blocked() or not session.state.place_id.is_empty():
		if lockpick.active: lockpick.finish(false)
		_cancelled()

func _unlocked() -> void:
	if not _owns_modal or session == null or _target.is_empty(): return
	if session.world.gameplay.health <= 0 or session.is_transition_blocked(): _cancelled(); return
	if not session.state.economy.consume_item("lockpick", 1): _cancelled(); return
	var state: Dictionary = session.state.world_state.get(STATE_KEY, {}).duplicate()
	state[_target] = true
	session.state.world_state[STATE_KEY] = state
	_cancelled()
	session.show_message("Fechadura aberta.")
	session.save_game()

func _cancelled() -> void:
	set_process(false)
	_target = ""
	if not _owns_modal: return
	_owns_modal = false
	if session != null and not session.is_transition_blocked(): session.close_menu()
