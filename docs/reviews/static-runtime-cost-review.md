# Revisão estática — custo e carregamento do mundo (Geteco V2)

Data da leitura: 21/09/2026  
Escopo: `geteco_v2`, somente leitura de código e configuração.  
Estado da evidência: **não medido**. Esta revisão não executou Godot, importação, compilação, testes, benchmark ou captura e, portanto, não aprova desempenho nem atribui FPS.

## Resumo prioritário e encaminhamento

| Prioridade | Achado | Impacto possível no jogador | Equipe indicada |
|---|---|---|---|
| P1 | Chunk é construído de forma síncrona e indivisível, inclusive malha e colisão | travamento curto ao cruzar células, sobretudo em porto e montanha | Mundo/streaming V2 + física |
| P1 | Toda a distribuição florestal da montanha é preparada ao criar a região | pausa na primeira carga/viagem para a montanha | Mundo/streaming V2 |
| P1 | Interiores não persistentes são carregados e reconstruídos no ato da entrada | atraso perceptível ao entrar e custo repetido ao revisitar | Interiores V2 + transições |
| P2 | Áudio do veículo resolve catálogo/recurso a cada quadro | custo recorrente e possível pico na primeira troca de família | Áudio/runtime V2 |
| P2 | Equipamento de veículos permanece em `_process` e reescreve estado inalterado a cada quadro | custo cumulativo com viatura(s) e carro já equipado | Veículos V2; integração externa de despacho |
| P3 | Consultas globais por grupo são refeitas por polling | custo de CPU/alocação que cresce com objetos registrados | Sessão/input + sobrevivência ao frio |

Os dois primeiros itens são a mesma frente de engenharia, mas não duplicam a causa: o primeiro trata o **trabalho pesado de cada chunk durante deslocamento**; o segundo ocorre **antes do streaming**, na preparação global da região montanhosa.

## Achados

### 1. P1 — montagem síncrona e indivisível de chunks no caminho de gameplay

1. **Prioridade e impacto no jogador:** P1. Ao mudar de célula, o chunk ocupado é montado imediatamente e os vizinhos são montados à razão de um chunk inteiro por quadro. Um chunk pode criar malhas, colisores, árvores, fachadas, estações e geometria portuária de uma só vez. Isso cria risco de frame longo/travamento curto durante deslocamento ou admissão em região; nenhuma duração foi medida.
2. **Arquivo, função e linha conferida:** `runtime/ProductionWorld.gd`, `_process`/`_update_physical_residency`, linhas 177–197 e 279–288; `world/regions/NativeRegion.gd`, `set_focus`/`_process`, linhas 140–166, e `_build_chunk`, linhas 194–275; `world/regions/MountainTerrain3D.gd`, `build_chunk`, linhas 82–130; `world/urban_detail/UrbanBuildingFactory.gd`, `populate_chunk`/`finalize_building`, linhas 115–152, e `_create_mesh_collision_safe`, linhas 220–238.
3. **Evidência e caminho de chamada:** `ProductionWorld._process()` chama `_update_physical_residency()`, que chama `set_focus()` nas regiões residentes enquanto o jogador está no exterior. Na troca de célula, `set_focus()` chama `_build_chunk()` imediatamente para a célula ocupada (linha 153); `NativeRegion._process()` chama a mesma função para cada vizinho pendente (linha 166), sem orçamento por tempo ou continuação por etapas. Na montanha, uma chamada gera arrays de terreno e executa `mesh.create_trimesh_shape()`; em Harbor, fachadas percorrem recursivamente suas malhas e podem executar `create_trimesh_collision()`. O caso de contêiner ainda chama `load(...HarborPortModel3D.gd).new()` e `art.build(...)` dentro do chunk (linhas 270–274). O descarregamento existe (`_trim_chunks()` chama `queue_free()` fora do raio de retenção configurado, linhas 160–164), mas uma revisita reconstrói o conteúdo.
4. **Classificação:** **risco**. A execução síncrona e a ausência de orçamento são demonstráveis por leitura; a existência e a magnitude de um travamento são não medidas.
5. **Correção sugerida, sem aplicar:** transformar `_build_chunk` em trabalho incremental com orçamento explícito (por etapa ou tempo), mantendo colisão mínima de admissão como etapa prioritária e separando apresentação pesada; preparar/reutilizar malhas e formas compartilháveis, especialmente terreno, fachadas autoradas e contêineres; preservar exatamente conteúdo, colisão e leitura visual. Não remover decoração como atalho.
6. **Validação necessária:** comparar a mesma rota renderizada antes/depois cruzando limites de célula em (a) centro/rota urbana, (b) South Port/contêineres/navio e (c) floresta/sawmill/vila na montanha. Registrar primeira visita e revisita, frame time p50/p95/p99/máximo, quadros acima de 33,3 e 66,7 ms, tempo de CPU/física/GPU/espera quando disponível, contagem de draw calls/corpos e eventos de construção por chunk. Confirmar também colisão e ausência de popping em cada etapa.

