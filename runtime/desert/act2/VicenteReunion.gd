extends Node3D
## Ato 2, missão A2-01 "Oito anos": o reencontro de Dante com Vicente em três lugares.
##   1. Encontro da arrancada: Vicente recebe Dante na frente da turma e marca o Motel Oásis.
##   2. Motel Oásis (Estrada do Sal): a conversa a sós; as cartas, a mãe, o advogado.
##   3. Capela da Estrada: a vela, o envelope com o dinheiro dos oito anos e as condições dele.
## O Vicente do encontro é o ator de DesertCampaign (some de lá enquanto a missão está no motel ou
## na capela); nos outros dois lugares este nó monta um ator próprio, só perto e com o lugar da
## Estrada do Sal já montado, e o devolve ao se afastar. Diálogos só em legenda (sem voz gravada).
## Também conduz A2-02 "Respeita a pista": a conversa da Bia (pelo contato dela no DesertCampaign), a
## corrida com o Digo (a arrancada que já existe) e Vicente na Arquibancada da reta.
const STATE := preload("res://runtime/desert/act2/VicenteAct2State.gd")
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const CONTACT := preload("res://runtime/desert/DesertCharacter.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const RACE := preload("res://activities/desert_drag/DesertDragProgress.gd")
const TITLE := "Oito anos"
const TRACK_TITLE := "Respeita a pista"
## Onde Vicente espera em cada etapa: lugar da Estrada do Sal e pontos locais candidatos (o primeiro
## livre vale). Motel: calçada sob a marquise, na frente da porta do quarto 6 (fora das colunas,
## da lixeira e da máquina de gelo). Capela: no terreiro, ao lado do caminho de pedra, longe da
## zeladora (que atende a vela a 2,4 m dela).
const SPOTS := {
	"motel": {"site": "motel", "points": [Vector3(2.6, 0, 1.0), Vector3(-1.6, 0, 1.0), Vector3(-1.0, 0, 4.2)], "face": Vector3(0, 0, 6)},
	"chapel": {"site": "chapel", "points": [Vector3(-2.6, 0, 3.8), Vector3(-2.4, 0, 6.0), Vector3(2.4, 0, 6.4)], "face": Vector3(0, 0, -1)},
	# Na frente do guarda-corpo (sólido em z 4), olhando a reta; a mais de 2,4 m do Seu Zé (18,3; 3),
	# que tem a ação dele na beira de estrada e vem antes na ordem das ações.
	"grandstand": {"site": "grandstand", "points": [Vector3(13.0, 0, 5.5), Vector3(10.0, 0, 5.5), Vector3(13.0, 0, 7.0)], "face": Vector3(13.0, 0, 30.0)},
}
const SPAWN_DISTANCE := 85.0
const RELEASE_DISTANCE := 120.0
const TALK_DISTANCE := 1.8
var session
var actor: CharacterBody3D
var _actor_stage := ""
var _clock := 0.0

func configure(owner_session) -> void:
	session = owner_session
	name = "VicenteReunion"
	session.world.gameplay.player_died.connect(_release)

func stage() -> String:
	return STATE.stage(session.state.world_state)

## Cena em que Vicente espera fora do encontro: etapa de A2-01 ou a Arquibancada de A2-02.
func scene() -> String:
	return scene_for(session.state.world_state)

static func scene_for(world: Dictionary) -> String:
	var current := STATE.stage(world)
	if current in ["motel", "chapel"]: return current
	if STATE.track_stage(world) == "grandstand": return "grandstand"
	return ""

## DesertCampaign tira o Vicente do encontro enquanto ele espera em outro lugar.
func away_from_meet() -> bool:
	return not scene().is_empty()

func _process(delta: float) -> void:
	_clock += delta
	if _clock < .3 or session == null or not session.ready_for_play: return
	_clock = 0.0
	var current := scene()
	var outside: bool = session.state.region_id == "desert" and session.state.place_id.is_empty() and session.world.gameplay.health > 0
	if not outside or not SPOTS.has(current):
		_release()
		return
	if is_instance_valid(actor) and _actor_stage != current: _release()
	var player: Vector3 = session.world.player.global_position
	var anchor := _site_point(current, Vector3.ZERO)
	var distance := Vector2(player.x, player.z).distance_to(Vector2(anchor.x, anchor.z))
	if is_instance_valid(actor):
		if distance > RELEASE_DISTANCE: _release()
		else: _face(current)
		return
	if distance < SPAWN_DISTANCE and _site_ready(current): _admit(current)

## Lugar montado pela beira de estrada (sem ele, só o chão do deserto: interruptor A/B desligado).
func _site_ready(current: String) -> bool:
	var region: Node3D = session.controller.regions.get("desert")
	if not is_instance_valid(region) or not region.surfaces_idle(): return false
	if not ROADSIDE.enabled(): return true
	var frontier = session.desert.frontier if session.desert != null else null
	if frontier == null or not is_instance_valid(frontier.roadside): return false
	var record: Dictionary = frontier.roadside.sites.get(str(SPOTS[current].site), {})
	return not record.is_empty() and not bool(record.parked)

func _site_point(current: String, local: Vector3) -> Vector3:
	var definition := ROADSIDE.site(str(SPOTS[current].site))
	var center: Vector2 = definition.center
	return ROADSIDE.at(definition, local, HM.surface_height(center))

func _admit(current: String) -> void:
	session.controller.region.prepare_collision_at(_site_point(current, Vector3.ZERO))
	for local: Vector3 in SPOTS[current].points:
		var guess := _site_point(current, local)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(guess + Vector3.UP * 2.0, guess - Vector3.UP * 2.0, 1))
		if hit.is_empty() or float(hit.normal.y) < .9: continue
		var point: Vector3 = hit.position + Vector3.UP * .05
		if not session.position_clear(point): continue
		actor = CONTACT.new()
		actor.identity_id = "vicente"
		actor.position = point
		add_child(actor)
		# Fora do grupo da turma do encontro: aqui ele está sozinho (o teste do encontro conta a turma).
		actor.remove_from_group("desert_drag_crew")
		actor.set_meta("act2_reunion", current)
		_actor_stage = current
		_face(current)
		return

