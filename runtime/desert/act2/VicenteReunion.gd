extends Node3D
## Ato 2 inteiro (roteiro em docs/story-act2-vicente-20261020.md; etapas em VicenteAct2State):
##   A2-01 "Oito anos": encontro da arrancada -> Motel Oásis -> Capela (envelope).
##   A2-02 "Respeita a pista": Bia -> corrida com o Digo (a que já existe) -> Arquibancada.
##   A2-03 "Peso morto": Raul -> caixote do Miragem -> Fiscal Rosa -> Raul (frete).
##   A2-04 "A ordem alterada": Irene no Cobre -> Irene na porta à noite -> orelhão do Horizonte.
##   A2-05 "Racha de irmãos": Vicente no encontro -> prova contra ele -> Vicente de novo.
##   A2-06 "Mesa de pedra": Vicente na caverna do Coyote.
##   A2-07 "Destinatário desconhecido": Dona Fátima -> torre de rádio -> rádio de Santa Lua.
##   A2-08 "Chave na chave": prova da Jessica -> Jessica -> Cascavel -> aposta (turbo cortado) -> chave.
##   A2-09 "Porta-malas novo": carro do Nonato (opcional) -> Bia e Digo montam o armazém.
##   A2-10 "Comboio da madrugada": assalto do comboio (DesertHeist) -> Vicente no motel.
##   A2-11 "Sal na ferida": Seu Bento nas Salinas -> caderno no acampamento da serra.
##   A2-12 "Teodoro": Teodoro no motel -> Teodoro na obra da passagem norte.
##   A2-13 "Os oito anos": Arquibancada -> ataque dos Cobras ao encontro -> Vicente na passagem norte.
## Quem espera fora do encontro (Vicente, Irene, Cascavel, Teodoro) é um ator próprio deste nó, montado
## só perto e com o lugar pronto, devolvido ao se afastar e ao morrer. O Vicente do encontro é o ator de
## DesertCampaign (some de lá enquanto ele espera em outro lugar). Pontos sem ator (caixote, Fiscal Rosa,
## orelhão, Dona Fátima, torre, rádio de Santa Lua, Nonato, Seu Bento, caderno) valem no lugar da ação
## comum do ponto enquanto a etapa estiver aberta (DesertRuntime pergunta a este nó antes). Diálogos só
## em legenda (sem voz gravada). Cada etapa só avança no fim do diálogo ou da ação, com Dante vivo e solto.
const STATE := preload("res://runtime/desert/act2/VicenteAct2State.gd")
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const CONTACT := preload("res://runtime/desert/DesertCharacter.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const RACE := preload("res://activities/desert_drag/DesertDragProgress.gd")
const LINES := preload("res://runtime/desert/act2/Act2Lines.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const ROSTER := preload("res://runtime/desert/drag_meet/DragMeetRoster.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const CAVE := preload("res://runtime/desert/wilds/CaveBuild.gd")
const COMMUNITY := preload("res://world/desert/community/DesertCommunitySite.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const COBRA := preload("res://gameplay/CobraAgent.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Objetivo e destino do ato 2 moram em VicenteAct2Objectives desde 01/11 (só para este arquivo caber na
## leitura); as funções antigas ficam aqui como delegação.
const OBJECTIVES := preload("res://runtime/desert/act2/VicenteAct2Objectives.gd")
## Cobras do ataque final e Vicente na briga do motel: eram classes internas; desde 01/11 cada uma tem
## arquivo próprio, reexportado com o mesmo nome.
const Raider := preload("res://runtime/desert/act2/Act2Raider.gd")
const BrotherFighter := preload("res://runtime/desert/act2/Act2BrotherFighter.gd")
const TITLE := "Oito anos"
const TRACK_TITLE := "Respeita a pista"
## Títulos, pontos de espera e os dois pontos que SPOTS usa moram em data/catalogs/VicenteAct2Spots.gd
## desde 01/11; ficam reexportados aqui com o mesmo nome.
const SPOTS_DATA := preload("res://data/catalogs/VicenteAct2Spots.gd")
const CHAIN_TITLES := SPOTS_DATA.CHAIN_TITLES
## Caixote dos Cobras no Miragem: o mesmo ponto de DesertCampaign.MANIFEST (que monta o caixote).
const MIRAGE_CRATE := Vector3(266, .05, -758)
## Orelhão do Horizonte: o ponto do "Descansar até as 20h" (DesertRuntime), que a ação da missão
## cobre enquanto a ligação está pendente.
const HORIZON_PHONE := Vector3(-315, 0, -913)
const BANK_DOOR := SPOTS_DATA.BANK_DOOR  # porta do Cobre (a razão do ponto está em VicenteAct2Spots)
## Bia no pátio do Digo (DesertCampaign.LOCATIONS.bia) e o raio em que o carro conta como "trazido".
const BIA_POINT := Vector3(-151, 0, -943)
const BIA_CAR_REACH := 18.0
## Concentração da arrancada (DesertLayout.DRAG_STAGING): onde as provas de história começam.
const STAGING := SPOTS_DATA.STAGING
const RACE_REACH := 15.0
## Acampamento dos foras-da-lei ao sul do leito seco (DesertWilds "outlaws_ridge").
const LEDGER_SITE := "outlaws_ridge"
## Ataque final: quatro Cobras chegando ao encontro pelo lado da pista.
const RAID_CENTER := Vector3(-965, 0, -1262)
const RAID_POINTS := [Vector3(-20, 0, -26), Vector3(-6, 0, -30), Vector3(10, 0, -28), Vector3(24, 0, -24)]
const RAID_DISTANCE := 110.0
const SPOTS := SPOTS_DATA.SPOTS  # onde cada um espera (motel, capela, arquibancada, caverna...)
const SPAWN_DISTANCE := 85.0
const RELEASE_DISTANCE := 120.0
const TALK_DISTANCE := 1.8
var session
var actor: CharacterBody3D
## Cena do ator montado (ex.: "motel", "convoy_motel", "teodoro_gate").
var _actor_stage := ""
var _clock := 0.0
## Resultado da última aposta (A2-08), só para a fala da chave; depois de carregar vale "perdeu".
var _bet_won := false
## Ataque final (A2-13): Cobras vivos desta visita.
var raiders: Array = []
var _objectives: OBJECTIVES = OBJECTIVES.new(self)

func configure(owner_session) -> void:
	session = owner_session
	name = "VicenteReunion"
	session.world.gameplay.player_died.connect(_on_player_died)

func _on_player_died() -> void:
	_release()
	_release_raiders()

func stage() -> String:
	return STATE.stage(session.state.world_state)

func _world() -> Dictionary:
	return session.state.world_state

static func chain_at(world: Dictionary, id: String) -> String: return OBJECTIVES.chain_at(world, id)

## Quem espera onde agora: {"scene", "spot", "who"} ou vazio.
static func scene_def(world: Dictionary) -> Dictionary:
	var current := STATE.stage(world)
	if current in ["motel", "chapel"]: return {"scene": current, "spot": current, "who": "vicente"}
	if STATE.track_stage(world) == "grandstand": return {"scene": "grandstand", "spot": "grandstand", "who": "vicente"}
	# Roteiro de diretor: quem espera na porta do Cobre à noite é a Helena.
	if chain_at(world, "order") == "night": return {"scene": "bank_night", "spot": "bank_night", "who": "helena"}
	if chain_at(world, "cave") == "": return {"scene": "cave", "spot": "cave", "who": "vicente"}
	if chain_at(world, "letters") == "water": return {"scene": "water_tower", "spot": "water_tower", "who": "helena"}
	if chain_at(world, "bet") in ["cascavel", "keys"]: return {"scene": "cascavel", "spot": "meet_edge", "who": "cascavel"}
	if chain_at(world, "convoy") == "motel": return {"scene": "convoy_motel", "spot": "motel", "who": "vicente"}
	if chain_at(world, "salt") == "home": return {"scene": "helena_home", "spot": "santa_lua", "who": "helena"}
	match chain_at(world, "teodoro"):
		"": return {"scene": "teodoro_motel", "spot": "motel", "who": "teodoro"}
		"fight": return {"scene": "brothers_fight", "spot": "motel", "who": "vicente"}
		"chase": return {"scene": "teodoro_gate", "spot": "gate", "who": "teodoro"}
	match chain_at(world, "finale"):
		"": return {"scene": "finale_grandstand", "spot": "grandstand", "who": "vicente"}
		"gate": return {"scene": "finale_gate", "spot": "gate", "who": "vicente"}
	return {}

## Nome da cena atual (compatível com o teste de A2-01/A2-02).
func scene() -> String:
	return str(scene_def(_world()).get("scene", ""))

## DesertCampaign tira o Vicente do encontro enquanto ele espera em outro lugar (ou na defesa do encontro,
## quando ele luta com a turma, sem ator: a cena fica com os Cobras).
func away_from_meet() -> bool:
	return str(scene_def(_world()).get("who", "")) == "vicente"

func is_night() -> bool:
	var time: float = session.weather.time_of_day if is_instance_valid(session.weather) else float(_world().get("time", .32))
	return time >= 20.0 / 24.0 or time < 5.0 / 24.0

func _process(delta: float) -> void:
	_clock += delta
	if _clock < .3 or session == null or not session.ready_for_play: return
	_clock = 0.0
	var outside: bool = session.state.region_id == "desert" and session.state.place_id.is_empty() and session.player_health() > 0
	_tick_missions(outside)
	var def := scene_def(_world())
	var spot := str(def.get("spot", ""))
	if not outside or spot.is_empty() or (SPOTS[spot].get("night", false) and not is_night()):
		_release()
		return
	if is_instance_valid(actor) and _actor_stage != str(def.scene): _release()
	# A2-12: o tempo da fuga acabou e o Teodoro já passou pela obra; fica só a pasta no chão.
	if str(def.scene) == "teodoro_gate" and _chase_lost():
		_release()
		return
	var player: Vector3 = session.player_position()
	var anchor := _site_point(spot, Vector3.ZERO)
	var distance := Vector2(player.x, player.z).distance_to(Vector2(anchor.x, anchor.z))
	if is_instance_valid(actor):
		if distance > RELEASE_DISTANCE: _release()
		else: _face(spot)
		return
	if distance < SPAWN_DISTANCE and _site_ready(spot): _admit(def)

## Avanços sem conversa: o assalto do comboio (A2-10), a briga dos irmãos (A2-12) e o ataque ao
## encontro (A2-13).
func _tick_missions(outside: bool) -> void:
	var world := _world()
	if outside: _tick_fight()
	if chain_at(world, "convoy") == "" and session.desert != null and is_instance_valid(session.desert.heist):
		if str(session.desert.heist.data.get("phase", "")) == "looted" and STATE.chain_advance(world, "convoy", "motel"):
			session.show_message("Ato 2 · " + str(CHAIN_TITLES.convoy) + " · Leve o lacre a Vicente, no Motel Oásis.")
			session.save_game()
	if chain_at(world, "finale") != "defend":
		_release_raiders()
		return
	if not outside:
		_release_raiders()
		return
	var near: bool = session.player_position().distance_to(RAID_CENTER) < RAID_DISTANCE
	if raiders.is_empty():
		if near: _spawn_raiders()
		return
	var alive := 0
	for raider in raiders:
		if is_instance_valid(raider) and not raider.dead: alive += 1
	if alive == 0:
		raiders.clear()
		if STATE.chain_advance(world, "finale", "gate"):
			session.show_message("Os Cobras recuaram. Vicente seguiu na frente para a passagem norte.")
			session.save_game()
	elif not near and session.player_position().distance_to(RAID_CENTER) > RAID_DISTANCE * 1.6:
		# Saiu da briga: o ataque recomeça inteiro na volta (sem meio ataque salvo).
		_release_raiders()

func _spawn_raiders() -> void:
	var region: Node3D = session.controller.regions.get("desert")
	if not is_instance_valid(region) or not region.surfaces_idle(): return
	var trace := STALL_WORK.begin()
	for i in RAID_POINTS.size():
		var local: Vector3 = RAID_POINTS[i]
		var point := RAID_CENTER + local
		point.y = HM.surface_height(Vector2(point.x, point.z)) + .06
		region.prepare_collision_at(point)
		var raider := Raider.new()
		raider.configure(session.world.gameplay, i % 3)
		raider.uniform_tones = [Color(0.18, 0.22, 0.16), Color(0.24, 0.20, 0.14), Color(0.16, 0.16, 0.18)]
		add_child(raider)
		raider.global_position = point
		raider.rotation.y = atan2(-local.x, -local.z)
		raider.engaged = true
		raider.alerted = true
		raiders.append(raider)
	STALL_WORK.finish_slow("desert.act2.raid", trace, 2000)
	session.show_message("Os Cobras chegaram ao encontro. Defenda a turma.")

func _release_raiders() -> void:
	for raider in raiders:
		if is_instance_valid(raider):
			raider.set_physics_process(false)
			raider.collision_layer = 0
			raider.collision_mask = 0
			raider.queue_free()
	raiders.clear()

func save_block_reason() -> String:
	for raider in raiders:
		if is_instance_valid(raider) and not raider.dead: return "Defenda o encontro antes de salvar."
	return ""

## Lugar pronto: chão do deserto e, quando é lugar da Estrada do Sal ou caverna, o lugar montado.
func _site_ready(spot: String) -> bool:
	var region: Node3D = session.controller.regions.get("desert")
	if not is_instance_valid(region) or not region.surfaces_idle(): return false
	var frontier = session.desert.frontier if session.desert != null else null
	if SPOTS[spot].has("cave"):
		return frontier != null and is_instance_valid(frontier.wilds) and frontier.wilds.sites.has(str(SPOTS[spot].cave))
	if not ROADSIDE.enabled() or not SPOTS[spot].has("site"): return true
	if frontier == null or not is_instance_valid(frontier.roadside): return false
	var record: Dictionary = frontier.roadside.sites.get(str(SPOTS[spot].site), {})
	return not record.is_empty() and not bool(record.parked)

static func _cave_site(id: String) -> Dictionary:
	for site in WILDS.SITES:
		if str(site.id) == id: return site
	return {}

func _site_point(spot: String, local: Vector3) -> Vector3:
	var def: Dictionary = SPOTS[spot]
	if def.has("cave"):
		var site := _cave_site(str(def.cave))
		var center: Vector2 = site.center
		return WILDS.ground(center) + Basis(Vector3.UP, float(site.yaw)) * local
	if def.has("anchor"):
		var anchor: Vector3 = def.anchor + local
		return Vector3(anchor.x, HM.surface_height(Vector2(anchor.x, anchor.z)), anchor.z)
	var definition := ROADSIDE.site(str(def.site))
	var center: Vector2 = definition.center
	return ROADSIDE.at(definition, local, HM.surface_height(center))

## Pontos candidatos do lugar; na caverna, em volta da fogueira (o lado dela depende da caverna).
func _points(spot: String) -> Array:
	if not SPOTS[spot].has("cave"): return SPOTS[spot].points
	var id := str(SPOTS[spot].cave)
	var fire := CAVE.fire_point(id)
	var side := CAVE.side(id)
	return [Vector3(fire.x, 0, fire.z + 2.0), Vector3(fire.x - side * 1.6, 0, fire.z + 1.6), Vector3(fire.x, 0, fire.z - 2.0)]

func _face_point(spot: String) -> Vector3:
	if SPOTS[spot].has("cave"):
		var fire := CAVE.fire_point(str(SPOTS[spot].cave))
		return _site_point(spot, Vector3(fire.x, 0, fire.z))
	return _site_point(spot, SPOTS[spot].face)

func _admit(def: Dictionary) -> void:
	var spot := str(def.spot)
	session.controller.region.prepare_collision_at(_site_point(spot, Vector3.ZERO))
	var lift := float(SPOTS[spot].get("ray", 3.0))
	for local: Vector3 in _points(spot):
		var guess := _site_point(spot, local)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(guess + Vector3.UP * lift, guess - Vector3.UP * 2.0, 1))
		if hit.is_empty() or float(hit.normal.y) < .9: continue
		var point: Vector3 = hit.position + Vector3.UP * .05
		if not session.position_clear(point): continue
		actor = BrotherFighter.new() if str(def.scene) == "brothers_fight" else CONTACT.new()
		actor.identity_id = str(def.who)
		actor.position = point
		add_child(actor)
		# Fora do grupo da turma do encontro: aqui ele está sozinho (o teste do encontro conta a turma).
		actor.remove_from_group("desert_drag_crew")
		actor.set_meta("act2_scene", str(def.scene))
		_actor_stage = str(def.scene)
		_face(spot)
		return

func _face(spot: String) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.visual) or actor.dead: return
	var talking: bool = session.modal and session.dialogue_open
	var target: Vector3 = session.player_position() if talking else _face_point(spot)
	var offset := target - actor.global_position
	actor.visual.rotation.y = atan2(offset.x, offset.z)
	actor.set_talking(talking)

func _release() -> void:
	if is_instance_valid(actor):
		actor.hide()
		actor.collision_layer = 0
		actor.queue_free()
	actor = null
	_actor_stage = ""

func _available() -> bool:
	return session != null and session.ready_for_play and session.state.region_id == "desert" and session.state.place_id.is_empty() and not session.modal and not session.player_in_vehicle() and session.player_health() > 0 and not session.is_transition_blocked()

func nearest_action() -> Dictionary:
	if session == null or not session.ready_for_play or session.state.region_id != "desert" or not session.state.place_id.is_empty(): return {}
	if session.player_in_vehicle(): return _race_action()
	if not _available(): return {}
	var player: Vector3 = session.player_position()
	var spot := _mission_point()
	if not spot.is_empty() and player.distance_to(spot.point) <= float(spot.reach): return {"id": "desert_story", "target": spot.target, "label": spot.label}
	if not is_instance_valid(actor) or actor.dead: return {}
	if actor is BrotherFighter and not actor.down: return {}
	if player.distance_to(actor.global_position) > TALK_DISTANCE: return {}
	return {"id": "desert_story", "target": "vicente_reunion", "label": "Conversar com " + str(CONTACT.LOOKS[actor.identity_id].name)}

## Prova de história (A2-05 contra Vicente, A2-08 contra o Cascavel): de carro, parado na concentração.
func story_race() -> String:
	var world := _world()
	if chain_at(world, "brothers") == "race": return "vicente"
	if chain_at(world, "bet") == "race": return "cascavel"
	return ""

func story_race_open(identity: String) -> bool:
	return not identity.is_empty() and story_race() == identity

func _race_action() -> Dictionary:
	var rival := story_race()
	if rival.is_empty() or session.modal or session.desert == null or not is_instance_valid(session.desert.drag) or session.desert.drag.active: return {}
	var car = session.player_vehicle()
	if not is_instance_valid(car) or car.global_position.distance_to(STAGING) > RACE_REACH: return {}
	return {"id": "desert_story", "target": "act2:race", "label": "Alinhar contra " + str(CONTACT.LOOKS[rival].name)}

## Ponto de ação sem ator da etapa atual.
func _mission_point() -> Dictionary:
	var world := _world()
	match chain_at(world, "cargo"):
		"crate": return {"target": "act2:crate", "point": MIRAGE_CRATE, "reach": 1.6, "label": "Abrir o caixote dos Cobras"}
		"weigh": return {"target": "act2:rosa", "point": rosa_point(), "reach": 2.4, "label": "Mostrar o lacre à Fiscal Rosa"}
	if chain_at(world, "order") == "call":
		return {"target": "act2:phone", "point": HORIZON_PHONE, "reach": 1.8, "label": "Ligar para o Maciota do orelhão"}
	match chain_at(world, "letters"):
		"": return {"target": "act2:fatima", "point": roadside_point("chapel", ROADSIDE.CHAPEL_KEEPER), "reach": 2.4, "label": "Perguntar à Dona Fátima"}
		"tower": return {"target": "act2:tower", "point": roadside_point("radio_tower", ROADSIDE.TOWER_LADDER), "reach": 2.4, "label": "Subir na torre e ligar para o Maciota"}
		"coop": return {"target": "act2:coop", "point": coop_point(), "reach": 2.2, "label": "Pedir o malote pelo rádio da cooperativa"}
	# A2-12: Teodoro escapou antes de Dante chegar (o tempo da fuga acabou): sobra a pasta no chão.
	if chain_at(world, "teodoro") == "chase" and _chase_lost():
		return {"target": "act2:folder", "point": folder_point(), "reach": 2.2, "label": "Pegar a pasta largada"}
	if chain_at(world, "trunk") == "":
		return {"target": "act2:nonato", "point": roadside_point("scrapyard", ROADSIDE.SCRAP_DEALER), "reach": 2.4, "label": "Perguntar ao Nonato por um carro"}
	match chain_at(world, "salt"):
		"": return {"target": "act2:bento", "point": roadside_point("salt_works", ROADSIDE.SALT_FOREMAN), "reach": 2.4, "label": "Mostrar o lacre ao Seu Bento"}
		"camp":
			if _camp_cleared(): return {"target": "act2:ledger", "point": ledger_point(), "reach": 2.6, "label": "Pegar o caderno meio queimado"}
	return {}

static func roadside_point(site_id: String, local: Vector3) -> Vector3:
	var definition := ROADSIDE.site(site_id)
	var center: Vector2 = definition.center
	return ROADSIDE.at(definition, local, HM.surface_height(center))

static func rosa_point() -> Vector3:
	return roadside_point("weigh_station", ROADSIDE.WEIGH_INSPECTOR)

static func coop_point() -> Vector3:
	var point: Vector3 = COMMUNITY.RADIO + Vector3(0, 0, .9)
	point.y = HM.surface_height(Vector2(point.x, point.z))
	return point

static func ledger_point() -> Vector3:
	var site := _cave_site(LEDGER_SITE)
	return WILDS.ground(site.center)

## O caderno só sai com o acampamento montado e sem fora-da-lei de pé.
func _camp_cleared() -> bool:
	var frontier = session.desert.frontier if session.desert != null else null
	if frontier == null or not is_instance_valid(frontier.wilds) or not frontier.wilds.sites.has(LEDGER_SITE): return false
	for outlaw in frontier.wilds.sites[LEDGER_SITE].get("actors", []):
		if is_instance_valid(outlaw) and not outlaw.dead: return false
	return true

func perform(target: String) -> bool:
	if nearest_action().get("target", "") != target: return false
	var world := _world()
	match target:
		"act2:crate": _say(crate_lines(), "cargo:weigh")
		"act2:rosa": _say(rosa_lines(), "cargo:raul")
		"act2:phone": _say(phone_lines(), "order:done")
		"act2:fatima": _say(LINES.fatima(), "letters:tower")
		"act2:tower": _say(LINES.tower(), "letters:coop")
		"act2:coop": _say(LINES.coop(), "letters:water")
		"act2:bento": _say(LINES.bento(), "salt:camp")
		"act2:ledger": _say(LINES.ledger(), "salt:home")
		"act2:folder": _say(LINES.teodoro_gate(false), "teodoro:done")
		"act2:nonato": return _nonato_car()
		"act2:race": return session.desert.drag.start_rival(story_race())
		"vicente_reunion": return _talk_actor(world)
		_: return false
	return true

func _talk_actor(world: Dictionary) -> bool:
	match _actor_stage:
		"motel": _say(motel_lines(session.state.economy.snapshot().collectibles), "chapel")
		"chapel": _say(chapel_lines(), "done")
		"grandstand":
			var race: Dictionary = RACE.data(world)
			_say(grandstand_lines("digo" in race.wins, float(race.best.get("digo", 0.0))), "track_done")
		"bank_night": _say(irene_night_lines(), "order:call")
		"cave":
			# Conversa, flashback jogável da blitz pelos olhos do Vicente, e o resto da conversa.
			var before := LINES.cave_before(LETTERS.complete(session.state.economy.snapshot().collectibles), session.state.economy.has_reward_receipt(LETTERS.CAR_RECEIPT))
			_say_then(before, func(): _flashback("vicente", func(): _say(LINES.cave_after(), "cave:done")))
		"water_tower": _say(LINES.water_tower(), "letters:done")
		"helena_home": _say(LINES.helena_home(), "salt:done")
		"brothers_fight":
			if actor is BrotherFighter and actor.down: _say(LINES.brothers_fight_after(), "teodoro:chase")
			else: return false
		"cascavel":
			if chain_at(world, "bet") == "cascavel":
				_say_then(LINES.cascavel(), func():
					_finish_step("bet:race")
					_vicente_shot())
			else:
				_say(LINES.cascavel_keys(_bet_won), "bet:done")
		"convoy_motel": _say(LINES.convoy_motel(), "convoy:done")
		"teodoro_motel": _say(LINES.teodoro_motel(), "teodoro:fight")
		"teodoro_gate": _say(LINES.teodoro_gate(true), "teodoro:done")
		"finale_grandstand": _say(LINES.finale_grandstand(), "finale:defend")
		"finale_gate": _say(LINES.finale_gate(), "finale:done")
		_: return false
	return true

## A2-09: o Nonato dá o Bison do fundo do pátio; vira carro da frota do deserto, na baia do ferro-velho.
func _nonato_car() -> bool:
	var world := _world()
	if chain_at(world, "trunk") != "": return false
	var definition := ROADSIDE.site("scrapyard")
	var bay := roadside_point("scrapyard", ROADSIDE.SCRAP_BAY) + Vector3.UP * .15
	var yaw := float(definition.yaw)
	session.controller.region.prepare_collision_at(bay)
	var car: CharacterBody3D = session.controller.spawn_vehicle(STATE.NONATO_CAR_ARCHETYPE, bay, yaw)
	if not is_instance_valid(car): session.show_message("Libere a baia do ferro-velho."); return false
	if not session.controller.vehicle_position_clear(car, bay, yaw):
		car.queue_free()
		session.show_message("Libere a baia do ferro-velho.")
		return false
	car.vehicle_id = STATE.NONATO_CAR_ID
	car.paint_color = Color("8c7a5c")
	_say(LINES.nonato(), "trunk:car", {"car": car})
	return true

## Contatos do encontro (DesertCampaign chama pelo "Conversar" deles).
func vicente() -> bool:
	var world := _world()
	match chain_at(world, "brothers"):
		"":
			session.show_message("Ato 2 · " + str(CHAIN_TITLES.brothers))
			_say(LINES.brothers_start(), "brothers:race")
		"race": _say([["Vicente", "Encosta o carro na concentração. Eu vou com o meu."]], "")
		"won", "lost": _say(LINES.brothers_after(chain_at(world, "brothers") == "won"), "brothers:done")
		_: return false
	return true

func jessica() -> bool:
	var world := _world()
	if chain_at(world, "bet") != "" or not bool(STORY.data(world).jessica_met): return false
	session.show_message("Ato 2 · " + str(CHAIN_TITLES.bet))
	_say(LINES.jessica_bet(), "bet:cascavel")
	return true

## Resultado das provas de história (DesertCampaign.race_finished).
func race_finished(result: Dictionary) -> void:
	if not result.get("finished", false): return
	var world := _world()
	var won := bool(result.get("won", false))
	match str(result.get("rival_id", "")):
		"vicente":
			if STATE.chain_advance(world, "brothers", "won" if won else "lost"):
				session.show_message("Fale com Vicente no encontro.")
		"cascavel":
			_bet_won = won
			if STATE.chain_advance(world, "bet", "keys"):
				session.show_message("O Cascavel espera a chave na concentração.")

## A2-01, A2-02 e A2-09 pela Bia; A2-03 pelo Raul; A2-04 pela Irene.
func bia() -> bool:
	var world := _world()
	if STATE.complete(world) and STATE.track_stage(world) == "":
		session.show_message("Ato 2 · " + TRACK_TITLE)
		_say(bia_lines(), "race")
		return true
	if chain_at(world, "trunk") in ["", "car"]:
		var car := _car_for_trunk()
		if not is_instance_valid(car):
			_say([["Bia", "Traz um carro pra cá, Dante, e estaciona aqui no pátio. O Nonato, no ferro-velho, tem um parado."]], "")
			return true
		_say(LINES.trunk_ready(car.vehicle_id == STATE.NONATO_CAR_ID), "trunk:done", {"trunk_car": car.vehicle_id})
		return true
	return false

## Carro da frota do deserto parado no pátio da Bia (o do Nonato, um comprado, o Supra, o Coyote).
func _car_for_trunk() -> CharacterBody3D:
	if session.desert == null: return null
	var fleet: Dictionary = _world().get("desert_fleet", {})
	var best: CharacterBody3D = null
	for car in session.controller.vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not fleet.has(car.vehicle_id) or car.health <= 0: continue
		var distance: float = car.global_position.distance_to(BIA_POINT)
		if distance > BIA_CAR_REACH: continue
		if best == null or distance < best.global_position.distance_to(BIA_POINT): best = car
	return best

func raul() -> bool:
	var world := _world()
	match chain_at(world, "cargo"):
		"":
			session.show_message("Ato 2 · " + str(CHAIN_TITLES.cargo))
			_say(raul_start_lines(), "cargo:crate")
		"raul": _say(raul_end_lines(), "cargo:done")
		"crate", "weigh": _say([["Raul", "O caixote está do lado das bombas do Miragem. Depois, a Rosa, na Balança."]], "")
		_: return false
	return true

func irene() -> bool:
	var world := _world()
	match chain_at(world, "order"):
		"":
			session.show_message("Ato 2 · " + str(CHAIN_TITLES.order))
			_say(irene_bank_lines(), "order:night")
		"night": _say([["Irene", "Aqui dentro, não. Depois das oito, na porta."]], "")
		_: return false
	return true

## Primeira etapa de A2-01, chamada pelo DesertCampaign ao falar com o Vicente do encontro.
func meet() -> bool:
	if stage() != "": return false
	session.show_message("Ato 2 · " + TITLE)
	_say(meet_lines(), "motel")
	return true

## Diálogo que termina chamando outra coisa (flashback, plano do Vicente), só com Dante vivo e solto.
func _say_then(rows: Array, next: Callable) -> void:
	var lines: Array = []
	for row in rows: lines.append({"speaker": row[0], "message": row[1]})
	session.show_dialogue(lines, func():
		if session.player_health() > 0 and not session.arrest_pending and not session.rescue_pending and session.state.region_id == "desert": next.call())

## Flashback jogável da blitz pelos olhos do Vicente (runtime/prologue/BlitzScene.gd, a mesma noite do
## prólogo): a cena pausa o mundo, roda num viewport próprio e chama `next` no fim ou no pulo.
const BLITZ := preload("res://runtime/prologue/BlitzScene.gd")
## Testes: a cena joga sozinha e mais rápido.
var flashback_autoplay := false
var flashback_pace := 1.0
func _flashback(point_of_view: String, next: Callable) -> void:
	var scene = BLITZ.start(session, point_of_view, func(_skipped := false): next.call())
	if scene == null:
		next.call()
		return
	scene.autoplay = flashback_autoplay
	scene.pace = flashback_pace

## A2-08: um plano curto no Vicente perto do carro, antes da largada da aposta (o jogador vê antes do Dante).
func _vicente_shot() -> void:
	var campaign = get_parent()
	var vicente = campaign.actors.get("vicente") if campaign != null and "actors" in campaign else null
	if not is_instance_valid(vicente) or session.modal: return
	var previous := get_viewport().get_camera_3d()
	var shot := Camera3D.new()
	shot.name = "Act2VicenteShot"
	shot.fov = 40.0
	add_child(shot)
	shot.global_position = vicente.global_position + Vector3(2.2, 1.5, 2.2)
	shot.look_at(vicente.global_position + Vector3.UP * 1.0)
	shot.make_current()
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(previous): previous.make_current()
		if is_instance_valid(shot): shot.queue_free())

