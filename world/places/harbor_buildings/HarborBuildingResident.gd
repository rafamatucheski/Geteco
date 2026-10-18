extends "res://scripts/Actor.gd"
## Civilian actors keep the shared collision/damage contracts. Their task is
## performed with native hand IK and real props, without NPC-sized billboards.
## Rework 15/10/2026: além de trabalhar em pé, o morador senta no próprio
## banquinho (dentro da cápsula), deita na cama do andar a partir de um ponto
## livre ao lado dela, conversa em dupla, toma café, varre e caminha entre
## pontos livres do cômodo. Nada disso varre a cena por quadro.
const MODEL := preload("res://assets/CivilianModel.gd")
const MATERIALS := preload("res://world/places/harbor_buildings/HarborBuildingMaterials.gd")
const SOCIAL_ROUTINE := preload("res://gameplay/civilian_social/BuildingSocialRoutine.gd")
const SEATED := ["sit_write", "sit_read", "sit_phone", "tv", "sit_doze"]
const WANDER_SPEED := .85
const WANDER_HOLD_AFTER_THREAT := 25.0
var specification: Dictionary = {}
var resident_model: Node3D
var prop: Node3D
var social_phone: Node3D
var social_routine: Node
var work_activity := "read"
var work_clock := 0.0
## Assento visual (banquinho) sob a pelve; só aparece sentado.
var seat: Node3D
## Cama (transform global, origem na altura do lençol) de quem dorme.
var sleep_bed := Transform3D()
var sleeping := false
## Pontos globais do passeio pelo cômodo, já validados como piso livre.
var wander_points: Array[Vector3] = []
var chat_partner: Node3D
var chat_offset := 0.0
var _wander_index := 0
var _wander_pause := 0.0
var _wander_stuck := 0.0
var _wander_hold := 0.0
var _wander_yaw := 0.0
## Rumo visual próprio: Actor._physics_process gira `visual` para o lado -Z
## dos rigs do jogador; o modelo civil olha para +Z, então o morador reescreve.
var _visual_yaw := 0.0
var _layer := 2

func _ready() -> void:
	name = str(specification.get("id", "BuildingResident"))
	identity = int(specification.get("identity", 7000))
	controlled_automatically = true
	automatic_direction = Vector3.ZERO
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	set_meta("gameplay_role", "civilian")
	set_meta("reaction_exempt", true)
	add_to_group("police_witness")
	add_to_group("v2_damageable")
	add_to_group("building_resident")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .86
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	resident_model = MODEL.new()
	resident_model.appearance_locked = true
	resident_model.appearance_variant = identity
	resident_model.lod_enabled = false
	var appearance: Dictionary = specification.get("appearance", {})
	resident_model.coat_color = Color(str(appearance.get("coat", "778775")))
	resident_model.pants_color = Color(str(appearance.get("pants", "414c4e")))
	resident_model.wardrobe_overrides = {"female":bool(appearance.get("female", false)), "height":1.0, "top":int(appearance.get("top", 1)),
		"bottom":0, "shoe":0, "hat":0, "bag":0, "backpack":false}
	# Corpo Meshy dos pedestres (mesmo sexo); o guarda-roupa acima só vale quando não há corpo compatível.
	preload("res://assets/civilians/CivilianBodyCatalog.gd").apply_keeping_sex(resident_model, identity)
	visual.add_child(resident_model)
	work_activity = str(specification.get("activity", "read"))
	if work_activity == "sleep" and sleep_bed == Transform3D(): work_activity = "sit_doze"
	speed = WANDER_SPEED
	_wander_pause = float(identity % 5) * .7
	resident_model.hand_provider = _hands
	_build_prop()
	_build_seat()
	_build_social_phone()
	last_position = global_position
	resident_model.teleported()
	process_priority = 1
	if work_activity == "sleep": _lie_down()

