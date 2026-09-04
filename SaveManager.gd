extends Node

## Gerenciador Central de Save / Load
## Controla gravação atômica versionada em user://saves/slot_NN.json e user://saves/autosave.json.
## Regra Inegociável: Todo estado é obtido e restaurado diretamente de CampaignState, Player e WantedManager.

const CURRENT_SAVE_VERSION: int = 1
const SAVE_DIR: String = "user://saves/"

# Estrutura de slots padrão suportados
const DEFAULT_SLOTS: Array[String] = ["slot_01", "slot_02", "slot_03", "slot_04", "slot_05"]

signal save_completed(slot_id: String, success: bool, message: String)
signal load_completed(slot_id: String, success: bool, message: String)

var _pending_save_data: Dictionary = {}
var _save_dir: String = SAVE_DIR
var _save_directory_ready := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_save_directory()

func _ensure_save_directory() -> void:
	if _save_directory_ready:
		return
	var absolute_save_dir := ProjectSettings.globalize_path(_save_dir)
	var err := DirAccess.make_dir_recursive_absolute(absolute_save_dir)
	if err != OK or not _directory_is_writable(absolute_save_dir):
		if DisplayServer.get_name() == "headless":
			absolute_save_dir = OS.get_temp_dir().path_join("gta_topdown_clone_headless/saves")
			err = DirAccess.make_dir_recursive_absolute(absolute_save_dir)
			if err == OK and _directory_is_writable(absolute_save_dir):
				_save_dir = absolute_save_dir + "/"
				_save_directory_ready = true
				return
		push_error("SaveManager: Falha ao preparar diretório de saves em %s (código %d)" % [_save_dir, err])
		return
	_save_directory_ready = true

func _directory_is_writable(absolute_directory: String) -> bool:
	var probe_path := absolute_directory.path_join(".write_probe.tmp")
	var probe := FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return false
	probe.close()
	DirAccess.remove_absolute(probe_path)
	return true

func get_slot_path(slot_id: String) -> String:
	_ensure_save_directory()
	var clean_id := slot_id.strip_edges().get_file()
	if not clean_id.ends_with(".json"):
		clean_id += ".json"
	return _save_dir + clean_id

## Retorna lista detalhada de slots com metadados para UI do MainMenu e PauseMenu
func list_slots() -> Array[Dictionary]:
	_ensure_save_directory()
	var results: Array[Dictionary] = []
	
	# Checar slots conhecidos primeiro (autosave + slots 1 a 5)
	var slots_to_check: Array[String] = ["autosave"]
	slots_to_check.append_array(DEFAULT_SLOTS)
	
	# Verificar se há outros arquivos .json no diretório
	var dir := DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var base := file_name.get_basename()
				if not slots_to_check.has(base):
					slots_to_check.append(base)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	for slot_id in slots_to_check:
		results.append(inspect_slot(slot_id))
		
	return results

## Inspeciona um slot sem necessariamente carregá-lo para execução
func inspect_slot(slot_id: String) -> Dictionary:
	var path := get_slot_path(slot_id)
	var info := {
		"slot_id": slot_id,
		"path": path,
		"exists": false,
		"valid": false,
		"error": "",
		"save_version": 0,
		"timestamp": 0,
		"date_string": "Vazio",
		"summary": {
			"money": 0,
			"current_stage": "",
			"current_stars": 0,
			"player_health": 0
		}
	}
	
	if not FileAccess.file_exists(path):
		info["error"] = "Slot vazio"
		return info
	
	info["exists"] = true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		info["error"] = "Erro ao abrir arquivo: %s" % error_string(FileAccess.get_open_error())
		return info
	
	var text := file.get_as_text()
	file.close()
	
	if text.strip_edges().is_empty():
		info["error"] = "Arquivo de save está vazio"
		return info
	
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		info["error"] = "Arquivo corrompido: JSON inválido"
		return info
	
	var data := parsed as Dictionary
	
	# Validação de save_version obrigatória
	if not data.has("save_version"):
		info["error"] = "Formato inválido: campo 'save_version' ausente"
		return info
	
	var ver: int = int(data.get("save_version", 0))
	info["save_version"] = ver
	if ver <= 0:
		info["error"] = "Versão de save inválida: v%d" % ver
		return info
	if ver > CURRENT_SAVE_VERSION:
		info["error"] = "Versão incompatível: v%d (jogo suporta até v%d)" % [ver, CURRENT_SAVE_VERSION]
		return info
	
	info["valid"] = true
	info["timestamp"] = int(data.get("timestamp", 0))
	info["date_string"] = String(data.get("date_string", "Data desconhecida"))
	if data.has("summary") and data["summary"] is Dictionary:
		info["summary"] = (data["summary"] as Dictionary).duplicate(true)
	
	return info

