extends SceneTree
## Os recursos offline mantêm a carroceria/lanternas/rodas autorais enquanto fornecem painéis
## removíveis com fundos acabados e um compartimento mecânico exposto.
const PANELS := preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd")
const PAINT := preload("res://runtime/VehiclePaint.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)

func run() -> void:
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/fleet/breakaway/manifest.json"))
	check(manifest is Dictionary,"prepared manifest exists")
	if not manifest is Dictionary: quit(1); return
	for id: String in PANELS.IDS:
		var model:=PANELS.create(id)
		var sibling:=PANELS.create(id)
		check(model!=null and sibling!=null,id+" prepared scene loads")
		if model==null or sibling==null: continue
		var panels: Dictionary={}
		var wheels:=0
		var lamps:=0
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if part.has_meta("wheel_center"): wheels+=1
			if part.has_meta("breakaway_part_id"):
				var panel_id:=str(part.get_meta("breakaway_part_id"))
				check(not panels.has(panel_id),id+" unique "+panel_id)
				panels[panel_id]=part
				check(part.mesh!=null and part.mesh.get_surface_count()>1,id+" panel has outer skin and inner face "+panel_id)
				var box: AABB=part.get_meta("breakaway_bounds",AABB())
				check(box.size.length()>0.3 and box.size.is_finite(),id+" finite meaningful panel bounds "+panel_id)
				if id=="sport_coupe" and panel_id=="hood": check(box.end.y<.9,id+" raised headlamp nacelles stay on the body")
				check(part.get_meta("breakaway_pivot",Vector3.INF).is_finite(),id+" finite pivot "+panel_id)
				check(part.transform==Transform3D.IDENTITY,id+" panel uses model-local geometry "+panel_id)
				var equivalent:=sibling.get_node(NodePath(str(part.name))) as MeshInstance3D
				check(equivalent!=null and equivalent.mesh==part.mesh,id+" pristine panel geometry remains shared "+panel_id)
			for surface in part.mesh.get_surface_count():
				var role:=ROLES.key(part,surface)
				if ROLES.is_headlight_lens(role) or ROLES.is_tail_lens(role):
					lamps+=1
					check(not part.has_meta("breakaway_part_id"),id+" functional lamps remain on body")
		check(panels.size()==3 and panels.has("hood") and panels.has("bumper_front") and panels.has("bumper_rear"),id+" all three panels authored")
		check(wheels>=4,id+" wheels retain their metadata")
		check(lamps>=2,id+" headlight/tail surface semantics preserved")
		check(model.has_node("BreakawayHardware"),id+" engine bay and bumper beams share one prepared draw")
		check(float(manifest.models[id].exterior_area_error)<.001,id+" exterior surface partition conserves area")
		var paint:=PAINT.new()
		paint.bind(model,id)
		paint.apply(Color.RED)
		var other_paint:=PAINT.new()
		other_paint.bind(sibling,id)
		other_paint.apply(Color.BLUE)
		check(not paint.materials.is_empty() and not other_paint.materials.is_empty(),id+" per-instance paints found")
		for material: StandardMaterial3D in paint.materials:
			if material not in paint.roof_materials: check(material.albedo_color==Color.RED,id+" sibling paint does not bleed")
		for part: MeshInstance3D in panels.values():
			var exterior_surfaces:=0
			var sibling_panel:=sibling.get_node(NodePath(str(part.name))) as MeshInstance3D
			for surface in part.mesh.get_surface_count():
				if ROLES.key(part,surface)=="paint":
					check((part.get_active_material(surface) as StandardMaterial3D).albedo_color==Color.RED,id+" panel shares vehicle paint")
				elif ROLES.key(part,surface)!="roof_paint":
					check(part.get_active_material(surface)==sibling_panel.get_active_material(surface),id+" unpainted trim retains authored material")
				if ROLES.key(part,surface)!="damage_hardware": exterior_surfaces+=1
				if ROLES.key(part,surface)=="damage_hardware": check((part.get_active_material(surface) as StandardMaterial3D).albedo_color==Color.WHITE,id+" inner metal stays neutral")
			check(exterior_surfaces>0,id+" removable panel retains authored exterior")
		model.free(); sibling.free()
	print("VEHICLE_PANEL_GEOMETRY failures=",failures.size()," models=",PANELS.IDS.size())
	quit(0 if failures.is_empty() else 1)