func _hands() -> Array:
	if dead or get_meta("workplace_threatened", false): return [null, null]
	var sway := sin(work_clock * 1.7)
	if is_instance_valid(social_routine):
		match social_routine.social.state:
			"calling_police": return [null, resident_model.to_global(Vector3(.19, 1.6, .12))]
			"happy": return [null, resident_model.to_global(Vector3(.36 + sway * .035, 1.43, .2))]
			"talking": return [null, null] # Native conversational arm motion.
			"annoyed": return [resident_model.to_global(Vector3(-.23, 1.02, .12)), resident_model.to_global(Vector3(.23, 1.02, .12))]
			"scared": return [resident_model.to_global(Vector3(-.22, 1.43, .21)), resident_model.to_global(Vector3(.22, 1.43, .21))]
			"recovering": return [null, resident_model.to_global(Vector3(.08, 1.22, .26))]
		if social_routine.social.routine_phase == "pause": return [null, null]
	match work_activity:
		"phone": return [null, resident_model.to_global(Vector3(.18, 1.51, .14))]
		"repair": return [resident_model.to_global(Vector3(-.15, 1.10, .52)), resident_model.to_global(Vector3(.15, 1.12 + sin(work_clock * 3.0) * .035, .57))]
		"cook": return [resident_model.to_global(Vector3(-.18, 1.17, .50)), resident_model.to_global(Vector3(-.16 + cos(work_clock * 1.6) * .04, 1.26, .57 + sway * .035))]
		"write": return [resident_model.to_global(Vector3(-.16, 1.10, .34)), resident_model.to_global(Vector3(.12 + sway * .03, 1.12, .38))]
		"sit_write": return [resident_model.to_global(Vector3(-.16, .90, .46)), resident_model.to_global(Vector3(.12 + sway * .03, .92, .50))]
		"sit_read": return [resident_model.to_global(Vector3(-.14, .78, .32)), resident_model.to_global(Vector3(.14, .78, .32))]
		"sit_phone": return [resident_model.to_global(Vector3(-.05, .92, .26)), resident_model.to_global(Vector3(.07 + sway * .01, .95, .28))]
		"tv", "sleep", "sit_doze", "chat": return [null, null]
		"coffee": return [null, resident_model.to_global(_mug_point())]
		"clean":
			var stroke := sin(work_clock * 2.4) * .14
			return [resident_model.to_global(Vector3(-.04 + stroke * .4, 1.10, .26)), resident_model.to_global(Vector3(.04 + stroke * .7, .82, .36))]
		"stretch":
			# De vez em quando se espreguiça; no resto do tempo fica olhando em volta.
			if fposmod(work_clock + float(identity % 7), 9.0) < 2.2:
				return [resident_model.to_global(Vector3(-.20, 1.98, .02)), resident_model.to_global(Vector3(.20, 1.98, .02))]
			return [null, null]
		"wander":
			if automatic_direction.length_squared() > .01: return [null, null]
			return [resident_model.to_global(Vector3(-.16, 1.17, .35)), resident_model.to_global(Vector3(.16, 1.17, .35))]
		_: return [resident_model.to_global(Vector3(-.16, 1.17, .35)), resident_model.to_global(Vector3(.16, 1.17, .35))]

func _mug_point() -> Vector3:
	# Gole a cada ~7 s; no resto, a caneca fica na altura do peito.
	var sip := clampf(sin(fposmod(work_clock + float(identity % 5), 7.0) / 1.4 * PI), 0.0, 1.0) if fposmod(work_clock + float(identity % 5), 7.0) < 1.4 else 0.0
	return Vector3(.16, 1.12, .28).lerp(Vector3(.06, 1.52, .14), sip)

func _build_prop() -> void:
	prop = Node3D.new()
	prop.name = "ActivityProp_" + work_activity
	resident_model.add_child(prop)
	if work_activity in ["phone", "sit_phone"]:
		prop.position = Vector3(.18, 1.51, .14) if work_activity == "phone" else Vector3(.07, .97, .28)
		if work_activity == "sit_phone": prop.rotation.x = -1.1
		_box(prop, Vector3.ZERO, Vector3(.073, .15, .018), "344544", "metal")
	elif work_activity in ["repair", "cook"]:
		_box(prop, Vector3(0, -.08, 0), Vector3(.026, .24, .035), "977441", "wood")
		_box(prop, Vector3(0, -.22, 0), Vector3(.075, .06, .07), "aaa998" if work_activity == "repair" else "977441", "metal" if work_activity == "repair" else "wood")
	elif work_activity == "coffee":
		_box(prop, Vector3(0, -.02, .03), Vector3(.08, .10, .08), "b8bca7", "ceramic")
	elif work_activity == "clean":
		# Vassoura: cabo da mão até o chão, cerdas à frente dos pés.
		_box(prop, Vector3(0, .60, 0), Vector3(.03, 1.20, .03), "8d7049", "wood")
		_box(prop, Vector3(0, .03, 0), Vector3(.30, .06, .08), "6b5a40", "wood")
	elif work_activity in ["tv", "sleep", "sit_doze", "chat", "stretch", "wander"]:
		pass
	else:
		prop.position = Vector3(0, 1.17, .37) if work_activity != "sit_read" else Vector3(0, .80, .32)
		prop.rotation.x = -.20 if work_activity != "sit_read" else -.75
		_box(prop, Vector3.ZERO, Vector3(.36, .027, .28), "655841", "wood")
		_box(prop, Vector3(0, .021, 0), Vector3(.32, .018, .25), "d6d0b4", "paper")
		for line in 4: _box(prop, Vector3(0, .034, -.07 + line * .047), Vector3(.24, .004, .006), "817f70", "paper")

