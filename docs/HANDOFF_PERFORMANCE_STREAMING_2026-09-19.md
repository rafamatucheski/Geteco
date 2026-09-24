# Handoff técnico — performance, população e streaming

Atualizado em 19/09/2026. Este documento existe para outra IA continuar o trabalho sem reiniciar a investigação nem apagar alterações concorrentes.

## Objetivo ativo

Fazer o runtime do Geteco escalar para mais pessoas, veículos e regiões com frame time controlado, mantendo o cenário real: `HarborGame`, trânsito, polícia, combate/caos, clima, iluminação, colisões e travessia física entre regiões. A meta provisória é 60 FPS / 16,67 ms no hardware medido, mas ainda **não foi atingida nem garantida** em todos os cenários.

## Regras obrigatórias antes de continuar

- Ler `AGENTS.md`, `docs/interior-physics-and-depth.md`, a skill `performance-do-jogo` e a skill `testes-com-criterio`.
- O worktree tem muitas mudanças simultâneas de outras sessões. Antes de qualquer operação Git, rodar `git status`.
- Nunca usar `git checkout`, `git restore`, `git reset --hard` ou `git clean`. Não sobrescrever arquivos concorrentes.
- Medição headless valida contratos funcionais, não FPS/GPU. Performance só pode ser aprovada em `HarborGame` renderizado, com janela mínima de 30 segundos no cenário afetado.
- Não executar dois benchmarks Godot ao mesmo tempo. Ao receber `session_id`, continuar pelo mesmo processo; não relançar o teste enquanto ele estiver vivo.
- Não chamar um teste de “direção” se o veículo ficou parado. Registrar distância, cobertura de movimento e maior parada.
- Não prometer 60 FPS universal. Informar hardware, renderer, resolução, cenário, p50/p95/p99, máximo e frames acima de 33,3/66,7 ms.

## Mudança arquitetural implementada nesta etapa

### Índice espacial de conflitos de tráfego

Novo arquivo: `cars/traffic/TrafficConflictIndex.gd`.

Problema anterior: para manter uma fila/reserva de cruzamento ativa, o código dependia de uma aproximação circular fixa de 96 px e fazia buscas amplas repetidas. Isso falhava com veículos longos, podia acordar atores laterais e não seguia corretamente uma cadeia de corpos removidos do broadphase pela suspensão de proximidade.

Solução atual:

- constrói um snapshot espacial uma vez por decisão de atividade;
- indexa candidatos por células de 256 px;
- para corpos adormecidos, consulta sob demanda somente as formas autoradas nas células atravessadas pelo sensor, em vez de reconstruir as formas das cinco cidades;
- intersecta o segmento de cada `RayCast2D` com essas formas;
- respeita máscara de colisão, formas desabilitadas e obstáculos vivos que truncam o raio;
- percorre transitivamente a cadeia com conjunto de visitados;
- consultas de sirene usam apenas células próximas;
- carros comuns ativos acordam somente seus três líderes lógicos imediatos na mesma `Path2D`; pistas paralelas e o restante da fila continuam dormentes;
- somente pistas com raiz ativa local são ordenadas, evitando ordenar tráfego distante a cada ciclo;
- o snapshot não persiste referências entre unloads/regiões.

Integração: `cars/traffic/TrafficSimulationBudget.gd` usa esse índice para reservas, filas e veículos de emergência. `systems/PopulationActivity.gd` expõe `conflict_usec` e estatísticas do índice em `stats`.

### Evidência funcional e de escala

`tests/test_reserved_traffic_budget.gd` foi ampliado e passou com:

- caminhão de 130 px cujo centro fica além do antigo raio de 96 px;
- cadeia transitiva caminhão → pedestre;
- ator lateral que deve continuar dormindo;
- corpo fora da máscara;
- parede viva interrompendo o corredor;
- forma desabilitada;
- mais 500 sleepers distantes.

Resultado observado:

```text
CONFLICT_INDEX_SCALING
small={indexed_actors:20,indexed_shapes:9,nearby_candidates:0,shape_tests:9}
large={indexed_actors:520,indexed_shapes:9,nearby_candidates:0,shape_tests:9}
```

Os 500 residentes distantes aumentaram somente a construção linear do snapshot uma vez, sem aumentar a ordenação de pistas nem os testes geométricos locais. `tests/test_local_dormant_leader_budget.gd` manteve conjunto ativo de quatro atores (raiz + três líderes), pista paralela dormente e caiu de 4,781 ms na primeira implementação para 1,623 ms depois de retirar ordenação global e indexação antecipada de formas. Também passaram `tests/test_reserved_traffic_budget.gd` e `tests/test_traffic_emergency_response.gd`; neste último, a primeira montagem de `UnionSedanModel` ainda custou 40,23 ms e está em frente isolada.

### Índice espacial persistente da população virtual

`systems/PopulationZoneManager.gd` deixou de percorrer todas as identidades virtuais a cada consulta de materialização. Registros comuns e registros fixados usam índices por célula mantidos quando são registrados, removidos ou movidos; a consulta visita somente as células próximas ao jogador. `streaming.population_zones.last_query` expõe quantas células e registros foram realmente examinados.

No contrato `tests/test_population_zones.gd`, com somente oito registros próximos e 200 consultas comparáveis:

```text
500 registros:  377,79 µs → 24,84 µs
1000 registros: 771,20 µs → 25,32 µs
5000 registros: 3874,43 µs → 33,35 µs
```

Assim, o custo de consulta ficou ligado à vizinhança, não às cinco cidades inteiras. A geração eventual do snapshot de telemetria ainda é O(n): com 5000 registros mediu 3,359 ms e deve continuar fora do caminho normal de cada frame.

### Cache completo das motocicletas

`cars/motorcycles/MotorcycleModel.gd` agora reutiliza uma árvore 3D completa preparada por `cars/VehicleGeometryCache.gd`, incluindo carroceria, piloto e descanso, mantendo materiais por instância e montagem posterior das rodas. O contrato `tests/test_motorcycle_geometry_cache.gd` passou e a frota foi inspecionada renderizada sem fallback 2D nem materiais pretos.

Três construções quentes caíram de 9,755 ms para 8,160 ms (16,4%) e a contagem observada de meshes após prewarm caiu de 181–230 para 46–49. A primeira construção completa continua custando cerca de 47–50 ms, portanto precisa ocorrer no prewarm e nunca quando a moto entra na câmera. A telemetria O(1) agora separa hit, miss, captura, restauração e construção fria.

Durante essa medição apareceu outro pico independente: a primeira construção de `AmericanFlatbedModel.gd` havia custado aproximadamente 54,57 ms. O modelo agora compartilha primitivas imutáveis: preserva 151 peças visuais com somente 37 recursos de mesh distintos. O teste dedicado mediu cerca de 10–21 ms frio e ~2 ms quente; a marca antiga de 54,57 ms não reapareceu isoladamente, mas o primeiro uso ainda deve ficar no prewarm e a confirmação integrada continua pendente.

### Sedã, pipeline comum e áudio veicular

`UnionSedanModel.gd` passou a compartilhar apenas `BoxMesh`/`CylinderMesh` imutáveis, preservando nós, transforms, materiais e pintura por instância. A construção fria isolada caiu de 17,84 para 7,62 ms, meshes únicos de 96 para 33 e a apresentação quente ficou em 4,59 ms. Mesmo assim, o `PB_BUILD` integrado caiu somente de 40,23 para 38,72 ms: o modelo local melhorou, mas o primeiro aparecimento ainda reprova 60 FPS.

O profiler renderizado `tests/test_vehicle_presentation_stage_profile.gd` decompôs o custo comum: `VehicleWheelRig.mount`/clearance chegou a 36,5 ms, batching a 26 ms e a primeira geração de ContactShadow a 12–14 ms; câmera, ambiente, luz direcional, textura e offset ficaram individualmente abaixo de 0,7 ms. Com caches quentes, o pipeline completo ficou em 4,7–6,1 ms. Portanto, luzes não são o gargalo dominante da apresentação veicular; o próximo passo é guardar no loading o template já preparado com clearance e batching.

`VehicleEngineSound.gd` agora entrega fallback audível imediato e prepara os streams finais imutáveis por família em worker. O primeiro bind caiu de ~109,0 para 3,152 ms, segundo veículo durante preparo para 0,039 ms, bind quente para 0,030 ms e primeira família de caminhão para 2,678 ms. Vozes/pitch/volume/playback permanecem por veículo; somente streams são compartilhados. `tests/test_vehicle_audio_first_bind_budget.gd` passou, mas a confirmação no trace da rota real ainda falta.

### Percurso real sem teleporte

Novo fixture: `tests/measure_real_gameplay_route.gd`. Ele inicia `HarborGame`, caminha até o carro por input, entra pela interação normal e percorre 13.835,4 px por input até atravessar fisicamente a costura Harbor–Mountain. O contrato headless mais recente passou com 35 waypoints, sem escrita direta de posição ou velocidade, mas isso prova somente carga/rota — não FPS.

