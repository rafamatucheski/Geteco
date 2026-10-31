extends RefCounted
## Morte, prisão e resgate da FullSession: as telas "SE FODEU"/"PRESO" com câmera lenta, a escolha
## do ponto de resgate e a multa. Separado em 31/10 para o FullSession.gd caber na leitura; as bandeiras
## (rescue_pending, arrest_pending, respawn_busy, death_presentation...) continuam na sessão, que o
## registro de limpeza e os testes leem, e cada função antiga virou delegação (as corrotinas com await).
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem _respawn e as
## apresentações numa subclasse da sessão e o despacho tem de continuar igual.

const PLACES := preload("res://world/places/PlaceCatalog.gd")
const RECOVERY_PENALTY := preload("res://runtime/RecoveryPenalty.gd")
const V1_DEATH_AUDIO := preload("res://audio/V1DeathAudio.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _show_v1_death_presentation() -> void:
	if is_instance_valid(g.death_presentation): g.death_presentation.queue_free()
	g.death_presentation = CanvasLayer.new()
	g.death_presentation.name = "WastedPresentation"
	g.death_presentation.layer = 120
	var audio := AudioStreamPlayer.new()
	audio.name = "WastedAudio"
	audio.stream = V1_DEATH_AUDIO.stream()
	audio.volume_db = 0.0
	g.death_presentation.add_child(audio)
	var tint := ColorRect.new()
	tint.name = "DeathTint"
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.48,0.035,0.055,0.0)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	g.death_presentation.add_child(tint)
	var label := Label.new()
	label.name = "WastedLabel"
	label.text = "SE FODEU"
	if g.bank_death_loss>0: label.text+=String(TranslationServer.translate("\n− R$ %d · Saque perdido"))%g.bank_death_loss
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size",42)
	label.add_theme_color_override("font_color",Color(1.0,0.94,0.87))
	label.add_theme_color_override("font_outline_color",Color(0.08,0.01,0.015))
	label.add_theme_constant_override("outline_size",5)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",3)
	label.add_theme_constant_override("shadow_offset_y",3)
	label.modulate.a = 0.0
	g.death_presentation.add_child(label)
	g.get_tree().root.add_child(g.death_presentation)
	audio.play()
	label.pivot_offset = g.get_viewport().get_visible_rect().size*.5
	label.scale = Vector2(1.35,1.35)
	var intro: Tween = g.create_tween().set_ignore_time_scale(true).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro.tween_property(tint,"color:a",.66,.35)
	intro.tween_property(label,"modulate:a",1.0,.35)
	intro.tween_property(label,"scale",Vector2.ONE,.35)
	await g._hold_recovery_presentation(g.death_presentation)

func _show_v1_arrest_presentation() -> void:
	if is_instance_valid(g.death_presentation): g.death_presentation.queue_free()
	g.death_presentation = CanvasLayer.new()
	g.death_presentation.name = "ArrestPresentation"
	g.death_presentation.layer = 120
	var tint := ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.1,0.2,0.8,0.45)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	g.death_presentation.add_child(tint)
	var label := Label.new()
	label.name = "ArrestLabel"
	label.text = "PRESO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size",46)
	label.add_theme_color_override("font_color",Color(0.2,0.6,1.0))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",3)
	label.add_theme_constant_override("shadow_offset_y",3)
	g.death_presentation.add_child(label)
	g.get_tree().root.add_child(g.death_presentation)
	label.modulate.a = 0.0
	var intro: Tween = g.create_tween().set_ignore_time_scale(true)
	intro.tween_property(label, "modulate:a", 1.0, 0.35)
	await g._hold_recovery_presentation(g.death_presentation)

func _hold_recovery_presentation(presentation: CanvasLayer) -> void:
	if not g._recovery_slow_motion:
		g._recovery_time_scale = Engine.time_scale
		g._recovery_slow_motion = true
	Engine.time_scale = g._recovery_time_scale * 0.2
	# Wall-clock timing keeps the message readable despite the slowed world.
	await g.get_tree().create_timer(2.4, false, false, true).timeout
	if not is_instance_valid(presentation) or presentation != g.death_presentation: return
	var blackout := ColorRect.new()
	blackout.name = "RecoveryBlackout"
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.color = Color(0, 0, 0, 0)
	blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	presentation.add_child(blackout)
	var fade: Tween = g.create_tween().set_ignore_time_scale(true)
	fade.tween_property(blackout, "color:a", 1.0, 0.8)
	await fade.finished
	if presentation != g.death_presentation: return
	g._restore_recovery_time_scale()