func _build_seat() -> void:
	seat = Node3D.new()
	seat.name = "Seat"
	add_child(seat)
	# Banquinho/cadeira inteiro dentro do raio da cápsula (0,30 m): o corpo
	# sentado não invade móveis nem o corredor.
	var wood := str(specification.get("appearance", {}).get("coat", "6b5a40"))
	_box(seat, Vector3(0, .42, -.06), Vector3(.40, .06, .38), "6b5a40", "wood")
	for x in [-.16, .16]:
		for z in [-.22, .10]: _box(seat, Vector3(x, .20, z), Vector3(.04, .40, .04), "4c4a45", "metal")
	if work_activity != "sit_doze": _box(seat, Vector3(0, .70, -.25), Vector3(.38, .44, .04), wood, "cloth")
	seat.visible = work_activity in SEATED

func _build_social_phone() -> void:
	social_phone = Node3D.new()
	social_phone.name = "EmergencyPhone"
	social_phone.position = Vector3(.19, 1.6, .12)
	resident_model.add_child(social_phone)
	_box(social_phone, Vector3.ZERO, Vector3(.073, .15, .018), "344544", "metal")
	social_phone.hide()

func configure_social(owner_gameplay: Node, reaction: Node, illicit: bool) -> void:
	if is_instance_valid(social_routine): return
	social_routine = SOCIAL_ROUTINE.new()
	social_routine.name = "BuildingSocialRoutine"
	social_routine.configure(self, owner_gameplay, reaction, specification, illicit)
	add_child(social_routine)
	add_to_group("social_npc")
	if is_instance_valid(reaction): reaction.threat_started.connect(_threat_started)

func social_options() -> Array[Dictionary]:
	return social_routine.social.options() if is_instance_valid(social_routine) else []

func social_snapshot() -> Dictionary:
	return social_routine.snapshot() if is_instance_valid(social_routine) else {"can_interact":false}

func begin_social(player: Node3D) -> bool:
	if sleeping: wake()
	return is_instance_valid(social_routine) and social_routine.begin_social(player)

func end_social() -> void:
	if is_instance_valid(social_routine): social_routine.end_social()

func social_interact(action: String, player: Node3D = null) -> Dictionary:
	return social_routine.interact(action, player) if is_instance_valid(social_routine) else {"ok":false}

func present_social_threat(calling: bool) -> void:
	if is_instance_valid(social_phone): social_phone.visible = calling and not dead and is_visible_in_tree()
	if dead or calling or get_meta("workplace_threatened", false): prop.hide()

## Ameaça: levanta na hora (banquinho some), acorda e suspende o passeio.
func _threat_started(_resident: Node3D) -> void:
	if sleeping: wake()
	resident_model.sit_amount = 0.0
	seat.hide()
	automatic_direction = Vector3.ZERO
	_wander_hold = WANDER_HOLD_AFTER_THREAT

func _lie_down() -> void:
	sleeping = true
	# Ninguém esbarra num corpo invisível ao lado da cama: a cápsula sai das
	# camadas de colisão enquanto o corpo visível está sobre o colchão.
	_layer = collision_layer
	collision_layer = 0
	_place_on_bed()

func _place_on_bed() -> void:
	# Pés para o lado oposto à cabeceira (-Z da cama), rosto para cima.
	var basis := sleep_bed.basis.orthonormalized() * Basis(Vector3.RIGHT, -PI * .5)
	visual.global_transform = Transform3D(basis, sleep_bed * Vector3(0, .13, .86))

func wake() -> void:
	if not sleeping: return
	sleeping = false
	collision_layer = _layer
	visual.transform = Transform3D.IDENTITY
	work_activity = "stretch"
	prop.name = "ActivityProp_stretch"
	if is_instance_valid(social_routine): social_routine.social.activity = "stretch"
	resident_model.teleported()

