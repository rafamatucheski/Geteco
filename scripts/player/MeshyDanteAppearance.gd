extends RefCounted
## Trajes da loja sobre o Dante Meshy. O modelo tem uma única textura assada,
## então cada traje recolore regiões dela (máscara gerada por
## tools/build_meshy_outfit_mask.py) e prende acessórios aos ossos.
## Limite conhecido: a silhueta é a do modelo. Regata e bermuda pintam pele
## sobre o volume da manga e da perna; sobretudo longo não ganha barra.
const SHADER := preload("res://scripts/player/meshy_dante_outfit.gdshader")
const REGIONS_TEX := "res://assets/characters/meshy_dante/dante_outfit_regions.png"
const STATS := preload("res://scripts/player/MeshyDanteRegionStats.gd")
const ADAPTER := preload("res://scripts/player/DanteVisualAdapter.gd")

const SKIN := 0
const HAIR := 1
const JACKET := 2
const SHIRT := 3
const PANTS := 4
const BELT := 5
const BOOTS := 6

const TORSO := 0
const UPPER_ARM := 1
const FOREARM := 2
const HAND := 3
const THIGH := 4
const SHIN := 5
const FOOT := 6

## Tom de pele pintado pelo Meshy, para regata, bermuda e peito aberto.
const SKIN_TONE := Color(0.93, 0.70, 0.53)

