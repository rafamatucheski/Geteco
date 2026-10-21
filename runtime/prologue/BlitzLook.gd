extends RefCounted
## Acabamento dos materiais da blitz do prólogo (asfalto molhado, concreto, madeira, tecido, metal...).
## BlitzScene cria cada material uma vez por chave ("blitz_*", em `_material`) e o passa por `dress` antes
## de retê-lo: aqui é o único lugar de textura e detalhe de superfície da cena. Roda sob a cortina.
##
## Texturas: 7 famílias + 1 variação larga em assets/prologue/ (tools/build_prologue_materials.py, BC7 com
## mipmaps), compartilhadas por todas as chaves. As peças são caixas grandes (UV 0..1 por face), então tudo
## vai em triplanar no espaço do mundo, com o ladrilho em metros: a textura não estica e cada instância de
## MultiMesh pega um pedaço diferente. Peças que se movem (lanterna, rádio, carta, caixas do caminhão)
## usam triplanar do objeto, senão a textura "nadaria" sobre elas.
##
## Custo de shader: todo material vestido tem o MESMO conjunto de recursos (albedo com rugosidade no alfa,
## normal, AO no UV2, triplanar, anisotrópico), então a cena inteira gera só duas variantes novas de
## StandardMaterial3D (mundo e objeto), compiladas no aquecimento coberto pela cortina. Emissivos (janela,
## lente, refletor, abajur) e transparentes (vidros) ficam como estão: já usam variantes que existem.
##
## A variação larga entra no canal de AO (UV2, escala de dezenas de metros): sem ela, a pista vista de cima
## mostrava o ladrilho de 6 m repetido. Não usamos o slot de detalhe para isso porque, sem normal de
## detalhe, o shader do BaseMaterial3D mistura a normal principal com a normal chata padrão (pelo alfa do
## detalhe) e o relevo sumiria.
##
## `GETECO_BLITZ_LOOK=0` deixa os materiais lisos (antes/depois no mesmo código).
const DIR := "res://assets/prologue/"
const TRUCK := "res://gameplay/desert_heist/DesertCargoTruckVisual.gd"
## O gerador normaliza cada albedo para média linear 0,40 por canal e o macro para 0,80: a cor média que a
## cena escolheu (albedo_color) é preservada dividindo por elas.
const ALBEDO_MEAN := .40
const MACRO_MEAN := .80
## Tábuas do piso: reaproveita a textura de tábuas da beira de estrada como AO (juntas e pregos).
const PLANKS := "res://assets/roadside/surfaces/planks.jpg"
const PLANKS_MEAN := .90

