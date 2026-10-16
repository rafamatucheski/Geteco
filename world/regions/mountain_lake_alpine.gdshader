shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Lago alpino (bacia no terreno): cor e opacidade pela profundidade real da água, com o fundo
// tirado do mapa de alturas do terreno que NativeLake grava, sem ler o buffer de profundidade.
#define LAKE_FLOOR_MAP
#include "res://world/regions/mountain_lake.gdshaderinc"
