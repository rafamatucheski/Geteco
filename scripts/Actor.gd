extends CharacterBody3D
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

const DANTE := preload("res://assets/dante.glb")
## Clipes da Universal Animation Library (CC0) retargetados para o esqueleto do Dante
## (`tools/retarget_ual_to_dante.gd`); entram como biblioteca "ual", sem tocar nos clipes originais.
const UAL_LIBRARY := "res://assets/animation_library/dante_ual.res"
## `ladder/Ladder_Descend`: o `Fast_Ladder_Climb` ao contrário (`tools/make_ladder_descend.gd`).
const LADDER_LIBRARY := "res://assets/animation_library/dante_ladder.res"
## Quedas da morte do Mixamo (`tools/retarget_mixamo_death_to_dante.gd`): biblioteca "mixamo" com
## death_left, death_right e death_forward. O quadril anda com a queda, então não é travado.
const MIXAMO_DEATH_LIBRARY := "res://assets/dante/mixamo/dante_mixamo_death.res"
## Sacar e guardar a espada (`tools/retarget_mixamo_sword_to_dante.gd`): biblioteca "mixsword" com
## withdraw_katana, sheathe_katana e sheathe_greatsword.
const MIXAMO_SWORD_LIBRARY := "res://assets/dante/mixamo/dante_mixamo_sword.res"
## Exercícios da academia Ferro Velho (mesma ferramenta, `-- --set=gym`): biblioteca "mixgym".
const MIXAMO_GYM_LIBRARY := "res://assets/dante/mixamo/dante_mixamo_gym.res"
## Entrar/sair do carro, puxar o motorista e levantar do chão (`tools/retarget_mixamo_vehicle_clips.gd`):
## biblioteca "mixveh" com enter_car, exit_car, pull_from_seat, getup_* e driving.
const MIXAMO_VEHICLE_LIBRARY := "res://assets/dante/mixamo/dante_mixamo_vehicle.res"
const LADDER_CLIPS := ["Fast_Ladder_Climb", "ladder/Ladder_Descend"]
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const BODY_CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const OUTFIT_APPEARANCE := preload("res://assets/outfits/MeshyDanteAppearance.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STEERING := preload("res://gameplay/crowd/PedestrianSteering.gd")
const STEP := preload("res://gameplay/crowd/PedestrianStep3D.gd")
const UMBRELLA := preload("res://gameplay/crowd/PedestrianUmbrella.gd")
## Civis longe da câmera, na rota própria ou em fuga/recuperação explicitamente
## autorizada pelo diretor, andam em passo de LOD: física a cada LOD_STRIDE quadros com o
## delta acumulado. Mantém rota e posição coerentes e corta ~2/3 do custo de move_and_slide + pose de quem não se vê.
const LOD_DISTANCE := 45.0
const LOD_STRIDE := 3
## Pedestre comum fora da tela anda a rota da calçada sem desvio, degrau nem move_and_slide, como o
## "dummy" do reVC. Ao entrar na tela volta à física no mesmo passo. GETECO_PED_DUMMY=0 desliga.
static var dummy_enabled := OS.get_environment("GETECO_PED_DUMMY") != "0"
const DUMMY_VIEW_MARGIN := 3.0
static var _dummy_frame := -1
static var _dummy_camera: Camera3D
static var _dummy_planes: Array[Plane] = []
var _steering: RefCounted
var _lod_delta := 0.0
## Velocidade pedida neste passo físico, passada de _tick_intent ao condutor do _stall_physics_tick.
var _intent_speed := 0.0
## Consulta de chuva do guarda-chuva, uma vez por segundo (escalonada pela identidade).
var _umbrella_clock := 0.0
var outfit_id := "dante_classic"
var outfit_material: ShaderMaterial
var is_player := false
var air_movement: RefCounted
var identity := 0
var camera: Camera3D
var visual: Node3D:
	set(value):
		visual = value
		_sync_pose_refs()
var animation: AnimationPlayer:
	set(value):
		animation = value
		_sync_pose_refs()
var skeleton: Skeleton3D:
	set(value):
		skeleton = value
		_sync_pose_refs()
var hips := -1
var hip_rest := Vector3.ZERO
var route := PackedVector3Array()
var waypoint := 0
var speed := 1.6
var automatic_direction := Vector3.ZERO
## Direção que o jogador pede neste passo físico (controle ou automática), mesmo
## quando uma parede zera a velocidade. Saídas por "empurrar" (escada do bueiro)
## leem isto: encostado na escada a velocidade é zero e a saída nunca disparava.
var move_intent := Vector3.ZERO
var controlled_automatically := false
var input_locked := false
var ski_controller
var health := 100.0
var dead := false
var travelled := 0.0
var phase := 0.0
var last_position := Vector3.ZERO
## Camada de apresentação de combate, ESCRITA por `Gameplay` e só lida aqui (nada decide dano).
## `combat_facing`: rumo visual forçado (rad, mesma convenção de `visual.rotation.y`); NAN = livre
## (a caminhada volta a girar o corpo). `combat_clip`/`combat_clip_time`: clipe do `dante.glb` a exibir no
## lugar de Walking/Running enquanto o nome não for vazio; a caminhada retoma sozinha ao esvaziar.
var combat_facing := NAN
var combat_clip := ""
var combat_clip_time := 0.0
## Postura de arma enquanto mira: "gun" (arma de fogo), "grenade" ou "" (mãos livres/corpo a corpo). Só vale com
## `combat_facing` ativo; escolhe a locomoção armada direcional.
var combat_stance := ""
## Alvos de empunhadura calculados por Gameplay/WeaponRigPose. São apresentação
## apenas: Gameplay resolve o dano no contato da ação.
var combat_weapon_pose: Dictionary = {}
var combat_weapon_id := ""
var combat_weapon_mount: Node3D
var combat_weapon_grip := Vector3.ZERO
var _reaction_tween: Tween
const FALL_TIME := 0.22
const FLINCH_ANGLE := 0.22
## Mistura curta entre locomoção e clipe de golpe (0 = só locomoção, 1 = só o clipe), tempo em `COMBAT_BLEND`.
var _combat_weight := 0.0
## Palmas da pose de locomoção/clipe, medidas antes de a camada de arma resolver os braços.
var _clip_palms := {}
var _last_clip := ""
var _last_clip_time := 0.0
## Pesos perceptivos equivalentes aos do Dante V1: a fase só avança com
## deslocamento real, enquanto o corpo entra/sai da passada suavemente.
var _locomotion_weight := 0.0
var _run_weight := 0.0
var _idle_pose: Array = []
var _combat_bones: Dictionary = {}:
	set(value):
		_combat_bones = value
		_sync_pose_refs()
var _combat_rests: Array[Transform3D] = []:
	set(value):
		_combat_rests = value
		_sync_pose_refs()
var _combat_skin: MeshInstance3D:
	set(value):
		_combat_skin = value
		_sync_pose_refs()
## Auxiliares de pose separados em 01/11 (Onda 3) só para este arquivo caber na leitura; o estado lido
## de fora continua aqui e cada função antiga delega em uma linha. Declarados depois das referências
## acima: o `_init` deles copia visual/skeleton/ossos/pele já inicializados (ver `_sync_pose_refs`).
const SEAT_POSE := preload("res://scripts/ActorSeatPose.gd")
var _seat_pose: SEAT_POSE = SEAT_POSE.new(self)
const LOCOMOTION_POSE := preload("res://scripts/ActorLocomotionPose.gd")
var _locomotion_pose: LOCOMOTION_POSE = LOCOMOTION_POSE.new(self)
const COMBAT_POSE := preload("res://scripts/ActorCombatPose.gd")
var _combat_pose: COMBAT_POSE = COMBAT_POSE.new(self)
var _idle_clock := 0.0
var _directional_weight := 0.0
var _gait_direction := Vector2(0, 1)
var _cycle_starts: Dictionary = {}
var _feet_yaw := 0.0
var _feet_initialized := false
var _turn_time := 1.0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_feet: Dictionary = {}
var _idle_feet: Dictionary = {}
var _hit_age := 1.0
# Mola do tronco do jogador ao ser atingido (x = para trás, y = lateral), aplicada
# nos ossos da coluna depois da pose. Antes o `visual` inteiro balançava pelos pés
# e reiniciava a cada tiro: com rajada o Dante tremia.
var _hit_lean := Vector2.ZERO
var _hit_lean_velocity := Vector2.ZERO
var _hit_lean_target := Vector2.ZERO
var _traversal_roots: Dictionary = {}
var _pose_delta := 1.0 / 60.0
var _elbow_previous: Dictionary = {}
## Torção do antebraço do quadro anterior por lado (pegada de taco/machado).
var _twist_previous: Dictionary = {}
## Duração da mistura de poses ao entrar e sair do clipe de golpe (não calibrada).
const COMBAT_BLEND := 0.08
const LOCOMOTION_BLEND_RATE := 7.0
## Katana na mão: parado, andando e correndo com os clipes da greatsword do Mixamo (Gameplay liga
## `sword_locomotion`). Os braços seguram a espada pelo próprio clipe (pegada nativa, como nos golpes).
## O prefixo vem de `sword_clip_set`: "gs" (greatsword, katana) ou "ss" (espada e escudo da serra).
const SWORD_IDLE := "mixsword/%s_idle"
const SWORD_WALK := "mixsword/%s_walk"
const SWORD_RUN := "mixsword/%s_run"
## Defesa com escudo parada: o clipe de bloqueio substitui a guarda (Gameplay liga `sword_block`).
const SHIELD_BLOCK_IDLE := "mixsword/ss_block_idle"
## Passada por ciclo (m) para travar a fase na distância. Natural, medido nos pés do Dante: Walk 1,61 m
## (1,18 m/s, ciclo de 1,37 s) e Run 2,69 m (4,48 m/s). Como o Walking comum (natural 1,46 m, tocado com
## 1,8 m a 3,5 m/s), a passada é ~25% maior que a natural: com a natural o Walk ciclaria 3× rápido demais.
const SWORD_WALK_STRIDE := 2.0
const SWORD_RUN_STRIDE := 2.8
var sword_locomotion := false
var sword_clip_set := "gs"
## Armas que tocam o próprio clipe do Mixamo (Gameplay.NATIVE_SWORDS).
const NATIVE_SWORDS := ["katana", "sword_shield"]
var sword_block := false
## Fôlego da academia (GymState.sprint_scale): multiplica só a velocidade da corrida.
var sprint_scale := 1.0
const RUN_BLEND_RATE := 4.5
const MOVING_SPEED_EPSILON := 0.12
const WALK_START := 0.067
## Os auxiliares de pose guardam cópias tipadas de visual, skeleton, _combat_bones, _combat_rests e
## _combat_skin para não ler `g.` dinâmico a cada osso. Os setters acima chamam isto a cada atribuição
## (o _ready, testes que montam o esqueleto à mão, quem troca o visual de fora); custo só na troca.
## `animation` (AnimationPlayer) também tem setter: ActorLocomotionPose o guarda tipado.
func _sync_pose_refs() -> void:
	if _seat_pose != null: _seat_pose.sync_refs()
	if _locomotion_pose != null: _locomotion_pose.sync_refs()
	if _combat_pose != null: _combat_pose.sync_refs()

func _ready() -> void:
	set_meta("gameplay_role","player" if is_player else "civilian")
	if not is_player: add_to_group("police_witness")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	if is_player:
		var model := DANTE.instantiate() as Node3D
		model.scale = Vector3.ONE * 1.03
		model.rotation.y = PI
		if has_meta("authored_female"):
			model.wardrobe_overrides["female"] = bool(get_meta("authored_female"))
		visual.add_child(model)
		animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation and not animation.has_animation_library("ual") and ResourceLoader.exists(UAL_LIBRARY):
			animation.add_animation_library("ual", load(UAL_LIBRARY))
		if animation and not animation.has_animation_library("ladder") and ResourceLoader.exists(LADDER_LIBRARY):
			animation.add_animation_library("ladder", load(LADDER_LIBRARY))
		if animation and not animation.has_animation_library("mixamo") and ResourceLoader.exists(MIXAMO_DEATH_LIBRARY):
			animation.add_animation_library("mixamo", load(MIXAMO_DEATH_LIBRARY))
		if animation and not animation.has_animation_library("mixsword") and ResourceLoader.exists(MIXAMO_SWORD_LIBRARY):
			animation.add_animation_library("mixsword", load(MIXAMO_SWORD_LIBRARY))
		if animation and not animation.has_animation_library("mixgym") and ResourceLoader.exists(MIXAMO_GYM_LIBRARY):
			animation.add_animation_library("mixgym", load(MIXAMO_GYM_LIBRARY))
		if animation and not animation.has_animation_library("mixveh") and ResourceLoader.exists(MIXAMO_VEHICLE_LIBRARY):
			animation.add_animation_library("mixveh", load(MIXAMO_VEHICLE_LIBRARY))
		skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton:
			hips = skeleton.find_bone("Hips")
			if hips >= 0: hip_rest = skeleton.get_bone_rest(hips).origin
			for bone_index in skeleton.get_bone_count():
				_combat_bones[skeleton.get_bone_name(bone_index)] = bone_index
				_combat_rests.append(skeleton.get_bone_rest(bone_index))
			_combat_skin = model.find_child("Mesh0", true, false) as MeshInstance3D
			# Punho do modelo deixa o polegar esticado; ver `DanteHandShapes`.
			if is_instance_valid(_combat_skin): _combat_skin.mesh = preload("res://scripts/DanteHandShapes.gd").fixed(_combat_skin.mesh)
		if animation:
			animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_build_idle_pose()
		set_outfit(outfit_id)
		air_movement = preload("res://gameplay/PlayerAirMovement.gd").new()
		air_movement.configure(self)
	else:
		var model := CIVILIAN.new()
		model.appearance_locked = true
		model.appearance_variant = identity
		model.coat_color = [Color("426c70"), Color("a35d42"), Color("d3c3a1"), Color("42556f"), Color("8e5362"), Color("70835d")][identity % 6]
		model.pants_color = [Color("293849"), Color("484644"), Color("615342")][identity % 3]
		# Pela posição também: quem desce de um carro herda o `region_id` do carro, que pode estar defasado.
		if get_meta("region_id", "") == "mountain" or (get_meta("region_id", "") != "desert" \
				and WORLD_CONNECTION.logical_region(global_position) == "mountain"):
			model.wardrobe_overrides = CIVILIAN.WINTER_WARDROBE.duplicate()
		model.rotation.y = PI
		# Corpo importado do Meshy para o pedestre genérico; sem entrada compatível (ou com guarda-roupa fixo, como
		# na montanha) continua o corpo procedural do kit.
		BODY_CATALOG.apply(model, identity)
		visual.add_child(model)
	last_position = global_position

## A apresentação consulta o dono do controle sem alterar o LOD da física existente.
func pedestrian_pose_requires_full_update() -> bool:
	return is_player or dead or input_locked or controlled_automatically \
		or not is_nan(combat_facing) or combat_clip != "" or not combat_weapon_pose.is_empty() \
		or (_reaction_tween != null and _reaction_tween.is_running()) \
		or has_meta("workplace_threatened") or has_meta("street_pose_owned") \
		or has_meta("street_down") or has_meta("street_flying")

func _can_walk_as_dummy() -> bool:
	if is_player or route.size() < 2 or air_movement != null or not is_on_floor(): return false
	if pedestrian_pose_requires_full_update() or has_meta(&"civilian_reaction_lod"): return false
	var view_camera := get_viewport().get_camera_3d()
	if view_camera == null: return false
	if _dummy_frame != Engine.get_physics_frames() or _dummy_camera != view_camera:
		_dummy_frame = Engine.get_physics_frames()
		_dummy_camera = view_camera
		_dummy_planes = view_camera.get_frustum()
	# Fora da tela só quando o corpo inteiro, com margem, está além de algum plano do quadro.
	var center := global_position + Vector3.UP
	for plane in _dummy_planes:
		if plane.distance_to(center) > DUMMY_VIEW_MARGIN: return true
	return false

func _walk_as_dummy(delta: float) -> void:
	var previous := route[(waypoint - 1 + route.size()) % route.size()]
	var target := STEERING.lane_point(previous, route[waypoint])
	var offset := target - global_position
	offset.y = 0
	if offset.length() < 0.5:
		waypoint = (waypoint + 1) % route.size()
		previous = route[(waypoint - 1 + route.size()) % route.size()]
		target = STEERING.lane_point(previous, route[waypoint])
		offset = target - global_position
		offset.y = 0
	var distance := offset.length()
	if distance < 0.001: return
	var direction := offset / distance
	var next := global_position + direction * minf(speed * delta, distance)
	# Rampa ou escada da rota: acompanha a altura do trecho para não voltar à física enterrado.
	var along := Vector3(target.x - previous.x, 0, target.z - previous.z)
	if absf(target.y - previous.y) > 0.05 and along.length_squared() > 0.01:
		var t := clampf(Vector3(next.x - previous.x, 0, next.z - previous.z).dot(along) / along.length_squared(), 0.0, 1.0)
		next.y = lerpf(previous.y, target.y, t)
	global_position = next
	velocity = direction * speed
	var displacement := global_position - last_position
	displacement.y = 0
	travelled += displacement.length()
	last_position = global_position
	visual.rotation.y = atan2(-direction.x, -direction.z)

func _physics_process(delta: float) -> void:
	var began := STALL_WORK.begin()
	_stall_physics_tick(delta)
	STALL_WORK.finish_slow("actor.physics", began, 10000, self)

func _stall_physics_tick(delta: float) -> void:
	if not is_player:
		_umbrella_clock -= delta
		if _umbrella_clock <= 0.0:
			_umbrella_clock = 1.0 + 0.1 * float(posmod(identity, 7))
			if is_instance_valid(visual) and visual.get_child_count() > 0: UMBRELLA.update(self, visual.get_child(0), identity)
	var rage_speed := float(get_meta("katana_rage_speed", 1.0)) if is_player else 1.0
	delta *= rage_speed
	var lod_scale := 1.0
	if not is_player and (not controlled_automatically or get_meta(&"civilian_reaction_lod", false)):
		var view_camera := get_viewport().get_camera_3d()
		if view_camera != null and view_camera.global_position.distance_squared_to(global_position) > LOD_DISTANCE * LOD_DISTANCE:
			_lod_delta += delta
			# Identidades estáveis distribuem a multidão; o primeiro tiro não
			# sincroniza todos os move_and_slide no mesmo terceiro passo físico.
			if (Engine.get_physics_frames() + identity) % LOD_STRIDE != 0: return
			lod_scale = _lod_delta / maxf(delta, 0.0001)
			delta = _lod_delta
	# Inclui a saída do LOD por outro dono de controle/câmera próxima; não deixa
	# delta antigo reaparecer quando esse civil voltar a ficar distante.
	_lod_delta = 0.0
	if dummy_enabled and _can_walk_as_dummy():
		_walk_as_dummy(delta)
		return
	var direction := _tick_intent(delta)
	var target_speed := _intent_speed
	_tick_move(delta, direction, target_speed, lod_scale, rage_speed)
	# _tick_move sai antes do fim só quando a queda do salto matou o jogador (after_move): aí não há pose.
	if dead and air_movement != null: return
	_tick_pose(delta, direction, target_speed)

## Etapa da intenção: direção pedida (automática, controle com a câmera ou rota da calçada com desvio),
## esqui, embriaguez, contenção da polícia e passo de mira. Devolve a direção; a velocidade fica em
## `_intent_speed` (o mesmo passo físico, sem alocar).
func _tick_intent(delta: float) -> Vector3:
	var direction := Vector3.ZERO
	var target_speed := speed
	if controlled_automatically:
		direction = automatic_direction
	elif is_player:
		var axis: Vector2 = get_node("/root/GameInput").movement()
		if camera:
			var right := camera.global_basis.x
			var back := camera.global_basis.z
			right.y = 0
			back.y = 0
			direction = (right.normalized() * axis.x + back.normalized() * axis.y).limit_length()
		# Corrida pelo `GameInput`: no controle é alternável (`sprint_toggled`), no teclado é segurar.
		target_speed = 6.5 * sprint_scale if get_node("/root/GameInput").sprinting() else 3.5
	elif route.size() > 1:
		# Mira a faixa da direita do trecho, não o eixo: quem vem no sentido oposto usa a outra faixa.
		var previous := route[(waypoint - 1 + route.size()) % route.size()]
		var offset := STEERING.lane_point(previous, route[waypoint]) - global_position
		offset.y = 0
		if offset.length() < 0.5:
			waypoint = (waypoint + 1) % route.size()
			offset = STEERING.lane_point(route[(waypoint - 1 + route.size()) % route.size()], route[waypoint]) - global_position
			offset.y = 0
		direction = offset.normalized()
	if not is_player and direction.length_squared() > 0.01:
		if _steering == null: _steering = STEERING.new()
		var steering_began := STALL_WORK.begin() if STALL_WORK.aggregate_enabled or STALL_WORK.session_enabled else 0
		direction = _steering.steer(self, direction, delta)
		if steering_began != 0: STALL_WORK.finish_slow("actor.steering",steering_began,10000,self)
		# Travou de verdade na rota própria: desiste deste ponto e segue para o próximo (volta pela calçada).
		if _steering.stuck and not controlled_automatically and route.size() > 1:
			waypoint = (waypoint + 1) % route.size()
	if is_player and not input_locked and is_instance_valid(ski_controller) and ski_controller.skiing:
		var motion: Vector3 = ski_controller.motion(delta,direction)
		direction = motion.normalized()
		target_speed = motion.length()
	if input_locked: direction = Vector3.ZERO
	# Intoxication alters voluntary movement through the real swept capsule.
	if is_player and not input_locked and not controlled_automatically and not (is_instance_valid(ski_controller) and ski_controller.skiing):
		var intoxication := clampf(float(get_meta("alcohol_intensity",0.0)),0.0,1.0)
		if intoxication > 0.0:
			direction = direction.rotated(Vector3.UP,float(get_meta("alcohol_sway",0.0)) * intoxication * .14)
			target_speed *= 1.0 - intoxication * .22
	if is_player and has_meta("police_restraint_left"):
		var restraint := maxf(0.0, float(get_meta("police_restraint_left")) - delta)
		if restraint <= 0.0: remove_meta("police_restraint_left")
		else:
			set_meta("police_restraint_left", restraint)
			target_speed *= 0.35
	if is_player and not is_nan(combat_facing) and direction.length_squared() > 0.001:
		if combat_stance == "melee":
			# Olhar para o cursor não põe uma lâmina na caminhada firme da arma de fogo.
			# O Gameplay cuida da fase curta comprometida; recuperação/guarda usam 1.0.
			target_speed *= clampf(float(get_meta("melee_movement_scale", 1.0)), 0.0, 1.0)
		else:
			# Um passo firme para trás/de lado não é uma corrida para frente tocada ao contrário.
			# Ajusta o deslocamento real à passada dos clipes direcionais nativos.
			var forward := Vector3(-sin(combat_facing), 0, -cos(combat_facing))
			var alignment := direction.normalized().dot(forward)
			var combat_speed := lerpf(2.3, 2.4 if alignment < 0.0 else 3.2, absf(alignment))
			target_speed = minf(target_speed, combat_speed)
	if is_player: target_speed *= float(get_meta("developer_speed_multiplier", 1.0))
	_intent_speed = target_speed
	return direction

## Etapa do deslocamento: velocidade varrida, salto/queda, degrau e move_and_slide.
func _tick_move(delta: float, direction: Vector3, target_speed: float, lod_scale: float, rage_speed: float) -> void:
	move_intent = direction
	velocity.x = direction.x * target_speed * lod_scale
	velocity.z = direction.z * target_speed * lod_scale
	# O snap de chão mantém o apoio no plano e nas descidas. Empurrar para baixo uma
	# cápsula já no chão repete colisões de piso em cada tick de caminhada.
	if air_movement != null:
		air_movement.before_move(delta, direction)
	else:
		velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	var step_began := STALL_WORK.begin() if STALL_WORK.aggregate_enabled or STALL_WORK.session_enabled else 0
	if air_movement == null or air_movement.phase == "ground": STEP.try_step(self, Vector3(velocity.x, 0, velocity.z) * (delta / lod_scale))
	if step_began != 0: STALL_WORK.finish_slow("actor.step",step_began,10000,self)
	var move_began := STALL_WORK.begin()
	# move_and_slide lê o delta do motor internamente. Compensa só a velocidade varrida
	# do jogador e depois restaura as unidades físicas para câmera, passos e combate.
	velocity *= rage_speed
	move_and_slide()
	velocity /= rage_speed
	if air_movement != null:
		air_movement.after_move()
		if dead: return
	STALL_WORK.finish_slow("actor.move_and_slide", move_began, 10000, self)
	if lod_scale != 1.0:
		velocity.x /= lod_scale
		velocity.z /= lod_scale

## Etapa da apresentação: distância andada, rumo do visual e a pose (locomoção, golpe, arma).
func _tick_pose(delta: float, direction: Vector3, target_speed: float) -> void:
	var displacement := global_position - last_position
	displacement.y = 0
	travelled += displacement.length()
	var actual_speed := displacement.length() / maxf(delta, 0.001)
	last_position = global_position
	var pose_began := STALL_WORK.begin() if STALL_WORK.aggregate_enabled or STALL_WORK.session_enabled else 0
	if direction.length_squared() > 0.01 and (not is_player or is_nan(combat_facing)):
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-14.0 * delta))
	# Mirando/atacando, o corpo segue o rumo do disparo, não o do movimento.
	if is_player and not is_nan(combat_facing):
		visual.rotation.y = rotate_toward(visual.rotation.y, combat_facing, delta * 24.0)
	if animation:
		# Camada de combate: o clipe de golpe entra e sai com uma mistura curta de poses (nada de corte seco); sem
		# clipe, só locomoção. A pose é sempre escolhida aqui; `Gameplay` só informa clipe e tempo.
		var combat_wanted := is_player and combat_clip != "" and animation.has_animation(combat_clip)
		var sword_legs := {}
		if combat_wanted and combat_weapon_id in NATIVE_SWORDS and actual_speed > MOVING_SPEED_EPSILON:
			_pose_locomotion(direction, target_speed, displacement, actual_speed, delta)
			for bone_name in ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]:
				var index := skeleton.find_bone(bone_name)
				if index >= 0: sword_legs[index] = skeleton.get_bone_pose(index)
		if combat_wanted:
			_last_clip = combat_clip
			_last_clip_time = combat_clip_time
		_combat_weight = move_toward(_combat_weight, 1.0 if combat_wanted else 0.0, delta / COMBAT_BLEND)
		if air_movement != null and air_movement.pose():
			_combat_weight = 0.0
		elif _combat_weight <= 0.0:
			_pose_locomotion(direction, target_speed, displacement, actual_speed, delta)
		elif _combat_weight >= 1.0:
			_pose_clip(_last_clip, _last_clip_time)
		elif is_instance_valid(skeleton):
			_pose_locomotion(direction, target_speed, displacement, actual_speed, delta)
			var locomotion_pose := _capture_pose()
			_pose_clip(_last_clip, _last_clip_time)
			_apply_blend(locomotion_pose, _capture_pose(), _combat_weight)
		else:
			_pose_locomotion(direction, target_speed, displacement, actual_speed, delta)
		for index in sword_legs: skeleton.set_bone_pose(index, sword_legs[index])
		if is_player: _clip_palms = {"Left": _clip_palm("Left"), "Right": _clip_palm("Right")}
		if hips >= 0:
			var hip_position := skeleton.get_bone_pose_position(hips)
			hip_position.x = hip_rest.x
			hip_position.z = hip_rest.z
			skeleton.set_bone_pose_position(hips, hip_position)
		if is_player:
			_hit_age += delta
			visual.rotation.x = 0.0
			_apply_hit_lean(delta)
			if air_movement == null or air_movement.phase == "ground": _apply_combat_weapon_pose()
	else:
		if visual.get_child(0).get("walking") != null: visual.get_child(0).walking = actual_speed > 0.1
	if pose_began != 0: STALL_WORK.finish_slow("actor.pose",pose_began,10000,self)

