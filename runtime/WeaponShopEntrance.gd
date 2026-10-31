extends Node

## Physical walk-up access; NPC interactions remain owned by FullSession.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const IDS := ["harbor_supermarket", "harbor_ammunation", "mountain_gunshop", "harbor_police", "harbor_bank", "maciota", "port_boss_garage", "harbor_clothing", "harbor_fuel", "harbor_hospital", "harbor_fire_station",
	"mountain_cabin", "mountain_cabin_encosta", "mountain_cabin_forest", "mountain_cabin_village_1", "mountain_cabin_village_2", "mountain_cabin_village_3", "mountain_cabin_village_4",
	"lumberjack_shelter", "lumberjack_shelter_2", "lumberjack_shelter_3", "mountain_outfitters", "mountain_boutique", "mountain_village_outfitters",
	"westgate_garden", "quayside_house", "canal_north", "cemetery_keeper", "mountain_bunker", "ski_lodge", "cobra_leader_house", "santa_lua_home_1", "santa_lua_home_2", "santa_lua_home_3", "santa_lua_home_4",
	# Umbra (parque): porta dupla de empurrar; antes só a ação "Entrar" e a porta não abria.
	"harbor_haunted_house",
	# Fagulha e Curitiba Cellar: folhas de correr que ninguém abria (só a ação silenciosa "Entrar").
	"harbor_arcade", "harbor_curitiba_cellar", "harbor_bar", "desert_bar",
	# Academia Ferro Velho: mesma casca e folhas de correr do Lastro.
	"harbor_gym",
	# Escritório da Serra Bruta: folha pintada da frente, que olha a estrada (-X).
	"mining_office"]
const PAINTED_SUPERMARKET := preload("res://world/places/supermarket/PaintedSupermarketFacade.gd")
const CAMERA_SECONDS := 0.55
const POLICE_DOOR_Z := 250.0 / 32.0 + 0.35
## Porta de vidro 0,72 m recuada das lojas 3D da North Frontage (UrbanLandmarkFrontage3D
## ._build_glazed_door): Union, Fuel e o banco sem fachada pintada.
const BANK_DOOR_Z := 180.0 / 32.0 - 0.72
## Vestíbulo atrás dessa porta de vidro: recuo de 1,65 m da fachada (_build_recessed_shell)
## menos os 0,72 m da folha. O corpo (cápsula de 0,30 m) para a ~0,63 m do plano dela.
const GLAZED_VESTIBULE_DEPTH := 1.65 - 0.72
## Pegadas V1 (OriginalWorldData, 16 px/m) do banco, da delegacia e do quartel: a entrada
## pintada sai do vão nelas (a do quartel é a mesma de PlaceCatalog.FIRE_STATION_DOOR_OFFSET).
const BANK_FOOTPRINT := Vector2(230.0, 180.0) / 16.0
const POLICE_FOOTPRINT := Vector2(190.0, 250.0) / 16.0
const FIRE_STATION_FOOTPRINT := Vector2(310.0, 220.0) / 16.0
## Raio da cápsula do Actor (0,30 m) mais 5 cm: o corpo inteiro cabe no vão pintado. No
## banco (meia abertura de 1,45 m) dá o 1,1 m que ele já usava.
const DOOR_CLEARANCE := 0.35
## Fundo do nicho da porta do bunker: porta em z 2,8625 e recorte até z 1,05 (WalkupFacadeDoor).
const BUNKER_NICHE_DEPTH := 2.8625 - 1.05
## Baia aberta do quartel: as paredes do vão seguem pelo vestíbulo, então vale todo ponto
## que o corpo alcança lá dentro, encostado na ombreira (raio da cápsula menos 5 cm). Com
## DOOR_CLEARANCE, quem entrava rente à parede ficava 5 cm fora e parava no vestíbulo.
const BAY_CLEARANCE := 0.25

