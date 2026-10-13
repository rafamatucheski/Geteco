# Análise das rodadas do oeste

Aquecimento excluído. Spans incluem todos os quadros de medição, inclusive zeros; valores em ms/quadro.
Pais e filhos são inclusivos e não podem ser somados. GPU/CPU de viewport são amostras assíncronas.

Comparações usam a mediana dos percentis das rodadas; a amplitude baseline + variante define a variação conservadora.
Duas repetições estimam ruído, sem constituir teste estatístico de significância.

| Rodada | Configuração | Quadros | Duração s | FPS | p50 ms | p95 ms | p99 ms | >33,3 | >66,7 | Erros runtime | Estado |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| base_1 | baseline | 1043 | 57.6 | 18.1 | 34.437 | 169.761 | 230.121 | 558 | 193 | 0 | sem erros registrados |
| base_2 | baseline | 1943 | 47.4 | 41.0 | 19.290 | 47.293 | 84.197 | 266 | 38 | 0 | sem erros registrados |
| instrumentation0_1 | instrumentation0 | 1706 | 47.5 | 35.9 | 24.350 | 53.598 | 82.746 | 336 | 39 | 0 | sem erros registrados |
| instrumentation0_2 | instrumentation0 | 1630 | 47.6 | 34.2 | 25.441 | 58.471 | 94.189 | 373 | 48 | 1 | inválida |
| no_density_1 | no_density | 1572 | 47.4 | 33.2 | 27.388 | 60.223 | 82.830 | 401 | 53 | 0 | sem erros registrados |
| no_density_2 | no_density | 1514 | 47.8 | 31.7 | 27.728 | 79.133 | 108.178 | 351 | 102 | 0 | sem erros registrados |
| no_roadside_parking_1 | no_roadside_parking | 1168 | 58.5 | 20.0 | 27.597 | 179.730 | 218.517 | 407 | 233 | 0 | sem erros registrados |
| no_roadside_parking_2 | no_roadside_parking | 1684 | 48.0 | 35.1 | 23.673 | 56.591 | 119.840 | 329 | 63 | 0 | sem erros registrados |
| no_traffic_1 | no_traffic | 3477 | 47.3 | 73.6 | 12.243 | 26.772 | 34.949 | 45 | 2 | 0 | sem erros registrados |
| no_traffic_2 | no_traffic | 3150 | 47.3 | 66.7 | 14.474 | 23.577 | 35.340 | 40 | 0 | 0 | sem erros registrados |
| no_traffic_yield_1 | no_traffic_yield | 1267 | 54.3 | 23.4 | 25.306 | 146.083 | 196.024 | 379 | 222 | 0 | sem erros registrados |
| no_traffic_yield_2 | no_traffic_yield | 787 | 52.4 | 15.0 | 53.818 | 144.897 | 197.998 | 659 | 281 | 0 | sem erros registrados |
| population0_1 | population0 | 3107 | 47.3 | 65.7 | 14.993 | 24.287 | 31.026 | 23 | 0 | 0 | sem erros registrados |
| population0_2 | population0 | 2428 | 47.3 | 51.3 | 17.006 | 35.836 | 48.984 | 168 | 4 | 0 | sem erros registrados |
| session_profile0_1 | session_profile0 | 820 | 52.7 | 15.6 | 48.294 | 146.015 | 171.969 | 609 | 296 | 2 | inválida |
| session_profile0_2 | session_profile0 | 2090 | 47.8 | 43.8 | 18.011 | 46.279 | 97.049 | 212 | 44 | 0 | sem erros registrados |

| Rodada | Focado % | Sem foco % | Pausado quadros | Resolução | Renderer | VSync | Limite FPS |
|---|---:|---:|---:|---|---|---:|---:|
| base_1 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| base_2 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| instrumentation0_1 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| instrumentation0_2 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_density_1 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_density_2 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_roadside_parking_1 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_roadside_parking_2 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_traffic_1 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_traffic_2 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_traffic_yield_1 | 98.3 | 1.7 | 0 | [3440, 1440] | mobile | 0 | 0 |
| no_traffic_yield_2 | 0.0 | 100.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| population0_1 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| population0_2 | 100.0 | 0.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| session_profile0_1 | 0.0 | 100.0 | 0 | [3440, 1440] | mobile | 0 | 0 |
| session_profile0_2 | 14.1 | 85.9 | 0 | [3440, 1440] | mobile | 0 | 0 |

Quadros sem foco são mantidos e identificados; eventual limitação do driver em segundo plano não foi eliminada por essa tabela.

## Efeito de uma variável

| Configuração | Repetições B/V | Redução p50 ms | Variação p50 ms | Critério p50 | Redução p95 ms | Variação p95 ms | Critério p95 |
|---|---:|---:|---:|---|---:|---:|---|
| instrumentation0 | 2/1 | 2.513 | 15.147 | repetição insuficiente | 54.929 | 122.468 | repetição insuficiente |
| no_density | 2/2 | -0.695 | 15.487 | efeito não separado da variação | 38.849 | 141.378 | efeito não separado da variação |
| no_roadside_parking | 2/2 | 1.229 | 19.071 | efeito não separado da variação | -9.633 | 245.607 | efeito não separado da variação |
| no_traffic | 2/2 | 13.505 | 17.378 | efeito não separado da variação | 83.352 | 125.663 | efeito não separado da variação |
| no_traffic_yield | 2/2 | -12.698 | 43.659 | foco não equivalente | -36.963 | 123.654 | foco não equivalente |
| population0 | 2/2 | 10.864 | 17.160 | efeito não separado da variação | 78.466 | 134.017 | efeito não separado da variação |
| session_profile0 | 2/1 | 8.852 | 15.147 | foco não equivalente | 62.248 | 122.468 | foco não equivalente |

Condições no_traffic_yield: `{"focused_percent": {"base_1": 100.0, "base_2": 100.0, "no_traffic_yield_1": 98.26361483820047, "no_traffic_yield_2": 0.0}}`. Rodadas sem erro permanecem nas tabelas; esse contraste não tem equivalência causal.

Condições session_profile0: `{"focused_percent": {"base_1": 100.0, "base_2": 100.0, "session_profile0_2": 14.114832535885167}}`. Rodadas sem erro permanecem nas tabelas; esse contraste não tem equivalência causal.

## base_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\base_1.json`

Bracket válido em 1043 quadros; inválido em 0. Passos físicos por quadro: `{"1": 195, "2": 466, "3": 157, "4": 49, "5": 13, "6": 8, "7": 7, "8": 148}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1043 | 34.504 | 17.526 | 124.625 |
| process_callback_ms | 1043 | 10.593 | 8.272 | 24.569 |
| process_to_deferred_ms | 1043 | 0.643 | 0.660 | 1.163 |
| deferred_to_render_pre_ms | 1043 | 0.457 | 0.328 | 1.214 |
| render_bracket_ms | 1043 | 4.331 | 4.028 | 6.520 |
| post_draw_to_physics_ms | 1043 | 1.419 | 0.999 | 3.796 |
| pre_process_gap_ms | 1043 | 4.745 | 3.288 | 12.793 |
| telemetry_ms | 1043 | 0.266 | 0.238 | 0.434 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 14.832 | 7.636 | 56.036 |
| actor.physics | 5.975 | 3.340 | 21.222 |
| west.telemetry.profile_process | 1.646 | 1.609 | 4.567 |
| vehicle_tires.redraw_marks | 1.026 | 0.696 | 2.786 |
| gameplay.physics | 0.944 | 0.531 | 3.151 |
| west.world.process | 0.837 | 0.415 | 3.108 |
| urban.physics | 0.801 | 0.590 | 2.079 |
| terminal.physics | 0.737 | 0.410 | 2.551 |
| reflection.process | 0.553 | 0.026 | 3.219 |
| west.audio.nearby_process | 0.221 | 0.127 | 0.524 |
| west.camera.process | 0.180 | 0.169 | 0.275 |
| west.street.physics | 0.152 | 0.016 | 0.704 |
| west.audio.world_process | 0.110 | 0.063 | 0.277 |
| west.traffic_yield.physics | 0.082 | 0.045 | 0.285 |
| west.parking.physics | 0.038 | 0.021 | 0.127 |
| west.audio.weather_process | 0.016 | 0.015 | 0.024 |
| west.region.process | 0.010 | 0.007 | 0.012 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.48184659635666344, "system_profile_callback": 1.6116232023010546}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 3140; p50 9.861 ms/passo e p95 19.645 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 1 | 195 | 19.783 | 24.691 | 7.950 | 9.574 |
| 2 | 466 | 32.107 | 39.953 | 8.300 | 10.017 |
| 3 | 157 | 46.635 | 58.419 | 9.155 | 11.307 |
| 4 | 49 | 62.376 | 79.280 | 9.850 | 12.895 |
| 5 | 13 | 76.162 | 107.725 | 10.234 | 14.758 |
| 6 | 8 | 101.740 | 141.771 | 10.922 | 17.308 |
| 7 | 7 | 115.394 | 133.146 | 11.057 | 14.162 |
| 8 | 148 | 157.496 | 237.482 | 14.470 | 21.754 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 4.927 | 3.688 | 7.135 |
| actor.physics | 1.985 | 1.644 | 2.726 |
| vehicle.drive | 1.319 | 1.014 | 1.885 |
| vehicle.street_pre | 0.935 | 0.671 | 1.417 |
| vehicle.effects | 0.801 | 0.616 | 1.224 |
| actor.move_and_slide | 0.732 | 0.637 | 1.043 |
| actor.step | 0.584 | 0.478 | 0.822 |
| vehicle.effects.tires | 0.528 | 0.413 | 0.848 |
| vehicle.move_and_slide | 0.482 | 0.374 | 0.751 |
| street.pre.props | 0.441 | 0.337 | 0.653 |
| west.vehicle.junction_gate | 0.423 | 0.311 | 0.647 |
| vehicle_tires.contacts | 0.376 | 0.297 | 0.603 |
| street.pre.people | 0.314 | 0.211 | 0.534 |
| gameplay.physics | 0.314 | 0.258 | 0.406 |
| street.pre.props.query | 0.268 | 0.209 | 0.397 |
| urban.physics | 0.266 | 0.269 | 0.415 |
| terminal.physics | 0.245 | 0.202 | 0.334 |
| vehicle.street_post | 0.208 | 0.136 | 0.274 |
| vehicle.lod | 0.163 | 0.130 | 0.218 |
| west.vehicle.escape | 0.140 | 0.109 | 0.191 |
| actor.steering | 0.124 | 0.101 | 0.165 |
| west.vehicle.can_rotate | 0.100 | 0.071 | 0.154 |
| west.vehicle.obstacle_ahead | 0.096 | 0.074 | 0.141 |
| west.vehicle.route_projection | 0.091 | 0.071 | 0.131 |
| vehicle.effects.powertrain | 0.089 | 0.068 | 0.137 |
| actor.pose | 0.077 | 0.059 | 0.108 |
| vehicle.wheels | 0.066 | 0.052 | 0.096 |
| vehicle.resting | 0.065 | 0.051 | 0.086 |
| street.post.contacts | 0.056 | 0.021 | 0.045 |
| vehicle.contacts | 0.056 | 0.037 | 0.075 |
| west.street.physics | 0.051 | 0.007 | 0.208 |
| vehicle.effects.impact | 0.048 | 0.035 | 0.076 |
| street.pre.crush | 0.047 | 0.034 | 0.070 |
| west.street.watch_people | 0.038 | 0.000 | 0.196 |
| vehicle.wreck_lifetime | 0.029 | 0.023 | 0.037 |
| west.traffic_yield.physics | 0.027 | 0.022 | 0.038 |
| street.pre.people.cast | 0.027 | 0.009 | 0.072 |
| street.post.slide | 0.018 | 0.013 | 0.029 |
| street.post.crush | 0.016 | 0.012 | 0.024 |
| west.parking.physics | 0.013 | 0.010 | 0.018 |
| urban.refresh_presence | 0.009 | 0.000 | 0.054 |
| vehicle_tires.surface_emit | 0.008 | 0.000 | 0.028 |
| vehicle_tires.skid_audio | 0.008 | 0.006 | 0.013 |
| west.traffic_yield.hazards | 0.008 | 0.006 | 0.010 |
| street.pre.props.hit | 0.002 | 0.000 | 0.000 |
| west.vehicle.rear_clear | 0.001 | 0.000 | 0.009 |
| street.pre.props.cast | 0.001 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_voice | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 14.832 | 7.636 | 56.036 | 1043 |
| actor.physics | root | None | 5.975 | 3.340 | 21.222 | 1043 |
| vehicle.drive | nested | vehicle.physics | 3.970 | 2.069 | 14.789 | 1043 |
| vehicle.street_pre | nested | vehicle.physics | 2.816 | 1.440 | 11.310 | 1043 |
| vehicle.effects | nested | vehicle.physics | 2.412 | 1.308 | 9.749 | 1043 |
| actor.move_and_slide | nested | actor.physics | 2.203 | 1.333 | 7.879 | 1043 |
| actor.step | nested | actor.physics | 1.759 | 0.974 | 6.210 | 1043 |
| west.telemetry.profile_process | root | None | 1.646 | 1.609 | 4.567 | 1043 |
| vehicle.effects.tires | nested | vehicle.effects | 1.590 | 0.882 | 6.672 | 1043 |
| vehicle.move_and_slide | nested | vehicle.physics | 1.453 | 0.808 | 5.929 | 1043 |
| street.pre.props | nested | vehicle.street_pre | 1.327 | 0.702 | 5.125 | 1043 |
| west.vehicle.junction_gate | nested | vehicle.drive | 1.274 | 0.638 | 5.158 | 1043 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 1.132 | 0.630 | 4.737 | 1031 |
| vehicle_tires.redraw_marks | root | None | 1.026 | 0.696 | 2.786 | 1026 |
| street.pre.people | nested | vehicle.street_pre | 0.947 | 0.457 | 4.165 | 1043 |
| gameplay.physics | root | None | 0.944 | 0.531 | 3.151 | 1043 |
| west.world.process | root | None | 0.837 | 0.415 | 3.108 | 1043 |
| street.pre.props.query | nested | street.pre.props | 0.807 | 0.436 | 3.080 | 1043 |
| urban.physics | root | None | 0.801 | 0.590 | 2.079 | 1043 |
| terminal.physics | root | None | 0.737 | 0.410 | 2.551 | 1043 |
| vehicle.street_post | nested | vehicle.physics | 0.627 | 0.280 | 2.176 | 1043 |
| reflection.process | root | None | 0.553 | 0.026 | 3.219 | 1043 |
| vehicle.lod | nested | vehicle.physics | 0.491 | 0.263 | 1.701 | 1043 |
| west.vehicle.escape | nested | vehicle.drive | 0.420 | 0.225 | 1.514 | 1043 |
| actor.steering | nested | actor.physics | 0.373 | 0.204 | 1.274 | 1043 |
| west.world.population_job | nested | west.world.process | 0.365 | 0.090 | 2.794 | 1043 |
| reflection.dynamic | nested | reflection.process | 0.316 | 0.000 | 1.992 | 1043 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.301 | 0.153 | 1.225 | 1043 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.295 | 0.206 | 0.785 | 1026 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.288 | 0.156 | 1.061 | 1041 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.273 | 0.154 | 1.011 | 1043 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.269 | 0.142 | 1.057 | 1043 |
| west.world.residency | nested | west.world.process | 0.259 | 0.237 | 0.423 | 1043 |
| actor.pose | nested | actor.physics | 0.232 | 0.120 | 0.848 | 1043 |
| west.audio.nearby_process | root | None | 0.221 | 0.127 | 0.524 | 1043 |
| vehicle.wheels | nested | vehicle.physics | 0.198 | 0.111 | 0.751 | 1043 |
| vehicle.resting | nested | vehicle.physics | 0.196 | 0.104 | 0.669 | 1043 |
| west.camera.process | root | None | 0.180 | 0.169 | 0.275 | 1043 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.176 | 0.000 | 1.674 | 155 |
| street.post.contacts | nested | vehicle.street_post | 0.170 | 0.043 | 0.352 | 1043 |
| vehicle.contacts | nested | vehicle.physics | 0.168 | 0.077 | 0.600 | 1043 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.166 | 0.000 | 1.591 | 88 |
| west.street.physics | root | None | 0.152 | 0.016 | 0.704 | 1043 |
| vehicle.effects.impact | nested | vehicle.effects | 0.145 | 0.074 | 0.574 | 1043 |
| street.pre.crush | nested | vehicle.street_pre | 0.143 | 0.073 | 0.553 | 1043 |
| west.street.watch_people | nested | west.street.physics | 0.114 | 0.000 | 0.566 | 241 |
| reflection.batch | nested | reflection.process | 0.112 | 0.000 | 1.101 | 1043 |
| west.audio.world_process | root | None | 0.110 | 0.063 | 0.277 | 1043 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.104 | 0.000 | 0.093 | 154 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.100 | 0.000 | 0.338 | 420 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.094 | 0.056 | 0.311 | 1043 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.094 | 0.000 | 0.000 | 45 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.086 | 0.046 | 0.295 | 1043 |
| west.traffic_yield.physics | root | None | 0.082 | 0.045 | 0.285 | 1043 |
| street.pre.people.cast | nested | street.pre.people | 0.082 | 0.022 | 0.357 | 554 |
| street.crash | inclusive_unknown | None | 0.081 | 0.000 | 0.000 | 7 |
| street.post.slide | nested | vehicle.street_post | 0.055 | 0.028 | 0.216 | 1043 |
| street.post.crush | nested | vehicle.street_post | 0.047 | 0.024 | 0.187 | 1043 |
| west.audio.ambience | nested | west.audio.world_process | 0.044 | 0.028 | 0.125 | 1043 |
| street.crash.damage_other | nested | street.crash | 0.041 | 0.000 | 0.000 | 7 |
| west.parking.physics | root | None | 0.038 | 0.021 | 0.127 | 1043 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.036 | 0.000 | 0.033 | 308 |
| street.crash.damage_self | nested | street.crash | 0.034 | 0.000 | 0.000 | 7 |
| west.camera.cutaway | nested | west.camera.process | 0.031 | 0.028 | 0.046 | 1043 |
| urban.refresh_presence | nested | urban.physics | 0.029 | 0.000 | 0.182 | 174 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.024 | 0.000 | 0.132 | 283 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.024 | 0.014 | 0.099 | 1031 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.023 | 0.012 | 0.079 | 1043 |
| reflection.registration | nested | reflection.process | 0.019 | 0.001 | 0.132 | 1043 |
| west.camera.terrain_offset | nested | west.camera.process | 0.017 | 0.015 | 0.025 | 1043 |
| west.audio.weather_process | root | None | 0.016 | 0.015 | 0.024 | 1043 |
| west.router.plan | nested | multiple_contexts | 0.016 | 0.000 | 0.000 | 2 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.015 | 0.013 | 0.023 | 1043 |
| west.traffic.route_near | nested | multiple_contexts | 0.012 | 0.000 | 0.000 | 22 |
| west.region.process | root | None | 0.010 | 0.007 | 0.012 | 1043 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.010 | 0.009 | 0.016 | 1043 |
| street.glass | inclusive_unknown | None | 0.008 | 0.000 | 0.000 | 6 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.007 | 0.000 | 0.000 | 5 |
| street.pre.props.hit | nested | street.pre.props | 0.006 | 0.000 | 0.000 | 31 |
| street.scatter | inclusive_unknown | None | 0.006 | 0.000 | 0.000 | 6 |
| street.scatter.geometry | nested | street.scatter | 0.005 | 0.000 | 0.000 | 6 |
| west.world.logical_region | nested | west.world.process | 0.005 | 0.004 | 0.008 | 1043 |
| west.audio.radio | nested | west.audio.world_process | 0.005 | 0.004 | 0.007 | 1043 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 3 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.003 | 0.000 | 0.028 | 68 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 3 |
| retire.drain | inclusive_unknown | None | 0.003 | 0.000 | 0.000 | 2 |
| ground_blood.allocate | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 11 |
| street.pre.props.cast | nested | street.pre.props | 0.002 | 0.000 | 0.000 | 44 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 22 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| street.glass.resources | nested | street.glass | 0.001 | 0.000 | 0.000 | 6 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 30 |
| street.slide.rotate | nested | street.post.slide | 0.001 | 0.000 | 0.000 | 24 |
| west.router.csharp.build | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 4 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 11 |
| street.glass.attach | nested | street.glass | 0.000 | 0.000 | 0.000 | 6 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 7 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 6 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 6 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 30 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 6 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| vehicle_tires.skid_voice | nested | vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 30 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 5.312 ms; p95 39.645 ms (1043 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 5.200 ms; p95 15.960 ms (1043 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## base_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\base_2.json`

