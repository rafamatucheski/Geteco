extends Node2D
## Two opposing paths use the same spline as the visible asphalt. Closed
## hairpins at the terminal aprons prevent cars piling up at dead ends.
var lane: Path2D
var vehicles: Array = []
var region_ready := false
const FLEET := ["summit_suv", "arctic_jeep", "lumber_pickup_4x4", "polar_van", "winter_suv_heavy", "ranch_single", "snow_plow_truck", "polar_van"]
const WINTER_PAINTS := [Color("d5dcd7"),Color("536f79"),Color("755744"),Color("d1d8d9"),Color("525f6d"),Color("796846"),Color("bd8745"),Color("758994")]
func _ready() -> void:
	var road: Node2D = get_parent().road
	var center: PackedVector2Array = road.smooth_points
	var up := PackedVector2Array()
	var down := PackedVector2Array()
	for i in center.size():
		var tangent := (center[mini(i+1,center.size()-1)]-center[maxi(i-1,0)]).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var terminal := 1.0-smoothstep(60,290,center[i].distance_to(center[-1]))
		var lane_offset := lerpf(31,95,terminal)
		up.append(center[i]+normal*lane_offset)
		down.append(center[i]-normal*lane_offset)
	var route := up.duplicate()
	var end_tangent := (center[-1]-center[-2]).normalized()
	var end_angle := Vector2(-end_tangent.y,end_tangent.x).angle()
	for i in range(1,32):
		route.append(center[-1]+Vector2.from_angle(end_angle-PI*i/32.0)*95)
	down.reverse()
	route.append_array(down)
	var start_tangent := (center[1]-center[0]).normalized()
	var start_angle := Vector2(start_tangent.y,-start_tangent.x).angle()
	if not get_parent().streamed_region:
		for i in range(1,12):
			route.append(center[0]+Vector2.from_angle(start_angle-PI*i/12.0)*31)
		route.append(up[0])
	lane = ModernTrafficFactory.create_lane(self,"MountainThroughTraffic",route)
	lane.set_meta("traffic_lane_loop",not get_parent().streamed_region)
	lane.set_meta("mountain_traffic", true)
	for i in 8:
		var car := ModernTrafficFactory.spawn_moving_vehicle(lane,"MountainTraffic%d"%i,FLEET[i],(float(i)+0.35)/8.0,85,0)
		car.repaint_vehicle(WINTER_PAINTS[i])
		vehicles.append(car)
		if get_parent().streamed_region: await get_tree().process_frame
	region_ready = true
