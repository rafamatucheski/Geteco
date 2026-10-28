extends RefCounted
## Acessórios avulsos da Union presos aos ossos do Dante Meshy, por cima de qualquer roupa.
## Peças estáticas montadas só quando o visual muda: nada roda por quadro.
## Medidas no espaço de repouso do modelo (em pé, olhando para +Z), as mesmas de
## MeshyDanteAppearance: cabeça com cabelo x ±0,122, y 1,396..1,70, z -0,159..0,111.
const CATALOG := preload("res://data/catalogs/AccessoryCatalog.gd")
const APPEARANCE := preload("res://assets/outfits/MeshyDanteAppearance.gd")
const SHAPES := preload("res://assets/outfits/OutfitGeometry.gd")
const PREFIX := "WardrobeAccessory"
const BONE := {"head":"Head", "eyes":"Head", "face":"Head", "neck":"neck"}
## Peças da roupa que o encaixe substitui; sem isso, boné e chapéu ocupariam a mesma cabeça.
const REPLACES := {
	"head": ["beanie", "cowboy_hat", "cap_backwards", "tactical_helmet"],
	"eyes": ["shades", "goggles"],
	"neck": ["scarf", "bandana", "fur_collar", "necklace"],
}

## equipped: encaixe -> id do catálogo. Vazio só desmonta.
static func apply(player: Node3D, equipped: Dictionary) -> void:
	if not is_instance_valid(player): return
	var skeleton := player.get("skeleton") as Skeleton3D
	if not is_instance_valid(skeleton): return
	for child in skeleton.get_children():
		if String(child.name).begins_with(PREFIX): child.free()
	var covers_eyes := false
	for slot in equipped:
		var id := str(equipped[slot])
		if CATALOG.ITEMS.has(id) and CATALOG.ITEMS[id].get("covers_eyes", false): covers_eyes = true
	_hide_replaced(skeleton, equipped, covers_eyes)
	var spaces := {}
	for slot in CATALOG.SLOTS:
		var id := str(equipped.get(slot, ""))
		if not CATALOG.ITEMS.has(id) or CATALOG.ITEMS[id].slot != slot: continue
		if slot == "eyes" and covers_eyes: continue
		var spec: Dictionary = CATALOG.ITEMS[id]
		var space := _space(skeleton, spaces, BONE[slot])
		var before := space.get_child_count()
		build(space, str(spec.kind), spec.color)
		for index in range(before, space.get_child_count()):
			space.get_child(index).set_meta("wardrobe_accessory", id)

static func _hide_replaced(skeleton: Skeleton3D, equipped: Dictionary, covers_eyes: bool) -> void:
	var hidden := []
	for slot in REPLACES:
		if equipped.has(slot) or (slot == "eyes" and covers_eyes): hidden.append_array(REPLACES[slot])
	for child in skeleton.get_children():
		var node_name := String(child.name)
		if node_name.begins_with("MeshyOutfit"):
			for space in child.get_children():
				for piece in space.get_children():
					if piece.get_meta("outfit_accessory_kind", "") in hidden: piece.visible = false
		elif node_name == "ParkCosmetics":
			for space in child.get_children():
				for piece in space.get_children():
					var park_slot := str(piece.get_meta("cosmetic_slot", ""))
					if (park_slot == "glasses" and (equipped.has("eyes") or covers_eyes)) or (park_slot == "mask" and equipped.has("face")):
						piece.visible = false

static func _space(skeleton: Skeleton3D, spaces: Dictionary, bone: String) -> Node3D:
	if spaces.has(bone): return spaces[bone]
	var attachment := BoneAttachment3D.new()
	attachment.name = PREFIX + bone
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var space := Node3D.new()
	space.transform = skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse()
	attachment.add_child(space)
	spaces[bone] = space
	return space

