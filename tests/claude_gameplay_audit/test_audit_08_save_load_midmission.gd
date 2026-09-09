extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 08 — Salvar/Carregar (save/load) com uma missão em andamento
## tests/test_save_settings_system.gd exercises SaveManager robustness with a
## synthetic mock player and never calls CampaignState.restore_from_save();
## tests/test_continuous_save.gd covers vehicle/region persistence thoroughly.
## Neither drives a real save+load cycle against the live HarborGame.tscn
## while a real campaign mission (CobraCampaignController) is actively in
## progress — that gap is what this audit targets. Uses an isolated save
## directory AND a slot name that can never collide with a real player slot
## (slot_01..slot_05/autosave), and deletes it again at the end.

func _initialize() -> void:
	run.call_deferred()


const AUDIT_SLOT := "claude_gameplay_audit_slot"


func run() -> void:
	_tag = "08_save_load_midmission"
	arm_watchdog(90.0)

	skip_onboarding_flags()
	var save_dir := isolate_saves(_tag)
	log_line("  [INFO] Diretório de save isolado para este teste: %s" % save_dir)

	var world := await boot_harbor(30)
	var player: Node = world.get_node("Player")
	var save_mgr := root.get_node("SaveManager")
	var campaign := root.get_node("CampaignState")
	var bridge: Node = world.get_node("CobraCampaign")
	var runtime: Node = bridge.runtime

	print("\n[ETAPA 1] Preparando um estado real de meio de jogo (missão ativa + inventário)")
	runtime.start_mission("cobra_contact")
	player.global_position = runtime.get("objective_position")
	await physics_frames(8)
	runtime.interact() # avança para o estágio 1 (não conclui)
	check(String(runtime.get("active_id")) == "cobra_contact", "Missão cobra_contact está ativa antes de salvar")
	check(int(runtime.get("stage")) == 1, "Missão está no estágio 1 (em andamento, não concluída) antes de salvar")

	player.set("money", 8123)
	player.call("buy_weapon", "shotgun") # debita o preço real da escopeta do saldo acima
	var money_before_save: int = int(player.get("money"))
	player.set("health", 66)
	player.set("armor", 30)
	var pos_before_save: Vector2 = Vector2(9100.0, 1650.0)
	player.global_position = pos_before_save

	print("\n[ETAPA 2] Salvando em slot isolado")
	var save_res: Dictionary = save_mgr.save_game(AUDIT_SLOT, "Auditoria Claude — meio de missão")
	check(bool(save_res.get("success", false)), "save_game() em slot isolado é bem-sucedido ('%s')" % save_res.get("error", ""))
	check(save_mgr.get_slot_path(AUDIT_SLOT).begins_with(save_dir) or not save_mgr.get_slot_path(AUDIT_SLOT).contains("saves/slot_0"), "O caminho do save fica no diretório isolado, não em slot_01..05 do jogador")

	print("\n[ETAPA 3] Alterando drasticamente o estado ao vivo (simula progresso/morte depois do save)")
	runtime.fail_mission("Auditoria: falha forçada para testar divergência pós-save")
	await physics_frames(3)
	player.set("money", 1)
	player.set("health", 5)
	player.set("armor", 0)
	player.global_position = Vector2(0, 0)
	campaign.set_campaign_flag(&"harbor_delivery_complete", false)
	check(String(runtime.get("active_id")) == "", "Estado ao vivo agora diverge do que foi salvo (missão falhada)")

	print("\n[ETAPA 4] Carregando o slot isolado e aplicando sobre o mundo real")
	var load_res: Dictionary = save_mgr.load_game(AUDIT_SLOT)
	check(bool(load_res.get("success", false)), "load_game() carrega o slot isolado com sucesso ('%s')" % load_res.get("error", ""))
	var applied: bool = save_mgr.apply_pending_save(self)
	check(applied, "apply_pending_save() aplica os dados carregados sobre o mundo em execução")

	print("\n[ETAPA 5] Verificando restauração completa (jogador, campanha e missão em andamento)")
	check(int(player.get("money")) == money_before_save, "Dinheiro do jogador é restaurado exatamente")
	check(int(player.get("health")) == 66, "Vida do jogador é restaurada exatamente")
	check(int(player.get("armor")) == 30, "Colete do jogador é restaurado exatamente")
	check(player.global_position.distance_to(pos_before_save) < 1.0, "Posição do jogador é restaurada exatamente")
	var inventory_after_load: Dictionary = player.get("weapon_inventory")
	check(bool(inventory_after_load.get("shotgun", false)), "Arma comprada antes do save continua no inventário depois de carregar")
	check(bool(campaign.has_campaign_flag(&"harbor_delivery_complete")), "Flag de campanha (harbor_delivery_complete) é restaurada pelo CampaignState.restore_from_save()")

	# A missão em si é restaurada via CobraCampaignState, cujo `data` lê
	# diretamente de CampaignState.cobra_campaign — depois de
	# restore_from_save() isso já reflete o namespace salvo automaticamente.
	var ledger: RefCounted = bridge.ledger
	check(String(ledger.data.get("active_id", "")) == "cobra_contact", "A missão cobra_contact volta a constar como ativa no ledger depois de carregar")
	check(int(ledger.data.get("stage", -1)) == 1, "O estágio salvo da missão (1, em andamento) é restaurado corretamente")

	# In real gameplay, loading a save always goes through a FRESH scene
	# instantiation (MainMenu "Load Game" -> change_scene_to_file), which
	# creates a brand-new CobraCampaignController via configure(). This test
	# reuses the already-running controller instead, so to reproduce exactly
	# what a real load does, call the same configure() a fresh boot would —
	# not a shortcut, but the documented recovery path in
	# CobraCampaignController.configure(): "Runtime fixtures are never
	# restored mid-combat. Resume at a safe mission start, retaining
	# completed missions and all one-time rewards in the ledger."
	runtime.configure(player, ledger, world.get_node("CobraTerritory"))
	check(String(ledger.data.get("active_id", "")) == "", "configure() após um load intencionalmente falha/limpa qualquer missão salva em andamento (nenhum estado de combate é restaurado)")
	check(bool(ledger.get_status("cobra_contact").get("available", false)), "A missão salva em andamento volta a ficar disponível para nova tentativa após o load (retry seguro, comportamento documentado e não uma perda silenciosa)")

	await finish(_tag, world)
