extends Node
const MODEL := preload("res://gameplay/wine/WineState.gd")
const CATALOG := preload("res://gameplay/wine/WineCatalog.gd")
const PLACE := "harbor_curitiba_cellar"
var session
var model = MODEL.new()
var ui
var overlay
var phase := 0.0
var refresh_clock := 0.0
var opened_health := 100.0
var story_index := 0
var _effects_live := false

func configure(owner_session) -> void:
	name="WineRuntime"
	session=owner_session
	if session.state.world_state.has("wine_cellar"):
		if not model.restore_snapshot(session.state.world_state.wine_cellar): session.controller.save_invalid=true
	overlay=preload("res://gameplay/wine/WineOverlay.gd").new()
	session.world.hud.add_child(overlay)
	ui=preload("res://gameplay/wine/WinePanel.gd").new()
	ui.adapter=self
	session.world.hud.add_child(ui)
	_publish_effect()

func snapshot() -> Dictionary: return model.snapshot()
func get_intensity() -> float: return model.intensity()
func recover() -> void:
	model.recover()
	phase=0.0
	_publish_effect()
	if is_instance_valid(overlay): overlay.hide()

func _available() -> bool:
	return session!=null and session.ready_for_play and not session.get_tree().paused and session.world.gameplay.health>0 and not session.is_transition_blocked() and not session.world.driving.occupied

func _near(target: String) -> bool:
	if not _available() or session.state.place_id!=PLACE or not is_instance_valid(session.room): return false
	if session.has_method("_service_threatened") and session._service_threatened(): return false
	var key := "luisa" if target=="luisa" else "service"
	if not session.room.interaction_points.has(key): return false
	return session.world.player.global_position.distance_to(session.room.interaction_points[key])<1.85

func nearest_action() -> Dictionary:
	if session==null or session.modal: return {}
	if _near("luisa"): return {"id":"wine","target":"luisa","label":"Falar com Luísa"}
	if _near("nelson"): return {"id":"wine","target":"nelson","label":"Falar com Nelson"}
	return {}

func perform(target: String) -> bool:
	if not _near(target): return false
	if target=="luisa": talk_luisa()
	elif target=="nelson": open_shop()
	else: return false
	return true

func open_shop() -> void:
	if not _near("nelson"): return
	_open(true)
func open_bag() -> void:
	if not _available(): return
	_open(false)
func _open(shop: bool) -> void:
	session._menu("Curitiba Cellar" if shop else "Vinhos")
	session.panel.hide()
	session.menu_closed=dismiss
	opened_health=float(session.world.gameplay.health)
	ui.shop=shop
	ui.show()
	ui.refresh()
func dismiss() -> void:
	if is_instance_valid(ui): ui.hide()
func close() -> void: session.close_menu()

func buy(id: String) -> bool:
	if not _near("nelson"): return false
	var result: Dictionary=model.purchase(id,session.state.economy)
	if result.ok:
		session.save_game()
		_feedback("Garrafa guardada · 3 taças. Escolha Beber para consumir.")
	else: _feedback(reason_text(str(result.reason)))
	if ui.visible: ui.refresh()
	return bool(result.ok)

func drink(id: String) -> bool:
	if not _available(): return false
	var result: Dictionary=model.drink(id,float(session.world.gameplay.health))
	if not result.ok:
		_feedback(reason_text(str(result.reason)))
		if ui.visible: ui.refresh()
		return false
	if float(result.heal)>0.0: session.world.gameplay.heal(float(result.heal))
	session.state.equip_weapon("fists")
	_publish_effect()
	session.save_game()
	# Close the modal so the deliberate sip and its effect remain visible.
	if ui.visible: session.close_menu()
	var sip:=preload("res://gameplay/wine/WineSip.gd").new()
	sip.player=session.world.player
	sip.session=session
	sip.tint=CATALOG.spec(id).color
	session.world.add_child(sip)
	session.show_message("%s · +%d vida · %s"%[CATALOG.spec(id).name,roundi(float(result.heal)),model.stage()])
	return true

func claim_gift() -> bool:
	if not _near("nelson") or not model.claim_gift(): return false
	session.save_game()
	_feedback("Nelson: Uma Malagousia para conhecer a casa. Ficou guardada com seus vinhos.")
	ui.refresh()
	return true

