extends "res://world/places/NativePlace.gd"
var session
var customers: Array[CharacterBody3D] = []
var checkout_owner: CharacterBody3D
## Lado do cliente nos dois caixas (Rosa à esquerda, Caio à direita). Playtest de 30/10: "quando
## entra o mercado nada acontece" — só o caixa da esquerda vendia, num ponto de 1,5 m; quem ia
## ao Caio, ou passava pelo meio da loja, não via ação nenhuma.
const CHECKOUT_POINTS := [Vector3(-4.2,0,4.5), Vector3(4.2,0,4.5)]
const PAINTED := preload("res://world/places/supermarket/PaintedSupermarketFacade.gd")

static func definition_data() -> Dictionary:
	var exterior := Vector3(990.0/16,0,140.0/16)
	# Fachada pintada: o vão fica fora do meio; chegada e volta em frente a ele.
	var door := Vector3(PAINTED.door_x() if PAINTED.available() else 0.0,0,0)
	var reward := {"id":"boa_praca_first_aid","kind":"item","item":"first_aid","amount":1,"local_position":Vector3(-7,0,6.25)}
	return {"id":"harbor_supermarket","original_name":"Boa Praça","region":"harbor",
		"source_id":"supermarket","model":"res://world/places/supermarket/SupermarketInterior.gd",
		"exterior_position":exterior,"entry_position":exterior+door+Vector3(0,0,7),"return_position":exterior+door+Vector3(0,0,7.5),
		"spawn":Vector3(0,0,5.6),"exit":Vector3(0,0,6.5),"size":Vector2(18,14),
		"camera_target":Vector3(0,.65,0),"camera_size":18.5,"variant":0,"service":"supermarket",
		"reward":reward,"rewards":[reward],"npcs":[
			{"id":"boa_praca_cashier","name":"Rosa","model":"res://world/places/MountainShopResidentModel.gd","appearance":{"coat_color":Color("487658"),"is_female":true},"local_position":Vector3(-6.55,0,4.5)},
			{"id":"boa_praca_cashier_2","name":"Caio","model":"res://world/places/MountainShopResidentModel.gd","appearance":{"coat_color":Color("487658")},"local_position":Vector3(6.55,0,4.5)}],
		"npc_model":"","npc_point":Vector3.ZERO,"integration_status":"native"}

func _ready() -> void:
	super._ready()
	interaction_points.service = to_global(CHECKOUT_POINTS[0])
	interaction_points["service_2"] = to_global(CHECKOUT_POINTS[1])
	# The camera-side facade cuts away visually; its original full body remains solid.
	for mesh in model.get_children():
		if mesh is MeshInstance3D and str(mesh.get_meta("interior_solid_id","" )).begins_with("FrontWall"):
			mesh.mesh = mesh.mesh.duplicate()
			mesh.mesh.size.y = .06
			mesh.position.y = .03

func on_session_entered(owner_session) -> void:
	session = owner_session
	if not customers.is_empty(): return
	for i in 4:
		var customer = preload("res://world/places/supermarket/SupermarketCustomer.gd").new()
		customer.market = self
		customer.customer_index = i
		customer.position = Vector3(-6.35+i*3.2,.04,-3.4+i*.7)
		add_child(customer)
		customers.append(customer)

## Ponto de compra mais perto de `point` (global): o caixa a que o jogador chegou.
func service_point_for(point: Vector3) -> Vector3:
	var best: Vector3 = interaction_points.service
	if interaction_points.has("service_2") and point.distance_squared_to(interaction_points.service_2) < point.distance_squared_to(best):
		best = interaction_points.service_2
	return best

func threatened() -> bool:
	if session == null: return false
	if session.world.gameplay.health <= 0: return true
	for actor in session.room_npcs:
		if not is_instance_valid(actor) or actor.dead: return true
		if actor.get_meta("workplace_threatened",false): return true
	return session.world.gameplay.stars > 0

func set_active(value: bool) -> void:
	super.set_active(value)
	for customer in customers:
		if is_instance_valid(customer): customer.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