### 2. P1 — preparação global da floresta bloqueia a criação da região montanhosa

1. **Prioridade e impacto no jogador:** P1. A geração determinística de todos os registros de árvores ocorre antes de a região ficar pronta, no mesmo encadeamento que adiciona a nova região à árvore. Isso pode alongar a abertura de save montanhoso e a viagem Harbor → montanha; não há medição de duração.
2. **Arquivo, função e linha conferida:** `world/regions/NativeRegion.gd`, `_ready`/`_prepare`, linhas 42–47 e 53–130, e `_prepare_forest`, linhas 392–428; `runtime/ProductionWorld.gd`, `build`/`_mount_region`, linhas 60–69 e 144–151, e `_travel_checked`, linhas 437–448; `world/regions/OriginalWorldData.json`, `forest_clusters`, linhas 2433–2673.
3. **Evidência e caminho de chamada:** `REGION.build_region()` retorna um nó; `_mount_region()` chama `world.add_child(mounted)` (linha 150), o que executa `_ready()`, que chama `_prepare()` antes de marcar `prepared`. Para a montanha, `_prepare()` chama `_prepare_forest()`. Os 27 clusters declarados somam 734 árvores solicitadas; o algoritmo admite até `count * 6`, isto é, 4.404 tentativas, e em cada tentativa percorre lugares e registros de nove células para afastamento de estradas/árvores. Depois ainda filtra todo o dicionário `records`. Na viagem, `_travel_checked()` chama `_mount_region()` (linha 444), antes do primeiro `await` (linha 448).
4. **Classificação:** **risco**. A quantidade e o bloqueio síncrono são demonstráveis por leitura; não foi medido se o custo é perceptível no hardware-alvo.
5. **Correção sugerida, sem aplicar:** pré-calcular e versionar apenas os registros determinísticos de distribuição, ou mover sua preparação para uma fase incremental/cancelável antes da admissão; manter seed, exclusões, densidade e clareiras. Se houver cache em memória, invalidá-lo por versão dos dados e não fazê-lo reter nós de cena.
6. **Validação necessária:** medir separadamente tempo de criação da região, tempo até colisão admitida e intervalos de quadro na primeira viagem Harbor → montanha, no carregamento direto de save montanhoso e na segunda ida após cache. Repetir com o mesmo save/configuração e registrar pico de primeira visita versus regime aquecido.

### 3. P1 — entrada em interiores carrega e reconstrói toda a sala no ato da interação

1. **Prioridade e impacto no jogador:** P1. Pressionar para entrar em um interior não persistente faz carregamento dinâmico, instanciação e múltiplas varreduras/construções de colisão antes de a transição concluir. Como o nó é liberado na saída, a mesma carga se repete na revisita; há risco de pausa na interação.
2. **Arquivo, função e linha conferida:** `runtime/FullSession.gd`, `enter_place`/`leave_place`, linhas 405–476; `world/places/NativePlace.gd`, `_ready`, linhas 21–95; `world/places/PlaceCatalog.gd`, `create_place`, linhas 96–101.
3. **Evidência e caminho de chamada:** `FullSession.enter_place()` chama `PLACES.create_place()`, adiciona `room` ao mundo na linha 429 e só depois chega aos `await`s de sincronização. Ao entrar na árvore, `NativePlace._ready()` executa `load(definition.model)`, instancia o modelo, percorre toda a hierarquia para retirar ambientes/luzes, percorre `MeshInstance3D` para agrupar sólidos e volta a percorrê-los duas vezes para cutaway/acabamento, além de criar corpos/colisores. `leave_place()` chama `room.queue_free()` para todo interior exceto Maciota, portanto a próxima entrada repete a reconstrução.
4. **Classificação:** **risco**. O carregamento e a reconstrução síncronos e repetidos são fatos por leitura; o frame spike/latência é hipótese até medição.
5. **Correção sugerida, sem aplicar:** cachear os recursos carregados e avaliar pooling/residência limitada de salas pesadas, ou dividir preparação visual/física em fases cobertas pela transição; preferir colisões autoradas/preparadas a varreduras repetidas quando o contrato físico permitir. Preservar o padrão visual, a oclusão e a colisão dos interiores.
6. **Validação necessária:** medir primeira entrada, saída e segunda entrada no banco, hospital, garagem do chefe, chalé/lodge e caverna, em cena renderizada. Capturar latência da ação até controle devolvido, máximo de frame, p95/p99 em janela que inclua a transição, memória antes/depois e contagem de nós/corpos; executar validação física/oclusão separada depois da correção.

