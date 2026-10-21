extends SceneTree
const FOOTPRINTS := preload("res://addons/geteco_world_editor/WorldPreviewUnitFootprints.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const UNITS := preload("res://world/editing/WorldUnits.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func run() -> void:
	var source := Node3D.new()
	root.add_child(source)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,1,0),Vector3(0,1,2),Vector3(0,2,2),Vector3(100,1,78),Vector3(100,1,80),Vector3(100,2,80)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	source.add_child(node)
	var group := PIECES.group(source,[node],"unit/harbor/s_motocross/SparseTape","Sparse tape")
	group.set_meta("world_edit_auto",true)
	group.set_meta("world_edit_source","unit/harbor/s_motocross")
	var rows := UNITS.manifest(source)
	check(rows.size() == 1 and rows[0].parts.size() == 1,"Fixture reproduces one filled bounding rectangle around a sparse wide course mesh")
	var original: Dictionary = rows[0].duplicate(true)
	FOOTPRINTS.refine(source,rows)
	check(rows[0].parts.size() == 2,"Vertical course tape retains its actual two thin projected strips")
	var covers_center := false
	for part: Array in rows[0].parts:
		if Rect2(part[0],part[1],part[2],part[3]).has_point(Vector2(50,40)): covers_center = true
	check(not covers_center,"Empty space between sparse decorations no longer paints over the real terrain")
	check(rows[0].id == original.id and rows[0].position == original.position and rows[0].size == original.size,"Refining the visual footprint preserves permanent identity, pivot and transform dimensions")
	check(node.mesh == mesh and node.get_parent() == group,"No scene geometry, resources or collision groups change")
	var unrelated: Dictionary = original.duplicate(true)
	unrelated.source_record = "unit/harbor/other_place"
	var unrelated_rows: Array = [unrelated]
	FOOTPRINTS.refine(source,unrelated_rows)
	check(unrelated_rows[0].parts.size() == 1,"The fix stays restricted to the affected motocross generator")
	source.free()
	print("WORLD_EDITOR_SPARSE_FOOTPRINTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
