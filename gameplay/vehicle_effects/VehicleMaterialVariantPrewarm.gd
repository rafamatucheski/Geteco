extends RefCounted
## Prepara sob a cortina as variantes de material de veículo que só surgem em
## jogo: sujeira de uso (VehicleUsage), desgaste/amassado e carcaça queimada
## (VehicleDamage). Os vidros da cabine mantêm os materiais originais. Cada
## combinação nova de flags do StandardMaterial3D gera uma versão
## SceneForwardMobileShaderRD; com cache frio ela compilava no primeiro desenho:
## draws de 47–68 ms (rec2/rec3 e first-draw-*, 05/10/2026; chaves 502cb30b e
## 0af590d5 = pintura suja / limpa depois de suja, 10b0b8ea = desgaste,
## f24a1c0a = vidro translúcido, 3d4ae273 = brasa da carcaça).
## Só cria cópias de material e caixas temporárias de desenho: nenhum veículo,
## RNG, população ou colisão. Cada material desenhado fica retido para o shader
## continuar no mapa do motor; o primeiro uso real com as mesmas flags o reutiliza.
const PAINT = preload("res://runtime/VehiclePaint.gd")
const USAGE = preload("res://runtime/VehicleUsage.gd")
const DAMAGE = preload("res://gameplay/vehicle_effects/VehicleDamage.gd")
const GUARDS = preload("res://gameplay/emergency/EffectsPrewarm.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
const SPACING := .7
static var _bases: Dictionary = {}         # assinatura -> pintura base (cópia)
static var _retained: Array[StandardMaterial3D] = []
static var _drawn := false
static var last_summary: Dictionary = {}

## Controle A/B de medição: HARBOR_VEHICLE_VARIANT_PREWARM=0 desliga só esta etapa.
static func enabled() -> bool:
	return OS.get_environment("HARBOR_VEHICLE_VARIANT_PREWARM") != "0" \
		and "--no-prewarm" not in OS.get_cmdline_user_args()

## Chamado com cada modelo decorado da frota já criado pelo aquecimento de
## shaders do tráfego, antes de liberá-lo. Não cria modelos extras.
static func collect(model: Node3D, archetype: String) -> void:
	if _drawn or not enabled() or model == null: return
	var paint = PAINT.new()
	paint.bind(model, archetype)
	for material in paint.materials:
		var signature := shader_signature(material)
		if not _bases.has(signature): _bases[signature] = material

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or not enabled() or DisplayServer.get_name() == "headless" or _bases.is_empty(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var base_count := _bases.size()
	var known := {}
	for signature in _bases: known[signature] = true
	var variants: Array[StandardMaterial3D] = []
	var candidates: Array = []
	for base: StandardMaterial3D in _bases.values(): candidates.append_array(_variants(base))
	candidates.append_array(DAMAGE.wreck_materials().values())
	for material: StandardMaterial3D in candidates:
		var signature := shader_signature(material)
		if known.has(signature): continue
		known[signature] = true
		variants.append(material)
	var visual := Node3D.new()
	visual.name = "VehicleMaterialVariantPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE * .5
	var columns := maxi(1, ceili(sqrt(float(variants.size()))))
	for index in variants.size():
		var part := MeshInstance3D.new()
		part.mesh = box
		part.material_override = variants[index]
		part.position = Vector3((index % columns - (columns - 1) * .5) * SPACING, -floorf(float(index) / columns) * SPACING, 0)
		visual.add_child(part)
	host.add_child(visual)
	_position(visual, camera)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in MAX_WAIT_FRAMES:
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if not is_instance_valid(visual) or visual.is_queued_for_deletion(): break
		_position(visual, camera)
		if draws[0] >= DRAW_FRAMES:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(visual): visual.free()
	if completed:
		_retained.append_array(variants)
		_drawn = true
		_bases.clear()
	last_summary = {"bases":base_count, "glass":0, "variants":variants.size(), "completed":completed,
		"draws":draws[0], "usec":Time.get_ticks_usec()-began}
	print("Variantes de material de veículo preparadas: ", JSON.stringify(last_summary))

## Mesmas mudanças de flags de VehicleUsage.apply e VehicleDamage._stall_apply_wear;
## valores contínuos (cor, rugosidade, escala) são uniforms e não importam aqui.
static func _variants(base: StandardMaterial3D) -> Array[StandardMaterial3D]:
	var result: Array[StandardMaterial3D] = []
	var detailed := base.duplicate() as StandardMaterial3D
	detailed.detail_enabled = true
	detailed.detail_albedo = USAGE._texture(1)
	detailed.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	detailed.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	detailed.uv2_triplanar = true
	result.append(detailed)
	# Uso sujo seguido de identidade limpa: detalhe desligado, textura e triplanar ficam.
	var reset := detailed.duplicate() as StandardMaterial3D
	reset.detail_enabled = false
	result.append(reset)
	# Desgaste a partir de 40%: verniz desligado.
	var worn := detailed.duplicate() as StandardMaterial3D
	worn.clearcoat_enabled = false
	result.append(worn)
	# Estágio 2+ em pintura sem textura própria: amassado triplanar em UV1.
	if base.albedo_texture == null and base.normal_texture == null:
		var dented := worn.duplicate() as StandardMaterial3D
		dented.normal_enabled = true
		dented.normal_texture = DAMAGE._dents()
		dented.uv1_triplanar = true
		result.append(dented)
	return result

## Aproxima a MaterialKey do motor: bools/enums e presença de texturas mudam o
## código do shader; cores e floats são uniforms.
static func shader_signature(material: Material) -> String:
	var parts: PackedStringArray = [material.get_class()]
	for property in material.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE): continue
		var value: Variant = material.get(property.name)
		match typeof(value):
			TYPE_BOOL, TYPE_INT: parts.append("%s=%s" % [property.name, value])
			TYPE_OBJECT:
				if property.name != "script": parts.append("%s=%s" % [property.name, value != null])
	return "|".join(parts)

static func _position(visual: Node3D, camera: Camera3D) -> void:
	visual.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 9.0)