### 4. P2 — resolução de catálogo e de recursos de áudio ocorre no loop de quadro

1. **Prioridade e impacto no jogador:** P2. Enquanto dirige, o sistema consulta a especificação do veículo e chama `ResourceLoader.exists()` em todos os quadros. Mesmo que o cache do motor evite nova leitura física em muitos casos, as consultas continuam no caminho quente, e a primeira troca de família carrega e duplica sete streams. O efeito perceptível é não medido.
2. **Arquivo, função e linha conferida:** `audio/WorldAudio.gd`, `_process`, linhas 91–130; `runtime/FleetCatalog.gd`, `all`/`spec`, linhas 2–9.
3. **Evidência e caminho de chamada:** `WorldAudio` é criado por `ProductionWorld.build()` (`runtime/ProductionWorld.gd`, linhas 119–120 e 132–135). Quando `world.driving.occupied` é verdadeiro, cada `_process` executa `FleetCatalog.spec()` (linha 116) e `ResourceLoader.exists()` (linha 118), embora `family` só mude esporadicamente. O carregamento e a duplicação dos sete loops ficam corretamente condicionados à mudança de família, mas continuam síncronos no primeiro quadro dessa mudança (linhas 119–126). A releitura atual não encontrou mais `load()` por passo: passos usam os catálogos `WATER_SOUND`/`V1_AUDIO` (linhas 106–109), portanto essa parte da evidência anterior foi removida.
4. **Classificação:** **defeito por leitura** quanto ao trabalho redundante por quadro; qualquer regressão de frame ou áudio é **não medida**.
5. **Correção sugerida, sem aplicar:** resolver e guardar a família quando o carro dirigido muda; cachear existência e streams por família; manter duplicação somente onde for necessária para configurar loop sem mutar recurso compartilhado.
6. **Validação necessária:** comparar direção contínua com carro/família estável e sequência de troca entre famílias. Registrar frame time e CPU, primeira troca versus troca aquecida, alocações/carregamentos se instrumentados e continuidade sonora/loop/radio.

### 5. P2 — equipamento de veículos reescreve estado inalterado em todo quadro

1. **Prioridade e impacto no jogador:** P2. Depois que o carro do jogador recebe equipamento — e para viaturas externas que o despacho cria — cada instância chama `_refresh()` a cada quadro mesmo parada, desocupada e sem sirene. O custo individual é pequeno, mas soma loops de luz/material e chamadas de áudio por instância.
2. **Arquivo, função e linha conferida:** `gameplay/VehicleEquipment.gd`, `_process`/`_refresh`, linhas 118–143; `scripts/Driving.gd`, `interact`, linhas 63–70; `gameplay/dispatch/DispatchController.gd`, `_create_vehicle`, linhas 304–319 (somente ponto externo de integração, sem revisar despacho internamente).
3. **Evidência e caminho de chamada:** `Driving.interact()` instala o equipamento no veículo ocupado e ele permanece como filho do carro. O ponto externo de criação de viaturas também chama `ensure_equipment()`. `VehicleEquipment._process()` é incondicional e `_refresh()` reatribui visibilidade das lâmpadas, emissão dos materiais, tenta parar sirene/buzina e somente então usa `_phase` para evitar a parte final dos beacons. Não há `set_process(false)` para estado estável.
4. **Classificação:** **defeito por leitura** quanto ao trabalho redundante em estado estável; impacto no orçamento de frame é **não medido**.
5. **Correção sugerida, sem aplicar:** tornar faróis/ocupação/horn event-driven; manter processamento apenas enquanto o beacon precisa alternar ou enquanto uma transição sonora está ativa; reativar ao mudar ocupação, dano, farol ou sirene. A integração deve continuar respeitando o controlador externo de despacho sem alterar sua lógica interna.
6. **Validação necessária:** medir cenário renderizado equivalente com carro já equipado e estacionado, direção com faróis, e resposta externa com várias viaturas/sirenes. Comparar contagem de `_process`/CPU e frame time, além de verificar faróis, beacon, sirene, buzina, dano, embarque/desembarque e descarregamento.

### 6. P3 — consultas globais por grupo são refeitas por polling

