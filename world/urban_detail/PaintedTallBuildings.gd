extends RefCounted
## Prédios altos do porto montados pelo modo alto do PaintedFacadeKit (térreo +
## andares repetidos + topo). Arquivo próprio para não disputar
## PaintedHarborHouses.gd com as outras frentes de trabalho. Sem class_name: quem usa
## faz preload, e o jogo funciona antes de o cache de classes ser refeito (--import).
##
## Piloto LIGADO por padrão desde 16/10 (pedido do usuário): GETECO_PAINTED_TALL=0
## desliga (e GETECO_PAINTED_FACADES=0 continua desligando tudo). Desligado, nenhum
## caminho do jogo muda: style_for devolve "" e height_for devolve a altura de antes.

## id do prédio no jogo -> estilo alto e altura pedida (m). A altura vira
## térreo + N andares + topo (PaintedFacadeKit.tall_layout); o catálogo do interior
## usa a mesma conta para a cobertura e o número de andares baterem com a casca.
## CivicTower: no V1 a silhueta tinha 95/16 = 5,9 m (menor que a ExchangeTower,
## 8 m), baixa demais para térreo + topo (7 m); 10 m = térreo + 1 andar + topo e
## continua abaixo da torre vizinha quando ela também for pintada (13 m).
const TALL := {
	"CivicTower": {"style": "torre-civica", "height": 10.0},
	# Rodada de 18/10 (pacotes do Codex de 15-16/10): GETECO_PAINTED_TALL_18=0 desliga só
	# estes três para A/B. Exchange com 13 m (térreo + 2 andares + topo; V1 tinha 8 m)
	# fica acima da CivicTower vizinha. Os dois de moradia são "office" que usavam a
	# casca/cena assada antiga; a largura de cada um fica a até 16% da pintura (lofts
	# 14 m em 13,1 m; misto 10 m em 11,6 m), e o letreiro pintado FOUNDRY LOFTS não é o
	# nome do jogo (NORTH UNION), como nos prédios de HARBOR em PaintedHarborHouses.
	"ExchangeTower": {"style": "torre-exchange", "height": 13.0, "switch": "GETECO_PAINTED_TALL_18"},
	"UnionApartments": {"style": "lofts-fundicao", "height": 13.0, "switch": "GETECO_PAINTED_TALL_18"},
	"Apartments": {"style": "predio-misto", "height": 10.0, "switch": "GETECO_PAINTED_TALL_18"},
	# Escritórios A/B/C (pacotes de 15/10, módulo 12 m, lateral 6 m): 10 m = térreo +
	# 1 andar + topo, como a CivicTower e abaixo da ExchangeTower. Caixa antiga tinha
	# 7,5 m (só térreo + topo, sem o andar que repete). Interruptor próprio para A/B:
	# GETECO_PAINTED_OFFICES=0 devolve só estes três às caixas assadas.
	# "max_stretch": o lote tem 14,4-16,3 m e o kit esticaria o módulo de 12 m inteiro
	# (até 1,35x), levando junto a porta pintada: a de A (1,5 m) passava de 1,8 m e
	# virava porta dupla. Acima de 1,15x o prédio fica com 13,8 m (catálogo, interior e
	# fábrica usam a mesma largura, como nos prédios de PaintedHarborHouses.HARBOR).
	"BridgeCourtEast": {"style": "escritorio-a", "height": 10.0, "switch": "GETECO_PAINTED_OFFICES", "max_stretch": 1.15},
	"NorthFrontage5": {"style": "escritorio-b", "height": 10.0, "switch": "GETECO_PAINTED_OFFICES", "max_stretch": 1.15},
	"NorthbankFront2": {"style": "escritorio-c", "height": 10.0, "switch": "GETECO_PAINTED_OFFICES", "max_stretch": 1.15},
}


static func enabled() -> bool:
	return PaintedFacadeKit.enabled() and OS.get_environment("GETECO_PAINTED_TALL") != "0"


## Estilo alto do prédio, ou "" (piloto desligado, id sem pacote ou estilo não importado).
static func style_for(building_id: String) -> String:
	if not enabled() or not TALL.has(building_id): return ""
	# Interruptor A/B de cada rodada (GETECO_PAINTED_TALL_18, GETECO_PAINTED_OFFICES);
	# a CivicTower não tem e só sai com GETECO_PAINTED_TALL=0.
	var switch := str(TALL[building_id].get("switch", ""))
	if not switch.is_empty() and OS.get_environment(switch) == "0": return ""
	var style: String = TALL[building_id].style
	return style if PaintedFacadeKit.is_tall(style) else ""


## Largura do prédio alto com "max_stretch": no máximo o módulo da frente vezes o
## fator; os demais (e o piloto desligado) ficam com `width`.
static func footprint_width(building_id: String, width: float) -> float:
	var style := style_for(building_id)
	if style.is_empty() or not TALL[building_id].has("max_stretch"): return width
	return minf(width, PaintedFacadeKit.natural_size(style).x * float(TALL[building_id].max_stretch))