var session: Node
var _facade: Node3D
var _facade_id := ""
var _door_amount := 0.0
var _entering := false
var _leaving := false
var _definitions: Dictionary = {}
var _blocked_entry_id := ""
var _reentry_remaining := 0.0
var _entry_cancelled := false
var _entry_generation := -1
var _push_remaining := 0.0
var _contact_depth := 0.0
var _push_age := 1.0
var _push_inward := Vector3.FORWARD

func _ready() -> void:
	process_physics_priority = 100 # Aplica o gesto depois da pose de caminhada do Actor.
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	_push_age += delta
	if _push_age >= .42 or not is_instance_valid(session) or _blocked() or not session.state.place_id.is_empty():
		set_physics_process(false)
		return
	var player = session.world.player
	if not is_instance_valid(player.skeleton) or player.combat_weapon_id not in ["", "fists"] or not player.combat_clip.is_empty(): return
	var weight := sin(PI * clampf(_push_age / .42, 0.0, 1.0))
	var before := {}
	for name in ["LeftArm", "LeftForeArm", "LeftHand"]:
		var bone: int = player.skeleton.find_bone(name)
		if bone >= 0: before[bone] = player.skeleton.get_bone_pose_rotation(bone)
	var across := Vector3(-_push_inward.z, 0, _push_inward.x)
	var palm: Vector3 = player.global_position + Vector3.UP * 1.22 + _push_inward * .48 - across * .18
	player._solve_combat_arm("Left", player.visual.to_local(palm), Basis.IDENTITY, false, -1.0)
	for bone in before:
		player.skeleton.set_bone_pose_rotation(bone, before[bone].slerp(player.skeleton.get_bone_pose_rotation(bone), weight))

func _movement_intent(player: CharacterBody3D) -> Vector3:
	# move_and_slide remove a velocidade para dentro numa porta fechada. Lê o movimento
	# pretendido em vez disso, usando a mesma base de câmera e controles remapeados do Actor.
	if player.controlled_automatically: return player.automatic_direction
	var axis: Vector2 = GameInput.movement()
	var right: Vector3 = session.world.camera.global_basis.x
	var back: Vector3 = session.world.camera.global_basis.z
	right.y = 0.0
	back.y = 0.0
	return (right.normalized() * axis.x + back.normalized() * axis.y).limit_length()

func _push_requested(local: Vector3, inward: Vector3, width: float, intent: Vector3) -> bool:
	var across := Vector3(-inward.z, 0, inward.x)
	var depth := local.dot(inward) - _contact_depth
	return absf(local.y) <= 1.0 and absf(local.dot(across)) <= width and depth >= -.6 and depth <= .15 and intent.dot(inward) > .3

func handles_place(id: String) -> bool:
	return id in IDS

func _definition_for(id: String) -> Dictionary:
	if _definitions.is_empty():
		for definition in PLACES.definitions():
			if handles_place(definition.id): _definitions[definition.id] = definition
		_definitions["maciota"] = {"id":"maciota", "region":"harbor"}
		for index in 2:
			var alias: Dictionary = _definitions.lumberjack_shelter.duplicate()
			alias["place_id"] = "lumberjack_shelter"
			alias.id = "lumberjack_shelter_%d" % (index + 2)
			alias.exterior_position = PLACES.shelter_access_exterior(index)
			_definitions[alias.id] = alias
	return _definitions.get(id, {})

