extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var pose := preload("res://gameplay/street_physics/BodyImpactPose3D.gd").new()
	var joint := Node3D.new()
	root.add_child(joint)
	joint.basis = Basis.from_euler(Vector3(.1,.3,-.2)) * Basis.from_scale(Vector3(1.1,.95,1.07))
	var initial := joint.transform
	pose._add(joint,Vector3(-.4,0,.25))
	var ok := true
	for step in 61:
		pose.apply(float(step)/60.0,step > 45)
		ok = ok and joint.basis.is_finite() and joint.basis.get_scale().is_equal_approx(initial.basis.get_scale())
	pose.restore()
	ok = ok and joint.transform.is_equal_approx(initial)
	joint.free()
	print("BODY_IMPACT_SCALE samples=61 restored=true passed=",ok)
	quit(0 if ok else 1)
