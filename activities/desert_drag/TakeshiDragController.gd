extends Node
## Optional honor duel. The championship keeps its six ordinary opponents.
const HONOR := preload("res://runtime/TakeshiHonor.gd")
const INTRO := "Um carro bonito não vence uma arrancada, Dante. Motor, sangue-frio e a troca certa. Mostre que sabe usar os três."
const VICTORY := "Pela honra, eu te subestimei. Você pode escolher o meu carro ou o tesouro da minha família."
var race: Node3D
var session
var result: Dictionary = {}
var choosing := false

func configure(owner_race: Node3D) -> void:
	race = owner_race
	session = race.session

func available() -> bool:
	return not race.active and session.ready_for_play and not session.controller.save_invalid and not session.is_transition_blocked() and session.world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending

func open() -> bool:
	if not available() or session.modal: return false
	if HONOR.pending_reward(session.state.world_state):
		_open_reward()
		return true
	session._menu("Takeshi")
	_label("Toyota Supra A80 · 800 m",24)
	_label("Prepare o carro para competir no limite. Largada, trocas e nitro decidem esta prova.",20)
	var saved := HONOR.data(session.state.world_state)
	if float(saved.best_seconds)>0: _label("Seu recorde: %.3f s"%float(saved.best_seconds),20)
	session._button("Revanche" if saved.won else "Desafiar Takeshi",_request_race)
	session._button("Voltar",session.close_menu)
	return true

func _request_race() -> void:
	if not available() or not session.modal: return
	session.close_menu()
	var reason: String = race.start_block_reason()
	if not reason.is_empty():
		if open(): _label(reason,18)
		return
	if not race.start_rival("takeshi"):
		if open(): _label("Aguarde a pista ficar livre e tente novamente.",18)

func completed(value: Dictionary) -> void:
	result = value.duplicate(true)
	if not available() or session.modal or not value.get("finished",false): return
	if HONOR.pending_reward(session.state.world_state):
		session.show_dialogue([{"speaker":"Takeshi","message":VICTORY}],_open_reward)
	else:
		var words := "Você ganhou. A palavra de Takeshi continua valendo." if value.get("won",false) else "Quase não basta, Dante. Acerte o carro e aprenda a ouvir o motor. Eu continuo aqui."
		session.show_dialogue([{"speaker":"Takeshi","message":words}],_show_result)

func _open_reward() -> void:
	if not available() or not HONOR.pending_reward(session.state.world_state): return
	session._menu("A palavra de Takeshi")
	_label("Escolha uma recompensa",25)
	_label("Toyota Supra A80",23)
	_label("O carro de Takeshi. A katana ficará disponível na Ammu-Nation por R$ 300.000.",19)
	session._button("Escolher o Supra",_claim.bind("car"))
	_label("Tesouro da família",23)
	_label("Katana: golpes exclusivos e RAGE. A escolha é definitiva.",19)
	session._button("Escolher a katana",_claim.bind("katana"))
	session._button("Decidir depois",_decide_later)

func _decide_later() -> void:
	session.close_menu()
	_show_result()

func _claim(choice: String) -> void:
	if choosing or not available() or not session.modal or not HONOR.pending_reward(session.state.world_state): return
	choosing = true
	var claimed: Dictionary = HONOR.claim(session,choice)
	choosing = false
	if not claimed.get("ok",false):
		_open_reward()
		_label(str(claimed.get("reason","Não foi possível entregar a recompensa. Tente novamente.")),18)
		return
	session.close_menu()
	var words := "Ele é seu. Cuide desse Supra como eu cuidei. Minha katana estará à venda na Ammu-Nation, se um dia a quiser." if choice=="car" else "Esta lâmina atravessou gerações da minha família. Agora a responsabilidade é sua, Dante."
	session.show_dialogue([{"speaker":"Takeshi","message":words}],_show_result)

func _show_result() -> void:
	if not available() or session.modal or result.is_empty(): return
	race.board_controller.show_takeshi_result(result)

func _label(value: String, point_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",point_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	session.column.add_child(label)
