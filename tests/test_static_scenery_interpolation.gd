extends SceneTree

const STATIC_SCENERY := [
	"res://geodata/StreetLamp.gd",
	"res://geodata/BreakableProp.gd",
	"res://geodata/nature/ProceduralStreetTree.gd",
	"res://geodata/nature/ProceduralUrbanRock.gd",
	"res://geodata/roads/RoadLuminaire3D.gd",
	"res://geodata/roads/TrafficSignalPost.gd",
	"res://geodata/roads/traffic/FixedTrafficSignal.gd",
	"res://geodata/roads/traffic/JunctionSignalVisual2D.gd",
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for script_path in STATIC_SCENERY:
		var script := load(script_path) as Script
		var scenery := script.new() as Node2D
		var fixed_anchor := scenery.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
		print(("PASS " if fixed_anchor else "FAIL ") + script_path)
		if not fixed_anchor:
			failures.append(script_path)
		scenery.free()
	print("STATIC_SCENERY_INTERPOLATION failures=", failures)
	quit(0 if failures.is_empty() else 1)