Bracket válido em 1943 quadros; inválido em 0. Passos físicos por quadro: `{"0": 22, "1": 1243, "2": 530, "3": 97, "4": 24, "5": 14, "6": 7, "7": 5, "8": 1}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1943 | 11.406 | 7.565 | 27.294 |
| process_callback_ms | 1943 | 6.336 | 5.373 | 12.012 |
| process_to_deferred_ms | 1943 | 0.429 | 0.501 | 0.780 |
| deferred_to_render_pre_ms | 1943 | 0.321 | 0.260 | 0.647 |
| render_bracket_ms | 1943 | 3.667 | 3.604 | 4.538 |
| post_draw_to_physics_ms | 1943 | 0.767 | 0.728 | 1.200 |
| pre_process_gap_ms | 1943 | 2.240 | 1.886 | 3.905 |
| telemetry_ms | 1943 | 0.208 | 0.197 | 0.289 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 4.707 | 3.264 | 11.722 |
| actor.physics | 2.193 | 1.527 | 5.424 |
| west.telemetry.profile_process | 0.608 | 0.186 | 2.149 |
| vehicle_tires.redraw_marks | 0.526 | 0.389 | 1.331 |
| west.world.process | 0.479 | 0.292 | 1.155 |
| reflection.process | 0.388 | 0.021 | 2.252 |
| urban.physics | 0.354 | 0.220 | 0.934 |
| gameplay.physics | 0.332 | 0.214 | 0.751 |
| terminal.physics | 0.279 | 0.184 | 0.661 |
| west.camera.process | 0.152 | 0.142 | 0.221 |
| west.audio.nearby_process | 0.148 | 0.109 | 0.311 |
| west.audio.world_process | 0.075 | 0.054 | 0.201 |
| west.street.physics | 0.054 | 0.007 | 0.393 |
| west.traffic_yield.physics | 0.030 | 0.020 | 0.064 |
| west.parking.physics | 0.014 | 0.009 | 0.033 |
| west.audio.weather_process | 0.014 | 0.013 | 0.017 |
| west.region.process | 0.007 | 0.006 | 0.008 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.18600205867215644, "system_profile_callback": 0.5834148224395266}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2845; p50 7.492 ms/passo e p95 10.850 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 22 | 8.364 | 10.616 | — | — |
| 1 | 1243 | 17.710 | 22.334 | 6.764 | 8.729 |
| 2 | 530 | 29.591 | 38.332 | 7.731 | 9.966 |
| 3 | 97 | 46.597 | 58.889 | 9.046 | 11.788 |
| 4 | 24 | 65.880 | 90.887 | 9.793 | 14.141 |
| 5 | 14 | 80.224 | 129.438 | 10.188 | 15.915 |
| 6 | 7 | 92.364 | 107.213 | 9.378 | 12.308 |
| 7 | 5 | 103.070 | 118.681 | 10.262 | 11.776 |
| 8 | 1 | 111.539 | 111.539 | 10.016 | 10.016 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 3.215 | 2.986 | 4.317 |
| actor.physics | 1.498 | 1.391 | 2.062 |
| vehicle.drive | 0.976 | 0.913 | 1.273 |
| actor.move_and_slide | 0.566 | 0.511 | 0.874 |
| vehicle.street_pre | 0.530 | 0.469 | 0.812 |
| vehicle.effects | 0.490 | 0.449 | 0.795 |
| actor.step | 0.423 | 0.391 | 0.592 |
| vehicle.effects.tires | 0.326 | 0.305 | 0.577 |
| west.vehicle.junction_gate | 0.316 | 0.303 | 0.439 |
| vehicle.move_and_slide | 0.292 | 0.267 | 0.464 |
| street.pre.props | 0.251 | 0.216 | 0.400 |
| urban.physics | 0.242 | 0.210 | 0.391 |
| vehicle_tires.contacts | 0.230 | 0.213 | 0.410 |
| gameplay.physics | 0.227 | 0.209 | 0.279 |
| terminal.physics | 0.191 | 0.176 | 0.253 |
| street.pre.people | 0.175 | 0.153 | 0.270 |
| street.pre.props.query | 0.153 | 0.134 | 0.248 |
| vehicle.lod | 0.118 | 0.108 | 0.144 |
| west.vehicle.escape | 0.114 | 0.104 | 0.162 |
| vehicle.street_post | 0.108 | 0.096 | 0.157 |
| actor.steering | 0.097 | 0.092 | 0.125 |
| west.vehicle.obstacle_ahead | 0.066 | 0.061 | 0.108 |
| west.vehicle.route_projection | 0.059 | 0.054 | 0.088 |
| actor.pose | 0.057 | 0.053 | 0.074 |
| vehicle.effects.powertrain | 0.054 | 0.047 | 0.091 |
| west.vehicle.can_rotate | 0.051 | 0.044 | 0.081 |
| vehicle.resting | 0.045 | 0.042 | 0.055 |
| vehicle.wheels | 0.040 | 0.036 | 0.062 |
| west.street.physics | 0.037 | 0.006 | 0.323 |
| west.street.watch_people | 0.029 | 0.000 | 0.311 |
| vehicle.contacts | 0.028 | 0.026 | 0.043 |
| vehicle.effects.impact | 0.028 | 0.025 | 0.042 |
| street.pre.crush | 0.027 | 0.024 | 0.042 |
| west.traffic_yield.physics | 0.020 | 0.019 | 0.026 |
| vehicle.wreck_lifetime | 0.020 | 0.019 | 0.025 |
| street.post.contacts | 0.020 | 0.015 | 0.025 |
| street.pre.people.cast | 0.010 | 0.000 | 0.038 |
| street.post.slide | 0.010 | 0.009 | 0.015 |
| west.parking.physics | 0.010 | 0.008 | 0.013 |
| street.post.crush | 0.009 | 0.008 | 0.014 |
| urban.refresh_presence | 0.007 | 0.000 | 0.059 |
| west.vehicle.rear_clear | 0.006 | 0.000 | 0.033 |
| vehicle_tires.surface_emit | 0.006 | 0.000 | 0.035 |
| west.traffic_yield.hazards | 0.006 | 0.005 | 0.007 |
| vehicle_tires.skid_audio | 0.005 | 0.004 | 0.009 |
| street.pre.props.hit | 0.003 | 0.000 | 0.000 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 4.707 | 3.264 | 11.722 | 1921 |
| actor.physics | root | None | 2.193 | 1.527 | 5.424 | 1921 |
| vehicle.drive | nested | vehicle.physics | 1.430 | 1.017 | 3.304 | 1921 |
| actor.move_and_slide | nested | actor.physics | 0.829 | 0.587 | 2.062 | 1921 |
| vehicle.street_pre | nested | vehicle.physics | 0.776 | 0.526 | 2.036 | 1903 |
| vehicle.effects | nested | vehicle.physics | 0.717 | 0.528 | 1.932 | 1903 |
| actor.step | nested | actor.physics | 0.619 | 0.438 | 1.523 | 1921 |
| west.telemetry.profile_process | root | None | 0.608 | 0.186 | 2.149 | 1943 |
| vehicle_tires.redraw_marks | root | None | 0.526 | 0.389 | 1.331 | 1702 |
| west.world.process | root | None | 0.479 | 0.292 | 1.155 | 1943 |
| vehicle.effects.tires | nested | vehicle.effects | 0.477 | 0.354 | 1.314 | 1903 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.462 | 0.350 | 0.985 | 1921 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.428 | 0.304 | 1.168 | 1903 |
| reflection.process | root | None | 0.388 | 0.021 | 2.252 | 1943 |
| street.pre.props | nested | vehicle.street_pre | 0.367 | 0.248 | 0.954 | 1902 |
| urban.physics | root | None | 0.354 | 0.220 | 0.934 | 1921 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.337 | 0.253 | 0.916 | 1741 |
| gameplay.physics | root | None | 0.332 | 0.214 | 0.751 | 1921 |
| reflection.dynamic | nested | reflection.process | 0.281 | 0.000 | 1.882 | 1943 |
| terminal.physics | root | None | 0.279 | 0.184 | 0.661 | 1921 |
| street.pre.people | nested | vehicle.street_pre | 0.256 | 0.173 | 0.689 | 1902 |
| street.pre.props.query | nested | street.pre.props | 0.224 | 0.153 | 0.587 | 1887 |
| west.world.residency | nested | west.world.process | 0.208 | 0.193 | 0.292 | 1943 |
| vehicle.lod | nested | vehicle.physics | 0.173 | 0.112 | 0.403 | 1921 |
| west.world.population_job | nested | west.world.process | 0.169 | 0.002 | 0.839 | 1943 |
| west.vehicle.escape | nested | vehicle.drive | 0.167 | 0.124 | 0.406 | 1921 |
| vehicle.street_post | nested | vehicle.physics | 0.158 | 0.108 | 0.411 | 1903 |
| west.camera.process | root | None | 0.152 | 0.142 | 0.221 | 1943 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.151 | 0.122 | 0.350 | 1699 |
| west.audio.nearby_process | root | None | 0.148 | 0.109 | 0.311 | 1943 |
| actor.steering | nested | actor.physics | 0.142 | 0.100 | 0.358 | 1921 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.097 | 0.075 | 0.226 | 1906 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.087 | 0.062 | 0.226 | 1921 |
| actor.pose | nested | actor.physics | 0.084 | 0.057 | 0.213 | 1921 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.079 | 0.056 | 0.217 | 1903 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.075 | 0.050 | 0.202 | 1899 |
| west.audio.world_process | root | None | 0.075 | 0.054 | 0.201 | 1943 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.070 | 0.000 | 0.006 | 174 |
| vehicle.resting | nested | vehicle.physics | 0.066 | 0.044 | 0.150 | 1921 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.066 | 0.000 | 0.000 | 79 |
| vehicle.wheels | nested | vehicle.physics | 0.059 | 0.040 | 0.161 | 1903 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.056 | 0.000 | 0.038 | 174 |
| west.street.physics | root | None | 0.054 | 0.007 | 0.393 | 1921 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.050 | 0.000 | 0.000 | 46 |
| west.street.watch_people | nested | west.street.physics | 0.043 | 0.000 | 0.372 | 218 |
| vehicle.contacts | nested | vehicle.physics | 0.042 | 0.028 | 0.114 | 1903 |
| vehicle.effects.impact | nested | vehicle.effects | 0.041 | 0.029 | 0.112 | 1903 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.040 | 0.000 | 0.201 | 414 |
| street.pre.crush | nested | vehicle.street_pre | 0.039 | 0.027 | 0.101 | 1902 |
| reflection.batch | nested | reflection.process | 0.037 | 0.000 | 0.237 | 1943 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.036 | 0.022 | 0.091 | 1921 |
| west.audio.ambience | nested | west.audio.world_process | 0.030 | 0.025 | 0.076 | 1943 |
| west.traffic_yield.physics | root | None | 0.030 | 0.020 | 0.064 | 1921 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.029 | 0.020 | 0.068 | 1921 |
| street.post.contacts | nested | vehicle.street_post | 0.029 | 0.017 | 0.065 | 1903 |
| west.camera.cutaway | nested | west.camera.process | 0.026 | 0.025 | 0.034 | 1943 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.017 | 0.000 | 0.018 | 350 |
| street.pre.people.cast | nested | street.pre.people | 0.015 | 0.000 | 0.073 | 588 |
| street.post.slide | nested | vehicle.street_post | 0.014 | 0.010 | 0.038 | 1903 |
| west.parking.physics | root | None | 0.014 | 0.009 | 0.033 | 1921 |
| west.camera.terrain_offset | nested | west.camera.process | 0.014 | 0.013 | 0.017 | 1943 |
| west.audio.weather_process | root | None | 0.014 | 0.013 | 0.017 | 1943 |
| street.post.crush | nested | vehicle.street_post | 0.014 | 0.009 | 0.037 | 1903 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.013 | 0.012 | 0.016 | 1943 |
| urban.refresh_presence | nested | urban.physics | 0.010 | 0.000 | 0.105 | 158 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.009 | 0.000 | 0.050 | 427 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.008 | 0.000 | 0.043 | 340 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.008 | 0.008 | 0.011 | 1943 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.008 | 0.005 | 0.017 | 1921 |
| reflection.registration | nested | reflection.process | 0.008 | 0.001 | 0.029 | 1943 |
| west.region.process | root | None | 0.007 | 0.006 | 0.008 | 1943 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.007 | 0.005 | 0.019 | 1741 |
| west.traffic.route_near | nested | multiple_contexts | 0.007 | 0.000 | 0.000 | 25 |
| west.router.plan | nested | multiple_contexts | 0.005 | 0.000 | 0.000 | 2 |
| street.crash | inclusive_unknown | None | 0.005 | 0.000 | 0.000 | 1 |
| street.pre.props.hit | nested | street.pre.props | 0.005 | 0.000 | 0.000 | 2 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.005 | 1943 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.003 | 0.005 | 1943 |
| street.crash.damage_other | nested | street.crash | 0.003 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 6 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 4 |
| street.crash.damage_self | nested | street.crash | 0.002 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 3 |
| retire.drain | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 25 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| ground_blood.allocate | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 14 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 14 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.pre.props.cast | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 2 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 1 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 14 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 2.256 ms; p95 8.242 ms (1943 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 3.925 ms; p95 7.822 ms (1943 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## instrumentation0_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\instrumentation0_1.json`

Bracket válido em 1706 quadros; inválido em 0. Passos físicos por quadro: `{"0": 1, "1": 865, "2": 653, "3": 122, "4": 40, "5": 12, "6": 6, "7": 4, "8": 3}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1706 | 13.553 | 9.351 | 30.488 |
| process_callback_ms | 1706 | 7.056 | 6.102 | 13.428 |
| process_to_deferred_ms | 1706 | 0.512 | 0.601 | 0.881 |
| deferred_to_render_pre_ms | 1706 | 0.345 | 0.295 | 0.503 |
| render_bracket_ms | 1706 | 3.993 | 3.877 | 5.057 |
| post_draw_to_physics_ms | 1706 | 0.622 | 0.626 | 1.071 |
| pre_process_gap_ms | 1706 | 2.405 | 2.142 | 4.226 |
| telemetry_ms | 1706 | 0.114 | 0.108 | 0.154 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.23828722157092613, "system_profile_callback": 0.680567409144197}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2845; p50 7.821 ms/passo e p95 11.095 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 1 | 11.624 | 11.624 | — | — |
| 1 | 865 | 18.559 | 23.817 | 6.849 | 8.651 |
| 2 | 653 | 30.023 | 38.873 | 7.963 | 9.819 |
| 3 | 122 | 47.692 | 59.371 | 9.023 | 11.299 |
| 4 | 40 | 61.388 | 97.556 | 9.561 | 15.700 |
| 5 | 12 | 78.223 | 100.406 | 10.635 | 12.976 |
| 6 | 6 | 105.371 | 133.534 | 10.798 | 15.269 |
| 7 | 4 | 98.725 | 114.515 | 10.227 | 11.573 |
| 8 | 3 | 177.810 | 183.523 | 15.208 | 16.494 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|

Residual não calculado: não há garantia de contenção temporal e ausência de sobreposição das raízes.

## instrumentation0_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\instrumentation0_2.json`

Bracket válido em 1630 quadros; inválido em 0. Passos físicos por quadro: `{"0": 1, "1": 788, "2": 599, "3": 160, "4": 52, "5": 15, "6": 5, "7": 5, "8": 5}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1630 | 14.511 | 12.819 | 34.312 |
| process_callback_ms | 1630 | 7.514 | 6.168 | 14.716 |
| process_to_deferred_ms | 1630 | 0.485 | 0.581 | 0.808 |
| deferred_to_render_pre_ms | 1630 | 0.351 | 0.298 | 0.496 |
| render_bracket_ms | 1630 | 3.854 | 3.753 | 4.764 |
| post_draw_to_physics_ms | 1630 | 0.591 | 0.595 | 1.034 |
| pre_process_gap_ms | 1630 | 2.502 | 2.212 | 4.395 |
| telemetry_ms | 1630 | 0.107 | 0.102 | 0.146 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Rodada inválida, excluída dos comparativos: `["runtime_console_errors"]`.


Erros durante execução em `D:\geteco\game\evidence\profile-west-cpu-20261013\instrumentation0_2.console.log`; timings preservados somente como diagnóstico:

- Linha 9: SCRIPT ERROR: Trying to assign invalid previously freed instance.

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.23443865030674846, "system_profile_callback": 0.740622699386503}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2854; p50 7.884 ms/passo e p95 11.366 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 1 | 7.855 | 7.855 | — | — |
| 1 | 788 | 19.048 | 23.009 | 7.296 | 8.766 |
| 2 | 599 | 29.096 | 40.469 | 7.676 | 9.834 |
| 3 | 160 | 48.129 | 60.512 | 9.079 | 11.845 |
| 4 | 52 | 61.317 | 82.912 | 9.332 | 12.898 |
| 5 | 15 | 77.142 | 116.552 | 10.042 | 14.516 |
| 6 | 5 | 94.189 | 136.654 | 9.452 | 15.684 |
| 7 | 5 | 101.729 | 162.114 | 10.476 | 15.540 |
| 8 | 5 | 133.206 | 142.037 | 12.289 | 13.295 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|

Residual não calculado: não há garantia de contenção temporal e ausência de sobreposição das raízes.

## no_density_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_density_1.json`

Bracket válido em 1572 quadros; inválido em 0. Passos físicos por quadro: `{"1": 676, "2": 650, "3": 162, "4": 54, "5": 21, "6": 3, "7": 5, "8": 1}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1572 | 15.499 | 14.501 | 36.867 |
| process_callback_ms | 1572 | 7.579 | 6.677 | 13.413 |
| process_to_deferred_ms | 1572 | 0.473 | 0.554 | 0.738 |
| deferred_to_render_pre_ms | 1572 | 0.325 | 0.272 | 0.474 |
| render_bracket_ms | 1572 | 3.675 | 3.607 | 4.576 |
| post_draw_to_physics_ms | 1572 | 0.712 | 0.702 | 1.116 |
| pre_process_gap_ms | 1572 | 2.610 | 2.438 | 4.612 |
| telemetry_ms | 1572 | 0.209 | 0.199 | 0.288 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 7.098 | 6.157 | 17.850 |
| actor.physics | 2.642 | 2.524 | 5.717 |
| vehicle_tires.redraw_marks | 0.917 | 0.841 | 2.080 |
| west.telemetry.profile_process | 0.793 | 0.194 | 2.488 |
| west.world.process | 0.606 | 0.328 | 2.219 |
| reflection.process | 0.424 | 0.021 | 2.362 |
| gameplay.physics | 0.400 | 0.390 | 0.903 |
| urban.physics | 0.356 | 0.217 | 1.049 |
| terminal.physics | 0.330 | 0.317 | 0.673 |
| west.audio.nearby_process | 0.160 | 0.109 | 0.349 |
| west.camera.process | 0.148 | 0.139 | 0.205 |
| west.audio.world_process | 0.077 | 0.052 | 0.208 |
| west.street.physics | 0.072 | 0.012 | 0.430 |
| west.traffic_yield.physics | 0.037 | 0.035 | 0.082 |
| west.parking.physics | 0.017 | 0.015 | 0.038 |
| west.audio.weather_process | 0.014 | 0.013 | 0.017 |
| west.region.process | 0.008 | 0.006 | 0.007 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.2165617048346056, "system_profile_callback": 0.7673568702290077}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2844; p50 8.285 ms/passo e p95 11.333 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 1 | 676 | 19.122 | 23.445 | 7.469 | 9.233 |
| 2 | 650 | 30.355 | 38.734 | 7.987 | 9.933 |
| 3 | 162 | 47.428 | 60.660 | 9.345 | 11.202 |
| 4 | 54 | 63.627 | 86.667 | 10.213 | 13.568 |
| 5 | 21 | 77.087 | 86.201 | 10.600 | 11.830 |
| 6 | 3 | 113.331 | 123.087 | 12.888 | 14.425 |
| 7 | 5 | 115.283 | 152.944 | 11.296 | 11.684 |
| 8 | 1 | 110.819 | 110.819 | 10.128 | 10.128 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 3.924 | 3.560 | 5.040 |
| actor.physics | 1.460 | 1.403 | 1.765 |
| vehicle.drive | 1.100 | 0.992 | 1.483 |
| vehicle.street_pre | 0.656 | 0.589 | 0.957 |
| vehicle.effects | 0.624 | 0.590 | 0.934 |
| actor.move_and_slide | 0.529 | 0.495 | 0.692 |
| actor.step | 0.422 | 0.405 | 0.517 |
| vehicle.effects.tires | 0.418 | 0.403 | 0.658 |
| vehicle.move_and_slide | 0.389 | 0.356 | 0.558 |
| west.vehicle.junction_gate | 0.354 | 0.319 | 0.503 |
| street.pre.props | 0.306 | 0.270 | 0.463 |
| vehicle_tires.contacts | 0.293 | 0.283 | 0.462 |
| gameplay.physics | 0.221 | 0.207 | 0.267 |
| street.pre.people | 0.220 | 0.202 | 0.311 |
| urban.physics | 0.197 | 0.151 | 0.367 |
| street.pre.props.query | 0.188 | 0.166 | 0.286 |
| terminal.physics | 0.182 | 0.181 | 0.226 |
| vehicle.street_post | 0.164 | 0.125 | 0.188 |
| vehicle.lod | 0.146 | 0.137 | 0.172 |
| west.vehicle.escape | 0.124 | 0.111 | 0.178 |
| actor.steering | 0.099 | 0.096 | 0.118 |
| west.vehicle.obstacle_ahead | 0.081 | 0.076 | 0.122 |
| west.vehicle.route_projection | 0.073 | 0.066 | 0.100 |
| vehicle.effects.powertrain | 0.068 | 0.061 | 0.102 |
| west.vehicle.can_rotate | 0.067 | 0.061 | 0.102 |
| actor.pose | 0.057 | 0.055 | 0.069 |
| vehicle.resting | 0.053 | 0.050 | 0.062 |
| vehicle.wheels | 0.053 | 0.049 | 0.074 |
| street.post.contacts | 0.050 | 0.020 | 0.032 |
| west.street.physics | 0.040 | 0.007 | 0.211 |
| vehicle.contacts | 0.037 | 0.034 | 0.051 |
| vehicle.effects.impact | 0.036 | 0.032 | 0.051 |
| street.pre.crush | 0.034 | 0.030 | 0.048 |
| west.street.watch_people | 0.031 | 0.000 | 0.200 |
| vehicle.wreck_lifetime | 0.025 | 0.024 | 0.031 |
| west.traffic_yield.physics | 0.020 | 0.019 | 0.025 |
| street.post.slide | 0.014 | 0.013 | 0.021 |
| street.pre.people.cast | 0.014 | 0.000 | 0.054 |
| street.post.crush | 0.012 | 0.011 | 0.016 |
| vehicle_tires.surface_emit | 0.010 | 0.000 | 0.035 |
| west.parking.physics | 0.009 | 0.008 | 0.013 |
| urban.refresh_presence | 0.007 | 0.000 | 0.055 |
| vehicle_tires.skid_audio | 0.006 | 0.006 | 0.010 |
| west.traffic_yield.hazards | 0.006 | 0.005 | 0.007 |
| west.vehicle.rear_clear | 0.004 | 0.000 | 0.027 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |
| street.pre.props.hit | 0.000 | 0.000 | 0.000 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 7.098 | 6.157 | 17.850 | 1572 |
| actor.physics | root | None | 2.642 | 2.524 | 5.717 | 1572 |
| vehicle.drive | nested | vehicle.physics | 1.989 | 1.649 | 4.782 | 1572 |
| vehicle.street_pre | nested | vehicle.physics | 1.187 | 0.950 | 3.092 | 1572 |
| vehicle.effects | nested | vehicle.physics | 1.130 | 0.911 | 2.979 | 1572 |
| actor.move_and_slide | nested | actor.physics | 0.956 | 0.860 | 2.145 | 1572 |
| vehicle_tires.redraw_marks | root | None | 0.917 | 0.841 | 2.080 | 1532 |
| west.telemetry.profile_process | root | None | 0.793 | 0.194 | 2.488 | 1572 |
| actor.step | nested | actor.physics | 0.764 | 0.719 | 1.676 | 1572 |
| vehicle.effects.tires | nested | vehicle.effects | 0.757 | 0.591 | 2.018 | 1572 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.704 | 0.605 | 1.817 | 1572 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.640 | 0.477 | 1.640 | 1572 |
| west.world.process | root | None | 0.606 | 0.328 | 2.219 | 1572 |
| street.pre.props | nested | vehicle.street_pre | 0.553 | 0.425 | 1.470 | 1572 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.530 | 0.413 | 1.394 | 1489 |
| reflection.process | root | None | 0.424 | 0.021 | 2.362 | 1572 |
| gameplay.physics | root | None | 0.400 | 0.390 | 0.903 | 1572 |
| street.pre.people | nested | vehicle.street_pre | 0.398 | 0.319 | 1.038 | 1572 |
| urban.physics | root | None | 0.356 | 0.217 | 1.049 | 1572 |
| street.pre.props.query | nested | street.pre.props | 0.340 | 0.261 | 0.906 | 1572 |
| terminal.physics | root | None | 0.330 | 0.317 | 0.673 | 1572 |
| reflection.dynamic | nested | reflection.process | 0.310 | 0.000 | 2.018 | 1572 |
| vehicle.street_post | nested | vehicle.physics | 0.297 | 0.208 | 0.643 | 1572 |
| vehicle.lod | nested | vehicle.physics | 0.264 | 0.250 | 0.589 | 1572 |
| west.world.population_job | nested | west.world.process | 0.259 | 0.002 | 1.971 | 1572 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.242 | 0.223 | 0.523 | 1531 |
| west.vehicle.escape | nested | vehicle.drive | 0.224 | 0.184 | 0.539 | 1572 |
| west.world.residency | nested | west.world.process | 0.221 | 0.208 | 0.298 | 1572 |
| actor.steering | nested | actor.physics | 0.179 | 0.174 | 0.382 | 1572 |
| west.audio.nearby_process | root | None | 0.160 | 0.109 | 0.349 | 1572 |
| west.camera.process | root | None | 0.148 | 0.139 | 0.205 | 1572 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.146 | 0.122 | 0.331 | 1571 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.132 | 0.109 | 0.329 | 1572 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.122 | 0.096 | 0.321 | 1572 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.121 | 0.094 | 0.321 | 1572 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.110 | 0.000 | 0.328 | 175 |
| actor.pose | nested | actor.physics | 0.104 | 0.100 | 0.224 | 1572 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.100 | 0.000 | 0.212 | 115 |
| vehicle.resting | nested | vehicle.physics | 0.097 | 0.093 | 0.217 | 1572 |
| vehicle.wheels | nested | vehicle.physics | 0.097 | 0.081 | 0.242 | 1572 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.094 | 0.000 | 0.287 | 175 |
| street.post.contacts | nested | vehicle.street_post | 0.090 | 0.032 | 0.110 | 1572 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.089 | 0.000 | 0.209 | 82 |
| west.audio.world_process | root | None | 0.077 | 0.052 | 0.208 | 1572 |
| west.street.physics | root | None | 0.072 | 0.012 | 0.430 | 1572 |
| vehicle.contacts | nested | vehicle.physics | 0.067 | 0.057 | 0.174 | 1572 |
| vehicle.effects.impact | nested | vehicle.effects | 0.066 | 0.053 | 0.181 | 1572 |
| street.pre.crush | nested | vehicle.street_pre | 0.062 | 0.048 | 0.160 | 1572 |
| west.street.watch_people | nested | west.street.physics | 0.056 | 0.000 | 0.401 | 219 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.055 | 0.000 | 0.240 | 404 |
| street.crash | inclusive_unknown | None | 0.050 | 0.000 | 0.000 | 8 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.045 | 0.041 | 0.101 | 1572 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.040 | 0.033 | 0.102 | 1572 |
| west.traffic_yield.physics | root | None | 0.037 | 0.035 | 0.082 | 1572 |
| reflection.batch | nested | reflection.process | 0.037 | 0.000 | 0.227 | 1572 |
| west.audio.ambience | nested | west.audio.world_process | 0.031 | 0.024 | 0.082 | 1572 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.026 | 0.000 | 0.023 | 350 |
| street.post.slide | nested | vehicle.street_post | 0.026 | 0.021 | 0.067 | 1572 |
| west.camera.cutaway | nested | west.camera.process | 0.025 | 0.024 | 0.031 | 1572 |
| street.crash.damage_other | nested | street.crash | 0.025 | 0.000 | 0.000 | 8 |
| street.pre.people.cast | nested | street.pre.people | 0.024 | 0.000 | 0.135 | 673 |
| street.crash.damage_self | nested | street.crash | 0.023 | 0.000 | 0.000 | 8 |
| street.post.crush | nested | vehicle.street_post | 0.021 | 0.018 | 0.054 | 1572 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.018 | 0.000 | 0.073 | 550 |
| west.parking.physics | root | None | 0.017 | 0.015 | 0.038 | 1572 |
| west.audio.weather_process | root | None | 0.014 | 0.013 | 0.017 | 1572 |
| west.camera.terrain_offset | nested | west.camera.process | 0.013 | 0.012 | 0.016 | 1572 |
| urban.refresh_presence | nested | urban.physics | 0.013 | 0.000 | 0.110 | 158 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.012 | 0.011 | 0.015 | 1572 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.011 | 0.008 | 0.028 | 1489 |
| reflection.registration | nested | reflection.process | 0.010 | 0.001 | 0.093 | 1572 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.010 | 0.009 | 0.022 | 1572 |
| west.traffic.route_near | nested | multiple_contexts | 0.009 | 0.000 | 0.000 | 34 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.008 | 0.007 | 0.010 | 1572 |
| west.region.process | root | None | 0.008 | 0.006 | 0.007 | 1572 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.008 | 0.000 | 0.047 | 271 |
| west.router.plan | nested | multiple_contexts | 0.006 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 7 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.005 | 1572 |
| west.world.logical_region | nested | west.world.process | 0.003 | 0.003 | 0.004 | 1572 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 6 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 4 |
| retire.drain | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 34 |
| street.glass | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| street.scatter | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 2 |
| street.scatter.geometry | nested | street.scatter | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| ground_blood.allocate | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 7 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 8 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 8 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 19 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 25 |
| street.glass.resources | nested | street.glass | 0.000 | 0.000 | 0.000 | 2 |
| street.pre.props.hit | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 1 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| street.glass.attach | nested | street.glass | 0.000 | 0.000 | 0.000 | 2 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 19 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 19 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| street.pre.props.cast | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 4.148 ms; p95 10.490 ms (1572 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 4.730 ms; p95 9.215 ms (1572 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## no_density_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_density_2.json`

