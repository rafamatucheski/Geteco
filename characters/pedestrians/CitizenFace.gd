extends RefCounted
## Tapered adult face; four material batches, no animation/render loop.
static func build(head: Node3D, radius: float, skin: Color, variant: int) -> void:
	if head.has_node("CitizenFace"): return
	var root=Node3D.new()
	root.name="CitizenFace"
	root.scale=Vector3.ONE*(radius/.17)
	head.add_child(root)
	var colors=[skin,skin.darkened(.38),Color("ded8cd"),Color("29282c")]
	var batches: Array[SurfaceTool]=[]
	for color in colors:
		var surface=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var material=StandardMaterial3D.new()
		material.albedo_color=color
		material.roughness=.85
		surface.set_material(material)
		batches.append(surface)
	# Keep the original cranium and headwear. Shape the visible jaw in front.
	add(batches[0],Vector3(.21,.15,.15),Vector3(0,-.068,-.056))
	for side in [-1,1]:
		var eye_x: float=side*(.057+(variant%3)*.003)
		add(batches[1],Vector3(.067,.032,.028),Vector3(eye_x,.024,-.155))
		add(batches[2],Vector3(.044,.018,.022),Vector3(eye_x,.024,-.17))
		add(batches[3],Vector3(.018,.019,.012),Vector3(eye_x,.024,-.182))
		add(batches[3],Vector3(.068,.015,.024),Vector3(eye_x,.053,-.16))
		add(batches[0],Vector3(.042,.074,.046),Vector3(side*.162,-.012,.002))
	add(batches[0],Vector3(.031,.089,.042),Vector3(0,.004,-.163))
	add(batches[0],Vector3(.052+(variant%4)*.004,.038,.043),Vector3(0,-.028,-.187))
	add(batches[1],Vector3(.068,.014,.023),Vector3(0,-.078,-.148))
	add(batches[0],Vector3(.062,.012,.019),Vector3(0,-.087,-.144))
	for batch in batches:
		var part=MeshInstance3D.new()
		part.mesh=batch.commit()
		root.add_child(part)
static func add(surface: SurfaceTool, size: Vector3, point: Vector3) -> void:
	var mesh=SphereMesh.new()
	mesh.radius=.5
	mesh.height=1
	mesh.radial_segments=12
	mesh.rings=6
	surface.append_from(mesh,0,Transform3D(Basis.from_scale(size),point))