func _restore_recovery_time_scale() -> void:
	if not g._recovery_slow_motion: return
	Engine.time_scale = g._recovery_time_scale
	g._recovery_slow_motion = false

func _finish_recovery_presentation() -> void:
	g._restore_recovery_time_scale()
	var presentation: CanvasLayer = g.death_presentation
	if not is_instance_valid(presentation): return
	# Remove the message behind the opaque cover, then reveal the settled camera.
	for child in presentation.get_children():
		if child is Control and child.name != "RecoveryBlackout": child.hide()
	await g.get_tree().create_timer(0.3, false, false, true).timeout
	if not is_instance_valid(presentation) or presentation != g.death_presentation: return
	var fade: Tween = g.create_tween().set_ignore_time_scale(true)
	fade.tween_property(presentation.get_node("RecoveryBlackout"), "color:a", 0.0, 1.0)
	await fade.finished
	if is_instance_valid(presentation) and presentation == g.death_presentation:
		g.death_presentation = null
		presentation.queue_free()

func _on_arrest() -> void:
	if g.arrest_pending or g.rescue_pending: return
	g._cancel_for(&"arrest_1")
	g.arrest_pending = true
	# Gameplay's arrest signal already owns this lock; illusion cleanup must
	# not release it while the custody presentation is running.
	g.world.player.input_locked = true
	g._cancel_for(&"arrest_2")
	g.prompt.text = ""
	g._cancel_for(&"arrest_3")
	# Service/mission teardown may restore an earlier input snapshot.
	# Custody takes final ownership before yielding to the presentation.
	g.world.player.input_locked = true
	await g._show_v1_arrest_presentation()
	if not g.arrest_pending or not g.is_inside_tree(): return
	await g._respawn()

func _on_death() -> void:
	g._cancel_for(&"death_1")
	if g.rescue_pending: return
	g._cancel_for(&"death_2")
	# Fora do registro: a resposta é o saque perdido, mostrado no "SE FODEU".
	g.bank_death_loss = g.robberies.player_died() if g.robberies != null else 0
	# The old arrest coroutine must not select custody or consume this rescue.
	g.arrest_pending = false
	# Um resgate que não é desta morte pode estar em curso: o _respawn da própria prisão (delegacia
	# escolhida, cortina abrindo; a rendição não para as balas de civis hostis) ou o da chegada.
	# Ele terminava depois desta morte, limpava rescue_pending, cobrava a multa e deixava o corpo
	# morto e travado na delegacia; esta morte via rescue_pending falso e pulava o próprio resgate.
	# Soltar a transição dele o faz parar no próximo _owns_transition, sem mexer nas bandeiras nem
	# cobrar nada, e deixa o _respawn desta morte começar (morte prevalece, como na apresentação).
	if g.respawn_busy:
		g.respawn_busy = false
		if g.transition_kind == "rescue": g._finish_transition(g.transition_generation)
	# Falling out of the world and an invalid restored position reach this path
	# directly, without damage_player. Establish the same dead state before any
	# boarding cleanup or death presentation reads it.
	g.world.gameplay.health = 0
	g._cancel_for(&"death_3")
	g.world.player.input_locked = true
	g.world.player.on_player_death()
	# Damage may have posed death before Driving restored the on-foot capsule.
	# Reassert the dead body's collision after cancelling that presentation.
	g.world.player.collision_layer = 0
	g.world.player.collision_mask = 0
	g.world.player.set_physics_process(false)
	g.world.gameplay.changed.emit()
	var from_interior: bool = not g.state.place_id.is_empty() or is_instance_valid(g.room)
	g.rescue_camera_heading = g.saved_heading if from_interior else g.world.camera.heading
	g.rescue_camera_size = g.saved_size if from_interior else g.world.camera.target_size
	g.rescue_pending = true
	g.prompt.text = ""
	g.world.hud.refresh_from_state()
	g._cancel_for(&"death_4")
	await g._show_v1_death_presentation()
	if not g.rescue_pending or not g.is_inside_tree(): return
	await g._respawn()

