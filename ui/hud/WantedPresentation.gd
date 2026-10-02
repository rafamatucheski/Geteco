extends RefCounted
const ACCENT := Color("e6bd72")

static func text_for(stars: int, phase: String, progress: float, clock: float) -> String:
	if phase == "surrender": return "RENDENDO-SE"
	if stars <= 0: return "INVESTIGAÇÃO LOCAL" if phase == "investigation" else ""
	var result := ""
	for index in stars:
		var color := ACCENT
		if phase == "search":
			var frequency := 2.0 if index == stars - 1 and progress >= 0.75 else 0.8
			color.a = 0.3 + 0.7 * (0.5 + 0.5 * cos(clock * TAU * frequency))
		result += "[color=#%s]★[/color]" % color.to_html(true)
	return result + ("  BUSCA" if phase == "search" else "  PERSEGUIÇÃO")
