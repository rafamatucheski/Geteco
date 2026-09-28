extends SceneTree
const IDS = ["pistol","magnum","smg","shotgun","sawed_off","ak47","m4a1","hunting_rifle","rpg","flamethrower","grenade","axe","knife","knuckles","bat","fists"]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var results := {}
	for variant in ["before", "after"]:
		var actor = load("res://evidence/dante-animation-fix-0924/Actor.before.gd" if variant == "before" else "res://scripts/Actor.gd").new()
		actor.is_player = true
		root.add_child(actor)
		actor.set_physics_process(false)
		var pose = load("res://evidence/dante-animation-fix-0924/WeaponRigPose.before.gd" if variant == "before" else "res://gameplay/WeaponRigPose.gd").new()
		var times: Array[float] = []
		for id in IDS:
			for tick in 300:
				actor.combat_facing = 0.0
				actor.combat_stance = "gun"
				var direction := Vector3.BACK if tick < 150 else Vector3.RIGHT
				var begin := Time.get_ticks_usec()
				actor._pose_locomotion(direction,3.5,direction*1.65/60.0,1.65)
				if tick % 60 == 0: pose.attack(id)
				actor.set_combat_weapon_pose(id,pose.update(id,1.0/60.0,true,tick>=150 and tick<250 and id in pose.FIREARMS,float(tick-150)/100.0,true,false,actor.phase))
				actor._apply_combat_weapon_pose()
				if tick >= 60: times.append(float(Time.get_ticks_usec()-begin)/1000.0)
		actor.free()
		times.sort()
		results[variant] = {"frames":times.size(),"p50_ms":times[times.size()/2],"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"max_ms":times.back()}
	print("POSE_CPU_ONLY_NOT_FPS ",JSON.stringify(results))
	FileAccess.open("res://evidence/dante-animation-fix-0924/pose-cost.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit()