func _pose_locomotion(direction: Vector3, _target_speed: float, displacement: Vector3, actual_speed: float, delta: float = 1.0 / 60.0) -> void: _locomotion_pose._pose_locomotion(direction, _target_speed, displacement, actual_speed, delta)

func has_sword_locomotion() -> bool: return _locomotion_pose.has_sword_locomotion()

func _pose_sword_idle() -> void: _locomotion_pose._pose_sword_idle()

func _build_idle_pose() -> void: _locomotion_pose._build_idle_pose()

func _pose_cycle(clip: String, normalized_phase: float, start: float) -> void: _locomotion_pose._pose_cycle(clip, normalized_phase, start)

func _mirror_current_pose() -> void: _locomotion_pose._mirror_current_pose()

func _apply_idle_breath() -> void: _locomotion_pose._apply_idle_breath()

func _pose_turn(delta: float, moving: bool) -> void: _locomotion_pose._pose_turn(delta, moving)

func _solve_leg(side: String, world_foot: Vector3) -> void: _locomotion_pose._solve_leg(side, world_foot)

func _apply_pose(pose: Array) -> void: _locomotion_pose._apply_pose(pose)

func _pose_clip(clip: String, time: float) -> void: _locomotion_pose._pose_clip(clip, time)

func pose_vehicle(sitting: float, stepping: float = 0.0, side: int = -1, reach: float = 1.0, handlebars: Dictionary = {}) -> void: _seat_pose.pose_vehicle(sitting, stepping, side, reach, handlebars)