func update(delta: float) -> void:
	if not is_instance_valid(session) or not session.ready_for_play or session.get_tree().paused:
		return
	_reentry_remaining = maxf(0.0, _reentry_remaining - delta)
	if _entering and _entry_interrupted():
		_entry_cancelled = true
		session.world.camera.clear_store_focus()
	if handles_place(session.state.place_id):
		_update_exit()
		return
	if not session.state.place_id.is_empty() or session.world.driving.occupied:
		return
	var player: CharacterBody3D = session.world.player
	var id := ""
	var closest := INF
	# Cached accesses; no catalog construction or scene traversal per frame.
	for candidate in IDS:
		var candidate_definition := _definition_for(candidate)
		# Parque desligado (linha de base de medição): a Umbra não existe.
		if candidate_definition.is_empty(): continue
		if candidate_definition.region != session.state.region_id: continue
		var distance := player.global_position.distance_squared_to(_door_position(candidate, candidate_definition))
		if distance < closest:
			closest = distance
			id = candidate
	if id.is_empty(): return
	if _facade_id != id and is_instance_valid(_facade):
		_facade.set_open_amount(0.0)
		_facade = null
		_facade_id = ""
		_door_amount = 0.0
		_push_remaining = 0.0
	var definition := _definition_for(id)
	var door := _door_position(id, definition)
	var near := closest < 81.0
	if near or (_facade_id == id and is_instance_valid(_facade)):
		_update_facade(id, near, delta)
	var local := player.global_position - door
	var inward := _inward(id)
	var across := Vector3(-inward.z, 0, inward.x)
	var depth := local.dot(inward)
	var width := _half_width(id)
	var side := local.dot(across) - _opening_shift(id)
	if not _blocked_entry_id.is_empty():
		if _blocked_entry_id != id or depth < -1.6 or absf(side) > width + .5:
			_blocked_entry_id = ""
	if not near or _entering or _leaving or _reentry_remaining > 0.0 or _blocked_entry_id == id or _blocked():
		return
	# A porta física de uma casa trancada já bloqueia o corpo. Não trava uma
	# travessia falha aqui: comprar na soleira precisa permitir a entrada na hora.
	if session.activities != null and not session.activities.can_enter_home(id): return
	if not _door_allows(id): return
	if id == "cobra_leader_house" and not _leader_accessible(): return
	# Empurrar abre a porta; só uma travessia intencional para dentro transfere.
	# Union/posto: quem já está atrás da folha (cápsula + meia espessura dela) atravessou; a
	# folha fecha quando ele passa de 0,5 m e sem isso ficava preso no vestíbulo.
	# Estação Zero: o vão no concreto tem ~1,8 m de fundo; quem passava dos 0,3 m ficava
	# no nicho com a folha fechada atrás e sem entrar nem sair (playtest de 21/10).
	var behind_leaf := id in ["harbor_clothing", "harbor_fuel", "mountain_bunker"] and depth > DOOR_CLEARANCE
	if is_instance_valid(_facade) and _facade_id == id and _door_amount < .85 and not behind_leaf: return
	if absf(side) > width or _movement_intent(player).dot(inward) <= .3: return
	var outer := -.1 if id == "harbor_police" else -1.15 if id in ["harbor_ammunation", "mountain_gunshop"] else -.8
	var inner := .6 if id == "harbor_police" else -.15 if id in ["harbor_ammunation", "mountain_gunshop"] else .3
	if id in ["harbor_ammunation", "mountain_gunshop"]: inner = maxf(inner, _contact_depth + .35)
	if id == "harbor_bank" and _painted(id):
		# Entrada no plano das folhas pintadas, 0,68 m à frente da porta de vidro antiga: a
		# mesma janela física de antes, em que o jogador cruza ~0,1 m antes das folhas já
		# abertas (sonda de 18/10) e no máximo a 1 m delas, ainda no vestíbulo de 1,5 m.
		outer = -.12
		inner = .98
	if id in ["harbor_clothing", "harbor_fuel"]:
		# Vale até o fundo do vestíbulo. A folha só chega a 0,85 ~0,25 s depois de começar a
		# empurrar (a −0,6 m): andando (3,5 m/s) o jogador já está a ~0,27 m, a menos de um
		# passo de física dos 0,3 m de antes, e correndo (6,5 m/s) chega ao fundo antes dos
		# 0,85, fora da janela (19/10, Union parou a 0,63 m sem entrar).
		var stretch: Vector3 = definition.get("editor_scale", Vector3.ONE)
		inner = GLAZED_VESTIBULE_DEPTH * stretch.z
	if id == "mountain_bunker": inner = BUNKER_NICHE_DEPTH - DOOR_CLEARANCE
	if id == "harbor_fire_station" and _painted(id):
		# Baia pintada aberta: vale do plano dela (a entrada fica 0,06 m à frente) até o fundo
		# do vestíbulo. Até 0,3 m, quem corria passava da janela e quem parava lá dentro só
		# entrava recuando para a rua (sonda de 19/10).
		outer = 0.0
		inner = PaintedFireStation.VESTIBULE_DEPTH
	if depth < outer or depth > inner: return
	_blocked_entry_id = id
	if not _entry_available(id): return
	_enter(id, definition)

