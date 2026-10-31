extends SceneTree
## Regressão: os trabalhadores offline precisam carregar, entregar e voltar sem parar,
## incluindo a virada entre ciclos, em vez de ficar parados numa marca congelada.
const ACTIVITY := preload("res://cutscenes/opening/ferry/FerryHarborActivity.gd")
func _initialize() -> void:
	var route := [Vector3.ZERO,Vector3(4,0,0),Vector3(4,0,2),Vector3(0,0,2)]
	var previous: Vector3 = ACTIVITY.worker_pose(route,0.0).position
	var distance := 0.0
	var carrying_distance := 0.0
	var empty_distance := 0.0
	var max_step := 0.0
	var at_source := false
	var at_destination := false
	for frame in range(1,2191):
		var pose := ACTIVITY.worker_pose(route,float(frame)/30.0)
		var step: float = previous.distance_to(pose.position)
		assert(pose.position.is_finite() and pose.speed>=0 and pose.speed<=1.3)
		assert(step<.044,"Worker must not jump at route/cycle boundaries")
		assert(pose.position.x>=-.001 and pose.position.x<=4.001 and pose.position.z>=-.001 and pose.position.z<=2.001)
		distance += step
		max_step = maxf(max_step,step)
		if pose.carrying: carrying_distance += step
		else: empty_distance += step
		if pose.position.distance_to(route[0])<.001 and pose.speed==0: at_source = true
		if pose.position.distance_to(route[2])<.001 and pose.speed==0: at_destination = true
		previous = pose.position
	assert(distance>40 and carrying_distance>20 and empty_distance>20)
	assert(at_source and at_destination,"Handling must stop at both work stations")
	print("FERRY_HARBOR_ACTIVITY frames=2190 distance=",distance," max_step=",max_step)
	quit()