func _fit_motorcycle_reach(handlebars: Dictionary) -> void: _seat_pose._fit_motorcycle_reach(handlebars)

## Motorista sentado (carro, picape, caminhão, ônibus, buggy, empilhadeira). Aditivo: a
## moto continua em `pose_vehicle` com guidão. `VehicleInterior` decide onde o Actor fica e
## quais são os alvos; aqui só se reclina o tronco e se resolve a perna/braço a cada alvo.
var seated := false

func pose_seated_base(recline: float) -> Vector3: return _seat_pose.pose_seated_base(recline)

func pose_seated_limbs(feet: Dictionary, hands: Dictionary) -> void: _seat_pose.pose_seated_limbs(feet, hands)

func pose_motorcycle_foot(weight: float, ground_y: float) -> void: _seat_pose.pose_motorcycle_foot(weight, ground_y)

func pose_driver_lean(lean: float) -> void: _seat_pose.pose_driver_lean(lean)

func pose_driver_look(look: float) -> void: _seat_pose.pose_driver_look(look)

func release_seated(keep_yaw := false) -> void: _seat_pose.release_seated(keep_yaw)

func _capture_pose() -> Array:
	var pose: Array = []
	for bone in skeleton.get_bone_count(): pose.append([skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone), skeleton.get_bone_pose_scale(bone)])
	return pose

