extends Node2D
## Side motor pool west of the precinct. The front and public footway stay clear.
const BAY_CENTERS := [Vector2(-95, -165), Vector2(-95, -45)]

func _ready() -> void:
	z_index = 3
	for index in BAY_CENTERS.size():
		var car = ModernTrafficFactory.spawn_parked_vehicle(
			self, "PatrolParked%d" % (index + 1), BAY_CENTERS[index],
			PI * 0.5, "police_cruiser" if index == 0 else "police_suv", 0)
		car.is_police_vehicle = true
		car.ensure_presentation()
	queue_redraw()

func _draw() -> void:
	# All bay paint stays inside the side lot, north of the public sidewalk.
	preload("res://world/harbor/UrbanGround.gd").paint(self,Rect2(-135,-235,170,280),Color("454b4e"))
	preload("res://world/harbor/UrbanGround.gd").yard(self,Rect2(-135,-235,170,280),147,true)
	for center in BAY_CENTERS:
		var left: float = center.x - 29.0
		var right: float = center.x + 29.0
		draw_polyline(PackedVector2Array([
			Vector2(left, center.y + 54), Vector2(left, center.y - 54),
			Vector2(right, center.y - 54), Vector2(right, center.y + 54)
		]), Color("#b7bcb5"), 1.5, true)
		draw_rect(Rect2(center.x - 19, center.y - 50, 38, 4), Color("#969f9f"))
	# Match the shared street paving; RoadNetwork owns the sidewalk and curb.
	draw_rect(Rect2(46, -10, 190, 63), preload("res://world/shared/roads/UnifiedRoadNetwork2D.gd").SIDEWALK_COLOR)
