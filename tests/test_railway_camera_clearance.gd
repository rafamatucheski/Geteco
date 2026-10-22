extends SceneTree
const CLEARANCE := preload("res://scripts/camera/RailwayCameraClearance.gd")
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")

func _initialize() -> void:
	var checks := 0
	var reproduced := 0
	var points: PackedVector3Array=NETWORK.edges()[2].points
	for heading in [0.0,PI*.25,PI*.5,PI]:
		var nominal := Vector3(0,25.3,25.3).rotated(Vector3.UP,heading)
		var back := nominal.normalized()
		var right := Vector3.UP.cross(back).normalized()
		var up := back.cross(right).normalized()
		for size in [24.0,40.0,60.0]:
			var view := Vector2(size*16.0/9.0,size)
			for index in range(0,points.size(),maxi(1,points.size()/12)):
				var focus := Vector3(points[index].x,0,points[index].z)-Vector3(back.x,0,back.z)*20.0
				var clearance := CLEARANCE.new()
				var safe := clearance.offset_for(focus,nominal,view,.1)
				assert(safe.normalized().is_equal_approx(back),"orthographic direction stays fixed")
				assert(safe.length()>=nominal.length()-.001,"safety never brings the lens closer")
				checks+=2
				for point in points:
					var top: Vector3=point+Vector3.UP*1.1
					var relative := top-focus
					var screen := Vector2(relative.dot(right),relative.dot(up))
					if not Rect2(-view*.5,view).has_point(screen): continue
					var old_depth := nominal.length()-relative.dot(back)
					if old_depth<.1: reproduced+=1
					assert(safe.length()-relative.dot(back)>=.1,"visible elevated rail remains beyond near plane")
					# Translating along back cannot change either screen coordinate.
					assert(absf((top-focus-safe).dot(right)-screen.x)<.001)
					assert(absf((top-focus-safe).dot(up)-screen.y)<.001)
					checks+=3
	assert(reproduced>0,"the old camera reproduced near-plane clipping in the authored railway")
	var far_away := CLEARANCE.new().offset_for(Vector3(-2000,0,1000),Vector3(0,25.3,25.3),Vector2(40,24),.1)
	assert(far_away.is_equal_approx(Vector3(0,25.3,25.3)),"unrelated areas keep the original pose")
	print("RAILWAY_CAMERA_CLEARANCE PASS checks=",checks," old_clipped_samples=",reproduced)
	quit()