func _apply_blend(from_pose: Array, to_pose: Array, weight: float) -> void:
	for bone in from_pose.size():
		skeleton.set_bone_pose_position(bone, (from_pose[bone][0] as Vector3).lerp(to_pose[bone][0], weight))
		skeleton.set_bone_pose_rotation(bone, (from_pose[bone][1] as Quaternion).slerp(to_pose[bone][1], weight))
		skeleton.set_bone_pose_scale(bone, (from_pose[bone][2] as Vector3).lerp(to_pose[bone][2], weight))

func set_combat_weapon_pose(id: String, pose: Dictionary) -> void: _combat_pose.set_combat_weapon_pose(id, pose)

func set_combat_weapon_mount(node: Node3D, grip: Vector3) -> void:
	combat_weapon_mount = node
	combat_weapon_grip = grip

func clear_combat_weapon_pose() -> void:
	combat_weapon_id = ""
	combat_weapon_pose = {}

func _two_hand_sword_transform(grip: Transform3D) -> Transform3D: return _combat_pose._two_hand_sword_transform(grip)

func _sword_switch_transform() -> Transform3D: return _combat_pose._sword_switch_transform()

func _sword_switch_length() -> float: return _combat_pose._sword_switch_length()

func _sword_switching() -> bool: return _combat_pose._sword_switching()

