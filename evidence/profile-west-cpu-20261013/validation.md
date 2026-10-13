A revisão independente verificou os 16 JSONs completos e os logs: 50.348 quadros raw e 29.386 medidos. As 16 rodadas têm integridade numérica; 14 não apresentam erro runtime observado. Duas devem sair das comparações causais, embora tenham encerrado com código 0 e `invalid: []`.

A soma dos brackets reconstrói o tempo de quadro com erro máximo 5.68e-14 ms. Timestamps contínuos, passos de física iguais aos contadores do motor, offset process/render 0, quantis e médias recomputados concordantes, nenhum overflow/drop do sink e nenhuma fase inválida. Todas as janelas medidas excedem 30 s; os três inventários ficaram no aquecimento.

| Rodada | Quadros medidos | Segundos | FPS | p95 (ms) | Foco por quadro | Estado runtime |
|---|---:|---:|---:|---:|---:|---|
| base_1 | 1043 | 57.649 | 18.09 | 169.761 | 100.00% | sem erro observado |
| base_2 | 1943 | 47.406 | 40.99 | 47.293 | 100.00% | sem erro observado |
| instrumentation0_1 | 1706 | 47.534 | 35.89 | 53.598 | 100.00% | sem erro observado |
| instrumentation0_2 | 1630 | 47.625 | 34.23 | 58.471 | 100.00% | erro; excluir causal |
| no_density_1 | 1572 | 47.411 | 33.16 | 60.223 | 100.00% | sem erro observado |
| no_density_2 | 1514 | 47.820 | 31.66 | 79.133 | 100.00% | sem erro observado |
| no_roadside_parking_1 | 1168 | 58.454 | 19.98 | 179.730 | 100.00% | sem erro observado |
| no_roadside_parking_2 | 1684 | 47.994 | 35.09 | 56.591 | 100.00% | sem erro observado |
| no_traffic_1 | 3477 | 47.270 | 73.56 | 26.772 | 100.00% | sem erro observado |
| no_traffic_2 | 3150 | 47.258 | 66.66 | 23.577 | 100.00% | sem erro observado |
| no_traffic_yield_1 | 1267 | 54.260 | 23.35 | 146.083 | 98.26% | sem erro observado |
| no_traffic_yield_2 | 787 | 52.372 | 15.03 | 144.897 | 0.00% | sem erro observado |
| population0_1 | 3107 | 47.262 | 65.74 | 24.287 | 100.00% | sem erro observado |
| population0_2 | 2428 | 47.296 | 51.34 | 35.836 | 100.00% | sem erro observado |
| session_profile0_1 | 820 | 52.716 | 15.56 | 146.015 | 0.00% | erro; excluir causal |
| session_profile0_2 | 2090 | 47.752 | 43.77 | 46.279 | 14.11% | sem erro observado |

`session_profile0_1`: TaxiLivery.set_available recebeu Nil em emission_energy_multiplier (linha 65), além de instância já liberada em CoastalPlanarReflections._remove_node (linha 100). `instrumentation0_2`: a segunda falha de reflexos.

Foco limita também rodadas sem erro: `no_traffic_yield_2` ficou integralmente sem foco na medição; `session_profile0_2` teve somente 14,115% dos quadros focados. Esta é a única repetição sem erro do controle SessionSystemProfile desligado, mas não sustenta uma comparação causal limpa com os baselines focados. Não houve 30 s desse controle com foco integral.
`no_traffic_2`, fase `warmup`: 1662/1713 quadros sem foco (97.02%); 96.55% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`no_traffic_yield_1`, fase `measurement`: 22/1267 quadros sem foco (1.74%); 5.54% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`no_traffic_yield_2`, fase `warmup`: 94/805 quadros sem foco (11.68%); 40.14% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`no_traffic_yield_2`, fase `boundary`: 1/1 quadros sem foco (100.00%); 100.00% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`no_traffic_yield_2`, fase `measurement`: 787/787 quadros sem foco (100.00%); 100.00% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`session_profile0_1`, fase `warmup`: 1089/1089 quadros sem foco (100.00%); 100.00% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`session_profile0_1`, fase `boundary`: 1/1 quadros sem foco (100.00%); 100.00% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`session_profile0_1`, fase `measurement`: 820/820 quadros sem foco (100.00%); 100.00% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`session_profile0_2`, fase `warmup`: 1619/1619 quadros sem foco (100.00%); 100.00% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`session_profile0_2`, fase `boundary`: 1/1 quadros sem foco (100.00%); 100.00% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.
`session_profile0_2`, fase `measurement`: 1795/2090 quadros sem foco (85.89%); 85.40% do tempo de parede atribuído às amostras com flag sem foco. Foco é observado na borda do quadro.

As 16 rodadas usaram Godot 4.7.2 .NET, Mobile, RTX 4060 Laptop, i7-13650HX, 3440×1440, VSync desligado, FPS sem limite e física a 60 Hz com máximo de oito passos por quadro. Os logs confirmam prewarm do roteador C# nativo em todas elas.

Nenhum quadro está pausado. Os hashes de 1.058 entradas, incluindo o DLL compilado, coincidem nas 16 rodadas: `31bf304e9ef9838f4994fc9b9bad615c36680c76a2c6f7c1bbaaa8eda6742d1e`. O digest foi recomputado a partir de cada mapa; profiler e benchmark atuais ainda coincidem com o snapshot. A restauração posterior da instrumentação de produção está registrada separadamente em restoration.json.

O custo próprio cronometrado dos probes é um limite inferior do overhead: não cobre integralmente dispatch, timers/dictionaries nas fontes ou writer thread. Não foi subtraído para fabricar FPS sem instrumentação. TIME_PROCESS/TIME_PHYSICS_PROCESS permanecem somente como monitores raw; os resumos usam timestamps de brackets, e CPU/GPU de viewport são amostras assíncronas.

Memória nativa aumentou durante a coleta. Os raw dictionaries/spans ficam retidos até o JSON final; cenário, cache e telemetria também podem contribuir. Sem controle de coleta sem retenção, isso não demonstra vazamento do produto. Custos e observações por rodada, frações de foco, erros, SHA dos artefatos e checks detalhados estão em validation.json.
