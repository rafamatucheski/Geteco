extends "res://scripts/Actor.gd"
## Os irmãos Ferraz na blitz do prólogo, oito anos antes: os dois são o `dante.glb` do jogador (mesmo rosto
## de família, mãos, caminhada, corrida, pegada de pistola e pose de motorista do jogo), cada um com a sua
## roupa, cabelo e acessórios. `identity` = "dante" (farda da patrulha e boné) ou "vicente" (jaqueta de
## trabalho, cabelo e barba castanho-claros, boné para trás, um pouco mais baixo).
##
## A cena conduz como marionete: move o nó, diz para onde olhar e o que as mãos fazem, e chama `pose_step`
## uma vez por quadro (física e entrada do Actor desligadas; a árvore está pausada). Interface que a cena
## usa: `weapon`, `muzzle_flash_3d`, `equip`, `update_pose`, `attack`, `hand_targets` (mundo; null = braço
## livre), `head_node`, `sit_amount` (inclinar o tronco), `seat`/`sit_on_ground`/`stand_up`.
const DRESS := preload("res://assets/outfits/MeshyDanteAppearance.gd")
const GEOMETRY := preload("res://assets/outfits/OutfitGeometry.gd")
const RIG_POSE := preload("res://gameplay/WeaponRigPose.gd")
const POSE_DATA := preload("res://gameplay/WeaponPoseData.gd")
const ARSENAL := preload("res://gameplay/ArsenalWeapon3D.gd")
## Farda da patrulha do jogo (PoliceModel, escalão 0).
const UNIFORM := Color(0.11, 0.15, 0.24)
var identity_id := "dante"
var weapon: Node3D
var muzzle_flash_3d: MeshInstance3D
var head_node: Node3D
var hand_targets: Array = [null, null]
## Só para a interface: a mão segue `hand_targets`.
var hand_provider := Callable()
## 0..1: inclina o tronco à frente (algemar alguém sentado no chão).
var sit_amount := 0.0
var seat_height := .45
var held_item: Node3D
var _weapon_pose = RIG_POSE.new()
var _armed_frame := -10
var _aiming := false
var _flash_time := 0.0
var _face_yaw := NAN
## Sentado: banco (mundo), pés e mãos (mundo) e quanto o encosto reclina. `_seat_weight` sobe de 0 a 1
## quando ele senta no chão (de pé para sentado, sem salto).
var _seat_point := Vector3.INF
var _seat_feet: Dictionary = {}
var _seat_hands: Dictionary = {}
var _seat_recline := 0.0
var _seat_weight := 0.0
var _seat_rate := 0.0
var _stand_point := Vector3.ZERO
## Cabeça baixa (rad) sobre a pose sentada: o Dante de oito anos depois, olhando a carta.
var head_bow := 0.0

func _ready() -> void:
	is_player = true
	outfit_id = "dante_ski"
	super._ready()
	set_physics_process(false)
	input_locked = true
	collision_layer = 0
	collision_mask = 0
	# Sem física: a pose de queda/pulo do jogador não entra.
	air_movement = null
	if identity_id == "vicente": _dress_vicente()
	else: _dress_dante()
	head_node = BoneAttachment3D.new()
	head_node.name = "BlitzHead"
	(head_node as BoneAttachment3D).bone_name = "Head"
	skeleton.add_child(head_node)

func _tint(regions: Dictionary) -> void:
	var cloth := outfit_material
	if cloth == null: return
	var tints: PackedColorArray = cloth.get_shader_parameter("region_tint")
	var patterns: PackedFloat32Array = cloth.get_shader_parameter("region_pattern")
	for region in regions:
		var tint: Color = regions[region][0]
		tint.a = 1.0
		tints[region] = tint
		patterns[region] = float(regions[region][1])
	cloth.set_shader_parameter("region_tint", tints)
	cloth.set_shader_parameter("region_pattern", patterns)
	# Sem as luvas do traje de esqui: as mãos ficam de pele.
	var zones := PackedColorArray()
	var masks := PackedInt32Array()
	for zone in 7:
		zones.append(Color(0, 0, 0, 0))
		masks.append(0)
	cloth.set_shader_parameter("zone_color", zones)
	cloth.set_shader_parameter("zone_mask", masks)
	cloth.set_shader_parameter("recolor", true)

func _dress_dante() -> void:
	_tint({DRESS.JACKET: [UNIFORM, .05], DRESS.SHIRT: [UNIFORM.lightened(.12), .15], DRESS.PANTS: [UNIFORM.darkened(.25), .2],
		DRESS.BELT: [Color("0c0d10"), .5], DRESS.BOOTS: [Color("0b0b0e"), .4]})
	# Boné de patrulha (aba na frente, +Z) e distintivo no peito, nas medidas da cabeça do modelo.
	var spaces := {}
	var head := DRESS._space(skeleton, spaces, "Head")
	var felt := GEOMETRY._make_mat(UNIFORM.darkened(.1), .8)
	head.add_child(GEOMETRY._make_ellipsoid(Vector3(.272, .19, .312), felt, Vector3(.004, 1.618, -.022)))
	head.add_child(GEOMETRY._make_ellipsoid(Vector3(.276, .07, .316), GEOMETRY._make_mat(Color("101215"), .6), Vector3(.004, 1.585, -.022)))
	var brim := GEOMETRY._make_box(Vector3(.17, .012, .1), GEOMETRY._make_mat(Color("0d0e11"), .45), Vector3(.004, 1.582, .155))
	brim.rotation.x = .18
	head.add_child(brim)
	var gold := GEOMETRY._make_mat(Color("c9a646"), .35, .6)
	head.add_child(GEOMETRY._make_ellipsoid(Vector3(.034, .04, .012), gold, Vector3(.004, 1.64, .135)))
	DRESS._space(skeleton, spaces, "Spine02").add_child(GEOMETRY._make_ellipsoid(Vector3(.045, .055, .014), gold, Vector3(-.075, 1.36, .135)))

