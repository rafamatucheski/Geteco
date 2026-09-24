extends Node3D
## V2 presentation for the Monaliza trunk, adapted from V1's
## res://world/harbor/monaliza/TrunkLiveView.gd. V1 needed a SubViewport
## projection hack because its world was 2D; V2's world is already real 3D,
## so this opens the actual trunk lid on the actual parked car, lights the
## actual trunk bay and places the actual weapon models inside it, framed by
## the existing CameraRig instead of a synthetic showcase stage.

const WEAPON := preload("res://gameplay/ArsenalWeapon3D.gd")
const PIVOT_NAME := "MonalizaTrunkHinge"
const OPEN_ANGLE := -2.15
const OPEN_SPEED := 2.6
# Same model-root-space offsets as V1's TrunkLiveView.SLOT_POSITIONS: both
# come from the same res://world/harbor/monaliza/MonalizaModel.gd geometry,
# and geteco_v2's baked res://assets/fleet/monaliza.scn preserves that space.
const SLOT_POSITIONS := {
	"longa": Vector3(0.12, 0.67, 1.66),
	"curta": Vector3(-0.38, 0.67, 1.97),
	"corpo": Vector3(0.35, 0.67, 1.97),
	"granada": Vector3(-0.02, 0.70, 1.96),
}
const SLOT_LABELS := {"longa": "LONGA", "curta": "CURTA", "corpo": "CORPO", "granada": "GRANADA"}
const CLOSE_OFFSET := Vector3(0, 6.2, 4.6)
const CLOSE_SIZE := 6.4
const TRAY_CENTER := Vector3(0, 0.648, 1.80)
# The baked res://assets/fleet/monaliza.scn is a flat, unlabeled mesh dump
# (277 anonymous MeshInstance3D children, no MonalizaTrunkHinge survives the
# bake) with no hollow trunk cavity to reveal, so a loadout sitting at deck
# height renders buried inside solid bodywork. `_safety()` (no_depth_test)
# already guarantees it draws regardless of that; LIFT_HEIGHT only has to
# clear the tray off the paint enough to read as "raised into view", not
# clear the whole car -- a large lift reads as a platform floating in the
# air disconnected from the car, which is worse than the bug it fixed.
const LIFT_HEIGHT := 0.2

var car: Node3D
var pivot: Node3D
var weapons: Node3D
var dressing: Node3D
var slot_models: Dictionary = {}
var slot_pads: Dictionary = {}
var cutouts: Dictionary = {}
var displayed: Dictionary = {}
var courtesy_light: OmniLight3D
var accent_light: SpotLight3D
var _camera: Camera3D
var _saved: Dictionary = {}
var _open_amount := 0.0

func open(active_car: Node3D, camera: Camera3D) -> void:
	car = active_car
	if not is_instance_valid(car) or not is_instance_valid(car.get("visual")): return
	pivot = car.visual.find_child(PIVOT_NAME, true, false)
	if weapons == null:
		weapons = Node3D.new()
		weapons.name = "TrunkLoadoutDisplay"
		car.visual.add_child(weapons)
		_build_dressing()
	_camera = camera
	if is_instance_valid(_camera) and _saved.is_empty():
		_saved = {
			"target": _camera.target, "locked": _camera.locked,
			"offset": _camera.offset, "target_size": _camera.target_size,
		}
		_camera.target = car
		_camera.locked = true
		_camera.offset = CLOSE_OFFSET
		_camera.target_size = CLOSE_SIZE
	set_process(true)

func update_loadout(slots: Dictionary) -> void:
	for slot in SLOT_POSITIONS:
		var id := String(slots.get(slot, ""))
		if displayed.has(slot) and String(displayed[slot]) == id: continue
		_replace_weapon(slot, id)

func _replace_weapon(slot: String, id: String) -> void:
	if slot_models.has(slot) and is_instance_valid(slot_models[slot]):
		slot_models[slot].free()
	var holder := Node3D.new()
	holder.name = "Trunk_" + slot
	weapons.add_child(holder)
	holder.position = SLOT_POSITIONS[slot]
	holder.rotation_degrees = Vector3(0, -90, 90)
	if slot != "longa": holder.scale = Vector3.ONE * 1.25
	if not id.is_empty():
		WEAPON.build(holder, id)
		for part in holder.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == null: continue
			for surface in part.mesh.get_surface_count():
				var material: Material = part.mesh.surface_get_material(surface)
				if material is StandardMaterial3D: _safety(material)
	slot_models[slot] = holder
	displayed[slot] = id
	_rebuild_cutout(slot, holder, not id.is_empty())

