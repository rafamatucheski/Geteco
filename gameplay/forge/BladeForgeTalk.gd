extends RefCounted
## Conversas e menu da pista da Forja da Serra. Sem estado próprio: o estágio fica em
## `world_state.blade_forge` (BladeForge) e os níveis em `Gameplay.customization`.
const FORGE := preload("res://gameplay/forge/BladeForge.gd")

static func perform(session, action: Dictionary) -> bool:
	var resident: Node = action.get("provider")
	if not is_instance_valid(resident) or resident.nearest_action().is_empty(): return false
	var quest: Dictionary = FORGE.quest(session.state.world_state)
	match str(action.get("target", "")):
		"smith": _smith(session, resident, quest)
		"hermit": _hermit(session, resident, quest)
		"miner": _miner(session, resident, quest)
		_: return false
	return true

static func _say(session, resident: Node, lines: Array, done := Callable()) -> void:
	resident.set_talking(true)
	session.show_dialogue(lines, func():
		if is_instance_valid(resident): resident.set_talking(false)
		if done.is_valid(): done.call())

static func _advance(session, quest: Dictionary, stage: String, notice: String) -> void:
	if FORGE.stage_index(stage) <= FORGE.stage_index(str(quest.stage)): return
	quest.stage = stage
	session.show_message(notice)
	session.save_game()

static func _smith(session, resident: Node, quest: Dictionary) -> void:
	match str(quest.stage):
		"unknown":
			_say(session, resident, [
				{"speaker":"Seu Bento", "message":"Pode chegar, a fornalha não morde. Eu às vezes."},
				{"speaker":"Dante", "message":"Disseram que aqui se conserta lâmina."},
				{"speaker":"Seu Bento", "message":"Conserto não, melhoro. Faca, machado, até katana: eu afio pra pesar mais no golpe e tempero pra ficar ligeira na mão."},
			], func():
				_advance(session, quest, "met", "Forja da Serra: melhorias de faca, machado e katana.")
				open_menu(session, resident))
		"has_ore":
			_say(session, resident, [
				{"speaker":"Seu Bento", "message":"Isso aí é... o minério negro do Tião. O mestre confiou em você, então."},
				{"speaker":"Dante", "message":"Ele disse que você bate torto."},
				{"speaker":"Seu Bento", "message":"Ele diz isso desde que eu tinha doze anos. Agora dá pra fazer o fio lendário: afiação e têmpera no máximo antes, e aço desses não sai barato."},
			], func():
				_advance(session, quest, "done", "Aço lendário liberado na Forja da Serra.")
				open_menu(session, resident))
		_: open_menu(session, resident)

static func _clue(session, resident: Node, quest: Dictionary) -> void:
	_say(session, resident, [
		{"speaker":"Seu Bento", "message":"Lâmina lendária? Isso eu não sei fazer. Quem sabia era o Mestre Aurélio, que me ensinou o ofício."},
		{"speaker":"Dante", "message":"E onde eu acho esse mestre?"},
		{"speaker":"Seu Bento", "message":"Largou a vila faz anos. Vive sozinho numa cabana lá no norte da serra, depois das pistas de esqui. Leva roupa quente, que lá o frio mata e urso não pede licença."},
	], func(): _advance(session, quest, "seek_hermit", "Novo local no mapa: Cabana do Mestre Aurélio."))

static func _hermit(session, resident: Node, quest: Dictionary) -> void:
	match str(quest.stage):
		"unknown", "met":
			_say(session, resident, [
				{"speaker":"Mestre Aurélio", "message":"Pouca gente sobe até aqui. Quem sobe, ou está perdido ou está fugindo."},
				{"speaker":"Mestre Aurélio", "message":"Se quer conversar sobre aço, fala primeiro com o Bento, lá na forja. Eu já larguei o martelo."},
			])
		"seek_hermit":
			var lines := [
				{"speaker":"Mestre Aurélio", "message":"O Bento te mandou? Aquele menino ainda bate torto."},
				{"speaker":"Mestre Aurélio", "message":"A têmpera eu ensino pra ele de novo. Mas aço que segura um fio desses não sai de ferro de loja."},
				{"speaker":"Mestre Aurélio", "message":"Lá no deserto, na mineração, mora um velho chamado Tião. Ele guarda um minério negro que tirou do fundo da cava. Diz que fui eu que mandei."},
			]
			if not _desert_open(session):
				lines.append({"speaker":"Mestre Aurélio", "message":"A estrada pro deserto só abre quando você acertar as contas na cidade. O minério espera, ele espera há vinte anos."})
			_say(session, resident, lines, func(): _advance(session, quest, "seek_miner", "Novo local no mapa: acampamento do Tião, na Mineração do deserto."))
		"seek_miner":
			_say(session, resident, [{"speaker":"Mestre Aurélio", "message":"O Tião fica do lado da estrada da mineração, no deserto. Vai, que o frio aqui não ajuda conversa comprida."}])
		"has_ore":
			_say(session, resident, [{"speaker":"Mestre Aurélio", "message":"Esse é o minério. Leva pro Bento antes que eu mude de ideia."}])
		_:
			_say(session, resident, [{"speaker":"Mestre Aurélio", "message":"Cuida bem dessa lâmina. Aço bom guarda a mão de quem fez."}])

