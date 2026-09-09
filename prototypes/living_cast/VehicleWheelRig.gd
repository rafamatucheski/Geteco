extends RefCounted

## Rig de rodas 3D compartilhado por todos os veículos do jogo.
##
## Monta os pivôs a partir do metadado `wheel_center` que os modelos gravam
## (BaseVehicle3DModel.add_wheel, RearEngineCoupe e BossMuscleModel) e mantém as
## duas animações da roda: giro do pneu no eixo X e esterçamento do eixo
## dianteiro no eixo Y.
##
## Por que ler o metadado em vez de recalcular a posição a partir do catálogo:
## cada modelo monta o cubo onde a carroceria pede — a picape 4x4 em y=0.44, o
## sedã em y=0.36, e a bitola varia de 0.85 a 0.98. Um pivô aproximado não casa
## com o centro autoral, o conjunto da roda não chega a ser reparentado e a roda
## fica congelada na lataria. Era o que acontecia com a frota da montanha.

## Raio de pneu assumido quando o modelo não grava `wheel_radius`.
const DEFAULT_TIRE_RADIUS := 0.355
## Batente de esterçamento (~33°), o mesmo limite físico de um carro de rua.
const MAX_STEER_ANGLE := 0.58
## Guinada máxima por passo aceita como curva real. Acima disso é teleporte
## (respawn, troca de faixa, reentrada em tela) e não pode virar esterço.
const MAX_YAW_STEP := 0.5
## Velocidade com que o esterço deduzido persegue o alvo, em 1/s.
const STEER_RESPONSE := 9.0
## Abaixo desta velocidade (m/s) a guinada não descreve mais o ângulo das rodas:
## o esterço fica onde estava, como num carro real que para no meio da curva.
const MIN_SPEED_FOR_YAW := 0.35

var pivots: Array[Node3D] = []
var spinners: Array[Node3D] = []
var steering_angle := 0.0
var wheelbase := 2.5

var _steers: PackedInt32Array = PackedInt32Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
var _last_heading := INF


## Extrai os conjuntos de roda de `body_model` para pivôs articulados.
## `fallback_centers` só é usado por modelos antigos sem metadado, para não
## perder o giro que eles já tinham.
func mount(body_model: Node3D, fallback_centers: Array[Vector3] = []) -> bool:
	var centers: Array[Vector3] = []
	for node in body_model.get_children():
		if node.has_meta("wheel_center"):
			var center: Vector3 = node.get_meta("wheel_center")
			if not centers.has(center):
				centers.append(center)
	if centers.is_empty():
		centers = fallback_centers
	if centers.is_empty():
		return false

	var min_z := INF
	var max_z := -INF
	for center in centers:
		min_z = minf(min_z, center.z)
		max_z = maxf(max_z, center.z)
	wheelbase = maxf(max_z - min_z, 0.5)
	# A frente do modelo é -Z: esterça quem está na metade dianteira do entre-eixos.
	var front_limit := (min_z + max_z) * 0.5

	for center in centers:
		var pivot := Node3D.new()
		pivot.position = center
		body_model.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var radius := DEFAULT_TIRE_RADIUS
		for node in body_model.get_children():
			if node is MeshInstance3D and node.get_meta("wheel_center", Vector3.INF) == center:
				radius = float(node.get_meta("wheel_radius", radius))
				# A pinça de freio esterça com o cubo mas não gira com o pneu.
				node.reparent(spin if node.get_meta("wheel_spins", false) else pivot, true)
		pivots.append(pivot)
		spinners.append(spin)
		_steers.append(1 if center.z < front_limit else 0)
		_radii.append(maxf(radius, 0.05))
	return true


func has_wheels() -> bool:
	return not pivots.is_empty()


## Avança a pose das rodas. `signed_speed_metres` é positivo para frente.
## `explicit_steer` é o ângulo real do volante, quando o veículo tem um; passe
## INF para deduzir o esterço da guinada da carroceria.
## Retorna true quando o ângulo de esterço mudou o bastante para pedir re-render.
func update(delta: float, signed_speed_metres: float, heading: float, explicit_steer: float = INF) -> bool:
	if pivots.is_empty() or delta <= 0.0:
		return false
	var previous := steering_angle
	if is_finite(explicit_steer):
		# Carro do jogador: o ângulo do volante já existe e vale mesmo parado,
		# então as rodas viram antes do carro sair do lugar.
		steering_angle = clampf(explicit_steer, -MAX_STEER_ANGLE, MAX_STEER_ANGLE)
		_last_heading = heading
	else:
		steering_angle = lerpf(
			steering_angle,
			_steer_from_yaw(delta, signed_speed_metres, heading),
			clampf(STEER_RESPONSE * delta, 0.0, 1.0)
		)
	for i in pivots.size():
		if _steers[i] == 1:
			# Guinada positiva em 2D é para a direita; o modelo aponta para -Z,
			# onde girar em +Y leva o pneu para a esquerda. Daí o sinal invertido.
			pivots[i].rotation.y = -steering_angle
		if not is_zero_approx(signed_speed_metres):
			spinners[i].rotation.x -= signed_speed_metres / _radii[i] * delta
	return absf(steering_angle - previous) > 0.0015


## Modelo de bicicleta invertido: com que ângulo as rodas dianteiras teriam de
## estar para a carroceria guinar nessa taxa e nessa velocidade. É o que permite
## esterçar veículo cuja IA gira `rotation` direto, sem passar por um volante.
func _steer_from_yaw(delta: float, signed_speed_metres: float, heading: float) -> float:
	var previous_heading := _last_heading
	_last_heading = heading
	if not is_finite(previous_heading) or absf(signed_speed_metres) < MIN_SPEED_FOR_YAW:
		return steering_angle
	var yaw_step := angle_difference(previous_heading, heading)
	if absf(yaw_step) > MAX_YAW_STEP:
		return steering_angle
	return clampf(
		atan(yaw_step / delta * wheelbase / signed_speed_metres),
		-MAX_STEER_ANGLE,
		MAX_STEER_ANGLE
	)
