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
const TITLE := "Oito anos"
const TRACK_TITLE := "Respeita a pista"
const CHAIN_TITLES := {"cargo": "Peso morto", "order": "A ordem alterada", "brothers": "Racha de irmãos", "cave": "Mesa de pedra",
	"letters": "Destinatário desconhecido", "bet": "Chave na chave", "trunk": "Porta-malas novo", "convoy": "Comboio da madrugada",
	"salt": "Sal na ferida", "teodoro": "Teodoro", "finale": "Os oito anos"}
## Caixote dos Cobras no Miragem: o mesmo ponto de DesertCampaign.MANIFEST (que monta o caixote).
const MIRAGE_CRATE := Vector3(266, .05, -758)
## Orelhão do Horizonte: o ponto do "Descansar até as 20h" (DesertRuntime), que a ação da missão
## cobre enquanto a ligação está pendente.
const HORIZON_PHONE := Vector3(-315, 0, -913)
## Porta do Cobre (DesertLayout.place_definitions: entrada a 1,4 m da fachada); Irene espera no pátio,
## além das saídas laterais (2,8 m), fora do caminho da porta.
const BANK_DOOR := Vector3(-210, 0, -911.6)
## Bia no pátio do Digo (DesertCampaign.LOCATIONS.bia) e o raio em que o carro conta como "trazido".
const BIA_POINT := Vector3(-151, 0, -943)
const BIA_CAR_REACH := 18.0
## Concentração da arrancada (DesertLayout.DRAG_STAGING): onde as provas de história começam.
const STAGING := Vector3(-915, 0, -1304)
const RACE_REACH := 15.0
## Acampamento dos foras-da-lei ao sul do leito seco (DesertWilds "outlaws_ridge").
const LEDGER_SITE := "outlaws_ridge"
## Ataque final: quatro Cobras chegando ao encontro pelo lado da pista.
const RAID_CENTER := Vector3(-965, 0, -1262)
const RAID_POINTS := [Vector3(-20, 0, -26), Vector3(-6, 0, -30), Vector3(10, 0, -28), Vector3(24, 0, -24)]
const RAID_DISTANCE := 110.0
## Onde cada um espera. "site": lugar da Estrada do Sal (local do lugar); "anchor": ponto do mundo (+ local);
## "cave": caverna do DesertWilds (local da caverna). Pontos candidatos: o primeiro livre vale.
## Motel: calçada sob a marquise, na frente da porta do quarto 6 (fora das colunas, da lixeira e da
## máquina de gelo). Capela: no terreiro, longe da zeladora (que atende a vela a 2,4 m dela).
const SPOTS := {
	"motel": {"site": "motel", "points": [Vector3(2.6, 0, 1.0), Vector3(-1.6, 0, 1.0), Vector3(-1.0, 0, 4.2)], "face": Vector3(0, 0, 6)},
	"chapel": {"site": "chapel", "points": [Vector3(-2.6, 0, 3.8), Vector3(-2.4, 0, 6.0), Vector3(2.4, 0, 6.4)], "face": Vector3(0, 0, -1)},
	# Na frente do guarda-corpo (sólido em z 4), olhando a reta; a mais de 2,4 m do Seu Zé (18,3; 3),
	# que tem a ação dele na beira de estrada e vem antes na ordem das ações.
	"grandstand": {"site": "grandstand", "points": [Vector3(13.0, 0, 5.5), Vector3(10.0, 0, 5.5), Vector3(13.0, 0, 7.0)], "face": Vector3(13.0, 0, 30.0)},
	# A2-04: Irene sai do caixa depois das 20h e espera no pátio do banco (só à noite).
	"bank_night": {"anchor": BANK_DOOR, "night": true, "points": [Vector3(4.2, 0, 2.2), Vector3(-4.2, 0, 2.2), Vector3(4.2, 0, 4.0)], "face": Vector3(0, 0, 0)},
	# A2-06: perto da fogueira da caverna do Coyote (pontos calculados pelo lado da caverna em _points).
	"cave": {"cave": "cave_brother", "points": [], "face": Vector3.ZERO, "ray": 1.6},
	# A2-08: Cascavel na beira da concentração, do lado do encontro (fora das faixas da pista).
	"meet_edge": {"anchor": STAGING, "points": [Vector3(-9, 0, 9), Vector3(-12, 0, 11), Vector3(-7, 0, 13)], "face": Vector3(0, 0, 0)},
	# A2-12/A2-13: na pista da passagem norte, antes dos operários (z -1786 a -1791) e da área fechada da
	# obra (DesertNorthPassLayout.restore_point devolve quem salva além de z -1786); a barreira em si fica
	# colada nas pedras e não deixa lugar livre para conversar.
	# Santa Lua: a caixa-d'água junto da torre da cooperativa (A2-07) e a praça perto da casa da Helena (A2-11).
	"water_tower": {"anchor": COMMUNITY.ORIGIN, "points": [Vector3(2.5, 0, 3.0), Vector3(-2.5, 0, 3.0), Vector3(3.5, 0, -2.0)], "face": Vector3(0, 0, 8)},
	"santa_lua": {"anchor": Vector3(-528, 0, -830), "points": [Vector3(3.0, 0, 2.0), Vector3(-3.0, 0, 2.0), Vector3(0, 0, 5.0)], "face": Vector3(0, 0, -6)},
	"gate": {"anchor": Vector3(342.5, 0, -1810), "points": [Vector3(0, 0, 35), Vector3(4, 0, 37), Vector3(-4, 0, 37)], "face": Vector3(0, 0, 0)},
}
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