# --- A2-12: briga dos irmãos e fuga do Teodoro -----------------------------------------------------
## A fuga dura isto: chegou à obra antes, o Teodoro ainda está lá; depois, só a pasta no chão.
const CHASE_SECONDS := 150.0
const FIGHT_PUNCH := 6.0
var _chase_deadline_msec := 0
var _fight_clock := 0.0

func _chase_lost() -> bool:
	return _chase_deadline_msec > 0 and Time.get_ticks_msec() > _chase_deadline_msec

static func folder_point() -> Vector3:
	var point := Vector3(342.5, 0, -1810) + Vector3(0, 0, 33)
	point.y = HM.surface_height(Vector2(point.x, point.z))
	return point

## Vicente parte para cima; cada soco que acerta tira um pouco de vida de Dante. Ele cai antes de morrer
## (BrotherFighter), e aí a conversa abre.
func _tick_fight() -> void:
	if not is_instance_valid(actor) or not actor is BrotherFighter or actor.down: return
	var player: Vector3 = session.player_position()
	var offset: Vector3 = player - actor.global_position
	offset.y = 0
	actor.chase(offset)
	_fight_clock -= .3
	if offset.length() < 1.4 and _fight_clock <= 0.0:
		_fight_clock = 1.2
		session.world.gameplay.damage_player(FIGHT_PUNCH, actor.global_position)

