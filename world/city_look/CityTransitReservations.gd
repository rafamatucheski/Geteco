extends RefCounted
## A bagunça de rua respeita a área calibrada e editada da parada do tubo.
## Arquitetura e colisão continuam pertencendo a UrbanTransitPresentation.

static func build() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var presentation: Node = load("res://runtime/UrbanTransitPresentation.gd").new()
	presentation.configure(null)
	for definition: Dictionary in presentation.definitions:
		if definition.get("deleted",false) or int(definition.type)>1: continue
		result.append(footprint(definition))
	presentation.free()
	return result

static func footprint(definition: Dictionary) -> Rect2:
	# UrbanStationModel3D: platform plus access ramp/rails, in authored pixels.
	var source := Rect2(-157,-32,351,67)
	if int(definition.type)==1: source=source.merge(Rect2(-153,-106,168,74))
	var edit: Dictionary = definition.get("edit",{})
	var stretch: Array = edit.get("stretch",[1,1])
	var basis := Basis(Vector3.UP,deg_to_rad(float(edit.get("rotation",0))))*Basis.from_scale(Vector3(float(stretch[0]),1,float(stretch[1])))
	var bounds := Rect2()
	var first := true
	for corner in [source.position,Vector2(source.end.x,source.position.y),source.end,Vector2(source.position.x,source.end.y)]:
		var calibrated: Vector2 = corner.rotated(float(definition.angle))/16.0
		var point: Vector3 = definition.position+basis*Vector3(calibrated.x,0,calibrated.y)
		var flat := Vector2(point.x,point.z)
		if first: bounds=Rect2(flat,Vector2.ZERO); first=false
		else: bounds=bounds.expand(flat)
	return bounds.grow(.12)
