extends SceneTree
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const MODELS := preload("res://activities/motocross/MotocrossModels.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var worst_hand := 0.0
	var worst_boot := 0.0
	var worst_arm := 0.0
	var worst_forearm := 0.0
	var worst_cuff := 0.0
	for model in 3:
		var bike := BIKE.new()
		MODELS.apply(bike,model)
		root.add_child(bike)
		bike.set_physics_process(false)
		bike.position = Vector3(12,3,-8)
		bike.rotation.y = 1.3
		for steer in [-1.0,0.0,1.0]:
			for lean in [-.28,0.0,.28]:
				for pitch in [-.35,0.0,.35]:
					bike.visual.rotation = Vector3(pitch,0,lean)
					bike._front.rotation.y = steer*.4
					bike._seat_rider()
					for i in 2:
						var side := -1.0 if i==0 else 1.0
						var art = bike._rider_visual
						var grip := bike._front.to_global(Vector3(side*.39,.85,.32))
						worst_hand = maxf(worst_hand,art.hands[i].global_position.distance_to(grip))
						var sole: Vector3 = art.boots[i].to_global(Vector3(0,-.12,0))
						worst_boot = maxf(worst_boot,sole.distance_to(bike.visual.to_global(Vector3(side*.27,.39,.08))))
						worst_arm = maxf(worst_arm,absf(art.arms[i][0].basis.y.length()-.32))
						worst_forearm = maxf(worst_forearm,absf(art.arms[i][1].basis.y.length()-.31))
						var calf: MeshInstance3D = art.legs[i][1]
						var ankle_end := calf.to_global(Vector3(0,.5,0))
						var knee_end := calf.to_global(Vector3(0,-.5,0))
						var cuff_top: Vector3 = art.boot_cuffs[i].to_global(Vector3(0,.22,0))
						var shin_point := Geometry3D.get_closest_point_to_segment(cuff_top,ankle_end,knee_end)
						worst_cuff = maxf(worst_cuff,cuff_top.distance_to(shin_point))
		check(bike._wheels.size()==2,"model%d has two rotating wheels"%model)
		bike.visual.rotation = Vector3.ZERO
		bike.pose_start_mount(1)
		check(bike._rider_visual.hands[0].global_position.distance_to(bike._front.to_global(Vector3(-.39,.85,.32)))<.003,"mount finishes with model%d holding handlebar"%model)
		bike.crash(.4)
		check(bike.rider.top_level and bike.rider.collision_layer==2,"model%d still detaches with physical rider collision"%model)
		bike.free()
	check(worst_hand<.003,"both hands follow real handlebars over 81 steering/slope/lean poses")
	check(worst_boot<.003,"boots follow real footpegs while leaning and pitching")
	check(worst_arm<.025,"upper arms retain anatomical length instead of stretching to grips")
	check(worst_forearm<.04,"forearms retain anatomical reach at full steering lock")
	check(worst_cuff<.003,"boot shafts remain around the shins instead of detached beside them")
	print("MOTOCROSS_ART_RESULT checks=",checks," failures=",failures," hand_error=",worst_hand," boot_error=",worst_boot," arm_error=",worst_arm," forearm_error=",worst_forearm)
	quit(0 if failures.is_empty() else 1)
