extends SceneTree
## Motorista visível ao volante em toda a frota conduzível, e de volta ao normal ao sair.
## Sem Main, sem tráfego, sem save pessoal: um palco, o Driving real, um Vehicle por
## arquétipo do catálogo e o Actor do jogador com o esqueleto de verdade.
## Mede: (1) o jogador fica visível ao terminar a entrada; (2) o corpo cabe na cabine (cabeça
## sob o teto nos fechados, quadril e cabeça dentro do casco); (3) as palmas tocam o aro do
## volante; (4) o corpo acompanha o veículo em movimento e inclinado; (5) ao sair não sobra
## visual deslocado, agachado, escalado, girado nem mãos fechadas; (6) o interior e o vidro
## translúcido existem só no veículo conduzido e a malha é a mesma entre instâncias.
## NÃO mede: aparência (ver tests/capture/capture_seated_driver.gd), animação de porta,
## nem custo de quadro.
const ACTOR := preload("res://scripts/Actor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DRIVING := preload("res://scripts/Driving.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")

class Fixture extends Node3D:
	var player
	var camera

class CameraStub extends Node:
	var locked := false
	var target: Node
	var initialized := false

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("SEATED FAIL ", label)

func run() -> void:
	var fixture := Fixture.new()
	root.add_child(fixture)
	fixture.camera = CameraStub.new()
	fixture.add_child(fixture.camera)
	fixture.player = ACTOR.new()
	fixture.player.is_player = true
	fixture.add_child(fixture.player)
	fixture.player.set_physics_process(false)
	var driving := DRIVING.new()
	driving.world = fixture
	var ids: Array = FLEET.all().keys()
	ids.sort()
	var seated_count := 0
	var shared_mesh := {}
	var triangle_min := 1000000
	var triangle_max := 0
	for id in ids:
		var car = VEHICLE.new()
		car.archetype = id
		fixture.add_child(car)
		car.set_physics_process(false)
		await process_frame
		var label := str(id)
		if id.begins_with("bike_") or id == "army_tank":
			check(not car.shows_seated_driver(), label + " mantém piloto próprio (moto/blindado)")
			car.queue_free()
			continue
		seated_count += 1
		check(not car.visual.has_node("Interior"), label + " sem interior antes de ser conduzido")
		# Estado inicial de quem chega andando até o carro.
		fixture.player.teleport(car.driver_door_anchor(-1))
		fixture.player.hide()
		fixture.player.input_locked = true
		driving.car = car
		driving.occupied = true
		var body_before := _body_snapshot(car)
		INTERIOR.attach(car)
		driving._complete_entry()
		INTERIOR.follow(fixture.player, car, 1.0) # termina a mistura (sem árvore, o delta do Driving é 0)
		check(fixture.player.visible, label + " jogador visível ao volante")
		check(fixture.player.seated, label + " jogador sentado")
		check(car.visual.has_node("Interior"), label + " interior montado")
		check(not fixture.player.input_locked, label + " entrada libera a pose")
		var s: Dictionary = INTERIOR.spec(car)
		check(not s.is_empty() and float(s.roof) > float(s.belt), label + " cabine medida (cintura abaixo do teto)")
		_check_fit(fixture.player, car, s, label)
		_check_hands(fixture.player, car, s, label)
		# Carro em movimento, guinado e inclinado (rampa): o corpo continua preso à base.
		car.global_transform = Transform3D(Basis(Vector3.UP, 1.3) * Basis(Vector3.RIGHT, -.12) * Basis(Vector3.BACK, .06), Vector3(14, .6, -9))
		for i in 30: driving._physics_process(1.0 / 60.0)
		var expected: Transform3D = car.global_transform * Transform3D(Basis.IDENTITY, fixture.player.get_meta("seated_state").origin)
		check(fixture.player.visual.global_position.distance_to(expected.origin) < .01, label + " visual acompanha o banco do veículo (posição)")
		check(fixture.player.global_position.distance_to(car.global_position) < .001, label + " o nó do jogador segue na posição do veículo (world.player.position == car.position)")
		check(fixture.player.global_basis.orthonormalized().is_equal_approx(car.global_basis.orthonormalized()), label + " corpo acompanha o veículo (inclinação)")
		check(fixture.player.visible, label + " segue visível dirigindo")
		# Malha e vidro: mesma malha entre instâncias, vidro translúcido só neste veículo.
		var mesh: Mesh = (car.visual.get_node("Interior") as MeshInstance3D).mesh
		if shared_mesh.has(car.archetype): check(shared_mesh[car.archetype] == mesh, label + " malha do interior em cache")
		shared_mesh[car.archetype] = mesh
		var triangles := mesh.get_faces().size() / 3
		triangle_min = mini(triangle_min, triangles)
		triangle_max = maxi(triangle_max, triangles)
		check(mesh.get_surface_count() <= 2 and triangles > 100 and triangles < 6000, label + " interior é uma malha só (opaca + forro translúcido) com detalhe e orçamento (%d triângulos)" % triangles)
		check(car.visual.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.name == "Interior").size() == 1, label + " um único nó de interior")
		_check_glass(car, label)
		_check_roof(car, body_before, label)
		# Sair: o corpo volta ao mundo sem resíduo.
		var before_hips: Vector3 = fixture.player.skeleton.get_bone_pose_position(fixture.player.hips)
		driving.occupied = false
		driving._complete_exit(car.global_position + car.global_basis.x * -2.4)
		check(fixture.player.visible and not fixture.player.seated, label + " saída devolve o corpo")
		check(fixture.player.global_basis.is_equal_approx(Basis.IDENTITY), label + " saída endireita o corpo")
		check(fixture.player.visual.position.is_zero_approx() and fixture.player.visual.rotation.is_zero_approx(), label + " saída não deixa o visual deslocado ou girado")
		check(fixture.player.visual.scale.is_equal_approx(Vector3.ONE), label + " saída não deixa o visual escalado")
		check(fixture.player.get_meta("seated_state", {}).is_empty(), label + " estado de sentado limpo")
		fixture.player._pose_locomotion(Vector3.ZERO, 0.0, Vector3.ZERO, 0.0, 1.0 / 60.0)
		var hips_after: Vector3 = fixture.player.skeleton.get_bone_pose_position(fixture.player.hips)
		check(hips_after.distance_to(fixture.player._idle_pose[fixture.player.hips][0]) < .02 and absf(hips_after.y - before_hips.y) < 2.0, label + " de pé, quadril no repouso (sem agachar)")
		var skin: MeshInstance3D = fixture.player._combat_skin
		check(skin.get_blend_shape_value(0) < .01 and skin.get_blend_shape_value(1) < .01, label + " mãos abertas depois de sair")
		car.queue_free()
		await process_frame
	# Trânsito não paga nada: veículo que ninguém conduziu segue com vidro opaco e sem interior.
	var traffic = VEHICLE.new()
	traffic.archetype = "union_sedan"
	fixture.add_child(traffic)
	traffic.set_physics_process(false)
	await process_frame
	check(not traffic.visual.has_node("Interior"), "trânsito sem interior")
	check(_translucent_glass_count(traffic) == 0, "trânsito com vidro opaco")
	check(seated_count >= 40, "cobre a frota inteira conduzível (%d)" % seated_count)
	print("SEATED_DRIVER checks=", checks, " vehicles=", seated_count, " triangulos_interior=", triangle_min, "..", triangle_max, " failures=", failures.size())
	if failures.is_empty():
		print("PASS test_seated_driver")
	else:
		print("FAIL test_seated_driver: ", failures.size())
	quit(0 if failures.is_empty() else 1)