O fixture reprova passos físicos impossíveis, deslocamento insuficiente, menos de 60% do tempo dirigindo, parada de 8 s, ausência de tráfego/polícia ou falta de troca regional. Com `--chaos`, mantém perseguição de nível 4 pela API de produção. CSV, JSON e traces de stalls acima de 100 ms incluem deltas de objetos/nós/recursos, grupos vivos, estado do streaming, `PresentationBudget` e cache de geometria. O custo de gerar um trace é retirado do relógio seguinte para não criar stalls artificiais em cascata.

O primeiro carregamento do percurso expôs um erro de script preexistente: `LumberjackShelterInterior.gd` redeclarava `_render_clock`, já herdado de `MountainCabinInterior.gd`. A declaração duplicada foi removida e o contrato voltou a carregar. Ainda falta executar o percurso renderizado depois que as frentes paralelas terminarem e não houver outro Godot ativo.

Primeira tentativa renderizada em Vulkan Mobile/RTX 4060, 1280×720, noite, chuva e `--chaos`: **reprovada antes do carro**. O jogador nasceu normalmente em `(1700,1130)`, percorreu 539 px por input, mas a rota inicial tentou seguir o lado obstruído da Union Avenue e ficou parada em torno de `(1385,1353)`. Entrada no carro, polícia e costura não aconteceram; portanto os 90,43 FPS, p95 15,02 ms e p99 17,61 ms desse trecho **não certificam** o cenário pedido. A rota foi ajustada para cruzar no entroncamento da Market Street e seguir o lado oeste, ainda exclusivamente por input; precisa ser repetida.

Mesmo reprovada, a tentativa capturou um stall útil de 149,20 ms no primeiro frame a pé. Houve +476 nós e +752 objetos; o trace mostra criação em lote de `Puddle.gd`, polígonos e `CPUParticles2D` da chuva, junto de materialização de trânsito/pedestres. O cache registrava 37 construções frias de veículo, 378,405 ms acumulados e máximo de 62,784 ms. Há frentes isoladas para cadenciar chuva e completar o prewarm; não atribuir o stall a luzes com essa evidência.

A chuva foi então dividida em duas fases orçamentadas: planejamento físico em fatias e materialização máxima de duas poças por frame. Geometria/shape imutáveis são compartilhados e 96 emissores individuais viraram um pool de oito. `tests/test_rain_puddle_creation_cadence.gd` passou: 96 poças em 49 frames (0,82 s), pico de planejamento 1,247 ms e pico de construção 1,310 ms no processo observado, preservando a curva visual final de 45 s e respingo.

O prewarm de veículos agora descobre catálogo, motocicletas e modelos presentes no mundo, guarda a forma já batched e expõe contadores pós-prewarm. `tests/test_harbor_vehicle_prewarm_coverage.gd` passou com 32 modelos compatíveis restaurados, zero misses/cold builds depois do aquecimento e cobertura explícita de Nimbus/Metro. O aquecimento headless custou ~4,05 s e deixou 13 modelos especiais incompatíveis fora do cache; isso desloca trabalho para a carga e ainda precisa de política de loading/cache persistente.

### Percurso renderizado com caminhada, carro e caos

A terceira tentativa conseguiu caminhar 2.115 px, entrar normalmente no carro, dirigir 7.512 px e manter até cinco viaturas / wanted 4, sem teleporte de setup. A janela ficou 100% em foco. O cenário reprovou porque o carro ficou preso na faixa errada da Foundry Avenue e depois foi destruído/resetado para `(565,1990)`, detectado como passo impossível de 3.095 px. A rota foi corrigida de `y=430` (contramão) para a faixa leste autorada em `y=370`; precisa ser repetida.

Resultado global da tentativa reprovada:

```text
61,51 FPS médio; p50 14,87 ms; p95 25,13 ms; p99 43,47 ms
22 stalls >100 ms; máximo 1.992,57 ms
3931 frames >16,67 ms; 272 >33,3 ms; 36 >66,7 ms
```

Por fase:

```text
caminhada: 94,59 FPS; p95 14,66; p99 17,96; máximo 123,40 ms
boarding:   89,07 FPS; p95 14,98; p99 19,23; máximo 20,30 ms
direção:    56,71 FPS; p95 26,59; p99 48,19; máximo 1.992,57 ms
```

O maior gargalo comprovado é a preparação da serra inteira. Durante a direção, antes de chegar à costura, o runtime subiu de ~32 mil para ~53 mil nós e de ~2,36 para ~3,10 GiB de memória de vídeo. Stalls principais:

```text
1.992,57 ms — SecretMountainLake/SmugglerCargoPlane/CargoSMG/Treasure
1.791,61 ms — MountainSettlement/WinterRoadsideDressing (pines/logs/branches)
1.070,06 ms — MountainTransitVillage/WinterNaturalDressing3D
  785,20 ms — MountainPassRoad/CliffGuardRails/CliffEdges/Tunnel
```

Isso demonstra que esconder/desabilitar a região depois da construção não é streaming suficiente: interiores, SubViewports, vegetação, tesouro e colisores ainda são materializados em grandes lotes. Três frentes disjuntas estão atacando esses blocos. `ContinuousWorld` agora registra `mountain_load_trigger` para descobrir por que a preparação começou quando o carro ainda estava em `(3249,449)`; suspeita atual é `RegionTravel.pending_world`, ainda não comprovada.

### Primeira redução isolada do avião

`CrashedCargoPlane3D.gd` passou a compartilhar uma caixa e um cilindro unitários e agrupar a geometria estática em 24 `MultiMeshInstance3D`, separados por material e domínio de cutaway. Arma, baú, ouro, tampa e colisões continuam independentes. No teste renderizado curto, o pico caiu de 84,85 para 62,18 ms, o primeiro quadro apresentado de 84,85 para 48,64 ms e os 131 `MeshInstance3D` do avião foram substituídos pelos lotes. É uma melhora de 26,7% no pico isolado, ainda acima do orçamento de 16,67 ms e ainda não confirmada no HarborGame completo.

A revisão de integração confirmou que cinco caixas precisam manter no modelo batched a posição final que `MountainCargoPlane._open_cargo_aisle()` aplicava depois da construção. Sem isso, o `MultiMesh` imutável voltaria a fechar visualmente o corredor embora a colisão estivesse livre.

O wrapper `MountainCargoPlane.gd` agora cria imediatamente o esqueleto funcional — colisões, pickup, identidade da arma, baú, tampa e ouro — e divide a geometria de apresentação em 21 trabalhos, no máximo dois por quadro e alvo de 2 ms. A inclusão síncrona caiu de 10,124 para 3,273 ms; a maior etapa indivisível foi a SMG em 4,201 ms e a apresentação terminou em 11 quadros. `tests/test_mountain_cargo_plane_staging_cadence.gd`, `tests/test_plane_loot_presentation.gd` e o teste estrutural do avião passaram. Isso ainda precisa ser confirmado na rota renderizada real, porque vários produtores cadenciados podem somar custo no mesmo quadro sem um escalonador global.

### Compactação da vegetação de inverno

`transit/MountainWinterDressing3D.gd` mantém um proxy invisível conservador por feature para o hull projetado e move apenas a apresentação aceita pelos filtros de rota para `MultiMesh`, agrupada por forma/material e por viewport. No teste integrado curto foram preservadas 1.075 primitivas visuais com 227 nós, 54 lotes, 31 features físicas, 209 vértices de polígonos, 19 sólidos e 12 detalhes atravessáveis. A assinatura direta pine/rock/log/branches preservou exatamente 138 primitivas. `tests/test_winter_dressing_multimesh_compaction.gd` e `tests/test_mountain_geodata.gd` passaram; a instalação headless ainda custou ~154 ms e precisa da medição renderizada na aproximação natural. A redução de ~88% em nós contra o stall histórico é indicativa, não uma comparação de FPS equivalente.

O caminho streamed agora também distribui construção de features e filtragem/hulls por frames e mantém os seis SubViewports em `UPDATE_DISABLED` até entrarem na tela. No contrato de cadência, a instalação levou cerca de 30 frames; picos atribuíveis ficaram em ~0,47 ms por feature do modelo, ~1,63 ms para alocar lotes, ~1,90 ms por filtro/hull e ~0,36 ms para montar a view. O intervalo bruto do headless não é usado como prova de FPS, pois inclui trabalho do motor sem atribuição; a próxima rota renderizada decide o frametime real.

`MountainPine3D.gd` compartilha meshes/materiais e agrupa galhos, neve e troncos em `MultiMesh`. Em 256 pinheiros, nós internos caíram 1.159→356, meshes únicos 1.095→33 e materiais 46→8; construção fria renderizada caiu 92,7→61,0 ms e primeira apresentação 415,9→251,2 ms. Silhuetas, oito tipos, neve, footprints, gelo e interação foram preservados. Ainda reprova se o lote nascer inteiro, por isso há uma frente separada fatiando `build_dense_pine_forest`.

### Correção de compilação concorrente

Uma alteração concorrente em `Player.gd` passou a chamar `ProceduralAudio.get_gunshot_stream(weapon_id, suppressed)`, mas a API ainda aceitava apenas um argumento e impedia o HarborGame de compilar. `ProceduralAudio.gd` agora aceita o parâmetro opcional; o volume e alcance reduzidos continuam aplicados pelo jogador. Depois disso, `tests/test_plane_loot_presentation.gd` voltou a passar.

