extends SceneTree
## Todo texto em português do código de produção precisa sair em inglês com o idioma em inglês.
## Lê os .gd/.tscn de verdade e passa cada texto pelo TranslationServer do jogo (os mesmos moldes
## de %s, separadores " · " e prefixos), então pega o que a tabela não cobre. Em 28/10 o Ato 2 do
## deserto, o turno da noite da Vértice e a Helena do Ato 1 inteiros apareciam em português no inglês.
## O que fica igual de propósito (nomes, marcas, arquivos de teste ou que escolhem o idioma sozinhos)
## está em data/localization/untranslated-ok.json.
## Limite: a heurística de "parece português" (acento ou palavra comum) deixa passar texto curto
## sem acento, e texto montado por concatenação só é visto em pedaços.
const ROOTS := ["activities", "assets", "audio", "cutscenes", "data", "gameplay", "runtime", "scripts", "systems", "ui", "world"]
const SKIP_DIRS := ["tests", "tools", "addons", "source_v1"]
const DIALOGUE_JSON := ["res://data/campaign/helena-act1-dialogue.json", "res://data/campaign/prologue-blitz-dialogue.json", "res://data/campaign/vertice-night-dialogue.json", "res://data/campaign/first-favors-dialogue.json"]
var failures := 0
var checks := 0
var missing: Array[String] = []
var _literal := RegEx.new()
var _accent := RegEx.new()
var _words := RegEx.new()
var _identifier := RegEx.new()
var _skip_line := RegEx.new()
var _ok_texts := {}
var _ok_files := {}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_literal.compile("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	_accent.compile("[áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ]")
	_words.compile("\\b(Sem|Não|Você|Para|Com|de|da|das|dos|para|pra|com|não|você|um|uma|na|no|em|ao|aos|está|os|que|pela|pelo|até|depois|antes|aqui|agora|ainda|seu|sua|Aperte|Segure|Saia|Volte|Leve|Siga|Fale|Pegue|Compre|Encontre|Corra|Pegar|Abrir|Falar|Fechar|Voltar|Continuar|Sair|Comprar|Vender)\\b")
	_identifier.compile("^[a-z0-9_.:\\-/]+$")
	_skip_line.compile("(print|push_warning|push_error|printerr|_warn\\(|StallWorkTrace|STALL_WORK|assert\\(|_note_slow|has_method|get_node|load\\(|preload\\(|add_task\\(|add_group_task\\(|\"en\"|english)")
	var allow: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/untranslated-ok.json"))
	for text in allow.get("texts", []): _ok_texts[str(text)] = true
	for path in allow.get("files", []): _ok_files[str(path)] = true
	preload("res://runtime/Localization.gd").install()
	var original := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for root_dir in ROOTS: _scan_dir("res://" + root_dir)
	_check_dialogue_json()
	# Montagens que a varredura só vê como molde: o texto final, como aparece na tela.
	var letter := String(TranslationServer.translate("Carta de Vicente nº 3 · 3 de 10"))
	check(letter == "Vicente's letter #3 · 3 of 10", "Cabeçalho da carta: " + letter)
	var wanted: String = preload("res://ui/hud/WantedPresentation.gd").text_for(2, "search", 0.0, 0.0)
	check(wanted.ends_with("  Search"), "Estrelas em busca: " + wanted)
	wanted = preload("res://ui/hud/WantedPresentation.gd").text_for(1, "pursuit", 0.0, 0.0)
	check(wanted.ends_with("  Pursuit"), "Estrelas em perseguição: " + wanted)
	wanted = preload("res://ui/hud/WantedPresentation.gd").text_for(0, "investigation", 0.0, 0.0, 62.0)
	check(wanted == "Local investigation  1:02", "Investigação local: " + wanted)
	TranslationServer.set_locale(original)
	missing.sort()
	for row in missing: push_error("Sem tradução: " + row)
	print("LOCALIZATION_COVERAGE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub in SKIP_DIRS: continue
		_scan_dir(path + "/" + sub)
	for file in dir.get_files():
		if file.begins_with("test_"): continue
		if file.ends_with(".gd") or file.ends_with(".tscn"): _scan_file(path + "/" + file)

func _scan_file(path: String) -> void:
	if _ok_files.has(path.trim_prefix("res://")): return
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for index in lines.size():
		var line: String = lines[index]
		var stripped := line.strip_edges()
		if stripped.begins_with("#") or _skip_line.search(line) != null: continue
		for found in _literal.search_all(line):
			var text := found.get_string(1).replace("\\n", "\n").replace("\\\"", "\"").replace("\\t", "\t")
			if not _looks_portuguese(text) or _ok_texts.has(text.strip_edges()): continue
			# Par embutido ("pt", "en") ao lado: o próprio código já escolhe o idioma.
			var after := line.substr(found.get_end()).strip_edges()
			if after.begins_with(","):
				var next := _literal.search(after)
				if next != null and next.get_start() <= 3 and not _looks_portuguese(next.get_string(1)): continue
			checks += 1
			# Pedaços de frase montada (" · Leve o lacre...") chegam ao tradutor já colados ao resto:
			# o teste cola um começo/fim qualquer para exercitar os prefixos e sufixos da tabela.
			var probe := ("Zzq" if text.begins_with(" ") else "") + text + ("Zzq" if text.ends_with(" ") else "")
			if String(TranslationServer.translate(probe)) == probe:
				failures += 1
				missing.append("%s:%d  %s" % [path.trim_prefix("res://"), index + 1, text.c_escape()])

func _looks_portuguese(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.length() < 2 or trimmed.begins_with("res://") or _identifier.search(trimmed) != null: return false
	if trimmed.begins_with("[") and trimmed.ends_with("]") and not " " in trimmed: return false
	return _accent.search(trimmed) != null or (" " in trimmed and _words.search(trimmed) != null)

## Falas em JSON escolhem o "en" sozinhas; "en" vazio cai para o português no jogo em inglês.
func _check_dialogue_json() -> void:
	for path in DIALOGUE_JSON:
		var empty: Array[String] = []
		_collect_empty_english(JSON.parse_string(FileAccess.get_file_as_string(path)), empty)
		check(empty.is_empty(), "%s: %d falas sem \"en\" (%s)" % [path, empty.size(), ", ".join(empty.slice(0, 3))])

func _collect_empty_english(value: Variant, empty: Array[String]) -> void:
	if value is Dictionary:
		if value.has("pt") and value.pt is String and str(value.get("en", "")).strip_edges().is_empty(): empty.append(str(value.pt))
		for child in value.values(): _collect_empty_english(child, empty)
	elif value is Array:
		for child in value: _collect_empty_english(child, empty)
