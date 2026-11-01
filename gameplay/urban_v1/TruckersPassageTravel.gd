extends RefCounted
## Viagens da passagem secreta: casa ↔ porão ↔ túnel (fallback sem corte físico), ocupação e câmera
## do porão, subida do forte ao esqui, entrada pela laje, cortina preta e as idas ao forte e ao esgoto.
## Separado de TruckersVillageSecretPassage.gd em 01/11 só para o dono caber na leitura. O estado
## (_transfer_busy, _cellar_occupied, _surface_camera, _curtain_layer) e os sinais continuam no dono;
## o dono mantém cada função antiga como delegação de uma linha (com `await` nas corrotinas).
## `g` fica como Node3D, e não como o script do dono, para não criar preload cíclico; até as chamadas
## entre funções deste arquivo passam por `g.` (inclusive `g._finish_tunnel_transfer.call_deferred()`).

const FORT_PLACE := preload("res://gameplay/urban_v1/MountainFortPlace.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _transfer_to_cellar() -> void:
	if g._transfer_busy: return
	g._transfer_busy = true
	g._surface_camera = g.get_viewport().get_camera_3d()

	g._lock_player(true)
	g._set_player_position(g._cellar_global(g.CELLAR_SPAWN))
	g._set_cellar_occupied(true)
	g._lock_player(false)
	g._transfer_busy = false

func _transfer_to_house() -> void:
	if g._transfer_busy: return
	g._transfer_busy = true
	g._lock_player(true)
	g._set_player_position(g.home.to_global(g.SURFACE_RETURN_LOCAL))
	g._set_cellar_occupied(false)
	g._lock_player(false)
	g._transfer_busy = false

func _transfer_to_tunnel() -> void:
	if g._transfer_busy or not g._keypad_unlocked() or not is_instance_valid(g.tunnel): return
	g._transfer_busy = true
	g.camera_transfer_started.emit(true)
	g._lock_player(true)
	g.tunnel.set_enabled(true)
	g._set_player_position(g.tunnel.entry_global())
	# SecretTunnel3D reivindica a câmera atual do porão como câmera de volta no
	# tick de process seguinte. Manter isto adiado evita dois donos de câmera.
	g._finish_tunnel_transfer.call_deferred()

func _finish_tunnel_transfer() -> void:
	g._lock_player(false)
	g._transfer_busy = false

func _transfer_from_tunnel() -> void:
	if g._transfer_busy or not is_instance_valid(g.tunnel): return
	g._transfer_busy = true
	g.camera_transfer_started.emit(false)
	g._lock_player(true)
	g._set_player_position(g._cellar_global(g.TUNNEL_RETURN))
	g._finish_tunnel_transfer.call_deferred()

func _set_player_position(point: Vector3) -> void:
	var player: Node3D = g.session.world.player
	if player.has_method("teleport"): player.teleport(point)
	else: player.global_position = point
	if player is CharacterBody3D: player.velocity = Vector3.ZERO

func _lock_player(value: bool) -> void:
	if g.session != null and is_instance_valid(g.session.world.player):
		g.session.world.player.input_locked = value

func _in_cellar(point: Vector3) -> bool:
	if not is_instance_valid(g.cellar_root): return false
	var local: Vector3 = g.cellar_root.to_local(point)
	return g.CELLAR_INSIDE.has_point(Vector2(local.x,local.z)) and local.y > -.8 and local.y < 3.2

func _set_cellar_occupied(value: bool,restore_surface_camera := true) -> void:
	if g._cellar_occupied == value: return
	g._cellar_occupied = value
	if is_instance_valid(g.cellar_ceiling): g.cellar_ceiling.visible = not value
	if g.homes != null and g.homes.homes.size() > g.HOME_INDEX:
		g.homes.homes[g.HOME_INDEX].roof.visible = not value
		g.homes.homes[g.HOME_INDEX].upper.visible = not value
	if value:
		g._enable_player_underground_layer()
		if not is_instance_valid(g._surface_camera): g._surface_camera = g.get_viewport().get_camera_3d()
		g.cellar_camera.make_current()
		if g.session.world.player.get("camera") != null: g.session.world.player.camera = g.cellar_camera
	elif restore_surface_camera and is_instance_valid(g._surface_camera):
		g._surface_camera.make_current()
		if g.session != null and is_instance_valid(g.session.world.player) and g.session.world.player.get("camera") != null:
			g.session.world.player.camera = g._surface_camera

func _update_cellar_camera(point: Vector3) -> void:
	var local: Vector3 = g.cellar_root.to_local(point)
	var focus := Vector3(clampf(local.x,-.85,.85),.58,clampf(local.z,-.65,.65))
	g.cellar_camera.global_position = g.cellar_root.to_global(focus+Vector3(0,10.8,8.6))
	g.cellar_camera.look_at(g.cellar_root.to_global(focus),Vector3.UP)

func _ski_exit_action() -> Dictionary:
	if g.session == null or not is_instance_valid(g.ski_exit) or g._transfer_busy or not g._vault_unlocked(): return {}
	if not g.session.ready_for_play or g.session.state.region_id != "mountain" or not g.session.state.place_id.is_empty(): return {}
	if g.session.player_in_vehicle() or g.session.player_health() <= 0: return {}
	if g.session.player_position().distance_to(g.ski_exit.interaction_global()) > 1.9: return {}
	return g._action("ski_enter","Abrir passagem de pedra")

## Subida do forte até o esqui: o elevador fecha, a tela escurece, o jogador vai para a
## serra e a laje de pedra se arrasta atrás dele.
func _ascend_to_ski() -> void:
	if g._transfer_busy or g.session == null or g.session.state.place_id != "mountain_fort": return
	var fort = g.session.room
	if not fort.operation.can_ascend():
		g._show_message("O elevador não parte com a sala sob fogo.")
		return
	g._transfer_busy = true
	g._lock_player(true)
	fort.model.set_lift_open(true)
	await g.get_tree().create_timer(1.1).timeout
	await g._curtain(1.0,.7,"Subindo...")
	g._lock_player(false)
	var from_mountain: bool = g.session.state.region_id == "mountain"
	await g.get_tree().create_timer(2.2).timeout
	var left: bool = await g.session.leave_place()
	if left and not from_mountain:
		if g.session.controller.travel("mountain",g.ski_exit.arrival_global()):
			while g.session.controller.travel_busy: await g.get_tree().process_frame
	if left: await g._emerge_from_slab()
	else: await g._curtain(0.0,.5)
	g._transfer_busy = false

func _enter_fort_from_ski() -> void:
	if g._transfer_busy or not is_instance_valid(g.ski_exit): return
	g._transfer_busy = true
	g._lock_player(true)
	g.ski_exit.set_open(true)
	await g.get_tree().create_timer(3.0).timeout
	await g._curtain(1.0,.6,"")
	g._lock_player(false)
	FORT_PLACE.next_return = g.ski_exit.arrival_global()
	var entered: bool = await g.session.enter_place("mountain_fort",false,"secret_network")
	FORT_PLACE.next_return = Vector3.INF
	if entered:
		g.session.return_point = g.ski_exit.arrival_global()
		g.session.access_id = "secret_network"
		g.session.save_game()
	g.ski_exit.set_open(false,false)
	await g._curtain(0.0,.6)
	g._transfer_busy = false

func _emerge_from_slab() -> void:
	g.ski_exit.activate_now()
	g.ski_exit.set_open(true,false)
	await g._curtain(0.0,.9)
	await g.get_tree().create_timer(3.4).timeout
	g.ski_exit.set_open(false)

## Cortina preta com texto opcional (fade em segundos).
func _curtain(alpha: float,seconds: float,text := "") -> void:
	if g._curtain_layer == null:
		g._curtain_layer = CanvasLayer.new()
		g._curtain_layer.layer = 90
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.color = Color.BLACK
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.modulate.a = 0.0
		g._curtain_layer.add_child(fill)
		var label := Label.new()
		label.name = "Text"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",30)
		fill.add_child(label)
		g.session.add_child(g._curtain_layer)
	var fill_node: ColorRect = g._curtain_layer.get_node("Fill")
	fill_node.get_node("Text").text = text
	var tween: Tween = g.create_tween()
	tween.tween_property(fill_node,"modulate:a",alpha,seconds)
	await tween.finished

func _travel_to_fort() -> void:
	if g.session == null or not g._vault_unlocked() or not is_instance_valid(g.tunnel): return
	var return_point: Vector3 = g.tunnel.vault_arrival_global()
	g.tunnel.set_return_camera(g.session.world.camera)
	var entered: bool = await g.session.enter_place("mountain_fort",false,"secret_network")
	if not entered: return
	g.session.return_point = return_point
	g.session.access_id = "secret_network"
	g.session.save_game()

func _travel_to_sewer() -> void:
	if g.session == null or not g._route_active("route_harbor_sewer") or not is_instance_valid(g.tunnel): return
	var return_point: Vector3 = g.tunnel.route_arrival_global()
	g.tunnel.set_return_camera(g.session.world.camera)
	var entered: bool = await g.session.enter_place("harbor_sewer",false,"secret_network")
	if not entered: return
	g.session.return_point = return_point
	g.session.access_id = "secret_network"
	g.session.save_game()