## Por chave: família, ladrilho em metros (número ou Vector3 por eixo do mundo), escala do macro em
## metros, rugosidade escalar (multiplica o alfa da textura), força da normal e opções:
## "local" (triplanar do objeto), "metallic", "ao" (textura de AO própria) e "ao_tile".
const LOOKS := {
	# Pista: rugosidade .48 x textura = úmido ~.42, poça ~.15.
	"blitz_wet_asphalt": {"family": "asphalt", "tile": 6.0, "macro": 31.0, "roughness": .48, "normal": 1.0},
	# Tinta: reboco em escala de faixa (desgaste em manchas, trinca fina). O asfalto aqui ficava "camuflado"
	# na faixa e virava granito nas pernas dos cavaletes, que usam o mesmo branco.
	"blitz_paint_white": {"family": "plaster", "tile": 2.0, "macro": 31.0, "roughness": .5, "normal": .4},
	"blitz_paint_yellow": {"family": "plaster", "tile": 2.0, "macro": 31.0, "roughness": .5, "normal": .4},
	"blitz_gravel": {"family": "asphalt", "tile": 11.0, "macro": 47.0, "roughness": .8, "normal": 1.4},
	# Copa e moita em escala bem menor e com mais relevo que o chão: de cima (~36 m) o detalhe delas some no
	# mipmap e a copa volta a ler como massa escura sobre o mato granulado (com a mesma escala sumia no chão).
	"blitz_verge": {"family": "vegetation", "tile": 4.5, "macro": 23.0, "roughness": .82, "normal": .8},
	"blitz_bush": {"family": "vegetation", "tile": 1.0, "macro": 17.0, "roughness": .8, "normal": 1.8},
	"blitz_tree": {"family": "vegetation", "tile": 1.0, "macro": 19.0, "roughness": .8, "normal": 2.0},
	# Tronco: reboco esticado na vertical vira casca com sulcos verticais.
	"blitz_trunk": {"family": "plaster", "tile": Vector3(.7, 3.5, .7), "macro": 13.0, "roughness": .92, "normal": 2.0},
	# Concreto molhado de chuva: um pouco mais liso que seco.
	"blitz_concrete": {"family": "concrete", "tile": 4.0, "macro": 29.0, "roughness": .82, "normal": 1.0},
	# Pintura: a faixa suja da textura fica na base do ladrilho (logo acima do chão, y múltiplo de 1,5 m).
	"blitz_post": {"family": "painted", "tile": 1.5, "macro": 19.0, "roughness": .45, "normal": .8},
	"blitz_barrier_red": {"family": "painted", "tile": 1.5, "macro": 13.0, "roughness": .5, "normal": .8},
	"blitz_rail": {"family": "painted", "tile": 1.5, "macro": 23.0, "roughness": .38, "normal": .6, "metallic": .25},
	"blitz_gate_steel": {"family": "painted", "tile": Vector3(1.5, 6.0, 1.5), "macro": 17.0, "roughness": .5, "normal": .8, "metallic": .2},
	"blitz_lantern_body": {"family": "painted", "tile": .5, "macro": 3.0, "roughness": .45, "normal": .6, "local": true},
	"blitz_radio": {"family": "painted", "tile": .4, "macro": 3.0, "roughness": .55, "normal": .5, "local": true},
	# Caixas de papelão (no baú e no quarto) e a carta: papel = o reboco em escala pequena.
	"blitz_cardboard": {"family": "plaster", "tile": .9, "macro": 3.1, "roughness": .92, "normal": 1.2, "local": true},
	"blitz_letter": {"family": "plaster", "tile": .45, "macro": 2.3, "roughness": .9, "normal": .5, "local": true},
	"blitz_room_wall": {"family": "plaster", "tile": 2.0, "macro": 7.0, "roughness": .9, "normal": .8},
	"blitz_room_wood": {"family": "wood", "tile": 1.0, "macro": 5.3, "roughness": .7, "normal": 1.0},
	"blitz_room_trim": {"family": "wood", "tile": .6, "macro": 5.3, "roughness": .7, "normal": .8},
	"blitz_room_floor": {"family": "wood", "tile": .9, "roughness": .62, "normal": 1.0, "ao": PLANKS, "ao_mean": PLANKS_MEAN, "ao_tile": 1.1},
	"blitz_room_sheet": {"family": "fabric", "tile": .7, "macro": 3.7, "roughness": .95, "normal": .6},
	"blitz_room_pillow": {"family": "fabric", "tile": .5, "macro": 3.7, "roughness": .95, "normal": .6},
	"blitz_room_blanket": {"family": "fabric", "tile": .9, "macro": 3.7, "roughness": .95, "normal": .8},
	# Cortina: tecido esticado na vertical vira caimento com dobras verticais.
	"blitz_room_curtain": {"family": "fabric", "tile": Vector3(.5, 2.6, .5), "macro": 3.7, "roughness": .95, "normal": 1.0},
	"blitz_room_jacket": {"family": "fabric", "tile": .35, "macro": 3.7, "roughness": .85, "normal": .8},
	"blitz_room_rug": {"family": "fabric", "tile": .3, "macro": 3.7, "roughness": .95, "normal": 1.0},
	"blitz_room_calendar": {"family": "plaster", "tile": .5, "macro": 3.1, "roughness": .9, "normal": .4},
	"blitz_room_metal": {"family": "painted", "tile": .6, "macro": 3.7, "roughness": .4, "normal": .5, "metallic": .3},
	"blitz_room_black": {"family": "painted", "tile": .6, "macro": 3.7, "roughness": .5, "normal": .5},
	"blitz_room_ceiling_lamp": {"family": "painted", "tile": .8, "macro": 3.7, "roughness": .6, "normal": .5},
}
## Chave nova do quarto sem entrada acima: família pelo nome (a cena principal ainda acrescenta peças).
const GUESSES := [
	[["floor", "shelf", "table", "chair", "desk", "wardrobe", "door", "frame", "wood", "bed"], {"family": "wood", "tile": .8, "macro": 5.3, "roughness": .7, "normal": .8}],
	[["sheet", "pillow", "blanket", "curtain", "cloth", "jacket", "towel", "rug", "mattress", "shirt", "boot", "bag"], {"family": "fabric", "tile": .45, "macro": 3.7, "roughness": .9, "normal": .8}],
	[["wall", "ceiling", "plaster"], {"family": "plaster", "tile": 2.0, "macro": 7.0, "roughness": .9, "normal": .8}],
	[["metal", "steel", "iron", "rail", "handle", "pipe"], {"family": "painted", "tile": .6, "macro": 3.7, "roughness": .45, "normal": .5}],
	[["card", "box", "paper", "envelope", "book"], {"family": "plaster", "tile": .6, "macro": 3.1, "roughness": .9, "normal": .8, "local": true}],
	[["concrete", "stone", "curb", "block"], {"family": "concrete", "tile": 4.0, "macro": 29.0, "roughness": .85, "normal": 1.0}],
]

