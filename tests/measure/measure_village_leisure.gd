extends "res://tests/measure/measure_truckers_village.gd"
## Optional process-local control removes only this feature, preserving other
## sessions' current world edits. No shared source or save is reverted on disk.
func run() -> void:
	if "--leisure-control" in OS.get_cmdline_user_args():
		var visuals: GDScript = load("res://gameplay/urban_v1/TruckersVillageVisuals.gd")
		var build := "\tleisure_art = preload(\"res://gameplay/urban_v1/TruckersVillageLeisureArt.gd\").build(self)\n"
		if not visuals.source_code.contains(build): quit(5); return
		visuals.source_code = visuals.source_code.replace(build,"")
		if visuals.reload(true)!=OK: quit(5); return
		_baseline_sources.append(visuals)
		var operations: GDScript = load("res://gameplay/urban_v1/UrbanOperations.gd")
		var integration := "\tvillage_leisure = preload(\"res://gameplay/urban_v1/TruckersVillageLeisure.gd\").new()\n\tadd_child(village_leisure)\n\tvillage_leisure.configure(session,village.leisure_art)\n"
		if not operations.source_code.contains(integration): quit(5); return
		operations.source_code = operations.source_code.replace(integration,"")
		if operations.reload(true)!=OK: quit(5); return
		_baseline_sources.append(operations)
	await super.run()