func _process(delta: float) -> void:
	if not is_instance_valid(weapons): return
	_open_amount = move_toward(_open_amount, 1.0, delta * OPEN_SPEED)
	# Ease-out: fast off the latch, settling gently at the top of the rise.
	var eased := 1.0 - pow(1.0 - _open_amount, 3.0)
	if is_instance_valid(pivot): pivot.rotation.x = lerpf(0.0, OPEN_ANGLE, eased)
	weapons.position.y = lerpf(0.0, LIFT_HEIGHT, eased)
	if is_instance_valid(courtesy_light): courtesy_light.light_energy = 0.85 * eased
	if is_instance_valid(accent_light): accent_light.light_energy = 1.6 * eased

func close() -> void:
	set_process(false)
	if is_instance_valid(_camera) and not _saved.is_empty():
		_camera.target = _saved.get("target")
		_camera.locked = _saved.get("locked", false)
		_camera.offset = _saved.get("offset", _camera.offset)
		_camera.target_size = _saved.get("target_size", _camera.target_size)
	_saved.clear()
	if is_instance_valid(pivot): pivot.rotation.x = 0.0
	if is_instance_valid(weapons): weapons.free()
	weapons = null
	dressing = null
	courtesy_light = null
	accent_light = null
	slot_models.clear()
	slot_pads.clear()
	cutouts.clear()
	displayed.clear()
	car = null
	pivot = null
	_camera = null
	_open_amount = 0.0
	queue_free()

# ---------------------------------------------------------------------------
# Trunk dressing: felt-lined tray, stitched trim, a courtesy light and a
# roadside kit, matching the level of finish V1's TrunkLiveView built for the
# same car. Built once per open() and freed with the rest of `weapons`.

func _safety(material: StandardMaterial3D) -> StandardMaterial3D:
	# The tray floats clear of the car on open (see LIFT_HEIGHT), but a still
	# mid-rise tray or a stray strut can dip into its own depth range; render
	# it through minor overlaps rather than risk it vanishing into the body.
	material.no_depth_test = true
	material.render_priority = 5
	return material

