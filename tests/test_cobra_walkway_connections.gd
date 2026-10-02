extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var dressing:=preload("res://world/editing/EditableCobraDressing.gd").new()
	dressing.configure("cobra")
	dressing.position=Vector3(481.25,0,106.25)
	root.add_child(dressing)
	var document: Dictionary=preload("res://world/editing/WorldEditData.gd").read_document()
	check(document.error.is_empty(),"Saved map parses and validates")
	preload("res://world/editing/WorldEditPieces.gd").apply(dressing,document.document.regions.harbor)
	await process_frame
	var paths:=[]
	for mesh in dressing.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("cobra_surface_label","")=="CobraFootpath": paths.append(mesh)
	for joint in [Vector2(7220,1580),Vector2(7250,1450),Vector2(7290,1290),Vector2(7300,2080),Vector2(7750,2080)]:
		var hits:=0
		for mesh in paths:
			var local: Vector3=mesh.to_local(Vector3(joint.x/16,.02,joint.y/16))
			if mesh.get_aabb().grow(.01).has_point(local): hits+=1
		check(hits>=2,"Saved walkway segments meet at "+str(joint))
	var grass:=dressing.find_children("*","MultiMeshInstance3D",true,false)
	check(grass.size()==1,"One grass batch survives the saved piece transforms")
	var overlaps:=0
	if not grass.is_empty():
		var display: MultiMeshInstance3D=grass[0]
		for i in display.multimesh.instance_count:
			var world:=display.global_transform*display.multimesh.get_instance_transform(i).origin
			for path in paths:
				var p: Vector3=path.to_local(world)
				var b: AABB=path.get_aabb()
				if p.x>=b.position.x and p.x<=b.end.x and p.z>=b.position.z and p.z<=b.end.z: overlaps+=1
	check(overlaps==0,"Grass respects actual edited walkway footprints")
	print("COBRA_WALKWAYS checks=8 failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
