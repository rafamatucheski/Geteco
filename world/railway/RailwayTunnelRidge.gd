extends RefCounted
## The tunnel is cut through a small authored ridge. Its skin and collision are
## the same triangles, with buried irregular feet and genuinely open portals.
const COLLISION_FACES := preload("res://world/chunk_bake/CollisionFaces.gd")
static func build(parent: Node3D, a: Vector3, b: Vector3, material: StandardMaterial3D) -> void:
	var along := (b-a).normalized()
	var right := along.cross(Vector3.UP).normalized()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var count := maxi(6,ceili(a.distance_to(b)/7.0))
	for index in count+1:
		var t := float(index)/float(count)
		var center := a.lerp(b,t)
		var ripple := sin(t*19.0+.6)*.8+sin(t*8.0)*.65
		var width := 11.8+sin(t*11.0+.9)*1.6
		var top := center.y+6.55
		var ring := PackedVector3Array([
			Vector3(center.x,-.28,center.z)-right*width,
			Vector3(center.x,center.y*.56+ripple,center.z)-right*(6.2+sin(t*9.0)*.5),
			Vector3(center.x,top+.2*absf(ripple),center.z)-right*3.56,
			Vector3(center.x,top+1.8+ripple,center.z)+right*sin(t*8.0)*.6,
			Vector3(center.x,top+.3*absf(ripple),center.z)+right*3.56,
			Vector3(center.x,center.y*.61-ripple*.6,center.z)+right*(6.6+sin(t*12.0)*.6),
			Vector3(center.x,-.32,center.z)+right*(width+1.3),
		])
		rings.append(ring)
		if index == 0: continue
		var previous: PackedVector3Array = rings[index-1]
		for cross in range(ring.size()-1):
			_face(surface,PackedVector3Array([previous[cross],previous[cross+1],ring[cross+1],ring[cross]]),Vector3.UP)
	# Close the flank cut faces, keeping the entire clearance rectangle open.
	for end_index in [0,count]:
		var ring: PackedVector3Array = rings[end_index]
		var outward := -along if end_index==0 else along
		for side in [0,1]:
			var outer: Vector3 = ring[0 if side==0 else 6]
			var middle: Vector3 = ring[1 if side==0 else 5]
			var inner: Vector3 = ring[2 if side==0 else 4]
			_face(surface,PackedVector3Array([outer,middle,inner,Vector3(inner.x,-.45,inner.z),Vector3(outer.x,-.45,outer.z)]),outward)
		var roof_base := (a if end_index==0 else b).y+6.34
		_face(surface,PackedVector3Array([ring[2],ring[3],ring[4],Vector3(ring[4].x,roof_base,ring[4].z),Vector3(ring[2].x,roof_base,ring[2].z)]),outward)
	# Malha e colisão das mesmas arrays da CPU: create_trimesh_shape lia a malha de volta da GPU (auditoria 19/10).
	var built: Array = COLLISION_FACES.commit_with_shape(surface)
	var mesh: ArrayMesh = built[0]
	var stone := material.duplicate() as StandardMaterial3D
	stone.vertex_color_use_as_albedo = true
	var visual := MeshInstance3D.new()
	visual.name = "CutRockRidge"
	visual.mesh = mesh
	visual.material_override = stone
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "CutRockRidgeSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("railway_solid")
	var collision := CollisionShape3D.new()
	collision.shape = built[1]
	body.add_child(collision)
	parent.add_child(body)

static func _face(surface: SurfaceTool, points: PackedVector3Array, outward: Vector3) -> void:
	for index in range(1,points.size()-1):
		var triangle := PackedVector3Array([points[0],points[index],points[index+1]])
		var normal := (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
		if normal.length_squared()<.5: continue
		if normal.dot(outward)<0.0: normal=-normal
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).dot(normal)>0.0: triangle.reverse()
		for point in triangle:
			var tone := .90+.05*sin(point.y*.82+point.x*.06)+.035*sin(point.z*.12)
			surface.set_color(Color(tone,tone*.995,tone*.97,1))
			surface.set_normal(normal)
			surface.add_vertex(point)
