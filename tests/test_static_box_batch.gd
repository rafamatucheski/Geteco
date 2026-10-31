extends SceneTree
## Compara geometria/atributos indexados com o caminho nativo legado do SurfaceTool.
const BOX_BATCH := preload("res://runtime/transit/StaticBoxBatch.gd")
var failed := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed += 1
		push_error(label)

func run() -> void:
	var old := SurfaceTool.new()
	var candidate := SurfaceTool.new()
	old.begin(Mesh.PRIMITIVE_TRIANGLES)
	candidate.begin(Mesh.PRIMITIVE_TRIANGLES)
	var offset := 0
	var sizes := [Vector3(2.55,2.58,11.5),Vector3(.025,.64,.06),Vector3(2.42,.18,7.8),Vector3(1,1,1)]
	for i in sizes.size():
		var box := BoxMesh.new()
		box.size = sizes[i]
		var basis := Basis.from_euler(Vector3(.12,.5,.21))
		if i == 3: basis = basis.scaled(Vector3(-1.0,1.2,.8))
		var pose := Transform3D(basis,Vector3(i*.3,.8,-i))
		old.append_from(box,0,pose)
		offset = BOX_BATCH.append_from(candidate,box,0,pose,offset)
	# Os dois chamadores mantêm as rodas cilíndricas fora do lote; outra geometria futura
	# e caixas subdivididas precisam manter o caminho de append original.
	var cylinder := CylinderMesh.new()
	old.append_from(cylinder,0,Transform3D.IDENTITY)
	offset = BOX_BATCH.append_from(candidate,cylinder,0,Transform3D.IDENTITY,offset)
	var subdivided := BoxMesh.new()
	subdivided.subdivide_width = 2
	old.append_from(subdivided,0,Transform3D.IDENTITY)
	offset = BOX_BATCH.append_from(candidate,subdivided,0,Transform3D.IDENTITY,offset)
	var final_box := BoxMesh.new()
	final_box.size = Vector3(.1,.2,.3)
	old.append_from(final_box,0,Transform3D.IDENTITY)
	offset = BOX_BATCH.append_from(candidate,final_box,0,Transform3D.IDENTITY,offset)
	var expected := old.commit_to_arrays()
	var actual := candidate.commit_to_arrays()
	check(expected[Mesh.ARRAY_INDEX] == actual[Mesh.ARRAY_INDEX],"indices and winding preserved")
	check(expected[Mesh.ARRAY_VERTEX].size() == actual[Mesh.ARRAY_VERTEX].size(),"vertex count preserved")
	for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV]:
		var equal: bool = expected[field].size() == actual[field].size()
		if equal:
			for i in expected[field].size():
				if typeof(expected[field][i]) == TYPE_FLOAT:
					if absf(expected[field][i]-actual[field][i]) > .002: equal = false; break
				elif expected[field][i].distance_to(actual[field][i]) > .002:
					equal = false; break
		check(equal,"geometry attribute %d preserved" % field)
	check(offset == actual[Mesh.ARRAY_VERTEX].size(),"offset matches mixed geometry")
	print("STATIC_BOX_BATCH ",checks-failed,"/",checks)
	quit(0 if failed == 0 else 1)
