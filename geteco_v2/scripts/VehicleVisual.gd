extends RefCounted
## Presentation-only factory. Geometry is shared with the original prepared car.
const COUPE := preload("res://assets/Coupe.scn")
static var materials: Dictionary = {}

static func create(color := Color("b83632")) -> Node3D:
	if materials.is_empty():
		var palette := {
			"paint": ["b83632",0.25,0.24], "rubber": ["171b20",0.0,0.9],
			"trim": ["30373d",0.15,0.45], "glass": ["243a47",0.35,0.17],
			"alloy": ["b5bdc3",0.72,0.24], "headlight": ["e6f0ed",0.15,0.16],
			"brake": ["cd6133",0.2,0.4], "rotor": ["515963",0.55,0.55],
			"smoked_lens": ["293b44",0.35,0.16], "tail": ["eb3832",0.1,0.25]
		}
		for key in palette:
			var entry: Array = palette[key]
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(entry[0])
			mat.metallic = entry[1]
			mat.roughness = entry[2]
			if key == "glass": mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			if key in ["headlight","tail"]:
				mat.emission_enabled = true
				mat.emission = mat.albedo_color
				mat.emission_energy_multiplier = 0.3 if key == "headlight" else 0.65
			materials[key] = mat
	var result := COUPE.instantiate() as Node3D
	var paint: StandardMaterial3D = materials.paint.duplicate()
	paint.albedo_color = color
	for part in result.get_children():
		var key := str(part.get_meta("coupe_damage_material_key",""))
		assert(materials.has(key),"Original coupe material missing: "+key)
		part.material_override = paint if key == "paint" else materials[key]
	return result