## Mesmo rosto de família, outro homem: mais novo, cabelo e barba castanhos (o Dante é quase preto), a
## jaqueta de quem dirige a noite toda e uma corrente. Sem boné (o do traje boiava sobre a cabeça no close)
## e sem tingir a pele (a cor nova sobre a textura do rosto ficava manchada).
func _dress_vicente() -> void:
	_tint({DRESS.HAIR: [Color("3e2c1f"), .85], DRESS.JACKET: [Color("4f5a44"), .12],
		DRESS.SHIRT: [Color("c9c3b4"), .25], DRESS.PANTS: [Color("2f3d52"), .5], DRESS.BELT: [Color("3a2a1c"), .5], DRESS.BOOTS: [Color("4a3626"), .6]})
	var spaces := {}
	DRESS._necklace(DRESS._space(skeleton, spaces, "neck"), Color("c9b27a"))
	var model := visual.get_child(0) as Node3D
	if model != null: model.scale = Vector3.ONE * 1.0

## Pistola da patrulha no coldre: o modelo do arsenal, montado na palma pela pegada do jogo.
func equip(_id: String) -> void:
	if is_instance_valid(weapon): return
	weapon = Node3D.new()
	weapon.name = "BlitzPistol"
	add_child(weapon)
	var tip := ARSENAL.build(weapon, "pistol")
	muzzle_flash_3d = MeshInstance3D.new()
	var flash := SphereMesh.new()
	flash.radius = .05
	flash.height = .1
	muzzle_flash_3d.mesh = flash
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(1, .85, .45)
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_3d.material_override = lit
	muzzle_flash_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle_flash_3d.position = tip
	muzzle_flash_3d.hide()
	weapon.add_child(muzzle_flash_3d)
	weapon.hide()
	set_combat_weapon_mount(weapon, POSE_DATA.GRIPS.pistol)

## Pistola na mão neste quadro; `aiming` ergue as duas mãos na linha de mira (pronto-baixo sem).
func update_pose(_delta: float, aiming: bool, _reloading := false, _progress := 0.0, _gait := 0.0) -> void:
	_armed_frame = Engine.get_process_frames()
	_aiming = aiming
	if not aiming: combat_facing = NAN

func attack() -> void:
	_weapon_pose.attack("pistol")
	_flash_time = .05