## regions: região -> [cor, quanto do padrão original manter (1 = xadrez inteiro)]
## zones: zona -> [cor, intensidade, regiões afetadas]
## print: estampa procedural (1 floral, 2 camuflagem) sobre as regiões listadas
## accessories: [tipo, cor]; posições calibradas no espaço de repouso do modelo
const OUTFITS := {
	"dante_classic": {},
	"dante_suit": {
		"regions": {JACKET: [Color("17171c"), 0.15], SHIRT: [Color("e6e3dc"), 0.25], PANTS: [Color("17171c"), 0.2], BELT: [Color("0d0d10"), 0.5], BOOTS: [Color("0b0b0e"), 0.35]},
		"accessories": [["tie", Color("c0392b")], ["watch", Color("d4a64a")]],
	},
	"dante_arctic": {
		# Padrão 0,08: a 0,2 as linhas do xadrez original ainda marcavam a parka.
		"regions": {JACKET: [Color("527d92"), 0.08], SHIRT: [Color("334b5a"), 0.3], PANTS: [Color("222f3e"), 0.25], BOOTS: [Color("493e34"), 0.6]},
		"zones": {HAND: [Color("2b3a44"), 1.0, [SKIN, JACKET]]},
		"accessories": [["beanie", Color("334b5a")], ["fur_collar", Color("d5cbb5")]],
	},
	"dante_ski": {
		# O capacete e os óculos vêm do PlayerSkiController; aqui só a roupa.
		"regions": {JACKET: [Color("c84b43"), 0.2], SHIRT: [Color("17242d"), 0.3], PANTS: [Color("182b3b"), 0.25], BOOTS: [Color("12191f"), 0.4]},
		"zones": {HAND: [Color("151b20"), 1.0, [SKIN, JACKET]]},
	},
	"dante_trench": {
		"regions": {JACKET: [Color("353b48"), 0.2], SHIRT: [Color("cfc8bd"), 0.3], PANTS: [Color("2f3640"), 0.25], BELT: [Color("191919"), 0.5], BOOTS: [Color("191919"), 0.4]},
		"zones": {HAND: [Color("2a1d17"), 1.0, [SKIN, JACKET]]},
		"accessories": [["scarf", Color("b3202a")]],
	},
	"dante_cowboy": {
		# Colete de couro no tronco; mangas da camisa creme por zona.
		"regions": {JACKET: [Color("8c532b"), 0.35], SHIRT: [Color("d8c8a8"), 0.3], PANTS: [Color("3e4b5b"), 0.6], BELT: [Color("4a2810"), 0.6], BOOTS: [Color("5a3214"), 0.7]},
		"zones": {UPPER_ARM: [Color("d8c8a8"), 1.0, [JACKET]], FOREARM: [Color("d8c8a8"), 1.0, [JACKET]]},
		"accessories": [["cowboy_hat", Color("5c381e")], ["bandana", Color("c0392b")]],
	},
	"dante_madmax": {
		"regions": {JACKET: [Color("2d3436"), 0.45], SHIRT: [Color("4b4b45"), 0.4], PANTS: [Color("636e72"), 0.55], BELT: [Color("2b2118"), 0.6], BOOTS: [Color("2d3436"), 0.5]},
		"zones": {HAND: [Color("1e1e1e"), 0.85, [SKIN, JACKET]]},
		"accessories": [["goggles", Color("e17055")], ["shoulder_pad", Color("b2bec3")]],
	},
	"dante_lumberjack": {
		# Mantém o xadrez inteiro e só troca o tom: flanela vermelha e preta.
		"regions": {JACKET: [Color("b71540"), 1.0], SHIRT: [Color("2d2a26"), 0.3], PANTS: [Color("2c3e6b"), 0.7], BOOTS: [Color("6a411f"), 0.8]},
		"accessories": [["beanie", Color("079992")], ["suspenders", Color("4a2e1a")]],
	},
	"dante_ghillie": {
		"regions": {JACKET: [Color("4b5a2e"), 0.2], SHIRT: [Color("3d4a2a"), 0.3], PANTS: [Color("4b5a2e"), 0.2], BELT: [Color("2b3520"), 0.5], BOOTS: [Color("1b2a15"), 0.5]},
		"zones": {HAND: [Color("2b3520"), 0.9, [SKIN, JACKET]]},
		"print": {"style": 2, "regions": [JACKET, PANTS], "a": Color("6b5330"), "b": Color("24301a"), "scale": 22.0},
		"accessories": [["tactical_helmet", Color("2b4c1f")], ["vest", Color("39452a")]],
	},
	"dante_hawaii": {
		# Camisa aberta e manga curta: peito e antebraço em pele; bermuda nas canelas.
		"regions": {JACKET: [Color("eb4d4b"), 0.12], SHIRT: [SKIN_TONE, 0.2], PANTS: [Color("22a6b3"), 0.3], BELT: [Color("22a6b3"), 0.3], BOOTS: [Color("f0932b"), 0.3]},
		"zones": {FOREARM: [SKIN_TONE, 1.0, [JACKET]], SHIN: [SKIN_TONE, 1.0, [PANTS]]},
		"print": {"style": 1, "regions": [JACKET], "a": Color("f9ca24"), "b": Color("ffffff"), "scale": 34.0},
		"accessories": [["shades", Color("1b1b1f")], ["necklace", Color("f5f0e6")]],
	},
	"dante_badboy": {
		# Regata preta: braços inteiros em pele; bermuda esportiva; tênis branco.
		"regions": {JACKET: [Color("141418"), 0.12], SHIRT: [Color("141418"), 0.12], PANTS: [Color("30336b"), 0.3], BELT: [Color("30336b"), 0.3], BOOTS: [Color("f2f2f2"), 0.3]},
		"zones": {UPPER_ARM: [SKIN_TONE, 1.0, [JACKET, SHIRT]], FOREARM: [SKIN_TONE, 1.0, [JACKET, SHIRT]], SHIN: [SKIN_TONE, 1.0, [PANTS]]},
		"accessories": [["cap_backwards", Color("eb4d4b")], ["shades", Color("1b1b1f")]],
	},
}

