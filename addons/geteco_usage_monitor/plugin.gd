@tool
extends EditorPlugin
## Editor only: the external supervisor owns pause/restore and waits for the
## exact game process, including Stop/F8 and crashes. No gameplay frame hook.

const SUPERVISOR := "res://tools/EditorUsageMonitor.ps1"
var _run_token := ""

func _build() -> bool:
	_run_token = ""
	if OS.get_name() != "Windows":
		return true
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	if local_app_data.is_empty() or not FileAccess.file_exists(local_app_data.path_join("OpenUsage/openusage.exe")):
		return true
	if not FileAccess.file_exists(SUPERVISOR):
		push_error("OpenUsage: supervisor ausente; execução cancelada.")
		return false
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	var output: Array = []
	var code := OS.execute("powershell.exe", PackedStringArray([
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", ProjectSettings.globalize_path(SUPERVISOR), "-Mode", "Start",
		"-EditorPid", str(OS.get_process_id()), "-Token", token,
		"-EditorExe", OS.get_executable_path(),
		"-ProjectRoot", ProjectSettings.globalize_path("res://").trim_suffix("/")
	]), output, true, false)
	if code != 0:
		push_error("OpenUsage: não foi possível preparar a pausa; execução cancelada. " + "\n".join(output))
		return false
	_run_token = token
	return true

func _run_scene(_scene: String, args: PackedStringArray) -> PackedStringArray:
	if not _run_token.is_empty():
		# Godot adds main_run_args after plugin args. Do not insert "--" here:
		# it would turn later engine switches into user arguments.
		# The engine ignores this custom option; the supervisor reads the nonce.
		args.append("--geteco-usage-session=" + _run_token)
		_run_token = ""
	return args
