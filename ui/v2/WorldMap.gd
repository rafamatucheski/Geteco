extends Control
var controller
func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	if controller == null: return
	var bounds := Rect2()
	var first := true
	for road in controller.region.roads:
		for point in road.points:
			var p := Vector2(point.x,point.z)
			bounds = Rect2(p,Vector2.ONE) if first else bounds.expand(p)
			first = false
	if first: return
	var scale_value := minf((size.x-30)/maxf(1,bounds.size.x),(size.y-30)/maxf(1,bounds.size.y))
	var origin := Vector2(15,15)-bounds.position*scale_value
	draw_rect(Rect2(Vector2.ZERO,size),Color("17252b"))
	for road in controller.region.roads:
		var points := PackedVector2Array()
		for point in road.points: points.append(origin+Vector2(point.x,point.z)*scale_value)
		if points.size()>1: draw_polyline(points,Color("72888e"),2,true)
	for entry in controller.region.entries:
		var point: Vector3 = entry.position
		draw_circle(origin+Vector2(point.x,point.z)*scale_value,3,Color("f39a38"))
	var player: Vector3 = controller.world.player.position
	draw_circle(origin+Vector2(player.x,player.z)*scale_value,5,Color("8cd1ed"))
	var target: Vector3 = controller.session.mission_world.target_position()
	draw_circle(origin+Vector2(target.x,target.z)*scale_value,5,Color("ffdd68"),false,2)