### Regressão bloqueante descoberta no penhasco

O worktree atual removeu a `Area2D`, os polígonos de queda e os métodos `_fall/_can_fall` de `MountainCliffEdges.gd`, além de apagar `MountainCliffFall.gd`. Isso reduz nós às custas de colisão e gameplay e não pode ser aceito como otimização. Como os arquivos pertencem a uma alteração concorrente, eles não foram sobrescritos automaticamente; a entrega permanece bloqueada nessa área até a queda ser preservada com custo limitado e `tests/test_mountain_cliff_edges.gd` voltar a passar.

## Medições renderizadas atuais

Ambiente medido:

- Godot 4.7.2 stable;
- Vulkan Mobile;
- NVIDIA GeForce RTX 4060 Laptop GPU;
- 1280×720;
- limite normal de 60 FPS, VSync desabilitado pelo projeto;
- `HarborGame` real.

### Downtown parado, noite/chuva/polícia/caos

O fixture histórico chamado `driving` em `tests/measure_city_scenarios.gd` deixa o jogador parado no centro. Ele agora declara explicitamente `sample_kind=stationary_downtown_*`. Não usar esses dados como evidência de streaming em movimento.

Baseline anterior ao novo índice, caos por 30 s:

```text
55,91 FPS; p95 25,324 ms; p99 30,899 ms; máximo 41,328 ms
5 viaturas; 145 residentes materializados / 227 registrados
```

Primeira execução após o índice:

```text
45,33 FPS; p95 32,720 ms; p99 82,742 ms; máximo 1382,024 ms
```

Essa execução teve um stall de 1,38 s e não pode ser aprovada. Uma confirmação equivalente foi feita para testar se o novo índice era a causa:

```text
56,80 FPS; p50 16,818 ms; p95 24,787 ms; p99 29,051 ms
máximo 40,015 ms; 3 frames >33,3 ms; 0 >66,7 ms
5 viaturas; 106 projéteis; 3 vítimas; 1 carro incendiado
```

O custo medido diretamente da nova busca em 328 execuções foi:

```text
p50 0,673 ms; p95 0,974 ms; p99 1,084 ms; máximo 1,154 ms
```

Conclusão correta: o pico de 1,38 s não se repetiu e não foi atribuído ao índice. Isso não prova que desapareceu; a causa do stall raro continua pendente. O cenário de caos confirmado ainda fica abaixo de 60 FPS (56,8), logo a meta absoluta continua reprovada.

Evidências locais:

- `C:/Users/rafae/.codex/visualizations/2026/09/18/01a0b4da-c042-7b52-a226-6a3f3b1d401d/spatial-chain-before`
- `C:/Users/rafae/.codex/visualizations/2026/09/18/01a0b4da-c042-7b52-a226-6a3f3b1d401d/spatial-chain-after`
- `C:/Users/rafae/.codex/visualizations/2026/09/18/01a0b4da-c042-7b52-a226-6a3f3b1d401d/spatial-chain-confirm`

### Direção com input real, noite/chuva/polícia

Novo fixture: `tests/measure_city_input_driving.gd`. Ele dirige o carro pela ação normal do jogo (`move_up`, `move_left`, `move_right`, `move_down`) e não altera posição, rotação, velocidade, colisões, vida ou ativação durante a janela medida.

Primeira execução:

```text
58,12 FPS; p95 21,692 ms; p99 27,063 ms; máximo 64,225 ms
5 viaturas; 3367 px percorridos; deslocamento 3367 px
79,97% do tempo com movimento; maior parada 5789,64 ms
```

O próprio teste marcou `valid_motion=false`, pois houve parada contínua maior que 5 s. Portanto, os números são diagnóstico, não certificação de direção contínua. Investigar se a parada veio de colisão/tráfego, dano/quebra do carro ou controle chegando ao fim da avenida. Não repetir o mesmo teste sem adicionar diagnóstico que responda isso.

Evidência: `C:/Users/rafae/.codex/visualizations/2026/09/18/01a0b4da-c042-7b52-a226-6a3f3b1d401d/input-driving`.

### Travessia física cidade ↔ serra

`tests/test_continuous_world.gd` passou renderizado:

- uma instância de mundo, jogador e carro sobreviveu à travessia;
- ida e volta ocorreram por física, sem troca de cena;
- maior deslocamento entre frames físicos: 4,183 px;
- sem barreira invisível ou dano na costura;
- suspensão/retomada do tráfego de Harbor funcionou;
- atmosfera, save e região foram atualizados;
- população continuou orçamentada durante a suspensão de Harbor.

Foi descoberta uma falha no próprio screenshot do teste: a imagem `bridge.png` mostrou água em vez da costura, porque a câmera criada em runtime ainda não havia sincronizado seu centro antes da captura. O fixture foi corrigido para adicionar a câmera depois de definir sua posição, resetar interpolação, aguardar física, forçar atualização de scroll e verificar o centro. Essa correção ainda precisa de uma execução renderizada final; ela não indica falha comprovada na ponte.

## Melhorias no contrato de benchmark

`tests/measure_game_frame_stability.gd` agora:

- usa `user://tests/frame-stability` como saída padrão, sem depender de pasta externa;
- falha cedo se não puder criar saída/abrir CSV/JSON;
- registra distância percorrida, deslocamento, maior passo, fração em movimento e maior parada;
- exige, para `sample_kind=driving`, pelo menos 300 px, 70% da janela em movimento e nenhuma parada de 5 s ou mais;
- propaga `_sample_failed` para subclasses não continuarem após falha.

`tests/measure_city_scenarios.gd` identifica corretamente as amostras paradas. `tests/measure_city_resolution_matrix.gd` interrompe etapas posteriores se a base falhar.

O relatório agora também inclui `subject_end`, estado de colisão do veículo dirigido e telemetria de foco da janela. Uma medição renderizada com menos de 90% da janela em foco é marcada como ambiente inválido, porque o driver pode reduzir clocks e alterar completamente o frame pacing.

## Correções posteriores ao primeiro diagnóstico

### Carro físico invisível/preto após streaming

A parada da direção real foi localizada: o jogador colidiu com `HarborTraffic_21`, na faixa `foundry_avenue/reverse_01`, no contato `(4104.096, 415.92)`. A captura mostrou que o collider existia, mas sua carroceria 3D não: apareciam somente sombra/fragmentos escuros.

Causa comprovada: `PresentationBudget` remove atores adormecidos da fila. Ao acordar, pedestres tinham `queue_presentation()`, mas `TrafficVehicle` não. Assim, um carro que dormisse antes da construção podia voltar com colisão ativa e permanecer visualmente ausente para sempre.

`TrafficVehicle.queue_presentation()` agora reinsere esse ator no orçamento ao acordar. `tests/test_vehicle_3d_presentation_contract.gd` reproduz dormir → sair da fila → acordar → voltar à fila → construir, e passou. A captura real posterior mostra o mesmo bloqueador com carroceria verde 3D visível:

`C:/Users/rafae/.codex/visualizations/2026/09/18/01a0b4da-c042-7b52-a226-6a3f3b1d401d/input-driving-visual-fix/gameplay.png`

Isso corrige o caminho de wake testado; não é prova de que toda possível origem de material preto foi eliminada.

### Rota do benchmark e limite lateral do tráfego

A telemetria completa corrigiu a hipótese inicial: `HarborTraffic_21` estava em `reverse_01`, centro `y=430`, rotação `π`, offset local zero, sirene inativa e desvio inativo. O fixture dirigia para leste em `y=425`, portanto estava na contramão e colidia corretamente com o fluxo oeste. A rota de direção real agora usa a faixa leste autorada em `y=370`.

Durante essa investigação também foi reforçado um risco real: desvio comum e manobra de sirene agora calculam o lado externo por `traffic_lane_offset × traffic_direction`, em vez de assumir que positivo ou negativo sempre significa acostamento. O casco inteiro precisa permanecer antes da linha central. Isso cobre também pistas de mão única com lanes nos dois lados do eixo.

O contrato funcional dedicado `tests/test_traffic_lane_avoidance_boundary.gd` cobre a faixa reversa e o casco real; `tests/test_traffic_emergency_response.gd` cobre a sirene. `tests/test_vehicle_obstacle_recovery.gd` passou as verificações de táxi, mas sua execução completa continua vermelha em uma asserção anterior e independente: a ambulância do fixture não avança. Ainda é necessária uma nova direção real válida na faixa corrigida.

### Ambiente de benchmark atualmente inválido

As execuções renderizadas recentes ficaram em 8–13 FPS. Uma delas tinha foco zero; outra teve foco 100%, mas a RTX 4060 continuou em P4 a 315 MHz e cerca de 12,6 W. Logo falta de foco não é a causa completa. O frame mostrou `process_ms` médio perto de 94 ms contra 31 ms na execução anterior de 58,12 FPS, além de física 14 ms contra 5,6 ms. Não aprovar performance nem atribuir automaticamente ao driver: é preciso verificar clocks/energia do CPU e fazer ablação comparável da carga atual.

### Resultado da investigação de CPU e espiral de física

