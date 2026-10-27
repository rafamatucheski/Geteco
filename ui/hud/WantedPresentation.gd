extends RefCounted
const ACCENT := Color("e6bd72")

## `remaining`: segundos que faltam da investigação local (mostrados como 0:42).
static func text_for(stars: int, phase: String, progress: float, clock: float, remaining := -1.0) -> String:
	if phase == "surrender": return "Rendendo-se"
	if stars <= 0:
		if phase != "investigation": return ""
		if remaining < 0.0: return "Investigação local"
		var seconds := int(ceil(remaining))
		return "Investigação local  %d:%02d" % [seconds / 60, seconds % 60]
	var result := ""
	for index in stars:
		var color := ACCENT
		if phase == "search":
			var frequency := 2.0 if index == stars - 1 and progress >= 0.75 else 0.8
			color.a = 0.3 + 0.7 * (0.5 + 0.5 * cos(clock * TAU * frequency))
		result += "[color=#%s]★[/color]" % color.to_html(true)
	return result + ("  Busca" if phase == "search" else "  Perseguição")