Bracket válido em 1514 quadros; inválido em 0. Passos físicos por quadro: `{"0": 2, "1": 654, "2": 636, "3": 88, "4": 54, "5": 46, "6": 18, "7": 9, "8": 7}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1514 | 16.713 | 14.213 | 52.348 |
| process_callback_ms | 1514 | 7.621 | 6.729 | 14.840 |
| process_to_deferred_ms | 1514 | 0.459 | 0.540 | 0.761 |
| deferred_to_render_pre_ms | 1514 | 0.337 | 0.272 | 0.827 |
| render_bracket_ms | 1514 | 3.647 | 3.521 | 4.666 |
| post_draw_to_physics_ms | 1514 | 0.835 | 0.766 | 1.508 |
| pre_process_gap_ms | 1514 | 2.809 | 2.525 | 5.805 |
| telemetry_ms | 1514 | 0.209 | 0.195 | 0.293 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 7.486 | 5.406 | 25.417 |
| actor.physics | 2.848 | 2.459 | 8.379 |
| vehicle_tires.redraw_marks | 0.941 | 0.725 | 3.172 |
| west.telemetry.profile_process | 0.764 | 0.189 | 2.526 |
| west.world.process | 0.613 | 0.323 | 2.465 |
| reflection.process | 0.484 | 0.021 | 2.367 |
| gameplay.physics | 0.424 | 0.387 | 1.163 |
| urban.physics | 0.417 | 0.299 | 1.004 |
| terminal.physics | 0.348 | 0.315 | 0.924 |
| west.audio.nearby_process | 0.155 | 0.105 | 0.348 |
| west.camera.process | 0.150 | 0.138 | 0.210 |
| west.audio.world_process | 0.078 | 0.053 | 0.208 |
| west.street.physics | 0.074 | 0.012 | 0.424 |
| west.traffic_yield.physics | 0.040 | 0.035 | 0.112 |
| west.parking.physics | 0.018 | 0.016 | 0.051 |
| west.audio.weather_process | 0.014 | 0.013 | 0.017 |
| west.region.process | 0.008 | 0.005 | 0.007 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.2303104359313078, "system_profile_callback": 0.7384194187582563}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2863; p50 8.392 ms/passo e p95 12.505 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 2 | 8.881 | 8.881 | — | — |
| 1 | 654 | 19.109 | 24.077 | 7.311 | 9.498 |
| 2 | 636 | 30.020 | 38.565 | 8.106 | 9.977 |
| 3 | 88 | 46.668 | 62.535 | 9.261 | 12.099 |
| 4 | 54 | 65.637 | 94.528 | 10.531 | 14.998 |
| 5 | 46 | 81.761 | 95.148 | 10.981 | 13.912 |
| 6 | 18 | 96.987 | 125.345 | 10.774 | 13.876 |
| 7 | 9 | 106.309 | 150.342 | 11.129 | 15.898 |
| 8 | 7 | 148.841 | 166.257 | 14.109 | 15.827 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 3.959 | 3.453 | 5.506 |
| actor.physics | 1.506 | 1.372 | 2.040 |
| vehicle.drive | 1.066 | 0.922 | 1.498 |
| vehicle.street_pre | 0.715 | 0.618 | 1.017 |
| vehicle.effects | 0.640 | 0.551 | 0.971 |
| actor.move_and_slide | 0.577 | 0.503 | 0.884 |
| actor.step | 0.434 | 0.400 | 0.561 |
| vehicle.effects.tires | 0.428 | 0.376 | 0.676 |
| vehicle.move_and_slide | 0.405 | 0.351 | 0.596 |
| street.pre.props | 0.337 | 0.293 | 0.499 |
| west.vehicle.junction_gate | 0.307 | 0.265 | 0.457 |
| vehicle_tires.contacts | 0.298 | 0.256 | 0.474 |
| street.pre.people | 0.236 | 0.198 | 0.344 |
| gameplay.physics | 0.224 | 0.204 | 0.276 |
| urban.physics | 0.220 | 0.214 | 0.368 |
| street.pre.props.query | 0.208 | 0.180 | 0.307 |
| terminal.physics | 0.184 | 0.181 | 0.228 |
| vehicle.lod | 0.140 | 0.124 | 0.180 |
| vehicle.street_post | 0.139 | 0.121 | 0.200 |
| west.vehicle.escape | 0.121 | 0.103 | 0.171 |
| actor.steering | 0.094 | 0.089 | 0.113 |
| west.vehicle.route_projection | 0.083 | 0.070 | 0.126 |
| west.vehicle.obstacle_ahead | 0.079 | 0.070 | 0.119 |
| west.vehicle.can_rotate | 0.076 | 0.065 | 0.115 |
| vehicle.effects.powertrain | 0.069 | 0.059 | 0.109 |
| vehicle.wheels | 0.056 | 0.049 | 0.082 |
| actor.pose | 0.056 | 0.052 | 0.069 |
| vehicle.resting | 0.052 | 0.046 | 0.066 |
| vehicle.contacts | 0.043 | 0.033 | 0.055 |
| west.street.physics | 0.039 | 0.006 | 0.205 |
| street.pre.crush | 0.038 | 0.032 | 0.055 |
| vehicle.effects.impact | 0.036 | 0.030 | 0.053 |
| west.street.watch_people | 0.030 | 0.000 | 0.193 |
| vehicle.wreck_lifetime | 0.024 | 0.021 | 0.031 |
| street.post.contacts | 0.022 | 0.018 | 0.032 |
| west.traffic_yield.physics | 0.021 | 0.019 | 0.026 |
| street.pre.people.cast | 0.018 | 0.000 | 0.061 |
| street.post.slide | 0.013 | 0.011 | 0.019 |
| street.post.crush | 0.012 | 0.011 | 0.017 |
| vehicle_tires.surface_emit | 0.010 | 0.000 | 0.035 |
| west.parking.physics | 0.010 | 0.009 | 0.014 |
| urban.refresh_presence | 0.007 | 0.000 | 0.054 |
| vehicle_tires.skid_audio | 0.007 | 0.006 | 0.011 |
| west.traffic_yield.hazards | 0.006 | 0.005 | 0.007 |
| west.vehicle.rear_clear | 0.000 | 0.000 | 0.000 |
| street.pre.props.hit | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_voice | 0.000 | 0.000 | 0.000 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 7.486 | 5.406 | 25.417 | 1512 |
| actor.physics | root | None | 2.848 | 2.459 | 8.379 | 1512 |
| vehicle.drive | nested | vehicle.physics | 2.016 | 1.539 | 6.805 | 1512 |
| vehicle.street_pre | nested | vehicle.physics | 1.353 | 0.919 | 4.653 | 1512 |
| vehicle.effects | nested | vehicle.physics | 1.210 | 0.815 | 4.186 | 1512 |
| actor.move_and_slide | nested | actor.physics | 1.092 | 0.876 | 3.361 | 1512 |
| vehicle_tires.redraw_marks | root | None | 0.941 | 0.725 | 3.172 | 1498 |
| actor.step | nested | actor.physics | 0.820 | 0.704 | 2.469 | 1512 |
| vehicle.effects.tires | nested | vehicle.effects | 0.809 | 0.532 | 2.786 | 1512 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.766 | 0.534 | 2.535 | 1512 |
| west.telemetry.profile_process | root | None | 0.764 | 0.189 | 2.526 | 1514 |
| street.pre.props | nested | vehicle.street_pre | 0.638 | 0.432 | 2.241 | 1512 |
| west.world.process | root | None | 0.613 | 0.323 | 2.465 | 1514 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.581 | 0.433 | 1.873 | 1512 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.564 | 0.371 | 1.948 | 1455 |
| reflection.process | root | None | 0.484 | 0.021 | 2.367 | 1514 |
| street.pre.people | nested | vehicle.street_pre | 0.446 | 0.303 | 1.466 | 1512 |
| gameplay.physics | root | None | 0.424 | 0.387 | 1.163 | 1512 |
| urban.physics | root | None | 0.417 | 0.299 | 1.004 | 1512 |
| street.pre.props.query | nested | street.pre.props | 0.393 | 0.269 | 1.401 | 1512 |
| reflection.dynamic | nested | reflection.process | 0.362 | 0.000 | 2.037 | 1514 |
| terminal.physics | root | None | 0.348 | 0.315 | 0.924 | 1512 |
| west.world.population_job | nested | west.world.process | 0.268 | 0.002 | 2.132 | 1514 |
| vehicle.lod | nested | vehicle.physics | 0.264 | 0.232 | 0.829 | 1512 |
| vehicle.street_post | nested | vehicle.physics | 0.263 | 0.179 | 0.906 | 1512 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.246 | 0.196 | 0.760 | 1498 |
| west.vehicle.escape | nested | vehicle.drive | 0.229 | 0.171 | 0.780 | 1512 |
| west.world.residency | nested | west.world.process | 0.218 | 0.202 | 0.297 | 1514 |
| actor.steering | nested | actor.physics | 0.177 | 0.159 | 0.498 | 1512 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.157 | 0.108 | 0.580 | 1512 |
| west.audio.nearby_process | root | None | 0.155 | 0.105 | 0.348 | 1514 |
| west.camera.process | root | None | 0.150 | 0.138 | 0.210 | 1514 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.149 | 0.112 | 0.482 | 1509 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.144 | 0.094 | 0.532 | 1512 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.131 | 0.087 | 0.451 | 1512 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.110 | 0.000 | 0.355 | 165 |
| vehicle.wheels | nested | vehicle.physics | 0.107 | 0.072 | 0.379 | 1512 |
| actor.pose | nested | actor.physics | 0.107 | 0.095 | 0.312 | 1512 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.099 | 0.000 | 0.233 | 124 |
| vehicle.resting | nested | vehicle.physics | 0.098 | 0.085 | 0.308 | 1512 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.097 | 0.000 | 0.355 | 165 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.092 | 0.000 | 0.275 | 84 |
| vehicle.contacts | nested | vehicle.physics | 0.080 | 0.050 | 0.255 | 1512 |
| west.audio.world_process | root | None | 0.078 | 0.053 | 0.208 | 1514 |
| west.street.physics | root | None | 0.074 | 0.012 | 0.424 | 1512 |
| street.pre.crush | nested | vehicle.street_pre | 0.072 | 0.048 | 0.249 | 1512 |
| vehicle.effects.impact | nested | vehicle.effects | 0.068 | 0.045 | 0.244 | 1512 |
| west.street.watch_people | nested | west.street.physics | 0.057 | 0.000 | 0.393 | 221 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.052 | 0.000 | 0.232 | 397 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.045 | 0.036 | 0.127 | 1512 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.045 | 0.038 | 0.144 | 1512 |
| reflection.batch | nested | reflection.process | 0.042 | 0.000 | 0.221 | 1514 |
| street.post.contacts | nested | vehicle.street_post | 0.041 | 0.027 | 0.150 | 1512 |
| west.traffic_yield.physics | root | None | 0.040 | 0.035 | 0.112 | 1512 |
| street.pre.people.cast | nested | street.pre.people | 0.035 | 0.000 | 0.141 | 652 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.033 | 0.000 | 0.023 | 330 |
| west.audio.ambience | nested | west.audio.world_process | 0.031 | 0.024 | 0.080 | 1514 |
| west.camera.cutaway | nested | west.camera.process | 0.026 | 0.024 | 0.033 | 1514 |
| street.post.slide | nested | vehicle.street_post | 0.025 | 0.016 | 0.083 | 1512 |
| street.post.crush | nested | vehicle.street_post | 0.023 | 0.016 | 0.080 | 1512 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.019 | 0.000 | 0.077 | 588 |
| west.parking.physics | root | None | 0.018 | 0.016 | 0.051 | 1512 |
| urban.refresh_presence | nested | urban.physics | 0.014 | 0.000 | 0.113 | 159 |
| west.audio.weather_process | root | None | 0.014 | 0.013 | 0.017 | 1514 |
| west.camera.terrain_offset | nested | west.camera.process | 0.013 | 0.012 | 0.016 | 1514 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.013 | 0.009 | 0.044 | 1455 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.013 | 0.012 | 0.016 | 1514 |
| west.traffic.route_near | nested | multiple_contexts | 0.012 | 0.000 | 0.000 | 40 |
| reflection.registration | nested | reflection.process | 0.011 | 0.001 | 0.097 | 1514 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.011 | 0.010 | 0.032 | 1512 |
| west.region.process | root | None | 0.008 | 0.005 | 0.007 | 1514 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.008 | 0.007 | 0.010 | 1514 |
| west.router.plan | nested | multiple_contexts | 0.006 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.005 | 0.000 | 0.000 | 7 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 7 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 7 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.005 | 1514 |
| west.world.logical_region | nested | west.world.process | 0.003 | 0.003 | 0.005 | 1514 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 6 |
| retire.drain | inclusive_unknown | None | 0.003 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 40 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| ground_blood.allocate | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 13 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| street.scatter | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 3 |
| street.scatter.geometry | nested | street.scatter | 0.001 | 0.000 | 0.000 | 3 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 38 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| street.pre.props.hit | nested | street.pre.props | 0.001 | 0.000 | 0.000 | 1 |
| street.glass | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 16 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| street.glass.resources | nested | street.glass | 0.000 | 0.000 | 0.000 | 1 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 3 |
| street.crash | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 16 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 3 |
| vehicle_tires.skid_voice | nested | vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 3 |
| street.pre.props.cast | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 1 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| street.glass.attach | nested | street.glass | 0.000 | 0.000 | 0.000 | 1 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| street.crash.damage_self | nested | street.crash | 0.000 | 0.000 | 0.000 | 1 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 16 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 1 |
| street.crash.damage_other | nested | street.crash | 0.000 | 0.000 | 0.000 | 1 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 1 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 4.377 ms; p95 13.904 ms (1514 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 4.505 ms; p95 10.888 ms (1514 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## no_roadside_parking_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_roadside_parking_1.json`

Bracket válido em 1168 quadros; inválido em 0. Passos físicos por quadro: `{"1": 486, "2": 345, "3": 87, "4": 35, "5": 29, "6": 22, "7": 22, "8": 142}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1168 | 30.741 | 15.062 | 128.634 |
| process_callback_ms | 1168 | 9.924 | 6.256 | 27.556 |
| process_to_deferred_ms | 1168 | 0.596 | 0.626 | 1.279 |
| deferred_to_render_pre_ms | 1168 | 0.419 | 0.308 | 0.910 |
| render_bracket_ms | 1168 | 4.346 | 3.871 | 7.434 |
| post_draw_to_physics_ms | 1168 | 1.162 | 0.776 | 3.651 |
| pre_process_gap_ms | 1168 | 4.019 | 2.541 | 13.055 |
| telemetry_ms | 1168 | 0.266 | 0.225 | 0.515 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 13.106 | 5.705 | 56.391 |
| actor.physics | 5.557 | 2.807 | 22.979 |
| west.telemetry.profile_process | 1.416 | 0.277 | 5.000 |
| vehicle_tires.redraw_marks | 0.851 | 0.488 | 2.970 |
| gameplay.physics | 0.837 | 0.438 | 3.393 |
| west.world.process | 0.823 | 0.369 | 2.907 |
| terminal.physics | 0.711 | 0.374 | 2.876 |
| urban.physics | 0.635 | 0.436 | 1.865 |
| reflection.process | 0.386 | 0.023 | 3.243 |
| west.audio.nearby_process | 0.234 | 0.128 | 0.700 |
| west.camera.process | 0.180 | 0.163 | 0.300 |
| west.street.physics | 0.143 | 0.014 | 0.747 |
| west.audio.world_process | 0.110 | 0.061 | 0.305 |
| west.traffic_yield.physics | 0.081 | 0.040 | 0.341 |
| west.audio.weather_process | 0.017 | 0.015 | 0.027 |
| west.region.process | 0.011 | 0.007 | 0.013 |
| west.parking.physics | 0.009 | 0.005 | 0.035 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.49676712328767125, "system_profile_callback": 1.3806960616438357}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 3144; p50 9.991 ms/passo e p95 20.233 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 1 | 486 | 18.827 | 22.533 | 7.591 | 8.819 |
| 2 | 345 | 29.442 | 38.436 | 7.999 | 9.828 |
| 3 | 87 | 48.442 | 67.634 | 9.669 | 11.443 |
| 4 | 35 | 62.245 | 82.996 | 9.820 | 13.044 |
| 5 | 29 | 79.464 | 97.591 | 10.320 | 13.508 |
| 6 | 22 | 96.926 | 122.335 | 11.218 | 14.523 |
| 7 | 22 | 117.041 | 139.958 | 11.968 | 15.513 |
| 8 | 142 | 169.752 | 227.304 | 15.079 | 20.519 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 4.869 | 3.428 | 7.263 |
| actor.physics | 2.065 | 1.596 | 2.886 |
| vehicle.drive | 1.470 | 1.023 | 2.265 |
| vehicle.street_pre | 0.858 | 0.584 | 1.363 |
| vehicle.effects | 0.703 | 0.537 | 0.995 |
| actor.move_and_slide | 0.703 | 0.595 | 0.949 |
| actor.step | 0.600 | 0.460 | 0.849 |
| vehicle.effects.tires | 0.453 | 0.359 | 0.658 |
| west.vehicle.junction_gate | 0.441 | 0.313 | 0.660 |
| vehicle.move_and_slide | 0.429 | 0.331 | 0.606 |
| street.pre.props | 0.395 | 0.271 | 0.621 |
| vehicle_tires.contacts | 0.321 | 0.251 | 0.472 |
| gameplay.physics | 0.311 | 0.232 | 0.424 |
| street.pre.people | 0.296 | 0.200 | 0.474 |
| terminal.physics | 0.264 | 0.208 | 0.363 |
| street.pre.props.query | 0.241 | 0.168 | 0.371 |
| urban.physics | 0.236 | 0.240 | 0.361 |
| vehicle.lod | 0.175 | 0.120 | 0.254 |
| west.vehicle.escape | 0.173 | 0.119 | 0.260 |
| vehicle.street_post | 0.165 | 0.119 | 0.251 |
| actor.steering | 0.139 | 0.102 | 0.200 |
| west.vehicle.obstacle_ahead | 0.110 | 0.077 | 0.171 |
| west.vehicle.route_projection | 0.098 | 0.068 | 0.149 |
| west.vehicle.can_rotate | 0.091 | 0.059 | 0.142 |
| actor.pose | 0.086 | 0.059 | 0.126 |
| vehicle.effects.powertrain | 0.082 | 0.061 | 0.123 |
| vehicle.resting | 0.068 | 0.048 | 0.098 |
| vehicle.wheels | 0.061 | 0.045 | 0.092 |
| west.street.physics | 0.053 | 0.007 | 0.208 |
| vehicle.contacts | 0.045 | 0.032 | 0.067 |
| vehicle.effects.impact | 0.043 | 0.031 | 0.063 |
| street.pre.crush | 0.043 | 0.029 | 0.068 |
| west.street.watch_people | 0.042 | 0.000 | 0.196 |
| vehicle.wreck_lifetime | 0.030 | 0.021 | 0.045 |
| west.traffic_yield.physics | 0.030 | 0.022 | 0.045 |
| street.post.contacts | 0.026 | 0.019 | 0.039 |
| street.post.slide | 0.015 | 0.011 | 0.024 |
| street.post.crush | 0.015 | 0.011 | 0.023 |
| street.pre.people.cast | 0.011 | 0.000 | 0.064 |
| urban.refresh_presence | 0.010 | 0.000 | 0.060 |
| west.vehicle.rear_clear | 0.009 | 0.000 | 0.042 |
| west.traffic_yield.hazards | 0.008 | 0.006 | 0.013 |
| vehicle_tires.surface_emit | 0.007 | 0.000 | 0.034 |
| vehicle_tires.skid_audio | 0.006 | 0.005 | 0.010 |
| street.pre.props.hit | 0.004 | 0.000 | 0.000 |
| west.parking.physics | 0.003 | 0.003 | 0.004 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 13.106 | 5.705 | 56.391 | 1168 |
| actor.physics | root | None | 5.557 | 2.807 | 22.979 | 1168 |
| vehicle.drive | nested | vehicle.physics | 3.958 | 1.758 | 17.817 | 1168 |
| vehicle.street_pre | nested | vehicle.physics | 2.309 | 0.872 | 10.714 | 1168 |
| vehicle.effects | nested | vehicle.physics | 1.893 | 0.810 | 7.573 | 1168 |
| actor.move_and_slide | nested | actor.physics | 1.892 | 1.005 | 7.212 | 1168 |
| actor.step | nested | actor.physics | 1.614 | 0.797 | 6.713 | 1168 |
| west.telemetry.profile_process | root | None | 1.416 | 0.277 | 5.000 | 1168 |
| vehicle.effects.tires | nested | vehicle.effects | 1.219 | 0.537 | 4.832 | 1168 |
| west.vehicle.junction_gate | nested | vehicle.drive | 1.188 | 0.501 | 5.199 | 1168 |
| vehicle.move_and_slide | nested | vehicle.physics | 1.155 | 0.525 | 4.591 | 1168 |
| street.pre.props | nested | vehicle.street_pre | 1.063 | 0.407 | 4.859 | 1168 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.865 | 0.383 | 3.535 | 1104 |
| vehicle_tires.redraw_marks | root | None | 0.851 | 0.488 | 2.970 | 998 |
| gameplay.physics | root | None | 0.837 | 0.438 | 3.393 | 1168 |
| west.world.process | root | None | 0.823 | 0.369 | 2.907 | 1168 |
| street.pre.people | nested | vehicle.street_pre | 0.798 | 0.306 | 3.663 | 1168 |
| terminal.physics | root | None | 0.711 | 0.374 | 2.876 | 1168 |
| street.pre.props.query | nested | street.pre.props | 0.648 | 0.251 | 2.931 | 1168 |
| urban.physics | root | None | 0.635 | 0.436 | 1.865 | 1168 |
| vehicle.lod | nested | vehicle.physics | 0.471 | 0.228 | 2.000 | 1168 |
| west.vehicle.escape | nested | vehicle.drive | 0.465 | 0.194 | 2.038 | 1168 |
| vehicle.street_post | nested | vehicle.physics | 0.444 | 0.182 | 1.907 | 1168 |
| reflection.process | root | None | 0.386 | 0.023 | 3.243 | 1168 |
| actor.steering | nested | actor.physics | 0.375 | 0.176 | 1.595 | 1168 |
| west.world.population_job | nested | west.world.process | 0.354 | 0.070 | 2.304 | 1168 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.297 | 0.118 | 1.365 | 1144 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.264 | 0.104 | 1.192 | 1168 |
| west.world.residency | nested | west.world.process | 0.261 | 0.226 | 0.461 | 1168 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.244 | 0.087 | 1.085 | 1168 |
| west.audio.nearby_process | root | None | 0.234 | 0.128 | 0.700 | 1168 |
| actor.pose | nested | actor.physics | 0.232 | 0.103 | 1.009 | 1168 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.227 | 0.145 | 0.714 | 998 |
| reflection.dynamic | nested | reflection.process | 0.224 | 0.000 | 2.522 | 1168 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.220 | 0.095 | 0.921 | 1168 |
| vehicle.resting | nested | vehicle.physics | 0.184 | 0.089 | 0.782 | 1168 |
| west.camera.process | root | None | 0.180 | 0.163 | 0.300 | 1168 |
| vehicle.wheels | nested | vehicle.physics | 0.163 | 0.069 | 0.708 | 1168 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.152 | 0.000 | 0.073 | 148 |
| west.street.physics | root | None | 0.143 | 0.014 | 0.747 | 1168 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.141 | 0.000 | 0.000 | 43 |
| vehicle.contacts | nested | vehicle.physics | 0.121 | 0.047 | 0.529 | 1168 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.121 | 0.000 | 0.487 | 148 |
| vehicle.effects.impact | nested | vehicle.effects | 0.115 | 0.047 | 0.460 | 1168 |
| street.pre.crush | nested | vehicle.street_pre | 0.115 | 0.043 | 0.538 | 1168 |
| west.street.watch_people | nested | west.street.physics | 0.114 | 0.000 | 0.652 | 241 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.114 | 0.000 | 0.408 | 64 |
| west.audio.world_process | root | None | 0.110 | 0.061 | 0.305 | 1168 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.102 | 0.000 | 0.455 | 420 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.088 | 0.049 | 0.329 | 1168 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.082 | 0.039 | 0.360 | 1168 |
| west.traffic_yield.physics | root | None | 0.081 | 0.040 | 0.341 | 1168 |
| street.post.contacts | nested | vehicle.street_post | 0.070 | 0.029 | 0.292 | 1168 |
| west.audio.ambience | nested | west.audio.world_process | 0.045 | 0.028 | 0.140 | 1168 |
| street.post.slide | nested | vehicle.street_post | 0.041 | 0.016 | 0.188 | 1168 |
| street.post.crush | nested | vehicle.street_post | 0.041 | 0.016 | 0.180 | 1168 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.035 | 0.000 | 0.038 | 294 |
| west.camera.cutaway | nested | west.camera.process | 0.031 | 0.027 | 0.051 | 1168 |
| street.pre.people.cast | nested | street.pre.people | 0.030 | 0.000 | 0.151 | 436 |
| reflection.batch | nested | reflection.process | 0.029 | 0.000 | 0.297 | 1168 |
| urban.refresh_presence | nested | urban.physics | 0.026 | 0.000 | 0.184 | 175 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.023 | 0.000 | 0.072 | 373 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.023 | 0.011 | 0.098 | 1168 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.018 | 0.000 | 0.088 | 370 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.017 | 0.008 | 0.067 | 1104 |
| west.audio.weather_process | root | None | 0.017 | 0.015 | 0.027 | 1168 |
| west.camera.terrain_offset | nested | west.camera.process | 0.016 | 0.015 | 0.028 | 1168 |
| west.traffic.route_near | nested | multiple_contexts | 0.016 | 0.000 | 0.000 | 28 |
| reflection.registration | nested | reflection.process | 0.016 | 0.001 | 0.118 | 1168 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.015 | 0.013 | 0.026 | 1168 |
| west.router.plan | nested | multiple_contexts | 0.012 | 0.000 | 0.000 | 2 |
| street.pre.props.hit | nested | street.pre.props | 0.011 | 0.000 | 0.000 | 3 |
| west.region.process | root | None | 0.011 | 0.007 | 0.013 | 1168 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.010 | 0.009 | 0.017 | 1168 |
| west.parking.physics | root | None | 0.009 | 0.005 | 0.035 | 1168 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.006 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.006 | 0.000 | 0.000 | 5 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.008 | 1168 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.004 | 0.009 | 1168 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 3 |
| retire.drain | inclusive_unknown | None | 0.003 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 28 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 1 |
| street.scatter | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| street.scatter.geometry | nested | street.scatter | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 17 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 17 |
| street.pre.props.cast | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 3 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 17 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| ground_blood.allocate | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.crash | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.damage_other | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.damage_self | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 4.566 ms; p95 40.147 ms (1168 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 4.667 ms; p95 16.956 ms (1168 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## no_roadside_parking_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_roadside_parking_2.json`

