extends SceneTree
## Contratos de alcance exterior e restauração da câmera. Não mede FPS nem aprova sombras/reflexos.
const DEPTH := preload("res://scripts/camera/ExteriorDepthRange.gd")
const CAMERA := preload("res://scripts/CameraRig.gd")
const REFLECTION := preload("res://world/city_look/CoastalPlanarReflections.gd")

class Region extends Node3D:
	var region_id := "harbor"

class Production extends Node:
	var region: Node3D
	var sun: DirectionalLight3D

class FixtureWorld extends Node3D:
	var production: Node
	var gameplay: Node
	var hud: Control

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func shadow_values(sun: DirectionalLight3D) -> Vector4:
	return Vector4(sun.directional_shadow_split_1, sun.directional_shadow_split_2,
		sun.directional_shadow_split_3, sun.directional_shadow_fade_start)

func pose_camera(camera: Camera3D, focus: Vector3, offset: Vector3, extra := 0.0) -> void:
	camera.global_position = focus + offset.normalized() * (offset.length() + extra)
	camera.look_at(focus)

func run() -> void:
	var stage := FixtureWorld.new()
	root.add_child(stage)
	stage.production = Production.new()
	stage.add_child(stage.production)
	stage.production.region = Region.new()
	stage.add_child(stage.production.region)
	stage.production.sun = DirectionalLight3D.new()
	var sun: DirectionalLight3D = stage.production.sun
	sun.directional_shadow_split_1 = .16
	sun.directional_shadow_split_2 = .22
	sun.directional_shadow_split_3 = .32
	sun.directional_shadow_fade_start = .4
	stage.add_child(sun)
	var original := shadow_values(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .1
	camera.far = 180.0
	camera.size = 21.0
	var focus := Vector3(40, 0, 140)
	pose_camera(camera, focus, CAMERA.EXTERIOR_OFFSET)
	var range = DEPTH.new()
	for invalid in ["", "0", "-10", "inválido", "nan", "inf", "1e999"]:
		range.configure_request(invalid)
		check(not range.enabled(), "valor inválido/desligado preserva o legado: " + invalid)
		check(is_equal_approx(range.apply(camera, focus, 0.0, sun), 180.0), "modo desligado mantém 180 m")
		check(shadow_values(sun).is_equal_approx(original), "modo desligado não toca nas cascatas")
	range.configure_request("120")
	var shortened: float = range.apply(camera, focus, 0.0, sun)
	check(is_equal_approx(shortened, 120.0) and range.active, "candidato de 120 m é aplicado no exterior")
	check(is_equal_approx(camera.near + sun.directional_shadow_split_1 * (shortened - camera.near),
		camera.near + original.x * (180.0 - camera.near)), "primeira fronteira de sombra conserva a profundidade")
	check(is_equal_approx(sun.directional_shadow_fade_start * shortened, original.w * 180.0), "fade não começa em cima do jogador")
	var once := shadow_values(sun)
	for index in 5: range.apply(camera, focus, 0.0, sun)
	check(shadow_values(sun).is_equal_approx(once), "compensação repetida não se multiplica")
	range.release()
	check(shadow_values(sun).is_equal_approx(original), "liberação restaura exatamente os valores autorados")

	# O requisito é manter os quatro cantos do chão no frustum, incluindo roll e alvo elevado.
	for offset in [CAMERA.EXTERIOR_OFFSET, CAMERA.PREVIEW_OFFSET, CAMERA.DRIVE_OFFSET]:
		for height in [0.0, 20.0]:
			for span in [14.0, 52.0]:
				for extra in [0.0, 70.0, 120.0]:
					for roll in [0.0, .016]:
						camera.size = span
						var point := Vector3(40, height, 140)
						pose_camera(camera, point, offset, extra)
						camera.rotate_object_local(Vector3.FORWARD, roll)
						var half_extents := camera.get_camera_projection().get_viewport_half_extents()
						var floor_far := DEPTH.minimum_far(camera.global_transform, half_extents * 2.0)
						var limit := DEPTH.choose_far(90.0, extra, floor_far)
						check(limit <= 180.0 + extra, "experimento não amplia o frustum legado")
						check(limit >= 90.0 + extra, "recuo ferroviário/prédio é compensado uma vez")
						for x in [-1.0, 1.0]:
							for y in [-1.0, 1.0]:
								var ray_origin: Vector3 = camera.global_position + camera.global_basis.x * half_extents.x * x + camera.global_basis.y * half_extents.y * y
								var ray_direction: Vector3 = -camera.global_basis.z
								var ground_depth: float = (DEPTH.HARBOR_MIN_Y - ray_origin.y) / ray_direction.y
								check(ground_depth + DEPTH.DEPTH_MARGIN <= limit + .001, "canto do chão preservado com zoom/recuo/roll")
	check(is_equal_approx(DEPTH.choose_far(120.0, 70.0, 170.0), 190.0), "piso calculado na câmera final não recebe recuo duplicado")
	check(is_equal_approx(DEPTH.choose_far(120.0, 0.0, INF), 180.0), "pose sem piso confiável volta ao legado")
	check(is_equal_approx(DEPTH.choose_far(120.0, 0.0, 200.0), 180.0), "piso além do legado recusa redução")

	camera.size = 21.0
	pose_camera(camera, focus, CAMERA.EXTERIOR_OFFSET)
	range.configure_request("settings")
	var previous := 0.0
	for distance in [40.0, 55.0, 80.0]:
		range.set_shadow_distance(distance)
		var limit: float = range.apply(camera, focus, 0.0, sun)
		check(limit > previous, "preferência de distância tem efeito no exterior: " + str(distance))
		check(limit >= range.floor_far, "preferência nunca corta o piso protegido")
		previous = limit
	range.release()
	camera.free()

	# Integração no CameraRig real: o experimento só pode possuir a câmera exterior ativa do Harbor.
	var rig = CAMERA.new()
	stage.add_child(rig)
	rig.set_process(false)
	rig._exterior_depth.configure_request("120")
	rig.size = 21.0
	rig.focus = focus
	pose_camera(rig, focus, CAMERA.EXTERIOR_OFFSET)
	rig.make_current()
	rig._update_exterior_depth_range(0.0)
	check(is_equal_approx(rig.far, 120.0), "CameraRig liga candidato no Harbor")
	check(is_equal_approx(rig.reflection_far(), 180.0), "reflexo conserva o alcance legado")
	var view := SubViewport.new()
	view.size = Vector2i(640, 360)
	stage.add_child(view)
	var reflected := Camera3D.new()
	view.add_child(reflected)
	REFLECTION.mirror_camera(rig, reflected, Vector3.UP, Vector3(0, .035, 0))
	check(is_equal_approx(reflected.far, 180.0), "chão molhado não herda o recorte de 120 m")
	REFLECTION.mirror_camera(rig, reflected, Vector3.BACK, Vector3.ZERO)
	check(is_equal_approx(reflected.far, 180.0), "fachada espelhada não herda o recorte de 120 m")
	rig.locked = true
	check(shadow_values(sun).is_equal_approx(original) and is_equal_approx(rig.far, 180.0), "entrada travada libera luz e alcance exterior")
	rig.far = 80.0
	rig._update_exterior_depth_range(0.0)
	check(is_equal_approx(rig.far, 80.0), "interior mantém seu far autorado")
	rig.locked = false
	rig._update_exterior_depth_range(0.0)
	rig.projection = Camera3D.PROJECTION_PERSPECTIVE
	rig.far = 75.0
	rig._tunnel_chase_blend = .5
	rig._update_exterior_depth_range(0.0)
	check(is_equal_approx(rig.far, 75.0) and shadow_values(sun).is_equal_approx(original), "transição do túnel mantém far e cascatas legadas")
	rig.projection = Camera3D.PROJECTION_ORTHOGONAL
	rig._tunnel_chase_blend = 0.0
	rig._update_exterior_depth_range(0.0)
	check(is_equal_approx(rig.far, 120.0), "saída do túnel retoma o candidato")
	stage.production.region.region_id = "mountain"
	rig._update_exterior_depth_range(0.0)
	check(is_equal_approx(rig.far, 180.0) and shadow_values(sun).is_equal_approx(original), "serra não recebe piso do Harbor")
	stage.production.region.region_id = "harbor"
	rig._update_exterior_depth_range(0.0)
	rig.set_developer_zoom(25.0, 1)
	check(not rig._exterior_depth.active and shadow_values(sun).is_equal_approx(original), "zoom de desenvolvedor libera a afinação")
	check(is_equal_approx(float(rig._developer_camera_state.far), 180.0), "zoom salva o alcance legado para a restauração")
	rig.reset_developer_zoom()
	rig._update_exterior_depth_range(0.0)
	rig.focus_on_store(focus, 9.0, .5)
	check(not rig._exterior_depth.active and is_equal_approx(rig.far, 180.0), "transição de acesso conserva alcance legado")
	rig.clear_store_focus()
	rig._update_exterior_depth_range(0.0)
	rig.free()
	check(shadow_values(sun).is_equal_approx(original), "desmontagem da câmera não deixa sol retunado")
	stage.free()
	print("EXTERIOR_DEPTH_RANGE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
