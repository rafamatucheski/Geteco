extends Translation
## Bounded presentation-only cache: no tree walks and no per-frame processing.
## Format templates also translate already-formatted labels without touching IDs.
const CACHE_LIMIT := 4096
var _messages: Dictionary = {}
var _templates: Dictionary = {}
var _cache: Dictionary = {}
var _prefixes: Dictionary = {}
var _suffixes: Dictionary = {}

func configure(pairs: Dictionary, english: bool) -> void:
	for pt in pairs:
		var en: Variant = pairs[pt]
		if not en is String or str(pt).is_empty() or en.is_empty(): continue
		var source: String = str(pt) if english else en
		var destination: String = en if english else str(pt)
		_messages[source] = destination
		# Both language strings are valid source inputs, including already-localized dialogue.
		if not _messages.has(destination): _messages[destination] = destination
		_add_template(source, destination)
		_add_template(destination, destination)
		if source.strip_edges() != source:
			_messages[source.strip_edges()] = destination.strip_edges()
			_add_template(source.strip_edges(), destination.strip_edges())
		if source.length() >= 5 and source.ends_with(" "):
			var key := _bucket(source.strip_edges())
			if not _prefixes.has(key): _prefixes[key] = []
			_prefixes[key].append([source, destination])
		if source.length() >= 4 and source.begins_with(" "):
			var key := source.strip_edges().get_slice(" ", source.strip_edges().get_slice_count(" ")-1)
			if not _suffixes.has(key): _suffixes[key] = []
			_suffixes[key].append([source, destination])

func _get_message(source: StringName, _context: StringName) -> StringName:
	var value := String(source)
	if _messages.has(value): return StringName(_messages[value])
	if _cache.has(value): return StringName(_cache[value])
	var translated := _resolve(value, 0)
	if _cache.size() >= CACHE_LIMIT: _cache.clear()
	_cache[value] = translated
	# Identity is a resolved source-language message too. Returning empty here
	# lets Godot try the English fallback on the first display of composed labels.
	return StringName(translated)

func _resolve(value: String, depth: int) -> String:
	if _messages.has(value): return _messages[value]
	if depth > 3 or value.is_empty(): return value
	var trimmed := value.strip_edges()
	if trimmed != value and not trimmed.is_empty():
		var begin := value.find(trimmed)
		return value.left(begin)+_resolve(trimmed, depth+1)+value.substr(begin+trimmed.length())
	var candidates: Array = _templates.get(_bucket(value), [])
	for row in candidates:
		var found: RegExMatch = row.pattern.search(value)
		if found == null: continue
		var result: String = row.target
		for index in range(found.get_group_count(), 0, -1):
			result = result.replace("{L10N_"+str(index)+"}", _resolve(found.get_string(index), depth+1))
		return result
	# Composed inventory rows, objective summaries and notices retain their separators.
	for separator in ["\n", " · ", "  |  ", " • ", " — ", " → ", ": ", " / "]:
		if separator in value:
			var parts := value.split(separator)
			for index in parts.size(): parts[index] = _resolve(parts[index], depth+1)
			var joined: String = separator.join(parts)
			if joined != value: return joined
	for row in _prefixes.get(_bucket(value), []):
		if value.begins_with(row[0]): return row[1]+_resolve(value.substr(row[0].length()), depth+1)
	var last_word := value.get_slice(" ", value.get_slice_count(" ")-1)
	for row in _suffixes.get(last_word, []):
		if value.ends_with(row[0]): return _resolve(value.left(value.length()-row[0].length()), depth+1)+row[1]
	return value

func _bucket(value: String) -> String:
	return value.get_slice(" ", 0).get_slice("\n", 0)

func _add_template(source: String, target: String) -> void:
	var tokens := RegEx.new()
	tokens.compile("(?<!%)%(?!%)(?:[-+0#]*[0-9]*(?:\\.[0-9]+)?)?[sdif]")
	var placeholders := tokens.search_all(source)
	if placeholders.is_empty(): return
	var target_tokens := tokens.search_all(target)
	if placeholders.size() != target_tokens.size(): return
	# Variable-first templates would match unrelated messages. These are composed at call sites.
	if placeholders[0].get_start() == 0: return
	var pattern := "^"
	var previous := 0
	for token in placeholders:
		pattern += _escape(source.substr(previous, token.get_start()-previous).replace("%%", "%"))
		pattern += "(.*?)" if token.get_string().ends_with("s") else "([-+0-9.,]+)"
		previous = token.get_end()
	pattern += _escape(source.substr(previous).replace("%%", "%"))+"$"
	var regex := RegEx.new()
	if regex.compile(pattern) != OK: return
	for index in range(target_tokens.size()-1, -1, -1):
		var token: RegExMatch = target_tokens[index]
		target = target.left(token.get_start())+"{L10N_"+str(index+1)+"}"+target.substr(token.get_end())
	target = target.replace("%%", "%")
	var key := _bucket(source)
	if not _templates.has(key): _templates[key] = []
	_templates[key].append({"pattern":regex, "target":target})

func _escape(value: String) -> String:
	var result := ""
	for character in value:
		if character in "\\.^$|?*+()[]{}": result += "\\"
		result += character
	return result