O perfil de viewports na rota real mediu a raiz em aproximadamente 2–8 ms de CPU e 2–13 ms de GPU, muito abaixo dos quadros de 70–170 ms. Luzes/render não explicavam a queda. A correlação do CSV revelou a causa amplificadora:

```text
1 passo de física: 334 frames, média 19,23 ms
2 passos:          159 frames, média 28,11 ms
6 passos:           26 frames, média 99,20 ms
8 passos:           77 frames, média 155,33 ms
```

O hitch inicial deixava dívida de física; até oito passos eram executados no quadro seguinte, que ficava ainda mais atrasado. `physics/common/max_physics_steps_per_frame=2` agora limita essa espiral, mantendo física a 60 Hz e interpolação ativa. Consequência explícita: se o render cair sustentadamente abaixo de 30 FPS, a simulação pode desacelerar. É uma contenção para frametime, não substitui reduzir o custo base.

Contrato: `tests/test_physics_catchup_budget.gd` passou.

### Sistema paralelo de passageiros corrigido

O perfil agregado por script mostrou os 24 `UrbanPassenger` como maior categoria de callbacks (1,30 ms/frame), mais `UrbanStationActorPresentation` (0,25 ms/frame). Eles pertenciam ao catálogo global de pedestres, mas a apresentação 3D externa da estação usava a mesma metadata de interiores. `PopulationActivity` tratava todos como fixados e nunca os suspendia por zona.

Agora somente a apresentação externa de estação declara `allows_population_sleep()`. Ao dormir, ator, colisão e adaptador 3D são suspensos; ao acordar, o mesmo rig/estado retorna. Interiores reais continuam fixados. Passaram `tests/test_external_presentation_population_sleep.gd` e `tests/test_population_proximity.gd`.

Na cena real, pedestres ativos no aquecimento caíram de 60 para 38–39. Antes do limite de catch-up, isso melhorou o aquecimento de 13,6 para 21,1 FPS e p50 de 69,3 para 42,6 ms, confirmando custo real — ainda insuficiente isoladamente.

### Confirmação renderizada após limite de catch-up

Evidência: `C:/Users/rafae/.codex/visualizations/2026/09/18/01a0b4da-c042-7b52-a226-6a3f3b1d401d/input-driving-catchup2-smart-driver`.

O motorista do fixture usa somente input normal, mas agora consulta um corredor físico e segue ônibus/motos sem remover colisões. Resultado de 30 s, noite/chuva/5 viaturas:

```text
54,36 FPS; p50 16,781 ms; p95 24,921 ms; p99 39,260 ms
máximo 1115,475 ms; 24 frames >33,3 ms; 2 >66,7 ms
1498 frames com 1 passo; 112 com 2; nenhum com 3–8 passos
1842 px percorridos; sem colisão; carro vivo (76 HP)
veículo à frente detectado em 1162 frames; folga mínima 56,87 px
```

A amostra ficou em `moving_fraction=68,73%` contra o corte antigo de 70%, porque o ônibus chegou a menos de 20 px/s; a maior parada contínua foi apenas 3,53 s. O critério foi corrigido para considerar crawl real acima de 5 px/s, ainda exigindo 300 px e nenhuma parada de 5 s. A execução não foi repetida depois dessa correção e permanece formalmente reprovada no arquivo original.

O limite resolveu a espiral, mas **60 FPS ainda não foi atingido** e reapareceu um stall raro de 1,115 s. No stall, `process_ms` reportou 1105,9 ms no quadro seguinte, objetos subiram 86165→86202, nodes 31041→31070 e a fila de apresentação 25→24; não houve `PB_BUILD` acima de 5 ms. Instrumentar eventos/materializações ao redor de frames >100 ms é a prioridade seguinte.

## Problemas e riscos ainda abertos

1. O caos real confirmado mede 56,8 FPS, não 60. É preciso localizar o custo restante antes de ampliar a população.
2. Há stalls raros grandes (1,38 s em uma execução). A correlação histórica sugere criação/materialização de objetos, mas a execução desta etapa não provou a causa específica.
3. O índice de conflito custa cerca de 0,7–1,1 ms por atualização e ainda percorre todos os atores uma vez ao construir o snapshot. Escala melhor que `reservas × atores`, mas para milhares de atores o próximo passo arquitetural é um índice espacial persistente por região, atualizado em eventos de materialização/movimento/célula — não reconstruído globalmente.
4. `PopulationZoneManager.gd` já virtualiza identidades distantes e limita materialização por tick, mas o snapshot observado ainda tinha 145 de 227 registros materializados no downtown. Isso é alto para cinco cidades; medir e separar moradores que precisam de Node, atores apenas visuais e identidades totalmente virtuais.
5. `PresentationBudget.gd` limita construções a uma por frame, mas cada rig é indivisível. Um rig de 5–10 ms ainda causa hitch e a fila pode ficar permanentemente atrasada. O orçamento precisa de cache/pool pré-aquecido e de uma política de latência visível, não apenas limite de contagem.
6. Vazamentos no encerramento dos testes continuam aparecendo (RIDs, ObjectDB e dependências). Alguns são preexistentes, mas precisam de investigação dirigida; não tratar como aprovado.
7. O frame time de 16,67 ms “independente da situação” exige definir um caos máximo suportado. Sem limite de explosões, projéteis, polícia, corpos e materializações por frame, nenhuma arquitetura consegue garantir custo finito.
8. A revisão de luzes ainda não foi concluída com ablação comparável na cena real. Dados antigos que usavam input incorreto ou cena de preview não provam que iluminação é barata.

## Próxima sequência recomendada

1. Instrumentar frames acima de 100 ms com contagem/delta por grupo e eventos de polícia, materialização de zona, `PresentationBudget`, projéteis, cadáveres e efeitos. O stall de 1,115 s é agora o maior risco de frametime.
2. Fazer uma confirmação finita da direção com o corte de crawl de 5 px/s. Não repetir se o stall reaparecer sem diagnóstico adicional.
3. Reexecutar uma vez `tests/test_continuous_world.gd` renderizado após a correção da câmera, validar todas as asserções e inspecionar `bridge.png`.
4. Medir combate parado com fogo, corpos e sangue sob o mesmo limite de catch-up. Direção e combate são cargas diferentes.
4. Se criação/materialização for confirmada, mover o custo para caches e pools por arquétipo: veículos, motos, pedestres e emergência; preparar meshes/materiais fora da janela visível e reutilizar instâncias. Manter limite temporal por frame e medir latência até apresentação.
5. Evoluir o índice espacial para propriedade das regiões: registro/desregistro ao materializar/desmaterializar, migração apenas ao trocar de célula e consulta local por AABB. Medir custo de manutenção e memória com 500, 1000 e 5000 identidades virtuais, mantendo apenas a vizinhança como Nodes.
6. Só depois aumentar densidade e repetir três cenários distintos: direção urbana com perseguição; combate parado com fogo/corpos/sangue; travessia cidade-serra com primeira visita e retorno. Cada um por pelo menos 30 s.
7. Fazer ablação dirigida de iluminação/efeitos somente se CPU/GPU do cenário atual apontar para render. Preservar aparência; ablação é diagnóstico, não produto final.

## Comandos de referência

Executável usado:

```text
D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe
```

Contrato funcional do índice:

```text
godot --headless --path D:/geteco/game --script res://tests/test_reserved_traffic_budget.gd
```

Direção real renderizada:

```text
godot --path D:/geteco/game --audio-driver Dummy --script res://tests/measure_city_input_driving.gd -- out_dir=<pasta-exclusiva> --normal-cap --night --rain --police --capture
```

Travessia renderizada:

```text
godot --path D:/geteco/game --audio-driver Dummy --script res://tests/test_continuous_world.gd -- out_dir=<pasta-exclusiva>
```

## Estado da entrega

O trabalho está em andamento. O novo índice espacial resolveu uma falha funcional e removeu a multiplicação de consultas locais por residentes distantes no caso testado. A travessia física funciona. A validação agora distingue corretamente cenário parado de direção real. Ainda não existe evidência suficiente para afirmar 60 FPS mínimo em qualquer situação, e o próximo gargalo provável precisa ser demonstrado no fixture de direção/caos antes da próxima mudança de runtime.

## Atualização: áudio, apresentação preparada e views da serra

`VehicleEngineSound.gd` passou a entregar loops curtos por família imediatamente e preparar as camadas finais fora da thread do frame. Na repetição local, o primeiro bind da família street custou 4,131 ms, a família truck fria 3,292 ms e os binds quentes 0,051 ms; o preparo pesado terminou em cerca de 103 ms sem bloquear o primeiro bind. O teste amplo de seis famílias inicialmente acusou seis falhas, mas a causa era o fixture: ele esperava que o desembarque animado de 1,85--2,45 s terminasse em seis frames e deixava `PlayerCar` substituir a velocidade artificial sem input. O fixture agora injeta a faixa de velocidade diretamente no controlador e testa o mesmo contrato de limpeza usado por `_complete_exit_vehicle`; `VEHICLE_ENGINE_LAYERS_RUNTIME failures=0`. Isso não substitui a rota real, mas elimina a falsa regressão de áudio.

