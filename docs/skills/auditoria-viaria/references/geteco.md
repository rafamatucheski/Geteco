# Referências do Geteco

Caminhos relativos à raiz do projeto, inspecionados em 29/09/2026. Confirme-os na versão atual. Esta referência não certifica o trânsito.

| Camada | Pontos de entrada |
|---|---|
| Documento e reconstrução | world/editing/WorldEditData.gd, EditableRegion.gd, WorldEditRoads.gd no mesmo diretório |
| Junções ajustadas | world/editing/WorldRoadJoins.gd; docs/edited-traffic.md |
| Grafo e curvas | gameplay/NativeTrafficRoutes.gd |
| Fases e ocupação | gameplay/traffic_junctions/TrafficJunctions.gd |
| Postes e lentes | world/city_look/CityChunkDressing.gd; procurar register_signal |
| Emergência | gameplay/traffic_yield/TrafficYieldController.gd, YieldRoadModel.gd, YieldRules.gd |
| Cena integrada | Main.tscn; descobrir consumidores do grafo/controlador com rg |

## Pontos que exigem cuidado

- tests/audit_edited_traffic.gd inspeciona Harbor, monta vizinhança não dirigida, imprime componentes e pontas próximas e termina sem transformar diagnósticos em reprovação. Não cobre toda a cidade, sentidos ou circulação física.
- tests/test_traffic_signals.gd usa cruz sintética de dois eixos. Não comprova conversões sem conflito, geometrias oblíquas ou posicionamento de todos os postes.
- NativeTrafficRoutes.configure infere mão única por inbound/outbound no ID e filtra vias estreitas; compare isso à intenção do mapa.
- TrafficJunctions.key_of usa XZ; o grafo conserva Y. Associação de sinais também usa proximidade horizontal. Investigue níveis sobrepostos: isso é hipótese de teste, não defeito reproduzido.
- O controlador agrupa movimentos em dois eixos, conserva registros de sinais entre configurações e expira reservas de ocupação. Confronte com geometria e presença física dos veículos.
- Defasagem por posição não prova coordenação por velocidade ou demanda.

## Testes candidatos

Leia os scripts e selecione apenas os pertinentes. Confirme isolamento do save, argumentos e dados ativos.

| Tema | Arquivos |
|---|---|
| Junções e edição | tests/test_edited_road_joins.gd; tests/test_world_editor_roads.gd |
| Passagem física | tests/test_edited_traffic_drive.gd |
| Semáforos | tests/test_traffic_signals.gd |
| Faixas e recuperação | tests/test_four_lane_traffic.gd; tests/test_traffic_unstick.gd |
| Conexões especiais | tests/test_canal_tunnel_traffic.gd; tests/test_mountain_side_road_access.gd; tests/test_truckers_village_roads.gd |
| Emergência | tests/dispatch/test_fire_traffic.gd |
| População | tests/validate_traffic_population_100.gd |
| Frame time renderizado | tests/measure/measure_edited_traffic.gd |

Descubra o executável Godot no ambiente. Testes SceneTree geralmente usam --headless --path <raiz> --script res://tests/<teste>.gd. Leia primeiro os requisitos do script. A medição de ruas editadas exige renderização e --no-save nos argumentos do usuário; leia a classe base e as opções de saída. Não execute uma medição headless para aprovar performance.

## Primeiro pedido sugerido

Use $auditoria-viaria para auditar a cidade atual, priorizando ligações entre regiões e cruzamentos complexos. Cruze grafo, geometria, semáforos e comportamento na cena renderizada. Entregue achados localizados com evidências e cobertura explícita, separando falhas de hipóteses e melhorias urbanísticas. Não altere o mapa nesta auditoria.