func tell_story() -> void:
	if not _near("nelson"): return
	dismiss()
	# Original fictional dialogue. Historical references: Met Museum symposium
	# essay and collections 253349 (krater), 250679 (Dionysos amphora).
	var stories := [
		[{"speaker":"Nelson","message":"Sabe, Dante, na Grécia antiga o simpósio era uma reunião de conversa, música e vinho. As taças também contavam histórias: muitas traziam Dioniso pintado."},{"speaker":"Dante","message":"Então a conversa já fazia parte da garrafa."},{"speaker":"Nelson","message":"Exatamente. Uma boa história merece tempo. Pode sentar, que eu ainda tenho muitas."}],
		[{"speaker":"Nelson","message":"Aquele vaso de boca larga lembra uma cratera grega. Ela servia para misturar vinho e água antes de servir. Até os utensílios mostram como cada época vivia."},{"speaker":"Dante","message":"Parece que você enxerga uma cidade inteira dentro de um vaso."},{"speaker":"Nelson","message":"É isso que me prende à história. Um objeto pequeno guarda um mundo enorme."}],
		[{"speaker":"Nelson","message":"Dioniso era o deus do vinho entre os gregos. Ele aparece em muitas cerâmicas antigas, junto de videiras e de seus acompanhantes."},{"speaker":"Dante","message":"Vou começar a reparar nos desenhos, então."},{"speaker":"Nelson","message":"Repare mesmo. E depois compare a Grécia com Brasil, Portugal e Chile. Cada garrafa aqui é um começo de conversa."}],
	]
	session.show_dialogue(stories[story_index%stories.size()],open_shop)
	story_index+=1

func talk_luisa() -> void:
	if not _near("luisa"): return
	session.show_dialogue([
		{"speaker":"Luísa","message":"Oi, Dante. Estou fechando o financeiro e conferindo as entradas da loja. O Nelson já te levou até a Grécia hoje?"},
		{"speaker":"Dante","message":"Ainda estou na primeira história."},
		{"speaker":"Luísa","message":"Então reserve um tempinho. Se escolher uma garrafa, a compra fica guardada nos seus vinhos. Você decide quando abrir."},
	])

func _feedback(text: String) -> void:
	if is_instance_valid(ui) and ui.visible: ui.feedback=text
	else: session.show_message(text)

func _process(delta: float) -> void:
	if session==null or not session.ready_for_play: return
	if session.world.gameplay.health<=0:
		if model.intensity()>0.0: recover()
		return
	if session.get_tree().paused: return
	if model.intensity()<=0.0 and float(model.data.cooldown)<=0.0 and not ui.visible:
		if _effects_live:
			phase=0.0
			_publish_effect()
			overlay.hide()
		return
	model.tick(delta)
	if model.intensity()>0.0: phase=fmod(phase+delta,TAU*100.0)
	else: phase=0.0
	_publish_effect()
	if is_instance_valid(overlay):
		overlay.update_effect(model.intensity(),phase,model.stage(),not session.modal and not session.is_transition_blocked())
	if ui.visible:
		if session.world.gameplay.health<opened_health or not _available() or (ui.shop and not _near("nelson")):
			session.close_menu()
		else:
			refresh_clock+=delta
			if refresh_clock>=0.15:
				refresh_clock=0.0
				ui.update_status()

func _publish_effect() -> void:
	if session==null or not is_instance_valid(session.world.player): return
	var active: float=model.intensity()
	_effects_live=active>0.0
	session.world.player.set_meta("alcohol_intensity",active)
	session.world.player.set_meta("alcohol_sway",sin(phase*1.3)*active)
	if is_instance_valid(session.world.camera):
		var visible_effect: float=active if not session.modal and not session.is_transition_blocked() else 0.0
		session.world.camera.set_meta("alcohol_intensity",visible_effect)
		session.world.camera.set_meta("alcohol_sway",sin(phase*1.3))

func _exit_tree() -> void:
	if session!=null and is_instance_valid(session.world.player):
		session.world.player.remove_meta("alcohol_intensity")
		session.world.player.remove_meta("alcohol_sway")
	if session!=null and is_instance_valid(session.world.camera):
		session.world.camera.remove_meta("alcohol_intensity")
		session.world.camera.remove_meta("alcohol_sway")
	if is_instance_valid(ui): ui.queue_free()
	if is_instance_valid(overlay): overlay.queue_free()

static func reason_text(reason: String) -> String:
	return {"unknown_wine":"Vinho indisponível.","bag_full":"Seus vinhos estão cheios: 36 taças.","insufficient_funds":"Dinheiro insuficiente.","empty":"Compre uma garrafa antes de beber.","cooldown":"Termine esta taça antes da próxima.","alcohol_limit":"Você já bebeu demais. Espere recuperar o equilíbrio.","unavailable":"Não é possível beber agora.","receipt_conflict":"Compra não concluída: registro de pagamento inconsistente.","purchase_limit":"Limite de compras atingido.","payment_refused":"Não foi possível registrar o pagamento."}.get(reason,"Não foi possível concluir.")