## Etapa de uma missão da cadeia, ou "-" se a anterior ainda não acabou.
static func chain_at(world: Dictionary, id: String) -> String:
	return STATE.chain_stage(world, id) if STATE.chain_ready(world, id) else "-"

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

static func scene_for(world: Dictionary) -> String:
	return str(scene_def(world).get("scene", ""))

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
	var outside: bool = session.state.region_id == "desert" and session.state.place_id.is_empty() and session.world.gameplay.health > 0
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
	var player: Vector3 = session.world.player.global_position
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
	var near: bool = session.world.player.global_position.distance_to(RAID_CENTER) < RAID_DISTANCE
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
	elif not near and session.world.player.global_position.distance_to(RAID_CENTER) > RAID_DISTANCE * 1.6:
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
	var target: Vector3 = session.world.player.global_position if talking else _face_point(spot)
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
	return session != null and session.ready_for_play and session.state.region_id == "desert" and session.state.place_id.is_empty() and not session.modal and not session.world.driving.occupied and session.world.gameplay.health > 0 and not session.is_transition_blocked()

func nearest_action() -> Dictionary:
	if session == null or not session.ready_for_play or session.state.region_id != "desert" or not session.state.place_id.is_empty(): return {}
	if session.world.driving.occupied: return _race_action()
	if not _available(): return {}
	var player: Vector3 = session.world.player.global_position
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
	var car = session.world.driving.car
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
		if session.world.gameplay.health > 0 and not session.arrest_pending and not session.rescue_pending and session.state.region_id == "desert": next.call())

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
	var player: Vector3 = session.world.player.global_position
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
	var alive: bool = session.world.gameplay.health > 0 and not session.arrest_pending and not session.rescue_pending and session.state.region_id == "desert"
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

func objective() -> String:
	return objective_for(_world())

