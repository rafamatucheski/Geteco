extends "res://assets/CivilianBase.gd"
## Pedestre civil articulado, na escala do Dante (~1,76 m).
##
## Esqueleto: pelve → tronco → cabeça; ombro → cotovelo; quadril → joelho →
## tornozelo. Cada articulação é uma MeshInstance3D com malha lisa do
## `CivilianMeshKit`; a cor de cada peça vem de `instance uniform`, então a
## multidão inteira divide poucas malhas e um material.
##
## Locomoção procedural, sem clipe: a fase do passo avança pela distância
## REALMENTE percorrida (como o Dante em `Actor._pose_locomotion`), e o pé de
## apoio fica plantado no chão via IK de duas barras, com rolamento
## calcanhar → planta → ponta. Nada disso lê a física do `Actor`: o modelo mede o
## próprio deslocamento global, então funciona igual sob `Actor`, rotinas V1 ou
## qualquer pai que o mova.
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")

var appearance_locked := false
var motorcycle_helmet_color := Color.TRANSPARENT
var pants_color := Color("33465c")
## `V1RoutineActor` escreve a atividade ("carry", "talk", ...); só apresentação.
var activity := ""
## Subclasses (estivador) fixam peças do guarda-roupa antes de `_ready`.
var wardrobe_overrides: Dictionary = {}
var wardrobe: Dictionary = {}
## Alvos globais das mãos [lado -X do corpo, lado +X]; null = braço livre. Quem
## segura arma ou maca (polícia, socorristas) escreve aqui a cada quadro e o
## braço vai até lá por IK, por cima da passada.
var hand_targets: Array = [null, null]
## false = pose todo quadro. NPC com arma precisa: a arma se move todo quadro.
var lod_enabled := true
## Sentado (0..1) num assento a `seat_height` metros do chão, como o
## `WinterResidentModel.set_seat_pose` dos moradores da montanha.
var sit_amount := 0.0
var seat_height := 0.45
## Alternativa a escrever `hand_targets`: chamado a cada pose, devolve [alvo0, alvo1].
var hand_provider: Callable

var pelvis: MeshInstance3D
var spine: MeshInstance3D
var head_node: MeshInstance3D
var thighs: Array[MeshInstance3D] = []
var shins: Array[MeshInstance3D] = []
var feet: Array[MeshInstance3D] = []
var upper_arms: Array[MeshInstance3D] = []
var forearms: Array[MeshInstance3D] = []
var _joints: Array[MeshInstance3D] = []
var _rest: Dictionary = {}
var _hip_offsets: Array[Vector3] = []
var _shoulders: Array[Vector3] = []
var _idle_stance: Array[Vector3] = []

# Estado da locomoção.
var _phase := 0.0
var _speed := 0.0
var _move_w := 0.0
var _run_w := 0.0
var _travel := 0.0
var _last_position := Vector3.INF
var _pending := 0.0
var _frame := 0
var _stagger := 0
var _seed := 0.0
var _look := 0.0
var _look_target := 0.0
var _look_timer := 0.0
var _talk_w := 0.0
var _carry_w := 0.0
var _owner_actor: Node

const PELVIS_Y := 0.94
const HIP_DROP := -0.04
const SPINE_OFFSET := Vector3(0, 0.12, 0)
const NECK := Vector3(0, 0.40, 0)
const SHOULDER_Y := 0.335
const HEEL := -0.055
const BALL := 0.135
## Proporção da varredura do pé de apoio coberta pela passada. Abaixo de 1 o pé
## escorrega um pouco para a frente no apoio; em 1 o quadril precisaria descer
## ~9 cm no contato do calcanhar para a perna alcançar (medido com o IK abaixo).
const REACH_SHARE := 0.92

