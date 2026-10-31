extends RefCounted
## Leitura ambiente derivada do mesmo clima regional e relógio do céu.
## Celsius é uma estimativa ambiente escrita, separada do calor do corpo (0–100%).
static func text(day: int, time: float, region: String, weather: int, mountain: Dictionary = {}) -> String:
	var minutes := posmod(int(floor(time * 1440.0)), 1440)
	var daylight := sin((time - .25) * TAU)
	var base: float = {"mountain":-8.0,"desert":30.0}.get(region,22.0)
	var temperature := roundi(base + daylight * (8.0 if region == "desert" else 4.0) - ([0.0,3.0,5.0,2.0][clampi(weather,0,3)] if region != "mountain" else float(mountain.get("front",0.0))*6.0))
	var weekday: String = ["seg","ter","qua","qui","sex","sáb","dom"][posmod(day-2,7)]
	return "%s · %02d:%02d · %d°C" % [weekday, minutes / 60, minutes % 60, temperature]

static func icon(time: float, region: String, weather: int, mountain: Dictionary = {}) -> String:
	if region == "mountain" and int(mountain.get("state",0)) > 0:
		return "hail" if int(mountain.get("state",0)) == 3 else "snow"
	if region != "mountain" and weather != 0:
		return ["sun","rain","storm","cloud"][clampi(weather,0,3)]
	return "sun" if fposmod(time,1.0) >= .25 and fposmod(time,1.0) < .75 else "moon"

static func vertical_text(day: int, time: float, region: String, weather: int, mountain: Dictionary = {}) -> String:
	return text(day,time,region,weather,mountain).replace(" · ","\n")
