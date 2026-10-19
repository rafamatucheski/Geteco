shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Variante de borda: escreve ALPHA quando edge_alpha está ligado, por isso vai inteira para o
// pipeline transparente. Só para malhas cujo alfa de vértice esmaece a borda sobre o terreno.
#define NATURAL_GROUND_EDGE
#include "res://world/regions/natural_ground_common.gdshaderinc"