`VehicleGeometryCache` agora pode guardar o template já recortado, com rodas montadas e geometria estática batched. O caminho vivo restaura a apresentação pronta, remonta apenas o estado articulado das rodas e não repete o batching. No teste renderizado isolado, Vertice/Nordic/Vale ficaram respectivamente em 1,84/3,89/8,91 ms após prewarm, e o primeiro frame apresentado em 11,76/2,23/2,31 ms. O teste estrutural repetido confirmou zero miss e zero cold build para os 32 modelos suportados depois do prewarm.

Há um custo novo que precisa ser tratado como dívida, não escondido: o prewarm dos modelos de Harbor levou 10.395 ms em headless, e o Vale sozinho ainda consome aproximadamente 2,56--2,77 s para construir o template frio. A tela de loading evita que isso aconteça durante direção, mas um construtor indivisível desse tamanho congela a própria animação de loading e não escala para várias cidades. A frente seguinte reduz o Vale na origem e, depois, o aquecimento deve ser particionado por conjunto regional em vez de aquecer o catálogo mundial.

`MountainStaticModelView.gd` agora entra na árvore com viewport/câmera/modelo/luz/ambiente completos, começa em `UPDATE_DISABLED` e serializa primeiras ativações `UPDATE_ONCE`, uma por frame. A construção estrutural ficou em cerca de 5,42 ms e ativações seguintes em até 7,48 ms. Contudo, o primeiro render frio ainda mediu 21,18 ms. Ablação sem sombras deu 21,77 ms e resolução interna a 50% deu 19,99 ms: luz, sombra e quantidade de pixels não são o custo dominante; o restante é inicialização fria de render target/pipeline/shader. A frente está funcionalmente aprovada, mas continua reprovada para a promessa absoluta de 16,67 ms no primeiro uso.

A floresta streamed deixou de materializar o mapa inteiro. `MountainForestStreamer.gd` indexa o plano determinístico em células de 320 px, acompanha `RegionTravel.controlled_car()` ou o jogador, carrega a vizinhança de 900 px e uma faixa antecipada no sentido do movimento, e remove células além de 1.480 px com histerese. A repetição local manteve 547 itens/522 pinheiros no plano, mas apenas 87 residentes na entrada e pico de 197 durante ida e volta; foram 813 materializações, 698 evicções e 338 reentradas. O builder devolveu em 2,280 ms, planejamento atingiu 1,308 ms, materialização 3,247 ms e evicção 0,370 ms, sempre até duas instâncias por frame. Variantes, escala, neve/bare, rochas e colisões reapareceram iguais na volta. O intervalo bruto headless chegou a 20,782 ms e não certifica FPS; a rota renderizada decide se a pré-carga de 900 px/820 px à frente evita pop-in e hitch no carro real.

O atlas do primeiro `MountainPine3D` deixou de ser uma etapa indivisível. Um worker persistente na raiz sobrevive à evicção da árvore que fez o primeiro pedido; enquanto o atlas global é preparado, o pinheiro procedural 2D permanece visível e collider/gelo já funcionam. O cache fica limitado às 16 combinações de neve e variante. Em quatro execuções renderizadas isoladas, construção fria caiu de 36,6 ms para 8,6--10,5 ms, primeira apresentação de 34,9 ms para 10,4--13,6 ms e instância quente para 0,20--0,24 ms. A meta isolada de 16,67 ms passou. O material final usa iluminação estática e ficou visualmente um pouco mais plano; isso foi aceito apenas como pendência visual, não como prova da rota completa. Os fixtures curtos ainda encerram o processo com atlas assíncronos em andamento e podem imprimir avisos de recursos no teardown.

## Atualização: orçamento global de trabalho pesado

`systems/RuntimeWorkScheduler.gd` passou a arbitrar as fatias pesadas que antes tinham apenas limites locais independentes. Avião, floresta, atlas dos pinheiros e decoração de inverno agora pedem uma reserva global antes da fatia e registram custo real ao terminar. O gate concede no máximo uma reserva pesada por frame, usa prioridade com aging, cancela automaticamente pedidos cujo owner saiu da árvore e mantém telemetria limitada a 512 registros.

No contrato concorrente `tests/test_runtime_work_scheduler_integration.gd`, os quatro produtores reais concluíram em 76 frames, com 75 reservas concluídas, nenhuma colisão de duas reservas no mesmo frame, espera máxima de 7 frames, fila final vazia e cancelamento de owner inválido confirmado. Contagem por produtor: winter 55, avião 11, pinheiro 5 e floresta 4. Os contratos isolados de avião, floresta e pinheiro também continuaram passando.

Esse mecanismo elimina a soma acidental de construtores diferentes, mas não torna uma operação indivisível barata. A primeira reserva fria do winter ainda consumiu 111,3 ms headless e produziu intervalo bruto de 119,8 ms. O scheduler está estruturalmente aprovado; o winter e a promessa de 16,67 ms continuam reprovados até decompor ou preaquecer essa inicialização. A estrada parcelada ainda precisa usar a mesma API para não competir com esses produtores.

O próximo comparativo integrado deve acontecer somente depois de reunir: estrada no scheduler, winter sem reserva fria de três dígitos e prewarm veicular por região. Em seguida, executar a rota física renderizada em duas passagens separadas: perseguição normal e caos de nível 4, sempre com trânsito, polícia, clima e transição Harbor--Mountain ativos.

### Estrada da serra no scheduler

`MountainPassRoad.gd` agora parcela a construção streamed em 11 reservas do scheduler global. No teste renderizado isolado em RTX 4060/Mobile, nenhuma reserva pesada coincidiu com outra no mesmo frame; o pavimento atingiu 13,6 ms e a física agregada do guard-rail 4,9 ms. A estrada publicou 15 rotas sem bloqueios no contrato de geodados.

O maior pico restante da montagem da estrada está fora desses estágios: `MountainCliffEdges.build` consumiu 132,8 ms de uma vez. O arquivo está alterado concorrentemente e a rotina `MountainCliffFall.gd` aparece removida no worktree atual; não sobrescrever nem restaurar isso por Git. A mecânica de queda e o parcelamento espacial do penhasco precisam de decisão explícita antes de editar esse conjunto. Até lá, a travessia real continua reprovada para 16,67 ms na primeira visita.

### Prewarm veicular por região

`VehicleGeometryCache.prepare_common_models()` agora aquece apenas o manifesto real de Harbor; `prepare_region()` permite solicitar Mountain depois, com cancelamento entre modelos, telemetria de tempo/memória e descritores de jobs. `VehiclePrewarmManifest.gd` deriva as listas de Harbor e Mountain das constantes de tráfego e estacionamento existentes, acrescentando apenas veículos autorados fora delas.

No teste headless, Harbor caiu de 45 modelos globais solicitados para 35 regionais e de 32 templates retidos para 23. O tempo caiu de aproximadamente 3.552 ms para 2.868 ms; a segunda chamada idempotente ficou em 0,343 ms. O SnowPlow permaneceu frio até Mountain ser solicitado. Os 23 modelos suportados pelo cache tiveram zero miss e zero cold build após o prewarm; 12 modelos operacionais externos ainda são apenas aquecidos, sem template restaurável. A memória estática adicional observada foi cerca de 30,1 MB e eviction continua desativado até existir rastreamento seguro de instâncias vivas.

Os contratos antigos que exigiam Arctic/serra durante o startup de Harbor foram atualizados para a propriedade regional: Harbor não pode reter Arctic antes da travessia; depois de `prepare_region(..., &"mountain")`, o template deve existir. `test_harbor_vehicle_prewarm_coverage.gd` e `test_vehicle_geometry_cache.gd` passaram novamente. O segundo ainda reporta RIDs/ObjectDB vivos no teardown; a asserção funcional passa, mas o vazamento de fixture/cache permanece dívida.

O maior modelo indivisível agora é `world/harbor/monaliza/MonalizaModel.gd`, com cerca de 697 ms headless. Está escondido pelo loading inicial, mas inviabiliza aquecimento regional durante gameplay e precisa ser otimizado na origem antes de conectar jobs veiculares ao scheduler global.

### Material de neve baked

O pico frio do winter foi localizado em `_ensure_resources()`: 113,416 ms eram gastos gerando proceduralmente albedo e normal 256×256 da neve; a primeira árvore custava apenas 0,494 ms e a alocação de batches 1,283 ms. `WinterDressingSnowMaterial.res` agora guarda o mesmo albedo/normal com mipmaps, projeção triplanar, cores, rugosidade e `normal_scale`.

Depois da troca, `_ensure_resources()` mediu 0,086 ms, primeira árvore 0,489 ms e batches 1,309 ms. O carregamento frio do script mais o recurso mediu 16,393 ms, muito próximo do teto de 16,67 ms, porém nenhuma das 56 reservas winter do teste concorrente excedeu o orçamento. Foram preservados 31 elementos físicos (19 sólidos, 12 atravessáveis), 138 primitivas e os MultiMeshes. A rota renderizada ainda precisa confirmar o custo real de carregamento e upload do recurso.

### Aproximação física e cache de Mountain

`VehicleRegionalPrewarmCoordinator.gd` foi ligado ao `ContinuousWorld`: ele observa o carro controlado ou o jogador real sem alterar transform/velocidade. O gatilho direto é 3.600 px antes da costura e o lookahead usa 8 segundos da velocidade; a 300 px/s, começa perto de 6.000 px. Se o jogador retornar além de 4.600 px afastando-se a mais de 20 px/s, a sessão é cancelada e uma retomada executa somente jobs restantes. Cada modelo recebe uma reserva própria no scheduler, no máximo um por frame, com prioridade maior à medida que a costura se aproxima.

