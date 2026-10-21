extends SceneTree
## Exact geometry comparison and CPU attribution; not a rendered FPS approval.
func _initialize() -> void: run.call_deferred()

func run() -> void:
	var out := "res://evidence/loading-fluid-20261021/geography-before"
	var compare := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--compare="): compare = arg.trim_prefix("--compare=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var trace = load("res://runtime/StallWorkTrace.gd")
	trace.aggregate_enabled = true
	var region = load("res://world/editing/EditableRegion.gd").build_region("harbor")
	var began := Time.get_ticks_usec()
	region.prepare_data()
	var elapsed := (Time.get_ticks_usec()-began)/1000.0
	var boundaries: Array = region.coastal_protection.boundaries
	var cells: Dictionary = region.coastal_protection.cells
	var snapshot := {"boundaries":boundaries,"cells":cells,"polygons":region.coastal_protection.polygons}
	var same := true
	if not compare.is_empty():
		var previous: Dictionary = FileAccess.open(compare,FileAccess.READ).get_var()
		same = var_to_bytes(previous) == var_to_bytes(snapshot)
	FileAccess.open(out+".bin",FileAccess.WRITE).store_var(snapshot)
	var report := {"prepare_ms":elapsed,"boundaries":boundaries.size(),"cells":cells.size(),"same_geometry":same,"compared_to":compare,"costs":trace.aggregate_totals}
	FileAccess.open(out+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOADING_GEOGRAPHY ",JSON.stringify(report))
	region.free()
	quit(0 if same else 1)
