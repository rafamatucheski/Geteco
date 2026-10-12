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
# Geometria do compartimento (espaço do modelo, mesmo das posições dos slots).
const FLOOR_Y := 0.648
const WALL_X := 0.76
const FOAM_THICKNESS := 0.032
const FOAM_CENTER_X := -0.03
const FOAM_WIDTH := 1.18
# As armas assentam em cima da espuma; DROP_HEIGHT é a altura de onde descem.
const SEAT_LIFT := 0.03
const DROP_HEIGHT := 0.14

var car: Node3D
var pivot: Node3D
var weapons: Node3D
var dressing: Node3D
var slot_models: Dictionary = {}
var slot_pads: Dictionary = {}
var slot_straps: Dictionary = {}
var slot_leds: Dictionary = {}
var led_mats: Array[StandardMaterial3D] = []
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
	var rest: Vector3 = SLOT_POSITIONS[slot] + Vector3(0, SEAT_LIFT, 0)
	holder.position = rest
	holder.rotation_degrees = Vector3(0, -90, 90)
	if slot != "longa": holder.scale = Vector3.ONE * 1.25
	if not id.is_empty():
		# A arma desce até a espuma em vez de aparecer já encaixada.
		holder.position.y += DROP_HEIGHT
		holder.create_tween().tween_property(holder, "position:y", rest.y, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	for led in led_mats: led.emission_energy_multiplier = 1.6 * eased
	for led in slot_leds.values(): led.emission_energy_multiplier = 2.2 * eased

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
	slot_straps.clear()
	slot_leds.clear()
	led_mats.clear()
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

## Material com teste de profundidade normal: o interior do compartimento
## precisa que as paredes escondam o que está atrás delas, senão tudo volta a
## parecer chapado. A bandeja já sobe LIFT_HEIGHT acima da lataria ao abrir, então
## não precisa mais do no_depth_test que as armas ainda usam.
func _solid_mat(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic = metal
	return material

func _textured_mat(color: Color, noise_type: int, frequency: float, rough := 0.97) -> StandardMaterial3D:
	var material := _solid_mat(color, rough)
	var grain := NoiseTexture2D.new()
	grain.width = 128
	grain.height = 128
	var noise := FastNoiseLite.new()
	noise.noise_type = noise_type
	noise.frequency = frequency
	grain.noise = noise
	material.albedo_texture = grain
	return material

func _led_mat(color: Color) -> StandardMaterial3D:
	var material := _solid_mat(color.darkened(0.6), 0.4)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.0
	return material

func _torus(parent: Node3D, pos: Vector3, inner: float, outer: float, material: Material, flat := true) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 8
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	if not flat: part.rotation_degrees.x = 90
	parent.add_child(part)
	return part

func _build_dressing() -> void:
	dressing = Node3D.new()
	dressing.name = "TrunkDressing"
	weapons.add_child(dressing)
	var trim := _solid_mat(Color("161e23"))
	var steel := _solid_mat(Color("879094"), 0.32, 0.7)
	var thread := _solid_mat(Color("8a8065"))
	var carpet := _textured_mat(Color("232b2a"), FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.6)
	var shade := _solid_mat(Color("070a0b"), 1.0)
	var foam := _textured_mat(Color("1b2123"), FastNoiseLite.TYPE_CELLULAR, 1.6, 1.0)
	led_mats.clear()

	# Piso forrado e abaixo dele uma sombra escura: dá a sensação de cavidade
	# em vez de uma tábua apoiada em cima da lataria.
	_box(dressing, TRAY_CENTER + Vector3(0, -0.012, 0), Vector3(1.5, 0.012, 0.74), shade)
	_box(dressing, TRAY_CENTER + Vector3(0, -0.004, 0), Vector3(1.48, 0.008, 0.72), carpet)

	# Paredes do compartimento: laterais, fundo (lado da cabine) e uma borda
	# baixa na traseira, cada uma com friso metálico no topo.
	for x in [-WALL_X, WALL_X]:
		_box(dressing, Vector3(x, FLOOR_Y + 0.07, 1.80), Vector3(0.05, 0.14, 0.76), carpet)
		_box(dressing, Vector3(x, FLOOR_Y + 0.145, 1.80), Vector3(0.062, 0.012, 0.78), steel)
		for i in 23:
			_box(dressing, Vector3(x - signf(x) * 0.026, FLOOR_Y + 0.11, 1.46 + i * 0.030), Vector3(0.003, 0.010, 0.013), thread)
	_box(dressing, Vector3(0, FLOOR_Y + 0.10, 1.425), Vector3(1.55, 0.20, 0.05), carpet)
	_box(dressing, Vector3(0, FLOOR_Y + 0.205, 1.425), Vector3(1.57, 0.012, 0.062), steel)
	_box(dressing, Vector3(0, FLOOR_Y + 0.025, 2.185), Vector3(1.55, 0.05, 0.04), carpet)
	_box(dressing, Vector3(0, FLOOR_Y + 0.052, 2.185), Vector3(1.57, 0.008, 0.052), steel)

	# Faixa de LED sob o friso: ilumina a espuma e acende junto com a tampa.
	var strip := _led_mat(Color("ffd9a0"))
	led_mats.append(strip)
	for x in [-WALL_X + 0.03, WALL_X - 0.03]:
		_box(dressing, Vector3(x, FLOOR_Y + 0.135, 1.80), Vector3(0.012, 0.008, 0.70), strip)
	_box(dressing, Vector3(0, FLOOR_Y + 0.193, 1.45), Vector3(1.46, 0.008, 0.012), strip)

	# Espuma de alta densidade com a altura do conjunto: é nela que as armas
	# se encaixam. O kit de emergência fica na faixa livre à direita.
	_box(dressing, Vector3(FOAM_CENTER_X, FLOOR_Y + FOAM_THICKNESS * 0.5, 1.80), Vector3(FOAM_WIDTH, FOAM_THICKNESS, 0.64), foam)
	_box(dressing, Vector3(FOAM_CENTER_X, FLOOR_Y + 0.004, 1.80), Vector3(FOAM_WIDTH + 0.03, 0.008, 0.67), trim)

	# Argolas de amarração nos cantos da espuma.
	for corner in [Vector2(-0.69, 1.50), Vector2(-0.69, 2.10), Vector2(0.65, 1.50)]:
		_box(dressing, Vector3(corner.x, FLOOR_Y + 0.006, corner.y), Vector3(0.05, 0.012, 0.05), steel)
		_torus(dressing, Vector3(corner.x, FLOOR_Y + 0.02, corner.y), 0.011, 0.021, steel)

	for slot in SLOT_POSITIONS:
		_build_slot(slot, trim, steel, foam)

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

## Fixação de cada tipo de arma: berço com tira para a longa, fita elástica para
## a curta, bainha com alças para a arma branca e copo de borracha para a
## granada. As peças que só fazem sentido com a arma presente ficam em
## `slot_straps` e aparecem/somem em `_rebuild_cutout`.
func _build_slot(slot: String, trim: Material, steel: Material, foam: Material) -> void:
	var slot_pos: Vector3 = SLOT_POSITIONS[slot]
	var top := FLOOR_Y + FOAM_THICKNESS
	var rubber := _solid_mat(Color("0d1112"), 0.9)
	var nylon := _solid_mat(Color("c9601c"), 0.8)
	var straps: Array[Node3D] = []

	# Poço escuro no formato da área do slot; a silhueta da arma é desenhada
	# por cima dele em _rebuild_cutout.
	var pad := _box(dressing, Vector3(slot_pos.x, top + 0.001, slot_pos.z), Vector3(0.34, 0.003, 0.30), _solid_mat(Color("0a0e0f"), 1.0))
	slot_pads[slot] = pad

	# Moldura em baixo-relevo: quatro frisos finos marcam o lugar mesmo vazio.
	var frame_color := _solid_mat(Color("3c4745"), 0.9)
	for z in [-0.15, 0.15]:
		_box(dressing, Vector3(slot_pos.x, top + 0.003, slot_pos.z + z), Vector3(0.36, 0.004, 0.008), frame_color)
	for x in [-0.18, 0.18]:
		_box(dressing, Vector3(slot_pos.x + x, top + 0.003, slot_pos.z), Vector3(0.008, 0.004, 0.30), frame_color)

	match slot:
		"longa":
			# Dois berços de borracha em U sobre pinos de aço, com tira de
			# nylon e fivela cruzando a arma.
			for dx in [-0.22, 0.22]:
				var base := slot_pos + Vector3(dx, 0, 0)
				_box(dressing, Vector3(base.x, top + 0.012, base.z), Vector3(0.05, 0.024, 0.15), rubber)
				for dz in [-0.07, 0.07]:
					_box(dressing, Vector3(base.x, top + 0.04, base.z + dz), Vector3(0.05, 0.05, 0.022), rubber)
				_box(dressing, Vector3(base.x, top + 0.026, base.z), Vector3(0.012, 0.006, 0.17), steel)
			var strap := Node3D.new()
			strap.position = Vector3(slot_pos.x + 0.10, top + 0.075, slot_pos.z)
			dressing.add_child(strap)
			_box(strap, Vector3.ZERO, Vector3(0.036, 0.008, 0.20), nylon)
			_box(strap, Vector3(0, 0.006, 0.07), Vector3(0.05, 0.012, 0.03), steel)
			straps.append(strap)
		"curta":
			# Pistola presa por fita elástica e dois ganchos de aço.
			for dz in [-0.12, 0.12]:
				_box(dressing, Vector3(slot_pos.x, top + 0.02, slot_pos.z + dz), Vector3(0.05, 0.04, 0.02), steel)
			var band := Node3D.new()
			band.position = Vector3(slot_pos.x + 0.04, top + 0.052, slot_pos.z)
			dressing.add_child(band)
			_box(band, Vector3.ZERO, Vector3(0.018, 0.006, 0.26), nylon)
			straps.append(band)
		"corpo":
			# Bainha de couro: duas alças com botão de pressão.
			var leather := _solid_mat(Color("3a2616"), 0.8)
			for dx in [-0.10, 0.10]:
				_box(dressing, Vector3(slot_pos.x + dx, top + 0.02, slot_pos.z - 0.10), Vector3(0.03, 0.04, 0.03), leather)
			var loops := Node3D.new()
			loops.position = Vector3(slot_pos.x, top + 0.05, slot_pos.z)
			dressing.add_child(loops)
			for dx in [-0.10, 0.10]:
				_box(loops, Vector3(dx, 0, 0), Vector3(0.026, 0.008, 0.26), leather)
				_box(loops, Vector3(dx, 0.006, 0.0), Vector3(0.014, 0.008, 0.014), steel)
			straps.append(loops)
		"granada":
			# Copo de borracha com anel de aço e tira de segurança.
			_torus(dressing, Vector3(slot_pos.x, top + 0.02, slot_pos.z), 0.060, 0.082, rubber)
			_torus(dressing, Vector3(slot_pos.x, top + 0.042, slot_pos.z), 0.062, 0.070, steel)
			var tie := Node3D.new()
			tie.position = Vector3(slot_pos.x, top + 0.085, slot_pos.z)
			dressing.add_child(tie)
			_box(tie, Vector3.ZERO, Vector3(0.20, 0.006, 0.018), nylon)
			straps.append(tie)
	slot_straps[slot] = straps
	for strap in straps: strap.visible = false

	# Plaquinha do slot, na frente da espuma (lado do para-choque).
	var label := Label3D.new()
	label.text = SLOT_LABELS[slot]
	label.font_size = 22
	label.pixel_size = 0.0011
	label.modulate = Color(0.78, 0.76, 0.66, 0.9)
	label.outline_size = 0
	label.rotation_degrees.x = -90
	label.position = Vector3(slot_pos.x + 0.02, top + 0.005, slot_pos.z + 0.215)
	dressing.add_child(label)

	# LED de status: âmbar quando vazio, verde quando há arma guardada.
	var led := _led_mat(Color("ffa63a"))
	slot_leds[slot] = led
	_box(dressing, Vector3(slot_pos.x - 0.13, top + 0.004, slot_pos.z + 0.215), Vector3(0.022, 0.008, 0.022), led)

func _build_warning_triangle(trim: Material, steel: Material) -> void:
	var triangle := Node3D.new()
	triangle.name = "EmergencyWarningTriangle"
	dressing.add_child(triangle)
	triangle.position = Vector3(0.65, FLOOR_Y + 0.012, 2.02)
	var red := _solid_mat(Color("d93620"), 0.25, 0.3)
	var reflective := _solid_mat(Color("ff7645"), 0.18, 0.5)
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
	_box(dressing, triangle.position + Vector3(0, -0.006, 0), Vector3(0.18, 0.01, 0.2), steel)

func _rebuild_cutout(slot: String, weapon: Node3D, filled: bool) -> void:
	if cutouts.has(slot) and is_instance_valid(cutouts[slot]):
		cutouts[slot].free()
	if not is_instance_valid(dressing): return
	var pad: MeshInstance3D = slot_pads.get(slot)
	if not is_instance_valid(pad): return
	# A filled slot recesses a silhouette of the actual weapon into the foam;
	# an empty slot keeps a plain outline so the tray still reads as organised.
	var led: StandardMaterial3D = slot_leds.get(slot)
	if led != null:
		var status := Color("46e07a") if filled else Color("ffa63a")
		led.albedo_color = status.darkened(0.6)
		led.emission = status
	for strap in slot_straps.get(slot, []):
		strap.visible = filled
	if not filled:
		cutouts.erase(slot)
		return
	var inset := Node3D.new()
	inset.name = "Cutout_" + slot
	weapons.add_child(inset)
	inset.position = weapon.position
	inset.position.y = FLOOR_Y + FOAM_THICKNESS + 0.003
	inset.scale = Vector3(1.10, 0.025, 1.10)
	var shadow := _solid_mat(Color("030506"), 1.0)
	for part in weapon.find_children("*", "MeshInstance3D", true, false):
		var silhouette := MeshInstance3D.new()
		silhouette.mesh = part.mesh
		silhouette.material_override = shadow
		silhouette.transform = Transform3D(weapon.basis, Vector3.ZERO) * (weapon.global_transform.affine_inverse() * part.global_transform)
		inset.add_child(silhouette)
	cutouts[slot] = inset
