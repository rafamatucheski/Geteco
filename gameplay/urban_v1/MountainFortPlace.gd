extends "res://world/places/NativePlace.gd"
## Forte militar sob a serra. Reaproveita a transição de lugar, a admissão física e o
## save. A região é "harbor" porque a entrada é o cofre do túnel secreto, em Harbor;
## a etapa seguinte liga a saída da serra (docs/fort-operation-plan.md).

var operation
## Quem entra pela laje do esqui define o retorno na serra antes de pedir a entrada.
static var next_return := Vector3.INF

static func definition_data() -> Dictionary:
	return {"id":"mountain_fort","original_name":"Forte da Serra","region":"harbor",
		"source_id":"mountain_fort","model":"res://gameplay/urban_v1/MountainFort.gd",
		"exterior_position":Vector3(-364,0,-120),"entry_position":Vector3(-364,0,-120),"return_position":next_return if next_return.is_finite() else Vector3(-364,0,-118),
		"spawn":Vector3(0,0,5.2),"exit":Vector3(0,0,6.1),"size":Vector2(20,14),
		"camera_target":Vector3(0,.7,-.4),"camera_size":17.0,"variant":0,"service":"secret",
		"reward":{},"rewards":[
			{"id":"mountain_fort_stash_cash","kind":"cash","amount":9000,"local_position":Vector3(7.3,0,-22.2)},
			{"id":"mountain_fort_stash_m4a1","kind":"weapon","item":"m4a1","amount":1,"ammo":150,"local_position":Vector3(8.1,0,-22.2)},
		],"npcs":[],"npc_model":"","npc_point":Vector3.ZERO,
		"hidden_access":true,"any_region":true,"silent_access":false,"integration_status":"native"}

func _ready() -> void:
	name = definition.id
	model = load(definition.model).new()
	add_child(model)
	for body in model.solids:
		solid_bodies.append(body)
		solid_bounds.append(body.get_meta("bounds"))
	solid_bodies.append(model.floor_body)
	model.set_cutaway(true)
	interaction_points["service"] = spawn_position
	_install_reward()

## O FullSession chama isto ao concluir a entrada: a operação precisa do jogador, do
## gameplay e da câmera da sessão.
func on_session_entered(owner_session) -> void:
	if is_instance_valid(operation): return
	operation = preload("res://gameplay/urban_v1/fort/FortOperation.gd").new()
	add_child(operation)
	operation.configure(self,owner_session)

func set_active(value: bool) -> void:
	super.set_active(value)
	if is_instance_valid(model): model.set_active(value)