static func objective_for(world: Dictionary) -> String:
	match STATE.stage(world):
		"motel": return "Vá ao Motel Oásis, na Estrada do Sal, e fale com Vicente."
		"chapel": return "Encontre Vicente na Capela da Estrada."
	if not STATE.complete(world): return ""
	match STATE.track_stage(world):
		"": return "Fale com Bia no pátio do Digo."
		"race": return "Corra contra Digo na reta: quadro da concentração."
		"grandstand": return "Encontre Vicente na Arquibancada da reta."
	match chain_at(world, "cargo"):
		"": return "Fale com Raul no encontro da arrancada."
		"crate": return "Abra o caixote dos Cobras no posto Miragem."
		"weigh": return "Leve o lacre à Fiscal Rosa, na Balança da Estrada do Sal."
		"raul": return "Volte ao Raul no encontro da arrancada."
	match chain_at(world, "order"):
		"": return "Leve o manifesto a Irene, no Cobre."
		"night": return "Vá à porta dos fundos do Cobre depois das 20h (descanse no Horizonte)."
		"call": return "Ligue para o Maciota do orelhão do Horizonte."
	match chain_at(world, "brothers"):
		"": return "Fale com Vicente no encontro da arrancada."
		"race": return "Corra contra Vicente: pare o carro na concentração."
		"won", "lost": return "Fale com Vicente no encontro da arrancada."
	if chain_at(world, "cave") == "": return "Encontre Vicente na caverna da mesa de pedra, ao sul do leito seco."
	match chain_at(world, "letters"):
		"": return "Pergunte à Dona Fátima, na Capela da Estrada."
		"tower": return "Suba na torre de rádio da Rua Principal e ligue para o Maciota."
		"coop": return "Peça o malote antigo pelo rádio da cooperativa de Santa Lua."
		"water": return "Encontre Helena na caixa-d'água de Santa Lua."
	match chain_at(world, "bet"):
		"": return "Fale com Jessica no encontro da arrancada." if bool(STORY.data(world).jessica_met) else "Corra contra Jessica pelo quadro da concentração."
		"cascavel": return "Fale com o Cascavel na concentração."
		"race": return "Chave na chave: corra contra o Cascavel (pare o carro na concentração)."
		"keys": return "Entregue a chave da Monaliza ao Cascavel."
	match chain_at(world, "trunk"):
		"": return "Arranje outro carro (o Nonato, no ferro-velho, tem um) e leve à Bia, no pátio do Digo."
		"car": return "Leve o carro do Nonato à Bia, no pátio do Digo."
	match chain_at(world, "convoy"):
		"": return "Roube a carga do comboio dos Cobras na Estrada do Sal, de madrugada (0h às 5h)."
		"motel": return "Leve o lacre a Vicente, no Motel Oásis."
	match chain_at(world, "salt"):
		"": return "Mostre o lacre ao Seu Bento, nas Salinas."
		"camp": return "Recupere o caderno no acampamento ao sul do leito seco."
		"home": return "Vá à casa da Helena em Santa Lua."
	match chain_at(world, "teodoro"):
		"": return "Dona Lurdes chamou: vá ao Motel Oásis."
		"fight": return "Vicente partiu pra cima. Derrube seu irmão."
		"chase": return "Alcance Teodoro na obra da passagem norte."
	match chain_at(world, "finale"):
		"": return "Encontre Vicente na Arquibancada da reta."
		"defend": return "Defenda o encontro da arrancada dos Cobras."
		"gate": return "Encontre Vicente na passagem norte."
	return ""

func target_position() -> Vector3:
	var spot := _mission_point()
	if not spot.is_empty(): return spot.point
	var world := _world()
	if not story_race().is_empty(): return STAGING
	if chain_at(world, "finale") == "defend": return RAID_CENTER
	if chain_at(world, "salt") == "camp": return ledger_point()
	if chain_at(world, "teodoro") == "chase" and not is_instance_valid(actor): return folder_point()
	if chain_at(world, "trunk") == "car" or (chain_at(world, "trunk") == "" and _car_for_trunk() != null): return BIA_POINT
	var def := scene_def(world)
	if not def.is_empty():
		if is_instance_valid(actor): return actor.global_position
		return _site_point(str(def.spot), _points(str(def.spot))[0])
	if chain_at(world, "brothers") in ["", "won", "lost"]: return LAYOUT.DRAG_VICENTE
	if chain_at(world, "bet") == "": return ROSTER.LEADERS.jessica if bool(STORY.data(world).jessica_met) else STAGING
	return Vector3.INF

# --- Falas --------------------------------------------------------------------------------------
# Escritas pela seção "Como escrever as falas" de docs/roteiro-diretor-geteco-20261021.md: fala
# curta, português falado, subtexto; ninguém explica o que o outro já sabe. Vicente lê os oito anos
# como abandono e hoje rouba carro para os Cobras (a chave de cliente de Harbor no motel). Sementes
# para depois: as cartas voltaram com "destinatário desconhecido" para um endereço que nunca mudou, e
# o advogado mentia para os dois.

static func meet_lines() -> Array:
	return [
		["Vicente", "Ó. Parou todo mundo. Dante Ferraz no meu encontro."],
		["Dante", "Vicente."],
		["Vicente", "Oito anos. (ri) Oito anos e cê chega de carro emprestado."],
		["Dante", "Eu pedi o processo de volta. Saí da polícia por causa dele."],
		["Vicente", "Que bonito. Lá dentro eu tinha uma parede e um prego. Riscava um dia por vez."],
		["Dante", "Eu sei."],
		["Vicente", "Sabe nada."],
		["Vicente", "Aqui ninguém resolve nada na bala. Nem no distintivo. Essa turma é minha."],
		["Vicente", "Motel Oásis, na Estrada do Sal. Quarto seis. Não vou fazer isso na frente deles."],
		["Vicente", "E vem sem sirene, se ainda souber."],
	]