Bracket válido em 1684 quadros; inválido em 0. Passos físicos por quadro: `{"1": 875, "2": 615, "3": 119, "4": 28, "5": 23, "6": 7, "7": 4, "8": 13}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1684 | 14.209 | 9.059 | 31.470 |
| process_callback_ms | 1684 | 7.034 | 5.755 | 14.592 |
| process_to_deferred_ms | 1684 | 0.478 | 0.561 | 0.810 |
| deferred_to_render_pre_ms | 1684 | 0.328 | 0.276 | 0.471 |
| render_bracket_ms | 1684 | 3.762 | 3.650 | 4.739 |
| post_draw_to_physics_ms | 1684 | 0.832 | 0.776 | 1.344 |
| pre_process_gap_ms | 1684 | 2.690 | 2.312 | 4.767 |
| telemetry_ms | 1684 | 0.215 | 0.203 | 0.296 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 5.922 | 4.033 | 13.336 |
| actor.physics | 2.506 | 1.804 | 5.748 |
| west.telemetry.profile_process | 0.754 | 0.198 | 2.614 |
| vehicle_tires.redraw_marks | 0.652 | 0.542 | 1.944 |
| west.world.process | 0.522 | 0.315 | 1.273 |
| gameplay.physics | 0.406 | 0.247 | 0.939 |
| reflection.process | 0.361 | 0.022 | 2.375 |
| urban.physics | 0.358 | 0.241 | 0.921 |
| terminal.physics | 0.341 | 0.210 | 0.813 |
| west.camera.process | 0.162 | 0.152 | 0.233 |
| west.audio.nearby_process | 0.155 | 0.110 | 0.334 |
| west.audio.world_process | 0.081 | 0.056 | 0.216 |
| west.street.physics | 0.069 | 0.013 | 0.421 |
| west.traffic_yield.physics | 0.037 | 0.026 | 0.091 |
| west.audio.weather_process | 0.014 | 0.014 | 0.018 |
| west.region.process | 0.009 | 0.006 | 0.008 |
| west.parking.physics | 0.004 | 0.003 | 0.010 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.23778444180522565, "system_profile_callback": 0.7271484560570072}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2863; p50 7.902 ms/passo e p95 12.181 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 1 | 875 | 18.548 | 23.444 | 7.130 | 8.880 |
| 2 | 615 | 29.584 | 39.101 | 7.791 | 9.668 |
| 3 | 119 | 47.210 | 62.481 | 8.865 | 11.468 |
| 4 | 28 | 67.032 | 93.754 | 10.349 | 14.322 |
| 5 | 23 | 78.782 | 93.667 | 10.120 | 11.521 |
| 6 | 7 | 90.383 | 119.840 | 10.296 | 11.693 |
| 7 | 4 | 122.738 | 145.838 | 12.324 | 12.658 |
| 8 | 13 | 138.686 | 176.830 | 12.864 | 15.243 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 3.483 | 3.144 | 4.602 |
| actor.physics | 1.474 | 1.335 | 1.876 |
| vehicle.drive | 0.997 | 0.890 | 1.312 |
| vehicle.street_pre | 0.604 | 0.526 | 0.879 |
| actor.move_and_slide | 0.542 | 0.490 | 0.762 |
| vehicle.effects | 0.535 | 0.499 | 0.853 |
| actor.step | 0.418 | 0.379 | 0.540 |
| vehicle.move_and_slide | 0.360 | 0.302 | 0.738 |
| vehicle.effects.tires | 0.355 | 0.337 | 0.627 |
| west.vehicle.junction_gate | 0.309 | 0.270 | 0.462 |
| street.pre.props | 0.285 | 0.252 | 0.432 |
| vehicle_tires.contacts | 0.247 | 0.239 | 0.431 |
| gameplay.physics | 0.239 | 0.216 | 0.303 |
| urban.physics | 0.211 | 0.181 | 0.370 |
| terminal.physics | 0.200 | 0.186 | 0.256 |
| street.pre.people | 0.200 | 0.172 | 0.289 |
| street.pre.props.query | 0.174 | 0.153 | 0.266 |
| vehicle.lod | 0.126 | 0.114 | 0.155 |
| vehicle.street_post | 0.118 | 0.105 | 0.168 |
| west.vehicle.escape | 0.113 | 0.098 | 0.161 |
| actor.steering | 0.097 | 0.090 | 0.116 |
| west.vehicle.obstacle_ahead | 0.071 | 0.063 | 0.111 |
| west.vehicle.route_projection | 0.068 | 0.059 | 0.097 |
| west.vehicle.can_rotate | 0.062 | 0.053 | 0.088 |
| vehicle.effects.powertrain | 0.059 | 0.053 | 0.091 |
| actor.pose | 0.057 | 0.052 | 0.069 |
| vehicle.resting | 0.049 | 0.044 | 0.059 |
| vehicle.wheels | 0.043 | 0.039 | 0.062 |
| west.street.physics | 0.041 | 0.007 | 0.230 |
| vehicle.contacts | 0.032 | 0.029 | 0.046 |
| west.street.watch_people | 0.032 | 0.000 | 0.211 |
| vehicle.effects.impact | 0.031 | 0.028 | 0.045 |
| street.pre.crush | 0.031 | 0.028 | 0.045 |
| vehicle.wreck_lifetime | 0.022 | 0.021 | 0.028 |
| west.traffic_yield.physics | 0.022 | 0.020 | 0.027 |
| street.post.contacts | 0.019 | 0.017 | 0.032 |
| street.post.slide | 0.011 | 0.009 | 0.015 |
| street.post.crush | 0.010 | 0.009 | 0.014 |
| vehicle_tires.surface_emit | 0.009 | 0.000 | 0.037 |
| street.pre.people.cast | 0.009 | 0.000 | 0.041 |
| urban.refresh_presence | 0.008 | 0.000 | 0.059 |
| west.traffic_yield.hazards | 0.006 | 0.005 | 0.008 |
| vehicle_tires.skid_audio | 0.005 | 0.005 | 0.010 |
| west.vehicle.rear_clear | 0.004 | 0.000 | 0.024 |
| west.parking.physics | 0.003 | 0.002 | 0.003 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| street.pre.props.hit | 0.000 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_voice | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 5.922 | 4.033 | 13.336 | 1684 |
| actor.physics | root | None | 2.506 | 1.804 | 5.748 | 1684 |
| vehicle.drive | nested | vehicle.physics | 1.695 | 1.173 | 4.067 | 1684 |
| vehicle.street_pre | nested | vehicle.physics | 1.027 | 0.710 | 2.298 | 1684 |
| actor.move_and_slide | nested | actor.physics | 0.922 | 0.700 | 2.238 | 1684 |
| vehicle.effects | nested | vehicle.physics | 0.910 | 0.682 | 2.067 | 1684 |
| west.telemetry.profile_process | root | None | 0.754 | 0.198 | 2.614 | 1684 |
| actor.step | nested | actor.physics | 0.711 | 0.504 | 1.644 | 1684 |
| vehicle_tires.redraw_marks | root | None | 0.652 | 0.542 | 1.944 | 1359 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.613 | 0.401 | 1.640 | 1684 |
| vehicle.effects.tires | nested | vehicle.effects | 0.603 | 0.466 | 1.450 | 1684 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.525 | 0.362 | 1.392 | 1684 |
| west.world.process | root | None | 0.522 | 0.315 | 1.273 | 1684 |
| street.pre.props | nested | vehicle.street_pre | 0.485 | 0.333 | 1.035 | 1684 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.420 | 0.326 | 1.019 | 1598 |
| gameplay.physics | root | None | 0.406 | 0.247 | 0.939 | 1684 |
| reflection.process | root | None | 0.361 | 0.022 | 2.375 | 1684 |
| urban.physics | root | None | 0.358 | 0.241 | 0.921 | 1684 |
| terminal.physics | root | None | 0.341 | 0.210 | 0.813 | 1684 |
| street.pre.people | nested | vehicle.street_pre | 0.339 | 0.232 | 0.777 | 1684 |
| street.pre.props.query | nested | street.pre.props | 0.295 | 0.203 | 0.637 | 1684 |
| reflection.dynamic | nested | reflection.process | 0.254 | 0.000 | 1.993 | 1684 |
| west.world.residency | nested | west.world.process | 0.219 | 0.205 | 0.312 | 1684 |
| vehicle.lod | nested | vehicle.physics | 0.214 | 0.131 | 0.477 | 1684 |
| vehicle.street_post | nested | vehicle.physics | 0.200 | 0.144 | 0.437 | 1684 |
| west.vehicle.escape | nested | vehicle.drive | 0.193 | 0.136 | 0.456 | 1684 |
| west.world.population_job | nested | west.world.process | 0.187 | 0.002 | 0.822 | 1684 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.179 | 0.154 | 0.497 | 1358 |
| actor.steering | nested | actor.physics | 0.166 | 0.107 | 0.362 | 1684 |
| west.camera.process | root | None | 0.162 | 0.152 | 0.233 | 1684 |
| west.audio.nearby_process | root | None | 0.155 | 0.110 | 0.334 | 1684 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.120 | 0.087 | 0.292 | 1662 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.115 | 0.081 | 0.263 | 1684 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.105 | 0.072 | 0.226 | 1684 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.100 | 0.072 | 0.227 | 1684 |
| actor.pose | nested | actor.physics | 0.098 | 0.062 | 0.219 | 1684 |
| vehicle.resting | nested | vehicle.physics | 0.083 | 0.051 | 0.190 | 1684 |
| west.audio.world_process | root | None | 0.081 | 0.056 | 0.216 | 1684 |
| vehicle.wheels | nested | vehicle.physics | 0.074 | 0.051 | 0.162 | 1684 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.069 | 0.000 | 0.040 | 173 |
| west.street.physics | root | None | 0.069 | 0.013 | 0.421 | 1684 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.068 | 0.000 | 0.007 | 173 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.064 | 0.000 | 0.000 | 63 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.063 | 0.000 | 0.000 | 40 |
| vehicle.contacts | nested | vehicle.physics | 0.055 | 0.038 | 0.126 | 1684 |
| west.street.watch_people | nested | west.street.physics | 0.054 | 0.000 | 0.399 | 221 |
| vehicle.effects.impact | nested | vehicle.effects | 0.053 | 0.037 | 0.124 | 1684 |
| street.pre.crush | nested | vehicle.street_pre | 0.053 | 0.038 | 0.121 | 1684 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.047 | 0.000 | 0.219 | 408 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.041 | 0.028 | 0.106 | 1684 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.038 | 0.026 | 0.089 | 1684 |
| west.traffic_yield.physics | root | None | 0.037 | 0.026 | 0.091 | 1684 |
| street.post.contacts | nested | vehicle.street_post | 0.033 | 0.023 | 0.077 | 1684 |
| west.audio.ambience | nested | west.audio.world_process | 0.032 | 0.025 | 0.083 | 1684 |
| reflection.batch | nested | reflection.process | 0.032 | 0.000 | 0.233 | 1684 |
| west.camera.cutaway | nested | west.camera.process | 0.028 | 0.026 | 0.037 | 1684 |
| street.post.slide | nested | vehicle.street_post | 0.018 | 0.013 | 0.041 | 1684 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.018 | 0.000 | 0.020 | 344 |
| street.post.crush | nested | vehicle.street_post | 0.017 | 0.012 | 0.038 | 1684 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.015 | 0.000 | 0.063 | 575 |
| street.pre.people.cast | nested | street.pre.people | 0.015 | 0.000 | 0.075 | 457 |
| west.camera.terrain_offset | nested | west.camera.process | 0.015 | 0.014 | 0.019 | 1684 |
| west.audio.weather_process | root | None | 0.014 | 0.014 | 0.018 | 1684 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.014 | 0.012 | 0.018 | 1684 |
| urban.refresh_presence | nested | urban.physics | 0.013 | 0.000 | 0.122 | 160 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.011 | 0.000 | 0.000 | 5 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.010 | 0.007 | 0.025 | 1684 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.009 | 0.007 | 0.022 | 1598 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.009 | 0.008 | 0.012 | 1684 |
| west.region.process | root | None | 0.009 | 0.006 | 0.008 | 1684 |
| reflection.registration | nested | reflection.process | 0.008 | 0.001 | 0.028 | 1684 |
| west.traffic.route_near | nested | multiple_contexts | 0.007 | 0.000 | 0.000 | 22 |
| west.router.plan | nested | multiple_contexts | 0.006 | 0.000 | 0.000 | 2 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.006 | 0.000 | 0.040 | 284 |
| west.parking.physics | root | None | 0.004 | 0.003 | 0.010 | 1684 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.005 | 1684 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.003 | 0.005 | 1684 |
| retire.drain | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 22 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| street.pre.props.cast | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 38 |
| ground_blood.allocate | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 5 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| street.pre.props.hit | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 19 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 12 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 12 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 12 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.crash | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.damage_other | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.damage_self | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.glass | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.glass.attach | nested | street.glass | 0.000 | 0.000 | 0.000 | 0 |
| street.glass.resources | nested | street.glass | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.geometry | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| vehicle_tires.skid_voice | nested | vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 3.411 ms; p95 10.991 ms (1684 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 4.276 ms; p95 9.974 ms (1684 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## no_traffic_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_1.json`

Bracket válido em 3477 quadros; inválido em 0. Passos físicos por quadro: `{"0": 915, "1": 2306, "2": 243, "3": 9, "4": 3, "5": 1}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 3477 | 3.743 | 3.742 | 11.176 |
| process_callback_ms | 3477 | 4.330 | 3.658 | 8.259 |
| process_to_deferred_ms | 3477 | 0.379 | 0.228 | 0.893 |
| deferred_to_render_pre_ms | 3477 | 0.272 | 0.240 | 0.464 |
| render_bracket_ms | 3477 | 3.198 | 2.989 | 4.577 |
| post_draw_to_physics_ms | 3477 | 0.543 | 0.558 | 1.279 |
| pre_process_gap_ms | 3477 | 1.673 | 1.517 | 3.252 |
| telemetry_ms | 3477 | 0.179 | 0.154 | 0.294 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| actor.physics | 1.227 | 1.264 | 3.572 |
| west.world.process | 0.301 | 0.217 | 0.573 |
| west.telemetry.profile_process | 0.296 | 0.121 | 1.443 |
| reflection.process | 0.278 | 0.022 | 1.641 |
| gameplay.physics | 0.207 | 0.205 | 0.594 |
| urban.physics | 0.179 | 0.132 | 0.478 |
| terminal.physics | 0.175 | 0.189 | 0.488 |
| west.camera.process | 0.167 | 0.144 | 0.272 |
| vehicle.physics | 0.124 | 0.084 | 0.497 |
| west.audio.world_process | 0.072 | 0.053 | 0.192 |
| west.street.physics | 0.033 | 0.007 | 0.322 |
| west.traffic_yield.physics | 0.019 | 0.019 | 0.050 |
| west.audio.weather_process | 0.015 | 0.014 | 0.022 |
| west.audio.nearby_process | 0.015 | 0.005 | 0.072 |
| west.parking.physics | 0.009 | 0.008 | 0.025 |
| west.region.process | 0.008 | 0.006 | 0.010 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.12683232671843542, "system_profile_callback": 0.2793445498993385}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2836; p50 4.197 ms/passo e p95 6.809 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 915 | 7.264 | 9.744 | — | — |
| 1 | 2306 | 13.013 | 20.867 | 3.957 | 6.113 |
| 2 | 243 | 27.621 | 35.774 | 5.939 | 7.167 |
| 3 | 9 | 39.366 | 44.149 | 5.851 | 7.495 |
| 4 | 3 | 45.167 | 48.712 | 6.346 | 7.045 |
| 5 | 1 | 61.587 | 61.587 | 6.999 | 6.999 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| actor.physics | 1.504 | 1.405 | 2.156 |
| actor.move_and_slide | 0.564 | 0.548 | 0.816 |
| actor.step | 0.427 | 0.397 | 0.615 |
| gameplay.physics | 0.254 | 0.223 | 0.362 |
| urban.physics | 0.220 | 0.207 | 0.426 |
| terminal.physics | 0.215 | 0.204 | 0.317 |
| vehicle.physics | 0.152 | 0.094 | 0.476 |
| actor.steering | 0.095 | 0.086 | 0.139 |
| actor.pose | 0.054 | 0.048 | 0.084 |
| west.street.physics | 0.040 | 0.007 | 0.329 |
| west.street.watch_people | 0.031 | 0.000 | 0.315 |
| west.traffic_yield.physics | 0.023 | 0.021 | 0.034 |
| vehicle.resting | 0.019 | 0.017 | 0.029 |
| vehicle.drive | 0.019 | 0.000 | 0.130 |
| west.parking.physics | 0.011 | 0.009 | 0.017 |
| urban.refresh_presence | 0.009 | 0.000 | 0.102 |
| vehicle.street_pre | 0.007 | 0.000 | 0.077 |
| west.traffic_yield.hazards | 0.006 | 0.005 | 0.009 |
| vehicle.wreck_lifetime | 0.006 | 0.005 | 0.009 |
| vehicle.lod | 0.005 | 0.000 | 0.017 |
| west.vehicle.escape | 0.004 | 0.000 | 0.014 |
| street.pre.people | 0.003 | 0.000 | 0.036 |
| west.vehicle.route_projection | 0.003 | 0.000 | 0.029 |
| vehicle.effects | 0.003 | 0.000 | 0.027 |
| west.vehicle.junction_gate | 0.003 | 0.000 | 0.011 |
| vehicle.move_and_slide | 0.002 | 0.000 | 0.020 |
| vehicle.street_post | 0.002 | 0.000 | 0.023 |
| west.vehicle.obstacle_ahead | 0.002 | 0.000 | 0.015 |
| street.pre.props | 0.001 | 0.000 | 0.011 |
| west.vehicle.can_rotate | 0.001 | 0.000 | 0.008 |
| street.pre.crush | 0.001 | 0.000 | 0.004 |
| vehicle.wheels | 0.001 | 0.000 | 0.006 |
| street.pre.props.query | 0.001 | 0.000 | 0.005 |
| vehicle.contacts | 0.001 | 0.000 | 0.005 |
| vehicle.effects.powertrain | 0.000 | 0.000 | 0.004 |
| vehicle.effects.tires | 0.000 | 0.000 | 0.002 |
| street.post.contacts | 0.000 | 0.000 | 0.003 |
| vehicle.effects.impact | 0.000 | 0.000 | 0.003 |
| street.post.slide | 0.000 | 0.000 | 0.002 |
| street.post.crush | 0.000 | 0.000 | 0.002 |
| vehicle_tires.contacts | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| actor.physics | root | None | 1.227 | 1.264 | 3.572 | 2562 |
| actor.move_and_slide | nested | actor.physics | 0.460 | 0.475 | 1.298 | 2562 |
| actor.step | nested | actor.physics | 0.348 | 0.359 | 0.992 | 2562 |
| west.world.process | root | None | 0.301 | 0.217 | 0.573 | 3477 |
| west.telemetry.profile_process | root | None | 0.296 | 0.121 | 1.443 | 3477 |
| reflection.process | root | None | 0.278 | 0.022 | 1.641 | 3477 |
| gameplay.physics | root | None | 0.207 | 0.205 | 0.594 | 2562 |
| reflection.dynamic | nested | reflection.process | 0.188 | 0.000 | 1.275 | 3477 |
| urban.physics | root | None | 0.179 | 0.132 | 0.478 | 2562 |
| terminal.physics | root | None | 0.175 | 0.189 | 0.488 | 2562 |
| west.world.residency | nested | west.world.process | 0.175 | 0.152 | 0.288 | 3477 |
| west.camera.process | root | None | 0.167 | 0.144 | 0.272 | 3477 |
| vehicle.physics | root | None | 0.124 | 0.084 | 0.497 | 2562 |
| actor.steering | nested | actor.physics | 0.077 | 0.079 | 0.221 | 2562 |
| west.audio.world_process | root | None | 0.072 | 0.053 | 0.192 | 3477 |
| west.world.population_job | nested | west.world.process | 0.063 | 0.002 | 0.136 | 3477 |
| actor.pose | nested | actor.physics | 0.044 | 0.044 | 0.130 | 2562 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.041 | 0.000 | 0.005 | 183 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.039 | 0.000 | 0.000 | 84 |
| reflection.batch | nested | reflection.process | 0.036 | 0.000 | 0.248 | 3477 |
| west.street.physics | root | None | 0.033 | 0.007 | 0.322 | 2562 |
| west.audio.ambience | nested | west.audio.world_process | 0.030 | 0.024 | 0.069 | 3477 |
| west.camera.cutaway | nested | west.camera.process | 0.029 | 0.026 | 0.044 | 3477 |
| west.street.watch_people | nested | west.street.physics | 0.025 | 0.000 | 0.309 | 218 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.022 | 0.021 | 0.062 | 2562 |
| west.traffic_yield.physics | root | None | 0.019 | 0.019 | 0.050 | 2562 |
| vehicle.resting | nested | vehicle.physics | 0.016 | 0.016 | 0.043 | 2562 |
| vehicle.drive | nested | vehicle.physics | 0.016 | 0.000 | 0.136 | 311 |
| west.camera.terrain_offset | nested | west.camera.process | 0.016 | 0.014 | 0.023 | 3477 |
| west.audio.weather_process | root | None | 0.015 | 0.014 | 0.022 | 3477 |
| west.audio.nearby_process | root | None | 0.015 | 0.005 | 0.072 | 3477 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.014 | 0.012 | 0.022 | 3477 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.009 | 0.008 | 0.014 | 3477 |
| west.parking.physics | root | None | 0.009 | 0.008 | 0.025 | 2562 |
| urban.refresh_presence | nested | urban.physics | 0.008 | 0.000 | 0.000 | 158 |
| west.region.process | root | None | 0.008 | 0.006 | 0.010 | 3477 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.007 | 0.000 | 0.057 | 439 |
| vehicle.street_pre | nested | vehicle.physics | 0.006 | 0.000 | 0.000 | 173 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.005 | 0.005 | 0.014 | 2562 |
| west.router.plan | nested | multiple_contexts | 0.005 | 0.000 | 0.000 | 2 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.005 | 0.004 | 0.014 | 2562 |
| vehicle.lod | nested | vehicle.physics | 0.004 | 0.000 | 0.025 | 821 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.007 | 3477 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.003 | 0.006 | 3477 |
| reflection.registration | nested | reflection.process | 0.003 | 0.001 | 0.001 | 3477 |
| west.vehicle.escape | nested | vehicle.drive | 0.003 | 0.000 | 0.015 | 307 |
| street.pre.people | nested | vehicle.street_pre | 0.003 | 0.000 | 0.000 | 168 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.002 | 0.000 | 0.004 | 307 |
| vehicle.effects | nested | vehicle.physics | 0.002 | 0.000 | 0.000 | 173 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.002 | 0.000 | 0.011 | 307 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.002 | 0.000 | 0.000 | 173 |
| vehicle.street_post | nested | vehicle.physics | 0.002 | 0.000 | 0.000 | 173 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 157 |
| retire.drain | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 3 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.001 | 0.000 | 0.009 | 366 |
| street.pre.props | nested | vehicle.street_pre | 0.001 | 0.000 | 0.000 | 168 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.001 | 0.000 | 0.014 | 183 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.001 | 0.000 | 0.000 | 160 |
| street.pre.crush | nested | vehicle.street_pre | 0.001 | 0.000 | 0.000 | 168 |
| vehicle.wheels | nested | vehicle.physics | 0.001 | 0.000 | 0.000 | 173 |
| street.pre.props.query | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 143 |
| vehicle.contacts | nested | vehicle.physics | 0.000 | 0.000 | 0.000 | 173 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.000 | 0.000 | 0.000 | 173 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| vehicle.effects.tires | nested | vehicle.effects | 0.000 | 0.000 | 0.000 | 173 |
| street.post.contacts | nested | vehicle.street_post | 0.000 | 0.000 | 0.000 | 173 |
| vehicle.effects.impact | nested | vehicle.effects | 0.000 | 0.000 | 0.000 | 173 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| street.post.slide | nested | vehicle.street_post | 0.000 | 0.000 | 0.000 | 173 |
| street.post.crush | nested | vehicle.street_post | 0.000 | 0.000 | 0.000 | 173 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.000 | 0.000 | 0.000 | 1 |
| ground_blood.allocate | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 1.716 ms; p95 5.359 ms (3477 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 2.648 ms; p95 5.504 ms (3477 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## no_traffic_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_2.json`

