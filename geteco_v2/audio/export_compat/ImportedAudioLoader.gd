extends RefCounted
## Carregador de áudio compatível com recurso importado/exportado.
## ESTADO: NÃO CONECTADO. Nenhum consumidor produtivo o chama ainda (contrato em docs/EXPORT_READINESS.md).
##
## Por que existe: no PCK um `.wav` só existe como recurso importado (`.godot/imported/*.sample`). `FileAccess` e
## `AudioStreamWAV.load_from_file()` só enxergam o arquivo-fonte, que é o que o editor tem e o pacote não. O caminho válido nos
## dois mundos é `ResourceLoader`. O arquivo bruto só é tentado quando o recurso importado NÃO existe (árvore sem reimportar),
## e nunca em silêncio: toda falha fica em `failures` e sai por `push_error` uma única vez por caminho.
##
## Contrato de tipo: `stream()` devolve `AudioStream` (basta para tocar e para `get_length()`); `wav()` exige `AudioStreamWAV`
## (necessário para `duplicate()` + `loop_mode`/`data`). `fresh()` devolve cópia própria para quem altera loop/tamanho, sem
## contaminar o cache compartilhado.
const SOURCE_EDITOR := "resource"
const SOURCE_RAW := "raw_file"

static var _cache: Dictionary = {}     ## path -> AudioStream (só sucessos; falhas ficam em `failures`)
static var failures: Dictionary = {}   ## path -> motivo (diagnóstico persistente, sem repetir push_error)
static var sources: Dictionary = {}    ## path -> SOURCE_*

## `AudioStream` do recurso importado; nulo (com diagnóstico) se indisponível. Cacheado.
static func stream(path: String) -> AudioStream:
	if _cache.has(path): return _cache[path]
	if failures.has(path): return null
	var loaded: AudioStream = null
	if ResourceLoader.exists(path, "AudioStream"):
		loaded = ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_REUSE) as AudioStream
		if loaded == null: return _fail(path, "ResourceLoader.exists=true mas load devolveu nulo/tipo não-AudioStream")
		sources[path] = SOURCE_EDITOR
	elif path.get_extension().to_lower() == "wav" and FileAccess.file_exists(path):
		# Somente árvore de fontes sem importação. Em PCK este ramo nunca é alcançado.
		loaded = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
		if loaded == null: return _fail(path, "arquivo bruto existe mas load_from_file falhou")
		sources[path] = SOURCE_RAW
	else:
		return _fail(path, "sem recurso importado nem arquivo bruto")
	_cache[path] = loaded
	return loaded

## Como `stream`, mas exige `AudioStreamWAV` (consumidores que leem `data`/`loop_mode`/`mix_rate`).
static func wav(path: String) -> AudioStreamWAV:
	var loaded := stream(path)
	if loaded == null: return null
	if not loaded is AudioStreamWAV:
		_fail(path, "esperava AudioStreamWAV, veio %s" % loaded.get_class())
		return null
	return loaded as AudioStreamWAV

## Cópia independente (para trocar loop_mode/loop_end sem alterar o recurso compartilhado).
static func fresh(path: String) -> AudioStreamWAV:
	var shared := wav(path)
	return shared.duplicate() as AudioStreamWAV if shared != null else null

## Duração em segundos; 0.0 se indisponível (o motivo está em `failures`). Mesma leitura usada pela recarga.
static func duration(path: String) -> float:
	var loaded := stream(path)
	return loaded.get_length() if loaded != null else 0.0

static func report() -> Dictionary:
	return {"loaded": _cache.size(), "failed": failures.size(), "failures": failures.duplicate(), "raw_fallbacks": sources.values().count(SOURCE_RAW)}

static func clear() -> void:
	_cache.clear()
	failures.clear()
	sources.clear()

static func _fail(path: String, reason: String) -> AudioStream:
	failures[path] = reason
	push_error("[ImportedAudioLoader] %s: %s" % [path, reason])
	return null