## Altura da casca pintada acima da calçada (soma exata das peças menos o que o kit
## afunda até a soleira da porta); `fallback` quando não é prédio alto.
static func height_for(building_id: String, fallback: float) -> float:
	var style := style_for(building_id)
	if style.is_empty(): return fallback
	return float(PaintedFacadeKit.tall_layout(style, float(TALL[building_id].height)).height) - PaintedFacadeKit.tall_sink(style)


## Monta o prédio alto em `building` (UrbanBuildingBase) se ele tiver estilo alto.
## Devolve false para o construtor seguir o caminho de sempre.
static func build_into(building: Node3D) -> bool:
	var style := style_for(building.building_id)
	if style.is_empty(): return false
	var size: Vector2 = building.building_size
	var access: Dictionary = load("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").for_source(building.building_id)
	# O catálogo já levou entrance_x para o vão pintado mais próximo (style_for de
	# PaintedHarborHouses devolve este estilo): a folha desse vão é a que abre.
	var walk_in_x: float = float((access.entrance_local as Vector3).x) if not access.is_empty() else NAN
	var visual := Node3D.new()
	visual.name = "PaintedTallOffset"
	building.visuals_root.add_child(visual)
	var solid := Node3D.new()
	solid.name = "PaintedTallSolidOffset"
	building.collision_root.add_child(solid)
	PaintedFacadeKit.build(visual, style, Vector3(size.x, height_for(building.building_id, 0.0), size.y), solid, walk_in_x)
	return true

# Cadastro só de revestimento: não entra em style_for/height_for/footprint_width.
# Os quatro interiores, suas portas e o cache de NativeRegion conservam os envelopes.
const EDITOR_SKINS := {
	"new_1790426066_503_97028106":"lofts-fundicao",
	"new_1790426877_636_2342363314":"predio-misto",
	"new_1790432139_406_2568146191":"predio-misto",
	"new_1790432236_682_2325181222":"torre-civica",
}
const SKIN_FINISH := preload("res://world/mountain_detail/MountainInteriorFinish.gd")
const SKIN_ART := preload("res://runtime/desert/roadside/RoadsideArt.gd")

static func editor_skin_for(building_id: String) -> String:
	if not enabled() or OS.get_environment("GETECO_PAINTED_EDITOR_SKINS") == "0": return ""
	return EDITOR_SKINS.get(building_id,"")

static func skin_base_material(style: String) -> Material:
	if style == "lofts-fundicao": return SKIN_FINISH.material("block",Color("805442"))
	if style == "predio-misto": return SKIN_FINISH.material("plaster",Color("aaa28f"))
	return SKIN_FINISH.material("cast",Color("a9aaa3"))

static func prewarm_materials() -> Array:
	return [skin_base_material("lofts-fundicao"),skin_base_material("predio-misto"),skin_base_material("torre-civica")]

## Reveste um volume existente, sem corpo, porta, sinalização ou alteração de tamanho.
## Térreo mineral mantém a entrada autorada; só andares acima dela usam janelas pintadas.
static func add_skin_box(parent: Node3D, label: String, center: Vector3, size: Vector3, style: String) -> void:
	var batch := SKIN_ART.batch()
	var bottom := center.y-size.y*.5
	var base_h := clampf(2.8-bottom,0.0,size.y)
	if size.y-base_h < 1.8: base_h=size.y
	var upper_h := size.y-base_h
	var floors := maxi(1,roundi(upper_h/3.0))
	for side in [-1.0,1.0]:
		for along_x in [true,false]:
			var width := size.x if along_x else size.z
			var normal := Vector3(0,0,side) if along_x else Vector3(side,0,0)
			var right := Vector3(side*width*.5,0,0) if along_x else Vector3(0,0,-side*width*.5)
			var face := center+normal*((size.z if along_x else size.x)*.5)
			if base_h > 0.0:
				batch.quad(skin_base_material(style),Vector3(face.x,bottom+base_h*.5,face.z),right,Vector3(0,base_h*.5,0),Rect2(0,0,1,1))
			if upper_h > 0.0:
				var part := "front_floor" if along_x else "side_floor"
				var module := PaintedFacadeKit.natural_size(style).x if along_x else float(PaintedFacadeKit.style_data(style).side[0])
				batch.quad(PaintedFacadeKit.material(style,part),Vector3(face.x,bottom+base_h+upper_h*.5,face.z),right,Vector3(0,upper_h*.5,0),Rect2(0,0,width/module,float(floors)))
	var root := Node3D.new()
	root.name=label+"PaintedSkin"
	parent.add_child(root)
	var baked := batch.bake()
	# O acesso contínuo recorta estas faces: retém os dados já compostos na CPU
	# para nunca ler os vértices de volta da GPU ao abrir a porta.
	var index := 0
	for key in batch.order:
		var group: Dictionary = batch.groups[key]
		if group.v.is_empty(): continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=group.v
		arrays[Mesh.ARRAY_NORMAL]=group.n
		arrays[Mesh.ARRAY_TEX_UV]=group.t
		arrays[Mesh.ARRAY_INDEX]=group.i
		var mesh: ArrayMesh = baked.meshes[index][0]
		mesh.set_meta("cpu_surface_arrays",[arrays])
		index+=1
	SKIN_ART.instantiate(root,baked)
