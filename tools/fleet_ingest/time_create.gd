extends SceneTree
## Cronometra cada etapa de FleetCatalog.create para os ids dados (padrão: police_suv,
## port_forklift), na 1ª e na 2ª criação: separa custo de leitura/primeira vez do custo fixo.
##   godot --path . --script res://tools/fleet_ingest/time_create.gd -- police_suv
func _initialize() -> void:
	var ids: Array = OS.get_cmdline_user_args() if not OS.get_cmdline_user_args().is_empty() else ["police_suv", "port_forklift"]
	var catalog = load("res://runtime/FleetCatalog.gd")
	for id in ids:
		for pass_index in 2:
			var definition: Dictionary = catalog.spec(id)
			var t0 := Time.get_ticks_usec()
			var packed := load(definition.scene) as PackedScene
			var t1 := Time.get_ticks_usec()
			var model := packed.instantiate() as Node3D
			var t2 := Time.get_ticks_usec()
			load("res://runtime/HeavyVehicleDetail.gd").decorate(id, model)
			var t3 := Time.get_ticks_usec()
			load("res://runtime/VehicleFinish.gd").decorate(id, model)
			var t4 := Time.get_ticks_usec()
			load("res://runtime/VehicleTwoTone.gd").decorate(id, model)
			var t5 := Time.get_ticks_usec()
			load("res://runtime/FleetSpeedPass.gd").decorate(id, model)
			var t6 := Time.get_ticks_usec()
			print("%s passo %d: load=%.0f instanciar=%.0f heavy=%.0f finish=%.0f twotone=%.0f speedpass=%.0f ms" % [id, pass_index + 1, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0, (t5 - t4) / 1000.0, (t6 - t5) / 1000.0])
			model.free()
	quit(0)