No contrato progressivo, Mountain preparou 5 modelos suportados e concluiu a 5.975 px da costura, com passo máximo de 5 px por frame, zero travessias antes da prontidão, zero miss e zero cold build ao instanciar depois. Modelos exclusivos de Harbor/global continuaram frios. A telemetria registra `crossed_before_ready`, sessões, jobs/frame e readiness por template. O maior job ainda era `SnowPlowModel`, 87,889 ms headless; isolamento global não reduz esse construtor indivisível.

### Monaliza

O custo de aproximadamente 697 ms da Monaliza foi atribuído ao recorte repetido das caixas de roda durante `VehicleWheelRig.mount`. `MonalizaWheelWells.res` preserva os meshes recortados exatos e pesa aproximadamente 133 KB. Headless, montagem das rodas caiu de 692,26 ms para 0,77 ms e pipeline construção+rodas+batching de 708,50 ms para 13,93 ms (-98,03%). O prewarm regional indicativamente caiu de 2.863 para 2.242 ms.

Na RTX 4060, depois do prewarm, construção+rodas+batching mediu 10,68 ms e a primeira apresentação do carro de gameplay 2,52 ms. Totalmente frio continua reprovado: carregamento 26,16 ms, construção 83,41 ms, batching 42,79 ms e primeira apresentação 150,40 ms. Foram preservados assinatura visual `302201904`, 39.671 triângulos, quatro rodas, pintura por instância, dano/reparo, porta-malas, showroom e `TrunkLiveView`. A captura `_codex_diag/monaliza-baked-wheel-wells.png` foi inspecionada: carroceria, rodas e materiais aparecem em 3D e não pretos.

### Primeira apresentação das vistas 3D estáticas

`MountainStaticModelView.gd` agora prepara em fases serializadas pelo scheduler: bootstrap mínimo do backend, alocação do alvo final e render completo fora do primeiro frame visível. A apresentação posterior caiu do histórico de 21,18 ms para 0,16--1,34 ms, mantendo 960×800, modelo, luz e sombras. Preparação automática é bloqueada quando a vista está perto da tela; no contrato ficou 20 frames sem consumir GPU e só renderizou após solicitação real.

O rastreamento de mutações foi mantido somente na subárvore local e desconecta depois do preparo; não existe mais fan-out via `SceneTree.node_added/node_removed`. Há invalidação explícita por `mark_static_render_dirty()` e telemetria de fila/fases. A fila terminou sem pending/in-flight.

O único estágio ainda instável é o bootstrap gráfico global 1×1: oscilou entre 13,44 e 18,41 ms. Alvo final (~0,75 ms) e modelo (~2,63 ms) ficaram baratos. A correção seguinte deve executar uma vez esse bootstrap durante `GameLoading`, antes de liberar controle, e então confirmar a rota real.

### Bootstrap gráfico no loading real

`GameLoading.gd` agora paga o bootstrap gráfico global depois de `world_build`, com a tela de loading visível e o mundo ainda pausado, antes do preparo veicular e da liberação dos controles. Novo jogo e restauração de save usam o mesmo `_run()`. A tentativa usa um viewport 1×1 temporário, mantém uma referência viva à textura até `frame_post_draw` e remove completamente o host ao terminar.

Na RTX 4060 Laptop/Forward Mobile, a fase contabilizada no loading levou 99,3 ms, incluindo 47,6 ms de espera pelo primeiro draw. Depois dela, o alvo 960×800 custou 1,132 ms, o render completo do modelo 1,732 ms e a primeira apresentação no gameplay 0,311 ms. Uma execução fria sem passar pelo loading chegou a 37,94 ms, confirmando que o custo não pode ficar no percurso do jogador.

Timeout não entra em loop: a pendência é registrada no loading atual, o mundo permanece pausado, e somente uma nova sessão de loading pode tentar outra vez. A telemetria distingue `scope=loading_global`, `charged_to=loading` e `vehicle_model_cost_included=false`; nenhum viewport temporário permaneceu. Os contratos headless, renderizado, idempotência e retry passaram. Isso resolve o pico específico de bootstrap, mas ainda não certifica a rota completa.

### Falha de prewarm não pode virar sucesso

`VehicleGeometryCache.execute_region_job()` não marca mais `_prepared` incondicionalmente. Um modelo operacional fora do contrato de restore pode ser considerado aquecido quando o construtor real terminou; um caminho suportado pelo cache só sai da fila quando o template restaurável foi capturado. Falha de construção ou captura permanece repetível, entra em `failed_models` e cancela o coordenador regional com causa explícita. O contrato usa um script suportado que não constrói `Node3D` para provar que a falha não desaparece da fila.

### Veículos externos e Cabriolet

O profiler dos 12 modelos externos de Harbor agora reproduz o pipeline real: construção, entrada na árvore, `VehicleWheelRig.mount`, `VehicleMeshBatcher.batch_model` e primeira apresentação, com o bootstrap global descontado. Todos ainda excedem 16,67 ms totalmente frios, portanto o prewarm regional é requisito arquitetural, não otimização opcional.

O pior modelo inicialmente isolado foi o Cabriolet: 66,32 ms de construção, 134,95 ms de montagem/recorte das rodas, 36,41 ms de batching e 7,40 ms de primeira apresentação; pipeline frio 245,09 ms. `CabrioletPreparedGeometry.scn` moveu a geometria recortada e batched para um recurso reproduzível. Depois: construção 59,09 ms, rodas 0,19 ms, batching 3,65 ms, primeira apresentação 7,66 ms, pipeline frio 70,59 ms (-71%) e caminho pós-prewarm 1,96 ms. Foram preservados 56.358 triângulos, assinatura `887016387`, quatro rodas, interior/conversível, pintura independente, dano, lâmpadas e reparo.

Ranking frio depois do Cabriolet, sem bootstrap/script load: BossMuscle 221,31 ms; PortBossRoadster 170,01; RegionalIntercityCoach 137,30; RescuePumper 125,55; MedicBox 113,71; HarborTransitBus 98,56; PoliceMotorcycle 86,72; PortForklift 86,06; HarborContainerTruck 78,28; Cabriolet 70,59; UrbanBus 32,85; UrbanBusTrailer 21,88. O BossMuscle repete o padrão de recorte (130,22 ms em wheel mount) e é a próxima frente. O teste de embarque também expôs um deslocamento 2D do pedestre ao sair pela esquerda do Cabriolet; contratos 3D passaram, mas a saída do veículo permanece pendência separada.

### SnowPlow

O limpa-neve passou a usar geometria baked equivalente à autoria. Construção caiu de 20,17 para 4,73 ms, recorte/montagem das seis rodas de 43,69 para 0,27 ms, batching de 7,12 para 1,41 ms e pipeline do modelo de 71,57 para 6,61 ms. Com recurso já carregado, o prewarm ficou em 9,13 ms; restore 1,85 ms e primeira apresentação pós-loading 0,99 ms. Foram preservados 38.642 triângulos, assinatura `3643091624`, lâmina, cutting edge, hopper, pintura independente/não preta, dano e deformação; nós geométricos caíram de 125 para 46.

A equivalência renderizada autoria/PackedScene teve RMS 0,000280 frontal e 0,000337 lateral, com mesmos bounds e materiais. A placa branca suspeita nas primeiras capturas era o topo de sal do hopper; fundo cinza confirmou que não estava destacada.

O job regional totalmente frio ainda reprova: 56,13 ms, agora dominados por `load(SnowPlowModel.gd)` síncrono, não pela construção. O teste vermelho foi preservado. A próxima mudança deve iniciar `ResourceLoader.load_threaded_request` durante a aproximação, consultar o status ao longo dos frames e só reservar o scheduler quando o recurso estiver pronto; `execute_region_job` precisa reutilizar o recurso carregado.

### Qualidade dos SubViewports sem wake em massa

O HarborGame real continha 311 SubViewports. A implementação anterior de `RenderQuality` promovia MSAA e forçava `UPDATE_ONCE` em todos os caches desabilitados no mesmo sinal: 113 views adormecidas foram acordadas, a callback custou 139,7 ms, o pico atingiu 78,20 ms e a memória de render cresceu cerca de 790,1 MB.

`RenderQuality.gd` agora preserva MSAA explicitamente autorado, parcela views genéricas ativas em no máximo quatro por frame e orçamento de pixels, e não acorda caches dormentes. A detecção automática de uma view que acabou de ficar residente é limitada a uma janela de um segundo/512 verificações; depois disso, `pending=0`, `idle=true`, timer e `_process` desligados. Views ainda dormentes guardam apenas metadado/hook. `PopulationActivity.set_active(true)` consome esse hook antes de restaurar apresentação e update mode, portanto um ator que acorda muito depois recebe o MSAA atual sem polling global.