const SKINS := [Color("f1c7a5"), Color("e0ac86"), Color("c89272"), Color("b97d5d"), Color("9f684e"), Color("7e4e38"), Color("5e3a2a"), Color("d8a07a")]
const HAIRS := [Color("1b1714"), Color("2b211b"), Color("47311f"), Color("6b4931"), Color("8a6a43"), Color("b8955e"), Color("8f8b86"), Color("7a3a22")]
const INNERS := [Color("ecebe4"), Color("c9ccd0"), Color("26272b"), Color("2f3d57"), Color("a9c1d9"), Color("e8dcc0"), Color("c89b3c"), Color("c98f8f")]
const SNEAKERS := [Color("e9e7e1"), Color("26272b"), Color("7d8187"), Color("2c3a5a"), Color("a13b32"), Color("d5c7a4")]
const BOOTS := [Color("5a3b26"), Color("3a2a20"), Color("24211f"), Color("7a5a3a")]
const DRESS_SHOES := [Color("1d1b1a"), Color("3b2619"), Color("4a3a30")]
const ACCENTS := [Color("222326"), Color("8b5a33"), Color("2c3d5e"), Color("9c3129"), Color("56603b"), Color("6f7174"), Color("c49a3a"), Color("5b3a5e")]

func _ready() -> void:
	var identity := appearance_variant if appearance_locked else randi_range(0, 119)
	appearance_variant = identity
	if not appearance_locked:
		coat_color = [Color("39835a"),Color("7d6e53"),Color("485b70"),Color("77524d"),Color("b7a784"),Color("743b54"),Color("c2c4b7"),Color("263d61"),Color("ad6940"),Color("536742"),Color("483943"),Color("77918c")][posmod(identity, 12)]
		pants_color = [Color("33465c"),Color("292a30"),Color("67594a"),Color("48554a"),Color("827c6c"),Color("394052")][posmod(identity / 3, 6)]
	_choose_wardrobe(identity)
	_build_rig()
	_apply_colors()
	_stagger = posmod(identity * 7, 8)
	_seed = float(posmod(identity * 131, 997)) * 0.37
	_look_timer = fposmod(_seed, 3.0)
	var node := get_parent()
	for i in 3:
		if node == null: break
		if node.get("dead") != null:
			_owner_actor = node
			break
		node = node.get_parent()
	_pose(0.0)

# --- Aparência ----------------------------------------------------------------

