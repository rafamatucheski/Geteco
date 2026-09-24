extends Node3D
const VEHICLE := preload("res://scripts/Vehicle.gd")
var cars: Array[CharacterBody3D] = []
var enabled := true

func _ready() -> void:
	if not enabled: return
	for side in 2:
		var route := _route(side == 1)
		for index in 3:
			var car := VEHICLE.new()
			car.name = "Traffic_%d_%d" % [side,index]
			car.traffic = true
			car.route = route
			car.route_distance = route.get_baked_length()*(float(index)/3.0+0.06)
			car.position = route.sample_baked(car.route_distance,true)+Vector3.UP*0.04
			var ahead := route.sample_baked(fposmod(car.route_distance+1,route.get_baked_length()),true)-car.position
			car.rotation.y = atan2(-ahead.x,-ahead.z)
			car.paint_color = [Color("4d798b"),Color("e1d8bb"),Color("628a69")][index]
			car.sensor_clock = float(index)*0.03
			add_child(car)
			cars.append(car)

func _route(mirrored: bool) -> Curve3D:
	var result := Curve3D.new()
	result.bake_interval = 0.25
	# Rounded clockwise loop: central avenue + west outer streets. The opposite
	# loop is rotated 180 degrees, keeping both central lanes right-hand traffic.
	var centers := [Vector2(-5.8,-31.2),Vector2(-5.8,34.8),Vector2(-31.2,34.8),Vector2(-31.2,-31.2)]
	for corner in 4:
		for step in 13:
			var angle := -PI/2+corner*PI/2+step*PI/24
			var point: Vector2 = centers[corner]+Vector2(cos(angle),sin(angle))*4.0
			var world_point := Vector3(point.x,0,point.y)
			if mirrored: world_point = -world_point
			result.add_point(world_point)
	result.add_point(result.get_point_position(0))
	return result
