class_name CobraTireStack3D
extends Node3D
## Pilha de 3 pneus empilhados, cintados — a barricada do território hostil.
## Mesma técnica de anel de prototypes/harbor_art_pack/props/PortLifebuoyStand3D.gd
## (TorusMesh deitado), montada por CobraBarricade.gd via MountainStaticModelView.

func _ready() -> void:
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("161616")
	rubber.roughness = 0.9
	for i in 3:
		var tire := TorusMesh.new()
		tire.inner_radius = 0.20
		tire.outer_radius = 0.34
		tire.rings = 20
		tire.ring_segments = 12
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = tire
		mesh_instance.rotation_degrees.x = 90.0
		mesh_instance.position = Vector3(0, 0.14 + i * 0.14, 0)
		mesh_instance.material_override = rubber
		add_child(mesh_instance)
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color("2a2a2a")
	strap.roughness = 0.6
	for side in [-0.30, 0.30]:
		var band := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, 0.46, 0.05)
		band.mesh = box
		band.position = Vector3(side, 0.23, 0)
		band.material_override = strap
		add_child(band)