func _detail_mat(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic = metal
	return _safety(material)

func _felt_mat() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("2c3634")
	material.roughness = 0.97
	var grain := NoiseTexture2D.new()
	grain.width = 128
	grain.height = 128
	var noise := FastNoiseLite.new()
	noise.frequency = 0.6
	grain.noise = noise
	material.albedo_texture = grain
	return _safety(material)

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	parent.add_child(part)
	return part

func _build_dressing() -> void:
	dressing = Node3D.new()
	dressing.name = "TrunkDressing"
	weapons.add_child(dressing)
	var trim := _detail_mat(Color("161e23"))
	var steel := _detail_mat(Color("879094"), 0.32, 0.7)
	var thread := _detail_mat(Color("8a8065"))
	var felt := _felt_mat()

	# Felt-lined tray floor under the whole loadout, with a stitched perimeter.
	_box(dressing, TRAY_CENTER + Vector3(0, -0.006, 0), Vector3(1.5, 0.01, 0.72), felt)
	for x in [-0.72, 0.72]:
		_box(dressing, Vector3(x, 0.648, 1.80), Vector3(0.025, 0.018, 0.73), trim)
		for i in 23:
			_box(dressing, Vector3(x, 0.66, 1.46 + i * 0.030), Vector3(0.010, 0.003, 0.013), thread)
	for z in [1.44, 2.15]:
		_box(dressing, Vector3(0, 0.648, z), Vector3(1.45, 0.018, 0.025), trim)

	# Individual felt pads under each slot, so an empty slot still reads as
	# "a place for a gun" instead of bare tray.
	for slot in SLOT_POSITIONS:
		var slot_pos: Vector3 = SLOT_POSITIONS[slot]
		var pad := _box(dressing, Vector3(slot_pos.x, 0.649, slot_pos.z), Vector3(0.30, 0.006, 0.30), _felt_mat())
		slot_pads[slot] = pad
		var label := Label3D.new()
		label.text = SLOT_LABELS[slot]
		label.font_size = 22
		label.pixel_size = 0.0011
		label.modulate = Color(0.72, 0.70, 0.60, 0.85)
		label.outline_size = 0
		label.no_depth_test = true
		label.render_priority = 5
		label.rotation_degrees.x = -90
		label.position = Vector3(slot_pos.x, 0.654, slot_pos.z + 0.16)
		dressing.add_child(label)

	# Roadside emergency kit riding beside the loadout, exactly like V1's.
	_build_warning_triangle(trim, steel)

	# Courtesy light: warm point light that reads the loadout regardless of
	# outdoor time of day, plus a tight spot for a cleaner rim on the guns.
	courtesy_light = OmniLight3D.new()
	courtesy_light.name = "TrunkCourtesyLight"
	courtesy_light.position = Vector3(-0.64, 1.05, 1.79)
	courtesy_light.light_color = Color("ffdfab")
	courtesy_light.omni_range = 2.2
	courtesy_light.omni_attenuation = 1.4
	courtesy_light.light_energy = 0.0
	dressing.add_child(courtesy_light)

	accent_light = SpotLight3D.new()
	accent_light.name = "TrunkAccentLight"
	accent_light.position = Vector3(0, 1.7, 1.8)
	accent_light.rotation_degrees = Vector3(-90, 0, 0)
	accent_light.light_color = Color("f3f2e6")
	accent_light.spot_range = 2.4
	accent_light.spot_angle = 42.0
	accent_light.spot_attenuation = 1.1
	accent_light.light_energy = 0.0
	accent_light.shadow_enabled = false
	dressing.add_child(accent_light)

func _build_warning_triangle(trim: Material, steel: Material) -> void:
	var triangle := Node3D.new()
	triangle.name = "EmergencyWarningTriangle"
	dressing.add_child(triangle)
	triangle.position = Vector3(0.66, 0.655, 2.02)
	var red := _detail_mat(Color("d93620"), 0.25, 0.3)
	var reflective := _detail_mat(Color("ff7645"), 0.18, 0.5)
	var points := [Vector3(-0.09, 0, 0.06), Vector3(0.09, 0, 0.06), Vector3(0, 0, -0.085)]
	for i in 3:
		var edge := Node3D.new()
		triangle.add_child(edge)
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % 3]
		edge.position = (a + b) * 0.5
		edge.rotation.y = atan2(b.x - a.x, b.z - a.z)
		_box(edge, Vector3.ZERO, Vector3(0.019, 0.009, a.distance_to(b) + 0.012), red)
		_box(edge, Vector3(0, -0.005, 0), Vector3(0.008, 0.003, a.distance_to(b)), reflective)
	for x in [-0.06, 0.06]:
		_box(triangle, Vector3(x, -0.01, 0.06), Vector3(0.015, 0.014, 0.03), trim)
	_box(dressing, triangle.position + Vector3(0, -0.006, 0), Vector3(0.24, 0.01, 0.2), steel)

func _rebuild_cutout(slot: String, weapon: Node3D, filled: bool) -> void:
	if cutouts.has(slot) and is_instance_valid(cutouts[slot]):
		cutouts[slot].free()
	if not is_instance_valid(dressing): return
	var pad: MeshInstance3D = slot_pads.get(slot)
	if not is_instance_valid(pad): return
	# A filled slot recesses a silhouette of the actual weapon into the felt;
	# an empty slot keeps a plain outline so the tray still reads as organised.
	pad.material_override.albedo_color = Color("232c2a") if filled else Color("2c3634")
	if not filled:
		cutouts.erase(slot)
		return
	var inset := Node3D.new()
	inset.name = "Cutout_" + slot
	weapons.add_child(inset)
	inset.position = weapon.position
	inset.position.y = 0.652
	inset.scale = Vector3(1.10, 0.025, 1.10)
	var shadow := _detail_mat(Color("0c1113"))
	for part in weapon.find_children("*", "MeshInstance3D", true, false):
		var silhouette := MeshInstance3D.new()
		silhouette.mesh = part.mesh
		silhouette.material_override = shadow
		silhouette.transform = Transform3D(weapon.basis, Vector3.ZERO) * (weapon.global_transform.affine_inverse() * part.global_transform)
		inset.add_child(silhouette)
	cutouts[slot] = inset
