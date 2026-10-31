extends "res://gameplay/v1_handling/V1Handling.gd"
## Mantém a direção e a aderência lateral existentes, seguras contra colisão. A força
## longitudinal, o estado da marcha e o nitro são compartilhados com o drag em vez de um câmbio paralelo.
const DRIVETRAIN := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const AXLE := preload("res://gameplay/desert_cars/AxleTraction.gd")
var drive := DRIVETRAIN.new()
var _configured := false
var _coast_deceleration := 1.8

func configure(specification: Dictionary) -> void:
	super.configure(specification)
	if specification.get("desert_car",false) or specification.get("full_powertrain",false):
		drive.configure(str(specification.id),specification.get("installed_parts",{}))
		# Freio-motor de rua em m/s², mais suave para veículos mais pesados.
		_coast_deceleration = 1.8 * clampf(pow(clampf(mass, .5, 8.0), -.30), .8, 1.2)
		_configured = true

func step(car: CharacterBody3D, delta: float, throttle: float, turn: float, handbrake: bool, wetness: float) -> void:
	if not _configured or throttle < 0.0 or car.speed < -.05:
		super.step(car,delta,throttle,turn,handbrake,wetness)
		if _configured: drive.synchronize(float(car.speed),absf(throttle) if float(car.speed)*throttle>0.0 else 0.0,float(car.speed)<0.0)
		return
	var prior_speed := maxf(0.0,float(car.speed))
	var entry_speed: float = car.horizontal_velocity.length()
	# A dirigibilidade de fábrica só fornece yaw/curva seguros. O atrito dela é substituído
	# pela resistência de embalo/rolamento do trem de força ao longo da nova direção abaixo.
	# Tração por eixo: o pedal, pesado pela fração da aderência que o motor pede, volta a
	# entrar no volante e no escorregamento (RWD sai de traseira, FWD de frente) sem somar força.
	if AXLE.applies(drive.race_mode): drive_power = clampf(throttle,0.0,1.0)*clampf(drive.grip_usage,0.0,1.0)
	super.step(car,delta,0.0,turn,handbrake,wetness)
	drive_power = -1.0
	# Os freios seguram o chassi enquanto os pneus de tração giram. Mantém isto só na rua;
	# a preparação do drag e a calibração compartilhada de força/marcha continuam independentes.
	if handbrake and throttle > .2:
		if car.horizontal_velocity.length_squared() < .75*.75:
			car.horizontal_velocity = Vector3.ZERO
			car.speed = 0.0
		var previous_rpm := drive.rpm
		drive.synchronize(float(car.speed), throttle)
		drive.launched = true
		drive.wheelspin = 0.0 # Ground-aware tire effects own the held squeal.
		wheelspin = car.burnout_strength()
		if wheelspin > 0.0:
			drive.gear = 1
			drive.shift_remaining = 0.0
			drive.rpm = move_toward(previous_rpm, drive.redline*lerpf(.48,.82,wheelspin), drive.redline*delta*1.8)
		return
	if not drive.launched:
		drive.rpm = drive.redline*.50
		drive.launch()
	drive.speed_mps = prior_speed
	var surface := str(car.get_meta("surface_kind","asphalt"))
	if is_instance_valid(car.effects) and is_instance_valid(car.effects.tire_effects):
		var contacts: Array = car.effects.tire_effects.last_contacts
		for contact in contacts:
			if not contact.is_empty(): surface = str(contact.get("kind",surface)); break
	drive.surface_grip = lerpf(1.0,.67,clampf(wetness,0.0,1.0))
	if surface in ["dirt","sand","grass","snow"]:
		var loose := AXLE.loose_surface(drivetrain) if AXLE.applies(drive.race_mode) else 1.0
		drive.surface_grip *= minf(1.0,float(drive.spec.dirt_grip)*.70*loose)
	if drive.rpm >= drive.ideal_shift_rpm: drive.shift_up()
	elif drive.rpm < drive.redline*.35 and drive.gear > 1: drive.shift_down()
	var boost := Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0,JOY_BUTTON_A)
	# Limitador de rua: tira a força nos últimos 8% e não deixa passar do teto.
	var cap := float(drive.spec.street_cap_mps) * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
	drive.step(delta,throttle*clampf((cap-drive.speed_mps)/(cap*.08),0.0,1.0),boost,1.0 if handbrake else 0.0)
	# Usa o pedal do motorista, não o acelerador reduzido do limitador. Só a resistência
	# de rolamento/ar deixa carros de rua embalarem quase indefinidamente. Mantém esta
	# resposta de rua fora da calibração compartilhada do trem de força da corrida de drag.
	if throttle <= .01:
		drive.speed_mps = move_toward(drive.speed_mps, 0.0, _coast_deceleration * clampf(delta, 0.0, .25))
	drive.speed_mps = minf(drive.speed_mps,cap)
	var forward: Vector3 = -car.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var lateral: Vector3 = car.horizontal_velocity-forward*car.horizontal_velocity.dot(forward)
	car.horizontal_velocity = lateral+forward*drive.speed_mps
	# A frente volta ao motor depois que o giro já passou parte dela para o lado; derrapando
	# (freio de mão segura o lado) isso somaria velocidade. Com o freio puxado nunca passa da
	# de entrada: o que sobra do lado fica e a frente encolhe (playtest 29/10).
	# Depois de SOLTAR o Espaço, handbrake_slide mantém o lado mole por 0,7 s e o mesmo
	# giro seguia somando: sem acelerador o sport_coupe ia de 20,1 a 22,4 m/s numa curva com
	# o freio só tocado (2º relato de 29/10, "pressiona e faz curva e ganha velocidade";
	# 292 casos do test_handbrake_never_accelerates). Na janela da derrapagem o módulo só
	# muda pelo que o motor somou ou tirou neste passo (pedal, freio-motor, rolagem), nunca
	# pelo giro. Fora dela a aderência mata o lado rápido e a curva normal fica como era.
	var budget := entry_speed if handbrake else maxf(0.0,entry_speed+drive.speed_mps-prior_speed)
	if (handbrake or handbrake_slide > 0.0) and car.horizontal_velocity.length() > budget:
		var side := lateral.length()
		var along := sqrt(maxf(0.0,budget*budget-side*side))
		drive.speed_mps = minf(drive.speed_mps,along)
		car.horizontal_velocity = lateral.limit_length(budget)+forward*drive.speed_mps
	car.speed = drive.speed_mps
	wheelspin = drive.wheelspin

func reset() -> void:
	super.reset()
	drive.reset()
