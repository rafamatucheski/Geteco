extends SceneTree
## Casa do Zelador pintada: um kit só, nenhuma peça 3D antiga visível, a única porta é a
## do WalkupFacadeDoor (folha pintada na dobradiça dela), colisão do casco e interior
## preservados, e o interruptor GETECO_PAINTED_KEEPER=0 devolve o 3D antigo.
const EXTERIOR := "res://assets/regions/source/world/harbor/cemetery/CemeteryHouseExterior3D.gd"
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func build(stage: Node3D) -> Array:
	var art: Node3D = load(EXTERIOR).new()
	stage.add_child(art)
	var facade = load("res://world/places/WalkupFacadeDoor.gd").install(art, CATALOG.get_definition("cemetery_keeper"))
	return [art, facade]

func visible_meshes(node: Node) -> Array:
	var list: Array = []
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).is_visible_in_tree(): list.append(mesh)
	return list

func run() -> void:
	OS.set_environment("GETECO_PAINTED_KEEPER", "1")
	var style := "casa-zelador"
	check(PaintedFacadeKit.all_styles().has(style), "style imported")
	var front: Array = PaintedFacadeKit.openings(style, "front")
	check(front.size() == 1 and front[0].leaf, "one front doorway with leaf")
	check(PaintedFacadeKit.openings(style, "back").is_empty(), "no back doorway (art has none)")
	var size := PaintedFacadeKit.natural_size(style)
	check(is_equal_approx(size.x, 7.1) and absf(size.y - 2.7) < .01 and is_equal_approx(size.z, 5.4), "natural size = hull 7.1 x 2.7 x 5.4")
	var stage := Node3D.new()
	root.add_child(stage)
	# Sem o adaptador: o casco continua o sólido do interior, escondido e rente ao chão.
	var bare: Node3D = load(EXTERIOR).new()
	stage.add_child(bare)
	var cottage := bare.get_node("LimewashedCottage") as MeshInstance3D
	check(cottage.get_meta("interior_solid_id", &"") == &"CottageWalls", "cottage keeps interior solid id")
	check(not cottage.visible, "cottage box hidden")
	check(absf(cottage.position.y - cottage.mesh.get_aabb().size.y * .5) < .001, "hull reaches the ground")
	bare.free()
	var built := build(stage)
	var art: Node3D = built[0]
	var adapter: Node3D = built[1]
	check(art.find_children("PaintedFacade_*", "", true, false).size() == 1, "exactly one painted kit")
	for old in ["TerracottaRoof", "SignBoard", "WindowFrame", "WindowGlass", "StoneFoundation", "StoneStep", "Firewood", "Chimney", "DoorPlank"]:
		check(art.find_children(old + "*", "", true, false).is_empty(), "old part gone: " + old)
	check(art.find_children("*", "Label3D", true, false).is_empty(), "no 3D lettering left")
	for piece in art.find_children("LimewashedCottagePassage*", "MeshInstance3D", true, false):
		check(not (piece as Node3D).visible, "hull passage piece hidden")
	check(not art.find_children("LimewashedCottagePassage*", "MeshInstance3D", true, false).is_empty(), "hull still cut for the doorway")
	var painted_leaves := art.find_children("PaintedDoorLeaf*", "MeshInstance3D", true, false)
	check(painted_leaves.size() == 2, "one painted leaf (front + inside)")
	var hinge: Node3D = adapter.get_node("DoorHinge")
	for leaf in painted_leaves: check(hinge.is_ancestor_of(leaf), "painted leaf lives on the walk-up hinge")
	check(art.get_node("PaintedKeeperHouse").find_children("Door", "", true, false).is_empty(), "kit has no door of its own (no duplicate)")
	check(hinge.get_node("DoorSolid") != null, "walk-up door solid kept")
	var leaf: MeshInstance3D = painted_leaves[0]
	var quad := leaf.mesh as QuadMesh
	check(quad.size.x > 1.2 and quad.size.x < 1.6 and quad.size.y > 2.0 and quad.size.y < 2.3, "leaf fills the painted doorway")
	check(absf(leaf.global_position.y - quad.size.y * .5) < .06, "door sill at ground level")
	check(absf(leaf.global_position.x) < .02, "painted doorway centered on the real door (x=0)")
	var before := leaf.global_position
	adapter.set_open_amount(1.0)
	check(leaf.global_position.distance_to(before) > .3, "leaf swings with the walk-up hinge")
	adapter.set_open_amount(0.0)
	# O que sobra visível é o kit, a folha e o vão escuro: nada fora do holder pintado.
	for mesh in visible_meshes(art):
		check(art.get_node("PaintedKeeperHouse").is_ancestor_of(mesh) or hinge.is_ancestor_of(mesh), "visible mesh belongs to the painted house: " + str(mesh.name))
	stage.queue_free()
	await process_frame
	# Interruptor: volta ao 3D antigo.
	OS.set_environment("GETECO_PAINTED_KEEPER", "0")
	var old_stage := Node3D.new()
	root.add_child(old_stage)
	var old_built := build(old_stage)
	check(not (old_built[0] as Node3D).has_node("PaintedKeeperHouse"), "switch off: no painted house")
	check(not (old_built[0] as Node3D).find_children("TerracottaRoof", "", true, false).is_empty(), "switch off: old roof back")
	OS.set_environment("GETECO_PAINTED_KEEPER", "")
	old_stage.queue_free()
	await process_frame
	print("PAINTED_CEMETERY_KEEPER checks=", checks, " failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)
