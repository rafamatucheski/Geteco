extends RefCounted
## O tiroteio do prólogo pelo lado de Dante: mira (mouse no plano do peito ou analógico), câmera de mira,
## tiro com o caminhão parando bala, acerto na cápsula, morte com a arma caindo, o atirador alternando entre
## exposto e escondido, os tocadores de tiro e a captura do mouse. Separado da BlitzScene em 01/11 só para
## ela caber na leitura; o estado (`shooter_health`, `shooter_hits`, `vicente_hit`, `_aim_point`...) continua
## lá, porque os testes leem esses campos na cena, e cada função antiga ficou lá como delegação de uma linha.
## `g` sem tipo e sem preload do dono, como em BlitzSet. Chamadas entre funções passam por `g.`.
const CORPSE := preload("res://runtime/prologue/BlitzCorpse.gd")
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const MIXAMO_DEATH := preload("res://gameplay/MixamoDeath.gd")

var g

func _init(host: CanvasLayer) -> void:
	g = host

## Por cima do ombro direito; o corpo de Dante gira com a mira e o PoliceModel põe as duas mãos na arma.
## De cima, um pouco adiantada para onde ele mira; o corpo de Dante gira com a mira e a pegada da pistola é
## a do jogo.
func _aim_camera(step: float) -> void:
	var lead: Vector3 = g._aim_point - g.dante.global_position
	lead.y = 0.0
	g._high_camera(g.dante.global_position + lead.limit_length(6.0) * .35, g.HIGH_SIZE, step)
	g.dante.combat_facing = g.aim_yaw

func _aim_tick(step: float) -> void:
	var target: Node3D = g._current_target()
	if g.autoplay and target != null:
		g._aim_point = target.global_position + Vector3.UP * 1.2
		var exposed: bool = target != g.shooter or g._shooter_visible()
		g._want_fire = exposed and g._fire_cooldown <= 0.0 and g.stage_time > (.4 if target == g.shooter else 1.8)
	else: g._aim_point = g._pointer_aim(step)
	var toward: Vector3 = g._aim_point - g.dante.global_position
	if Vector2(toward.x, toward.z).length() > .3: g.aim_yaw = atan2(-toward.x, -toward.z)
	g.dante.update_pose(step, true, false, 0.0, 0.0)
	g._aim_camera(step)
	g._place_crosshair()
	if g._want_fire or (not g.autoplay and Input.is_action_pressed("fire") and g._fire_cooldown <= 0.0):
		g._want_fire = false
		g._fire()

## Ponto mirado: o mouse projetado no plano do peito (como o jogo mira de cima); no controle, a direção do
## analógico do GameInput do jogo.
func _pointer_aim(step: float) -> Vector3:
	var game_input: Node = g.get_node_or_null("/root/GameInput")
	if game_input != null and game_input.using_gamepad:
		var point: Vector3 = game_input.aim_target_3d(g.dante, g.camera, step, false)
		return Vector3(point.x, 1.2, point.z)
	var mouse: Vector2 = g._main_viewport.get_mouse_position() * Vector2(g._viewport.size) / g._main_viewport.get_visible_rect().size
	var hit: Variant = Plane(Vector3.UP, 1.2).intersects_ray(g.camera.project_ray_origin(mouse), g.camera.project_ray_normal(mouse))
	return hit if hit != null else g._aim_point

func _place_crosshair() -> void:
	if not g._crosshair.visible or g.camera.is_position_behind(g._aim_point): return
	var screen: Vector2 = g.camera.unproject_position(g._aim_point) * g._main_viewport.get_visible_rect().size / Vector2(g._viewport.size)
	g._crosshair.position = screen - g._crosshair.size * .5

## Peito de Dante: de onde sai o tiro.
func _muzzle_origin() -> Vector3:
	return g.dante.global_position + Vector3.UP * 1.35

func _current_target() -> Node3D:
	if g.stage == "dante_fight" and g.shooter_health > 0: return g.shooter
	if g.stage == "dante_flee" and not g.vicente_hit: return g.vicente
	return null

