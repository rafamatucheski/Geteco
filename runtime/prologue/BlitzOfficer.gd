extends "res://gameplay/PoliceModel.gd"
## Dante oito anos mais novo, de farda, na blitz do prólogo. É o PoliceModel da patrulha (mesma farda,
## quepe, pegada de pistola com as duas mãos, recuo e clarão) com o rosto dele: o corpo Meshy da
## patrulha traria outro rosto, então aqui o corpo é sempre o do kit, vestido como o policial.
const DANTE_FACE := {"variant": 9601, "skin": Color("d4a688"), "hair_color": Color("2a221d"), "beard": 0,
	"glasses": false, "female": false, "build": 1, "height": 1.02}

func _body_look() -> Dictionary:
	var look := super._body_look()
	look.merge(DANTE_FACE, true)
	return look

func _install_body() -> void:
	if is_instance_valid(body) or not is_inside_tree(): return
	var keep: Array = [muzzle_flash_3d]
	if is_instance_valid(weapon): keep.append(weapon)
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, _body_look(), keep)
	body.hand_provider = _body_weapon_targets
