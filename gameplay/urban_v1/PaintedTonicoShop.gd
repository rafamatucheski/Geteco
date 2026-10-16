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
## Interruptor: GETECO_PAINTED_FACADES=0 volta ao 3D antigo. PROVISÓRIO: enquanto o teste e as
## capturas no jogo não passarem, o gancho fica DESLIGADO por padrão e só liga com
## GETECO_PAINTED_TONICO=1; depois inverta para ligado por padrão (desliga com =0).

const STYLE := "loja-tonico"
## Caixa autoral 24 x 10 x 3,2 centrada em (-30, ., -34); o espaço de autoria a estica.
const AUTHOR_CENTER := Vector3(-30, 0, -34)
const AUTHOR_SIZE := Vector2(24, 10)


static func enabled() -> bool:
	# PROVISÓRIO: trocar por `== "0"` quando a verificação terminar.
	if not PaintedFacadeKit.enabled() or OS.get_environment("GETECO_PAINTED_TONICO") != "1": return false
	return not PaintedFacadeKit.style_data(STYLE).is_empty()


## Monta o kit no lugar do casco. `author` é STATION_TRANSFORM; o nó volta para o chamador.
static func build(village: Node3D, author: Transform3D) -> Node3D:
	var center: Vector3 = author * AUTHOR_CENTER
	var size := Vector3(AUTHOR_SIZE.x * author.basis.x.length(), PaintedFacadeKit.natural_size(STYLE).y, AUTHOR_SIZE.y * author.basis.z.length())
	var visual := Node3D.new()
	visual.name = "PaintedTonicoShop"
	visual.position = Vector3(center.x, 0, center.z)
	village.add_child(visual)
	var scratch := Node3D.new()
	village.add_child(scratch)
	# Entrada no meio da fachada (o vão pintado é central, x local 0 = entrance_x do catálogo).
	PaintedFacadeKit.build(visual, STYLE, size, scratch, 0.0)
	scratch.free()
	visual.set_meta("painted_facade_style", STYLE)
	return visual
