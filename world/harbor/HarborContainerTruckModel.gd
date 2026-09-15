extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## Open container carrier used only by the South Port fleet.
var cargo_mount: Node3D

func build() -> void:
	paint = mat("paint","31577a",.3,.4)
	var steel := mat("steel","495b60",.7,.5)
	var black := mat("rubber","182126",.0,.9)
	var glass := mat("glass","203e4a",.3,.2)
	var trim := mat("trim","c3c5ad",.6,.4)
	var head := mat("headlight","fff0bd",.1,.2,.7)
	var tail := mat("taillight","d95238",.1,.3,.5)
	box(Vector3(0,.4,0),Vector3(2.1,.25,8.5),steel)
	box(Vector3(0,.77,1),Vector3(2.5,.16,5.95),steel)
	for z in [-1.8,3.8]:
		for x in [-1.12,1.12]: box(Vector3(x,.90,z),Vector3(.18,.14,.18),trim)
	box(Vector3(0,1.35,-3.15),Vector3(2.35,1.85,1.95),paint)
	box(Vector3(0,1.74,-4.14),Vector3(2.12,.78,.04),glass)
	box(Vector3(0,2.31,-3.15),Vector3(2.45,.12,2.04),paint)
	box(Vector3(0,.51,-4.23),Vector3(2.48,.28,.2),trim)
	box(Vector3(0,1,-4.16),Vector3(1.25,.37,.05),black)
	for side in [-1,1]:
		box(Vector3(side*1.18,1.7,-3.2),Vector3(.035,.65,1.2),glass)
		box(Vector3(side*1.38,1.8,-3.95),Vector3(.2,.35,.17),steel)
		box(Vector3(side*.91,.9,-4.17),Vector3(.35,.27,.05),head)
		box(Vector3(side*.9,.49,4.24),Vector3(.33,.18,.05),tail)
		box(Vector3(side*1.1,.4,-.7),Vector3(.2,.26,1.7),trim)
		for z in [-3.05,2.25,3.45]: add_wheel(side*1.05,.47,z,.47,.3,.25,6)
	cargo_mount = Node3D.new()
	cargo_mount.name = "ContainerOnFlatbed"
	cargo_mount.position = Vector3(0,.85,1)
	add_child(cargo_mount)
	cargo_mount.hide()

func prepare_cargo(theme: int) -> void:
	var container := preload("res://prototypes/harbor_art_pack/props/PortContainer40ft3D.gd").new()
	container.color_theme = theme
	container.scale = Vector3(.9,.72,.475)
	cargo_mount.add_child(container)
	preload("res://prototypes/harbor_art_pack/PortMeshOptimizer.gd").optimize_hierarchy(cargo_mount)
	for batch in cargo_mount.get_node("BatchedStaticGeometry").get_children():
		var surface := SurfaceTool.new()
		surface.create_from(batch.mesh,0)
		surface.generate_normals()
		batch.mesh = surface.commit()
