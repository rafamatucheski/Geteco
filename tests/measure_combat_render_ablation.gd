extends "res://tests/measure_city_scenarios.gd"
## Diagnostic only: freeze 3D render submissions while retaining simulation.
var _views: Array[SubViewport] = []
var _freeze := false
var _frozen_peak := 0
func _initialize() -> void:
	super._initialize()
	node_added.connect(func(node: Node):
		if node is SubViewport: _views.append(node))
	RenderingServer.frame_pre_draw.connect(_before_draw)
func _before_draw() -> void:
	if not _freeze: return
	var frozen := 0
	for view in _views:
		if is_instance_valid(view) and view.get_camera_3d() != null:
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			frozen += 1
	_frozen_peak = maxi(_frozen_peak, frozen)
func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	_freeze = label != "warmup" and OS.get_cmdline_user_args().has("--freeze-3d")
	await super._sample(output, label, seconds, car)
	var path := output.path_join(label + ".json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["diagnostic_frozen_3d_viewports"] = _frozen_peak
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data, "\t"))