func _say(rows: Array, next_stage: String, extra := {}) -> void:
	var lines: Array = []
	for row in rows: lines.append({"speaker": row[0], "message": row[1]})
	session.show_dialogue(lines, func(): _finish_step(next_stage, extra))

## Fim de um diálogo: só conta se Dante continua vivo, solto e no deserto.
func _finish_step(next_stage: String, extra := {}) -> void:
	var car: Variant = extra.get("car")
	var alive: bool = session.player_health() > 0 and not session.arrest_pending and not session.rescue_pending and session.state.region_id == "desert"
	if not alive:
		# O carro do Nonato só existe se a conversa terminou.
		if car != null and is_instance_valid(car): car.queue_free()
		return
	var world := _world()
	if next_stage.is_empty(): return
	if next_stage.contains(":"):
		var parts := next_stage.split(":")
		var id := parts[0]
		if parts[1] == "done":
			# O rótulo só nomeia a origem no aviso central de dinheiro; o estado não o grava.
			var paid_extra: Dictionary = extra.duplicate()
			paid_extra.label = String(TranslationServer.translate(str(CHAIN_TITLES[id])))
			var result: Dictionary = STATE.chain_finish(world, session.state.economy, id, paid_extra)
			if not result.ok:
				# Carteira cheia: a missão espera na última conversa, que paga na próxima vez.
				if str(result.reason) != "stage": session.show_message("Libere espaço na carteira para receber o pagamento.")
				return
			REWARD_AUDIO.play(session, "collectible")
			var title := String(TranslationServer.translate(str(CHAIN_TITLES[id])))
			session.show_message(String(TranslationServer.translate("%s concluída")) % title)
			if id == "finale": session.show_message("Ato 2 concluído · A passagem norte está aberta.")
		else:
			var from := STATE.chain_stage(world, id)
			if id == "trunk" and parts[1] == "car":
				if car == null or not is_instance_valid(car) or not _grant_nonato_car(car): return
			if not STATE.chain_advance(world, id, parts[1]): return
			if from == "" and id not in ["brothers", "bet"]: session.show_message("Ato 2 · " + str(CHAIN_TITLES[id]))
			if id == "teodoro" and parts[1] == "chase":
				_chase_deadline_msec = Time.get_ticks_msec() + int(CHASE_SECONDS * 1000.0)
				session.show_message("O Teodoro fugiu de carro para a obra da passagem norte. Corra.")
		session.save_game()
		return
	if next_stage == "race":
		if not STATE.track_advance(world, "race"): return
	elif next_stage == "track_done":
		if not STATE.track_advance(world, "done"): return
		REWARD_AUDIO.play(session, "collectible")
		session.show_message(String(TranslationServer.translate("%s concluída")) % String(TranslationServer.translate(TRACK_TITLE)))
	elif next_stage == "done":
		# Paga antes de marcar (carteira cheia não marca), então confere a etapa antes de pagar.
		if stage() != "chapel": return
		var paid: Dictionary = session.state.economy.grant_world_reward({"id": STATE.ENVELOPE_RECEIPT, "kind": "cash", "amount": STATE.ENVELOPE_AMOUNT, "label": "Envelope de Vicente"})
		if not paid.ok:
			# Carteira cheia: a missão espera na capela, e a próxima conversa tenta de novo.
			session.show_message("Libere espaço na carteira para receber o envelope de Vicente.")
			return
		if not STATE.advance(world, "done"): return
		STORY.mark(world, "met_vicente")
		REWARD_AUDIO.play(session, "collectible")
		session.show_message(String(TranslationServer.translate("%s concluída")) % String(TranslationServer.translate(TITLE)))
	elif not STATE.advance(world, next_stage): return
	session.save_game()