func _head_top(player) -> Vector3:
	return player.skeleton.to_global(player.skeleton.get_bone_global_pose(player._combat_bones["head_end"]).origin)

## Cabeça sob o teto nos fechados e o corpo todo dentro do casco do veículo.
func _check_fit(player, car, s: Dictionary, label: String) -> void:
	var head: Vector3 = car.to_local(_head_top(player))
	var pelvis: Vector3 = car.to_local(INTERIOR.pelvis_world(player))
	if not bool(s.open_top):
		check(head.y < float(s.roof) - .01, label + " cabeça sob o teto (%.2f < %.2f)" % [head.y, float(s.roof)])
	check(absf(head.x) < float(car.half_width) and head.z > -float(car.half_length) and head.z < float(car.half_length), label + " cabeça dentro do casco")
	check(absf(pelvis.x) < float(car.half_width) - .1 and pelvis.y > .1 and pelvis.y < float(car.body_height), label + " quadril dentro do casco")
	# Cabeça atrás da base do para-brisa: não atravessa o capô nem o painel.
	check(head.z > float(s.wz0) + .1, label + " cabeça atrás do para-brisa")
	# Pés no piso da cabine (não flutuando nem enterrados).
	for side in ["Left", "Right"]:
		var foot: Vector3 = car.to_local(player.skeleton.to_global(player.skeleton.get_bone_global_pose(player._combat_bones[side + "Foot"]).origin))
		check(foot.y > float(s.floor) - .04 and foot.y < float(s.floor) + .30, label + " pé " + side + " no piso (%.2f)" % (foot.y - float(s.floor)))