func _face(current: String) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.visual): return
	var talking: bool = session.modal and session.dialogue_open
	var target: Vector3 = session.world.player.global_position if talking else _site_point(current, SPOTS[current].face)
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
	if not _available() or not is_instance_valid(actor) or actor.dead: return {}
	if session.world.player.global_position.distance_to(actor.global_position) > TALK_DISTANCE: return {}
	return {"id": "desert_story", "target": "vicente_reunion", "label": "Conversar com Vicente"}

func perform(target: String) -> bool:
	if target != "vicente_reunion" or nearest_action().is_empty(): return false
	match _actor_stage:
		"motel": _say(motel_lines(session.state.economy.snapshot().collectibles), "chapel")
		"chapel": _say(chapel_lines(), "done")
		"grandstand":
			var race: Dictionary = RACE.data(session.state.world_state)
			_say(grandstand_lines("digo" in race.wins, float(race.best.get("digo", 0.0))), "track_done")
		_: return false
	return true

## A2-02, primeira etapa: a conversa da Bia (DesertCampaign chama pelo "Conversar" dela).
func bia() -> bool:
	if not STATE.complete(session.state.world_state) or STATE.track_stage(session.state.world_state) != "": return false
	session.show_message("Ato 2 · " + TRACK_TITLE)
	_say(bia_lines(), "race")
	return true

## Primeira etapa, chamada pelo DesertCampaign ao falar com o Vicente do encontro.
func meet() -> bool:
	if stage() != "": return false
	session.show_message("Ato 2 · " + TITLE)
	_say(meet_lines(), "motel")
	return true

func _say(rows: Array, next_stage: String) -> void:
	var lines: Array = []
	for row in rows: lines.append({"speaker": row[0], "message": row[1]})
	session.show_dialogue(lines, func(): _finish_step(next_stage))

## Fim de um diálogo: só conta se Dante continua vivo, solto e no deserto.
func _finish_step(next_stage: String) -> void:
	if session.world.gameplay.health <= 0 or session.arrest_pending or session.rescue_pending or session.state.region_id != "desert": return
	var world: Dictionary = session.state.world_state
	if next_stage == "race":
		if not STATE.track_advance(world, "race"): return
	elif next_stage == "track_done":
		if not STATE.track_advance(world, "done"): return
		REWARD_AUDIO.play(session, "collectible")
		session.show_message(String(TranslationServer.translate("%s concluída")) % String(TranslationServer.translate(TRACK_TITLE)))
	elif next_stage == "done":
		# Paga antes de marcar (carteira cheia não marca), então confere a etapa antes de pagar.
		if stage() != "chapel": return
		var paid: Dictionary = session.state.economy.grant_world_reward({"id": STATE.ENVELOPE_RECEIPT, "kind": "cash", "amount": STATE.ENVELOPE_AMOUNT})
		if not paid.ok:
			# Carteira cheia: a missão espera na capela, e a próxima conversa tenta de novo.
			session.show_message("Libere espaço na carteira para receber o envelope de Vicente.")
			return
		if not STATE.advance(world, "done"): return
		STORY.mark(world, "met_vicente")
		REWARD_AUDIO.play(session, "collectible")
		session.show_message(String(TranslationServer.translate("%s concluída · + R$ %d")) % [String(TranslationServer.translate(TITLE)), STATE.ENVELOPE_AMOUNT])
	elif not STATE.advance(world, next_stage): return
	session.save_game()

