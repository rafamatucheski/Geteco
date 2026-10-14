extends SceneTree
const DRESSING := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const COMPOSER := preload("res://world/urban_detail/HarborDressingGround.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for zone in ["cobra","salvage","cemetery"]:
		print("DRESSING_BEGIN ",zone)
		var started := Time.get_ticks_msec()
		var dressing := DRESSING.new()
		dressing.configure(zone)
		root.add_child(dressing)
		print("DRESSING_BUILT ",zone," ms=",Time.get_ticks_msec()-started)
		var owners := {}
		var names := {}
		for node in dressing.find_children("*","MeshInstance3D",true,false):
			if node.mesh == null or not COMPOSER._is_ground(str(node.get_meta("harbor_ground_label",node.name))): continue
			var faces: PackedVector3Array = node.mesh.get_faces()
			for i in range(0,faces.size(),3):
				var a: Vector3 = node.global_transform*faces[i]
				var b: Vector3 = node.global_transform*faces[i+1]
				var c: Vector3 = node.global_transform*faces[i+2]
				var lo := Vector2(minf(a.x,minf(b.x,c.x)),minf(a.z,minf(b.z,c.z)))
				var hi := Vector2(maxf(a.x,maxf(b.x,c.x)),maxf(a.z,maxf(b.z,c.z)))
				for x in range(floori(lo.x),ceili(hi.x)):
					for z in range(floori(lo.y),ceili(hi.y)):
						var p := Vector2(x+.371,z+.613)
						if not Geometry2D.point_is_inside_triangle(p,Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)): continue
						var key := Vector2i(x,z)
						owners[key] = int(owners.get(key,0))+1
						if not names.has(key): names[key] = []
						names[key].append(str(node.name))
		var overlaps := 0
		for key in owners:
			if owners[key]>1:
				overlaps+=1
				if overlaps<5: print("DRESSING_OVERLAP ",key," ",names[key])
		if overlaps>0 or owners.size()<100: failures+=1
		print("DRESSING_GROUND ",zone," samples=",owners.size()," overlapping_samples=",overlaps)
		dressing.free()
	print("DRESSING_RESULT failures=",failures)
	quit(1 if failures else 0)