## Palmas no aro do volante (raio do volante ± tolerância, no plano do aro).
func _check_hands(player, car, s: Dictionary, label: String) -> void:
	if str(s.kind) == "forklift":
		var palm: Vector3 = car.to_local(player.combat_palm_position("Right"))
		var hub := Vector3(float(s.sx), float(s.hub_y), float(s.hub_z))
		check(palm.distance_to(hub) < float(s.r) + .09, label + " mão direita no volante")
		return
	var hub := Vector3(float(s.sx), float(s.hub_y), float(s.hub_z))
	for side in ["Left", "Right"]:
		var palm: Vector3 = car.to_local(player.combat_palm_position(side))
		var gap: float = absf(palm.distance_to(hub) - float(s.r))
		check(gap < .07, label + " palma " + side + " no aro do volante (folga %.3f)" % gap)

func _translucent_glass_count(car) -> int:
	var count := 0
	for part in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.name == "Interior" or part.mesh == null: continue
		if part.material_override is StandardMaterial3D and part.material_override.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: count += 1
		for surface in part.mesh.get_surface_count():
			var override = part.get_surface_override_material(surface)
			if override is StandardMaterial3D and override.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: count += 1
	return count

## Entrar preserva a geometria e a opacidade da carroceria; só o vidro pode mudar.
func _body_snapshot(car) -> Array:
	var state: Array = []
	for part in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.name in ["Interior", "WarmUp"]: continue
		var materials: Array = []
		for surface in part.mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			if material is StandardMaterial3D and not INTERIOR._is_glass(part, surface, material):
				materials.append([surface, material, material.transparency, material.albedo_texture, material.albedo_color.a])
		state.append([part, part.mesh, materials])
	return state

func _check_body_unchanged(car, before: Array, label: String) -> void:
	var unchanged := true
	for entry in before:
		var part: MeshInstance3D = entry[0]
		unchanged = unchanged and part.mesh == entry[1]
		for saved in entry[2]:
			var material: StandardMaterial3D = part.get_active_material(saved[0])
			unchanged = unchanged and material == saved[1] and material.transparency == saved[2] and material.albedo_texture == saved[3] and is_equal_approx(material.albedo_color.a, saved[4])
	check(unchanged, label + " carroceria conserva malha, material e opacidade")

func _check_roof(car, before: Array, label: String) -> void:
	var view: Dictionary = car.get_meta("interior_view", {})
	check(not view.is_empty(), label + " vista dos vidros registrada")
	_check_body_unchanged(car, before, label + " ao entrar")
	INTERIOR.set_low_camera_roof(car, true)
	INTERIOR.set_low_camera_roof(car, false)
	_check_body_unchanged(car, before, label + " ao mudar câmera")
	if car._paint != null:
		car._paint.apply(Color("b72934"))
		_check_body_unchanged(car, before, label + " ao repintar")
	var cut_meshes: Array = []
	for entry in view.get("parts", []): cut_meshes.append(entry[1])
	INTERIOR.close_view(car)
	check(not car.has_meta("interior_view"), label + " close_view limpa a vista")
	for entry in cut_meshes:
		check(entry != null, label + " malha original guardada para restaurar")
	var leftover: Array = car.visual.find_children("RoofCut", "MeshInstance3D", true, false).filter(func(n): return not n.is_queued_for_deletion())
	check(leftover.is_empty(), label + " close_view remove o teto recortado")
	# Reabre para o restante do teste (saída, vidro).
	INTERIOR.attach(car)
	_check_body_unchanged(car, before, label + " ao reentrar")

func _check_glass(car, label: String) -> void:
	# Toda cabine fechada com vidro medido tem que ter vidro translúcido; buggy e empilhadeira não têm.
	var spec: Dictionary = INTERIOR.spec(car)
	if not bool(spec.open_top): check(_translucent_glass_count(car) > 0, label + " vidro translúcido no veículo conduzido")