func objective() -> String:
	return objective_for(session.state.world_state)

static func objective_for(world: Dictionary) -> String:
	match STATE.stage(world):
		"motel": return "Vá ao Motel Oásis, na Estrada do Sal, e fale com Vicente."
		"chapel": return "Encontre Vicente na Capela da Estrada."
	if not STATE.complete(world): return ""
	match STATE.track_stage(world):
		"": return "Fale com Bia no pátio do Digo."
		"race": return "Corra contra Digo na reta: quadro da concentração."
		"grandstand": return "Encontre Vicente na Arquibancada da reta."
	return ""

func target_position() -> Vector3:
	var current := scene()
	if not SPOTS.has(current): return Vector3.INF
	if is_instance_valid(actor): return actor.global_position
	return _site_point(current, SPOTS[current].points[0])

# --- Falas --------------------------------------------------------------------------------------
# Vicente lê os oito anos como abandono e não sabe da armação; nada aqui conta quem armou. Duas
# sementes ficam plantadas para as missões seguintes (roteiro, A2-04 e A2-07): as cartas voltaram
# com "destinatário desconhecido" para um endereço que nunca mudou, e o advogado dizia a Vicente que
# Dante nunca aparecia.

static func meet_lines() -> Array:
	return [
		["Vicente", "Olha só. A turma inteira parou pra ver. Dante Ferraz no meu encontro."],
		["Dante", "Vicente."],
		["Vicente", "Oito anos, Dante. Oito. Agora você aparece?"],
		["Dante", "Eu tentei reabrir o caso. Pedi o processo de volta. Saí da polícia quando achei os primeiros indícios."],
		["Vicente", "Indícios. Sabe o que eu tinha lá dentro? Uma parede e um prego pra riscar os dias."],
		["Dante", "Eu sei que isso não devolve nada."],
		["Vicente", "Aqui ninguém resolve nada na bala. Nem no distintivo. Essa turma é minha, e você é só mais um carro na fila."],
		["Vicente", "Não vou fazer isso na frente deles. Motel Oásis, na Estrada do Sal. Quarto 6."],
		["Vicente", "Se ainda souber chegar sem sirene."],
	]

static func motel_lines(collectibles: Array) -> Array:
	var found := LETTERS.found(collectibles)
	var rows: Array = [
		["Vicente", "Veio sozinho. Pelo menos isso."],
		["Dante", "Foi aqui que você ficou quando saiu?"],
		["Vicente", "Primeira noite livre. Luz acesa e porta aberta a noite inteira. A Dona Lurdes achou que eu ia fugir sem pagar."],
	]
	if found == 0:
		rows.append_array([
			["Vicente", "Eu escrevi pra você. Dez cartas. Voltaram todas com carimbo: destinatário desconhecido."],
			["Dante", "Nunca chegou carta nenhuma, Vicente. Eu morei no mesmo endereço esses oito anos."],
			["Vicente", "Então alguém achou que você não devia ler. Ou você está mentindo de novo."],
			["Vicente", "Eu deixei as cartas pelo caminho que eu fiz. Harbor, a serra, aqui. Se quiser saber o que eu pensei lá dentro, vai ter que buscar."],
		])
	elif found < LETTERS.IDS.size():
		rows.append_array([
			["Vicente", "O Maciota disse que você anda achando umas cartas minhas por aí."],
			["Dante", String(TranslationServer.translate("Achei %d. Todas com carimbo de destinatário desconhecido. Eu morei no mesmo endereço esses oito anos.")) % found],
			["Vicente", "Então alguém fez questão que você não lesse. Ou você está mentindo de novo."],
			["Vicente", "Continua procurando. O que eu tinha pra dizer está tudo ali."],
		])
	else:
		rows.append_array([
			["Vicente", "Você achou todas. Até a da mesa de pedra."],
			["Dante", "Todas com carimbo de destinatário desconhecido. Eu morei no mesmo endereço esses oito anos, Vicente."],
			["Vicente", "Então alguém fez questão que você não lesse. Isso eu vou querer entender."],
			["Vicente", "Se você já viu o Coyote, sabe onde a gente vai conversar de verdade. Mas não hoje."],
		])
	rows.append_array([
		["Vicente", "A mãe perguntava de você até o fim. Eu dizia que você estava ocupado prendendo gente."],
		["Dante", "Eu ia toda semana ao fórum. O seu advogado não me deixava chegar perto do processo."],
		["Vicente", "O Teodoro? Ele jurava que você nunca apareceu."],
		["Dante", "Então um de nós dois ouviu mentira por oito anos."],
		["Vicente", "Não começa. Tem uma capela mais pra leste, na mesma estrada. Eu acendo uma vela lá toda semana."],
		["Vicente", "Vou na frente. Se quiser terminar essa conversa, me encontra lá."],
	])
	return rows

