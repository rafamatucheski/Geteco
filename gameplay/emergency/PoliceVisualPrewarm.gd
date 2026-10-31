extends RefCounted
## Renderiza a apresentação representativa da polícia sob a cobertura de carregamento existente.
## Nenhum PoliceAgent, despacho, corpo de colisão, áudio ou grupo de jogo é criado.
const MODEL = preload("res://gameplay/PoliceModel.gd")
const SILHOUETTE = preload("res://gameplay/PoliceOcclusionSilhouette.gd")
const GUARDS = preload("res://gameplay/emergency/EffectsPrewarm.gd")
const WEAPONS := ["pistol", "smg", "m4a1", "m4a1", "m4a1"]
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _drawn := false
# Os recursos de corpo/equipamento e de arma já têm caches compartilhados limitados. Mantém
# um material de clarão idêntico vivo para que o shader StandardMaterial dele sobreviva.
static var _flash_material: Material

class ExteriorContext extends RefCounted:
	var state := {"place_id": ""}

class VisualHolder extends Node3D:
	var dead := false
	var controller: RefCounted

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var tree := host.get_tree()
	var visual := Node3D.new()
	visual.name = "PoliceVisualPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	host.add_child(visual)
	var models: Array = []
	var context := ExteriorContext.new()
	for tier in WEAPONS.size():
		var owner := VisualHolder.new()
		owner.controller = context
		visual.add_child(owner)
		var model = MODEL.new()
		model.tier = tier
		# Não consome PoliceAppearance.next_model nem cria todas as aparências.
		model.appearance_index = tier
		owner.add_child(model)
		models.append(model)
	_position(visual, camera)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	var equipped := false
	var presentation_ready := false
	for frame in MAX_WAIT_FRAMES:
		await tree.process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if not is_instance_valid(visual) or visual.is_queued_for_deletion(): break
		_position(visual, camera)
		if not equipped:
			var bodies_ready := true
			for model in models:
				if not is_instance_valid(model.body): bodies_ready = false
			if not bodies_ready: continue
			for tier in models.size():
				models[tier].equip(WEAPONS[tier])
				models[tier].muzzle_flash_3d.show()
				models[tier].get_parent().add_child(SILHOUETTE.new())
			equipped = true
			draws[0] = 0
			continue
		if not presentation_ready:
			var overlays_ready := true
			for model in models:
				if model.body.spine.material_overlay == null or model.muzzle_flash_3d.material_overlay == null: overlays_ready = false
			if not overlays_ready: continue
			presentation_ready = true
			draws[0] = 0
			continue
		if draws[0] >= DRAW_FRAMES:
			_flash_material = models[0].muzzle_flash_3d.material_override
			_drawn = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	# Remove antes que ProductionWorld possa revelar a cena; nenhum quadro visível na fila.
	if is_instance_valid(visual): visual.free()

static func _position(visual: Node3D, camera: Camera3D) -> void:
	visual.global_transform = Transform3D(Basis.IDENTITY, camera.global_position-camera.global_basis.z*9.0)
	var index := 0
	for child in visual.get_children():
		child.position = camera.global_basis.x * (float(index)-2.0) * 2.2 - Vector3.UP
		index += 1