Bracket válido em 3150 quadros; inválido em 0. Passos físicos por quadro: `{"0": 480, "1": 2523, "2": 131, "3": 14, "4": 2}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 3150 | 4.253 | 4.448 | 6.771 |
| process_callback_ms | 3150 | 4.737 | 4.054 | 7.709 |
| process_to_deferred_ms | 3150 | 0.424 | 0.255 | 0.818 |
| deferred_to_render_pre_ms | 3150 | 0.299 | 0.271 | 0.420 |
| render_bracket_ms | 3150 | 3.431 | 3.365 | 4.165 |
| post_draw_to_physics_ms | 3150 | 0.657 | 0.715 | 1.059 |
| pre_process_gap_ms | 3150 | 1.858 | 1.836 | 2.661 |
| telemetry_ms | 3150 | 0.201 | 0.192 | 0.290 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| actor.physics | 1.254 | 1.295 | 2.216 |
| west.world.process | 0.324 | 0.247 | 0.531 |
| west.telemetry.profile_process | 0.323 | 0.149 | 1.443 |
| reflection.process | 0.291 | 0.024 | 2.039 |
| gameplay.physics | 0.231 | 0.243 | 0.406 |
| urban.physics | 0.207 | 0.226 | 0.416 |
| terminal.physics | 0.193 | 0.207 | 0.335 |
| west.camera.process | 0.182 | 0.170 | 0.265 |
| vehicle.physics | 0.129 | 0.107 | 0.381 |
| west.audio.world_process | 0.079 | 0.061 | 0.192 |
| west.street.physics | 0.037 | 0.007 | 0.397 |
| west.traffic_yield.physics | 0.022 | 0.022 | 0.041 |
| west.audio.weather_process | 0.017 | 0.016 | 0.020 |
| west.audio.nearby_process | 0.016 | 0.006 | 0.072 |
| west.parking.physics | 0.010 | 0.010 | 0.022 |
| west.region.process | 0.007 | 0.006 | 0.009 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.14181619047619048, "system_profile_callback": 0.3055431746031746}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2835; p50 4.632 ms/passo e p95 6.052 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 480 | 8.708 | 10.822 | — | — |
| 1 | 2523 | 14.798 | 19.516 | 4.561 | 5.777 |
| 2 | 131 | 26.073 | 38.474 | 5.401 | 7.295 |
| 3 | 14 | 37.176 | 56.957 | 5.984 | 8.044 |
| 4 | 2 | 41.699 | 41.699 | 5.053 | 5.053 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| actor.physics | 1.393 | 1.354 | 1.897 |
| actor.move_and_slide | 0.507 | 0.486 | 0.738 |
| actor.step | 0.383 | 0.374 | 0.536 |
| gameplay.physics | 0.256 | 0.247 | 0.324 |
| urban.physics | 0.230 | 0.233 | 0.396 |
| terminal.physics | 0.214 | 0.213 | 0.281 |
| vehicle.physics | 0.143 | 0.110 | 0.418 |
| actor.steering | 0.093 | 0.090 | 0.125 |
| actor.pose | 0.053 | 0.051 | 0.073 |
| west.street.physics | 0.041 | 0.008 | 0.397 |
| west.street.watch_people | 0.032 | 0.000 | 0.380 |
| west.traffic_yield.physics | 0.024 | 0.023 | 0.032 |
| vehicle.resting | 0.020 | 0.019 | 0.027 |
| vehicle.drive | 0.016 | 0.000 | 0.121 |
| west.parking.physics | 0.011 | 0.010 | 0.015 |
| urban.refresh_presence | 0.009 | 0.000 | 0.110 |
| west.traffic_yield.hazards | 0.006 | 0.006 | 0.008 |
| vehicle.street_pre | 0.006 | 0.000 | 0.061 |
| vehicle.wreck_lifetime | 0.006 | 0.006 | 0.008 |
| vehicle.lod | 0.004 | 0.000 | 0.015 |
| west.vehicle.escape | 0.003 | 0.000 | 0.013 |
| street.pre.people | 0.003 | 0.000 | 0.029 |
| west.vehicle.route_projection | 0.002 | 0.000 | 0.031 |
| west.vehicle.junction_gate | 0.002 | 0.000 | 0.010 |
| vehicle.effects | 0.002 | 0.000 | 0.026 |
| vehicle.street_post | 0.002 | 0.000 | 0.022 |
| west.vehicle.obstacle_ahead | 0.002 | 0.000 | 0.018 |
| vehicle.move_and_slide | 0.001 | 0.000 | 0.018 |
| street.pre.props | 0.001 | 0.000 | 0.007 |
| west.vehicle.can_rotate | 0.001 | 0.000 | 0.007 |
| street.pre.crush | 0.001 | 0.000 | 0.003 |
| vehicle.wheels | 0.001 | 0.000 | 0.006 |
| street.pre.props.query | 0.000 | 0.000 | 0.003 |
| vehicle.contacts | 0.000 | 0.000 | 0.005 |
| vehicle.effects.powertrain | 0.000 | 0.000 | 0.004 |
| street.post.contacts | 0.000 | 0.000 | 0.003 |
| vehicle.effects.impact | 0.000 | 0.000 | 0.003 |
| vehicle.effects.tires | 0.000 | 0.000 | 0.002 |
| street.post.slide | 0.000 | 0.000 | 0.002 |
| street.post.crush | 0.000 | 0.000 | 0.002 |
| vehicle_tires.contacts | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| actor.physics | root | None | 1.254 | 1.295 | 2.216 | 2670 |
| actor.move_and_slide | nested | actor.physics | 0.456 | 0.456 | 0.816 | 2670 |
| actor.step | nested | actor.physics | 0.345 | 0.354 | 0.621 | 2670 |
| west.world.process | root | None | 0.324 | 0.247 | 0.531 | 3150 |
| west.telemetry.profile_process | root | None | 0.323 | 0.149 | 1.443 | 3150 |
| reflection.process | root | None | 0.291 | 0.024 | 2.039 | 3150 |
| gameplay.physics | root | None | 0.231 | 0.243 | 0.406 | 2670 |
| urban.physics | root | None | 0.207 | 0.226 | 0.416 | 2670 |
| reflection.dynamic | nested | reflection.process | 0.194 | 0.000 | 1.634 | 3150 |
| terminal.physics | root | None | 0.193 | 0.207 | 0.335 | 2670 |
| west.world.residency | nested | west.world.process | 0.192 | 0.180 | 0.281 | 3150 |
| west.camera.process | root | None | 0.182 | 0.170 | 0.265 | 3150 |
| vehicle.physics | root | None | 0.129 | 0.107 | 0.381 | 2670 |
| actor.steering | nested | actor.physics | 0.084 | 0.086 | 0.154 | 2670 |
| west.audio.world_process | root | None | 0.079 | 0.061 | 0.192 | 3150 |
| west.world.population_job | nested | west.world.process | 0.063 | 0.002 | 0.119 | 3150 |
| actor.pose | nested | actor.physics | 0.048 | 0.049 | 0.092 | 2670 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.038 | 0.000 | 0.006 | 183 |
| west.street.physics | root | None | 0.037 | 0.007 | 0.397 | 2670 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.036 | 0.000 | 0.000 | 66 |
| reflection.batch | nested | reflection.process | 0.035 | 0.000 | 0.280 | 3150 |
| west.camera.cutaway | nested | west.camera.process | 0.032 | 0.029 | 0.044 | 3150 |
| west.audio.ambience | nested | west.audio.world_process | 0.032 | 0.027 | 0.089 | 3150 |
| west.street.watch_people | nested | west.street.physics | 0.028 | 0.000 | 0.380 | 218 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.024 | 0.025 | 0.046 | 2670 |
| west.traffic_yield.physics | root | None | 0.022 | 0.022 | 0.041 | 2670 |
| vehicle.resting | nested | vehicle.physics | 0.018 | 0.018 | 0.033 | 2670 |
| west.camera.terrain_offset | nested | west.camera.process | 0.017 | 0.016 | 0.022 | 3150 |
| west.audio.weather_process | root | None | 0.017 | 0.016 | 0.020 | 3150 |
| west.audio.nearby_process | root | None | 0.016 | 0.006 | 0.072 | 3150 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.015 | 0.014 | 0.021 | 3150 |
| vehicle.drive | nested | vehicle.physics | 0.014 | 0.000 | 0.115 | 259 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.010 | 0.009 | 0.013 | 3150 |
| west.parking.physics | root | None | 0.010 | 0.010 | 0.022 | 2670 |
| urban.refresh_presence | nested | urban.physics | 0.008 | 0.000 | 0.000 | 157 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.008 | 0.000 | 0.057 | 439 |
| west.region.process | root | None | 0.007 | 0.006 | 0.009 | 3150 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.006 | 0.006 | 0.012 | 2670 |
| vehicle.street_pre | nested | vehicle.physics | 0.005 | 0.000 | 0.000 | 153 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.005 | 0.005 | 0.010 | 2670 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.006 | 3150 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.004 | 0.006 | 3150 |
| west.router.plan | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 2 |
| vehicle.lod | nested | vehicle.physics | 0.004 | 0.000 | 0.014 | 981 |
| reflection.registration | nested | reflection.process | 0.003 | 0.001 | 0.001 | 3150 |
| west.vehicle.escape | nested | vehicle.drive | 0.003 | 0.000 | 0.013 | 259 |
| street.pre.people | nested | vehicle.street_pre | 0.003 | 0.000 | 0.000 | 152 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.002 | 0.000 | 0.003 | 259 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.002 | 0.000 | 0.009 | 259 |
| vehicle.effects | nested | vehicle.physics | 0.002 | 0.000 | 0.000 | 153 |
| vehicle.street_post | nested | vehicle.physics | 0.001 | 0.000 | 0.000 | 153 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 157 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.001 | 0.000 | 0.000 | 153 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.001 | 0.000 | 0.018 | 183 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.001 | 0.000 | 0.010 | 366 |
| street.pre.props | nested | vehicle.street_pre | 0.001 | 0.000 | 0.000 | 152 |
| retire.drain | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 2 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.001 | 0.000 | 0.000 | 145 |
| street.pre.crush | nested | vehicle.street_pre | 0.000 | 0.000 | 0.000 | 152 |
| vehicle.wheels | nested | vehicle.physics | 0.000 | 0.000 | 0.000 | 153 |
| street.pre.props.query | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 135 |
| vehicle.contacts | nested | vehicle.physics | 0.000 | 0.000 | 0.000 | 153 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.000 | 0.000 | 0.000 | 153 |
| street.post.contacts | nested | vehicle.street_post | 0.000 | 0.000 | 0.000 | 153 |
| vehicle.effects.impact | nested | vehicle.effects | 0.000 | 0.000 | 0.000 | 153 |
| vehicle.effects.tires | nested | vehicle.effects | 0.000 | 0.000 | 0.000 | 153 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| street.post.slide | nested | vehicle.street_post | 0.000 | 0.000 | 0.000 | 153 |
| street.post.crush | nested | vehicle.street_post | 0.000 | 0.000 | 0.000 | 153 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| ground_blood.allocate | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.000 | 0.000 | 0.000 | 0 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 2.250 ms; p95 3.729 ms (3150 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 3.123 ms; p95 5.022 ms (3150 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## no_traffic_yield_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_yield_1.json`

Bracket válido em 1267 quadros; inválido em 0. Passos físicos por quadro: `{"0": 3, "1": 607, "2": 360, "3": 59, "4": 30, "5": 30, "6": 32, "7": 34, "8": 112}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 1267 | 24.485 | 12.637 | 102.559 |
| process_callback_ms | 1267 | 9.408 | 6.399 | 23.540 |
| process_to_deferred_ms | 1267 | 0.534 | 0.557 | 1.122 |
| deferred_to_render_pre_ms | 1267 | 0.368 | 0.260 | 0.840 |
| render_bracket_ms | 1267 | 4.165 | 3.875 | 6.547 |
| post_draw_to_physics_ms | 1267 | 1.221 | 0.804 | 3.101 |
| pre_process_gap_ms | 1267 | 3.866 | 2.383 | 12.126 |
| telemetry_ms | 1267 | 0.242 | 0.216 | 0.427 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 10.745 | 4.666 | 45.176 |
| actor.physics | 4.380 | 2.098 | 18.166 |
| vehicle_tires.redraw_marks | 1.203 | 0.713 | 4.053 |
| west.telemetry.profile_process | 1.146 | 0.224 | 3.969 |
| urban.physics | 0.763 | 0.321 | 3.319 |
| gameplay.physics | 0.704 | 0.393 | 2.775 |
| west.world.process | 0.694 | 0.344 | 2.531 |
| terminal.physics | 0.603 | 0.309 | 2.482 |
| reflection.process | 0.488 | 0.024 | 2.480 |
| west.audio.nearby_process | 0.202 | 0.123 | 0.496 |
| west.camera.process | 0.170 | 0.156 | 0.265 |
| west.street.physics | 0.113 | 0.012 | 0.600 |
| west.audio.world_process | 0.098 | 0.060 | 0.273 |
| west.parking.physics | 0.031 | 0.017 | 0.123 |
| west.audio.weather_process | 0.015 | 0.014 | 0.022 |
| west.region.process | 0.010 | 0.006 | 0.010 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.3710055248618785, "system_profile_callback": 1.1160418310970799}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 3100; p50 9.138 ms/passo e p95 16.604 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 3 | 8.136 | 9.356 | — | — |
| 1 | 607 | 18.116 | 22.660 | 6.980 | 8.562 |
| 2 | 360 | 29.905 | 39.842 | 7.466 | 9.442 |
| 3 | 59 | 45.915 | 63.232 | 8.176 | 10.804 |
| 4 | 30 | 66.109 | 97.292 | 9.323 | 12.895 |
| 5 | 30 | 81.178 | 128.777 | 10.345 | 13.539 |
| 6 | 32 | 96.015 | 123.083 | 10.922 | 14.153 |
| 7 | 34 | 117.682 | 157.266 | 11.836 | 14.344 |
| 8 | 112 | 147.508 | 213.038 | 13.047 | 18.447 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 4.392 | 3.261 | 6.141 |
| actor.physics | 1.790 | 1.359 | 2.385 |
| vehicle.drive | 1.250 | 1.045 | 1.649 |
| vehicle.street_pre | 0.749 | 0.514 | 1.168 |
| vehicle.effects | 0.687 | 0.478 | 1.041 |
| actor.move_and_slide | 0.670 | 0.523 | 0.902 |
| actor.step | 0.497 | 0.365 | 0.684 |
| vehicle.effects.tires | 0.459 | 0.324 | 0.712 |
| vehicle.move_and_slide | 0.445 | 0.358 | 0.641 |
| west.vehicle.junction_gate | 0.391 | 0.347 | 0.528 |
| street.pre.props | 0.358 | 0.239 | 0.579 |
| vehicle_tires.contacts | 0.324 | 0.233 | 0.502 |
| urban.physics | 0.312 | 0.237 | 0.438 |
| gameplay.physics | 0.288 | 0.226 | 0.369 |
| terminal.physics | 0.247 | 0.186 | 0.334 |
| street.pre.people | 0.241 | 0.166 | 0.368 |
| street.pre.props.query | 0.219 | 0.146 | 0.355 |
| vehicle.street_post | 0.164 | 0.107 | 0.238 |
| vehicle.lod | 0.157 | 0.124 | 0.204 |
| west.vehicle.escape | 0.141 | 0.117 | 0.191 |
| actor.steering | 0.116 | 0.091 | 0.152 |
| west.vehicle.obstacle_ahead | 0.094 | 0.075 | 0.137 |
| west.vehicle.route_projection | 0.082 | 0.064 | 0.120 |
| west.vehicle.can_rotate | 0.081 | 0.054 | 0.128 |
| vehicle.effects.powertrain | 0.075 | 0.053 | 0.113 |
| actor.pose | 0.069 | 0.052 | 0.094 |
| vehicle.resting | 0.058 | 0.044 | 0.076 |
| vehicle.wheels | 0.054 | 0.039 | 0.082 |
| west.street.physics | 0.046 | 0.007 | 0.222 |
| vehicle.contacts | 0.045 | 0.029 | 0.067 |
| street.pre.crush | 0.040 | 0.027 | 0.063 |
| vehicle.effects.impact | 0.039 | 0.027 | 0.059 |
| west.street.watch_people | 0.037 | 0.000 | 0.209 |
| street.post.contacts | 0.036 | 0.018 | 0.039 |
| vehicle.wreck_lifetime | 0.027 | 0.021 | 0.037 |
| street.post.slide | 0.015 | 0.010 | 0.024 |
| street.post.crush | 0.013 | 0.009 | 0.021 |
| west.parking.physics | 0.013 | 0.009 | 0.018 |
| vehicle_tires.surface_emit | 0.010 | 0.000 | 0.035 |
| urban.refresh_presence | 0.009 | 0.000 | 0.053 |
| vehicle_tires.skid_audio | 0.006 | 0.005 | 0.010 |
| street.pre.people.cast | 0.006 | 0.000 | 0.029 |
| west.vehicle.rear_clear | 0.003 | 0.000 | 0.018 |
| street.pre.props.hit | 0.000 | 0.000 | 0.000 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_voice | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 10.745 | 4.666 | 45.176 | 1264 |
| actor.physics | root | None | 4.380 | 2.098 | 18.166 | 1264 |
| vehicle.drive | nested | vehicle.physics | 3.059 | 1.533 | 12.106 | 1264 |
| vehicle.street_pre | nested | vehicle.physics | 1.833 | 0.677 | 8.688 | 1261 |
| vehicle.effects | nested | vehicle.physics | 1.681 | 0.669 | 7.628 | 1261 |
| actor.move_and_slide | nested | actor.physics | 1.638 | 0.753 | 6.651 | 1264 |
| actor.step | nested | actor.physics | 1.216 | 0.564 | 5.143 | 1264 |
| vehicle_tires.redraw_marks | root | None | 1.203 | 0.713 | 4.053 | 1170 |
| west.telemetry.profile_process | root | None | 1.146 | 0.224 | 3.969 | 1267 |
| vehicle.effects.tires | nested | vehicle.effects | 1.123 | 0.453 | 5.239 | 1261 |
| vehicle.move_and_slide | nested | vehicle.physics | 1.089 | 0.486 | 4.734 | 1261 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.958 | 0.494 | 3.660 | 1264 |
| street.pre.props | nested | vehicle.street_pre | 0.876 | 0.312 | 4.049 | 1254 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.794 | 0.323 | 3.696 | 1178 |
| urban.physics | root | None | 0.763 | 0.321 | 3.319 | 1264 |
| gameplay.physics | root | None | 0.704 | 0.393 | 2.775 | 1264 |
| west.world.process | root | None | 0.694 | 0.344 | 2.531 | 1267 |
| terminal.physics | root | None | 0.603 | 0.309 | 2.482 | 1264 |
| street.pre.people | nested | vehicle.street_pre | 0.589 | 0.218 | 2.628 | 1254 |
| street.pre.props.query | nested | street.pre.props | 0.536 | 0.191 | 2.541 | 1252 |
| reflection.process | root | None | 0.488 | 0.024 | 2.480 | 1267 |
| vehicle.street_post | nested | vehicle.physics | 0.401 | 0.146 | 1.733 | 1261 |
| vehicle.lod | nested | vehicle.physics | 0.385 | 0.207 | 1.568 | 1264 |
| west.vehicle.escape | nested | vehicle.drive | 0.344 | 0.177 | 1.350 | 1264 |
| reflection.dynamic | nested | reflection.process | 0.343 | 0.000 | 2.100 | 1267 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.310 | 0.196 | 0.971 | 1169 |
| west.world.population_job | nested | west.world.process | 0.287 | 0.002 | 2.132 | 1267 |
| actor.steering | nested | actor.physics | 0.284 | 0.139 | 1.137 | 1264 |
| west.world.residency | nested | west.world.process | 0.237 | 0.216 | 0.368 | 1267 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.230 | 0.113 | 0.950 | 1239 |
| west.audio.nearby_process | root | None | 0.202 | 0.123 | 0.496 | 1267 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.201 | 0.096 | 0.849 | 1264 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.197 | 0.073 | 0.943 | 1252 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.183 | 0.072 | 0.836 | 1261 |
| west.camera.process | root | None | 0.170 | 0.156 | 0.265 | 1267 |
| actor.pose | nested | actor.physics | 0.169 | 0.079 | 0.696 | 1264 |
| vehicle.resting | nested | vehicle.physics | 0.141 | 0.075 | 0.574 | 1264 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.134 | 0.000 | 0.380 | 146 |
| vehicle.wheels | nested | vehicle.physics | 0.133 | 0.054 | 0.592 | 1261 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.127 | 0.000 | 0.295 | 86 |
| west.street.physics | root | None | 0.113 | 0.012 | 0.600 | 1264 |
| vehicle.contacts | nested | vehicle.physics | 0.110 | 0.040 | 0.486 | 1261 |
| west.audio.world_process | root | None | 0.098 | 0.060 | 0.273 | 1267 |
| street.pre.crush | nested | vehicle.street_pre | 0.097 | 0.037 | 0.456 | 1254 |
| vehicle.effects.impact | nested | vehicle.effects | 0.095 | 0.036 | 0.427 | 1261 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.091 | 0.000 | 0.055 | 147 |
| west.street.watch_people | nested | west.street.physics | 0.090 | 0.000 | 0.510 | 239 |
| street.post.contacts | nested | vehicle.street_post | 0.087 | 0.025 | 0.286 | 1261 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.083 | 0.000 | 0.000 | 40 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.081 | 0.038 | 0.350 | 1264 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.081 | 0.000 | 0.316 | 416 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.067 | 0.033 | 0.272 | 1264 |
| reflection.batch | nested | reflection.process | 0.044 | 0.000 | 0.245 | 1267 |
| west.audio.ambience | nested | west.audio.world_process | 0.040 | 0.027 | 0.114 | 1267 |
| street.post.slide | nested | vehicle.street_post | 0.036 | 0.013 | 0.174 | 1261 |
| street.post.crush | nested | vehicle.street_post | 0.033 | 0.012 | 0.149 | 1261 |
| west.parking.physics | root | None | 0.031 | 0.017 | 0.123 | 1264 |
| west.camera.cutaway | nested | west.camera.process | 0.029 | 0.027 | 0.045 | 1267 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.025 | 0.000 | 0.161 | 298 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.025 | 0.000 | 0.027 | 294 |
| street.crash | inclusive_unknown | None | 0.022 | 0.000 | 0.000 | 1 |
| urban.refresh_presence | nested | urban.physics | 0.021 | 0.000 | 0.160 | 172 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.016 | 0.007 | 0.072 | 1178 |
| west.camera.terrain_offset | nested | west.camera.process | 0.015 | 0.014 | 0.024 | 1267 |
| west.audio.weather_process | root | None | 0.015 | 0.014 | 0.022 | 1267 |
| street.crash.damage_self | nested | street.crash | 0.015 | 0.000 | 0.000 | 1 |
| street.pre.people.cast | nested | street.pre.people | 0.014 | 0.000 | 0.090 | 267 |
| reflection.registration | nested | reflection.process | 0.014 | 0.001 | 0.102 | 1267 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.014 | 0.012 | 0.022 | 1267 |
| west.traffic.route_near | nested | multiple_contexts | 0.011 | 0.000 | 0.000 | 23 |
| west.region.process | root | None | 0.010 | 0.006 | 0.010 | 1267 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.009 | 0.008 | 0.015 | 1267 |
| west.router.plan | nested | multiple_contexts | 0.008 | 0.000 | 0.000 | 2 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.007 | 0.000 | 0.051 | 118 |
| street.crash.damage_other | nested | street.crash | 0.007 | 0.000 | 0.000 | 1 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.007 | 1267 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 5 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.004 | 0.007 | 1267 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 5 |
| retire.drain | inclusive_unknown | None | 0.003 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 3 |
| street.scatter | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 2 |
| street.glass | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 2 |
| street.scatter.geometry | nested | street.scatter | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 23 |
| street.pre.props.hit | nested | street.pre.props | 0.001 | 0.000 | 0.000 | 9 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| street.pre.props.cast | nested | street.pre.props | 0.001 | 0.000 | 0.000 | 9 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.glass.resources | nested | street.glass | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 15 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| street.glass.attach | nested | street.glass | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 4 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 15 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 1 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 15 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 2 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| vehicle_tires.skid_voice | nested | vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 3.738 ms; p95 29.181 ms (1267 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 4.527 ms; p95 16.100 ms (1267 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## no_traffic_yield_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_yield_2.json`

