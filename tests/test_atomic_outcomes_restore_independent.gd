extends SceneTree
## Synthetic persistence of already-observed productive outcomes.
## Requires an explicit unique directory below OS.get_temp_dir().

const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const SERVICES := preload("res://runtime/Services.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("ATOMIC_RESTORE PASS " if ok else "ATOMIC_RESTORE FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok:
		failures.append(label)
		push_error(label + ((" | " + detail) if not detail.is_empty() else ""))

func isolated_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--isolated-save-root="):
			return arg.trim_prefix("--isolated-save-root=").replace("\\", "/").trim_suffix("/")
	return ""

func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().to_lower()

func _run() -> void:
	var directory := isolated_root()
	var temp := canonical(OS.get_temp_dir()).trim_suffix("/") + "/"
	var resolved := canonical(directory).trim_suffix("/") + "/"
	if directory.is_empty() or not directory.is_absolute_path() or not resolved.begins_with(temp) or resolved == temp:
		push_error("ATOMIC_RESTORE refuses storage outside a unique temp directory: " + directory)
		quit(2)
		return
	var state = STATE.new()
	state.economy.grant_reward("armor_funds", 500)
	var armor_result: Dictionary = state.economy.purchase_body_armor(20, 100, "armor:productive_result")
	if armor_result.get("ok", false):
		state.combat_state = {"health": 100.0, "armor": float(armor_result.armor), "crime_points": 0, "hidden_time": 0.0, "customization": {}}
	check(armor_result.get("ok", false) and state.economy.balance == 0 and int(state.combat_state.armor) == 100,
		"colete publica proteção e débito como um único resultado")

	check(state.campaign.begin("primeiro_giro"), "missão produtiva de Harbor inicia no estado sintético")
	var receipt_result: Dictionary = state.campaign.apply_event("bank_receipt_received", {"target_id": "helena", "on_foot": true, "unarmed": true})
	var pickup_result: Dictionary = state.campaign.apply_event("harbor_parcel_collected", {"target_id": "harbor_parcel", "on_foot": true})
	check(receipt_result.get("ok", false) and pickup_result.get("ok", false) and state.campaign.step == 2,
		"coleta produtiva publica o avanço para entrega")

	var services = SERVICES.new()
	services.auto_serial = 1
	services.serviced_count = 1
	services.set("_last_vehicle", "acceptance_vehicle")
	state.world_state.services = services.snapshot()
	check(SERVICES.validate_snapshot(state.world_state.services), "resultado concluído do serviço forma snapshot válido")

	var store = STORE.new()
	store.path = directory.path_join("outcomes.json")
	check(canonical(store.path).begins_with(resolved) and canonical(store.path) != canonical(STORE.PATH), "SaveStore usa somente o diretório temporário exclusivo")
	var save_result: Error = store.save(state)
	check(save_result == OK, "resultado composto é salvo", error_string(save_result))
	var restored = STATE.new()
	var load_result: Dictionary = store.load_into(restored)
	check(load_result.get("ok", false), "resultado composto é restaurado", str(load_result))
	if not load_result.get("ok", false):
		print("ATOMIC_OUTCOMES_RESTORE FAIL checks=", checks, " failures=", failures.size())
		quit(1)
		return
	check(restored.economy.balance == 0 and int(restored.combat_state.armor) == 100,
		"restauração preserva saldo e colete")
	check(restored.campaign.active_id == "primeiro_giro" and restored.campaign.step == 2 and int(restored.world_state.services.serviced_count) == 1,
		"restauração preserva coleta e serviço")
	var retry: Dictionary = restored.campaign.apply_event("harbor_parcel_collected", {"target_id": "harbor_parcel", "on_foot": true})
	check(not retry.get("changed", true) and restored.campaign.step == 2 and restored.economy.balance == 0,
		"nova interação após restauração não duplica a coleta")
	var armor_retry: Dictionary = restored.economy.purchase_body_armor(restored.combat_state.armor, 100, "armor:retry")
	check(not armor_retry.get("ok", true) and restored.economy.balance == 0,
		"nova interação após restauração não cobra colete já completo")
	print("ATOMIC_OUTCOMES_RESTORE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
