extends RefCounted
class_name NecoPressFactory

## Factory for creating and placing instances of NecoPress3D.
## Ensures standard instantiation, positioning, and rotation without direct scene coupling.
## Keeps NecoPress3D completely modular and reusable across game modes or test scenes.

## Default transform in Neco's Salvage Yard (matching V1 SalvageYard3D and V2 SalvageYardNative)
const SALVAGE_YARD_PRESS_POSITION := Vector3(7.2, 0.0, -1.5)
const SALVAGE_YARD_PRESS_ROTATION_Y := 0.0

## Instantiates a new NecoPress3D component at the specified position and Y-rotation.
static func create_press(world_pos: Vector3 = Vector3.ZERO, rotation_y: float = 0.0) -> NecoPress3D:
	var press := NecoPress3D.new()
	press.name = "NecoPress3D"
	press.position = world_pos
	press.rotation.y = rotation_y
	return press

## Instantiates a new NecoPress3D pre-configured for Neco's Salvage Yard plot.
static func create_press_at_salvage_yard() -> NecoPress3D:
	return create_press(SALVAGE_YARD_PRESS_POSITION, SALVAGE_YARD_PRESS_ROTATION_Y)