func _track_sword_switch(native: bool) -> void: _combat_pose._track_sword_switch(native)

func _present_native_sword_arms() -> void: _combat_pose._present_native_sword_arms()

func _apply_combat_weapon_pose() -> void: _combat_pose._apply_combat_weapon_pose()

func _stabilize_combat_pose() -> void: _combat_pose._stabilize_combat_pose()

func _protract_clavicle(side: String) -> void: _combat_pose._protract_clavicle(side)

func _blend_arm_bone(bone: int, clip: Quaternion, weight: float) -> void: _combat_pose._blend_arm_bone(bone, clip, weight)

func _set_combat_grips(right: bool, left: bool, right_fist := false, left_fist := false, right_relaxed := false, left_relaxed := false) -> void: _combat_pose._set_combat_grips(right, left, right_fist, left_fist, right_relaxed, left_relaxed)

const FREE_ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]

func _solve_combat_arm(side: String, target_local: Vector3, palm_basis_local: Basis, _gripping: bool, sign_side: float, _free_weight: float = 0.0) -> void: _combat_pose._solve_combat_arm(side, target_local, palm_basis_local, _gripping, sign_side, _free_weight)

func _grip_hand_basis(hand: int, handle: Vector3, fingers: Vector3) -> Basis: return _combat_pose._grip_hand_basis(hand, handle, fingers)