func _shooter_visible() -> bool:
	if not is_instance_valid(g.shooter) or g.shooter_health <= 0: return false
	var chest: Vector3 = g.shooter.global_position + Vector3.UP * 1.2
	return g._truck_hit(g._muzzle_origin(), (chest - g._muzzle_origin()).normalized()) > g._muzzle_origin().distance_to(chest)

func _fire() -> void:
	if g._fire_cooldown > 0.0: return
	g._fire_cooldown = .26
	g.shots_fired += 1
	g.dante.attack()
	g._shot_audio(-1.0)
	# Do peito de Dante para o ponto mirado, na altura do peito (de cima a mira é no chão do mapa).
	var origin: Vector3 = g._muzzle_origin()
	var direction: Vector3 = (Vector3(g._aim_point.x, 1.25, g._aim_point.z) - origin).normalized()
	var wall: float = g._truck_hit(origin, direction)
	var target: Node3D = g._current_target()
	if target == null: return
	var distance: float = g.capsule_hit(origin, direction, target.global_position, .4 if target == g.shooter else .36, 1.75 if target == g.shooter else (1.75 - .7 * g.vicente.sit_amount))
	if distance < 0.0 or distance > wall:
		if wall < INF: g._play_at_volume("res://audio/weapons_fire/ricochet_%d.wav" % (g.shots_fired % 4), -10.0)
		return
	g._play_at_volume("res://audio/body_impacts/body_hit_%d.wav" % (g.shots_fired % 3), -6.0)
	if target == g.shooter:
		g.shooter_hits += 1
		g.shooter_health -= 1
		if g.shooter_health > 0:
			FALL.apply_hit(g.shooter, g.shooter, direction, 26.0)
			# Ferido, ele se esconde antes da próxima rajada.
			if g.shooter_hits % 3 == 0: g._shooter_exposed = false
		else:
			g._kill(g.shooter, direction)
			g.stage_time = 0.0
			g.say("dante", "shooter_down")
	elif target == g.vicente:
		g.vicente_hit = true
		g._capture_mouse(false)
		g._crosshair.hide()
		g._hide_prompt()
		g._objective.text = ""
		g.vicente._flinch(direction, 35.0)
		g._set_stage("dante_wounded")

## Morte como a do jogo: solta as mãos, a arma cai da mão até o asfalto e o corpo toca o clipe de morte do
## Mixamo (o lado sai do empurrão do tiro). Sem a biblioteca, a queda procedural.
func _kill(model: Node3D, direction: Vector3) -> void:
	FALL._release_hands(model)
	g._drop_gun(model)
	var marker := CORPSE.new()
	model.add_child(marker)
	if not MIXAMO_DEATH.play(marker, model, direction): FALL.apply_fall(model, model, direction)
	g._play_at_volume("res://audio/body_impacts/body_land_%d.wav" % randi_range(0, 2), -8.0)

## A arma sai da mão: cai girando, quica uma vez e fica deitada no asfalto.
func _drop_gun(model: Node3D) -> void:
	var gun = model.get("weapon")
	if not gun is Node3D or not is_instance_valid(gun) or not gun.visible: return
	var flash = model.get("muzzle_flash_3d")
	if flash is Node3D: flash.hide()
	gun.reparent(g._set, true)
	var start: Transform3D = gun.global_transform
	var scale_kept := start.basis.get_scale()
	var land: Vector3 = Vector3(start.origin.x, .03, start.origin.z) + g._forward(model) * .3 + Vector3(randf_range(-.15, .15), 0, randf_range(-.15, .15))
	var rest := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, PI * .5)
	var from_rotation := start.basis.orthonormalized().get_rotation_quaternion()
	var to_rotation := rest.get_rotation_quaternion()
	var fall: Tween = g.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fall.tween_method(func(t: float):
		if not is_instance_valid(gun): return
		# Queda com gravidade até o chão (70% do tempo) e um quique baixo.
		var drop := clampf(t / .7, 0.0, 1.0)
		var bounce := sin(clampf((t - .7) / .3, 0.0, 1.0) * PI) * .07 if t > .7 else 0.0
		var height := lerpf(start.origin.y, land.y, drop * drop) + bounce
		var flat := start.origin.lerp(land, minf(1.0, t * 1.2))
		var turn := from_rotation.slerp(to_rotation, smoothstep(0.0, .85, t))
		gun.global_transform = Transform3D(Basis(turn).scaled(scale_kept), Vector3(flat.x, height, flat.z))
	, 0.0, 1.0, .55 / g.pace)
	fall.tween_callback(func(): g._play_at_volume("res://audio/weapons_fire/gun_holster_2.wav", -10.0))

