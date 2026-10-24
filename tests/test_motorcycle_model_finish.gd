extends SceneTree
## Shared packed models must not share mutable paint, lamp or damage state.
const VEHICLE=preload("res://scripts/Vehicle.gd")
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func snapshot(model: Node3D,nonlens_only:=false) -> Dictionary:
	var result:={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null: continue
		for surface in part.mesh.get_surface_count():
			var role:=ROLES.key(part,surface)
			if nonlens_only and (ROLES.is_headlight_lens(role) or ROLES.is_tail_lens(role) or role=="lens"): continue
			var mat:=part.get_active_material(surface) as StandardMaterial3D
			if mat==null: continue
			result[str(model.get_path_to(part))+"/"+str(surface)]={"color":mat.albedo_color,"roughness":mat.roughness,"emission":mat.emission_enabled,"energy":mat.emission_energy_multiplier,"detail":mat.detail_enabled,"visible":part.visible}
	return result
func run() -> void:
	var stage:=Node3D.new()
	root.add_child(stage)
	for id: String in ["bike_sport","bike_cruiser","bike_urban"]:
		var a:=VEHICLE.new(); a.archetype=id; a.paint_color=Color("b63b32"); a.process_mode=Node.PROCESS_MODE_DISABLED
		var b:=VEHICLE.new(); b.archetype=id; b.paint_color=Color("31577a"); b.process_mode=Node.PROCESS_MODE_DISABLED
		stage.add_child(a); stage.add_child(b)
		a.ensure_equipment(stage); b.ensure_equipment(stage)
		var untouched:=snapshot(b.visual)
		check(not a._paint.materials.is_empty() and not b._paint.materials.is_empty(),id+" exposes independently repaintable materials")
		a.paint_color=Color("d5a544")
		for mat: StandardMaterial3D in a._paint.materials: check(mat.albedo_color.is_equal_approx(Color("d5a544")),id+" body takes requested paint")
		check(snapshot(b.visual)==untouched,id+" repaint cannot affect second instance")
		var trim:=snapshot(a.visual,true)
		a.controlled=true
		check(a.equipment.toggle_headlights(),id+" headlight action accepted")
		a.brake_input=true; a.equipment._refresh()
		check(snapshot(a.visual,true)==trim,id+" headlight/brake actions preserve every nonlens surface")
		a.controlled=false; a.brake_input=false; a.equipment._refresh()
		var healthy:=snapshot(a.visual)
		a.receive_damage(a.max_health*.55/maxf(a.damage_resistance,.05))
		check(is_equal_approx(a.health,a.max_health*.45),id+" damage affects intended instance")
		check(snapshot(b.visual)==untouched,id+" damage cannot affect second instance")
		a.repair()
		check(snapshot(a.visual)==healthy,id+" repair restores painted finish")
		a.restore_health(0.0)
		check(a.damage_look.wrecked,id+" terminal damage enters wreck presentation")
		a.repair()
		check(not a.damage_look.wrecked and snapshot(a.visual)==healthy,id+" repair recovers all visible finishes after wreck")
		check(snapshot(b.visual)==untouched,id+" wreck/repair preserves second instance")
		a.free(); b.free()
		await process_frame
	stage.free()
	print("MOTORCYCLE_MODEL_FINISH checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
