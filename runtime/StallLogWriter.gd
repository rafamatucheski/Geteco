extends RefCounted
## Somente strings e arquivo na thread; nunca acessa a árvore do jogo.
const MAX_PENDING := 2048
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending: Array[String] = []
var _file: FileAccess
var _stopping := false
var _dropped := 0
var _reported_drops := 0
var _batches := 0
var _max_write_ms := 0.0

func start(path: String) -> Error:
	# Abertura antes da partida. Daqui em diante só a thread toca no arquivo.
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null: return FileAccess.get_open_error()
	var error := _thread.start(_run)
	if error != OK:
		_file.close()
		_file = null
	return error

func enqueue(line: String) -> bool:
	_mutex.lock()
	if _stopping or _pending.size() >= MAX_PENDING:
		_dropped += 1
		_mutex.unlock()
		return false
	var wake := _pending.is_empty()
	_pending.append(line)
	_mutex.unlock()
	if wake: _wake.post()
	return true

func stats() -> Dictionary:
	_mutex.lock()
	var result := {"threaded": true, "queued_records": _pending.size(),
		"dropped_records": _dropped, "write_batches": _batches, "max_write_ms": _max_write_ms}
	_mutex.unlock()
	return result

func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var lines := _pending
		_pending = []
		var stopping := _stopping
		var drops := _dropped - _reported_drops
		_reported_drops = _dropped
		_mutex.unlock()
		if drops > 0: lines.append(JSON.stringify({"type": "writer_dropped", "records": drops}))
		if not lines.is_empty():
			var began := Time.get_ticks_usec()
			_store_batch(lines)
			_mutex.lock()
			_batches += 1
			_max_write_ms = maxf(_max_write_ms, float(Time.get_ticks_usec() - began) / 1000.0)
			_mutex.unlock()
		if stopping: break
	_file.close()
	_file = null

func _store_batch(lines: Array[String]) -> void:
	for line in lines: _file.store_line(line)
	_file.flush()

func stop() -> void:
	if not _thread.is_started(): return
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	# Espera apenas no encerramento: preserva inclusive a última janela.
	_thread.wait_to_finish()