func _respawn() -> void:
	g._cancel_for(&"rescue_1")
	if g.respawn_busy: return
	var token: int = g._begin_transition("rescue")
	if token < 0:
		g.show_message("Aguarde a transição atual e tente novamente.")
		return
	g.respawn_busy = true
	var arrested: bool = g.arrest_pending
	var fallback: Vector3 = g.controller.region.spawn_position+Vector3.UP*.1
	var destination := fallback
	# Morte acorda na porta do Bay Medical, prisão sai pela delegacia (RecoveryPenalty).
	var recovery_place: Dictionary = PLACES.get_definition(RECOVERY_PENALTY.place_for(g.state.region_id, arrested))
	if not recovery_place.is_empty(): destination = recovery_place.return_position+Vector3.UP*.1
	g.controller.region.set_focus(destination)
	# Na serra o ponto de resgate é o spawn_position, no tabuleiro da ponte: o piso é da conexão.
	g.controller.prepare_connection_at(destination)
	if g.cold != null: g.cold.prepare_collision_at(destination)
	for i in 3:
		await g.get_tree().physics_frame
		if not g._owns_transition(token): return
	if not g.position_clear(destination) and destination != fallback:
		# Porta ocupada (ambulância, viatura estacionada): usa o ponto de resgate da região.
		destination = fallback
		g.controller.region.set_focus(destination)
		g.controller.prepare_connection_at(destination)
		if g.cold != null: g.cold.prepare_collision_at(destination)
		for i in 3:
			await g.get_tree().physics_frame
			if not g._owns_transition(token): return
	if not g.position_clear(destination):
		g.respawn_busy = false
		g._finish_transition(token)
		g._restore_recovery_time_scale()
		if is_instance_valid(g.death_presentation): g.death_presentation.queue_free()
		g.death_presentation = null
		g._menu("Local de custódia ocupado. Aguarde e tente novamente." if g.arrest_pending else "Local de resgate ocupado. Aguarde e tente novamente.")
		g._button("Tentar novamente",Callable(g, "_respawn"))
		return
	if g.world.driving.occupied:
		g.world.driving.occupied = false
		if is_instance_valid(g.world.driving.car):
			g.world.driving.car.controlled = false
			g.world.driving.car.external_input = false
			g.world.driving.car.throttle_input = 0
	g._cancel_for(&"rescue_2")
	if is_instance_valid(g.room):
		if g.room == g.world.maciota_place: g.room.set_interior_active(false)
		else: g.room.queue_free()
	g._clear_service_npcs()
	g.room = null
	g.state.set_location(g.state.region_id)
	g.world.gameplay.respawn()
	g.world.player.respawn_player()
	g._cancel_for(&"rescue_3")
	g.sync_dispatch_location()
	if g.cold != null: g.cold.recover_after_rescue()
	if g.wine != null: g.wine.recover()
	g.world.player.teleport(destination)
	g._sync_location_presentation()
	g.world.player.collision_layer = 2
	g.world.player.collision_mask = 7
	g.world.player.show()
	g.world.player.set_physics_process(true)
	g.world.camera.target = g.world.player
	g.world.camera.offset = g.world.camera.EXTERIOR_OFFSET
	g.world.camera.heading = g.rescue_camera_heading
	g.world.camera.target_size = g.rescue_camera_size
	g.world.camera.size = g.rescue_camera_size
	g.world.camera.locked = false
	g.world.camera.initialized = false
	g.world.camera._process(1)
	g._refresh_routine_context()
	g.world.player.input_locked = true
	await g._finish_recovery_presentation()
	if not g._owns_transition(token): return
	g.rescue_pending = false
	g.arrest_pending = false
	g.respawn_busy = false
	g._finish_transition(token)
	g.close_menu()
	# Só depois do resgate concluído: "Tentar novamente" não pode cobrar duas vezes.
	var notices: Array[String] = []
	if g.bank_death_loss>0:
		notices.append(String(TranslationServer.translate("Assalto fracassado: − R$ %d"))%g.bank_death_loss)
		g.bank_death_loss=0
	var penalty_text := RECOVERY_PENALTY.message(RECOVERY_PENALTY.apply(g.state.economy, arrested), arrested)
	if not penalty_text.is_empty(): notices.append(penalty_text)
	if not notices.is_empty():
		g.show_message(" · ".join(notices))
		g.world.gameplay.changed.emit()
	g.save_game()