static var _textures := {}

static func enabled() -> bool:
	return OS.get_environment("GETECO_BLITZ_LOOK") != "0"

static func dress(material: StandardMaterial3D) -> void:
	if material == null or not enabled(): return
	var key := material.resource_name
	if key == "blitz_truck_paint":
		_match_truck(material)
		return
	# Emissivos e vidros ficam lisos: textura não ajuda e cada combinação nova seria mais um shader.
	if material.emission_enabled or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return
	var look: Dictionary = LOOKS.get(key, _guess(key))
	if look.is_empty(): return
	var family: String = look.family
	var world := not bool(look.get("local", false))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.albedo_texture = _texture(DIR + family + "_albedo.png")
	material.roughness_texture = material.albedo_texture
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	material.roughness = float(look.get("roughness", material.roughness))
	material.normal_enabled = true
	material.normal_texture = _texture(DIR + family + "_normal.png")
	material.normal_scale = float(look.get("normal", 1.0))
	if look.has("metallic"): material.metallic = float(look.metallic)
	var tile: Variant = look.get("tile", 1.0)
	var size: Vector3 = tile if tile is Vector3 else Vector3.ONE * float(tile)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = world
	material.uv1_scale = Vector3(1.0 / size.x, 1.0 / size.y, 1.0 / size.z)
	# Borda dura entre projeções: em caixa girada (cavaletes) a mistura larga fazia imagem dupla.
	material.uv1_triplanar_sharpness = 4.0
	material.ao_enabled = true
	material.ao_on_uv2 = true
	material.ao_texture = _texture(str(look.get("ao", DIR + "macro.png")))
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.ao_light_affect = 1.0
	material.uv2_triplanar = true
	material.uv2_world_triplanar = world
	material.uv2_scale = Vector3.ONE / float(look.get("ao_tile", look.get("macro", 20.0)))
	material.uv2_triplanar_sharpness = 2.0
	# Mesma cor média de antes: a textura (média .40) e o AO (média .80/.90) escureceriam o tom escolhido.
	var mean := ALBEDO_MEAN * float(look.get("ao_mean", MACRO_MEAN))
	var linear := material.albedo_color.srgb_to_linear()
	var lifted := Color(linear.r / mean, linear.g / mean, linear.b / mean).linear_to_srgb()
	lifted.a = material.albedo_color.a
	material.albedo_color = lifted

static func _guess(key: String) -> Dictionary:
	if not key.begins_with("blitz_room_"): return {}
	for entry in GUESSES:
		for word in entry[0]:
			if key.contains(word): return entry[1]
	return {}

## A porta é a mesma chapa da cabine do caminhão de carga: mesmo acabamento, senão ela destoava (mais
## brilhante e sem metal) do resto da cabine, que usa o material compartilhado do deserto (não tocado).
static func _match_truck(material: StandardMaterial3D) -> void:
	var paint: StandardMaterial3D = load(TRUCK).material("paint")
	if paint == null: return
	material.metallic = paint.metallic
	material.roughness = paint.roughness
	material.metallic_specular = paint.metallic_specular

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		# Carga sob a cortina (só quando a cena monta), não no boot: Arrival pré-carrega a BlitzScene.
		_textures[path] = load(path)
	return _textures[path]