static func motel_lines(collectibles: Array) -> Array:
	var found := LETTERS.found(collectibles)
	var rows: Array = [
		["Vicente", "Veio sozinho. Já é alguma coisa."],
		["Dante", "Que chave é essa?"],
		["Vicente", "(enfia no bolso) De carro. Tem carro no deserto, sabia?"],
		["Dante", "Com chaveiro de oficina de Harbor."],
		["Vicente", "Cê vai me revistar também? Senta aí."],
		["Vicente", "Primeira noite que eu saí, dormi aqui. Luz acesa, porta aberta. A Dona Lurdes achou que eu ia fugir sem pagar."],
	]
	if found == 0:
		rows.append_array([
			["Vicente", "Eu te escrevi. Dez vezes. Voltou tudo. Destinatário desconhecido."],
			["Dante", "Eu morei no mesmo lugar os oito anos."],
			["Vicente", "Então alguém não queria que cê lesse. Ou cê tá mentindo."],
			["Vicente", "Deixei as cartas pelo caminho. Harbor, a serra, aqui. Quer saber o que eu pensei lá dentro? Vai buscar."],
		])
	elif found < LETTERS.IDS.size():
		rows.append_array([
			["Vicente", "O Maciota disse que cê anda catando carta minha por aí."],
			["Dante", String(TranslationServer.translate("Achei %d. Todas voltaram. Eu nunca mudei de endereço.")) % found],
			["Vicente", "Então alguém fez questão. Ou cê tá mentindo."],
			["Vicente", "Continua catando. O que eu tinha pra dizer tá ali."],
		])
	else:
		rows.append_array([
			["Vicente", "Achou todas. Até a da mesa de pedra."],
			["Dante", "Todas voltaram. Eu nunca mudei de endereço, Vicente."],
			["Vicente", "Então alguém fez questão. Isso eu vou querer saber quem."],
			["Vicente", "Se cê já viu o Coyote, sabe onde a gente vai conversar de verdade. Hoje não."],
		])
	rows.append_array([
		["Vicente", "A mãe perguntava de você até o fim."],
		["Dante", "E você dizia o quê?"],
		["Vicente", "Que cê tava ocupado. Prendendo gente."],
		["Dante", "Eu ia toda semana no fórum. Teu advogado nunca me deixou chegar perto."],
		["Vicente", "O Teodoro? Ele jurava que cê nunca apareceu."],
		["Dante", "Então um de nós ouviu mentira oito anos."],
		["Vicente", "Para. (levanta) Tem uma capela mais pra frente, na mesma estrada. Eu acendo vela lá."],
		["Vicente", "Vou na frente. Se quiser terminar, me acha lá."],
	])
	return rows

static func bia_lines() -> Array:
	return [
		["Bia", "Cê que é o irmão. O Vicente avisou."],
		["Dante", "Avisou o quê?"],
		["Bia", "\"Se ele aparecer, mostra a reta e não deixa ele se matar.\" Palavra por palavra."],
		["Bia", "Oitocentos metros. Relação curta sai forte e morre cedo. Turbo grande pede giro."],
		["Bia", "Espaço é marcha. Shift é nitro, guarda pro fim. Queimou a largada, vai pro fim da fila."],
		["Dante", "E o Digo?"],
		["Bia", "O Digo corre com todo mundo que chega. Ganhando ou perdendo, a oficina abre pra você depois."],
		["Bia", "Vai lá no quadro da concentração. Ele já tá te esperando."],
	]

static func grandstand_lines(won: bool, seconds: float) -> Array:
	var rows: Array = []
	if seconds > 0.0:
		# Vírgula decimal, como o Seu Zé escreve no caderno.
		rows.append(["Seu Zé do Cronômetro", String(TranslationServer.translate("Oitocentos em %s. Anotei, rapaz.")) % ("%.2f" % seconds).replace(".", ",")])
	else:
		rows.append(["Seu Zé do Cronômetro", "Anotei tua prova, rapaz."])
	rows.append_array([
		["Vicente", "Ele anota todo mundo. Antes de eu ser preso já anotava."],
		["Seu Zé do Cronômetro", "Teu irmão fazia essa reta num Coyote sem nitro. Largava igualzinho: segurando o giro até doer."],
		["Vicente", "Ganhou do Digo. Ele vai falar disso uma semana." if won else "Perdeu pro Digo. Pelo menos devolveu o carro inteiro."],
		["Dante", "Cê ficou olhando de longe."],
		["Vicente", "Queria ver se cê corria pra ganhar ou pra provar alguma coisa."],
		["Dante", "E aí?"],
		["Vicente", "Sei lá."],
		["Vicente", "Eu corria aqui pra pagar o Teodoro. Cada largada, um mês de advogado. Quando me prenderam o dinheiro já tinha acabado."],
		["Dante", "E agora cê corre pra pagar quem?"],
		["Vicente", "(olha pra ele um tempo) O Raul tem um papel que não é dele. Pergunta pro velho no Miragem."],
	])
	return rows

