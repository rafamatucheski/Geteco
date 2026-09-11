extends SceneTree
## Confere se os dedos atravessam a imagem da galeria nas quatro poses fotografadas.
var cache: Dictionary={}
var failures:=0
var hits: Dictionary={}
func _initialize() -> void: run.call_deferred()

func meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.visible: out.append(node)
	for child in node.get_children(): meshes(child,out)

func intersections(node: MeshInstance3D, photo: MeshInstance3D) -> int:
	var id:=node.mesh.get_instance_id()
	if not cache.has(id):
		var arrays:=node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		cache[id]=[vertices,indices]
	var vertices: PackedVector3Array=cache[id][0]
	var indices: PackedInt32Array=cache[id][1]
	var transform:=photo.global_transform.affine_inverse()*node.global_transform
	var points:=transform*vertices
	var count:=0
	for i in range(0,indices.size(),3):
		for edge in 3:
			var a: Vector3=points[indices[i+edge]]
			var b: Vector3=points[indices[i+(edge+1)%3]]
			if a.z*b.z>=0: continue
			var point:=a.lerp(b,-a.z/(b.z-a.z))
			if absf(point.x)<photo.mesh.size.x/2 and absf(point.y)<photo.mesh.size.y/2: count+=1
	return count

func run() -> void:
	var stage: Node3D=load("res://cutscenes/opening/v3/opening_stage.gd").new()
	root.add_child(stage); await process_frame
	var samples:=0
	for t in [47.5,48.2,64.5,69.5]:
		stage.set_time(t)
		assert(stage.phone_gallery.visible)
		for hand in stage.hands:
			var parts: Array[MeshInstance3D]=[]; meshes(hand,parts)
			for part in parts:
				var count:=intersections(part,stage.phone_gallery)
				if count>0:
					hits[String(part.get_path())]=[t,count]
					failures+=count
		samples+=1
	for key in hits: print("INTERSECTION ",key," first=",hits[key])
	print("OPENING_PHOTO_SURFACE samples=",samples," triangle_edges_crossing_gallery=",failures)
	stage.queue_free(); await process_frame; await create_timer(.2).timeout
	quit(1 if failures else 0)