func _combat_hand_tip(hand: int) -> Vector3: return _combat_pose._combat_hand_tip(hand)

func _orient_arm_segment(bone: int, child: int, direction: Vector3, plane: Vector3, rest_plane: Vector3) -> void: _combat_pose._orient_arm_segment(bone, child, direction, plane, rest_plane)

func _point_combat_bone(bone: int, child: int, target: Vector3) -> void: _combat_pose._point_combat_bone(bone, child, target)

func _set_combat_bone_rotation(bone: int, p_global_rotation: Basis) -> void: _combat_pose._set_combat_bone_rotation(bone, p_global_rotation)

func _clip_palm(side: String) -> Vector3: return _combat_pose._clip_palm(side)

func combat_palm_position(side: String) -> Vector3: return _combat_pose.combat_palm_position(side)

func combat_realized_palm_basis(side: String) -> Basis: return _combat_pose.combat_realized_palm_basis(side)

func combat_weapon_transform(grip: Vector3) -> Transform3D: return _combat_pose.combat_weapon_transform(grip)

func combat_left_palm_transform() -> Transform3D: return _combat_pose.combat_left_palm_transform()

func combat_rig_info() -> Dictionary: return _combat_pose.combat_rig_info()

func teleport(point: Vector3) -> void:
	release_seated()
	global_position = point
	if air_movement != null: air_movement.reset()
	last_position = point
	velocity = Vector3.ZERO
	_feet_initialized = false
	_turn_time = -1.0
	_turn_feet.clear()
	reset_physics_interpolation()