static func bia_lines() -> Array:
	return [
		["Bia", "Então você é o irmão. O Vicente avisou que você ia aparecer por aqui."],
		["Dante", "Avisou como?"],
		["Bia", "\"Se ele vier, mostra a reta pra ele e não deixa ele se matar.\" Palavras dele."],
		["Bia", "Aqui a prova é de oitocentos metros. Relação curta sai forte e acaba cedo; turbo grande pede giro. O carro tem que durar a reta inteira."],
		["Bia", "Espaço troca a marcha. Shift é o nitro: guarda pro fim. Queimou a largada, volta pro fim da fila."],
		["Dante", "E o Digo?"],
		["Bia", "O Digo corre com todo mundo que chega. Ganhando ou perdendo, depois dele a oficina fica aberta pra você."],
		["Bia", "Vai na concentração da largada e olha o quadro. Ele já está esperando."],
	]

static func grandstand_lines(won: bool, seconds: float) -> Array:
	var rows: Array = []
	if seconds > 0.0:
		# Vírgula decimal, como o Seu Zé escreve no caderno.
		rows.append(["Seu Zé do Cronômetro", String(TranslationServer.translate("Oitocentos metros em %s segundos. Anotei no caderno, rapaz.")) % ("%.2f" % seconds).replace(".", ",")])
	else:
		rows.append(["Seu Zé do Cronômetro", "Anotei a tua prova no caderno, rapaz."])
	rows.append_array([
		["Vicente", "Ele anota todo mundo. Desde antes de eu ser preso."],
		["Seu Zé do Cronômetro", "Teu irmão fazia essa reta num Coyote sem nitro. Largava igualzinho a você: segurando o giro até o último segundo."],
		["Vicente", "Ganhou do Digo. Ele vai passar uma semana falando disso." if won else "Perdeu pro Digo. Pelo menos devolveu a pista inteira."],
		["Dante", "Você ficou olhando de longe."],
		["Vicente", "Fiquei. Queria ver se você corria pra ganhar ou pra provar alguma coisa."],
		["Dante", "E aí?"],
		["Vicente", "Ainda não sei."],
		["Vicente", "Eu corria aqui pra pagar o Teodoro. Cada largada era um mês de advogado. Quando me prenderam, o dinheiro já tinha acabado fazia tempo."],
		["Dante", "Você pagava o advogado com corrida?"],
		["Vicente", "Com o que mais? Polícia não empresta dinheiro pra irmão de preso."],
		["Vicente", "Se quer mexer no passado, o Raul tem um papel que não é dele. Pergunta pro velho no posto Miragem."],
	])
	return rows

static func chapel_lines() -> Array:
	return [
		["Vicente", "Eu não sei mais rezar. Só sento aqui e fico olhando a vela."],
		["Dante", "A mãe rezava por nós dois."],
		["Vicente", "Por você mais. Dizia que quem prende os outros precisa de mais proteção."],
		["Vicente", "Quando eu estava lá dentro, caía um depósito todo mês na minha conta da cantina. Sem nome. Eu sabia de quem era."],
		["Vicente", "Não gastei. Mil e quinhentos. Está tudo aqui, no envelope."],
		["Dante", "Não era dívida, Vicente."],
		["Vicente", "Pra mim era. Pega. Agora não é mais."],
		["Vicente", "Quer ficar no deserto? Fica. Mas aqui você é piloto, não policial."],
		["Vicente", "Corre com o Digo na reta. Ganhando ou perdendo, mostra que respeita a pista. Depois a gente fala daquela noite."],
		["Dante", "E se eu provar que alguém armou aquilo pra você?"],
		["Vicente", "Então prova. Promessa eu já ouvi demais."],
	]
