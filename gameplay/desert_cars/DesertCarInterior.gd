extends RefCounted
## Dimensões da cabine definidas junto com o exterior, independentes dos retrovisores e
## dos recortes de porta. O sistema compartilhado de motorista sentado ainda monta e anima a cabine.
static func spec(s: Dictionary) -> Dictionary:
	var w := float(s["size"][0])
	var h := float(s["size"][1])
	var l := float(s["size"][2])
	var coupe := str(s.body)=="coupe"
	var sport := str(s.body) in ["coupe","muscle"]
	return {
		"kind":"sport" if sport else ("pickup" if s.body=="pickup" else "car"),
		"floor":float(s.wheel_radius)*.72+.025,
		"seat_floor":float(s.wheel_radius)*.72+.025,
		"belt":float(s.shoulder),
		"roof":h-(.085 if coupe else .115),
		"hw":w*.41,
		"wz0":l*float(s.cabin_front)+.035,
		"wz1":l*float(s.roof_front)+.035,
		"rear":l*float(s.cabin_back)-.045,
		"rear_top":l*float(s.roof_back)-.035,
		"rows":str(s.body) in ["hatch","sedan"],
		# O teto externo já fecha a cabine. Um forro retangular cortaria
		# os ombros afunilados dele e apareceria como um segundo teto transparente.
		"roof_liner":false,
		"roof_rear":l*float(s.roof_back)-.035,
		"roof_trim_x":w*(.30 if coupe else .34),
		"roof_trim_y":h-(.13 if coupe else .16),
		"dash_front_inset":.055,
		"dash_min_depth":.10,
		"cluster_rise":.02,
		"cluster_depth":.12,
	}
