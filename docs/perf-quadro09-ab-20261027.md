# A/B frio do quadro de ~1 s (27/10, madrugada)

Rota oeste com estresse e despacho, 3440Ã—1440, cache frio por sessÃ£o. Leitura em docs/perf-playthrough-20261021.md Â§16.

## 13Âª â€” X padrÃ£o Ã— D sem transparÃªncia

```
rodada	lado	p50	p95	máx	>250ms	quadros>150ms	jogável_s
1	X	11.39	15.45	1018.72	2	[1019, 1008]	80.6
2	D	12.49	18.0	136.68	0	[]	87.6
3	D	12.98	18.6	1232.8	1	[1233, 186]	84.4
4	X	12.72	17.07	1161.21	2	[1161, 1083]	84.0
5	X	12.69	17.19	1093.06	1	[1093]	83.9
6	D	11.74	16.3	130.53	0	[]	85.5
7	D	13.18	18.19	147.52	0	[]	84.1
8	X	12.45	17.56	147.06	0	[]	84.6
lado X: 4 rodadas, quadro > 700 ms em 3
lado D: 4 rodadas, quadro > 700 ms em 1
```

## 15Âª â€” K carga intacta Ã— X padrÃ£o

```
rodada	lado	p50	p95	máx	>250ms	quadros>150ms	jogável_s
1	K	11.92	16.32	1155.06	1	[1155]	86.0
2	X	12.03	16.72	134.1	0	[]	85.4
3	X	12.94	17.91	1228.27	1	[1228, 153]	84.9
4	K	12.54	17.04	155.96	0	[156]	84.0
5	K	12.53	17.2	149.69	0	[]	84.5
6	X	13.35	18.43	1155.14	1	[1155]	86.2
7	X	12.87	17.77	1420.41	4	[1420, 1155, 1114, 1082, 189]	84.4
8	K	12.6	17.57	142.34	0	[]	85.0
lado K: 4 rodadas, quadro > 700 ms em 1
lado X: 4 rodadas, quadro > 700 ms em 3
```

## 16Âª â€” C prÃ©-aquecimento da carga Ã— N sem

```
rodada	lado	p50	p95	máx	>250ms	quadros>150ms	jogável_s
1	C	11.71	16.0	108.59	0	[]	85.2
2	N	12.52	16.79	1077.57	1	[1078]	86.8
3	N	12.2	16.43	1274.33	2	[1274, 1178]	87.3
4	C	14.39	18.68	185.42	0	[185]	88.4
5	C	12.96	17.68	2416.38	2	[2416, 1209]	85.2
6	N	13.78	19.09	1160.78	1	[1161, 173]	85.7
7	N	12.88	17.43	1152.39	1	[1152]	84.7
8	C	12.97	17.25	143.5	0	[]	83.7
lado C: 4 rodadas, quadro > 700 ms em 1
lado N: 4 rodadas, quadro > 700 ms em 4
```

## 17Âª â€” A carga some Ã— B carga queima

```
rodada	lado	p50	p95	máx	>250ms	quadros>150ms	jogável_s
1	A	11.31	15.59	1099.48	1	[1099]	80.1
2	B	12.42	17.35	127.73	0	[]	84.8
3	B	13.0	17.51	127.06	0	[]	85.3
4	A	13.0	17.3	1049.89	1	[1050]	85.2
5	A	12.48	17.73	133.18	0	[]	84.2
6	B	12.66	17.46	1047.17	1	[1047]	85.6
7	B	12.09	16.79	179.93	0	[180]	83.4
8	A	12.12	16.69	1233.11	1	[1233]	83.7
lado A: 4 rodadas, quadro > 700 ms em 3
lado B: 4 rodadas, quadro > 700 ms em 1
```

## Picos por tipo (cold_ab_spikes.py)