static func _miner(session, resident: Node, quest: Dictionary) -> void:
	match str(quest.stage):
		"seek_miner":
			_say(session, resident, [
				{"speaker":"Tião", "message":"Aurélio? Achei que o frio já tinha levado aquele teimoso."},
				{"speaker":"Tião", "message":"Esse minério eu guardo há vinte anos. Tirei do fundo da cava antes de fecharem o veio. Ninguém mais sabe trabalhar ele."},
				{"speaker":"Tião", "message":"Leva. Mas fala pro ferreiro que, se estragar, eu subo a serra pra buscar de volta."},
			], func(): _advance(session, quest, "has_ore", "Minério negro recebido. Leve à Forja da Serra."))
		"has_ore", "done":
			_say(session, resident, [{"speaker":"Tião", "message":"Já te dei o que eu tinha de bom. O resto da cava é carvão e poeira."}])
		_:
			_say(session, resident, [{"speaker":"Tião", "message":"Procurando alguma coisa, moço? A cava é perigosa e o sol aqui não perdoa."}])

static func _desert_open(session) -> bool:
	return preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(session.state.campaign.snapshot())

static func open_menu(session, resident: Node) -> void:
	var gameplay = session.world.gameplay
	var quest: Dictionary = FORGE.quest(session.state.world_state)
	session._menu("Forja da Serra · Seu Bento")
	var owned := 0
	for id in FORGE.BLADES:
		if not session.state.owns_weapon(id): continue
		owned += 1
		var tracks: Array = FORGE.TRACKS.duplicate()
		if str(quest.stage) == "done": tracks.append("legendary")
		for track in tracks:
			var offer: Dictionary = FORGE.offer(gameplay.customization, str(quest.stage), id, track)
			session._button(_label(gameplay.customization, id, track, offer), func(): _buy(session, resident, id, track))
	if owned == 0:
		session._button("Traga uma faca, um machado ou a katana", session.close_menu)
	match str(quest.stage):
		"met": session._button("Perguntar sobre aço lendário", func(): _clue(session, resident, quest))
		"seek_hermit": session._button("Aço lendário: procure o Mestre Aurélio, no norte da serra", session.close_menu)
		"seek_miner": session._button("Aço lendário: busque o minério do Tião, no deserto", session.close_menu)
	session._button("Sair", session.close_menu)

static func _label(customization: Dictionary, id: String, track: String, offer: Dictionary) -> String:
	var blade: String = FORGE.LABELS[id]
	if track == "legendary":
		if FORGE.legendary(customization, id): return "%s · Lendária ✓" % blade
		if not offer.ok: return "%s · Lendária — %s" % [blade, offer.reason]
		return "%s · Lendária (+25%% dano, golpe mais rápido) · $%d" % [blade, int(offer.price)]
	var current := FORGE.level(customization, id, track)
	var title: String = FORGE.TRACK_LABELS[track]
	if not offer.ok: return "%s · %s %d/%d — máximo" % [blade, title, current, FORGE.MAX_LEVEL]
	var effect := "+12% dano" if track == "edge" else "golpe 8% mais rápido"
	return "%s · %s %d/%d → %d (%s) · $%d" % [blade, title, current, FORGE.MAX_LEVEL, int(offer.level), effect, int(offer.price)]

static func _buy(session, resident: Node, id: String, track: String) -> void:
	var quest: Dictionary = FORGE.quest(session.state.world_state)
	var result: Dictionary = session.world.gameplay.buy_forge_upgrade(id, track, str(quest.stage))
	if not result.ok:
		session.show_message(str(result.reason))
	else:
		var blade: String = FORGE.LABELS[id]
		if track == "legendary": session.show_message("%s lendária · aço negro com fio aceso" % blade)
		else: session.show_message("%s · %s nível %d" % [blade, FORGE.TRACK_LABELS[track], int(result.level)])
		session.save_game()
	# O menu aberto deixa a sessão modal (nearest_action fica vazio): confere só o alcance.
	if is_instance_valid(resident) and resident.in_reach(): open_menu(session, resident)
	else: session.close_menu()