func _blocked() -> bool:
	return session.modal or session.is_transition_blocked() or session.world.player.input_locked or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _entry_available(id: String) -> bool:
	if not preload("res://runtime/ShopSafety.gd").admission_allowed(id, session.world.gameplay.stars):
		session.show_message("Perca a polícia antes de entrar.")
		return false
	if id == "cobra_leader_house" and not _leader_accessible():
		session.show_message("Takeshi ainda não liberou o acesso à casa.")
		return false
	if session.activities != null and not session.activities.can_enter_home(id):
		session.show_message("Esta casa ainda não é sua.")
		return false
	if not _door_allows(id):
		session.show_message("Porta trancada. É necessário um lockpick.")
		return false
	if session.garage_rewards != null and not session.garage_rewards.can_enter(id):
		session.show_message("A garagem abre entre 1h e 5h.")
		return false
	if id == "harbor_bank" and not session.robberies.can_enter_bank():
		session.show_message("O banco está fechado para investigação.")
		return false
	return true

func _door_allows(id: String) -> bool:
	return session.get("door_lockpick") == null or session.door_lockpick.allows(id)

func _leader_accessible() -> bool:
	return session.state.campaign.has_progress("cobra_finale") or (session.state.campaign.active_id == "cobra_finale" and session.state.campaign.step >= 6)

func _entry_interrupted() -> bool:
	return session.modal or session.is_transition_blocked() or session.transition_generation != _entry_generation or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _update_facade(id: String, near: bool, delta: float) -> void:
	# Estas garagens já têm portões erguidos/abertos; não procura dobradiças.
	# A baia pintada do quartel também é aberta: o portão antigo não existe nela (sem
	# visual nem colisão), e esperar o valor dele chegar a 0,85 deixava passar da janela.
	if id in ["maciota", "port_boss_garage"] or id == "harbor_fire_station" and _painted(id): return
	if not is_instance_valid(_facade) or _facade_id != id:
		_push_remaining = 0.0
		set_physics_process(false)
		_facade = null
		_facade_id = ""
		for candidate in get_tree().get_nodes_in_group("v2_walkin_facade"):
			if str(candidate.get_meta("place_id", "")) == id:
				_facade = candidate
				_facade_id = id
				_door_amount = float(candidate.get("open_amount"))
				_contact_depth = 0.0
				var contact := _door_position(id, _definition_for(id))
				if "hinge" in candidate and is_instance_valid(candidate.hinge): contact = candidate.hinge.global_position
				elif "entrance_door" in candidate and is_instance_valid(candidate.entrance_door): contact = candidate.entrance_door.global_position
				elif "panels" in candidate and not candidate.panels.is_empty(): contact = candidate.panels[0].global_position
				elif "leaves" in candidate and not candidate.leaves.is_empty(): contact = candidate.leaves[0].global_position
				elif "police_door_visuals" in candidate and not candidate.police_door_visuals.is_empty(): contact = candidate.police_door_visuals[0].global_position
				_contact_depth = (contact - _door_position(id, _definition_for(id))).dot(_inward(id))
				break
	if not is_instance_valid(_facade): return
	# A posse trava a dobradiça física e também a admissão na sala.
	var owned: bool = session.activities == null or session.activities.can_enter_home(id)
	owned = owned and preload("res://runtime/ShopSafety.gd").admission_allowed(id, session.world.gameplay.stars)
	if id == "harbor_bank" and not session.robberies.can_enter_bank(): owned = false
	if id == "cobra_leader_house" and not _leader_accessible(): owned = false
	# Casa trancada (DoorLockpick): a folha não cede ao empurrão até arrombar.
	if not _door_allows(id): owned = false
	var player: CharacterBody3D = session.world.player
	var inward := _inward(id)
	var pushing := near and owned and not _blocked() and _push_requested(player.global_position - _door_position(id, _definition_for(id)), inward, _half_width(id), _movement_intent(player))
	if pushing:
		if _push_remaining <= 0.0 and _door_amount < .1:
			_push_age = 0.0
			_push_inward = inward
			set_physics_process(true)
		_push_remaining = .65
	else:
		_push_remaining = maxf(0.0, _push_remaining - delta)
	# A presença não pode iniciar uma abertura, mas impede que uma folha já aberta
	# feche através da cápsula quando o jogador para na soleira.
	var local := player.global_position - _door_position(id, _definition_for(id))
	var depth := local.dot(inward) - _contact_depth
	var across := Vector3(-inward.z, 0, inward.x)
	if owned and _door_amount > .1 and absf(local.y) <= 1.0 and absf(local.dot(across)) <= _half_width(id) and depth >= -.5 and depth <= .5:
		_push_remaining = maxf(_push_remaining, .2)
	var next := move_toward(_door_amount, 1.0 if owned and (_push_remaining > 0.0 or _entering) else 0.0, delta / .28)
	if not is_equal_approx(next, _door_amount):
		_door_amount = next
		_facade.set_open_amount(_door_amount)