func _choose_wardrobe(identity: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = identity * 7919 + 104729
	var female := rng.randf() < 0.5
	var w := {}
	w.female = female
	w.build = _pick(rng, [0, 1, 2], [0.3, 0.5, 0.2])
	w.top = _pick(rng, [0, 1, 2, 3, 4, 5], [0.25, 0.17, 0.17, 0.11, 0.15, 0.15]) if female else _pick(rng, [0, 1, 2, 3, 5], [0.28, 0.2, 0.22, 0.15, 0.15])
	w.bottom = _pick(rng, [0, 1, 2], [0.6, 0.15, 0.25]) if female else _pick(rng, [0, 1], [0.78, 0.22])
	if w.top == 4: w.bottom = 2
	w.shoe = _pick(rng, [0, 1, 2], [0.55, 0.2, 0.25])
	w.hair = _pick(rng, [3, 4, 5, 6, 0, 2], [0.35, 0.25, 0.14, 0.1, 0.1, 0.06]) if female else _pick(rng, [0, 1, 2, 6, 7, 3], [0.3, 0.2, 0.2, 0.1, 0.12, 0.08])
	w.beard = 0 if female else _pick(rng, [0, 1, 2, 3], [0.55, 0.12, 0.2, 0.13])
	w.hat = _pick(rng, [0, 1, 2], [0.8, 0.13, 0.07])
	w.glasses = rng.randf() < 0.15
	w.backpack = rng.randf() < 0.15
	w.bag = 0 if w.backpack or rng.randf() > (0.3 if female else 0.06) else (1 if rng.randf() < 0.5 else -1)
	w.height = rng.randf_range(0.95, 1.05) * (0.95 if female else 1.0)
	w.skin = SKINS[rng.randi() % SKINS.size()]
	var grey := rng.randf() < 0.1
	w.hair_color = HAIRS[6] if grey else HAIRS[rng.randi() % 6 if rng.randf() < 0.9 else 7]
	w.inner = INNERS[rng.randi() % INNERS.size()]
	var shoe_roll := rng.randi()
	w.accent = ACCENTS[rng.randi() % ACCENTS.size()]
	w.top_color = coat_color
	w.bottom_color = pants_color
	if w.bottom == 1: w.bottom_color = pants_color.lightened(0.12)
	if motorcycle_helmet_color != Color.TRANSPARENT:
		# O piloto montado usa capacete integral; a mesma leitura visual continua
		# após a queda, em vez de trocar por um motorista genérico sem capacete.
		w.hat = 3
		w.accent = motorcycle_helmet_color
		w.backpack = false
	w.merge(wardrobe_overrides, true)
	# Cor do calçado depois dos overrides: bota de estivador sorteia na paleta de bota.
	var shoes: Array = [SNEAKERS, BOOTS, DRESS_SHOES][w.shoe]
	if not wardrobe_overrides.has("shoe_color"): w.shoe_color = shoes[shoe_roll % shoes.size()]
	wardrobe = w

static func _pick(rng: RandomNumberGenerator, values: Array, weights: Array) -> Variant:
	var roll := rng.randf()
	for i in values.size():
		roll -= float(weights[i])
		if roll <= 0.0: return values[i]
	return values[-1]

func _build_rig() -> void:
	var w := wardrobe
	var profile := KIT.build_profile(w.female, w.build)
	scale = Vector3.ONE * float(w.height)
	pelvis = _joint(self, "Pelvis", Vector3(0, PELVIS_Y, 0), KIT.pelvis_mesh(profile, w.top, w.bottom, w.bag))
	spine = _joint(pelvis, "Spine", SPINE_OFFSET, KIT.chest_mesh(profile, w.top, w.backpack, -w.bag))
	head_node = _joint(spine, "Head", NECK, KIT.head_mesh(w.female, w.hair, w.beard, w.hat, w.glasses))
	var hip_x: float = profile.hip.x * 0.6
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var prefix := "left_" if i == 0 else "right_"
		var title := "Left" if i == 0 else "Right"
		_hip_offsets.append(Vector3(side * hip_x, HIP_DROP, 0))
		_shoulders.append(Vector3(side * (float(profile.shoulder) - 0.004), SHOULDER_Y, -0.006))
		# Nomes `left_upper_leg` etc. são os que `CharacterFallPresentation3D`
		# procura para articular a queda. O antebraço fica com outro nome de
		# propósito: a pose de queda dele dobra o cotovelo para trás neste rig.
		var thigh := _joint(pelvis, prefix + "upper_leg", _hip_offsets[i], KIT.thigh_mesh(profile, w.bottom, w.top))
		var shin := _joint(thigh, prefix + "lower_leg", Vector3(0, -KIT.THIGH, 0), KIT.shin_mesh(profile, w.bottom, w.top, w.shoe))
		var foot := _joint(shin, title + "Foot", Vector3(0, -KIT.SHIN, 0), KIT.foot_mesh(w.shoe))
		var arm := _joint(spine, prefix + "upper_arm", _shoulders[i], KIT.upper_arm_mesh(profile, w.top))
		var fore := _joint(arm, title + "Forearm", Vector3(0, -KIT.UPPER_ARM, 0), KIT.forearm_mesh(profile, w.top, side))
		thighs.append(thigh)
		shins.append(shin)
		feet.append(foot)
		upper_arms.append(arm)
		forearms.append(fore)
		_idle_stance.append(Vector3(side * 0.018, 0, (0.045 if (i == 0) == (posmod(appearance_variant, 2) == 0) else -0.02)))
	# Ordem histórica de `limbs`: perna, braço do lado -X; perna, braço do lado +X.
	limbs.assign([thighs[0], upper_arms[0], thighs[1], upper_arms[1]])

func _joint(parent: Node3D, joint_name: String, offset: Vector3, mesh: Mesh) -> MeshInstance3D:
	var joint := MeshInstance3D.new()
	joint.name = joint_name
	joint.mesh = mesh
	joint.position = offset
	parent.add_child(joint)
	_joints.append(joint)
	_rest[joint] = offset
	return joint

func _apply_colors() -> void:
	var w := wardrobe
	var params := {"skin_color": w.skin, "hair_color": w.hair_color, "top_color": w.top_color, "inner_color": w.inner,
		"bottom_color": w.bottom_color, "shoe_color": w.shoe_color, "accent_color": w.accent}
	for joint in _joints:
		for key in params: joint.set_instance_shader_parameter(key, params[key])

## Nó filho de `joint` cuja origem coincide com a origem do modelo em repouso:
## peças extras (EPI do estivador) continuam autoradas em coordenadas do modelo
## e passam a acompanhar a articulação.
func anchor(joint: Node3D) -> Node3D:
	var offset := Vector3.ZERO
	var node: Node = joint
	while node != self and node != null:
		offset += _rest.get(node, Vector3.ZERO)
		node = node.get_parent()
	var holder := Node3D.new()
	holder.position = -offset
	joint.add_child(holder)
	return holder

## Chamado por quem teleporta o pai (esteira de teste, respawn): o salto não
## vira velocidade nem avanço de fase.
func teleported() -> void:
	_last_position = global_position

# --- Animação ------------------------------------------------------------------

func _process(delta: float) -> void:
	clock += delta
	if is_instance_valid(_owner_actor) and _owner_actor.get("dead") == true:
		# A queda (`CharacterFallPresentation3D`) passa a dirigir as articulações.
		set_process(false)
		return
	_measure(delta)
	_pending += delta
	_frame += 1
	var interval := _update_interval() if lod_enabled else 1
	if interval > 1 and (_frame + _stagger) % interval != 0: return
	_pose(_pending)
	_pending = 0.0

func _measure(delta: float) -> void:
	var here := global_position
	if _last_position == Vector3.INF: _last_position = here
	var step := here - _last_position
	_last_position = here
	step.y = 0.0
	var distance := step.length()
	if distance > 3.0: distance = 0.0
	var forward := global_basis.z
	forward.y = 0.0
	if distance > 0.0001 and step.dot(forward) < -0.3 * distance * forward.length(): _travel -= distance
	else: _travel += distance
	_speed = lerpf(_speed, distance / maxf(delta, 0.0001), 1.0 - exp(-8.0 * delta))

## Pedestre fora da tela ou pequeno na tela atualiza a pose menos vezes; a fase
## continua acumulando distância, então ele retoma no passo certo.
func _update_interval() -> int:
	if not is_inside_tree(): return 1
	var camera := get_viewport().get_camera_3d()
	if camera == null: return 1
	if not camera.is_position_in_frustum(global_position + Vector3.UP): return 6
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL: return 1 if camera.size < 32.0 else 2
	var distance := camera.global_position.distance_to(global_position)
	return 1 if distance < 30.0 else (2 if distance < 60.0 else 4)

func _pose(dt: float) -> void:
	dt = minf(dt, 0.25)
	var v := _speed
	_move_w = move_toward(_move_w, 1.0 if v > 0.18 else 0.0, dt * 4.0)
	_run_w = move_toward(_run_w, smoothstep(2.2, 3.3, v), dt * 3.0)
	_carry_w = move_toward(_carry_w, 1.0 if activity == "carry" else 0.0, dt * 4.0)
	_talk_w = move_toward(_talk_w, 1.0 if activity == "talk" else 0.0, dt * 3.0)
	var mw := smoothstep(0.0, 1.0, _move_w)
	var rw := _run_w
	var idle := 1.0 - mw
	var stride := lerpf(clampf(0.92 + 0.34 * v, 1.05, 1.8), clampf(1.0 + 0.48 * v, 2.0, 3.6), rw)
	_phase = fposmod(_phase + _travel / stride, 1.0)
	_travel = 0.0

	# Pés: apoio plantado com rolamento, balanço em arco; corrida com fase aérea
	# (apoio curto) e calcanhar subindo para trás no início do balanço.
	var duty := lerpf(0.6, 0.34, rw)
	var reach := minf(0.5 * stride * duty * REACH_SHARE, 0.42) * mw
	var behind := 0.1 * rw * mw
	var lift := lerpf(0.075, 0.15, rw) * mw
	var strike := lerpf(0.3, 0.12, rw) * mw
	var push := lerpf(-0.8, -0.95, rw) * mw
	var ankles: Array[Vector3] = []
	var pitches: Array[float] = []
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var f := _foot(fposmod(_phase + 0.5 * i, 1.0), duty, reach, behind, lift, strike, push, rw * mw)
		ankles.append((Vector3(side * lerpf(0.098, 0.078, rw * mw), f.y, f.x) + _idle_stance[i] * idle).lerp(Vector3(side * 0.13, KIT.ANKLE_HEIGHT, 0.4), _sit()))
		pitches.append(f.z)

	# Pelve: sobe no meio do apoio andando, desce no apoio correndo; gira com a
	# perna que avança, cai do lado do balanço e transfere o peso lateralmente.
	var bob_wave := cos(4.0 * PI * (_phase - duty * 0.5))
	var bob := lerpf(0.014 * bob_wave, -0.02 * bob_wave, rw) * mw
	var sway := sin(TAU * (_phase + 0.05))
	var yaw := lerpf(0.1, 0.15, rw) * cos(TAU * _phase) * mw
	var roll := -lerpf(0.045, 0.02, rw) * sway * mw
	var shift := -0.02 * sway * mw * (1.0 - rw)
	var weight := sin(clock * 0.55 + _seed)
	shift += 0.022 * weight * idle
	roll -= 0.03 * weight * idle
	var tilt := lerpf(0.02, 0.09, rw) * mw
	var pelvis_basis := Basis.from_euler(Vector3(tilt, yaw, roll))
	var pelvis_position := Vector3(shift, PELVIS_Y - (0.008 + 0.015 * rw) * mw + bob, 0.0)
	# Só a perna de apoio limita a altura da pelve: a do balanço está no ar e
	# pode encolher. Incluí-la agachava o corredor no começo do balanço.
	var leg_reach := (KIT.THIGH + KIT.SHIN) * 0.998
	var drop := 0.0
	for i in 2:
		if fposmod(_phase + 0.5 * i, 1.0) >= duty and mw > 0.5: continue
		var gap: Vector3 = pelvis_position + pelvis_basis * _hip_offsets[i] - ankles[i]
		drop = maxf(drop, gap.y - sqrt(maxf(leg_reach * leg_reach - gap.x * gap.x - gap.z * gap.z, 0.0)))
	pelvis_position.y -= drop
	# Sentado: a pelve desce até o assento (a altura é global; o modelo tem
	# escala própria) e os pés vão à frente; o IK dobra os joelhos sozinho.
	var sit := _sit()
	if sit > 0.0:
		var seat := seat_height / maxf(global_transform.basis.get_scale().y, 0.01) + 0.08
		pelvis_position = pelvis_position.lerp(Vector3(0.0, seat, -0.06), sit)
		pelvis_basis = pelvis_basis.slerp(Basis(Vector3.RIGHT, -0.08), sit)
	pelvis.transform = Transform3D(pelvis_basis, pelvis_position)
	for i in 2: _place_leg(i, pelvis_basis, pelvis_position, ankles[i], pitches[i])

	# Tronco contra-gira a pelve (ombros opostos ao quadril), inclina na corrida
	# e respira parado.
	var breathe := sin(clock * 1.7 + _seed) * 0.012 * (1.0 + rw * 1.5)
	var chest_yaw := -yaw * 1.7
	var chest_roll := -roll * 0.85
	var chest_lean := lerpf(0.03, 0.22, rw) * mw - tilt * 0.5 + breathe - 0.05 * _carry_w + 0.1 * _sit()
	spine.transform = Transform3D(Basis.from_euler(Vector3(chest_lean, chest_yaw, chest_roll)), SPINE_OFFSET)
	var spine_model := pelvis.transform * spine.transform

	_look_timer -= dt
	if _look_timer <= 0.0:
		var noise := fposmod(sin(clock * 12.9898 + _seed * 78.233) * 43758.5453, 1.0)
		_look_target = (noise - 0.5) * lerpf(0.35, 1.2, idle) if noise > 0.25 else 0.0
		_look_timer = 2.0 + noise * 4.5
	_look = lerpf(_look, _look_target, 1.0 - exp(-3.0 * dt))
	var nod := sin(clock * 2.6 + _seed) * 0.06 * _talk_w
	var head_yaw := -(yaw + chest_yaw) * 0.85 + _look * (1.0 - 0.7 * rw)
	var head_pitch := -(tilt + chest_lean) * 0.75 + 0.05 + nod + 0.12 * _carry_w
	var head_roll := -(roll + chest_roll) * 0.8
	head_node.transform = Transform3D(Basis.from_euler(Vector3(head_pitch, head_yaw, head_roll)), NECK)

	# Braços em oposição às pernas; na corrida cotovelo a ~90° e balanço cruzando
	# levemente à frente do corpo. Parado: pendem com leve dobra.
	if hand_provider.is_valid(): hand_targets = hand_provider.call()
	var amplitude := lerpf(0.2 + 0.12 * clampf(v - 1.1, 0.0, 1.0), 0.62, rw) * mw
	var bias := lerpf(0.03, -0.05, rw) * mw
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var swing := cos(TAU * (_phase - 0.04)) * side
		var flex := bias + amplitude * swing + 0.02 * idle
		# Correndo, o cotovelo fecha quando o braço vem à frente (mão perto do
		# peito) e abre quando vai para trás; fixo em 90° parecia zumbi.
		var elbow := lerpf(0.13 + 0.3 * clampf(flex / 0.35, 0.0, 1.0) * mw, 1.3 + 0.38 * swing, rw)
		var abduct := side * (0.085 + 0.05 * rw)
		if i == 1 and _talk_w > 0.0:
			# Gesticula com a mão direita enquanto conversa.
			flex = lerpf(flex, 0.35 + 0.22 * sin(clock * 2.1 + _seed), _talk_w)
			elbow = lerpf(elbow, 1.25 + 0.35 * sin(clock * 3.3 + _seed), _talk_w)
			abduct = lerpf(abduct, side * 0.22, _talk_w)
		var arm_basis := Basis.from_euler(Vector3(-flex, -side * 0.22 * rw, abduct))
		var fore_basis := Basis(Vector3.RIGHT, -elbow)
		if hand_targets[i] is Vector3:
			var reached := _reach_arm(i, spine_model, to_local(hand_targets[i]), Vector3(side * 0.9, -0.8, -0.3))
			arm_basis = reached[0]
			fore_basis = reached[1]
		elif _carry_w > 0.0:
			var carried := _carry_arm(i, spine_model)
			arm_basis = arm_basis.slerp(carried[0], _carry_w)
			fore_basis = fore_basis.slerp(carried[1], _carry_w)
		upper_arms[i].transform = Transform3D(arm_basis, _shoulders[i])
		forearms[i].transform = Transform3D(fore_basis, Vector3(0, -KIT.UPPER_ARM, 0))

func _sit() -> float:
	return smoothstep(0.0, 1.0, clampf(sit_amount, 0.0, 1.0))

## Tornozelo do pé no instante `t` do ciclo: Vector3(z, y, inclinação do pé).
func _foot(t: float, duty: float, reach: float, behind: float, lift: float, strike: float, push: float, kick: float) -> Vector3:
	if t < duty: return _stance(t / duty, reach, behind, strike, push)
	var u := (t - duty) / (1.0 - duty)
	var from := _stance(1.0, reach, behind, strike, push)
	var to := _stance(0.0, reach, behind, strike, push)
	var ease := u * u * (3.0 - 2.0 * u)
	var arc := sin(PI * u)
	var z := lerpf(from.x, to.x, ease) - kick * 0.22 * arc * (1.0 - u)
	var y := lerpf(from.y, to.y, u) + lift * arc + kick * 0.4 * arc * arc * (1.0 - u)
	return Vector3(z, y, lerpf(from.z, to.z, smoothstep(0.1, 0.85, u)))

## Apoio: o ponto de contato recua na velocidade do corpo; o pé gira no
## calcanhar logo após tocar e na planta antes de sair, nunca deslizando.
func _stance(s: float, reach: float, behind: float, strike: float, push: float) -> Vector3:
	var ground := reach * (1.0 - 2.0 * s) - behind
	if s < 0.14: return _rock(ground + HEEL, Vector2(-HEEL, KIT.ANKLE_HEIGHT), strike * (1.0 - s / 0.14))
	if s > 0.6: return _rock(ground + BALL, Vector2(-BALL, KIT.ANKLE_HEIGHT), push * smoothstep(0.6, 1.0, s))
	return Vector3(ground, KIT.ANKLE_HEIGHT, 0.0)

## Tornozelo girando `angle` (bico para cima > 0) em torno de um pivô no chão.
static func _rock(pivot_z: float, arm: Vector2, angle: float) -> Vector3:
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(pivot_z + arm.x * c - arm.y * s, arm.x * s + arm.y * c, angle)

func _place_leg(i: int, pelvis_basis: Basis, pelvis_position: Vector3, ankle: Vector3, pitch: float) -> void:
	var side := -1.0 if i == 0 else 1.0
	var hip: Vector3 = pelvis_position + pelvis_basis * _hip_offsets[i]
	var solved := _two_bone(hip, ankle, KIT.THIGH, KIT.SHIN, Vector3(side * 0.12, 0.0, 1.0))
	var knee: Vector3 = solved[0]
	var bend: Vector3 = solved[1]
	var thigh_basis := _bone_basis(hip, knee, bend)
	var shin_basis := _bone_basis(knee, knee + (ankle - knee).normalized() * KIT.SHIN, bend)
	thighs[i].transform = Transform3D(pelvis_basis.transposed() * thigh_basis, _hip_offsets[i])
	shins[i].transform = Transform3D(thigh_basis.transposed() * shin_basis, Vector3(0, -KIT.THIGH, 0))
	var foot_basis := Basis(Vector3.UP, side * 0.09) * Basis(Vector3.RIGHT, -pitch)
	feet[i].transform = Transform3D(shin_basis.transposed() * foot_basis, Vector3(0, -KIT.SHIN, 0))

## Braços segurando a caixa do estivador (`V1RoutineActor`, caixa a 1,0 m de
## altura e 0,34 m à frente): IK até as laterais da caixa, cotovelos para baixo
## e só um pouco abertos (polo lateral demais abria os braços como asa).
func _carry_arm(i: int, spine_model: Transform3D) -> Array:
	var side := -1.0 if i == 0 else 1.0
	return _reach_arm(i, spine_model, Vector3(side * 0.235, 1.0 / maxf(scale.y, 0.01), 0.3), Vector3(side * 0.35, -1.0, -0.25))

## Braço até `target` (espaço do modelo), cotovelo puxado para `pole`.
func _reach_arm(i: int, spine_model: Transform3D, target: Vector3, pole: Vector3) -> Array:
	var shoulder := spine_model * _shoulders[i]
	var solved := _two_bone(shoulder, target, KIT.UPPER_ARM, KIT.FOREARM + 0.06, pole)
	var elbow: Vector3 = solved[0]
	var upper := _bone_basis(shoulder, elbow, Vector3(0, 0, 1))
	var fore := _bone_basis(elbow, target, Vector3(0, 1, 0))
	return [spine_model.basis.orthonormalized().transposed() * upper, upper.transposed() * fore]

## IK de duas barras. Devolve [articulação do meio, direção da dobra].
static func _two_bone(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Array:
	var to := target - root
	var distance := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.0005)
	var direction := to.normalized() if to.length_squared() > 0.000001 else Vector3.DOWN
	var bend := (pole - direction * pole.dot(direction)).normalized()
	if bend.is_zero_approx(): bend = Vector3.FORWARD
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	return [root + direction * along + bend * sqrt(maxf(0.0, a * a - along * along)), bend]

## Base de um osso pendurado em -Y: +Y aponta de volta para o pai e +Z para `front`.
static func _bone_basis(from: Vector3, to: Vector3, front: Vector3) -> Basis:
	var y := (from - to).normalized()
	var z := (front - y * front.dot(y)).normalized()
	if z.is_zero_approx(): z = Vector3.FORWARD
	return Basis(y.cross(z), y, z)
