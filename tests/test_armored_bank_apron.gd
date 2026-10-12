extends SceneTree
const APRON := preload("res://gameplay/armored/ArmoredBankApron.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _initialize() -> void:
	for phase in ["loading","boarding","driving","unloading"]:
		for hostile in [false,true]:
			var returning: bool = phase == "unloading"
			var data := SCHEDULE.initial(SCHEDULE.departure(3 if returning else 1,(14.0 if returning else 9.0)/24.0))
			data.phase = phase
			data.service_layout = 0
			data.hostile = hostile
			data.virtual_poses = false
			data.cargo_cycles = [1,2]
			for slot in 4: data.vehicles.append({"point":[40.0+slot*12,0.08,26.75],"yaw":-PI/2,"health":900 if slot<2 else 120})
			data.guards = [{"health":0,"point":[42,.08,25],"seat":0,"phase":"car"},{"health":45,"point":[44,.08,25],"seat":1,"phase":"bank"}]
			var before := data.duplicate(true)
			APRON.migrate_loading(data)
			if hostile or phase == "driving":
				check(data == before,"combat and underway checkpoints keep exact poses")
			else:
				check(data.vehicles.all(func(row): return row.point[2] < 17),"neutral service checkpoint moves off the avenue")
				check(data.vehicles[0].health == 900 and data.vehicles[3].health == 120,"migration preserves damaged vehicles")
				check(data.guards[0].health == 0 and data.guards[1].health == 45 and data.cargo_cycles == [1,2],"migration preserves casualties, wounds and completed cargo trips")
				check(not SCHEDULE.restore(data).is_empty(),"migrated state obeys save validation")
				var once := data.duplicate(true)
				APRON.migrate_loading(data)
				check(data == once,"checkpoint migration is idempotent")
	print("ARMORED_APRON_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
