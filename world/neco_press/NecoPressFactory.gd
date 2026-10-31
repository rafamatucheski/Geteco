extends RefCounted
class_name NecoPressFactory

## Fábrica para criar e posicionar instâncias de NecoPress3D.
## Garante instanciação, posição e rotação padrão sem acoplamento direto à cena.
## Mantém o NecoPress3D totalmente modular e reutilizável entre modos de jogo ou cenas de teste.

## Transform padrão no ferro-velho do Neco (batendo com SalvageYard3D da V1 e SalvageYardNative da V2)
const SALVAGE_YARD_PRESS_POSITION := Vector3(7.2, 0.0, -1.5)
const SALVAGE_YARD_PRESS_ROTATION_Y := 0.0

## Instancia um novo componente NecoPress3D na posição e rotação Y indicadas.
static func create_press(world_pos: Vector3 = Vector3.ZERO, rotation_y: float = 0.0) -> NecoPress3D:
	var press := NecoPress3D.new()
	press.name = "NecoPress3D"
	press.position = world_pos
	press.rotation.y = rotation_y
	return press

## Instantiates a new NecoPress3D pre-configured for Neco's Salvage Yard plot.
static func create_press_at_salvage_yard() -> NecoPress3D:
	return create_press(SALVAGE_YARD_PRESS_POSITION, SALVAGE_YARD_PRESS_ROTATION_Y)