1. **Prioridade e impacto no jogador:** P3. Há consultas por grupos globais em ciclos periódicos, produzindo arrays e trabalho proporcional aos membros enquanto o jogador está no mundo. Isoladamente parecem limitadas, mas competem com streaming e simulação nos mesmos quadros.
2. **Arquivo, função e linha conferida:** `scripts/Driving.gd`, `_process`/`can_enter`, linhas 36–49 e 127–134; `runtime/FullSession.gd`, `_process`, linhas 680–708; `runtime/cold/HeatPresentation.gd`, `update_sources`, linhas 7–13.
3. **Evidência e caminho de chamada:** a cada 0,1 s e quando a pé, `Driving._process()` chama `can_enter()`, que pede `get_nodes_in_group("drivable")`; no mesmo intervalo, `FullSession._process()` pede `get_nodes_in_group("native_world_rewards")` no exterior. `ColdSurvival` chama `HeatPresentation.update_sources()` continuamente e, a cada 0,25 s, a função pede `native_heat_source` antes de testar `enabled`; portanto a consulta também ocorre fora da montanha quando o adaptador está instalado.
4. **Classificação:** **defeito por leitura** para a consulta térmica quando `enabled == false`; **risco** para o custo cumulativo das demais consultas. Nenhuma regressão foi medida.
5. **Correção sugerida, sem aplicar:** retornar antes da consulta quando a apresentação térmica está desabilitada; manter registries fracos/eventos de entrada e saída para veículos, recompensas e fontes, ou reduzir polling apenas se medição justificar, sem atrasar prompts/interações.
6. **Validação necessária:** instrumentar número de membros consultados e tempo por sistema em Harbor e montanha, com população/tráfego configurados e durante streaming. Comparar resposta do prompt de veículo, coleta de recompensa e criação/remoção de fontes térmicas, junto das métricas de frame time.

## Limites verificados e falsos positivos evitados

- Não foi demonstrada quantidade ilimitada nos pools centrais inspecionados: população é limitada a 96 (`runtime/ProductionWorld.gd:111,271–277`), tráfego ambiente só nasce quando `vehicles.size() < 9` (`runtime/ProductionWorld.gd:300`), incêndios têm teto 12 e incidentes teto 24 (`gameplay/emergency/EmergencyManager.gd:6,48,63`), e efeitos de cápsula/mancha usam anéis de 16/12 (`gameplay/CombatEffects.gd:16–17`). Esses limites não equivalem a aprovação de custo.
- O streaming descarrega chunks fora do raio configurado (`world/regions/NativeRegion.gd:156–164`) e recursos visuais compartilhados de pinheiros/dressing possuem caches estáticos. Não foi encontrado, nesta passagem, vazamento demonstrável de chunks ou de recursos compartilhados; o risco registrado é reconstrução/custo de pico.
- Chamadas internas de despacho e ultrapassagem ficaram fora do escopo. Só foi lido o ponto externo que equipa a viatura para confirmar o chamador de `VehicleEquipment`.
- Relatórios e medições existentes foram usados apenas para localizar ferramentas/cenários. Nenhum resultado anterior foi tratado como prova do estado atual.

## Plano de medição posterior

Quando uma equipe aplicar correção, capturar baseline e comparativo na mesma máquina/GPU, Godot/renderer, 1280×720, qualidade, câmera, rota, horário, clima, população, tráfego, estado de save, VSync e limite. Usar cena real renderizada; headless pode validar contratos, não FPS/GPU.

Para regime estável, usar janela finita de pelo menos 30 s por cenário e guardar intervalos reais entre frames, FPS médio calculado, p50/p95/p99, máximo e contagens acima de 33,3/66,7 ms. Separar aquecimento/cache e primeira visita; para transições/chunks, registrar também a janela curta do evento e o tempo de bloqueio. Medir CPU, física, GPU e espera quando disponíveis. Sem orçamento acordado, aumento acima de 5% em p95/p99 serve somente como sinal para repetir amostra equivalente, não como reprovação automática.

Cenários mínimos:

1. Harbor, a pé e dirigindo, cruzando células do centro até South Port/contêineres/navio, com população e tráfego de produção.
2. Harbor → montanha, primeira viagem e retorno, depois rota por floresta, serraria, vila, lago/caverna e neve com clima/frio ativos.
3. Primeira e segunda entrada nos interiores pesados listados no achado 3.
4. Direção contínua, troca de famílias de veículo e cenário com viaturas/sirenes para isolar os achados 4–6.

## Lacunas e não executado

- Nenhuma compilação ou verificação de tipagem foi feita; esta revisão não declara o projeto compilando.
- Nenhum teste, Godot, benchmark, profiler, importação, captura ou validação visual/física foi executado.
- Não foram gerados `.import`/`.uid`, nem lidos saves pessoais, credenciais ou dados externos.
- Não foi feito perfil de driver/GPU, contagem runtime de nós/corpos/memória, nem confirmação de cache efetivo do `ResourceLoader` no pacote exportado.
- Como o repositório está sob alterações concorrentes, os trechos citados foram relidos imediatamente antes da consolidação; mudanças posteriores exigem nova conferência dirigida.
