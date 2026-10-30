extends RefCounted
class_name PaintedTonicoShop

## Loja Tônico (Vila dos Caminhoneiros) com a fachada pintada do estilo `loja-tonico`.
##
## A loja não é um UrbanBuildingBase: é uma caixa montada por TruckersVillageVisuals
## (`_station`, no espaço de autoria esticado por STATION_TRANSFORM) e também o prédio do
## catálogo `TruckersStationStore`, cujo interior entra por proximidade na porta central.
## O kit pinta só o VISUAL do casco (paredes, telhado, letreiro); a colisão (`_solid
## "TonicoShop"`), a cobertura de bombas, as bombas e o cutaway ficam como estavam. O casco
## de colisão do kit é descartado porque HarborBuildingExteriorAccess já recorta a colisão
## antiga na entrada; a folha pintada é a porta que abre (`walk_in`) e a caixa antiga de
## porta/janelas/letreiro deixa de ser desenhada em `_station`.
##
## Interruptor: GETECO_PAINTED_TONICO=0 (ou GETECO_PAINTED_FACADES=0) volta ao 3D antigo.
##
## Posto compacto (padrão; GETECO_PAINTED_TONICO_STATION=0 volta ao posto largo): ao lado
## da cobertura de 14 x 9 m a loja de 18,72 x 2,9 m lia como um galpão baixo (30/10).
## Usa o estilo `loja-tonico-compacta` (11,2 x 3,6 m, recortado da mesma pintura com 0,7 m
## de reboco acima das janelas) centrado na cobertura. O interior do catálogo é gerado
## pelo retângulo do catálogo (HarborBuildingInterior), então `footprint()` é a fonte
## única de casco, colisão, catálogo e interior.

const STYLE := "loja-tonico"
const COMPACT_STYLE := "loja-tonico-compacta"
## Caixa autoral 24 x 10 x 3,2 centrada em (-30, ., -34); o espaço de autoria a estica.
const AUTHOR_CENTER := Vector3(-30, 0, -34)
const AUTHOR_SIZE := Vector2(24, 10)
## Vila (TruckersVillageVisuals.ORIGIN) e loja compacta no espaço local da vila, sem
## esticar: frente na mesma linha z = -25,62 da loja larga (balcão e pátio já estão ali)
## e centro em x = -29,68, o eixo da cobertura compacta.
const VILLAGE_ORIGIN := Vector3(-330, 0, 108)
const COMPACT_CENTER := Vector3(-29.68, 0, -29.32)


static func enabled() -> bool:
	if not PaintedFacadeKit.enabled() or OS.get_environment("GETECO_PAINTED_TONICO") == "0": return false
	return not PaintedFacadeKit.style_data(STYLE).is_empty()


## Posto compacto com a loja de proporção de conveniência (ver cabeçalho).
static func compact_enabled() -> bool:
	if not enabled() or OS.get_environment("GETECO_PAINTED_TONICO_STATION") == "0": return false
	return not PaintedFacadeKit.style_data(COMPACT_STYLE).is_empty()


static func style() -> String:
	return COMPACT_STYLE if compact_enabled() else STYLE


## Retângulo da loja em coordenadas do Harbor: centro, tamanho (largura, profundidade) e
## altura do catálogo. A loja larga mantém os números de antes (18,72 x 7,4 m, 2,91 m).
static func footprint() -> Dictionary:
	if compact_enabled():
		var natural := PaintedFacadeKit.natural_size(COMPACT_STYLE)
		# +1 cm como a loja larga (2,898 -> 2,91): a cobertura do catálogo fica sobre a laje pintada.
		return {"position": VILLAGE_ORIGIN + COMPACT_CENTER, "size": Vector2(natural.x, natural.z), "height": natural.y + .01}
	return {"position": Vector3(-359.56, 0, 78.68), "size": Vector2(18.72, 7.4), "height": 2.91}


## Monta o kit no lugar do casco. `author` é STATION_TRANSFORM (ignorado no posto
## compacto, que usa footprint() sem esticar); o nó volta para o chamador.
static func build(village: Node3D, author: Transform3D) -> Node3D:
	var style_name := style()
	var center: Vector3 = author * AUTHOR_CENTER
	var size := Vector3(AUTHOR_SIZE.x * author.basis.x.length(), PaintedFacadeKit.natural_size(STYLE).y, AUTHOR_SIZE.y * author.basis.z.length())
	if style_name == COMPACT_STYLE:
		center = COMPACT_CENTER
		size = PaintedFacadeKit.natural_size(COMPACT_STYLE)
	var visual := Node3D.new()
	visual.name = "PaintedTonicoShop"
	visual.position = Vector3(center.x, 0, center.z)
	village.add_child(visual)
	var scratch := Node3D.new()
	village.add_child(scratch)
	# Entrada no meio da fachada (o vão pintado é central, x local 0 = entrance_x do catálogo).
	PaintedFacadeKit.build(visual, style_name, size, scratch, 0.0)
	scratch.free()
	visual.set_meta("painted_facade_style", style_name)
	return visual