## Recibo de valor zero e frota do deserto, como o Coyote das cartas (DesertWilds._update_brother).
func _grant_nonato_car(car: CharacterBody3D) -> bool:
	var economy = session.state.economy
	if not economy.has_reward_receipt(STATE.NONATO_CAR_RECEIPT) and not economy.grant_reward(STATE.NONATO_CAR_RECEIPT, 0): return false
	var world := _world()
	if not world.has("desert_fleet"): world.desert_fleet = {}
	world.desert_fleet[STATE.NONATO_CAR_ID] = FLEET_STATE.capture(car, session.state.region_id)
	if session.desert != null and session.desert.has_method("_track_owned"): session.desert._track_owned(car)
	REWARD_AUDIO.play(session, "collectible")
	return true

func objective() -> String: return _objectives.objective()

static func objective_for(world: Dictionary) -> String: return OBJECTIVES.objective_for(world)

func target_position() -> Vector3: return _objectives.target_position()

# --- Falas --------------------------------------------------------------------------------------
# As falas de A2-01 a A2-04 moram em Act2Lines desde 01/11, junto com as do resto do ato 2; as
# delegações ficam porque o fluxo e os testes chamam REUNION.*_lines().
static func meet_lines() -> Array: return LINES.meet_lines()
static func motel_lines(collectibles: Array) -> Array: return LINES.motel_lines(collectibles)
static func bia_lines() -> Array: return LINES.bia_lines()
static func grandstand_lines(won: bool, seconds: float) -> Array: return LINES.grandstand_lines(won, seconds)
static func raul_start_lines() -> Array: return LINES.raul_start_lines()
static func crate_lines() -> Array: return LINES.crate_lines()
static func rosa_lines() -> Array: return LINES.rosa_lines()
static func raul_end_lines() -> Array: return LINES.raul_end_lines()
static func irene_bank_lines() -> Array: return LINES.irene_bank_lines()
static func irene_night_lines() -> Array: return LINES.irene_night_lines()
static func phone_lines() -> Array: return LINES.phone_lines()
static func chapel_lines() -> Array: return LINES.chapel_lines()
