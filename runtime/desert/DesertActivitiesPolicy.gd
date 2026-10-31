extends RefCounted
## Só diagnóstico: base renderizada comparável sem o novo lote.
static func enabled() -> bool:
	return not (OS.is_debug_build() and "--desert-activities-baseline" in OS.get_cmdline_user_args())
