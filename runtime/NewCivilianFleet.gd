extends RefCounted
## Adições civis escritas; os valores de jogo usam a mesma escala da frota existente.
const IDS := ["besouro_1300", "mare_microvan", "toco_minitruck"]
const DATA := {
 "besouro_1300":{"label":"Besouro 1300","size":[1.90,1.58,4.23],"colors":["a7b78bff","d9cfafff","758d96ff","925647ff"],"speed":278.0,"mass":.9,"district":"residential","engine":"compact","door":{"zf":-.69,"zr":.57,"sill":.30,"belt":.89,"top":1.48,"x":.73,"seat_z":-.06}},
 "mare_microvan":{"label":"Maré","size":[2.08,2.05,4.59],"colors":["4c9b95ff","718da0ff","ae674fff","83946aff"],"speed":264.0,"mass":1.55,"district":"coastal","engine":"van","door":{"class":"tall","zf":-1.92,"zr":-.76,"sill":.35,"belt":1.12,"top":1.95,"x":.84,"seat_z":-1.25}},
 "toco_minitruck":{"label":"Toco","size":[2.00,1.90,4.41],"colors":["dca33eff","d6d5c8ff","66868fff","8b5546ff"],"speed":258.0,"mass":1.4,"district":"industrial","engine":"truck","door":{"class":"tall","zf":-1.89,"zr":-.58,"sill":.36,"belt":1.00,"top":1.82,"x":.80,"seat_z":-1.12}}
}
static func door_spec(id: String) -> Dictionary:
 return DATA.get(id,{}).get("door",{}).duplicate(true)
static func spec(id: String) -> Dictionary:
 if not DATA.has(id): return {}
 var d: Dictionary = DATA[id]
 return {"id":id,"label":d.label,"scene":"res://assets/fleet/redesigned/"+id+".scn","bounds_size":d.size,"bounds_center":[0,d.size[1]*.5,0],"colors":d.colors,"target_width":34.0,"target_length":72.0 if id=="besouro_1300" else 80.0,"acceleration":610.0,"braking":900.0,"max_speed":d.speed,"turn_speed":2.5,"drift_factor":.78,"mass":d.mass,"durability":155 if id=="besouro_1300" else 210,"drivetrain":"rwd","engine_family":d.engine,"engine_pitch":1.1 if id=="besouro_1300" else .9,"district":d.district,"roof_prop":"none","crop_index":0,"mesh_count":10}
