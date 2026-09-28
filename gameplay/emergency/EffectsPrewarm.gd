extends RefCounted
## Compila os pipelines de GPU do fogo, da fumaça e da explosão antes da 1ª ocorrência.
##
## Medido em tests/measure/probe_first_emergency.gd (sessão fria): acender UM fogo no
## chão custa 0,2 ms na chamada, mas o 1º desenho do efeito trava 70-105 ms (shader de
## partícula/chama + luz); a explosão, 80-120 ms. Montar os nós antes
## (Fire.prewarm_visuals) não ajuda: o pipeline só compila quando algo é DESENHADO na
## janela principal (um SubViewport fora da tela foi testado e não aqueceu nada).
## Por isso os efeitos são desenhados uma vez diante da câmera, sob a cortina de carga.
const FIRE = preload("res://gameplay/emergency/Fire.gd")
const EFFECTS = preload("res://gameplay/CombatEffects.gd")

static func run(host: Node3D) -> void:
	if not is_instance_valid(host) or not host.is_inside_tree(): return
	if "--no-prewarm" in OS.get_cmdline_user_args(): return
	var camera := host.get_viewport().get_camera_3d()
	var point := Vector3(0, 0, -8)
	if camera != null: point = camera.global_position - camera.global_basis.z * 9.0
	var fire = FIRE.new()
	host.add_child(fire)
	fire.global_position = point
	var effects = EFFECTS.new()
	host.add_child(effects)
	effects.explosion(point, 6.0)
	# Três quadros: o 1º desenha, os seguintes cobrem emissores que só soltam partículas depois.
	for frame in 3: await host.get_tree().process_frame
	if is_instance_valid(effects):
		effects.shutdown()
		effects.free()
	if is_instance_valid(fire): fire.free()