## Salva o estado completo atual do jogo em um slot
func save_game(slot_id: String = "slot_01", custom_summary_note: String = "") -> Dictionary:
	_ensure_save_directory()
	
	var tree := get_tree()
	var player = tree.get_first_node_in_group("player")
	var wanted = tree.root.get_node_or_null("WantedManager")
	var campaign = tree.root.get_node_or_null("CampaignState")
	
	if player == null or not is_instance_valid(player):
		var err_msg := "Não é possível salvar: Jogador não encontrado no mundo"
		save_completed.emit(slot_id, false, err_msg)
		return {"success": false, "error": err_msg}
	
	# Obter dados de cada subsistema sem duplicar fontes de verdade
	var player_data: Dictionary = player.serialize() if player.has_method("serialize") else {}
	var wanted_data: Dictionary = wanted.serialize() if wanted and wanted.has_method("serialize") else {}
	var campaign_data: Dictionary = campaign.to_save_data() if campaign and campaign.has_method("to_save_data") else {}
	
	var now_dict := Time.get_datetime_dict_from_system()
	var date_str := "%04d-%02d-%02d %02d:%02d:%02d" % [
		now_dict.year, now_dict.month, now_dict.day,
		now_dict.hour, now_dict.minute, now_dict.second
	]
	
	var stage_name := String(campaign.current_stage) if campaign else "desconhecido"
	var stars_count: int = int(wanted.current_stars) if wanted else 0
	var player_money: int = int(player.get("money")) if player else 0
	var player_hp: int = int(player.get("health")) if player else 100
	
	var payload: Dictionary = {
		"save_version": CURRENT_SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"date_string": date_str,
		"slot_id": slot_id,
		"summary": {
			"note": custom_summary_note,
			"money": player_money,
			"current_stage": stage_name,
			"current_stars": stars_count,
			"player_health": player_hp
		},
		"campaign": campaign_data,
		"player": player_data,
		"wanted": wanted_data
	}
	
	# Gravação atômica com arquivo temporário
	var target_path := get_slot_path(slot_id)
	var temp_path := target_path + ".tmp"
	
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		var err_msg := "Falha ao abrir arquivo temporário para escrita: %s" % error_string(FileAccess.get_open_error())
		push_error("SaveManager: " + err_msg)
		save_completed.emit(slot_id, false, err_msg)
		return {"success": false, "error": err_msg}
	
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	
	# Renomeia com segurança
	var absolute_target_path := ProjectSettings.globalize_path(target_path)
	var absolute_temp_path := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(target_path):
		DirAccess.remove_absolute(absolute_target_path)
	
	var rename_err := DirAccess.rename_absolute(absolute_temp_path, absolute_target_path)
	if rename_err != OK:
		var err_msg := "Falha ao renomear arquivo temporário para %s (código %d)" % [target_path, rename_err]
		push_error("SaveManager: " + err_msg)
		save_completed.emit(slot_id, false, err_msg)
		return {"success": false, "error": err_msg}
	
	var success_msg := "Jogo salvo com sucesso no slot '%s'!" % slot_id
	save_completed.emit(slot_id, true, success_msg)
	return {"success": true, "path": target_path, "summary": payload["summary"]}

## Executa autosave seguro em checkpoints de missão
## NUNCA salva durante perseguição ativa (estrelas > 0) ou se o jogador estiver morto
func request_autosave(checkpoint_label: String = "") -> bool:
	var tree := get_tree()
	var wanted = tree.root.get_node_or_null("WantedManager")
	if wanted and int(wanted.get("current_stars")) > 0:
		print("SaveManager: Autosave ignorado (perseguição policial ativa: %d estrelas)" % int(wanted.get("current_stars")))
		return false
	
	var player = tree.get_first_node_in_group("player")
	if player and (bool(player.get("is_dead")) or bool(player.get("is_arrested"))):
		print("SaveManager: Autosave ignorado (jogador morto ou preso)")
		return false
	
	var res := save_game("autosave", "Checkpoint: " + checkpoint_label)
	return res.get("success", false)

## Prepara carregamento de um slot. Rejeita versões desconhecidas com erro explicativo.
func load_game(slot_id: String = "slot_01") -> Dictionary:
	var inspect := inspect_slot(slot_id)
	if not inspect.get("valid", false):
		var err_msg: String = inspect.get("error", "Save inválido")
		push_error("SaveManager: Não é possível carregar '%s': %s" % [slot_id, err_msg])
		load_completed.emit(slot_id, false, err_msg)
		return {"success": false, "error": err_msg}
	
	var path: String = inspect["path"]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err_msg := "Erro ao abrir save para leitura: %s" % error_string(FileAccess.get_open_error())
		load_completed.emit(slot_id, false, err_msg)
		return {"success": false, "error": err_msg}
	
	var text := file.get_as_text()
	file.close()
	
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		var err_msg := "Conteúdo de save malformado"
		load_completed.emit(slot_id, false, err_msg)
		return {"success": false, "error": err_msg}
	
	var data := parsed as Dictionary
	var ver: int = int(data.get("save_version", 0))
	if ver > CURRENT_SAVE_VERSION:
		var err_msg := "Versão de save não suportada: v%d (máximo v%d)" % [ver, CURRENT_SAVE_VERSION]
		load_completed.emit(slot_id, false, err_msg)
		return {"success": false, "error": err_msg}
	
	_pending_save_data = data
	load_completed.emit(slot_id, true, "Save carregado com sucesso")
	return {"success": true, "data": data}

func has_pending_save() -> bool:
	return not _pending_save_data.is_empty()

func clear_pending_save() -> void:
	_pending_save_data.clear()

## Aplica os dados do save pendente sobre os nós reais da cena atual
func apply_pending_save(tree: SceneTree) -> bool:
	if _pending_save_data.is_empty():
		return false
	
	var data := _pending_save_data
	_pending_save_data = {} # Consumido
	
	# 1. Restaurar CampaignState
	var campaign = tree.root.get_node_or_null("CampaignState")
	if campaign and data.has("campaign") and data["campaign"] is Dictionary:
		campaign.restore_from_save(data["campaign"])
	
	# 2. Restaurar WantedManager
	var wanted = tree.root.get_node_or_null("WantedManager")
	if wanted and data.has("wanted") and data["wanted"] is Dictionary:
		wanted.restore(data["wanted"])
	
	# 3. Restaurar Player
	var player = tree.get_first_node_in_group("player")
	if player and data.has("player") and data["player"] is Dictionary:
		player.restore(data["player"])
	
	print("SaveManager: Save aplicado com sucesso no mundo!")
	return true