static func apply(mesh: MeshInstance3D, skeleton: Skeleton3D, outfit_id: String) -> ShaderMaterial:
	var source := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("albedo_tex", source.albedo_texture)
	material.set_shader_parameter("normal_tex", source.normal_texture)
	material.set_shader_parameter("orm_tex", source.roughness_texture)
	material.set_shader_parameter("region_tex", load(REGIONS_TEX))
	material.set_shader_parameter("region_mean", PackedFloat32Array(STATS.MEANS))
	var data: Dictionary = OUTFITS.get(outfit_id, {})
	var regions: Dictionary = data.get("regions", {})
	var tints := PackedColorArray()
	var patterns := PackedFloat32Array()
	for region in 7:
		var entry: Array = regions.get(region, [])
		var tint := Color(1, 1, 1, 0)
		if not entry.is_empty():
			# Sem srgb_to_linear: o Godot já converte Color ao enviar o array ao
			# shader. Converter aqui também escurecia e saturava (pele laranja).
			tint = entry[0]
			tint.a = 1.0
		tints.append(tint)
		patterns.append(float(entry[1]) if not entry.is_empty() else 1.0)
	var zones: Dictionary = data.get("zones", {})
	var zone_colors := PackedColorArray()
	var zone_masks := PackedInt32Array()
	for zone in 7:
		var entry: Array = zones.get(zone, [])
		if entry.is_empty():
			zone_colors.append(Color(0, 0, 0, 0))
			zone_masks.append(0)
			continue
		var color: Color = entry[0]
		color.a = float(entry[1])
		zone_colors.append(color)
		zone_masks.append(_bits(entry[2]))
	material.set_shader_parameter("region_tint", tints)
	material.set_shader_parameter("region_pattern", patterns)
	material.set_shader_parameter("zone_color", zone_colors)
	material.set_shader_parameter("zone_mask", zone_masks)
	var print_data: Dictionary = data.get("print", {})
	material.set_shader_parameter("print_style", int(print_data.get("style", 0)))
	material.set_shader_parameter("print_mask", _bits(print_data.get("regions", [])))
	material.set_shader_parameter("print_a", print_data.get("a", Color.WHITE))
	material.set_shader_parameter("print_b", print_data.get("b", Color.WHITE))
	material.set_shader_parameter("print_scale", float(print_data.get("scale", 30.0)))
	material.set_shader_parameter("recolor", not regions.is_empty() or not zones.is_empty())
	mesh.set_surface_override_material(0, material)
	_dress(skeleton, data.get("accessories", []))
	return material

static func _bits(list: Array) -> int:
	var mask := 0
	for region in list: mask |= 1 << int(region)
	return mask

static func _dress(skeleton: Skeleton3D, accessories: Array) -> void:
	for old in skeleton.get_children():
		if String(old.name).begins_with("MeshyOutfit"): old.free()
	var spaces := {}
	for item in accessories:
		var kind: String = item[0]
		var color: Color = item[1]
		match kind:
			"beanie": _beanie(_space(skeleton, spaces, "Head"), color)
			"cowboy_hat": _cowboy_hat(_space(skeleton, spaces, "Head"), color)
			"cap_backwards": _cap_backwards(_space(skeleton, spaces, "Head"), color)
			"tactical_helmet": _tactical_helmet(_space(skeleton, spaces, "Head"), color)
			"goggles": _goggles(_space(skeleton, spaces, "Head"), color)
			"shades": _shades(_space(skeleton, spaces, "Head"), color)
			"tie": _tie(_space(skeleton, spaces, "Spine"), color)
			"watch": _watch(_space(skeleton, spaces, "LeftHand"), color)
			"scarf": _scarf(_space(skeleton, spaces, "neck"), color)
			"bandana": _bandana(_space(skeleton, spaces, "neck"), color)
			"fur_collar": _fur_collar(_space(skeleton, spaces, "neck"), color)
			"necklace": _necklace(_space(skeleton, spaces, "neck"), color)
			"suspenders": _suspenders(_space(skeleton, spaces, "Spine01"), color)
			"vest": _vest(_space(skeleton, spaces, "Spine01"), color)
			"shoulder_pad": _shoulder_pad(_space(skeleton, spaces, "LeftArm"), color)

## Nó que acompanha o osso, com filhos escritos no espaço de repouso do modelo
## (em pé, olhando para +Z). Assim as medidas vêm direto da malha importada.
static func _space(skeleton: Skeleton3D, spaces: Dictionary, bone: String) -> Node3D:
	if spaces.has(bone): return spaces[bone]
	var attachment := BoneAttachment3D.new()
	attachment.name = "MeshyOutfit" + bone
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var space := Node3D.new()
	space.transform = skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse()
	attachment.add_child(space)
	spaces[bone] = space
	return space

static func _torus(inner: float, outer: float, material: Material, position: Vector3) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 10
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	return instance