Na validação final: callback 1,30 ms, pico 23,65 ms, p95 20,98 ms e memória adicional ~199,4 MB; 0 wake em massa. `SouthDockWorker0` acordou de `UPDATE_DISABLED` para `UPDATE_WHEN_VISIBLE`, mudou 2x→4x e consumiu o hook. O teste dedicado dormiu dez atores, deixou o sistema ficar ocioso e acordou somente um; os outros nove permaneceram 2x/desabilitados. A troca de qualidade deixou de ser o pico sistêmico, mas o p95 ainda excede 16,67 ms e a base de 311 SubViewports/~2 GB de render precisa de auditoria por categoria antes de escalar para cinco cidades.

### ResourceLoader assíncrono no prewarm regional

`VehicleRegionalPrewarmCoordinator` agora solicita os scripts/recursos de todos os jobs pela API threaded durante a aproximação, consulta o estado ao longo dos frames e só pede a reserva pesada quando o `Resource` está pronto. `execute_region_job` reutiliza o `Script` carregado e rejeita tipo/caminho incompatível. Cancelamento e retomada preservam quatro jobs pendentes no contrato, falhas permanecem retryable em `failed_models`, aproximação física realizou 5 requests/5 recursos/5 reservas/5 execuções e manteve no máximo um job pesado por frame, sem teleporte.

O critério temporal continua reprovado. Em sete processos completamente frios do SnowPlow, o request custou 0,129–0,343 ms e seis jobs carregados ficaram em 10,247–15,698 ms, mas um primeiro uso consumiu 738,669 ms dentro da construção/captura. Mediana 10,669 ms; 6/7 dentro de 16,67 ms. A aproximação também encontrou `RanchSingleModel.gd` em 33,942 ms. Não usar média nem cache quente para aprovar: é preciso instrumentar `script.new`, entrada na árvore/_ready, rig, batching e captura separadamente, isolar o outlier e corrigir RanchSingle antes da rota.

### BossMuscle

`BossMusclePreparedGeometry.scn` consolida a autoria em 10 grupos operacionais com 26.582 triângulos, assinatura `3943922188`, quatro rodas, quatro lâmpadas, uma carroceria deformável e um grupo estático. O modelo só aceita o recurso com contrato v2 e todas essas invariantes; bake incompleto/errado é recusado e cai na geometria procedural, sem duplicar nós nem expor visual preto/corrompido.

Na RTX 4060/Forward Mobile, bootstrap (15,855 ms) e resource load (17,729 ms) foram medidos separadamente. Pipeline frio 50,763 ms e prewarm completo 42,497 ms continuam fora do orçamento, mas o caminho real depois de `VehicleGeometryCache._prepare_model_template` ficou em 4,259 ms: construtor 0,015, restore+add 0,610, rodas 0,085, rebatch 0,001 e primeira apresentação 3,548 ms. A primeira instância de warmup foi liberada antes da medição. Cache hit, dano, quebra localizada de luz, carbonização, reparo e pintura independente passaram. BossMuscle está aprovado somente pós-prewarm; não é seguro frio no gameplay.

### Telemetria interna dos jobs regionais

`VehicleGeometryCache` agora separa `script.new`/instanciação, `add_child`/`_ready`, wheel mount, batching, flatten, captura/pack, request de viewport, liberação do modelo e tempo não atribuído. Em 20 processos frios isolados do SnowPlow: mínimo 9,769 ms, mediana 10,410, p95 10,831, máximo 15,590 e 0/20 acima de 16,67 ms. P95 por estágio: instanciação 6,194 ms, captura 3,257, batching 0,964 e rodas 0,322. O outlier histórico de 738,669 ms não reapareceu e não pode ser atribuído retroativamente; permanece falha histórica, não aprovação absoluta. Se repetir, a nova telemetria identifica o estágio.

O RanchSingle isolado marcou 52,734 ms: wheel mount 30,067, instanciação 14,501, batching 5,325 e captura 2,346 ms. É o maior gargalo regional reproduzível atual e deve ser otimizado antes da rota. Cada processo diagnóstico ainda encerra com aviso de uma instância ObjectDB vazada; não confundir isso com aprovação limpa do fixture.

Importante: job isolado abaixo de 16,67 ms não é aprovação de 60 FPS. O frame real já consome cerca de 10–12 ms em Harbor; somar um job de 10–15 ms ainda produz 20–27 ms. O scheduler mantém orçamento extra de 6 ms e marca `over_budget`; a rota integrada deve correlacionar a reserva/job com o frametime total do mesmo frame. Qualquer aprovação final vem do frame composto, não do teto inteiro aplicado separadamente a cada sistema.

### RanchSingle compactado, prewarm ainda vermelho

`RanchSinglePreparedGeometry.scn` remove o recorte das rodas e o batching repetidos, com fallback procedural validado. A forma final preserva assinatura `2058053124`, 13.800 triângulos, 14 grupos, quatro rodas, quatro lâmpadas, pintura independente, dano/reparo e equivalência visual. O fixture agora reprova divergência real de assinatura; uma primeira compactação que alterou a assinatura foi detectada e não foi aceita até restaurar o contrato semântico.

Procedural versus compacto: prewarm regional 94,761→48,454 ms; instanciação 47,259→44,023; rodas 27,649→0,116; batching 15,960→1,636 ms. O gameplay restaurado pelo cache ficou 6,377 ms, mas o prewarm continua muito acima da fatia extra de 6 ms. O custo restante é `script.new`/instanciação. A frente seguinte deve evitar instanciação/captura duplicada e transformar o pipeline regional em estados retomáveis (shell/materiais, geometria preparada, rodas, batching, captura), cedendo entre etapas; não esconder 44 ms dentro de uma única reserva.

### Inventário de SubViewports do HarborGame

O inventário renderizado encontrou 311 SubViewports, todos gerenciados por `RenderQuality`; 195 (62,7%) estavam dormentes. São 52.150.006 pixels configurados e 170.220.588 pixel-samples com MSAA; caches dormentes concentram 113.852.656 (66,9%). Observação global: renderer ~2.206.465.040 bytes (2.104 MiB) e memória estática do processo ~816,7 MiB. Não atribuir esses bytes globais a owners; ranking causal usa contagem/pixels/pixel-samples.

A população dormindo não é o principal retentor: 74 views e 1.902.592 pixel-samples (~1,1%). Props estáticos somam ~77,1 milhões e interiores ~67,5 milhões. Maiores grupos: `MountainStaticModelView` 59 dormentes/32,9 milhões; seis estações 20,7 milhões; três interiores residenciais 17,28 milhões; três exteriores residenciais 9,216 milhões; ferro-velho 8,256 milhões. Cada residência usa 1440×1000 com MSAA 4x (5,76 milhões de amostras), casa do coveiro 1200×960 4x, workshop 2048×1024 2x.

Primeira compactação segura sugerida: somente texturas de interiores residenciais inativos sob `InteriorSpaces`, restaurando tamanho/MSAA pelo hook de qualidade e renderizando antes do fade de entrada. Não alterar `MountainStaticModelView` nem estações nessa etapa. O fixture terminou `failures=[]`, mas imprimiu avisos de RIDs no teardown rápido; não usar isso como prova de vazamento do jogo.

## Atualização: jobs regionais retomáveis e cancelamento real

`VehicleGeometryCache.advance_region_job()` agora executa uma única etapa retomável por ticket e publica `_models`/`_prepared` atomicamente apenas no commit. Cargas usam `ResourceLoader` threaded; captura aninhada é suprimida durante o job regional. A telemetria guarda `ticket_id`, frame, produtor, caminho, estágio e custo real e separa `regional_misses`/`regional_cold_builds` de simples carregamento. O scheduler passou a cancelar pendências por owner/produtor e o coordenador preserva a causa original ao retornar ou cancelar uma sessão.

O contrato do scheduler passou com fila final vazia, cancelamento seletivo e nunca duas reservas pesadas no mesmo frame. A dívida continua explícita: alguns jobs antigos ainda excediam 6 ms, portanto o mecanismo de cadência não era aprovação de frametime por si só.

`RanchSingle` passou a entrar diretamente por recurso preparado: total ativo 7,727 ms distribuído e maior estágio 2,755 ms. `SnowPlow` também usa geometria preparada direta: total ativo 4,810 ms e maior estágio 1,703 ms. Ambos evitam `procedural_build`, wheel mount, batching, flatten e capture pack no percurso regional.

## Atualização: segurança do cache e frota regional

O cache agora distingue template restaurável de aquecimento somente operacional. Um modelo com referências vivas não pode mais ser publicado falsamente como `_prepared`; opt-out explícito usa `vehicle_geometry_cache_operational_only()`. `RescuePumper` permanece operacional-only porque torre e bocal de água ainda não têm contrato de reatach seguro. Motos deixaram de consultar transform global fora da árvore e os quatro modelos passaram o contrato isolado sem carros 2D/pretos.

`MedicBox` falhava com `unsafe_operational_node_references:rear_doors`. As portas passaram a ser resolvidas por `NodePath` estável (`RearDoorLeft`/`RearDoorRight`), mantendo cache completo. O prewarm de Harbor passou com `failures=[]`; a segunda execução ficou em 1,092 ms, sem job, miss ou cold build repetido. A frente de geometria integral preparada do MedicBox ainda está em andamento porque o wheel mount frio observado foi 14,009 ms.