# A2-03 "Peso morto": Raul, o caixote, a Fiscal Rosa. A carga que passou na balança pesava duas
# toneladas menos que a apreendida. Dante já sabe das Salinas pela Vértice (M06-C).
static func raul_start_lines() -> Array:
	return [
		["Raul", "O Vicente te mandou? Ele não manda ninguém em lugar nenhum. Deve gostar de você."],
		["Dante", "Disse que cê tem um papel que não é seu."],
		["Raul", "Semana passada parou um bitrem dos Cobras pra abastecer. Saiu correndo. Deixou um caixote no pátio."],
		["Raul", "Ninguém voltou. Trinta anos de estrada, filho: carga que ninguém volta pra buscar não devia existir."],
		["Dante", "Cê abriu?"],
		["Raul", "Eu tenho neto. Tá do lado das bombas, coberto. Abre você."],
		["Raul", "Se tiver lacre, leva pra Rosa, na Balança. Ela pesa caminhão nessa estrada desde antes de cê usar farda."],
	]

static func crate_lines() -> Array:
	return [
		["Dante", "Lacre de chumbo. Número da salina, raspado no fim."],
		["Dante", "Igual ao da apreensão. Eu assinei o auto com um desses na mão."],
		["Dante", "Manifesto. Código dos Cobras. Pagamento pelo Cobre."],
		["Dante", "Dois dias antes da operação."],
	]

static func rosa_lines() -> Array:
	return [
		["Fiscal Rosa", "Lacre da salina. Faz tempo que eu não vejo um desses."],
		["Dante", "Desde quando?"],
		["Fiscal Rosa", "Desde aquela confusão. O rapaz das corridas. O caminhão dele passou aqui na noite da operação."],
		["Fiscal Rosa", "Eu mesma pesei. Vinte toneladas."],
		["Dante", "A apreensão diz vinte e duas."],
		["Fiscal Rosa", "Eu sei o que a apreensão diz. (abre o livro) E sei o que a minha balança disse."],
		["Fiscal Rosa", "Ninguém da polícia veio perguntar. Nem o advogado dele."],
		["Dante", "Alguém mexeu na carga depois daqui."],
		["Fiscal Rosa", "Isso cê que vai dizer, não eu. A página eu copio. E se precisar de mim no fórum, eu vou."],
	]

static func raul_end_lines() -> Array:
	return [
		["Raul", "Abriu. Tá na tua cara."],
		["Dante", "O caminhão do Vicente pesou duas toneladas a menos do que diz a apreensão."],
		["Raul", "Então o menino carregou uma coisa e prenderam ele com outra."],
		["Raul", "Toma. O posto me pagou pra guardar o caixote. Não quero esse dinheiro."],
		["Raul", "O manifesto tem número do Cobre. A Irene lê isso melhor que eu."],
		["Raul", "E, Dante. O Vicente não pode saber disso pela boca de outro. Quando tiver certeza, fala você."],
	]

# A2-04 "A ordem alterada": a primeira pista de quem armou. A Irene não pode ir além do balcão; quem lê
# o registro à noite é a Helena, que voltou para Santa Lua e faz as contas da cooperativa.
static func irene_bank_lines() -> Array:
	return [
		["Irene", "Essa transferência é nossa. (vira a tela pra si) Paga dois dias antes da apreensão."],
		["Dante", "E a ordem de frete?"],
		["Irene", "Saiu sem motorista. O nome entrou depois."],
		["Dante", "Vicente Ferraz."],
		["Irene", "Daqui eu não passo. Tem câmera, tem gerente regional."],
		["Irene", "Mas tem uma moça de Harbor fazendo as contas da cooperativa. Conhece esse sistema melhor que eu."],
		["Irene", "Ela busca o extrato da cooperativa depois das oito. Pela porta dos fundos."],
	]

