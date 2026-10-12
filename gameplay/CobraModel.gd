extends "res://gameplay/PoliceModel.gd"
## Mesmo corpo e IK dos pedestres; reaproveita somente a pose de armas da polícia.
const LOOK := preload("res://gameplay/urban_v1/CobraAppearance.gd")
var seated := false
var seat_armed := false
var cobra_uniform := true
var standing_body_scale := Vector3.ONE
var _seat_hands: Callable
var _seat_aim_time := 0.0
var _seat_target := Vector3.ZERO

func _ready() -> void:
	model_root = self
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, {
		"role": "cobra", "role_index": tier, "variant": 730 + tier, "female": false, "build": [0, 1, 2][tier],
		"height": [1.0, 1.02, 1.04][tier], "top": 0, "bottom": 0, "shoe": 1,
		"hair": [1, 2, 0][tier], "beard": [0, 1, 2][tier], "hat": 0,
		"glasses": false, "backpack": false, "bag": 0,
		"skin": [Color("c79570"), Color("ac785a"), Color("80553e")][tier],
		"hair_color": Color("171917"), "top_color": Color("23302a"),
		"bottom_color": Color("202522"), "shoe_color": Color("191c19"),
		"inner": Color("222923"), "accent": Color("82916c")})
	torso_node = body.spine
	head_node = body.head_node
	if cobra_uniform: LOOK.dress(self)
	else:
		body.wardrobe.top_color = Color("405e7a") if tier==1 else Color("835e40")
		body._apply_colors()
	if seated:
		body.sit_amount = 1.0
		body.seat_height = .40
		body._pose(0.0)
		if not seat_armed: return
	muzzle_flash_3d = MeshInstance3D.new()
	var flash := SphereMesh.new()
	flash.radius = .045
	flash.height = .09
	muzzle_flash_3d.mesh = flash
	muzzle_flash_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, .8, .2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_3d.material_override = material
	add_child(muzzle_flash_3d)
	equip("pistol" if seated else ["pistol", "shotgun", "smg"][tier])
	weapon.name = "CobraWeapon"
	weapon.visible = not seated
	body._pose(0.0)

func take_hit(direction: Vector3, strength: float) -> void:
	body.take_hit(direction, strength)

func fit_seat(car: Node3D, cabin: Dictionary, driver: bool) -> void:
	standing_body_scale = body.scale
	body.seat_height = float(cabin.cush) - float(cabin.floor)
	body._pose(0.0)
	var above_seat: float = _seated_head_top(car) - float(cabin.cush)
	body.scale *= minf(1.0, (float(cabin.roof) - .05 - float(cabin.cush)) / maxf(above_seat, .1))
	position.z = float(cabin.sz) - .06 * body.scale.y
	if driver:
		var hub := Vector3(cabin.sx, cabin.hub_y, cabin.hub_z)
		body.hand_provider = func() -> Array:
			return [car.to_global(hub + Vector3(cabin.r*.8, 0, .02)), car.to_global(hub + Vector3(-cabin.r*.8, 0, .02))]
	else:
		body.hand_provider = func() -> Array:
			return [body.pelvis.to_global(Vector3(-.13, -.05, .22)), body.pelvis.to_global(Vector3(.13, -.05, .22))]
	body._pose(0.0)
	_seat_hands = body.hand_provider

func _seated_head_top(car: Node3D) -> float:
	if body.head_node.mesh != null:
		var bounds: AABB = car.global_transform.affine_inverse() * body.head_node.global_transform * body.head_node.mesh.get_aabb()
		return bounds.end.y
	# Imported bodies use a meshless pose joint. Carry the authored crown height
	# from the head's rest space into its seated skeleton pose, not the T-pose AABB.
	var rig: RefCounted = body._meshy
	rig.sync()
	var skeleton: Skeleton3D = rig.skeleton
	var head: int = rig._bone("Head")
	var rest: Transform3D = skeleton.get_bone_global_rest(head)
	var mesh_node: MeshInstance3D = rig.mesh_node
	var rest_top: Vector3 = skeleton.global_transform.affine_inverse() * mesh_node.global_transform * Vector3(0, mesh_node.mesh.get_aabb().end.y, 0)
	var crown: Vector3 = rest.affine_inverse() * Vector3(rest.origin.x, rest_top.y, rest.origin.z)
	return car.to_local(skeleton.to_global(skeleton.get_bone_global_pose(head) * crown)).y

func aim_from_seat(target: Vector3, delta: float) -> void:
	_seat_target = target
	_seat_aim_time = .6
	_update_seat_aim(delta)

func _update_seat_aim(delta: float) -> void:
	var direction: Vector3 = get_parent().to_local(_seat_target) - position
	rotation.y = atan2(-direction.x, -direction.z)
	weapon.show()
	update_pose(delta, true, false, 0.0, 0.0)

func rest_in_seat(delta: float) -> void:
	if _seat_aim_time > 0.0:
		_seat_aim_time = maxf(0.0, _seat_aim_time - delta)
		_update_seat_aim(delta)
		return
	update_pose(delta, false, false, 0.0, 0.0)
	weapon.hide()
	rotation.y = 0.0
	body.hand_provider = _seat_hands
