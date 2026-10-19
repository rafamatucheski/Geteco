extends "res://tests/test_drag_open_meet.gd"
## Unchanged full queue flow; inspect deferred resource owners at shutdown.
func finish() -> void:
	print("DRAG_SHUTDOWN_QUEUE ",JSON.stringify(preload("res://runtime/GpuReleaseQueue.gd").debug_snapshot()))
	super.finish()