static func build(space: Node3D, kind: String, color: Color) -> void:
	match kind:
		"beanie": APPEARANCE._beanie(space, color)
		"cowboy_hat": APPEARANCE._cowboy_hat(space, color)
		"cap_backwards": APPEARANCE._cap_backwards(space, color)
		"goggles": APPEARANCE._goggles(space, color)
		"shades": APPEARANCE._shades(space, color)
		"scarf": APPEARANCE._scarf(space, color)
		"bandana": APPEARANCE._bandana(space, color)
		"cap_front": _cap_front(space, color)
		"fedora": _fedora(space, color)
		"bucket": _bucket(space, color)
		"beret": _beret(space, color)
		"aviator": _aviator(space, color)
		"sport": _sport(space, color)
		"round": _round(space, color)
		"thick": _thick(space, color)
		"bandit": _bandit(space, color)
		"surgical": _surgical(space, color)
		"skull": _skull(space, color)
		"balaclava": _balaclava(space, color)
		"hockey": _hockey(space, color)
		"chain": _chain(space, color)
		"bowtie": APPEARANCE._bowtie(space, color)

static func _mat(color: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	return SHAPES._make_mat(color, rough, metal)

# --- Cabeça ---

static func _cap_front(space: Node3D, color: Color) -> void:
	var cloth := _mat(color, .85)
	# Mesma copa do boné virado (calibrada sobre o cabelo); a aba vai para a testa.
	space.add_child(SHAPES._make_ellipsoid(Vector3(.275, .20, .315), cloth, Vector3(.004, 1.612, -.022)))
	var brim := SHAPES._make_box(Vector3(.17, .012, .12), cloth, Vector3(.004, 1.592, .165))
	brim.rotation.x = .16
	space.add_child(brim)
	space.add_child(SHAPES._make_ellipsoid(Vector3(.022, .012, .022), _mat(color.darkened(.35), .8), Vector3(.004, 1.713, -.022)))

static func _fedora(space: Node3D, color: Color) -> void:
	var felt := _mat(color, .8)
	var brim := SHAPES._make_tapered_limb(.20, .20, .012, felt, Vector3(.004, 1.632, -.02))
	brim.scale = Vector3(1, 1, 1.12)
	space.add_child(brim)
	var crown := SHAPES._make_tapered_limb(.098, .124, .12, felt, Vector3(.004, 1.697, -.02))
	crown.scale = Vector3(1, 1, 1.2)
	space.add_child(crown)
	# Vinco do topo: uma tampa mais escura um pouco abaixo da borda da copa.
	var dent := SHAPES._make_ellipsoid(Vector3(.15, .03, .20), _mat(color.darkened(.2), .85), Vector3(.004, 1.752, -.02))
	space.add_child(dent)
	var band := SHAPES._make_tapered_limb(.126, .126, .022, _mat(color.darkened(.65), .7), Vector3(.004, 1.65, -.02))
	band.scale = Vector3(1, 1, 1.2)
	space.add_child(band)

static func _bucket(space: Node3D, color: Color) -> void:
	var canvas := _mat(color, .95)
	var crown := SHAPES._make_tapered_limb(.112, .136, .10, canvas, Vector3(.004, 1.668, -.022))
	crown.scale = Vector3(1, 1, 1.15)
	space.add_child(crown)
	space.add_child(SHAPES._make_ellipsoid(Vector3(.224, .04, .258), canvas, Vector3(.004, 1.716, -.022)))
	# Aba inclinada para baixo, tronco de cone aberto.
	var brim := SHAPES._make_tapered_limb(.138, .19, .045, canvas, Vector3(.004, 1.602, -.022))
	brim.scale = Vector3(1, 1, 1.12)
	space.add_child(brim)

static func _beret(space: Node3D, color: Color) -> void:
	var wool := _mat(color, .95)
	var body := SHAPES._make_ellipsoid(Vector3(.29, .10, .31), wool, Vector3(.022, 1.668, -.03))
	body.rotation.z = -.16
	space.add_child(body)
	var band := SHAPES._make_tapered_limb(.128, .132, .03, wool, Vector3(.004, 1.632, -.025))
	band.scale = Vector3(1, 1, 1.13)
	space.add_child(band)
	space.add_child(SHAPES._make_tapered_limb(.006, .008, .025, wool, Vector3(.03, 1.72, -.03)))

# --- Olhos (lentes na altura dos óculos escuros da roupa: y 1,542, z 0,108) ---

static func _temples(space: Node3D, material: Material, half_width: float) -> void:
	for side in [-1.0, 1.0]:
		space.add_child(SHAPES._make_box(Vector3(.006, .006, .11), material, Vector3(side * half_width + .004, 1.547, .055)))

static func _aviator(space: Node3D, color: Color) -> void:
	var frame := _mat(color, .25, .9)
	var lens := _mat(Color("2a2f28"), .08, .55)
	for side in [-1.0, 1.0]:
		var at := Vector3(side * .037 + .004, 1.537, .110)
		# Gota: elipse mais larga embaixo, levemente inclinada para fora.
		var glass := SHAPES._make_ellipsoid(Vector3(.05, .044, .008), lens, at)
		glass.rotation.z = side * .12
		space.add_child(glass)
		var rim := SHAPES._make_ellipsoid(Vector3(.056, .05, .005), frame, at + Vector3(0, 0, -.003))
		rim.rotation.z = side * .12
		space.add_child(rim)
	space.add_child(SHAPES._make_box(Vector3(.026, .004, .004), frame, Vector3(.004, 1.556, .112)))
	space.add_child(SHAPES._make_box(Vector3(.018, .003, .004), frame, Vector3(.004, 1.548, .112)))
	_temples(space, frame, .066)

static func _sport(space: Node3D, color: Color) -> void:
	var mirror := _mat(color, .06, .95)
	space.add_child(SHAPES._make_box(Vector3(.11, .032, .008), mirror, Vector3(.004, 1.543, .111)))
	# Pontas envolventes viram para trás seguindo a têmpora.
	for side in [-1.0, 1.0]:
		var wing := SHAPES._make_box(Vector3(.03, .028, .008), mirror, Vector3(side * .064 + .004, 1.543, .098))
		wing.rotation.y = -side * .55
		space.add_child(wing)
	_temples(space, _mat(Color("1a1c20"), .5), .072)

static func _round(space: Node3D, color: Color) -> void:
	var frame := _mat(color, .3, .85)
	var lens := _mat(Color("a8661f"), .1, .4)
	for side in [-1.0, 1.0]:
		var at := Vector3(side * .036 + .004, 1.542, .110)
		var rim := APPEARANCE._torus(.022, .026, frame, at)
		rim.rotation.x = PI * .5
		space.add_child(rim)
		var glass := SHAPES._make_tapered_limb(.023, .023, .004, lens, at + Vector3(0, 0, -.001))
		glass.rotation.x = PI * .5
		space.add_child(glass)
	space.add_child(SHAPES._make_box(Vector3(.024, .004, .004), frame, Vector3(.004, 1.548, .111)))
	_temples(space, frame, .064)

static func _thick(space: Node3D, color: Color) -> void:
	var acetate := _mat(color, .4)
	var lens := _mat(Color("39404a"), .1, .3)
	for side in [-1.0, 1.0]:
		var at := Vector3(side * .037 + .004, 1.542, .110)
		space.add_child(SHAPES._make_box(Vector3(.056, .036, .008), acetate, at + Vector3(0, 0, -.002)))
		space.add_child(SHAPES._make_box(Vector3(.044, .025, .006), lens, at + Vector3(0, -.001, .003)))
	space.add_child(SHAPES._make_box(Vector3(.022, .01, .008), acetate, Vector3(.004, 1.548, .110)))
	for side in [-1.0, 1.0]:
		space.add_child(SHAPES._make_box(Vector3(.009, .01, .11), acetate, Vector3(side * .066 + .004, 1.549, .055)))

# --- Rosto (mesma base da máscara do parque: casca no rosto abaixo dos olhos) ---

static func _lower_shell(space: Node3D, material: Material, depth := .075) -> void:
	space.add_child(SHAPES._make_ellipsoid(Vector3(.17, .09, depth), material, Vector3(.004, 1.471, .088)))

static func _ear_straps(space: Node3D, color: Color) -> void:
	var strap := _mat(color, .9)
	for side in [-1.0, 1.0]:
		space.add_child(SHAPES._make_box(Vector3(.008, .012, .12), strap, Vector3(side * .082 + .004, 1.485, .032)))

static func _bandit(space: Node3D, color: Color) -> void:
	var cloth := _mat(color, .9)
	# Cobre do nariz para baixo e cai num bico abaixo do queixo.
	space.add_child(SHAPES._make_ellipsoid(Vector3(.175, .10, .08), cloth, Vector3(.004, 1.478, .086)))
	var flap := SHAPES._make_box(Vector3(.085, .085, .012), cloth, Vector3(.004, 1.43, .108))
	flap.rotation.z = PI * .25
	flap.scale = Vector3(1, .75, 1)
	space.add_child(flap)
	var knot := SHAPES._make_ellipsoid(Vector3(.04, .03, .03), cloth, Vector3(.004, 1.50, -.162))
	space.add_child(knot)
	_ear_straps(space, color)

static func _surgical(space: Node3D, color: Color) -> void:
	var paper := _mat(color, .95)
	_lower_shell(space, paper, .07)
	var pleat := _mat(color.darkened(.15), .95)
	for y in [1.488, 1.468, 1.448]:
		space.add_child(SHAPES._make_box(Vector3(.10, .003, .004), pleat, Vector3(.004, y, .124)))
	_ear_straps(space, Color("f1f1ee"))

static func _skull(space: Node3D, color: Color) -> void:
	var bone := _mat(color, .7)
	var dark := _mat(Color("1d1a1c"), .85)
	_lower_shell(space, bone)
	space.add_child(SHAPES._make_ellipsoid(Vector3(.024, .02, .016), dark, Vector3(.004, 1.497, .124)))
	# Dentes: uma faixa escura com divisórias claras por cima.
	space.add_child(SHAPES._make_box(Vector3(.07, .018, .006), dark, Vector3(.004, 1.452, .119)))
	for x in [-.024, -.008, .008, .024]:
		space.add_child(SHAPES._make_box(Vector3(.004, .018, .006), bone, Vector3(x + .004, 1.452, .1215)))
	_ear_straps(space, Color("29232c"))

static func _balaclava(space: Node3D, color: Color) -> void:
	var knit := _mat(color, .97)
	# Duas cascas deixam a faixa dos olhos aberta: na frente (z ≈ 0,11) a de cima
	# termina em ~1,57 e a de baixo começa em ~1,50.
	# A de baixo mais estreita e mais à frente: com 0,262 × 0,30 parecia um balão sobre a barba.
	space.add_child(SHAPES._make_ellipsoid(Vector3(.262, .205, .30), knit, Vector3(.004, 1.622, -.024)))
	space.add_child(SHAPES._make_ellipsoid(Vector3(.236, .17, .275), knit, Vector3(.004, 1.455, -.004)))
	var collar := SHAPES._make_tapered_limb(.08, .09, .06, knit, Vector3(.004, 1.39, -.03))
	space.add_child(collar)

static func _hockey(space: Node3D, color: Color) -> void:
	var shell := _mat(color, .55)
	var dark := _mat(Color("15151a"), .8)
	space.add_child(SHAPES._make_ellipsoid(Vector3(.19, .27, .07), shell, Vector3(.004, 1.53, .108)))
	for side in [-1.0, 1.0]:
		var hole := SHAPES._make_ellipsoid(Vector3(.034, .02, .01), dark, Vector3(side * .036 + .004, 1.545, .139))
		hole.rotation.z = side * -.2
		space.add_child(hole)
	for at in [Vector3(-.02, 1.47, .138), Vector3(.0, 1.465, .139), Vector3(.02, 1.47, .138), Vector3(-.012, 1.445, .134), Vector3(.012, 1.445, .134), Vector3(-.03, 1.61, .132), Vector3(.03, 1.61, .132)]:
		space.add_child(SHAPES._make_ellipsoid(Vector3(.008, .008, .006), dark, at + Vector3(.004, 0, 0)))
	_ear_straps(space, Color("2a2a2e"))
	for side in [-1.0, 1.0]:
		space.add_child(SHAPES._make_box(Vector3(.008, .012, .14), _mat(Color("2a2a2e"), .9), Vector3(side * .085 + .004, 1.60, .02)))

# --- Pescoço: x ±0,071; y 1,358..1,424; centro z ≈ -0,035. Peito: frente z ≈ 0,115 ---

static func _chain(space: Node3D, color: Color) -> void:
	var metal := _mat(color, .22, 1.0)
	# Esticada em z para a frente da corrente pousar no peito, não afundar na gola.
	var links := APPEARANCE._torus(.088, .097, metal, Vector3(.004, 1.34, -.012))
	links.scale = Vector3(1, 1, 1.32)
	links.rotation.x = .42
	space.add_child(links)
	space.add_child(SHAPES._make_box(Vector3(.022, .03, .006), metal, Vector3(.004, 1.268, .118)))
