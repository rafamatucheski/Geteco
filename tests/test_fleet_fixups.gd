extends SceneTree
## Correções de arte da frota (tools/fleet_fixups/apply_fleet_fixups.gd):
## - todo .scn passou pelas correções;
## - moto: garfo/para-lama/guidão esterçam mas não rolam com o pneu; piloto tem braços;
## - nenhuma lanterna traseira corrigida voltou a ficar descolada da lataria.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const GEOMETRY := preload("res://tools/fleet_fixups/FleetGeometry.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for id in FLEET.all():
		var model: Node3D = FLEET.create(id)
		check(int(model.get_meta("fleet_fixups", 0)) >= 1, id + ": .scn sem as correções da frota (rodar apply_fleet_fixups)")
		model.free()
	for id in ["bike_urban", "bike_sport", "bike_cruiser"]:
		var model: Node3D = FLEET.create(id)
		var geo = GEOMETRY.new(model)
		var added := 0
		for part in geo.parts():
			var center: Vector3 = geo.bounds(part).get_center()
			check(not (absf(center.x) < .01 and absf(center.z) < .05 and center.y < .55 and not part.has_meta("wheel_center") and GEOMETRY.color_of(part).to_html(false) in ["41454d", "253043"]), id + ": membro do piloto largado na origem")
			if part.has_meta("fleet_fixup"): added += 1
		check(added >= 20, id + ": piloto sem braços/pernas (%d peças)" % added)
		model.free()
	var bike = load("res://scripts/Vehicle.gd").new()
	bike.archetype = "bike_urban"
	root.add_child(bike)
	await process_frame
	check(not bike.steer_pivots.is_empty(), "moto sem pivô de esterço para o garfo")
	bike.steering = .3
	bike.speed = 8.0
	bike.traffic = false
	for i in 20: await physics_frame
	for pivot in bike.steer_pivots.values():
		check(is_zero_approx(pivot.rotation.x), "garfo/para-lama da moto rolando com o pneu (rotation.x=%.2f)" % pivot.rotation.x)
	var rolled := false
	for pivot in bike.wheels: rolled = rolled or absf(pivot.rotation.x) > .01
	check(rolled, "rodas da moto pararam de rolar")
	bike.queue_free()
	if failures.is_empty(): print("FLEET_FIXUPS OK")
	for failure in failures: print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