static func irene_night_lines() -> Array:
	return [
		["Helena", "Você não sabe mesmo ficar quieto."],
		["Dante", "Helena."],
		["Helena", "A Irene me ligou. Disse que tinha um homem de Harbor fazendo pergunta errada."],
		["Helena", "(entrega uma folha) A ordem original e a alteração. Olha o campo de autorização."],
		["Dante", "Zero, quatro, um, sete."],
		["Helena", "Eu vi esse número cinco anos seguidos. Na conta dos Cobras, em Harbor."],
		["Dante", "Isso é matrícula de polícia."],
		["Helena", "Do mesmo formato da sua?"],
		["Dante", "(silêncio)"],
		["Helena", "Vai embora antes que alguém veja a gente. (vira, para) Santa Lua tem um rádio só. Se você aparecer, todo mundo vai saber."],
	]

static func phone_lines() -> Array:
	return [
		["Maciota", "Dante? Essa hora? Aconteceu alguma coisa com o Vicente?"],
		["Dante", "Ele tá bem. Preciso saber de quem é uma matrícula. Zero, quatro, um, sete."],
		["Maciota", "Matrícula de polícia? Dante, isso faz barulho."],
		["Dante", "Foi ela que pôs o Vicente no caminhão."],
		["Maciota", "(suspira) Conheço gente que conhece gente. Vai demorar."],
		["Maciota", "E a moça do banco? A Helena tá aí?"],
		["Dante", "Por que?"],
		["Maciota", "Nada. Cê respondeu rápido demais, só isso."],
		["Maciota", "E fala com teu irmão logo. Oito anos já foi tempo de sobra pra ele achar que cê escondia coisa."],
	]

static func chapel_lines() -> Array:
	return [
		["Vicente", "Eu não sei mais rezar. Só sento e fico olhando a vela."],
		["Dante", "A mãe rezava por nós dois."],
		["Vicente", "Por você mais. Dizia que quem prende os outros precisa de mais proteção."],
		["Vicente", "Lá dentro caía um depósito todo mês na minha conta da cantina. Sem nome. Eu sabia de quem era."],
		["Vicente", "Não gastei. Mil e quinhentos. Tá aqui."],
		["Dante", "Não era dívida."],
		["Vicente", "Pra mim era. Pega. Pronto, agora não é mais."],
		["Vicente", "Quer ficar no deserto? Fica. Mas aqui cê é piloto, não polícia."],
		["Vicente", "Corre com o Digo na reta. Ganha, perde, tanto faz. Mostra que respeita a pista. Depois a gente fala daquela noite."],
		["Dante", "E se eu provar que armaram pra você?"],
		["Vicente", "Então prova. Promessa eu já ouvi demais."],
	]

## Cobras do ataque final: mesmos agentes dos foras-da-lei (DesertWilds.Outlaw), sempre engajados.
class Raider extends "res://gameplay/CobraAgent.gd":
	func _ready() -> void:
		super._ready()
		add_to_group("act2_raiders")
		set_meta("region_id", "desert")
		set_meta("character_name", "Cobra")

## Vicente na briga do motel (A2-12): apanha, cambaleia e cai sentado antes de morrer; nunca morre.
## Anda na direção de Dante para trocar socos (a mesma física de chão do DesertCharacter).
class BrotherFighter extends "res://runtime/desert/DesertCharacter.gd":
	const DOWN_AT := 35.0
	const SPEED := 2.4
	var down := false
	var _push := Vector3.ZERO

	func chase(offset: Vector3) -> void:
		if down: return
		_push = offset.normalized() * SPEED if offset.length() > 1.2 else Vector3.ZERO
		if is_instance_valid(visual) and offset.length() > .1: visual.rotation.y = atan2(offset.x, offset.z)

	func _physics_process(delta: float) -> void:
		velocity = Vector3(_push.x, maxf(-20.0, velocity.y - 18.0 * delta), _push.z)
		move_and_slide()

	func receive_damage(amount: float, _source: Node = null) -> void:
		if down or not is_finite(amount) or amount <= 0: return
		health = maxf(DOWN_AT, health - amount)
		if is_instance_valid(visual) and visual.has_method("take_hit"): visual.take_hit(Vector3.ZERO, clampf(amount / 35.0, .3, 1.0))
		if health <= DOWN_AT:
			down = true
			_push = Vector3.ZERO
			set_talking(false)