func set_outfit(id: String) -> bool:
	if not is_player or not OUTFIT_APPEARANCE.OUTFITS.has(id): return false
	if not is_instance_valid(skeleton):
		outfit_id = id
		return true
	var skin_mesh := visual.find_child("Mesh0", true, false) as MeshInstance3D
	if skin_mesh == null: return false
	outfit_material = OUTFIT_APPEARANCE.apply(skin_mesh, skeleton, id)
	outfit_id = id
	return outfit_material != null

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or amount <= 0: return
	# Alvo marcado (ele ou um ancestral) não sofre dano por nenhum caminho direto.
	if PROTECTION.is_protected(self): return
	if is_player:
		var branch_gameplay = get_parent().get("gameplay")
		var from: Vector3 = (source as Node3D).global_position if source is Node3D else Vector3.INF
		if branch_gameplay: branch_gameplay.damage_player(amount, from)
		return
	var vehicle_source: bool = is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source()
	health = maxf(0,health-amount)
	if health <= 0:
		dead = true
		if has_meta("v2_burning"):
			preload("res://gameplay/BurningActor.gd").char_body(self)
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		var impact_dir: Vector3 = (global_position - (source as Node3D).global_position).normalized() if source is Node3D else Vector3.ZERO
		_fall_over(impact_dir)
	else:
		var push: Vector3 = (global_position - (source as Node3D).global_position) if source is Node3D else Vector3.ZERO
		_flinch(push, amount)
	var gameplay = get_parent().get("gameplay")
	if dead and gameplay and gameplay.has_method("drop_cash"): gameplay.drop_cash(self)
	# A autoria continua no veículo real. A denúncia só é encaminhada depois de
	# `dead` refletir o resultado deste impacto, inclusive no golpe fatal.
	if vehicle_source:
		if gameplay and gameplay.has_method("report_vehicle_assault"): gameplay.report_vehicle_assault(self,source)
		elif gameplay: gameplay.register_crime(25,global_position)
	if gameplay and gameplay.get("emergency") != null: gameplay.emergency.report_injury(self,dead)

## Queda com articulação de membros, rotação direcional e quique suave no solo (V1).
func _fall_over(impact := Vector3.ZERO) -> void:
	if not is_instance_valid(visual): return
	if not is_player: UMBRELLA.drop(self, impact)
	if _reaction_tween != null: _reaction_tween.kill()
	preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact)

## Morte do jogador: alterna entre o clipe do Dante e `ual/Death01` (a queda de costas da UAL).
## `variant` fixa a escolha (testes e capturas); -1 sorteia.
## `push` é a direção em que o golpe empurra o corpo (do atacante para o jogador). Sem direção,
## o sorteio antigo continua valendo.
var last_death_clip := ""

func present_fall_death() -> void:
	if _reaction_tween != null: _reaction_tween.kill()
	clear_combat_weapon_pose()
	if animation != null and animation.has_animation("mixamo/death_forward"):
		last_death_clip = "mixamo/death_forward"
		_pose_clip(last_death_clip, animation.get_animation(last_death_clip).length)
	visual.rotation.x = 0.0
	visual.rotation.z = 0.0

func on_player_death(variant := -1, push := Vector3.ZERO) -> void:
	if dead: return
	dead = true
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	var death_clip := "dying_backwards"
	var directional := _directional_death_clip(push)
	if not directional.is_empty():
		death_clip = directional
	elif (variant if variant >= 0 else randi() % 2) == 1 and animation != null and animation.has_animation("ual/Death01"): death_clip = "ual/Death01"
	# Clipes do Mixamo levam o quadril junto com a queda; os antigos ficam presos ao lugar.
	var lock_hips := not death_clip.begins_with("mixamo/")
	last_death_clip = death_clip
	if animation != null and animation.has_animation(death_clip):
		if _reaction_tween != null: _reaction_tween.kill()
		var from_pose := _capture_pose()
		clear_combat_weapon_pose()
		visual.rotation.x = 0.0
		_reaction_tween = create_tween()
		_reaction_tween.tween_method(func(time: float):
			_pose_clip(death_clip, time)
			if time < 0.20: _apply_blend(from_pose, _capture_pose(), smoothstep(0, 0.20, time))
			if not lock_hips: return
			var hip := skeleton.get_bone_pose_position(hips)
			hip.x = hip_rest.x
			hip.z = hip_rest.z
			skeleton.set_bone_pose_position(hips, hip)
		, 0.0, animation.get_animation(death_clip).length, animation.get_animation(death_clip).length)
	else:
		_fall_over(Vector3.BACK)