## O caminhão para bala: distância até a caixa dele ao longo do raio (INF se passa livre).
func _truck_hit(origin: Vector3, direction: Vector3) -> float:
	var inverse: Transform3D = g.truck.global_transform.affine_inverse()
	var local_origin := inverse * origin
	var hit: Variant = AABB(Vector3(-1.3, 0, -5.75), Vector3(2.6, 3.9, 11.5)).intersects_ray(local_origin, inverse.basis * direction)
	return INF if hit == null else local_origin.distance_to(hit)

func _shooter_tick(step: float) -> void:
	if not is_instance_valid(g.shooter) or g.shooter_health <= 0: return
	g._shooter_clock -= step
	if g._shooter_clock <= 0.0:
		g._shooter_exposed = not g._shooter_exposed
		g._shooter_clock = 2.2 if g._shooter_exposed else 1.3
	var goal: Vector3 = g.SHOOTER_EXPOSED if g._shooter_exposed else g.SHOOTER_HIDDEN
	g.shooter.global_position = g.shooter.global_position.move_toward(goal, 2.6 * step)
	g._face(g.shooter, g.dante.global_position - g.shooter.global_position)
	g.shooter.update_pose(step, true, false, 0.0, 0.0)
	if g.shooter.global_position.distance_to(g.SHOOTER_EXPOSED) < .35:
		g._shooter_fire_clock -= step
		if g._shooter_fire_clock <= 0.0:
			g._shooter_fire_clock = randf_range(.5, .8)
			g._enemy_shot()

func _enemy_shot() -> void:
	g.shooter.attack()
	g._play_at_volume("res://audio/weapons_fire/pistol_%d.wav" % randi_range(0, 3), -3.0)
	g._play_at_volume("res://audio/weapons_fire/bullet_whiz_%d.wav" % randi_range(0, 3), -8.0)
	g._shake = maxf(g._shake, .25)

func _shot_audio(volume: float) -> void:
	g._play_at_volume("res://audio/weapons_fire/pistol_%d.wav" % (g.shots_fired % 4), volume)

## Tiros e impactos se sobrepõem: cada um num tocador próprio que some ao terminar.
func _play_at_volume(path: String, volume: float) -> void:
	var stream: AudioStream = g._sound(path)
	if stream == null: return
	var player: AudioStreamPlayer = g._player("SFX", stream, volume)
	player.finished.connect(player.queue_free)
	player.play()

func _show_fire_prompt() -> void:
	var game_input: Node = g.get_node_or_null("/root/GameInput")
	var hint: String = game_input.prompt("fire") if game_input != null else "—"
	if hint == "—": hint = "Mouse"
	g._prompt.text = "[%s] %s" % [hint, g.text(g.lines().get("prompts", {}).get("fire"))]
	g._crosshair.show()

func _capture_mouse(value: bool) -> void:
	if DisplayServer.get_name() == "headless": return
	if value and not g._mouse_owned:
		g._previous_mouse = Input.mouse_mode
		g._mouse_owned = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not value and g._mouse_owned:
		g._mouse_owned = false
		Input.mouse_mode = g._previous_mouse
