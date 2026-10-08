extends SceneTree
## Check the actual triangle winding and lens-to-body contact, independently of
## render screenshots. A lens must be exposed, supported and close to its panel.
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const MODEL := preload("res://gameplay/desert_cars/DesertCarModel.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _triangles(model: Node3D, key: String) -> Array:
	var triangles: Array = []
	for part: MeshInstance3D in model.get_children():
		if part.material_override.resource_name != key: continue
		var faces := part.mesh.get_faces()
		for i in range(0,faces.size(),3):
			triangles.append([part.transform*faces[i],part.transform*faces[i+1],part.transform*faces[i+2]])
	return triangles

func _run() -> void:
	for id: String in CATALOG.ids():
		var spec := CATALOG.spec(id)
		var model := MODEL.create(spec)
		var shell := Node3D.new()
		var paint := StandardMaterial3D.new()
		paint.resource_name = "paint"
		if spec.body == "coupe":
			preload("res://gameplay/desert_cars/DesertZShape.gd")._shell(shell,spec,paint)
		else:
			MODEL._body(shell,spec,paint)
		var hull := _triangles(shell,"paint")
		for end in [-1.0,1.0]:
			var seen := 0
			var inverted := 0
			for tri: Array in hull:
				var center: Vector3 = (tri[0]+tri[1]+tri[2])/3.0
				var normal: Vector3 = (tri[2]-tri[0]).cross(tri[1]-tri[0]).normalized()
				if center.z*end > float(spec["size"][2])*.46 and absf(normal.z)>.8:
					seen += 1
					if normal.z*end<0: inverted += 1
			check(seen>0 and inverted==0,"%s end %s: opaque fascia triangles face outside (%d inverted / %d)"%[id,end,inverted,seen])
			if spec.body!="coupe" and not (spec.body=="pickup" and end>0):
				var lip_y := float(spec.shoulder)*(.90 if spec.body=="pickup" else .85) if end<0 else float(spec.shoulder)*.96
				var missing := 0
				for side_x in [-.40,-.20,0.0,.20,.40]:
					for rise in [.005,.022,.040]:
						var ray := Vector3(float(side_x)*float(spec["size"][0]),lip_y+float(rise),end*float(spec["size"][2])*.55)
						var found := false
						for tri: Array in hull:
							var hit: Variant = Geometry3D.ray_intersects_triangle(ray,Vector3(0,0,-end),tri[0],tri[1],tri[2])
							if hit is Vector3 and hit.z*end>float(spec["size"][2])*.48: found=true; break
						if not found: missing += 1
				check(missing==0,"%s end %s: inset deck joins fascia without see-through slit (%d missing)"%[id,end,missing])
		for key in ["headlight","tail"]:
			var tested := 0
			var unsupported := 0
			var buried := 0
			var detached := 0
			var worst_gap := 0.0
			var outward := Vector3.UP if spec.body=="coupe" else Vector3(0,0,-1 if key=="headlight" else 1)
			for tri: Array in _triangles(model,key):
				var normal: Vector3 = (tri[2]-tri[0]).cross(tri[1]-tri[0]).normalized()
				if normal.dot(outward)<.8: continue
				var center: Vector3 = (tri[0]+tri[1]+tri[2])/3.0
				# Include vertices near the rim: a supported centre alone misses
				# the corner hanging beyond the bonnet or the trunk edge.
				for point: Vector3 in [center,center.lerp(tri[0],.98),center.lerp(tri[1],.98),center.lerp(tri[2],.98)]:
					tested += 1
					var origin := point+outward*.15
					var nearest := INF
					for support: Array in hull:
						var hit: Variant = Geometry3D.ray_intersects_triangle(origin,-outward,support[0],support[1],support[2])
						if hit is Vector3: nearest=minf(nearest,origin.distance_to(hit))
					if not is_finite(nearest): unsupported += 1; continue
					var gap := nearest-.15
					worst_gap=maxf(worst_gap,gap)
					if gap<.0005: buried += 1
					if gap>.035: detached += 1
			check(tested>0 and unsupported==0,"%s %s: lens perimeter has body support (%d / %d unsupported)"%[id,key,unsupported,tested])
			check(buried==0,"%s %s: lens faces remain outside the opaque panel (%d buried)"%[id,key,buried])
			check(detached==0,"%s %s: lens follows panel within 35 mm (%d detached, max %.3f m)"%[id,key,detached,worst_gap])
		model.free()
		shell.free()
	print("DESERT_CAR_FIT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