func _enter(id: String, definition: Dictionary) -> void:
	_entering = true
	_entry_cancelled = false
	_entry_generation = session.transition_generation
	var player: CharacterBody3D = session.world.player
	player.input_locked = true
	var camera = session.world.camera
	var focus := _door_position(id, definition) + _inward(id) * 1.0 + Vector3.UP * 1.2
	if id == "harbor_ammunation": focus = definition.exterior_position + Vector3(0, 1.2, 2.0)
	elif id == "mountain_gunshop": focus = definition.exterior_position + Vector3(0, 1.2, 0)
	camera.focus_on_store(focus, _close_size(id), CAMERA_SECONDS)
	await get_tree().create_timer(CAMERA_SECONDS).timeout
	if not is_instance_valid(session) or not is_instance_valid(player):
		_entering = false
		return
	# Uma morte, prisão ou transição de veículo pode tomar a posse durante o zoom.
	var interrupted := _entry_cancelled or _entry_interrupted()
	if not session.modal and not session.is_transition_blocked() and not session.world.driving.is_body_transition_active():
		player.input_locked = false
	if not interrupted:
		if session.state.place_id.is_empty() and session.state.region_id == definition.region:
			await session.enter_place(str(definition.get("place_id", id)), true, id)
	if is_instance_valid(camera): camera.clear_store_focus()
	_entering = false

func _update_exit() -> void:
	if _leaving or _entering or _blocked() or not is_instance_valid(session.room): return
	var player: CharacterBody3D = session.world.player
	var local: Vector3 = player.global_position - session.room.exit_position
	var bank: bool = session.state.place_id=="harbor_bank"
	var half_width := 1.08 if bank else .75
	var approach := -.8 if bank else -.55
	if absf(local.x) > half_width or local.z < approach or local.z > .45 or player.velocity.z < .7: return
	_leave()

func _leave() -> void:
	_leaving = true
	var id: String = session.state.place_id
	if handles_place(session.access_id): id = session.access_id
	var definition := _definition_for(id)
	var player: CharacterBody3D = session.world.player
	player.input_locked = true
	var left: bool = await session.leave_place()
	if is_instance_valid(player):
		if left:
			_blocked_entry_id = id
			_reentry_remaining = CAMERA_SECONDS + .15
			player.input_locked = true
			var camera = session.world.camera
			camera.zoom_out_from_store(_door_position(id, definition), _close_size(id), CAMERA_SECONDS)
			# Estabelece o quadro inicial de fechamento antes que o exterior possa renderizar.
			camera._process(0.0)
			await get_tree().create_timer(CAMERA_SECONDS).timeout
			if is_instance_valid(camera): camera.clear_store_focus()
		if is_instance_valid(session) and not session.is_transition_blocked() and not session.modal:
			player.input_locked = false
	_leaving = false