Bracket válido em 787 quadros; inválido em 0. Passos físicos por quadro: `{"1": 24, "2": 217, "3": 193, "4": 126, "5": 61, "6": 47, "7": 41, "8": 78}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 787 | 42.390 | 31.036 | 102.486 |
| process_callback_ms | 787 | 12.822 | 10.975 | 26.881 |
| process_to_deferred_ms | 787 | 0.781 | 0.738 | 1.365 |
| deferred_to_render_pre_ms | 787 | 0.511 | 0.369 | 1.485 |
| render_bracket_ms | 787 | 4.720 | 4.510 | 6.484 |
| post_draw_to_physics_ms | 787 | 1.435 | 1.209 | 2.692 |
| pre_process_gap_ms | 787 | 5.323 | 4.402 | 10.900 |
| telemetry_ms | 787 | 0.274 | 0.256 | 0.405 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 19.141 | 14.149 | 47.589 |
| actor.physics | 6.250 | 4.585 | 15.567 |
| west.telemetry.profile_process | 2.120 | 1.889 | 4.088 |
| vehicle_tires.redraw_marks | 1.715 | 1.577 | 3.522 |
| urban.physics | 1.193 | 0.872 | 3.278 |
| gameplay.physics | 1.089 | 0.836 | 2.569 |
| west.world.process | 1.054 | 0.481 | 3.589 |
| terminal.physics | 0.918 | 0.713 | 2.274 |
| reflection.process | 0.507 | 0.026 | 3.450 |
| west.audio.nearby_process | 0.254 | 0.193 | 0.482 |
| west.camera.process | 0.184 | 0.175 | 0.262 |
| west.street.physics | 0.181 | 0.038 | 0.614 |
| west.audio.world_process | 0.122 | 0.069 | 0.319 |
| west.parking.physics | 0.048 | 0.035 | 0.117 |
| west.audio.weather_process | 0.017 | 0.016 | 0.022 |
| west.region.process | 0.013 | 0.007 | 0.011 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.5802693773824651, "system_profile_callback": 2.083466327827192}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 3039; p50 10.401 ms/passo e p95 16.194 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 1 | 24 | 22.420 | 25.269 | 8.456 | 9.957 |
| 2 | 217 | 33.589 | 41.201 | 8.567 | 10.047 |
| 3 | 193 | 48.674 | 66.129 | 9.505 | 11.989 |
| 4 | 126 | 64.740 | 83.419 | 10.198 | 13.053 |
| 5 | 61 | 78.297 | 104.837 | 10.588 | 14.377 |
| 6 | 47 | 92.922 | 115.465 | 10.932 | 13.618 |
| 7 | 41 | 115.272 | 158.568 | 11.688 | 14.720 |
| 8 | 78 | 141.377 | 209.043 | 12.778 | 18.579 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 4.957 | 4.420 | 6.747 |
| actor.physics | 1.619 | 1.472 | 2.188 |
| vehicle.drive | 1.284 | 1.140 | 1.741 |
| vehicle.street_pre | 0.951 | 0.837 | 1.314 |
| vehicle.effects | 0.800 | 0.724 | 1.102 |
| actor.move_and_slide | 0.566 | 0.515 | 0.766 |
| vehicle.effects.tires | 0.519 | 0.465 | 0.737 |
| vehicle.move_and_slide | 0.510 | 0.445 | 0.740 |
| actor.step | 0.465 | 0.427 | 0.607 |
| street.pre.props | 0.448 | 0.394 | 0.622 |
| west.vehicle.junction_gate | 0.375 | 0.319 | 0.538 |
| vehicle_tires.contacts | 0.366 | 0.327 | 0.516 |
| street.pre.people | 0.312 | 0.266 | 0.452 |
| urban.physics | 0.309 | 0.288 | 0.454 |
| gameplay.physics | 0.282 | 0.255 | 0.346 |
| street.pre.props.query | 0.275 | 0.243 | 0.385 |
| terminal.physics | 0.238 | 0.216 | 0.304 |
| vehicle.street_post | 0.224 | 0.164 | 0.260 |
| vehicle.lod | 0.155 | 0.137 | 0.198 |
| west.vehicle.escape | 0.143 | 0.127 | 0.190 |
| actor.steering | 0.111 | 0.099 | 0.149 |
| west.vehicle.can_rotate | 0.096 | 0.084 | 0.140 |
| west.vehicle.route_projection | 0.095 | 0.087 | 0.128 |
| vehicle.effects.powertrain | 0.094 | 0.085 | 0.130 |
| west.vehicle.obstacle_ahead | 0.090 | 0.081 | 0.131 |
| street.post.contacts | 0.069 | 0.024 | 0.048 |
| vehicle.wheels | 0.069 | 0.062 | 0.093 |
| actor.pose | 0.066 | 0.058 | 0.089 |
| vehicle.resting | 0.063 | 0.056 | 0.082 |
| vehicle.contacts | 0.056 | 0.045 | 0.072 |
| street.pre.crush | 0.051 | 0.043 | 0.076 |
| vehicle.effects.impact | 0.050 | 0.043 | 0.074 |
| west.street.physics | 0.047 | 0.008 | 0.191 |
| west.street.watch_people | 0.036 | 0.000 | 0.175 |
| vehicle.wreck_lifetime | 0.027 | 0.024 | 0.035 |
| street.post.slide | 0.019 | 0.015 | 0.033 |
| street.post.crush | 0.016 | 0.014 | 0.023 |
| street.pre.people.cast | 0.016 | 0.007 | 0.070 |
| west.parking.physics | 0.012 | 0.011 | 0.017 |
| urban.refresh_presence | 0.009 | 0.000 | 0.051 |
| vehicle_tires.surface_emit | 0.009 | 0.000 | 0.028 |
| vehicle_tires.skid_audio | 0.008 | 0.007 | 0.011 |
| west.vehicle.rear_clear | 0.003 | 0.000 | 0.018 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 19.141 | 14.149 | 47.589 | 787 |
| actor.physics | root | None | 6.250 | 4.585 | 15.567 | 787 |
| vehicle.drive | nested | vehicle.physics | 4.960 | 3.656 | 12.554 | 787 |
| vehicle.street_pre | nested | vehicle.physics | 3.671 | 2.782 | 9.393 | 787 |
| vehicle.effects | nested | vehicle.physics | 3.090 | 2.344 | 7.935 | 787 |
| actor.move_and_slide | nested | actor.physics | 2.185 | 1.637 | 5.382 | 787 |
| west.telemetry.profile_process | root | None | 2.120 | 1.889 | 4.088 | 787 |
| vehicle.effects.tires | nested | vehicle.effects | 2.005 | 1.522 | 5.057 | 787 |
| vehicle.move_and_slide | nested | vehicle.physics | 1.971 | 1.472 | 5.225 | 787 |
| actor.step | nested | actor.physics | 1.797 | 1.356 | 4.472 | 787 |
| street.pre.props | nested | vehicle.street_pre | 1.730 | 1.328 | 4.502 | 787 |
| vehicle_tires.redraw_marks | root | None | 1.715 | 1.577 | 3.522 | 781 |
| west.vehicle.junction_gate | nested | vehicle.drive | 1.450 | 1.040 | 3.877 | 787 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 1.413 | 1.080 | 3.577 | 787 |
| street.pre.people | nested | vehicle.street_pre | 1.206 | 0.907 | 3.165 | 787 |
| urban.physics | root | None | 1.193 | 0.872 | 3.278 | 787 |
| gameplay.physics | root | None | 1.089 | 0.836 | 2.569 | 787 |
| street.pre.props.query | nested | street.pre.props | 1.060 | 0.812 | 2.751 | 787 |
| west.world.process | root | None | 1.054 | 0.481 | 3.589 | 787 |
| terminal.physics | root | None | 0.918 | 0.713 | 2.274 | 787 |
| vehicle.street_post | nested | vehicle.physics | 0.865 | 0.528 | 1.933 | 787 |
| vehicle.lod | nested | vehicle.physics | 0.599 | 0.425 | 1.510 | 787 |
| west.world.population_job | nested | west.world.process | 0.552 | 0.097 | 3.288 | 787 |
| west.vehicle.escape | nested | vehicle.drive | 0.551 | 0.404 | 1.392 | 787 |
| reflection.process | root | None | 0.507 | 0.026 | 3.450 | 787 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.454 | 0.419 | 0.926 | 781 |
| actor.steering | nested | actor.physics | 0.427 | 0.317 | 1.072 | 787 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.370 | 0.276 | 1.006 | 787 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.369 | 0.291 | 0.910 | 787 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.361 | 0.278 | 0.905 | 787 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.347 | 0.248 | 0.931 | 786 |
| reflection.dynamic | nested | reflection.process | 0.310 | 0.000 | 2.762 | 787 |
| west.world.residency | nested | west.world.process | 0.270 | 0.254 | 0.399 | 787 |
| street.post.contacts | nested | vehicle.street_post | 0.268 | 0.081 | 0.307 | 787 |
| vehicle.wheels | nested | vehicle.physics | 0.265 | 0.203 | 0.685 | 787 |
| actor.pose | nested | actor.physics | 0.255 | 0.187 | 0.645 | 787 |
| west.audio.nearby_process | root | None | 0.254 | 0.193 | 0.482 | 787 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.246 | 0.000 | 2.550 | 140 |
| vehicle.resting | nested | vehicle.physics | 0.242 | 0.174 | 0.602 | 787 |
| west.world.operation.population_spawn | nested | multiple_contexts | 0.232 | 0.000 | 2.452 | 100 |
| vehicle.contacts | nested | vehicle.physics | 0.215 | 0.147 | 0.535 | 787 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.200 | 0.000 | 0.070 | 139 |
| street.pre.crush | nested | vehicle.street_pre | 0.197 | 0.142 | 0.530 | 787 |
| vehicle.effects.impact | nested | vehicle.effects | 0.193 | 0.144 | 0.505 | 787 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.188 | 0.000 | 0.000 | 34 |
| west.camera.process | root | None | 0.184 | 0.175 | 0.262 | 787 |
| west.street.physics | root | None | 0.181 | 0.038 | 0.614 | 787 |
| police.physics | inclusive_unknown | None | 0.169 | 0.000 | 1.091 | 69 |
| street.crash | inclusive_unknown | None | 0.155 | 0.000 | 0.000 | 10 |
| west.street.watch_people | nested | west.street.physics | 0.140 | 0.000 | 0.543 | 234 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.128 | 0.093 | 0.318 | 787 |
| west.audio.world_process | root | None | 0.122 | 0.069 | 0.319 | 787 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.122 | 0.000 | 0.316 | 387 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.105 | 0.077 | 0.264 | 787 |
| police.move_and_slide | inclusive_unknown | None | 0.085 | 0.000 | 0.581 | 69 |
| street.post.slide | nested | vehicle.street_post | 0.073 | 0.051 | 0.211 | 787 |
| street.crash.damage_self | nested | street.crash | 0.073 | 0.000 | 0.000 | 10 |
| street.crash.damage_other | nested | street.crash | 0.069 | 0.000 | 0.000 | 10 |
| street.post.crush | nested | vehicle.street_post | 0.063 | 0.047 | 0.171 | 787 |
| street.pre.people.cast | nested | street.pre.people | 0.062 | 0.022 | 0.250 | 403 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.050 | 0.000 | 0.034 | 280 |
| west.audio.ambience | nested | west.audio.world_process | 0.048 | 0.030 | 0.116 | 787 |
| west.parking.physics | root | None | 0.048 | 0.035 | 0.117 | 787 |
| reflection.batch | nested | reflection.process | 0.041 | 0.000 | 0.298 | 787 |
| urban.refresh_presence | nested | urban.physics | 0.034 | 0.000 | 0.192 | 168 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.034 | 0.000 | 0.146 | 314 |
| west.camera.cutaway | nested | west.camera.process | 0.031 | 0.029 | 0.042 | 787 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.029 | 0.022 | 0.074 | 787 |
| reflection.registration | nested | reflection.process | 0.023 | 0.001 | 0.146 | 787 |
| west.traffic.route_near | nested | multiple_contexts | 0.020 | 0.000 | 0.000 | 26 |
| west.camera.terrain_offset | nested | west.camera.process | 0.017 | 0.016 | 0.024 | 787 |
| west.audio.weather_process | root | None | 0.017 | 0.016 | 0.022 | 787 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.015 | 0.014 | 0.022 | 787 |
| west.router.plan | nested | multiple_contexts | 0.015 | 0.000 | 0.000 | 2 |
| street.glass | inclusive_unknown | None | 0.013 | 0.000 | 0.000 | 10 |
| west.region.process | root | None | 0.013 | 0.007 | 0.011 | 787 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.011 | 0.009 | 0.015 | 787 |
| street.scatter | inclusive_unknown | None | 0.011 | 0.000 | 0.000 | 10 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.010 | 0.000 | 0.077 | 119 |
| street.scatter.geometry | nested | street.scatter | 0.009 | 0.000 | 0.000 | 10 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.008 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.007 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.006 | 0.000 | 0.000 | 4 |
| retire.drain | inclusive_unknown | None | 0.005 | 0.000 | 0.000 | 3 |
| west.audio.radio | nested | west.audio.world_process | 0.005 | 0.004 | 0.007 | 787 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.005 | 0.000 | 0.000 | 3 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.004 | 0.008 | 787 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.004 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 26 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 2 |
| street.glass.resources | nested | street.glass | 0.002 | 0.000 | 0.000 | 10 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| ground_blood.allocate | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 5 |
| street.glass.attach | nested | street.glass | 0.001 | 0.000 | 0.000 | 10 |
| vehicle_damage.wear | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 12 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 28 |
| street.slide.rotate | nested | street.post.slide | 0.001 | 0.000 | 0.000 | 33 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 4 |
| west.router.csharp.build | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 10 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 10 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 10 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 10 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 28 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 28 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| gameplay.damage | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| gameplay.fire_at | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 10.140 ms; p95 32.993 ms (787 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 7.328 ms; p95 16.636 ms (787 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## population0_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\population0_1.json`

Bracket válido em 3107 quadros; inválido em 0. Passos físicos por quadro: `{"0": 441, "1": 2506, "2": 150, "3": 10}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 3107 | 5.309 | 5.602 | 10.110 |
| process_callback_ms | 3107 | 4.669 | 4.070 | 7.999 |
| process_to_deferred_ms | 3107 | 0.281 | 0.143 | 0.618 |
| deferred_to_render_pre_ms | 3107 | 0.203 | 0.181 | 0.289 |
| render_bracket_ms | 3107 | 3.311 | 3.307 | 3.998 |
| post_draw_to_physics_ms | 3107 | 0.573 | 0.643 | 0.943 |
| pre_process_gap_ms | 3107 | 1.439 | 1.437 | 2.164 |
| telemetry_ms | 3107 | 0.196 | 0.194 | 0.273 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 2.933 | 3.067 | 5.300 |
| vehicle_tires.redraw_marks | 0.416 | 0.316 | 1.436 |
| west.world.process | 0.385 | 0.266 | 0.850 |
| west.telemetry.profile_process | 0.328 | 0.179 | 1.290 |
| reflection.process | 0.312 | 0.021 | 2.194 |
| urban.physics | 0.233 | 0.225 | 0.483 |
| gameplay.physics | 0.204 | 0.214 | 0.409 |
| terminal.physics | 0.172 | 0.184 | 0.303 |
| west.camera.process | 0.152 | 0.144 | 0.216 |
| west.audio.nearby_process | 0.135 | 0.110 | 0.288 |
| actor.physics | 0.110 | 0.114 | 0.267 |
| west.audio.world_process | 0.067 | 0.055 | 0.160 |
| west.street.physics | 0.020 | 0.006 | 0.198 |
| west.traffic_yield.physics | 0.017 | 0.018 | 0.034 |
| west.audio.weather_process | 0.014 | 0.014 | 0.017 |
| west.parking.physics | 0.009 | 0.009 | 0.019 |
| west.region.process | 0.007 | 0.006 | 0.007 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.12452333440617959, "system_profile_callback": 0.3063099452848407}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2836; p50 5.787 ms/passo e p95 7.446 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 441 | 7.784 | 10.273 | — | — |
| 1 | 2506 | 15.271 | 20.249 | 5.723 | 7.222 |
| 2 | 150 | 26.164 | 32.488 | 6.355 | 8.223 |
| 3 | 10 | 37.762 | 45.161 | 6.010 | 8.423 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 3.213 | 3.171 | 4.230 |
| vehicle.drive | 0.903 | 0.882 | 1.234 |
| vehicle.effects | 0.541 | 0.533 | 0.825 |
| vehicle.street_pre | 0.499 | 0.481 | 0.725 |
| vehicle.effects.tires | 0.359 | 0.360 | 0.585 |
| vehicle.move_and_slide | 0.342 | 0.321 | 0.557 |
| street.pre.props | 0.293 | 0.285 | 0.441 |
| west.vehicle.junction_gate | 0.273 | 0.260 | 0.431 |
| urban.physics | 0.255 | 0.239 | 0.391 |
| vehicle_tires.contacts | 0.249 | 0.252 | 0.407 |
| gameplay.physics | 0.224 | 0.217 | 0.269 |
| terminal.physics | 0.188 | 0.187 | 0.243 |
| street.pre.props.query | 0.180 | 0.175 | 0.275 |
| actor.physics | 0.121 | 0.150 | 0.244 |
| vehicle.street_post | 0.119 | 0.116 | 0.170 |
| vehicle.lod | 0.113 | 0.111 | 0.135 |
| west.vehicle.escape | 0.099 | 0.093 | 0.151 |
| street.pre.people | 0.087 | 0.085 | 0.124 |
| west.vehicle.route_projection | 0.067 | 0.064 | 0.095 |
| west.vehicle.obstacle_ahead | 0.064 | 0.062 | 0.108 |
| west.vehicle.can_rotate | 0.063 | 0.061 | 0.094 |
| vehicle.effects.powertrain | 0.059 | 0.056 | 0.095 |
| vehicle.wheels | 0.045 | 0.044 | 0.066 |
| vehicle.resting | 0.042 | 0.041 | 0.051 |
| actor.move_and_slide | 0.038 | 0.043 | 0.087 |
| actor.step | 0.036 | 0.041 | 0.077 |
| vehicle.contacts | 0.033 | 0.032 | 0.046 |
| vehicle.effects.impact | 0.032 | 0.030 | 0.046 |
| street.pre.crush | 0.030 | 0.029 | 0.043 |
| west.street.physics | 0.022 | 0.006 | 0.197 |
| vehicle.wreck_lifetime | 0.020 | 0.019 | 0.025 |
| west.traffic_yield.physics | 0.019 | 0.018 | 0.024 |
| street.post.contacts | 0.018 | 0.017 | 0.029 |
| west.street.watch_people | 0.015 | 0.000 | 0.185 |
| street.post.slide | 0.011 | 0.010 | 0.015 |
| actor.steering | 0.011 | 0.014 | 0.020 |
| street.post.crush | 0.010 | 0.010 | 0.015 |
| west.parking.physics | 0.009 | 0.009 | 0.013 |
| vehicle_tires.surface_emit | 0.009 | 0.000 | 0.040 |
| urban.refresh_presence | 0.007 | 0.000 | 0.093 |
| actor.pose | 0.005 | 0.007 | 0.010 |
| vehicle_tires.skid_audio | 0.005 | 0.005 | 0.009 |
| west.traffic_yield.hazards | 0.005 | 0.005 | 0.006 |
| west.vehicle.rear_clear | 0.004 | 0.000 | 0.029 |
| street.pre.props.cast | 0.001 | 0.000 | 0.000 |
| street.pre.props.hit | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 2.933 | 3.067 | 5.300 | 2666 |
| vehicle.drive | nested | vehicle.physics | 0.824 | 0.857 | 1.462 | 2666 |
| vehicle.effects | nested | vehicle.physics | 0.494 | 0.507 | 1.007 | 2666 |
| vehicle.street_pre | nested | vehicle.physics | 0.455 | 0.460 | 0.833 | 2666 |
| vehicle_tires.redraw_marks | root | None | 0.416 | 0.316 | 1.436 | 2271 |
| west.world.process | root | None | 0.385 | 0.266 | 0.850 | 3107 |
| west.telemetry.profile_process | root | None | 0.328 | 0.179 | 1.290 | 3107 |
| vehicle.effects.tires | nested | vehicle.effects | 0.328 | 0.336 | 0.720 | 2666 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.313 | 0.303 | 0.641 | 2666 |
| reflection.process | root | None | 0.312 | 0.021 | 2.194 | 3107 |
| street.pre.props | nested | vehicle.street_pre | 0.268 | 0.270 | 0.495 | 2666 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.249 | 0.248 | 0.469 | 2666 |
| urban.physics | root | None | 0.233 | 0.225 | 0.483 | 2666 |
| reflection.dynamic | nested | reflection.process | 0.229 | 0.000 | 1.850 | 3107 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.228 | 0.234 | 0.503 | 2632 |
| west.world.residency | nested | west.world.process | 0.218 | 0.206 | 0.310 | 3107 |
| gameplay.physics | root | None | 0.204 | 0.214 | 0.409 | 2666 |
| terminal.physics | root | None | 0.172 | 0.184 | 0.303 | 2666 |
| street.pre.props.query | nested | street.pre.props | 0.164 | 0.166 | 0.307 | 2666 |
| west.camera.process | root | None | 0.152 | 0.144 | 0.216 | 3107 |
| west.audio.nearby_process | root | None | 0.135 | 0.110 | 0.288 | 3107 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.117 | 0.101 | 0.351 | 2271 |
| actor.physics | root | None | 0.110 | 0.114 | 0.267 | 1835 |
| vehicle.street_post | nested | vehicle.physics | 0.108 | 0.110 | 0.206 | 2666 |
| vehicle.lod | nested | vehicle.physics | 0.103 | 0.108 | 0.214 | 2666 |
| west.vehicle.escape | nested | vehicle.drive | 0.091 | 0.089 | 0.173 | 2666 |
| west.world.population_job | nested | west.world.process | 0.086 | 0.002 | 0.122 | 3107 |
| street.pre.people | nested | vehicle.street_pre | 0.079 | 0.080 | 0.144 | 2666 |
| west.audio.world_process | root | None | 0.067 | 0.055 | 0.160 | 3107 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.061 | 0.062 | 0.112 | 2666 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.059 | 0.058 | 0.124 | 2644 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.058 | 0.058 | 0.112 | 2666 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.055 | 0.000 | 0.035 | 183 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.054 | 0.053 | 0.110 | 2666 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.051 | 0.000 | 0.000 | 55 |
| vehicle.wheels | nested | vehicle.physics | 0.041 | 0.042 | 0.074 | 2666 |
| vehicle.resting | nested | vehicle.physics | 0.038 | 0.040 | 0.079 | 2666 |
| actor.move_and_slide | nested | actor.physics | 0.035 | 0.030 | 0.101 | 1835 |
| actor.step | nested | actor.physics | 0.033 | 0.031 | 0.086 | 1835 |
| reflection.batch | nested | reflection.process | 0.030 | 0.000 | 0.236 | 3107 |
| vehicle.contacts | nested | vehicle.physics | 0.030 | 0.031 | 0.056 | 2666 |
| vehicle.effects.impact | nested | vehicle.effects | 0.029 | 0.029 | 0.057 | 2666 |
| street.pre.crush | nested | vehicle.street_pre | 0.028 | 0.028 | 0.052 | 2666 |
| west.audio.ambience | nested | west.audio.world_process | 0.027 | 0.025 | 0.050 | 3107 |
| west.camera.cutaway | nested | west.camera.process | 0.027 | 0.025 | 0.033 | 3107 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.025 | 0.000 | 0.183 | 437 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.023 | 0.023 | 0.044 | 2666 |
| west.street.physics | root | None | 0.020 | 0.006 | 0.198 | 2666 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.018 | 0.018 | 0.035 | 2666 |
| west.traffic_yield.physics | root | None | 0.017 | 0.018 | 0.034 | 2666 |
| street.post.contacts | nested | vehicle.street_post | 0.017 | 0.017 | 0.034 | 2666 |
| west.audio.weather_process | root | None | 0.014 | 0.014 | 0.017 | 3107 |
| west.camera.terrain_offset | nested | west.camera.process | 0.014 | 0.013 | 0.017 | 3107 |
| west.street.watch_people | nested | west.street.physics | 0.014 | 0.000 | 0.185 | 219 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.013 | 0.012 | 0.015 | 3107 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.011 | 0.000 | 0.018 | 367 |
| street.post.slide | nested | vehicle.street_post | 0.010 | 0.010 | 0.019 | 2666 |
| actor.steering | nested | actor.physics | 0.010 | 0.011 | 0.023 | 1835 |
| street.post.crush | nested | vehicle.street_post | 0.009 | 0.010 | 0.018 | 2666 |
| west.parking.physics | root | None | 0.009 | 0.009 | 0.019 | 2666 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.008 | 0.008 | 0.010 | 3107 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.008 | 0.000 | 0.040 | 603 |
| urban.refresh_presence | nested | urban.physics | 0.007 | 0.000 | 0.087 | 158 |
| west.region.process | root | None | 0.007 | 0.006 | 0.007 | 3107 |
| actor.pose | nested | actor.physics | 0.005 | 0.006 | 0.012 | 1835 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.005 | 0.005 | 0.010 | 2632 |
| west.traffic.route_near | nested | multiple_contexts | 0.005 | 0.000 | 0.000 | 30 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.005 | 0.005 | 0.009 | 2666 |
| reflection.registration | nested | reflection.process | 0.004 | 0.001 | 0.001 | 3107 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.005 | 3107 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.004 | 0.000 | 0.029 | 391 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.003 | 0.005 | 3107 |
| west.router.plan | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 6 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 4 |
| street.pre.props.cast | nested | street.pre.props | 0.001 | 0.000 | 0.000 | 49 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 30 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| retire.drain | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 2 |
| street.pre.props.hit | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 1 |
| street.scatter | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.000 | 0.000 | 0.005 | 183 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| street.scatter.geometry | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 11 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 11 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 11 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 1.673 ms; p95 3.595 ms (3107 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 2.909 ms; p95 5.192 ms (3107 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## population0_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\population0_2.json`