`ArcticJeepPreparedGeometry.scn` compacta a forma pós-clearance/batching em 12 grupos. Em três processos frios, total ativo 2,318–2,624 ms e maior estágio 1,125 ms. Foram preservados quatro centros de roda, dois faróis, 11 papéis de material, assinatura visual `2561308829`, clearance `2025983418`, dano/reparo e fallback procedural.

`CourierVan` e `SummitSUV` receberam wheel wells preparados. Validação renderizada na RTX 4060/Forward Mobile:

```text
CourierVan wheel_mount: 11,965 -> 0,424–2,097 ms
SummitSUV wheel_mount: 15,749 -> 0,326–1,153 ms
restore de cache: 0,171–0,243 ms
```

Quatro rodas 3D, materiais independentes e não pretos, geometria, dano/reparo e cache passaram. Contudo, construção procedural fria ainda mediu 59–103 ms e batching 16–51 ms no perfil renderizado. O teste de aproximação mais recente ficou com um único estágio acima de 6 ms: `CourierVanModel.gd::procedural_build = 8,339 ms`. Por isso Courier e Summit estão sendo convertidos para recursos integrais preparados; a aproximação ainda não está aprovada.

## Atualização: residências compactadas, validação visual ainda aberta

Três interiores residenciais inativos agora ficam em 2×2 e `UPDATE_DISABLED`, preservando o tamanho autorado 1440×1000 separadamente. Antes de entrar, o hook de qualidade é consumido, o alvo é restaurado e a tela só aparece depois de `frame_post_draw`. Colisão, spawn e estações usam uma base ortográfica imutável calculada em 1440×1000; isso corrigiu uma falha escondida em que `Camera3D.unproject_position()` consultava o alvo compactado e deslocava a física por centenas de pixels.

No HarborGame renderizado real, três residências caíram de 17.280.000 para 48 pixel-samples enquanto inativas. O corpo real do Player atravessou o corredor nas duas direções e foi bloqueado pelo `DoorBoundary` em movimento varrido. A entrada mediu p50 15,827 ms, p95 23,149 ms e máximo 26,345 ms; não está aprovada para 16,67 ms. A captura mostra o Player 3D visível e não preto, mas o controle automatizado de diferença de pixels deu zero porque escondia o anchor em vez do rig diretamente. O fixture foi corrigido para alternar o rig; falta a repetição renderizada antes de aprovar profundidade/oclusão.

## Estado exato desta fase

- Harbor regional funcional/idempotente: verde.
- RanchSingle, SnowPlow e ArcticJeep por estágio: verdes isoladamente.
- Courier/Summit wheel mount: verde; pipeline integral ainda em trabalho.
- Aproximação Harbor--Mountain: vermelha por `CourierVan procedural_build` 8,339 ms na última execução.
- Residência: física e economia de target verdes; visual-depth e p95 ainda vermelhos.
- Rota física normal/caos: não executar até a aproximação não ter stages >6 ms.
- Meta 60 FPS mínimo: ainda não atingida.
- `MountainCliffEdges.build` continua com pico conhecido de aproximadamente 132,8 ms e não foi editado por existir trabalho concorrente no arquivo e remoção concorrente de `MountainCliffFall.gd`.

## Atualização: frota preparada, bootstrap de materiais e primeira rota real

`MedicBoxPreparedGeometry.scn` passou a ser o recurso integral da ambulância: 43 meshes, 23.503 triângulos e assinatura `3101446470`. O job ativo total ficou em 3,937 ms, maior estágio 1,483 ms e restauração das rodas 0,197 ms; portas traseiras, quatro rodas, materiais não pretos, dano/deformação/reparo e fallback passaram. O fixture dedicado foi ampliado de 16 para 256 passos porque o limite antigo não representava a quantidade real de grupos preparados.

`SummitSUVPreparedGeometry.scn` eliminou construção/recorte/batching procedural no job regional. Em cinco processos headless+renderizados, o maior estágio absoluto ficou em 4,951 ms. Na regressão integrada, Arctic/Summit/Ranch/Snow usaram respectivamente 14/16/16/48 fatias, com máximos 1,043/2,811/2,407/4,363 ms; cancelamento, retry, publicação atômica, materiais, rodas e dano passaram.

O attach de `PackedScene` preparada em `VehicleGeometryCache` agora é retomável: begin, uma fatia por grupo e finish. A raiz vazia entra em um viewport de warmup, somente um grupo é anexado por ticket/frame e a publicação em `_models`/`_prepared` continua atômica no commit. Cancelamento libera filhos parentless e não expõe template parcial. Arctic, Ranch, Snow e Summit passaram inclusive nos limites de cancelamento.

`CourierVanPreparedGeometry.scn` tem 19 grupos, 31 surfaces, 24.488 triângulos e assinatura `4069370056`. O cold render direto revelou que os picos restantes eram compilação da primeira variante de rubber/lamp/glass (20--22 ms por material e 38--40 ms no frame adjacente), não tamanho de mesh. `GameLoading` agora aquece as quatro famílias canônicas de material com loading visível e mundo pausado, depois aquece Harbor. Num cenário que retém pipelines e limpa somente o template Courier para simular uma região futura, baseline idle p95/max foi 16,732/16,775 ms e o job Courier 16,730/16,752 ms, delta -0,002/-0,023 ms; maior estágio 0,921 ms, maior attach 0,159 ms e zero estágio acima de 6 ms. Isso prova o job isolado pós-loading, não a rota absoluta.

`CoupeDamagePreparedGeometry.scn` substituiu um pipeline de 197,361 ms dominado por wheel clearance de 165,972 ms. A forma preparada tem 38 meshes, 61.039 triângulos e assinatura `909733885`; usa 48 estágios, máximo 2,389 ms, attach 0,919 ms, restore de rodas 0,179 ms e primeira apresentação 0,601 ms. Quatro rodas, 11 luzes, pintura independente/não preta, duas carrocerias deformáveis, dano, luz quebrável, reparo e fallback passaram. As constantes/helpers da base foram prefixadas `COUPE_*`/`_coupe_*` para não colidir com subclasses; não reintroduzir constantes genéricas nessa base.

O contrato de aproximação física mais recente ficou verde: cinco requests, cinco recursos prontos, cinco modelos instanciados, 155 estágios/reservas, zero estágio acima de 6 ms, no máximo um job pesado por frame, nenhuma espera bloqueante e todos concluídos antes da costura. Isso é evidência funcional/arquitetural; não certifica FPS.

### Primeira rota normal renderizada após o staging

A execução `artifacts/real-route-normal-20260919-staged` usou HarborGame real, caminhada, embarque e direção somente por input, wanted 2, polícia, população e trânsito. Terminou vermelha antes da costura porque o carro ficou bloqueado e foi destruído. Foram 7.771 frames/151,31 s: média 19,471 ms, p50 16,526, p95 31,398, p99 44,215 e máximo 1.777,365 ms; 3.793 frames acima de 16,67, 244 acima de 33,3 e 58 acima de 50 ms. População média/pico 134/157, trânsito 18,7/23 e polícia 2,70/4.

O maior achado não é o cache veicular: durante a rota houve somente um miss/cold build não regional de 2,308 ms. O problema dominante foi a montanha sendo construída quando o carro ainda estava 7.770 px da costura. `mountain_static_render` executou 191 jobs, total 9,572 s de CPU, média 50,115 ms, máximo 1,646 s, 189 jobs acima do orçamento de 6 ms e 147 compostos com frames acima de 16,67 ms. Winter/pine/cargo/road também rodaram cedo. Pico de apresentação: 493 SubViewports totais, 192 ativos e 74.895.922 pixels. Na direção, SubViewports ativos médios 159,4 e frame time médio/p95 20,87/32,23 ms; a pé, 125,9 e 13,86/20,19 ms.

O fixture de rota agora detecta 1,8 s sem progresso e executa somente inputs reais de ré/esterço/avanço. Se o carro for destruído, sai pela ação normal, caminha até um veículo íntegro e embarca com `E`; não escreve transform, posição, rotação ou velocidade. A validação estrutural passou: 35 waypoints, 13.835,4 px e costura cruzada pelo trajeto. Ainda falta repetir renderizado depois de: (1) impedir montagem distante da montanha e fatiar os jobs reais abaixo de 6 ms; (2) reduzir SubViewports ativos/pixels sem sprites 2D; (3) concluir `VerticeMidEngine` preparado. Não executar caos antes de uma rota normal funcional completa.

### Pendências abertas exatas

- Montanha: gating por aproximação física e decomposição real de `mountain_static_render`; trabalho em andamento.
- Apresentações: orçamento/atlas/compactação para reduzir 192 SubViewports ativos sem remover 3D/população; trabalho em andamento.
- VerticeMidEngine: wheel mount de aproximadamente 102 ms e máximo de modelo ~133 ms no loading; conversão preparada em andamento.
- Residência: última correção do positive-control esconde cada `VisualInstance3D`; repetição renderizada ainda não feita. Entrada anterior p50/p95/max 16,670/20,763/21,424 ms, portanto ainda vermelha.
- Meta 60 FPS mínimo: não atingida e não deve ser declarada até normal e caos completarem fisicamente com frame composto dentro do contrato.