```
# perf-q09-20261027
stalls-20261027-020858.log | draw 1019 ms t=120 carcaças=2 nós+-1; draw 1009 ms t=121 carcaças=2 nós+0
stalls-20261027-021202.log | sem pico
stalls-20261027-021511.log | draw 1233 ms t=170 carcaças=1 nós+0
stalls-20261027-021818.log | draw 1083 ms t=142 carcaças=4 nós+0; draw 1164 ms t=169 carcaças=5 nós+17
stalls-20261027-022125.log | draw 1096 ms t=145 carcaças=2 nós+17
stalls-20261027-022431.log | sem pico
stalls-20261027-022739.log | sem pico
stalls-20261027-023046.log | sem pico
stalls-20261027-023414.log | draw 1130 ms t=171 carcaças=1 nós+0
stalls-20261027-023727.log | sem pico
stalls-20261027-024036.log | sem pico
stalls-20261027-024345.log | sem pico
# perf-q09b-20261027
stalls-20261027-024907.log | surface 1155 ms t=99 carcaças=0 nós+0
stalls-20261027-025216.log | sem pico
stalls-20261027-025523.log | draw 1228 ms t=158 carcaças=1 nós+1
stalls-20261027-025831.log | sem pico
stalls-20261027-030138.log | sem pico
stalls-20261027-030446.log | draw 1155 ms t=120 carcaças=1 nós+122
stalls-20261027-030754.log | surface 1421 ms t=98 carcaças=0 nós+0; draw 1155 ms t=114 carcaças=1 nós+0; draw 1082 ms t=126 carcaças=1 nós+0; draw 1114 ms t=150 carcaças=1 nós+0
stalls-20261027-031101.log | sem pico
# perf-q09c-20261027
stalls-20261027-031727.log | sem pico
stalls-20261027-032036.log | draw 1077 ms t=159 carcaças=2 nós+0
stalls-20261027-032343.log | draw 1178 ms t=126 carcaças=2 nós+0; draw 1278 ms t=139 carcaças=2 nós+17
stalls-20261027-032652.log | sem pico
stalls-20261027-033001.log | surface 1212 ms t=121 carcaças=2 nós+17; draw 2417 ms t=168 carcaças=4 nós+0
stalls-20261027-033310.log | draw 1161 ms t=137 carcaças=2 nós+0
stalls-20261027-033618.log | draw 1152 ms t=158 carcaças=1 nós+0
stalls-20261027-033924.log | sem pico
# perf-q09d-20261027
stalls-20261027-034932.log | surface 1102 ms t=117 carcaças=1 nós+25
stalls-20261027-035236.log | sem pico
stalls-20261027-035542.log | sem pico
stalls-20261027-035849.log | draw 1053 ms t=169 carcaças=3 nós+17
stalls-20261027-040155.log | sem pico
stalls-20261027-040502.log | draw 1050 ms t=114 carcaças=1 nós+17
stalls-20261027-040810.log | sem pico
stalls-20261027-041117.log | surface 1233 ms t=109 carcaças=2 nós+-48
```



Quadros com pipeline `draw` ou `surface` nova depois da cortina, 4 sessÃµes frias com `GETECO_PIPELINE_PROBE=sig` (export `artifacts/perf-q09-20261027`). `rodadas` = em quantas das 4 a combinaÃ§Ã£o apareceu; `t` em segundos desde o inÃ­cio do processo.

- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | bor_building_patrol_court_north/harbor_building_patrol_court_north/@/Dressing_light_ffe2b5 | malha=CylinderMesh: | material: emission_enabled=true
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /harbor_building_patrol_court_north/harbor_building_patrol_court_north/@/Envelope_WorkDesk | malha=BoxMesh: | material: 
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/Dante/Visual/dante/Armature/Skeleton3D/Mesh0 | malha=ArrayMesh: | material: shader=res://assets/outfits/meshy_dante_outfit.gdshader
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/@/CombatEffects/@ | malha=BoxMesh: | material: vertex_color_use_as_albedo=true
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/@/CombatEffects/@ | malha=ArrayMesh: | material: transparency=1 blend_mode=1 cull_mode=2 depth_draw_mode=2 shading_mode=0 vertex_color_use_as_albedo=true
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/HarborNativeRegion/Chunk/AnchorTable1/TableTop | malha=CylinderMesh: | material: cull_mode=2
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/HarborNativeRegion/Chunk/AnchorTable1/TableFoot | malha=BoxMesh: | material: cull_mode=2
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/HarborNativeRegion/Chunk/NorthFrontage3/Visuals/CorniceDentils | malha=ArrayMesh: | material: vertex_color_use_as_albedo=true vertex_color_is_srgb=true albedo_texture
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/HarborNativeRegion/Chunk/HarborRoad_202932 | malha=ArrayMesh: | material: shader=res://world/urban_detail/coastal_wet_asphalt.gdshader
- [specialization,surface] rodadas=4 t=[82.4, 78.6, 78.5, 78.7] | /root/World3D/HarborNativeRegion/TunnelCutawayPrimer | malha=BoxMesh: | material: transparency=1 depth_draw_mode=2
- [surface] rodadas=1 t=[85.1] | /root/World3D/@/Coupe/Body | malha=res://assets/fleet/redesigned/courier_van.scn | material: vertex_color_use_as_albedo=true vertex_color_is_srgb=true detail_enabled=true detail_uv_layer=1 uv2_triplanar=true
- [surface] rodadas=4 t=[85.1, 81.3, 81.2, 81.4] | /root/World3D/@/Coupe/Body | malha=res://assets/fleet/redesigned/courier_van.scn | material: transparency=1 cull_mode=2 vertex_color_use_as_albedo=true vertex_color_is_srgb=true
- [surface] rodadas=4 t=[85.1, 81.3, 81.2, 81.4] | /root/WorldSkidmarkBudget/SurfaceAlignedWorldTireMarks | malha=ArrayMesh: | material: transparency=1 cull_mode=2 shading_mode=0 vertex_color_use_as_albedo=true
- [specialization,surface] rodadas=4 t=[99.5, 95.4, 95.3, 95.8] | /root/World3D/PlayerCoupe/Coupe/Shell | malha=res://assets/fleet/breakaway/sport_coupe.scn | material: vertex_color_use_as_albedo=true next_pass=shader=res://gameplay/vehicle_effects/VehicleBodyRain.gdshader
- [specialization,surface] rodadas=4 t=[99.5, 95.4, 95.3, 95.8] | /root/World3D/PlayerCoupe/Coupe/HeadlightL | malha=res://assets/fleet/breakaway/sport_coupe.scn | material: vertex_color_use_as_albedo=true emission_enabled=true
- [specialization,surface] rodadas=4 t=[99.5, 95.4, 95.3, 95.8] | /root/World3D/@/@/LightningBolt/Core | malha=ImmediateMesh: | material: transparency=1 cull_mode=2 depth_draw_mode=2 shading_mode=0 emission_enabled=true disable_receive_shadows=true
- [specialization,surface] rodadas=4 t=[99.5, 95.4, 95.3, 95.8] | /root/World3D/HarborNativeRegion/Chunk/PatrolCourtNorth/BuildingAccess/ParcelDetail1 | malha=QuadMesh: | material: transparency=1 depth_draw_mode=2 albedo_texture
- [specialization,surface] rodadas=4 t=[99.5, 95.4, 95.3, 95.8] | /root/World3D/@/Coupe/WindshieldRain/Glass | malha=ArrayMesh: | material: shader=res://gameplay/vehicle_effects/VehicleWindshieldRain.gdshader
- [specialization,surface] rodadas=1 t=[141.3] | /root/World3D/@/Coupe/Body | malha=res://assets/fleet/breakaway/metro_hatch.scn | material: emission_enabled=true emission_operator=1 uv1_triplanar=true albedo_texture emission_texture
- [specialization,surface] rodadas=1 t=[141.3] | /root/World3D/@/Coupe/Body | malha=res://assets/fleet/breakaway/metro_hatch.scn | material: transparency=1
- [specialization,surface] rodadas=1 t=[141.3] | /root/World3D/@/Coupe/DriverDoorPresentation/DriverDoorL/Fittings | malha=ArrayMesh: | material: emission_enabled=true emission_operator=1 uv1_triplanar=true albedo_texture emission_texture
- [draw,specialization] rodadas=1 t=[170.5] | /root/World3D/@/Coupe/BedLoad | malha=ArrayMesh: | material: emission_enabled=true emission_operator=1 uv1_triplanar=true albedo_texture emission_texture
- [draw,specialization] rodadas=1 t=[170.5] | /root/World3D/HarborNativeRegion/Chunk/@/@ | malha=res://assets/city_props/wave3_sinal.glb | material: vertex_color_use_as_albedo=true vertex_color_is_srgb=true
- [draw,specialization] rodadas=1 t=[170.5] | /root/World3D/HarborNativeRegion/Chunk/@/@ | malha=SphereMesh: | material: 
- [surface] rodadas=1 t=[81.3] | /root/World3D/@/Coupe/Body | malha=res://assets/fleet/redesigned/courier_van.scn | material: vertex_color_use_as_albedo=true vertex_color_is_srgb=true detail_uv_layer=1 uv2_triplanar=true
- [specialization,surface] rodadas=3 t=[95.4, 95.3, 95.8] | /root/World3D/@/Coupe/Body | malha=res://assets/fleet/breakaway/police_cruiser.scn | material: emission_enabled=true emission_operator=1 uv1_triplanar=true albedo_texture emission_texture
- [specialization,surface] rodadas=3 t=[95.4, 95.3, 95.8] | /root/World3D/@/Coupe/Body | malha=res://assets/fleet/breakaway/police_cruiser.scn | material: transparency=1
