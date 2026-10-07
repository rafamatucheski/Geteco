extends SceneTree
## A vitrine 3D mostra o carro certo, acompanha a prévia do neon e libera tudo ao fechar.
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _run() -> void:
	var panel := PANEL.new()
	root.add_child(panel)
	await process_frame
	var showroom = panel._showroom
	_check(not showroom.has_model(),"Vitrine não pode ter carro antes de abrir")
	panel.show_vehicle("porto_rosso",{},[],0,5000,{"archetype":"porto_rosso","paint":Color("e01824")})
	await process_frame
	_check(showroom.has_model() and showroom._archetype == "porto_rosso","Vitrine não mostra o carro pedido")
	_check(showroom._viewport.own_world_3d,"Vitrine precisa de mundo 3D próprio para não tocar no jogo")
	_check(showroom._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Vitrine aberta deve renderizar")
	var first = showroom._model
	panel.show_vehicle("porto_rosso",{"ecu":"ecu_1"},["ecu_1"],1,5000,{"archetype":"porto_rosso","paint":Color("e01824")})
	_check(showroom._model == first,"Reabrir o mesmo carro não pode recriar o modelo")
	panel.show_vehicle("sedan_classic",{},[],1,5000,{"archetype":"sedan_classic","paint":Color("284d79")})
	_check(showroom._archetype == "sedan_classic" and showroom._model != first,"Trocar de carro não trocou o modelo")
	_check(not showroom._glow_disc.visible,"Sem neon, o palco não pode brilhar")
	panel._select_slot("neon")
	panel._preview({"slot":"neon","id":"neon_amber"})
	_check(showroom._glow_disc.visible and showroom._glow_light.light_color == Color("ff9a2e") and showroom._glow_light.light_energy > 0.0,"Prévia do neon âmbar não chegou à vitrine")
	panel._preview({})
	_check(not showroom._glow_disc.visible,"Fim da prévia deve apagar o neon que não está instalado")
	var before: float = showroom.yaw()
	await create_timer(.4).timeout
	_check(absf(angle_difference(before,showroom.yaw())) > .02,"O carro não gira sozinho")
	# O mesmo `hide()` que o runtime usa ao sair da oficina libera o modelo e para de renderizar.
	panel.hide()
	await process_frame
	_check(not showroom.has_model(),"Fechar a oficina deixou o modelo na memória")
	_check(showroom._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Vitrine fechada continua renderizando")
	panel.free()
	await process_frame
	print("TUNING_SHOWROOM ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