Bracket válido em 2428 quadros; inválido em 0. Passos físicos por quadro: `{"0": 170, "1": 1758, "2": 441, "3": 46, "4": 10, "6": 1, "7": 2}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 2428 | 8.005 | 6.510 | 17.479 |
| process_callback_ms | 2428 | 5.560 | 4.567 | 11.057 |
| process_to_deferred_ms | 2428 | 0.319 | 0.150 | 0.674 |
| deferred_to_render_pre_ms | 2428 | 0.254 | 0.213 | 0.410 |
| render_bracket_ms | 2428 | 3.618 | 3.576 | 4.358 |
| post_draw_to_physics_ms | 2428 | 0.617 | 0.618 | 1.043 |
| pre_process_gap_ms | 2428 | 1.724 | 1.589 | 2.823 |
| telemetry_ms | 2428 | 0.220 | 0.215 | 0.303 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 4.306 | 3.589 | 9.391 |
| actor.physics | 0.627 | 0.565 | 1.613 |
| west.telemetry.profile_process | 0.537 | 0.208 | 2.081 |
| vehicle_tires.redraw_marks | 0.444 | 0.339 | 1.357 |
| west.world.process | 0.423 | 0.294 | 0.960 |
| reflection.process | 0.373 | 0.024 | 2.566 |
| gameplay.physics | 0.270 | 0.225 | 0.539 |
| urban.physics | 0.251 | 0.222 | 0.575 |
| terminal.physics | 0.251 | 0.214 | 0.529 |
| west.region.process | 0.217 | 0.006 | 1.181 |
| west.camera.process | 0.167 | 0.159 | 0.230 |
| west.audio.nearby_process | 0.154 | 0.123 | 0.333 |
| west.audio.world_process | 0.076 | 0.061 | 0.198 |
| west.street.physics | 0.028 | 0.007 | 0.231 |
| west.traffic_yield.physics | 0.024 | 0.020 | 0.045 |
| west.audio.weather_process | 0.016 | 0.015 | 0.019 |
| west.parking.physics | 0.012 | 0.009 | 0.025 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.17059349258649095, "system_profile_callback": 0.5109752883031301}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2838; p50 6.614 ms/passo e p95 9.501 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 170 | 7.925 | 10.405 | — | — |
| 1 | 1758 | 16.372 | 22.031 | 6.268 | 8.374 |
| 2 | 441 | 28.612 | 39.471 | 7.224 | 10.133 |
| 3 | 46 | 42.751 | 58.944 | 8.186 | 10.581 |
| 4 | 10 | 62.546 | 100.635 | 9.498 | 11.678 |
| 6 | 1 | 109.825 | 109.825 | 6.073 | 6.073 |
| 7 | 2 | 66.367 | 66.367 | 6.139 | 6.139 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 3.684 | 3.485 | 5.148 |
| vehicle.drive | 1.014 | 0.973 | 1.394 |
| vehicle.effects | 0.573 | 0.526 | 1.024 |
| vehicle.street_pre | 0.564 | 0.554 | 0.846 |
| actor.physics | 0.537 | 0.567 | 0.841 |
| vehicle.move_and_slide | 0.394 | 0.373 | 0.628 |
| vehicle.effects.tires | 0.362 | 0.327 | 0.738 |
| street.pre.props | 0.330 | 0.321 | 0.518 |
| west.vehicle.junction_gate | 0.298 | 0.282 | 0.423 |
| vehicle_tires.contacts | 0.252 | 0.228 | 0.510 |
| gameplay.physics | 0.231 | 0.224 | 0.282 |
| urban.physics | 0.215 | 0.209 | 0.372 |
| terminal.physics | 0.214 | 0.212 | 0.277 |
| street.pre.props.query | 0.202 | 0.197 | 0.321 |
| actor.move_and_slide | 0.183 | 0.181 | 0.343 |
| actor.pose | 0.172 | 0.203 | 0.295 |
| vehicle.street_post | 0.167 | 0.139 | 0.214 |
| vehicle.lod | 0.126 | 0.121 | 0.156 |
| west.vehicle.escape | 0.113 | 0.105 | 0.171 |
| street.pre.people | 0.096 | 0.094 | 0.144 |
| west.vehicle.route_projection | 0.075 | 0.075 | 0.113 |
| west.vehicle.can_rotate | 0.069 | 0.068 | 0.110 |
| vehicle.effects.powertrain | 0.067 | 0.062 | 0.116 |
| west.vehicle.obstacle_ahead | 0.067 | 0.064 | 0.123 |
| vehicle.contacts | 0.066 | 0.038 | 0.058 |
| actor.step | 0.066 | 0.056 | 0.122 |
| vehicle.wheels | 0.053 | 0.052 | 0.079 |
| vehicle.resting | 0.047 | 0.046 | 0.057 |
| street.post.contacts | 0.047 | 0.020 | 0.037 |
| vehicle.effects.impact | 0.037 | 0.034 | 0.057 |
| street.pre.crush | 0.035 | 0.034 | 0.051 |
| west.street.physics | 0.024 | 0.007 | 0.202 |
| vehicle.wreck_lifetime | 0.022 | 0.022 | 0.029 |
| west.traffic_yield.physics | 0.020 | 0.019 | 0.025 |
| actor.steering | 0.017 | 0.016 | 0.026 |
| west.street.watch_people | 0.016 | 0.000 | 0.188 |
| street.post.slide | 0.014 | 0.013 | 0.023 |
| street.post.crush | 0.012 | 0.011 | 0.017 |
| west.parking.physics | 0.010 | 0.009 | 0.014 |
| urban.refresh_presence | 0.010 | 0.000 | 0.070 |
| vehicle_tires.surface_emit | 0.007 | 0.000 | 0.042 |
| vehicle_tires.skid_audio | 0.006 | 0.005 | 0.011 |
| west.traffic_yield.hazards | 0.006 | 0.005 | 0.007 |
| west.vehicle.rear_clear | 0.003 | 0.000 | 0.028 |
| street.pre.props.hit | 0.000 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_voice | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 4.306 | 3.589 | 9.391 | 2258 |
| vehicle.drive | nested | vehicle.physics | 1.185 | 0.999 | 2.539 | 2258 |
| vehicle.effects | nested | vehicle.physics | 0.670 | 0.560 | 1.671 | 2258 |
| vehicle.street_pre | nested | vehicle.physics | 0.659 | 0.585 | 1.456 | 2258 |
| actor.physics | root | None | 0.627 | 0.565 | 1.613 | 2256 |
| west.telemetry.profile_process | root | None | 0.537 | 0.208 | 2.081 | 2428 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.460 | 0.384 | 1.132 | 2258 |
| vehicle_tires.redraw_marks | root | None | 0.444 | 0.339 | 1.357 | 1581 |
| west.world.process | root | None | 0.423 | 0.294 | 0.960 | 2428 |
| vehicle.effects.tires | nested | vehicle.effects | 0.423 | 0.351 | 1.123 | 2258 |
| street.pre.props | nested | vehicle.street_pre | 0.386 | 0.342 | 0.860 | 2258 |
| reflection.process | root | None | 0.373 | 0.024 | 2.566 | 2428 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.348 | 0.291 | 0.770 | 2258 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.294 | 0.243 | 0.791 | 2000 |
| gameplay.physics | root | None | 0.270 | 0.225 | 0.539 | 2258 |
| reflection.dynamic | nested | reflection.process | 0.264 | 0.000 | 2.132 | 2428 |
| urban.physics | root | None | 0.251 | 0.222 | 0.575 | 2258 |
| terminal.physics | root | None | 0.251 | 0.214 | 0.529 | 2258 |
| street.pre.props.query | nested | street.pre.props | 0.236 | 0.210 | 0.518 | 2258 |
| west.region.process | root | None | 0.217 | 0.006 | 1.181 | 2428 |
| actor.move_and_slide | nested | actor.physics | 0.214 | 0.183 | 0.560 | 2256 |
| west.world.residency | nested | west.world.process | 0.209 | 0.223 | 0.322 | 2127 |
| actor.pose | nested | actor.physics | 0.201 | 0.200 | 0.574 | 2256 |
| vehicle.street_post | nested | vehicle.physics | 0.195 | 0.144 | 0.379 | 2258 |
| west.camera.process | root | None | 0.167 | 0.159 | 0.230 | 2428 |
| west.audio.nearby_process | root | None | 0.154 | 0.123 | 0.333 | 2428 |
| vehicle.lod | nested | vehicle.physics | 0.148 | 0.122 | 0.306 | 2258 |
| west.vehicle.escape | nested | vehicle.drive | 0.133 | 0.110 | 0.288 | 2258 |
| west.world.population_job | nested | west.world.process | 0.127 | 0.002 | 0.151 | 2127 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.126 | 0.114 | 0.359 | 1579 |
| street.pre.people | nested | vehicle.street_pre | 0.113 | 0.097 | 0.258 | 2258 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.108 | 0.000 | 1.106 | 199 |
| west.world.operation.population_job:traffic | nested | multiple_contexts | 0.088 | 0.000 | 0.041 | 164 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.088 | 0.078 | 0.199 | 2258 |
| west.world.operation.traffic_spawn | nested | multiple_contexts | 0.083 | 0.000 | 0.000 | 59 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.081 | 0.071 | 0.189 | 2258 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.078 | 0.066 | 0.191 | 2258 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.078 | 0.069 | 0.196 | 2104 |
| vehicle.contacts | nested | vehicle.physics | 0.077 | 0.039 | 0.104 | 2258 |
| actor.step | nested | actor.physics | 0.077 | 0.057 | 0.211 | 2256 |
| west.audio.world_process | root | None | 0.076 | 0.061 | 0.198 | 2428 |
| vehicle.wheels | nested | vehicle.physics | 0.062 | 0.054 | 0.141 | 2258 |
| vehicle.resting | nested | vehicle.physics | 0.055 | 0.046 | 0.112 | 2258 |
| street.post.contacts | nested | vehicle.street_post | 0.055 | 0.021 | 0.059 | 2258 |
| stream.harbor.record.building | inclusive_unknown | None | 0.046 | 0.000 | 0.000 | 2 |
| vehicle.effects.impact | nested | vehicle.effects | 0.043 | 0.036 | 0.103 | 2258 |
| street.pre.crush | nested | vehicle.street_pre | 0.041 | 0.036 | 0.090 | 2258 |
| reflection.batch | nested | reflection.process | 0.039 | 0.000 | 0.305 | 2428 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.034 | 0.000 | 0.217 | 400 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.032 | 0.025 | 0.063 | 2258 |
| west.audio.ambience | nested | west.audio.world_process | 0.031 | 0.028 | 0.057 | 2428 |
| west.camera.cutaway | nested | west.camera.process | 0.029 | 0.028 | 0.037 | 2428 |
| street.crash | inclusive_unknown | None | 0.029 | 0.000 | 0.000 | 5 |
| west.street.physics | root | None | 0.028 | 0.007 | 0.231 | 2258 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.026 | 0.022 | 0.055 | 2258 |
| west.traffic_yield.physics | root | None | 0.024 | 0.020 | 0.045 | 2258 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.020 | 0.000 | 0.000 | 5 |
| actor.steering | nested | actor.physics | 0.020 | 0.016 | 0.047 | 2256 |
| west.street.watch_people | nested | west.street.physics | 0.019 | 0.000 | 0.212 | 207 |
| street.post.slide | nested | vehicle.street_post | 0.017 | 0.013 | 0.043 | 2258 |
| west.camera.terrain_offset | nested | west.camera.process | 0.016 | 0.015 | 0.019 | 2428 |
| west.audio.weather_process | root | None | 0.016 | 0.015 | 0.019 | 2428 |
| street.crash.damage_self | nested | street.crash | 0.015 | 0.000 | 0.000 | 5 |
| west.world.operation.population_job:equipment | nested | multiple_contexts | 0.015 | 0.000 | 0.022 | 328 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.014 | 0.013 | 0.017 | 2428 |
| street.post.crush | nested | vehicle.street_post | 0.014 | 0.012 | 0.031 | 2258 |
| street.crash.damage_other | nested | street.crash | 0.012 | 0.000 | 0.000 | 5 |
| west.parking.physics | root | None | 0.012 | 0.009 | 0.025 | 2258 |
| urban.refresh_presence | nested | urban.physics | 0.011 | 0.000 | 0.115 | 149 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.011 | 0.000 | 0.000 | 3 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.010 | 0.009 | 0.011 | 2128 |
| reflection.registration | nested | reflection.process | 0.009 | 0.001 | 0.026 | 2428 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.009 | 0.000 | 0.044 | 439 |
| retire.drain | inclusive_unknown | None | 0.008 | 0.000 | 0.000 | 13 |
| stream.harbor.record.cemetery | inclusive_unknown | None | 0.007 | 0.000 | 0.000 | 1 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.007 | 0.005 | 0.018 | 2000 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.007 | 0.006 | 0.013 | 2258 |
| west.traffic.route_near | nested | multiple_contexts | 0.006 | 0.000 | 0.000 | 30 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.006 | 0.000 | 0.000 | 1 |
| west.router.plan | nested | multiple_contexts | 0.005 | 0.000 | 0.000 | 2 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.005 | 2428 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.003 | 0.000 | 0.032 | 222 |
| west.world.logical_region | nested | west.world.process | 0.003 | 0.003 | 0.005 | 2127 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.003 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:ranch_single | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 5 |
| west.world.operation.spawn_vehicle_add_child:nimbus_minivan | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 5 |
| street.glass | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:cobra_v8 | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_add_child:sport_coupe | nested | multiple_contexts | 0.002 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:courier_van | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 4 |
| street.scatter | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 4 |
| street.scatter.geometry | nested | street.scatter | 0.001 | 0.000 | 0.000 | 4 |
| west.world.operation.spawn_vehicle_position_clear | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 30 |
| west.world.operation.spawn_vehicle_add_child:taxi_yellow | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| retire.detach_cached_records | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:bike_urban | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| west.world.operation.spawn_vehicle_add_child:bike_cruiser | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 1 |
| west.world.operation.population_job:citizen | nested | multiple_contexts | 0.000 | 0.000 | 0.006 | 164 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| west.world.operation.spawn_vehicle_add_child:bike_sport | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:arctic_jeep | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.world.operation.spawn_vehicle_add_child:union_sedan | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| stream.harbor.record.harbor_prop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| street.glass.resources | nested | street.glass | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 22 |
| stream.harbor.record.harbor_dressing | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| street.pre.props.hit | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 7 |
| street.glass.attach | nested | street.glass | 0.000 | 0.000 | 0.000 | 4 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 5 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 24 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 4 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 22 |
| ground_blood.allocate | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| street.pre.props.cast | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 2 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 4 |
| vehicle_tires.skid_voice | nested | vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 5 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 22 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:cargo_flatbed_truck | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_cruiser | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.spawn_vehicle_add_child:police_suv | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |
| west.world.operation.startup:prepared | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 1.813 ms; p95 4.747 ms (2428 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 3.164 ms; p95 6.033 ms (2428 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## session_profile0_1

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\session_profile0_1.json`