func player_near_police(player: CharacterBody3D, definition: Dictionary) -> bool:
	return player.global_position.distance_to(_door_position("harbor_police", definition)) < 12.0

func _inward(id: String) -> Vector3:
	if id in preload("res://world/desert/village/DesertVillageHomes.gd").IDS or id == "mining_office":
		return Vector3.FORWARD.rotated(Vector3.UP, float(_definition_for(id).exterior_rotation))
	var direction := Vector3.LEFT if id == "port_boss_garage" else Vector3.FORWARD
	return direction.rotated(Vector3.UP,float(_definition_for(id).get("editor_rotation",0)))

func _half_width(id: String) -> float:
	match PLACES.walkup_family(id):
		"cabin": return .16
		"shop", "residence", "keeper": return .23
		"bunker": return .34
		"lodge": return .42
	match id:
		"maciota", "port_boss_garage": return 1.8
		"harbor_ammunation": return 1.05
		# Delegacia pintada: porta dupla de ~2,1 m que o editor estica para ~3,2 m.
		"harbor_police": return _painted_half_width(id, PaintedPoliceStation.opening_half_width(PaintedHarborHouses.footprint_width("Police", POLICE_FOOTPRINT.x))) if _painted(id) else .95
		"harbor_hospital": return 1.1
		# Quartel pintado: baia aberta de ~5,4 m; 1,4 m cobria só o meio dela e quem entrava
		# pela beira parava no vestíbulo sem trocar de lugar.
		"harbor_fire_station": return _painted_half_width(id, _fire_station_bay().x, BAY_CLEARANCE) if _painted(id) else 1.4
		# Banco pintado: vão de ~2,9 m (a porta antiga tinha 1,42 m).
		"harbor_bank": return _painted_half_width(id, PaintedBankBranch.opening_half_width(_bank_footprint().x)) if _painted(id) else .48
		"harbor_clothing", "harbor_fuel": return .48
		# Vão pintado de ~0,93 m e uma folha, como as lojas de porta de empurrar (família "shop").
		"harbor_supermarket": return .23 if _painted(id) else .62
		"cobra_leader_house": return .23
		"harbor_haunted_house", "harbor_arcade", "harbor_curitiba_cellar", "harbor_bar", "desert_bar", "harbor_gym": return .9
		# Vão pintado de ~1,46 m: meia abertura menos a cápsula.
		"mining_office": return .4
	return .62

## Até onde, para o lado, empurrar e atravessar valem: o vão pintado na pegada que o
## editor de mundo esticou, menos a cápsula. A delegacia (18 m de frente, meia abertura
## de ~1,6 m) tinha 0,95 m fixo e a folha não abria para quem empurrava mais de lado.
func _painted_half_width(id: String, half_opening: float, clearance := DOOR_CLEARANCE) -> float:
	var stretch: Vector3 = _definition_for(id).get("editor_scale", Vector3.ONE)
	return half_opening * stretch.x - clearance

## Quanto o meio do vão fica ao lado da entrada, na direção `across`: só a baia pintada do
## quartel não é centrada nela (+0,22 m), e a meia largura vale a partir do meio do vão.
func _opening_shift(id: String) -> float:
	if id != "harbor_fire_station" or not _painted(id): return 0.0
	var stretch: Vector3 = _definition_for(id).get("editor_scale", Vector3.ONE)
	return _fire_station_bay().y * stretch.x

func _painted(id: String) -> bool:
	match id:
		"harbor_bank": return not PaintedHarborHouses.style_for("NorthFrontage0", "bank_branch").is_empty()
		"harbor_police": return not PaintedHarborHouses.style_for("Police", "police_precinct").is_empty()
		"harbor_fire_station": return not PaintedHarborHouses.style_for("NorthFireStation", "fire_station").is_empty()
		"harbor_supermarket": return PAINTED_SUPERMARKET.available()
	return false