# Cabeça com cabelo: x ±0,122; y 1,396..1,70; z -0,159 (nuca)..0,111 (rosto).
static func _beanie(space: Node3D, color: Color) -> void:
	var wool := ADAPTER._make_mat(color, 0.95)
	space.add_child(ADAPTER._make_ellipsoid(Vector3(0.265, 0.21, 0.30), wool, Vector3(0.004, 1.625, -0.025)))
	var cuff := ADAPTER._make_tapered_limb(0.134, 0.137, 0.05, wool, Vector3(0.004, 1.575, -0.025))
	cuff.scale = Vector3(1, 1, 1.13)
	space.add_child(cuff)

static func _cowboy_hat(space: Node3D, color: Color) -> void:
	var felt := ADAPTER._make_mat(color, 0.8)
	# A aba apoia na altura da testa; em 1,655 o chapéu pairava acima do cabelo.
	var brim := ADAPTER._make_tapered_limb(0.25, 0.25, 0.014, felt, Vector3(0.004, 1.628, -0.02))
	brim.scale = Vector3(1, 1, 1.1)
	space.add_child(brim)
	var crown := ADAPTER._make_tapered_limb(0.11, 0.13, 0.14, felt, Vector3(0.004, 1.70, -0.02))
	crown.scale = Vector3(1, 1, 1.2)
	space.add_child(crown)
	var band := ADAPTER._make_tapered_limb(0.132, 0.132, 0.025, ADAPTER._make_mat(color.darkened(0.6), 0.7), Vector3(0.004, 1.648, -0.02))
	band.scale = Vector3(1, 1, 1.2)
	space.add_child(band)

static func _cap_backwards(space: Node3D, color: Color) -> void:
	var cloth := ADAPTER._make_mat(color, 0.85)
	# Mais baixo e largo que a cabeça com cabelo: em 1,655 flutuava como boina.
	space.add_child(ADAPTER._make_ellipsoid(Vector3(0.275, 0.20, 0.315), cloth, Vector3(0.004, 1.612, -0.022)))
	var brim := ADAPTER._make_box(Vector3(0.16, 0.012, 0.11), cloth, Vector3(0.004, 1.585, -0.21))
	brim.rotation.x = -0.15
	space.add_child(brim)

static func _tactical_helmet(space: Node3D, color: Color) -> void:
	var shell := ADAPTER._make_mat(color, 0.75)
	space.add_child(ADAPTER._make_ellipsoid(Vector3(0.29, 0.25, 0.32), shell, Vector3(0.004, 1.625, -0.02)))
	var rim := ADAPTER._make_tapered_limb(0.148, 0.152, 0.03, shell, Vector3(0.004, 1.56, -0.02))
	rim.scale = Vector3(1, 1, 1.1)
	space.add_child(rim)
	space.add_child(ADAPTER._make_box(Vector3(0.04, 0.03, 0.02), ADAPTER._make_mat(Color("1b1f1a"), 0.5), Vector3(0.004, 1.64, 0.14)))

static func _goggles(space: Node3D, color: Color) -> void:
	var strap := _torus(0.128, 0.138, ADAPTER._make_mat(Color("2a2622"), 0.8), Vector3(0.004, 1.61, -0.02))
	strap.scale = Vector3(1, 1, 1.15)
	space.add_child(strap)
	var lens := ADAPTER._make_mat(color, 0.15, 0.3)
	for side in [-1.0, 1.0]:
		var glass := ADAPTER._make_tapered_limb(0.032, 0.032, 0.022, lens, Vector3(side * 0.042 + 0.004, 1.61, 0.118))
		glass.rotation.x = PI * 0.5
		space.add_child(glass)

static func _shades(space: Node3D, color: Color) -> void:
	var lens := ADAPTER._make_mat(color, 0.08, 0.6)
	# Revisão frontal: em 1,555 as lentes cobriam a sobrancelha.
	for side in [-1.0, 1.0]:
		space.add_child(ADAPTER._make_box(Vector3(0.048, 0.026, 0.008), lens, Vector3(side * 0.036 + 0.004, 1.542, 0.108)))
		space.add_child(ADAPTER._make_box(Vector3(0.006, 0.006, 0.11), lens, Vector3(side * 0.066 + 0.004, 1.547, 0.055)))
	space.add_child(ADAPTER._make_box(Vector3(0.024, 0.006, 0.006), lens, Vector3(0.004, 1.549, 0.110)))

