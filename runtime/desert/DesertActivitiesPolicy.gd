extends RefCounted
## Diagnostic only: comparable rendered baseline without the new batch.
static func enabled() -> bool:
	return not (OS.is_debug_build() and "--desert-activities-baseline" in OS.get_cmdline_user_args())
