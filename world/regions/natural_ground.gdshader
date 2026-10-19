shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Variante opaca: sem ALPHA (o uniform edge_alpha existe, mas não tem efeito aqui).
// Malhas com borda esmaecida usam natural_ground_edge.gdshader.
#include "res://world/regions/natural_ground_common.gdshaderinc"