func _process(delta: float) -> void:
	if dead:
		prop.hide()
		social_phone.hide()
		seat.hide()
		automatic_direction = Vector3.ZERO
		resident_model.hand_provider = Callable()
		resident_model.sit_amount = 0.0
		set_process(false)
		return
	if get_meta("workplace_threatened", false):
		prop.hide()
		return
	work_clock += delta
	_wander_hold = maxf(0.0, _wander_hold - delta)
	var working := true
	var calm := true
	var social: RefCounted = social_routine.social if is_instance_valid(social_routine) else null
	if social != null:
		calm = social.state == "calm"
		working = calm and social.routine_phase == "work"
		if sleeping and social.state not in ["calm", "talking"]: wake()
	if sleeping:
		prop.visible = false
		_place_on_bed()
		return
	# Sentado continua sentado na pausa e na conversa; levanta com medo.
	var seated: bool = work_activity in SEATED and (social == null or social.state in ["calm", "talking", "happy", "annoyed"])
	resident_model.sit_amount = move_toward(float(resident_model.sit_amount), 1.0 if seated else 0.0, delta * 2.5)
	seat.visible = resident_model.sit_amount > .35
	var target_yaw := 0.0
	var talking := false
	if social != null:
		talking = social.state in ["talking", "happy"]
		social_phone.visible = social.state == "calling_police"
	var player_partner: Node3D = social_routine.partner if is_instance_valid(social_routine) else null
	if is_instance_valid(player_partner):
		var offset: Vector3 = to_local(player_partner.global_position)
		target_yaw = atan2(offset.x, offset.z)
	elif work_activity == "chat" and is_instance_valid(chat_partner) and calm:
		var offset: Vector3 = to_local(chat_partner.global_position)
		target_yaw = atan2(offset.x, offset.z)
		# A dupla alterna a fala a cada ~3 s.
		talking = int((work_clock + chat_offset) / 3.2) % 2 == 0
	if work_activity == "wander":
		target_yaw = _wander(delta, social, working)
	resident_model.activity = "talk" if talking else ""
	_visual_yaw = lerp_angle(_visual_yaw, target_yaw, 1.0 - exp(-(7.0 if work_activity == "wander" else 4.0) * delta))
	visual.rotation.y = _visual_yaw
	prop.visible = working and work_activity not in ["wander", "chat", "stretch", "tv", "sit_doze"]
	if not working: return
	if work_activity in ["repair", "cook"] and resident_model.forearms.size() > 1:
		prop.global_position = resident_model.forearms[1].to_global(Vector3(0, -preload("res://assets/civilians/CivilianMeshKit.gd").FOREARM, 0))
		prop.rotation = Vector3(.14, 0, .12)
	elif work_activity == "coffee":
		prop.position = _mug_point()
	elif work_activity == "clean":
		var stroke := sin(work_clock * 2.4) * .14
		prop.position = Vector3(stroke * .7, 0, .55)
		prop.rotation = Vector3(-.42, 0, -stroke * .6)
	# Small head movements show attention without moving the collision capsule.
	var pitch := .14 + sin(work_clock * .65) * .025
	if work_activity == "sit_doze": pitch = .55 + sin(work_clock * .4) * .04
	elif work_activity == "tv": pitch = -.05 + sin(work_clock * .3) * .02
	elif work_activity in ["stretch", "chat"]: pitch = .02
	resident_model.head_node.rotation.x = pitch

## Passeio entre pontos livres do cômodo; para quando o jogador chega perto,
## numa conversa, com medo ou logo depois de uma ameaça.
func _wander(delta: float, social: RefCounted, working: bool) -> float:
	var player_near := false
	if is_instance_valid(social_routine) and social_routine._has_gameplay():
		player_near = social_routine.gameplay.player.global_position.distance_squared_to(global_position) < 2.6 * 2.6
	if wander_points.size() < 2 or not working or player_near or _wander_hold > 0.0 or (social != null and social.state != "calm"):
		automatic_direction = Vector3.ZERO
		return _wander_yaw
	if _wander_pause > 0.0:
		_wander_pause -= delta
		automatic_direction = Vector3.ZERO
		return _wander_yaw
	var offset := wander_points[_wander_index] - global_position
	offset.y = 0.0
	if offset.length() < .22:
		automatic_direction = Vector3.ZERO
		_wander_index = (_wander_index + 1) % wander_points.size()
		_wander_pause = 2.5 + float((identity + _wander_index * 13) % 7) * .6
		_wander_stuck = 0.0
		return _wander_yaw
	var direction := offset.normalized()
	automatic_direction = direction
	# Travou (alguém no caminho): desiste deste ponto e segue para o próximo.
	_wander_stuck += delta
	if _wander_stuck > 6.0:
		_wander_stuck = 0.0
		_wander_index = (_wander_index + 1) % wander_points.size()
	var local := global_basis.inverse() * direction
	_wander_yaw = atan2(local.x, local.z)
	return _wander_yaw

func _box(parent: Node3D, at: Vector3, size: Vector3, color: String, kind: String) -> void:
	var visual_prop := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual_prop.mesh = mesh
	visual_prop.position = at
	visual_prop.material_override = MATERIALS.material(kind, Color(color))
	parent.add_child(visual_prop)
