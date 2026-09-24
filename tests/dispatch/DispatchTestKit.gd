extends RefCounted
## Cenário mínimo compartilhado pelos testes de despacho: piso sólido, malha de
## ruas, Dante, Gameplay real (com o EmergencyManager real) e o controlador.
## Não usa Maciota nem a garagem; as regras dessas áreas são conferidas pelos
## testes próprios (tests/test_garage_weapon_restrictions.gd) e aqui apenas o
## bloqueio de armas (`state.safe`) é exercitado.

const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
const CONTROLLER := preload("res://gameplay/dispatch/DispatchController.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")

class CombatState extends RefCounted:
	var equipped_weapon := "fists"
	var safe := false
	func owns_weapon(_id: String) -> bool: return false
	func get_ammo(_id: String) -> Dictionary: return {}
	func consume_ammo(_id: String, _amount: int) -> bool: return false
	func add_ammo(_id: String, _amount: int) -> bool: return false
	func reload_weapon(_id: String, _capacity: int = -1) -> bool: return false
	func equip_weapon(_id: String) -> bool: return not safe
	func can_attack() -> bool: return not safe
	func weapons_allowed() -> bool: return not safe

## Duas avenidas em cruz e um anel: há sempre rota alternativa.
static func grid_roads(extent: float = 90.0, ring: float = 60.0) -> Array:
	return [
		{"id": "avenue_x", "width": 8.0, "points": PackedVector3Array([Vector3(-extent, 0, 0), Vector3(extent, 0, 0)])},
		{"id": "avenue_z", "width": 8.0, "points": PackedVector3Array([Vector3(0, 0, -extent), Vector3(0, 0, extent)])},
		{"id": "ring", "width": 8.0, "points": PackedVector3Array([Vector3(-ring, 0, -ring), Vector3(ring, 0, -ring), Vector3(ring, 0, ring), Vector3(-ring, 0, ring), Vector3(-ring, 0, -ring)])},
	]

## Uma rua reta sem alternativa.
static func single_road(extent: float = 90.0) -> Array:
	return [{"id": "only", "width": 8.0, "points": PackedVector3Array([Vector3(-extent, 0, 0), Vector3(extent, 0, 0)])}]

static func build(tree: SceneTree, roads: Array, player_position: Vector3) -> Dictionary:
	var scene := Node3D.new()
	tree.root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 1, 500)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	var player := ACTOR.new()
	player.is_player = true
	player.controlled_automatically = true
	player.position = player_position
	scene.add_child(player)
	var state := CombatState.new()
	var gameplay := GAMEPLAY.new()
	gameplay.configure(scene, player, null, state)
	scene.add_child(gameplay)
	var routes := ROUTES.new()
	routes.configure(roads)
	var controller := CONTROLLER.new()
	controller.configure(scene, gameplay, routes)
	scene.add_child(controller)
	return {"scene": scene, "player": player, "gameplay": gameplay, "state": state, "routes": routes, "controller": controller}

static func add_wall(scene: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = center
	return wall

static func add_patient(scene: Node3D, point: Vector3, health: float = 15.0) -> CharacterBody3D:
	var patient := ACTOR.new()
	patient.position = point
	scene.add_child(patient)
	patient.health = health
	return patient

static func teardown(bundle: Dictionary) -> void:
	var scene: Node = bundle.scene
	if is_instance_valid(scene): scene.free()
