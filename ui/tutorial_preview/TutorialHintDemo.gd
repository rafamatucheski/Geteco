extends SceneTree
## Demonstração independente do TutorialHintPresenter (sem integração ao
## jogo real, sem save, sem HUD real). Instancia o apresentador sozinho,
## exercita fila / bloqueio / dispensa / duração, e captura PNGs reais da
## UI discreta para conferência visual.
##
## Precisa de um renderer de verdade (sem --headless) para tirar screenshot,
## igual ao padrão usado em tests/capture_harbor_preview.gd:
##
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --path "D:/geteco/game" --script res://ui/tutorial_preview/TutorialHintDemo.gd
##
## Salva os PNGs em ui/tutorial_preview/ (capture_*.png).

const PRESENTER := preload("res://ui/tutorial_preview/TutorialHintPresenter.gd")
const OUT_DIR := "D:/geteco/game/ui/tutorial_preview/"

func _init() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT_DIR + name
	var result := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " -> ", result)

func _run() -> void:
	root.size = Vector2i(480, 270)
	root.content_scale_size = Vector2i(480, 270)

	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var presenter := PRESENTER.new()
	# "ui_cancel" já existe no InputMap padrão do Godot em qualquer projeto
	# (tecla Esc por padrão) -- não é uma tecla inventada por este arquivo,
	# só demonstra que o apresentador aceita qualquer action já registrada
	# pelo chamador, sem presumir nenhuma tecla própria do jogo.
	presenter.set_dismiss_action("ui_cancel")
	presenter.set_hint_duration(30.0)
	world.add_child(presenter)
	for frame in 6:
		await process_frame

	print("DEMO 1/4: pedindo a primeira dica (primeiro porta-malas)")
	presenter.request_hint("first_trunk")
	for frame in 6:
		await process_frame
	await _shot("capture_hint_shown.png")
	print("DEMO active=", presenter.get_active_hint_id())

	print("DEMO 2/4: combate ativo -- novo pedido fica na fila, nada novo aparece")
	presenter.set_combat_active(true)
	presenter.request_hint("cold_shelter")
	for frame in 6:
		await process_frame
	await _shot("capture_blocked_queue.png")
	print("DEMO active_during_block=", presenter.get_active_hint_id(), " pending=", presenter.get_pending_hints())

	print("DEMO 3/4: dispensando a ativa e saindo do combate -- a da fila aparece sozinha")
	presenter.dismiss_hint()
	presenter.set_combat_active(false)
	for frame in 6:
		await process_frame
	await _shot("capture_next_after_unblock.png")
	print("DEMO active_after_unblock=", presenter.get_active_hint_id())

	print("DEMO 4/4: repetição -- pedir de novo uma dica já vista nesta sessão é recusado")
	var repeat_ok := presenter.request_hint("first_trunk")
	print("DEMO repeat_request_accepted=", repeat_ok, " (esperado: false)")

	presenter.reset_preview()
	print("DEMO reset_preview() -> active=", presenter.get_active_hint_id(), " pending=", presenter.get_pending_hints(), " seen(first_trunk)=", presenter.has_seen("first_trunk"))

	print("DEMO_TUTORIAL_PREVIEW done")
	quit(0)
