extends "res://gameplay/PoliceModel.gd"
## Colega de Dante na blitz: o PoliceModel da patrulha com o corpo Meshy da patrulha que recebeu as mãos
## autoradas do Dante (tools/meshy_graft_dante_hands.py, cópias em assets/prologue/police/). O corpo
## original não tem perfil de mão: as palmas ficavam abertas para fora e nada fechava na lanterna, no
## rádio ou na pistola. Só a cena usa estas cópias; a patrulha do jogo continua com o corpo de sempre.
var body_path := "res://assets/prologue/police/patrol_m_hands.glb"

func _install_body() -> void:
	if is_instance_valid(body) or not is_inside_tree(): return
	var keep: Array = [muzzle_flash_3d]
	if is_instance_valid(weapon): keep.append(weapon)
	var look := _body_look()
	if ResourceLoader.exists(body_path): look.merge({"body_source": body_path, "body_tint": {}, "body_accessories": []}, true)
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, look, keep)
	body.hand_provider = _body_weapon_targets
	if is_instance_valid(weapon):
		body.hand_targets = _body_weapon_targets()
		body._pose(0.0)