func blitz_face(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() > .001: _face_yaw = atan2(-direction.x, -direction.z)

func blitz_forward() -> Vector3:
	return -visual.global_basis.z.normalized()

func blitz_hold_item(item: Node3D) -> bool:
	held_item = item
	return true

## Motorista: quadril no banco, pés nos pedais, mãos no aro (tudo em mundo). Pose de veículo do jogo.
func seat(point: Vector3, feet: Dictionary, hands: Dictionary, recline := .12) -> void:
	_seat_point = point
	_seat_feet = feet
	_seat_hands = hands
	_seat_recline = recline
	_seat_weight = 1.0
	_seat_rate = 0.0

## Ferido: as pernas falham e ele senta no asfalto em `seconds`, pernas à frente; mãos em `hands`.
func sit_on_ground(point: Vector3, feet: Dictionary, hands: Dictionary, seconds := .7) -> void:
	_stand_point = global_position
	_seat_point = point
	_seat_feet = feet
	_seat_hands = hands
	_seat_recline = -.18
	_seat_weight = 0.0
	_seat_rate = 1.0 / maxf(seconds, .05)

func update_seat_hands(hands: Dictionary) -> void:
	_seat_hands = hands

## Oito anos depois: a roupa de hoje do Dante (o traje padrão), sem boné nem distintivo da farda; a
## pistola fica guardada.
func civilian() -> void:
	set_outfit("dante_classic")
	if is_instance_valid(weapon): weapon.hide()

func stand_up() -> void:
	_seat_point = Vector3.INF
	_seat_weight = 0.0
	release_seated()

func sitting() -> bool:
	return _seat_point.is_finite()

## Uma pose por quadro, depois de a cena mover o nó: caminhada do jogo pelo deslocamento real (ou a pose
## sentada), depois a camada de mãos (pistola, lanterna ou alcance livre) e o objeto na palma resolvida.
func pose_step(delta: float) -> void:
	if skeleton == null or animation == null: return
	delta = maxf(delta, .0001)
	_pose_delta = delta
	if sitting():
		_pose_seated(delta)
		_place_item()
		return
	var displacement := global_position - last_position
	displacement.y = 0.0
	last_position = global_position
	var actual_speed := displacement.length() / delta
	var moving := actual_speed > MOVING_SPEED_EPSILON
	var direction := displacement / displacement.length() if moving else Vector3.ZERO
	if not is_nan(combat_facing): visual.rotation.y = rotate_toward(visual.rotation.y, combat_facing, delta * 12.0)
	elif not is_nan(_face_yaw): visual.rotation.y = lerp_angle(visual.rotation.y, _face_yaw, 1.0 - exp(-10.0 * delta))
	elif moving: visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-10.0 * delta))
	var armed := Engine.get_process_frames() - _armed_frame <= 1 and is_instance_valid(weapon)
	combat_stance = "gun" if armed and _aiming else ""
	_pose_locomotion(direction, 1.6, displacement, actual_speed, delta)
	_clip_palms = {"Left": _clip_palm("Left"), "Right": _clip_palm("Right")}
	_hit_age += delta
	if armed:
		var frame: Dictionary = _weapon_pose.update("pistol", delta, _aiming, false, 0.0, moving, false, phase, combat_rig_info())
		set_combat_weapon_pose("pistol", frame)
		_apply_combat_weapon_pose()
		weapon.global_transform = combat_weapon_transform(POSE_DATA.GRIPS.pistol)
	else:
		var hold := _hold_pose()
		if not hold.is_empty():
			set_combat_weapon_pose("blitz_hold", hold)
			_apply_combat_weapon_pose()
		elif is_instance_valid(held_item) and held_item.is_visible_in_tree():
			# Lanterna na mão livre: o braço segue a caminhada e o punho fecha no tubo (chamar a camada vazia
			# também abriria a mão no mesmo quadro).
			clear_combat_weapon_pose()
			_stabilize_combat_pose()
			_set_combat_grips(true, false, true, false)
		else:
			clear_combat_weapon_pose()
			_apply_combat_weapon_pose()
	_flash_time = maxf(0.0, _flash_time - delta)
	if is_instance_valid(muzzle_flash_3d): muzzle_flash_3d.visible = _flash_time > 0.0
	_place_item()

func _place_item() -> void:
	if is_instance_valid(held_item) and held_item.get_parent() != self and held_item.is_visible_in_tree():
		held_item.global_position = combat_palm_position("Right")

## Pose sentada do jogo (banco do caminhão ou asfalto). Ao sentar no chão mistura com a postura em pé e
## desce o corpo junto, para não pular de uma para a outra.
func _pose_seated(delta: float) -> void:
	_seat_weight = minf(1.0, _seat_weight + _seat_rate * delta) if _seat_rate > 0.0 else 1.0
	var standing: Array = []
	if _seat_weight < 1.0:
		_pose_locomotion(Vector3.ZERO, 0.0, Vector3.ZERO, 0.0, delta)
		standing = _capture_pose()
	var hip_local := pose_seated_base(_seat_recline)
	var seated_origin := _seat_point - global_basis * hip_local
	var feet := {}
	for side in _seat_feet: feet[side] = to_local(_seat_feet[side])
	var hands := {}
	for side in _seat_hands:
		var hold: Transform3D = _seat_hands[side]
		hands[side] = Transform3D(global_basis.inverse() * hold.basis, to_local(hold.origin))
	pose_seated_limbs(feet, hands)
	if head_bow > 0.0 and _combat_bones.has("Head"):
		var head: int = _combat_bones.Head
		skeleton.set_bone_pose_rotation(head, skeleton.get_bone_pose_rotation(head) * Quaternion(Vector3.RIGHT, head_bow))
	if _seat_weight < 1.0:
		_apply_blend(standing, _capture_pose(), smoothstep(0.0, 1.0, _seat_weight))
		global_position = _stand_point.lerp(seated_origin, smoothstep(0.0, 1.0, _seat_weight))
	else: global_position = seated_origin
	last_position = global_position

## Alvos de mão em espaço do Actor (frente -Z): punho fechado em cada mão com alvo.
func _hold_pose() -> Dictionary:
	if not (hand_targets[0] is Vector3 or hand_targets[1] is Vector3): return {}
	var to_local_space := visual.global_transform.affine_inverse()
	var pose := {"armed": false, "basis": Basis(Vector3.RIGHT, -.25), "right_solve": hand_targets[0] is Vector3,
		"left_solve": hand_targets[1] is Vector3, "right_grip": hand_targets[0] is Vector3, "left_grip": hand_targets[1] is Vector3,
		"support_weight": 0.0, "lean": .55 * clampf(sit_amount, 0.0, 1.0), "arm_rate": 10.0}
	pose["right"] = to_local_space * (hand_targets[0] as Vector3) if hand_targets[0] is Vector3 else Vector3(.2, .9, -.1)
	pose["left"] = to_local_space * (hand_targets[1] as Vector3) if hand_targets[1] is Vector3 else Vector3(-.2, .9, -.1)
	pose["left_basis"] = Basis(Vector3.RIGHT, -.25)
	return pose