Bracket válido em 820 quadros; inválido em 0. Passos físicos por quadro: `{"1": 66, "2": 263, "3": 154, "4": 82, "5": 67, "6": 50, "7": 41, "8": 97}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 820 | 41.864 | 30.039 | 105.454 |
| process_callback_ms | 820 | 11.483 | 9.766 | 23.843 |
| process_to_deferred_ms | 820 | 0.640 | 0.660 | 1.217 |
| deferred_to_render_pre_ms | 820 | 0.620 | 0.434 | 1.601 |
| render_bracket_ms | 820 | 4.712 | 4.419 | 7.049 |
| post_draw_to_physics_ms | 820 | 1.036 | 0.929 | 1.952 |
| pre_process_gap_ms | 820 | 4.968 | 3.989 | 10.255 |
| telemetry_ms | 820 | 0.307 | 0.291 | 0.466 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Rodada inválida, excluída dos comparativos: `["runtime_console_errors"]`.


Erros durante execução em `D:\geteco\game\evidence\profile-west-cpu-20261013\session_profile0_1.console.log`; timings preservados somente como diagnóstico:

- Linha 9: SCRIPT ERROR: Invalid assignment of property or key 'emission_energy_multiplier' with value of type 'float' on a base object of type 'Nil'.
- Linha 23: SCRIPT ERROR: Trying to assign invalid previously freed instance.

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 16.881 | 11.920 | 44.328 |
| actor.physics | 8.175 | 5.857 | 20.438 |
| vehicle_tires.redraw_marks | 1.479 | 1.121 | 3.640 |
| gameplay.physics | 1.074 | 0.792 | 2.723 |
| urban.physics | 1.065 | 0.655 | 3.597 |
| terminal.physics | 0.972 | 0.671 | 2.540 |
| west.region.process | 0.963 | 0.009 | 2.811 |
| reflection.process | 0.836 | 0.040 | 3.771 |
| west.world.process | 0.794 | 0.341 | 3.537 |
| west.audio.nearby_process | 0.247 | 0.164 | 0.545 |
| west.camera.process | 0.189 | 0.176 | 0.283 |
| west.street.physics | 0.180 | 0.043 | 0.706 |
| west.audio.world_process | 0.121 | 0.068 | 0.315 |
| west.traffic_yield.physics | 0.090 | 0.064 | 0.227 |
| west.parking.physics | 0.047 | 0.033 | 0.119 |
| west.audio.weather_process | 0.018 | 0.017 | 0.025 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.573830487804878, "system_profile_callback": 0.0}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 3080; p50 10.621 ms/passo e p95 15.838 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 1 | 66 | 19.216 | 24.484 | 7.890 | 10.080 |
| 2 | 263 | 32.817 | 42.305 | 8.855 | 10.987 |
| 3 | 154 | 47.841 | 63.121 | 9.759 | 12.700 |
| 4 | 82 | 66.438 | 91.898 | 10.579 | 14.921 |
| 5 | 67 | 83.800 | 110.357 | 10.803 | 14.884 |
| 6 | 50 | 95.002 | 126.631 | 10.786 | 13.835 |
| 7 | 41 | 115.817 | 150.956 | 11.842 | 15.065 |
| 8 | 97 | 138.934 | 184.032 | 12.854 | 16.854 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 4.494 | 3.982 | 6.357 |
| actor.physics | 2.176 | 2.003 | 2.734 |
| vehicle.drive | 1.191 | 1.044 | 1.643 |
| vehicle.street_pre | 0.896 | 0.816 | 1.294 |
| actor.move_and_slide | 0.835 | 0.764 | 1.091 |
| vehicle.effects | 0.680 | 0.596 | 1.084 |
| actor.step | 0.595 | 0.539 | 0.780 |
| vehicle.move_and_slide | 0.543 | 0.528 | 0.825 |
| vehicle.effects.tires | 0.441 | 0.387 | 0.776 |
| street.pre.props | 0.423 | 0.380 | 0.601 |
| west.vehicle.junction_gate | 0.392 | 0.326 | 0.586 |
| street.pre.people | 0.326 | 0.285 | 0.496 |
| vehicle_tires.contacts | 0.321 | 0.281 | 0.568 |
| gameplay.physics | 0.286 | 0.254 | 0.374 |
| urban.physics | 0.284 | 0.240 | 0.538 |
| street.pre.props.query | 0.263 | 0.243 | 0.385 |
| terminal.physics | 0.259 | 0.236 | 0.351 |
| actor.pose | 0.220 | 0.241 | 0.373 |
| vehicle.street_post | 0.192 | 0.135 | 0.219 |
| vehicle.lod | 0.167 | 0.151 | 0.216 |
| west.vehicle.escape | 0.144 | 0.122 | 0.207 |
| actor.steering | 0.127 | 0.115 | 0.164 |
| vehicle.contacts | 0.108 | 0.048 | 0.081 |
| vehicle.effects.powertrain | 0.098 | 0.094 | 0.150 |
| west.vehicle.can_rotate | 0.097 | 0.084 | 0.156 |
| west.vehicle.route_projection | 0.090 | 0.080 | 0.134 |
| west.vehicle.obstacle_ahead | 0.085 | 0.078 | 0.140 |
| street.post.contacts | 0.077 | 0.027 | 0.049 |
| vehicle.wheels | 0.070 | 0.066 | 0.103 |
| vehicle.resting | 0.065 | 0.058 | 0.088 |
| street.pre.crush | 0.056 | 0.046 | 0.139 |
| vehicle.effects.impact | 0.052 | 0.046 | 0.086 |
| west.street.physics | 0.048 | 0.010 | 0.189 |
| west.street.watch_people | 0.035 | 0.000 | 0.179 |
| vehicle.wreck_lifetime | 0.029 | 0.026 | 0.040 |
| west.traffic_yield.physics | 0.024 | 0.021 | 0.033 |
| street.post.slide | 0.024 | 0.022 | 0.042 |
| street.pre.people.cast | 0.023 | 0.000 | 0.076 |
| street.post.crush | 0.016 | 0.015 | 0.024 |
| urban.refresh_presence | 0.013 | 0.000 | 0.056 |
| west.parking.physics | 0.012 | 0.011 | 0.018 |
| street.pre.props.hit | 0.009 | 0.000 | 0.000 |
| west.traffic_yield.hazards | 0.009 | 0.007 | 0.012 |
| vehicle_tires.surface_emit | 0.007 | 0.000 | 0.030 |
| vehicle_tires.skid_audio | 0.007 | 0.006 | 0.012 |
| west.vehicle.rear_clear | 0.002 | 0.000 | 0.020 |
| street.slide.rotate | 0.001 | 0.000 | 0.007 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| vehicle_tires.skid_voice | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 16.881 | 11.920 | 44.328 | 820 |
| actor.physics | root | None | 8.175 | 5.857 | 20.438 | 820 |
| vehicle.drive | nested | vehicle.physics | 4.474 | 3.019 | 11.978 | 820 |
| vehicle.street_pre | nested | vehicle.physics | 3.364 | 2.304 | 9.170 | 820 |
| actor.move_and_slide | nested | actor.physics | 3.138 | 2.259 | 8.032 | 820 |
| vehicle.effects | nested | vehicle.physics | 2.553 | 1.728 | 7.485 | 820 |
| actor.step | nested | actor.physics | 2.235 | 1.602 | 5.739 | 820 |
| vehicle.move_and_slide | nested | vehicle.physics | 2.041 | 1.535 | 5.043 | 820 |
| vehicle.effects.tires | nested | vehicle.effects | 1.656 | 1.107 | 5.267 | 820 |
| street.pre.props | nested | vehicle.street_pre | 1.589 | 1.106 | 4.267 | 820 |
| vehicle_tires.redraw_marks | root | None | 1.479 | 1.121 | 3.640 | 726 |
| west.vehicle.junction_gate | nested | vehicle.drive | 1.473 | 0.980 | 4.250 | 820 |
| street.pre.people | nested | vehicle.street_pre | 1.225 | 0.814 | 3.587 | 820 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 1.205 | 0.810 | 3.849 | 758 |
| gameplay.physics | root | None | 1.074 | 0.792 | 2.723 | 820 |
| urban.physics | root | None | 1.065 | 0.655 | 3.597 | 820 |
| street.pre.props.query | nested | street.pre.props | 0.989 | 0.710 | 2.712 | 820 |
| terminal.physics | root | None | 0.972 | 0.671 | 2.540 | 820 |
| west.region.process | root | None | 0.963 | 0.009 | 2.811 | 820 |
| reflection.process | root | None | 0.836 | 0.040 | 3.771 | 820 |
| actor.pose | nested | actor.physics | 0.827 | 0.605 | 2.285 | 820 |
| west.world.process | root | None | 0.794 | 0.341 | 3.537 | 820 |
| vehicle.street_post | nested | vehicle.physics | 0.721 | 0.398 | 1.609 | 820 |
| vehicle.lod | nested | vehicle.physics | 0.626 | 0.456 | 1.561 | 820 |
| west.vehicle.escape | nested | vehicle.drive | 0.540 | 0.363 | 1.465 | 820 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.510 | 0.000 | 1.742 | 269 |
| actor.steering | nested | actor.physics | 0.479 | 0.346 | 1.228 | 820 |
| reflection.dynamic | nested | reflection.process | 0.477 | 0.000 | 2.405 | 820 |
| vehicle.contacts | nested | vehicle.physics | 0.407 | 0.139 | 0.565 | 820 |
| west.world.population_job | nested | west.world.process | 0.401 | 0.003 | 3.208 | 566 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.386 | 0.316 | 0.906 | 726 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.369 | 0.274 | 0.946 | 820 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.366 | 0.245 | 1.074 | 820 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.338 | 0.229 | 0.922 | 820 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.319 | 0.218 | 0.901 | 769 |
| street.post.contacts | nested | vehicle.street_post | 0.289 | 0.080 | 0.349 | 820 |
| vehicle.wheels | nested | vehicle.physics | 0.263 | 0.188 | 0.730 | 820 |
| west.audio.nearby_process | root | None | 0.247 | 0.164 | 0.545 | 820 |
| vehicle.resting | nested | vehicle.physics | 0.245 | 0.171 | 0.627 | 820 |
| west.world.residency | nested | west.world.process | 0.211 | 0.243 | 0.452 | 566 |
| street.pre.crush | nested | vehicle.street_pre | 0.210 | 0.156 | 0.545 | 820 |
| vehicle.effects.impact | nested | vehicle.effects | 0.196 | 0.138 | 0.505 | 820 |
| west.camera.process | root | None | 0.189 | 0.176 | 0.283 | 820 |
| west.street.physics | root | None | 0.180 | 0.043 | 0.706 | 820 |
| stream.harbor.record.building | inclusive_unknown | None | 0.174 | 0.000 | 0.000 | 4 |
| street.crash | inclusive_unknown | None | 0.168 | 0.000 | 0.000 | 17 |
| reflection.batch | nested | reflection.process | 0.160 | 0.000 | 1.205 | 820 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.146 | 0.094 | 0.360 | 820 |
| west.street.watch_people | nested | west.street.physics | 0.133 | 0.000 | 0.639 | 204 |
| west.audio.world_process | root | None | 0.121 | 0.068 | 0.315 | 820 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.111 | 0.000 | 0.367 | 336 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.110 | 0.077 | 0.279 | 820 |
| west.traffic_yield.physics | root | None | 0.090 | 0.064 | 0.227 | 820 |
| street.post.slide | nested | vehicle.street_post | 0.089 | 0.064 | 0.234 | 820 |
| street.pre.people.cast | nested | street.pre.people | 0.087 | 0.000 | 0.485 | 407 |
| street.crash.damage_other | nested | street.crash | 0.084 | 0.000 | 0.000 | 17 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.080 | 0.000 | 0.000 | 6 |
| street.crash.damage_self | nested | street.crash | 0.068 | 0.000 | 0.000 | 17 |
| retire.drain | inclusive_unknown | None | 0.067 | 0.000 | 0.000 | 36 |
| street.post.crush | nested | vehicle.street_post | 0.061 | 0.042 | 0.169 | 820 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.057 | 0.000 | 0.000 | 3 |
| west.audio.ambience | nested | west.audio.world_process | 0.051 | 0.033 | 0.132 | 820 |
| reflection.registration | nested | reflection.process | 0.050 | 0.001 | 0.189 | 820 |
| urban.refresh_presence | nested | urban.physics | 0.048 | 0.000 | 0.222 | 147 |
| west.parking.physics | root | None | 0.047 | 0.033 | 0.119 | 820 |
| stream.harbor.record.cemetery | inclusive_unknown | None | 0.046 | 0.000 | 0.000 | 2 |
| west.camera.cutaway | nested | west.camera.process | 0.034 | 0.032 | 0.050 | 820 |
| street.pre.props.hit | nested | street.pre.props | 0.034 | 0.000 | 0.000 | 4 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.032 | 0.023 | 0.081 | 820 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.027 | 0.000 | 0.168 | 234 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.025 | 0.018 | 0.078 | 758 |
| street.glass | inclusive_unknown | None | 0.021 | 0.000 | 0.000 | 16 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.019 | 0.010 | 0.018 | 569 |
| west.camera.terrain_offset | nested | west.camera.process | 0.018 | 0.017 | 0.027 | 820 |
| west.audio.weather_process | root | None | 0.018 | 0.017 | 0.025 | 820 |
| street.scatter | inclusive_unknown | None | 0.017 | 0.000 | 0.000 | 16 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.016 | 0.015 | 0.024 | 820 |
| street.scatter.geometry | nested | street.scatter | 0.015 | 0.000 | 0.000 | 16 |
| west.router.plan | nested | multiple_contexts | 0.013 | 0.000 | 0.000 | 2 |
| west.traffic.route_near | nested | multiple_contexts | 0.013 | 0.000 | 0.000 | 19 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.011 | 0.000 | 0.000 | 1 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.008 | 0.000 | 0.044 | 103 |
| retire.detach_cached_records | inclusive_unknown | None | 0.007 | 0.000 | 0.000 | 5 |
| vehicle_damage.wear | inclusive_unknown | None | 0.006 | 0.000 | 0.039 | 130 |
| west.audio.radio | nested | west.audio.world_process | 0.005 | 0.005 | 0.008 | 820 |
| vehicle_damage.fire | inclusive_unknown | None | 0.004 | 0.000 | 0.027 | 108 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.004 | 0.009 | 566 |
| ground_blood.allocate | inclusive_unknown | None | 0.003 | 0.000 | 0.000 | 12 |
| street.slide.rotate | nested | street.post.slide | 0.003 | 0.000 | 0.018 | 139 |
| street.glass.resources | nested | street.glass | 0.003 | 0.000 | 0.000 | 16 |
| stream.harbor.record.harbor_prop | inclusive_unknown | None | 0.003 | 0.000 | 0.000 | 3 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 5 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.002 | 0.000 | 0.000 | 1 |
| street.pre.props.cast | nested | street.pre.props | 0.001 | 0.000 | 0.000 | 8 |
| stream.harbor.record.salvage | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 1 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.001 | 0.000 | 0.015 | 55 |
| stream.harbor.record.harbor_dressing | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 3 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| street.glass.attach | nested | street.glass | 0.001 | 0.000 | 0.000 | 16 |
| street.crash.impulse | nested | street.crash | 0.001 | 0.000 | 0.000 | 17 |
| street.scatter.material | nested | street.scatter | 0.001 | 0.000 | 0.000 | 16 |
| street.scatter.commit | nested | street.scatter | 0.001 | 0.000 | 0.000 | 16 |
| west.router.csharp.build | nested | multiple_contexts | 0.001 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 3 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.005 | 55 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 4 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 16 |
| vehicle_tires.skid_voice | nested | vehicle_tires.skid_audio | 0.000 | 0.000 | 0.000 | 3 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.002 | 55 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 6 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 9.220 ms; p95 34.227 ms (820 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 6.614 ms; p95 16.816 ms (820 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## session_profile0_2

Fonte: `D:\geteco\game\evidence\profile-west-cpu-20261013\session_profile0_2.json`

Bracket válido em 2090 quadros; inválido em 0. Passos físicos por quadro: `{"0": 56, "1": 1471, "2": 438, "3": 67, "4": 23, "5": 13, "6": 8, "7": 6, "8": 8}`.

| Fase medida | n | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|---:|
| physics_callback_ms | 2090 | 10.408 | 6.757 | 25.868 |
| process_callback_ms | 2090 | 5.877 | 4.989 | 11.342 |
| process_to_deferred_ms | 2090 | 0.438 | 0.323 | 0.805 |
| deferred_to_render_pre_ms | 2090 | 0.323 | 0.268 | 0.557 |
| render_bracket_ms | 2090 | 3.595 | 3.502 | 4.745 |
| post_draw_to_physics_ms | 2090 | 0.701 | 0.645 | 1.210 |
| pre_process_gap_ms | 2090 | 2.208 | 1.835 | 4.007 |
| telemetry_ms | 2090 | 0.226 | 0.211 | 0.331 |
| session_diagnostics_telemetry_ms | 0 | — | — | — |
| session_profile_telemetry_ms | 0 | — | — | — |

Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):

| Sistema | Média ms | p50 ms | p95 ms |
|---|---:|---:|---:|
| vehicle.physics | 3.798 | 2.488 | 9.597 |
| actor.physics | 1.824 | 1.262 | 4.274 |
| west.world.process | 0.498 | 0.276 | 1.352 |
| vehicle_tires.redraw_marks | 0.497 | 0.404 | 1.422 |
| urban.physics | 0.365 | 0.238 | 0.872 |
| reflection.process | 0.357 | 0.022 | 2.500 |
| gameplay.physics | 0.331 | 0.221 | 0.766 |
| terminal.physics | 0.277 | 0.190 | 0.662 |
| west.audio.nearby_process | 0.153 | 0.115 | 0.325 |
| west.camera.process | 0.150 | 0.140 | 0.221 |
| west.audio.world_process | 0.074 | 0.052 | 0.209 |
| west.street.physics | 0.056 | 0.007 | 0.410 |
| west.traffic_yield.physics | 0.026 | 0.018 | 0.060 |
| west.audio.weather_process | 0.015 | 0.014 | 0.018 |
| west.parking.physics | 0.014 | 0.009 | 0.034 |
| west.region.process | 0.008 | 0.006 | 0.008 |

Contadores cumulativos da sessão: médias ms/quadro `{"diagnostics_callback": 0.19765215311004786, "system_profile_callback": 0.0}`. Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela.

Passos físicos efetivamente bracketados: 2859; p50 7.111 ms/passo e p95 11.506 ms/passo.

Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:

| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |
|---:|---:|---:|---:|---:|---:|
| 0 | 56 | 7.886 | 11.174 | — | — |
| 1 | 1471 | 17.056 | 21.887 | 6.385 | 8.214 |
| 2 | 438 | 29.740 | 38.278 | 7.816 | 9.707 |
| 3 | 67 | 47.394 | 69.334 | 9.114 | 11.601 |
| 4 | 23 | 59.728 | 81.899 | 9.393 | 11.052 |
| 5 | 13 | 81.908 | 106.698 | 11.530 | 13.877 |
| 6 | 8 | 102.880 | 192.800 | 12.130 | 15.767 |
| 7 | 6 | 106.404 | 124.205 | 11.367 | 13.193 |
| 8 | 8 | 134.760 | 156.357 | 12.418 | 14.633 |

| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |
|---|---:|---:|---:|
| vehicle.physics | 2.776 | 2.393 | 3.912 |
| actor.physics | 1.334 | 1.218 | 1.705 |
| vehicle.drive | 0.799 | 0.719 | 1.039 |
| actor.move_and_slide | 0.523 | 0.477 | 0.719 |
| vehicle.street_pre | 0.490 | 0.393 | 0.798 |
| vehicle.effects | 0.463 | 0.400 | 0.748 |
| actor.step | 0.410 | 0.370 | 0.532 |
| vehicle.effects.tires | 0.328 | 0.289 | 0.558 |
| vehicle.move_and_slide | 0.309 | 0.257 | 0.489 |
| urban.physics | 0.267 | 0.234 | 0.357 |
| west.vehicle.junction_gate | 0.251 | 0.228 | 0.350 |
| gameplay.physics | 0.242 | 0.219 | 0.308 |
| vehicle_tires.contacts | 0.239 | 0.209 | 0.411 |
| street.pre.props | 0.233 | 0.186 | 0.395 |
| terminal.physics | 0.202 | 0.185 | 0.267 |
| street.pre.people | 0.180 | 0.145 | 0.277 |
| street.pre.props.query | 0.145 | 0.118 | 0.250 |
| vehicle.lod | 0.118 | 0.108 | 0.140 |
| west.vehicle.escape | 0.101 | 0.090 | 0.144 |
| actor.steering | 0.094 | 0.088 | 0.121 |
| vehicle.street_post | 0.078 | 0.064 | 0.116 |
| west.vehicle.obstacle_ahead | 0.067 | 0.061 | 0.107 |
| west.vehicle.route_projection | 0.058 | 0.049 | 0.086 |
| west.vehicle.can_rotate | 0.054 | 0.042 | 0.094 |
| actor.pose | 0.054 | 0.050 | 0.070 |
| vehicle.effects.powertrain | 0.054 | 0.044 | 0.090 |
| vehicle.resting | 0.047 | 0.042 | 0.057 |
| west.street.physics | 0.041 | 0.007 | 0.353 |
| vehicle.wheels | 0.040 | 0.033 | 0.063 |
| west.street.watch_people | 0.031 | 0.000 | 0.342 |
| vehicle.contacts | 0.030 | 0.024 | 0.045 |
| vehicle.effects.impact | 0.029 | 0.023 | 0.046 |
| street.pre.crush | 0.027 | 0.022 | 0.043 |
| vehicle.wreck_lifetime | 0.021 | 0.019 | 0.026 |
| west.traffic_yield.physics | 0.019 | 0.017 | 0.024 |
| street.post.contacts | 0.018 | 0.014 | 0.026 |
| street.pre.people.cast | 0.011 | 0.000 | 0.049 |
| west.parking.physics | 0.010 | 0.009 | 0.015 |
| street.post.slide | 0.010 | 0.008 | 0.015 |
| street.post.crush | 0.009 | 0.007 | 0.014 |
| vehicle_tires.surface_emit | 0.009 | 0.000 | 0.039 |
| urban.refresh_presence | 0.008 | 0.000 | 0.065 |
| west.traffic_yield.hazards | 0.006 | 0.006 | 0.008 |
| vehicle_tires.skid_audio | 0.005 | 0.005 | 0.009 |
| west.vehicle.rear_clear | 0.004 | 0.000 | 0.026 |
| street.pre.props.hit | 0.003 | 0.000 | 0.000 |
| street.pre.props.cast | 0.000 | 0.000 | 0.000 |
| street.slide.rotate | 0.000 | 0.000 | 0.000 |

Ranking por média por quadro; percentis sempre sobre todos os quadros:

| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |
|---|---|---|---:|---:|---:|---:|
| vehicle.physics | root | None | 3.798 | 2.488 | 9.597 | 2034 |
| actor.physics | root | None | 1.824 | 1.262 | 4.274 | 2034 |
| vehicle.drive | nested | vehicle.physics | 1.093 | 0.752 | 2.698 | 2034 |
| actor.move_and_slide | nested | actor.physics | 0.715 | 0.509 | 1.655 | 2034 |
| vehicle.street_pre | nested | vehicle.physics | 0.671 | 0.420 | 1.842 | 2034 |
| vehicle.effects | nested | vehicle.physics | 0.633 | 0.426 | 1.837 | 2034 |
| actor.step | nested | actor.physics | 0.561 | 0.385 | 1.295 | 2034 |
| west.world.process | root | None | 0.498 | 0.276 | 1.352 | 2090 |
| vehicle_tires.redraw_marks | root | None | 0.497 | 0.404 | 1.422 | 1795 |
| vehicle.effects.tires | nested | vehicle.effects | 0.449 | 0.314 | 1.364 | 2034 |
| vehicle.move_and_slide | nested | vehicle.physics | 0.423 | 0.273 | 1.163 | 2034 |
| urban.physics | root | None | 0.365 | 0.238 | 0.872 | 2034 |
| reflection.process | root | None | 0.357 | 0.022 | 2.500 | 2090 |
| west.vehicle.junction_gate | nested | vehicle.drive | 0.343 | 0.243 | 0.843 | 2034 |
| gameplay.physics | root | None | 0.331 | 0.221 | 0.766 | 2034 |
| vehicle_tires.contacts | nested | vehicle.effects.tires | 0.327 | 0.227 | 0.970 | 1818 |
| street.pre.props | nested | vehicle.street_pre | 0.318 | 0.198 | 0.936 | 2034 |
| terminal.physics | root | None | 0.277 | 0.190 | 0.662 | 2034 |
| reflection.dynamic | nested | reflection.process | 0.252 | 0.000 | 2.069 | 2090 |
| street.pre.people | nested | vehicle.street_pre | 0.246 | 0.154 | 0.633 | 2034 |
| west.world.residency | nested | west.world.process | 0.235 | 0.220 | 0.335 | 2090 |
| street.pre.props.query | nested | street.pre.props | 0.199 | 0.126 | 0.594 | 2034 |
| vehicle.lod | nested | vehicle.physics | 0.161 | 0.109 | 0.372 | 2034 |
| west.audio.nearby_process | root | None | 0.153 | 0.115 | 0.325 | 2090 |
| west.world.population_job | nested | west.world.process | 0.152 | 0.002 | 0.873 | 2090 |
| west.camera.process | root | None | 0.150 | 0.140 | 0.221 | 2090 |
| vehicle_tires.surface_end | nested | vehicle_tires.redraw_marks | 0.148 | 0.130 | 0.374 | 1794 |
| west.vehicle.escape | nested | vehicle.drive | 0.139 | 0.099 | 0.320 | 2034 |
| actor.steering | nested | actor.physics | 0.129 | 0.091 | 0.314 | 2034 |
| vehicle.street_post | nested | vehicle.physics | 0.106 | 0.067 | 0.270 | 2034 |
| west.vehicle.obstacle_ahead | nested | multiple_contexts | 0.091 | 0.068 | 0.224 | 1997 |
| west.vehicle.route_projection | nested | vehicle.drive | 0.080 | 0.051 | 0.207 | 2034 |
| west.vehicle.can_rotate | nested | vehicle.drive | 0.075 | 0.045 | 0.218 | 2034 |
| actor.pose | nested | actor.physics | 0.074 | 0.051 | 0.180 | 2034 |
| west.audio.world_process | root | None | 0.074 | 0.052 | 0.209 | 2090 |
| vehicle.effects.powertrain | nested | vehicle.effects | 0.073 | 0.048 | 0.200 | 2034 |
| vehicle.resting | nested | vehicle.physics | 0.064 | 0.042 | 0.153 | 2034 |
| west.street.physics | root | None | 0.056 | 0.007 | 0.410 | 2034 |
| vehicle.wheels | nested | vehicle.physics | 0.055 | 0.035 | 0.146 | 2034 |
| west.street.watch_people | nested | west.street.physics | 0.043 | 0.000 | 0.391 | 220 |
| stream.harbor.prepare_collision | inclusive_unknown | None | 0.041 | 0.026 | 0.101 | 2034 |
| vehicle.contacts | nested | vehicle.physics | 0.040 | 0.025 | 0.108 | 2034 |
| vehicle.effects.impact | nested | vehicle.effects | 0.040 | 0.024 | 0.110 | 2034 |
| west.audio.nearby_select | nested | west.audio.nearby_process | 0.039 | 0.000 | 0.207 | 416 |
| street.pre.crush | nested | vehicle.street_pre | 0.037 | 0.024 | 0.092 | 2034 |
| reflection.batch | nested | reflection.process | 0.035 | 0.000 | 0.251 | 2090 |
| west.audio.ambience | nested | west.audio.world_process | 0.032 | 0.026 | 0.082 | 2090 |
| vehicle.wreck_lifetime | nested | vehicle.physics | 0.029 | 0.020 | 0.068 | 2034 |
| west.camera.cutaway | nested | west.camera.process | 0.028 | 0.026 | 0.034 | 2090 |
| west.traffic_yield.physics | root | None | 0.026 | 0.018 | 0.060 | 2034 |
| street.post.contacts | nested | vehicle.street_post | 0.024 | 0.015 | 0.064 | 2034 |
| street.pre.people.cast | nested | street.pre.people | 0.015 | 0.000 | 0.069 | 623 |
| west.audio.weather_process | root | None | 0.015 | 0.014 | 0.018 | 2090 |
| west.parking.physics | root | None | 0.014 | 0.009 | 0.034 | 2034 |
| west.camera.terrain_offset | nested | west.camera.process | 0.014 | 0.013 | 0.018 | 2090 |
| street.post.slide | nested | vehicle.street_post | 0.013 | 0.008 | 0.035 | 2034 |
| west.camera.tunnel_chase | nested | west.camera.process | 0.013 | 0.012 | 0.016 | 2090 |
| street.post.crush | nested | vehicle.street_post | 0.013 | 0.008 | 0.033 | 2034 |
| vehicle_tires.surface_emit | nested | vehicle.effects.tires | 0.012 | 0.000 | 0.048 | 422 |
| urban.refresh_presence | nested | urban.physics | 0.011 | 0.000 | 0.112 | 158 |
| stream.harbor.set_focus | inclusive_unknown | None | 0.010 | 0.009 | 0.012 | 2090 |
| west.traffic_yield.hazards | nested | west.traffic_yield.physics | 0.009 | 0.006 | 0.020 | 2034 |
| reflection.registration | nested | reflection.process | 0.008 | 0.001 | 0.030 | 2090 |
| west.traffic.route_near | nested | multiple_contexts | 0.008 | 0.000 | 0.000 | 31 |
| west.region.process | root | None | 0.008 | 0.006 | 0.008 | 2090 |
| vehicle_tires.skid_audio | nested | vehicle.effects.tires | 0.007 | 0.005 | 0.021 | 1818 |
| west.vehicle.rear_clear | nested | multiple_contexts | 0.005 | 0.000 | 0.027 | 318 |
| street.pre.props.hit | nested | street.pre.props | 0.004 | 0.000 | 0.000 | 2 |
| west.audio.radio | nested | west.audio.world_process | 0.004 | 0.004 | 0.005 | 2090 |
| west.world.logical_region | nested | west.world.process | 0.004 | 0.003 | 0.005 | 2090 |
| west.router.plan | nested | multiple_contexts | 0.003 | 0.000 | 0.000 | 2 |
| retire.drain | inclusive_unknown | None | 0.001 | 0.000 | 0.000 | 2 |
| ground_blood.allocate | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 7 |
| west.router.csharp.build_path | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| west.router.csharp.build | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| pickup.configure.torus_bind | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.configure_voice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 17 |
| pickup.bind.mesh | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| gameplay.fire_at | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.nearest_edge | nested | multiple_contexts | 0.000 | 0.000 | 0.000 | 2 |
| retire.hide_and_enqueue | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| west.router.csharp.plan | nested | west.router.plan | 0.000 | 0.000 | 0.000 | 2 |
| pickup.bind.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.play | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 17 |
| pickup.configure.material | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| pickup.configure.torus_create | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| street.pre.props.cast | nested | street.pre.props | 0.000 | 0.000 | 0.000 | 2 |
| vehicle_damage.wear | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 2 |
| contact_audio.stop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 17 |
| pickup.bind.properties | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| retire.detach_cached_records | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 1 |
| pickup.bind.add_child | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 3 |
| contact_audio.pool_attach | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_bus | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_script | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| contact_audio.pool_voices | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.carve_tunnel | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.dressing_step | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.container | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.harbor_bridge | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.original_facade | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.road | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.ship | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_model | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.record.south_port_rail | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| stream.harbor.surfaces | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.crash | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.damage_other | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.damage_self | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.crash.impulse | nested | street.crash | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.attach | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.commit | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.geometry | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.scatter.material | nested | street.scatter | 0.000 | 0.000 | 0.000 | 0 |
| street.slide.rotate | nested | street.post.slide | 0.000 | 0.000 | 0.000 | 0 |
| terminal.build | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.add_child_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.append_free_loop | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.commit_upload | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch.reuse | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.batch_body | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.collision | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.doors | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_construct | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.model_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.coach.ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.gate.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.passenger.mesh_prewarm_slice | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.route.prepare | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.curve_assembly | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_configure | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| terminal.street.router_plan | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |
| urban.actor.create_ready | inclusive_unknown | None | 0.000 | 0.000 | 0.000 | 0 |

Residual physics: p50 2.431 ms; p95 9.180 ms (2090 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

Residual process: p50 3.994 ms; p95 8.382 ms (2090 quadros, 0 rejeitados por cobertura excedente). Complemento sem causa atribuída.

## Arquivos não utilizados

- `D:\geteco\game\evidence\profile-west-cpu-20261013\analysis-preliminary.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\base_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\base_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\base_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\base_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\hardware.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\instrumentation0_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\instrumentation0_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\instrumentation0_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\instrumentation0_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_density_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_density_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_density_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_density_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_roadside_parking_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_roadside_parking_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_roadside_parking_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_roadside_parking_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_yield_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_yield_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_yield_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\no_traffic_yield_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\population0_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\population0_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\population0_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\population0_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\restoration.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\session_profile0_1.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\session_profile0_1.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\session_profile0_2.inputs.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\session_profile0_2.run.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\span-parent-map.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\temporary-spans-manifest.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
- `D:\geteco\game\evidence\profile-west-cpu-20261013\validation.json`: Arquivo não contém samples por quadro; não é rodada deste profiler