## Baia da entrada do quartel pintado (meia largura, deslocamento do meio) na pegada que a
## fábrica usa: a largura natural da pintura, como no banco.
func _fire_station_bay() -> Vector2:
	return PaintedFireStation.entrance_bay(PaintedHarborHouses.footprint_width("NorthFireStation", FIRE_STATION_FOOTPRINT.x))

## Pegada do banco pintado: a fábrica põe o prédio na largura natural da pintura.
func _bank_footprint() -> Vector2:
	return Vector2(PaintedHarborHouses.footprint_width("NorthFrontage0", BANK_FOOTPRINT.x), BANK_FOOTPRINT.y)

func _close_size(id: String) -> float:
	if PLACES.walkup_family(id) == "cabin": return 8.0
	if id in ["mountain_bunker", "ski_lodge"]: return 14.0
	return 8.0 if id == "mountain_gunshop" else 14.0 if id in ["port_boss_garage", "harbor_fire_station"] else 11.0

func _door_position(id: String, definition: Dictionary) -> Vector3:
	if definition.has("editor_door_position"): return definition.editor_door_position
	if definition.has("editor_transform"):
		var original := definition.duplicate()
		original.exterior_position = definition.editor_base_exterior
		definition.editor_door_position = definition.editor_transform*_original_door_position(id,original)
		return definition.editor_door_position
	return _original_door_position(id,definition)

func _original_door_position(id: String, definition: Dictionary) -> Vector3:
	if id in preload("res://world/desert/village/DesertVillageHomes.gd").IDS or id == "mining_office": return definition.walkup_door_position
	if id == "cobra_leader_house": return definition.walkup_door_position
	# Boa Praça pintado: o vão da pintura fica à esquerda do meio da frente.
	if id == "harbor_supermarket" and _painted(id): return definition.exterior_position + Vector3(PAINTED_SUPERMARKET.door_x(), 0, PAINTED_SUPERMARKET.door_z())
	if id == "harbor_supermarket": return definition.exterior_position + Vector3(0,0,5.5)
	# Plano da fachada da Umbra (ParkLume._house): folhas da UmbraDoor.
	if id == "harbor_haunted_house": return definition.exterior_position + Vector3(0,0,7.5)
	# Plano das folhas de correr (ArcadeFacade / CuritibaCellarFacade).
	if id in ["harbor_bar", "desert_bar"]: return definition.exterior_position + Vector3(0,0,5.88)
	# Ferro Velho: galpão de 8 m de fundo (GymFacade), folhas no plano da frente.
	if id == "harbor_gym": return definition.exterior_position + Vector3(0,0,3.88)
	if id == "harbor_arcade": return definition.exterior_position + Vector3(0,0,4.91)
	if id == "harbor_curitiba_cellar": return definition.exterior_position + Vector3(0,0,5.39)
	var family := PLACES.walkup_family(id)
	if not family.is_empty(): return definition.exterior_position + Vector3(0, 0, PLACES.walkup_door_z(family))
	if id == "maciota": return session.world.maciota_place.entry_position - Vector3(0, 0, .4875)
	if id == "port_boss_garage": return definition.exterior_position + Vector3(-4.5, 0, 0)
	if id == "harbor_hospital": return definition.exterior_position + Vector3(0, 0, 120.0 / (18.0 * .76822128))
	if id == "harbor_fire_station": return definition.exterior_position + PLACES.FIRE_STATION_DOOR_OFFSET
	if id in ["harbor_clothing", "harbor_fuel"]: return definition.exterior_position + Vector3(0, 0, BANK_DOOR_Z)
	if id == "harbor_bank" and _painted(id): return definition.exterior_position + PaintedBankBranch.entrance_local(_bank_footprint())
	var z := POLICE_DOOR_Z if id == "harbor_police" else BANK_DOOR_Z if id == "harbor_bank" else 5.8 if id == "harbor_ammunation" else 2.7
	return definition.exterior_position + Vector3(0, 0, z)
