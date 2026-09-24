extends Node3D
class_name UrbanTransitStation3D

## Adapter for urban transit stations and regional coach terminals in native 3D.
## Replaces the legacy SubViewport approach with native 3D instances.
## Preserves metric geometry (PPM calibrated) without double scaling.

enum StationType {
	TUBE_STOP,
	TUBE_TERMINAL,
	COACH_TERMINAL
}

@export var station_type: StationType = StationType.TUBE_STOP
@export var station_name: String = "Estação"
@export var orientation_angle: float = 0.0

var station_model: Node3D

func _ready() -> void:
	build_station()

func build_station() -> void:
	if station_model != null:
		station_model.queue_free()
		station_model = null
	
	match station_type:
		StationType.TUBE_STOP:
			var stop := UrbanStationModel3D.new()
			stop.name = "StationModel"
			add_child(stop)
			stop.build(orientation_angle, false)
			station_model = stop
		
		StationType.TUBE_TERMINAL:
			var terminal := UrbanStationModel3D.new()
			terminal.name = "StationTerminalModel"
			add_child(terminal)
			terminal.build(orientation_angle, true)
			station_model = terminal
		
		StationType.COACH_TERMINAL:
			var coach_terminal := HarborTerminalModel3D.new()
			coach_terminal.name = "CoachTerminalModel"
			add_child(coach_terminal)
			station_model = coach_terminal

func get_boarding_approach() -> Vector3:
	# Local approach point for passengers (calibrated to rotated model geometry)
	match station_type:
		StationType.TUBE_STOP, StationType.TUBE_TERMINAL:
			var pt: Vector2 = Vector2(123.0, 14.0).rotated(orientation_angle)
			return to_global(Vector3(pt.x / UrbanStationModel3D.PPM, 0.20, pt.y / (UrbanStationModel3D.PPM * UrbanStationModel3D.FLOOR_Y)))
		StationType.COACH_TERMINAL:
			return to_global(Vector3(10.0 / HarborTerminalModel3D.PPM, 0.12, -180.0 / (HarborTerminalModel3D.PPM * HarborTerminalModel3D.FLOOR_Y)))
	return global_position