## Queda pelo lado do empurrão, no referencial do modelo (rosto em +z, esquerda do Dante em +x,
## medidos nos ossos de repouso e na queda de `dying_backwards`). Vazio = sem clipe direcional.
func _directional_death_clip(push: Vector3) -> String:
	if animation == null or skeleton == null: return ""
	var flat := Vector3(push.x, 0.0, push.z)
	if flat.length_squared() < 0.0001: return ""
	var local := skeleton.global_transform.basis.inverse() * flat.normalized()
	var clip := ""
	if absf(local.z) >= absf(local.x):
		clip = "mixamo/death_forward" if local.z > 0.0 else "dying_backwards"
	else:
		clip = "mixamo/death_left" if local.x > 0.0 else "mixamo/death_right"
	return clip if animation.has_animation(clip) else ""

func present_hit() -> void:
	if not is_player or dead: return
	_hit_age = 0.0
	# Mesmo esquema do civil (CivilianModel.take_hit): alvo que decai + mola sem oscilação.
	var room := 1.0 - clampf(_hit_lean_target.length() / 0.22, 0.0, 1.0)
	_hit_lean_target = (_hit_lean_target + Vector2(0.13, randf_range(-0.05, 0.05)) * room).limit_length(0.22)

func _apply_hit_lean(delta: float) -> void:
	if _hit_lean == Vector2.ZERO and _hit_lean_velocity == Vector2.ZERO and _hit_lean_target == Vector2.ZERO: return
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var dt := minf(remaining, 1.0 / 120.0)
		_hit_lean_target *= exp(-dt / 0.3)
		_hit_lean_velocity += (100.0 * (_hit_lean_target - _hit_lean) - 20.0 * _hit_lean_velocity) * dt
		_hit_lean += _hit_lean_velocity * dt
		remaining -= dt
	if _hit_lean_target.length_squared() < 0.000001 and _hit_lean.length_squared() < 0.000001 and _hit_lean_velocity.length_squared() < 0.0001:
		_hit_lean = Vector2.ZERO
		_hit_lean_velocity = Vector2.ZERO
		_hit_lean_target = Vector2.ZERO
		return
	if not is_instance_valid(skeleton): return
	# Eixos do personagem no espaço do esqueleto (o modelo é girado 180°).
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	var right := (to_skeleton * visual.global_basis.x).normalized()
	var forward := (to_skeleton * -visual.global_basis.z).normalized()
	# Divide a curva entre a lombar e o peito: um osso só dobrava em quina.
	for entry in [["Spine01", 0.45], ["Spine02", 0.55]]:
		var bone: int = _combat_bones.get(entry[0], -1)
		if bone < 0: continue
		var weight: float = entry[1]
		var turn := Basis(right, _hit_lean.x * weight) * Basis(forward, _hit_lean.y * weight)
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		var local := parent_basis.inverse() * turn * parent_basis
		skeleton.set_bone_pose_rotation(bone, (Quaternion(local) * skeleton.get_bone_pose_rotation(bone)).normalized())

func respawn_player() -> void:
	if not is_player: return
	if air_movement != null: air_movement.reset()
	dead = false
	health = 100.0
	if _reaction_tween != null: _reaction_tween.kill()
	visual.position = Vector3.ZERO
	visual.rotation.x = 0.0
	visual.rotation.z = 0.0
	if animation != null and not _idle_pose.is_empty():
		animation.play("Walking")
		_apply_pose(_idle_pose)
	clear_combat_weapon_pose()
	_hit_age = 1.0
	_hit_lean = Vector2.ZERO
	_hit_lean_velocity = Vector2.ZERO
	_hit_lean_target = Vector2.ZERO
	_combat_pose.clear_presented_arms()
	_feet_initialized = false
	_turn_feet.clear()
	_locomotion_weight = 0.0
	_run_weight = 0.0
	_directional_weight = 0.0
	last_position = global_position
	velocity = Vector3.ZERO

## Reação ao ferimento, só apresentação (o dano já foi aplicado acima). O tronco
## do modelo recebe um impulso no sentido do tiro; o corpo inteiro não gira mais.
func _flinch(push: Vector3 = Vector3.ZERO, amount: float = 20.0) -> void:
	if not is_instance_valid(visual) or is_player: return
	var model := visual.get_child(0) if visual.get_child_count() > 0 else null
	if push.length_squared() < 0.0001: push = -visual.global_basis.z
	if model != null and model.has_method("take_hit"):
		model.take_hit(push, clampf(amount / 35.0, 0.3, 1.0))
		return
	if _reaction_tween != null: _reaction_tween.kill()
	_reaction_tween = create_tween()
	_reaction_tween.tween_property(visual, "rotation:x", -FLINCH_ANGLE * 0.5, 0.08).set_ease(Tween.EASE_OUT)
	_reaction_tween.tween_property(visual, "rotation:x", 0.0, 0.25).set_ease(Tween.EASE_IN_OUT)

func recover_from_injury() -> void:
	if dead: return
	health = maxf(health,60)