# Peito: frente z ≈ 0,115 entre y 1,175 e 1,36.
static func _tie(space: Node3D, color: Color) -> void:
	var silk := ADAPTER._make_mat(color, 0.45)
	space.add_child(ADAPTER._make_box(Vector3(0.032, 0.03, 0.022), silk, Vector3(0.004, 1.33, 0.105)))
	var blade := ADAPTER._make_box(Vector3(0.05, 0.24, 0.01), silk, Vector3(0.004, 1.19, 0.112))
	blade.rotation.x = -0.05
	space.add_child(blade)

static func _watch(space: Node3D, color: Color) -> void:
	var band := ADAPTER._make_tapered_limb(0.03, 0.03, 0.022, ADAPTER._make_mat(color, 0.25, 0.9), Vector3(0.60, 1.27, -0.052))
	band.rotation.z = PI * 0.5
	space.add_child(band)

# Pescoço: x ±0,071; y 1,358..1,424; centro z ≈ -0,035.
static func _scarf(space: Node3D, color: Color) -> void:
	var wool := ADAPTER._make_mat(color, 0.95)
	space.add_child(_torus(0.065, 0.118, wool, Vector3(0.004, 1.375, -0.03)))
	var tail := ADAPTER._make_box(Vector3(0.07, 0.22, 0.03), wool, Vector3(0.06, 1.25, 0.085))
	tail.rotation.z = 0.1
	space.add_child(tail)

static func _bandana(space: Node3D, color: Color) -> void:
	var cloth := ADAPTER._make_mat(color, 0.9)
	space.add_child(_torus(0.07, 0.10, cloth, Vector3(0.004, 1.385, -0.03)))
	var knot := ADAPTER._make_box(Vector3(0.09, 0.09, 0.015), cloth, Vector3(0.004, 1.335, 0.075))
	knot.rotation.z = PI * 0.25
	knot.scale = Vector3(1, 0.7, 1)
	space.add_child(knot)

static func _fur_collar(space: Node3D, color: Color) -> void:
	var fur := _torus(0.085, 0.165, ADAPTER._make_mat(color, 1.0), Vector3(0.004, 1.37, -0.035))
	fur.scale = Vector3(1, 1.4, 1)
	space.add_child(fur)

static func _necklace(space: Node3D, color: Color) -> void:
	var beads := _torus(0.082, 0.092, ADAPTER._make_mat(color, 0.4), Vector3(0.004, 1.345, -0.02))
	beads.rotation.x = 0.35
	space.add_child(beads)

static func _suspenders(space: Node3D, color: Color) -> void:
	var leather := ADAPTER._make_mat(color, 0.6)
	for side in [-1.0, 1.0]:
		var front := ADAPTER._make_box(Vector3(0.028, 0.36, 0.012), leather, Vector3(side * 0.075 + 0.004, 1.18, 0.128))
		front.rotation.z = -side * 0.05
		space.add_child(front)
		space.add_child(ADAPTER._make_box(Vector3(0.028, 0.36, 0.012), leather, Vector3(side * 0.07 + 0.004, 1.18, -0.17)))

static func _vest(space: Node3D, color: Color) -> void:
	var nylon := ADAPTER._make_mat(color, 0.8)
	space.add_child(ADAPTER._make_box(Vector3(0.28, 0.26, 0.035), nylon, Vector3(0.004, 1.19, 0.13)))
	space.add_child(ADAPTER._make_box(Vector3(0.30, 0.28, 0.035), nylon, Vector3(0.004, 1.19, -0.175)))
	var pouch := ADAPTER._make_mat(color.darkened(0.25), 0.85)
	for x in [-0.08, 0.0, 0.08]:
		space.add_child(ADAPTER._make_box(Vector3(0.06, 0.07, 0.03), pouch, Vector3(x + 0.004, 1.12, 0.155)))

static func _shoulder_pad(space: Node3D, color: Color) -> void:
	var steel := ADAPTER._make_mat(color, 0.35, 0.8)
	space.add_child(ADAPTER._make_ellipsoid(Vector3(0.15, 0.07, 0.15), steel, Vector3(0.205, 1.39, -0.05)))
	space.add_child(ADAPTER._make_ellipsoid(Vector3(0.12, 0.05, 0.12), steel, Vector3(0.215, 1.36, -0.05)))
