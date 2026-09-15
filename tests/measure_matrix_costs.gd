extends "res://tests/measure_game_frame_stability.gd"
var cost_file: FileAccess
func _report_render() -> void:
 if cost_file == null:
  var folder = "D:/geteco/artifacts/performance-matrix-0912"
  for arg in OS.get_cmdline_user_args():
   if arg.begins_with("out_dir="): folder = arg.trim_prefix("out_dir=")
  cost_file = FileAccess.open(folder.path_join("costs.jsonl"),FileAccess.WRITE)
 cost_file.store_line(JSON.stringify(preload("res://tests/MatrixCostProbe.gd").take()))
 super._report_render()
