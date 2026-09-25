extends UrbanBuildingBase
class_name PortBossGarageExterior3D

## Native exterior of the productive port garage, reconstructed from
## PortBossGaragePortal.gd. The catalog origin is PortBossGarage.EXTERIOR; the
## V1 interaction marker is four metres west and the building extends west.

func build() -> void:
	# This restricted garage has no facade sign; its catalog name remains usable in menus.
	proper_name = ""
	height = 3.2
	var wall := UrbanMaterials.material_for_color(Color("777c72"), 0.86)
	var trim := UrbanMaterials.material_for_color(Color("94958a"), 0.82)
	var roof := UrbanMaterials.material_for_color(Color("45565c"), 0.88)
	var shutter := UrbanMaterials.material_for_color(Color("3a484a"), 0.72)
	var stripe := UrbanMaterials.material_for_color(Color("cfb850"), 0.76)
	# Source coordinates are translated so the V1 marker (x=8.8) lands at the
	# catalog approach (-4 m). Dimensions and colors remain those of the portal.
	add_solid_box(visuals_root, "BossGarageMainShell", Vector3(-13.8, 1.6, 0), Vector3(15.0, 3.2, 6.0), wall)
	add_mesh_box(visuals_root, "BossGarageRoof", Vector3(-13.8, 3.25, 0), Vector3(15.3, 0.16, 6.3), roof)
	add_mesh_box(visuals_root, "BossGarageApronBase", Vector3(-5.4, -0.04, 0), Vector3(1.8, 0.08, 5.7), UrbanMaterials.sidewalk_stone())
	for side in [-1.0, 1.0]:
		add_solid_box(visuals_root, "BossGarageSide", Vector3(-5.4, 1.6, side * 2.9), Vector3(1.8, 3.2, 0.3), wall)
		add_solid_box(visuals_root, "BossGarageDoorPost", Vector3(-4.5, 1.25, side * 2.45), Vector3(0.45, 2.5, 0.5), trim)
		add_mesh_box(visuals_root, "BossGarageApronStripe", Vector3(-3.8, 0.02, side * 2.1), Vector3(2.7, 0.025, 0.13), stripe)
	add_solid_box(visuals_root, "BossGarageLintel", Vector3(-4.5, 2.8, 0), Vector3(0.6, 0.6, 5.4), wall)

	# The shutter is shown raised but never receives a collider.
	add_mesh_box(visuals_root, "BossGarageRaisedShutter", Vector3(-4.5, 3.02, 0), Vector3(0.16, 0.26, 4.4), shutter)
	for rib in 11:
		add_mesh_box(visuals_root, "BossGarageShutterRib", Vector3(-4.4, 2.91 + rib * 0.018, -2.0 + rib * 0.4), Vector3(0.035, 0.025, 0.33), trim)
	add_mesh_box(visuals_root, "BossGarageThreshold", Vector3(-3.5, -0.02, 0), Vector3(3.3, 0.04, 4.5), UrbanMaterials.sidewalk_stone())
