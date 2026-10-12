# Harbor — investigação de performance, 09/10/2026

Relato: 30–40 FPS e frametime irregular mesmo parado ou andando a pé. Três agentes revisaram CPU/NPCs, renderização e streaming. Esta rodada corrigiu trabalho redundante; **a recuperação do FPS ainda não está comprovada**.

## Estado atual — prevalece sobre o histórico abaixo

- Círculo/transparência exterior removido a pedido do usuário; silhueta de Dante preservada e com contraste reforçado. Fachadas de MarketHall corrigidas separando paredes coplanares do interior/exterior. Contratos e evidência temporal descritos adiante.
- Permanecem os caches de catálogo, materiais, geometria imutável das marcas, projeção de rotas e as correções de admissão do táxi/contato com o chão já validadas. O experimento posterior de atualizar somente cores das marcas foi retirado: testes funcionais passaram, ganho de FPS não foi comprovado.
- As fontes runtime registradas são **idênticas** entre `tire-upload-before-focused-agreed` (113,03 FPS) e `original-confirmation-user-ready` (51,90 FPS). Na comparação intermediária, apenas `VehicleTireEffects.gd` diferiu. A cena tem trânsito vivo, cuja composição varia; os registros não cobrem hashes de todos os assets.
- Na confirmação de 51,90 FPS, com apresentação nativa válida, a CPU externa ocupou em média **54,26% da máquina** durante 28,11 s observados; Godot, aproximadamente 1,17 núcleo dos 20 lógicos. O consumo externo foi medido com contadores nativos por PID, sem enumeração de processos por amostra. Isso impede atribuir a diferença de FPS exclusivamente ao código.
- O usuário informou que precisa manter essas tarefas externas. A investigação passa a tratar essa carga como condição existente, sem fechar aplicativos ou alterar ventilação, controles térmicos e acesso remoto. **Estabilidade de 60 FPS sem picos continua não aprovada.**

As seções seguintes preservam o histórico, incluindo hipóteses abandonadas e medições invalidadas; não são todas descrições da configuração final.

## Evidência e causas

- **Jessica / catálogo de lugares — desperdício demonstrado.** O contato consulta a posição do banco periodicamente, mesmo antes de ser liberado. Cada consulta reconstruía todas as definições de lugares, incluindo mapas distantes. No profiler da cena Main: 108 chamadas a `PlaceCatalog.get_definition`, 614 ms acumulados em 30 s. Isso não demonstra que seja a causa única dos 30–40 FPS.
- **Transparência de fachadas — candidato recente, impacto global inconclusivo.** `ExteriorReveal` foi introduzido em 08/10 e o relatório anterior deixou performance pendente. Reenviava quatro uniforms por material e intensidade por geometria a cada frame, mesmo estabilizados; também sincronizava valores de origem inalterados. O profiler deste ponto atribuiu 201 ms acumulados ao update em 427 frames. Não foi dominante em CPU nesse ponto; o custo GPU dos materiais transparentes/prepass perto de outras fachadas continua sem A/B isolado.
- **Equipamentos dos veículos — redundância anterior, corrigida.** Emissão das lentes era reescrita a cada frame, e áudio já parado recebia `stop()` repetidamente. Não atribuímos a origem da regressão recente a esse código.
- **Streaming de regiões — sem culpado global demonstrado.** Parque, pesca e conteúdo do deserto possuem gates de distância/região. Não alteramos sua política, população, colisões ou retenção de chão.
- **Trânsito/pneus — próximos alvos de perfil.** A simulação de veículos domina parte do perfil instrumentado; `_hit_people` varre pessoas por veículo e os rastros dos pneus recompõem geometria periodicamente. Não alterados: broadphase e geometria exigem validação própria antes de justificar o risco.

## Alterações

1. `runtime/JessicaRuntime.gd`: cache local da definição do banco; invalida ao mudar a linha do banco no documento do editor, inclusive mutação interna e remoção do override. Estacionamento e alvo da missão aceitam a mesma definição atualizada. Não escreve o documento nem saves.
2. `scripts/camera/ExteriorReveal.gd`: comparação exata antes de enviar uniforms e intensidade; mantém consultas físicas, animação dos materiais de origem, seleção de fachadas, fades e shader. Geometria recém-carregada recebe todos os parâmetros. Contadores de uploads no snapshot permitem observar trabalho evitado.
3. `gameplay/VehicleEquipment.gd`: atualiza emissão quando acendimento/dano mudam; interrompe áudio apenas quando estiver tocando. Feixes, intensidade, sombras, orçamento e transições permanecem iguais.
4. `tests/measure/measure_harbor_idle_regression.gd`: reutiliza o medidor de produção com `--market`, `--walk` e ablação diagnóstica `--reveal-off`; registra estado do efeito, movimento real e PID. Não certifica exclusividade de hardware sozinho.

## Validação executada

Godot 4.7.2 .NET, build `Harbor.csproj` aprovado sem warnings/erros, caminho C# nativo confirmado no ensaio Main. GPU RTX 4060 Laptop, Vulkan Mobile. Meta provisória: 60 FPS / 16,67 ms; aumento >5% de p95/p99 exigiria confirmação equivalente, sem alterar tolerância após os resultados.

| Verificação | Resultado |
| --- | --- |
| `test_exterior_reveal.gd` | 27 checks, zero falhas; inicialização, estado estável sem uploads redundantes, streaming, materiais animados, restauração e objetos não marcados |
| `test_traffic_headlights.gd` | 50 checks, zero falhas; inclui dano unilateral, energia e reparo sem mudança de horário |
| `test_vehicle_equipment.gd` | 41 checks, zero falhas |
| `test_jessica_car.gd` | 31 checks, zero falhas; inclui âncoras e invalidação do banco |
| `test_camera_rig.gd` | PASS |
| Novo medidor, `--check-only` | sem erros de parser |
| Diff dos arquivos alterados | sem erros de whitespace |

Teste de CPU com 200 consultas intercaladas equivalentes, após aquecer ambos os caminhos:

| Consulta | p50 | p95 | máximo |
| --- | ---: | ---: | ---: |
| Catálogo inteiro, caminho anterior | 14,424 ms | 27,089 ms | 43,999 ms |
| Cache do banco com verificação de invalidação | 0,221 ms | 0,612 ms | 3,159 ms |

A mediana desta operação caiu aproximadamente 65×. É um microbenchmark headless de CPU sob carga externa, **não** um comparativo de FPS/GPU. As 200 consultas retornaram a mesma posição nos dois caminhos. Evidência: `evidence/harbor-regression-20261009/bank-lookup.json` e `measure_bank_lookup.gd`.

## Limites das medições renderizadas

O primeiro benchmark foi interrompido ao detectar um teste de katana de outra conversa. Durante o profiler, outra conversa iniciou um benchmark de circulação residencial. O usuário informou que não podia pausar as outras sessões e pediu para continuar a análise. Os processos alheios foram preservados.

O profiler completou 427 frames em 30 s; sua amostra perdeu foco e competiu por recursos. Registrou 14,23 FPS, p50 53,84 ms, p95 151,97 ms, p99 170,04 ms, máximo 208,49 ms, 325 frames >33,3 ms e 171 >66,7 ms. **Esses valores são inválidos como baseline ou resultado do jogo.** O profiler adiciona overhead e seu ranking serve apenas ao diagnóstico. A exportação de funções está em `profile-before.json`; o resumo de frame/render/estado está em `profile-before.log`. `concurrent-processes.json` registra a concorrência.

Uma tentativa posterior pelo wrapper exclusivo recusou iniciar porque havia outro processo Godot de teste ativo. Não repetimos até obter um número conveniente. Mudanças simultâneas em `Actor.gd`, `CameraRig.gd`, `Gameplay.gd` e outros arquivos também impedem tratar um ensaio posterior como A/B apenas destes patches sem congelar a revisão.

## Pendências e sequência proposta

1. Reservar uma janela sem outros testes e congelar os arquivos relevantes. O wrapper `evidence/harbor-regression-20261009/run-measure.ps1` recusa concorrência inicial e interrompe somente sua própria instância se detectar uma nova.
2. Medir parado e caminhada, ponto inicial e fachada MarketHall, pelo menos 30 s após aquecimento, com mesmos settings/carga/horário. Registrar resolução, VSync, limitador, câmera, população, CPU/GPU, p50/p95/p99/máximo e frames lentos. O medidor herda esses dados do runner existente; não houve comparação antes/depois válida nesta rodada.
3. Executar `--reveal-off` apenas para atribuir custo. Se o efeito dominar GPU, investigar a área/lotes enviados ao caminho transparente, preservando a janela visual de Dante. Não remover o efeito nem baixar qualidade global para aprovar.
4. Completar evidência temporal renderizada de fachadas e faróis em movimento/noite; os contratos headless aprovados não certificam ausência de flickering. Nenhuma certificação visual global ou de performance é feita aqui.

Estado da primeira rodada: **contratos locais aprovados; redução de trabalho CPU demonstrada; FPS, frametime integrado e apresentação temporal pendentes**. Alterações concorrentes e saves pessoais preservados; sem commits desta rodada.

## Continuação com Godot exclusivo

O usuário liberou uma janela sem outras instâncias do motor. O wrapper passou a guardar exit code e rejeitar execuções sem relatório, além de registrar processos. O build .NET continuou aprovado. Não se reutilizam números da rodada concorrente como baseline.

`isolated-idle-boundaries` registrou 29,281 s de CPU efetiva na thread principal em 30,067 s de parede (97,4%). Callbacks físicos ocuparam 20,016 s em 1.742 passos; todos os oito maiores intervalos executaram oito passos físicos. A hipótese principal passou a ser custo contínuo de CPU mais acúmulo de passos, sem atribuir o residual exclusivamente ao solver. A câmera desse runner era preview=true.

`isolated-idle-stage` usou câmera padrão (preview=false), coletor agregado opcional e nenhum profiler de script/eventos detalhados. Em 29,974 s / 1.488 passos: `vehicle.physics` 11,211 s; `actor.physics` 6,376 s; `actor.move_and_slide` 3,776 s; `vehicle.drive` 2,948 s; `vehicle.effects` 2,644 s, incluindo pneus 1,958 s. Os tempos são inclusivos: não somar pais e filhos. Houve 635.145 chamadas ao coletor; FPS dessa captura não é aprovação nem comparação limpa com câmera diferente.

Correções adicionais em avaliação:

- Marcas de pneus armazenam seus cantos imutáveis, preservando normais, geometria, envelhecimento e limites.
- Atropelamento lê origem e comprimento do veículo uma vez por consulta.
- Atores apoiados usam velocidade vertical zero com o floor snap existente, evitando empurrar continuamente a cápsula contra o chão. Gravidade continua ativa ao perder apoio. Nas rampas, remover a força descendente também altera o deslocamento tangencial; não se afirma equivalência exata de velocidade ao comportamento anterior.
- Aproximação do cruzamento deixa de consultar `stop_line` quando a distância já vem do `stop_offset` autorado. Sensores e decisões continuam ativos.

Validação adicional: pneus 63 checks; efeitos 40; impactos pesados 72; coletores independentes sem falhas; locomoção do Actor 13; comparação física de apoio 32; aproximação de cruzamento 5. O primeiro probe de apoio tinha uma expectativa inadequada de deslocamento horizontal na rampa: o próprio baseline falhou apesar de permanecer apoiado. O contrato foi corrigido para exigir subida e apoio, registrando separadamente os endpoints das duas variantes. Os logs originais foram preservados.

O censo read-only `isolated-grounded-zero-idle-support-census.json`, realizado antes do aquecimento, encontrou superfícies quase coplanares em 47/103 origens, sem truncamento. Dante tinha Land, HarborRoad Solid e CoastalWalkSupport no nível zero. Isso identifica candidatos, não mede custo de contatos. Nenhuma dessas colisões foi removida.

A primeira medição limpa candidata, `isolated-grounded-zero-idle`, registrou 84,52 FPS, p95 18,104 ms, p99 28,386 ms, máximo 68,715 ms, 7/2.537 intervalos acima de 33,3 ms. Perdeu foco nos últimos 10 frames e foi corretamente marcada **inválida para aprovação**.

### Comparação renderizada válida e picos residuais

| Execução | s | câmera | teto passos | FPS | p95 / p99 ms | máximo ms | >33,3 / >66,7 |
| --- | ---: | --- | ---: | ---: | --- | ---: | --- |
| `isolated-grounded-minus-one-clean` | 30 | padrão | 8 | 9,69 | 194,411 / 211,107 | 228,505 | 243 / 198 |
| `isolated-grounded-zero-clean` | 60 | padrão | 8 | 69,00 | 32,655 / 60,224 | 154,932 | 194 / 32 |
| `launcher3-preview-idle` | 60 | diagonal | 3 | 92,20 | 28,315 / 52,714 | 95,310 | 176 / 16 |

Todas essas três execuções mantiveram foco. As duas primeiras usaram o mesmo enquadramento, resolução 1920×1080, MSAA=2 (4×), VSync=1, limitador 144, 60 Hz físicos e logger desligado. O movimento antigo foi recolocado manualmente apenas durante sua execução e a correção zero foi restaurada em seguida. População/tráfego continuaram vivos e não determinísticos: houve variação natural de unidades de despacho e de densidade. Isso demonstra melhora integrada, mas não uma razão de ganho universal isolada de toda variação da simulação.

A terceira inclui cache da projeção geométrica de carros parados, câmera diagonal e o logger/limite de três passos já usados pelo `JogarCSharp.cmd`; não deve ser tratada como A/B exclusivo desse cache ou desse teto. O projeto/editor ainda usa oito passos por padrão. Não alteramos frequência física nem preferências persistidas. A população atingiu 40 e os veículos 49 nessa execução. O wrapper ampliado confirmou os hashes dos arquivos relevantes antes/depois.

O contrato de apoio foi ampliado para 42 checks, incluindo descida a 28,44 m/s e transporte/remoção de plataforma `AnimatableBody3D`. Passaram também katana/RAGE (35), cache da projeção de rota (19), faixa de parada (5) e desobstrução do tráfego. O cache invalida por posição exata, mudança de curva e edição interna da curva, sem cachear sensores ou decisões de cruzamento.

`isolated-grounded-zero-route` percorreu ida/volta, combate e recuperação, mas perdeu foco a partir de 77,482 s. Seus números gerais **não aprovam FPS**. A análise separada dos intervalos focados identificou dois mecanismos: um pico de 157,83 ms incluiu 98,989 ms entre desenho e primeira física com CPU contabilizada zero, seguidos de sete passos físicos; outros picos de 72,34/68,83 ms incluíram 48–49 ms em callbacks físicos. Não atribuímos a espera a SDL, driver ou sistema sem stack nativa correspondente.

Há investigação anterior em `sdl-input-stalls-20261005.md` com assinatura semelhante e stacks nativas, mas nenhuma mitigação aprovada. Esta sessão não está elevada para capturar ETW de kernel. Não desligamos DirectInput nem removemos suporte a controles.

Outra fonte concreta de trabalho repetido foi localizada: `TaxiRank` tentava criar um táxi em vaga ocupada a cada 0,5 s, construindo e descartando 126 nós. O logger registra tentativas de 8–11 ms junto de picos, inclusive na rodada focada com três passos. A pré-checagem física agora usa o mesmo volume, orientação, máscara e exceção de rampa da admissão real, antes de construir o veículo. Mantém a tentativa a cada 0,5 s e a checagem autoritativa final; não remove táxis nem muda a vaga. `test_taxi_rank_admission.gd` passou 13 verificações, incluindo camadas, obstáculo rotacionado, exceção da rampa, vaga liberada e hull real.

`launcher3-preview-taxi-precheck` perdeu foco e não aprova nem reprova FPS. A execução seguinte, `launcher3-preview-taxi-focused`, manteve foco e hashes estáveis durante 60 s: 66,09 FPS, p95 44,884 ms, p99 61,879 ms, máximo 91,831 ms, 284 intervalos >33,3 ms e 24 >66,7 ms. No log `stalls-20261009-132008.log`, recorte t=98,629849–158,639602, desapareceram os ciclos de 126 nós e as tentativas repetidas de spawn. Isso comprova a eliminação daquele trabalho, **não uma melhora adicional de FPS**: a rodada teve lentidão sustentada em aproximadamente 10–25 s, ainda sem causa exclusiva atribuída. Um `vehicle.street_pre` de ambulância levou 54,458 ms; a etapa precisa de divisão mais precisa. O pico de exportação após a janela foi excluído.

Foi preparado o coletor `capture_owned_wait_points.py`, que verifica imagem, PID pai, nascimento e TID da própria instância, coleta no máximo 12 contextos quando os ciclos da main ficam parados por pelo menos 20 ms e retoma a thread antes do unwind offline. Não requer elevação nem altera dispositivos. O preflight em filho sintético próprio passou 13 checks e retomou todas as oito capturas, com máximo de 0,3822 ms entre solicitação e retomada. Capturas desse coletor serão diagnóstico perturbativo, nunca benchmark limpo.

**Estabilidade sem picos ainda não aprovada.**

### Caminhada noturna e coleta nativa

`launcher3-market-walk-night`: 60,034 s com foco e fontes preservados, 46,27 FPS, p95 55,685 ms, p99 74,379 ms, máximo 159,335 ms; 435 intervalos >33,3 ms e 53 >66,7 ms. O jogador percorreu fisicamente 107,73 m incluindo aquecimento, com 41 inversões; tempo do mundo terminou em 0,8268. Os bins de dez segundos foram 71,57 / 74,99 / 41,42 / 44,79 / 23,04 / 21,85 FPS. Não houve estabilidade noturna. GPU p95 9,10 ms/máximo 20,68 ms e CPU de render p95 2,63 ms/máximo 4,99 ms não explicam sozinhos os intervalos de 55–159 ms. Reveal manteve seis geometrias/quatro materiais, sem novas escritas por instância. 672/721 registros lentos não alteraram nós, todos estavam sem build jobs; memória ficou entre 1.074 e 1.078 MB. Esses dados não sustentam vazamento ou streaming contínuo como causa dominante.

`launcher3-native-route` completou ida/volta/combate/recuperação com foco válido e hashes preservados de 1.073 fontes de runtime (além dos runners). É uma captura diagnóstica com observadores. No retorno: 31,34 FPS, p95 68,188 ms, p99 83,468 ms, máximo 97,865 ms. A main consumiu 28,891 s de CPU em 29,993 s (96,33%); callbacks físicos ocuparam 18,298 s em 1.647 passos. O sampler fez 21.896 consultas em 124,189 s, sem encontrar episódio qualificável de ciclos parados por pelo menos 20 ms e sem suspender a thread. Consumiu 2,031 s de CPU própria. Isso não refuta esperas em outras execuções; a espera longa anterior não se reproduziu.

O maior intervalo entre desenho e primeira física dessa rota foi 61,933 ms, mas com CPU ativa (62,5 ms na granularidade do contador), junto de 138 nós novos perto de `(172, 23)`. Trata-se de outro mecanismo, cuja origem ainda está sendo rastreada. Os novos spans de `street.pre.*` não excederam individualmente 5 ms. O próximo diagnóstico usa somas por etapa em bins de cinco segundos e contadores nativos de CPU, para atribuir o custo acumulado sem interpretar ausência de span lento como ausência de custo.

### Etapas agregadas, perfil de funções e alfândega

`launcher3-night-stage-cpu` manteve foco durante 60 s e coletou 55 etapas sem perdas, com 3.587 passos físicos na janela agregada. Tempos inclusivos: veículo 11,762 s; ator 5,029 s; direção de veículo 3,320 s; efeitos 2,531 s; movimento do ator 1,711 s; pré-interações de veículo 1,585 s; movimento do veículo 1,500 s; degrau de ator 1,357 s; pose do ator 0,714 s. A main consumiu 95–99% dos bins de cinco segundos. A execução diagnóstica registrou 76,72 FPS e máximo 72,231 ms; terminou com apenas quatro carros em movimento, portanto não serve como A/B do caso anterior com 12 carros em movimento. Não aprovamos estabilidade por essa média.

`launcher3-night-profile` coletou 1.140 frames de profiler sem erros de protocolo, mas perdeu foco e não aprova FPS. Seu ranking identifica custos, não uma comparação limpa: callbacks físicos somaram 14,76 s e de process 4,17 s em 30 s de captura. `can_rotate` custou 145 ms e a projeção de rota 129 ms no total; não se implementou a proposta de evitar giro idêntico como se isso resolvesse o déficit. Nova captura combina limites completos, etapas e amostragem nativa na mesma janela de retorno para atribuir o resíduo corretamente.

Os 138 nós foram identificados como `harbor_customs_house`, pelo descarregamento explícito e pela sequência de quatro passos aguardada pelo preparo. A coroutine retoma no sinal `physics_frame`, antes dos observadores dos callbacks, razão pela qual sua construção apareceu no intervalo ainda não atribuído. `HarborBuildingRuntime.prepare_room` consultava duas vezes o catálogo global, recompondo lugares de todos os mapas. Agora usa `HarborBuildingCatalog.find` e instancia a mesma classe com a mesma definição. O desenho, sólidos, acesso, waits e fluxo de recuperação permanecem iguais. Há spans próprios para lookup, instanciação e `add_child/_ready`. A equivalência passou 79 verificações em `test_harbor_building_preparation_lookup.gd`.

A primeira tentativa do teste de recuperação não chegou a executar assertions: o boot aguardava indefinidamente `startup_streaming_settled`, flag que só é atribuída uma vez e permanece falsa quando o orçamento inicial acaba. Ao solicitar encerramento após cerca de 305 s, o processo já havia terminado pelo próprio timeout (exit 3, zero assertions); nenhum processo alheio foi encerrado. O helper de teste foi corrigido para aceitar oito frames consecutivos de filas realmente ociosas após ready, com limite de 180 s de relógio. Isso não altera nem ignora filas do runtime. A execução corrigida, renderizada no launcher com três passos, passou 65 verificações de admissão, mudança de andar, morte durante transição/preparação, recuperação, saída e reentrada (`test_harbor_building_recovery-ready.log`).


### Atribuição da criação e amostragem nativa

`launcher3-return-native-cpu` não aprova FPS: perdeu foco fora e dentro da volta. O recorte focado da volta cobre 30,015–44,753 s (1.057 intervalos); o restante perdeu foco. A captura nativa periódica coletou 118 pontos com retomada confirmada, sem erro de decode e suspensão máxima de 1,0637 ms. Dos 58 pontos focados, 53 estavam no executável Godot, dois no driver NVIDIA e três em bibliotecas de sistema. O endereço do módulo e RVA são evidência; nomes de exportações próximas não identificam a função executada. Não apareceu espera dominante no driver. A instrumentação é perturbativa e não equivale a benchmark limpo.

Na mesma execução, a preparação da alfândega acrescentou 138 nós e levou 53,657 ms em `add_child/_ready`, dentro de um intervalo de 54,089 ms antes dos callbacks físicos. Lookup levou 0,325 ms e instanciação 0,025 ms. Isso localiza o custo residual na construção síncrona do interior, após a correção do catálogo.

O microdiagnóstico renderizado `customs-construction-before.json` separou duas construções no mesmo processo. Primeira: 131,215 ms totais, 51,296 ms de carga do script/modelo, 66,453 ms ao adicionar o modelo e 12,067 ms nas recompensas. Segunda: 15,351 ms totais, 0,013 ms de carga, 2,390 ms ao adicionar e 11,976 ms nas recompensas. Pixels das quatro texturas somaram 3,452 ms e upload/mipmaps 0,243 ms. Esse cenário isolado identifica custos de primeira utilização; seus 131 ms não são uma medição de frame time da cena Main.

Foi criada uma cópia independente para comparar o backend físico, sem alterar o backend do projeto original. SHA256 confirmou os 17.112 arquivos copiados (3.196.142.566 bytes), sem links físicos ou simbólicos. A cópia começa em GodotPhysics3D, igual ao original; qualquer variante Jolt será diagnóstico isolado antes de considerar adoção.


### Correção do critério de janela e experimento de backend

**Ressalva descoberta às 14:16, que prevalece sobre referências anteriores a rodadas válidas:** `DisplayServer.window_is_focused()` retornou true em algumas rodadas cujo `window_mode` era 1. O enum da própria GodotSharp 4.7.2 confirma que 1 é `Minimized`. Não havia verificação nativa de `IsIconic/IsWindowVisible/GetForegroundWindow`; portanto, foco sozinho não basta para aprovar essas medições como apresentação normal. Os dados de trabalho/CPU continuam diagnósticos, mas as comparações anteriores marcadas apenas por foco não certificam FPS. O runner agora restaura uma janela minimizada uma única vez antes do aquecimento; o wrapper registra também estado nativo das janelas do seu próprio processo.

Na cópia isolada, `snapshot-godotphysics-night` registrou 47,86 FPS, p95 50,490 ms, p99 70,075 ms, máximo 91,975 ms, porém modo 1. `snapshot-jolt-night-isolated` registrou 48,30 FPS, p95 50,391 ms, p99 66,807 ms, máximo 78,842 ms, em modo 0. Ambas mantiveram o foco informado pelo motor, mas a diferença de modo impede um A/B estrito. Jolt também não atingiu estabilidade na amostra; não há evidência suficiente para adotá-lo e o projeto original continua GodotPhysics3D. A primeira tentativa Jolt foi interrompida aos 67 s pela detecção de um Godot externo sem argumentos, antes da medição; nenhum processo externo foi encerrado.

`customs-construction-preload.json` confirma recurso do modelo previamente retido nas duas visitas e custo de carga desprezível. Não eliminou todo o custo inicial: primeira construção 111,172 ms, shell 62,758 ms e decoração 30,309 ms; segunda 15,291 ms. O novo detalhamento atribuiu 12,697/10,407 ms à vinculação da malha TorusMesh do halo de recompensa. Material e criação do objeto de recurso ficaram abaixo de 0,2 ms; a geração da geometria ocorre na vinculação. Isso justifica compartilhar somente a malha imutável, preservando materiais individuais.


### Materiais, rastros e nova direção visual solicitada

O cache de TorusMesh passou os contratos funcionais, mas **não reduziu o pico**: `customs-construction-halo-cache.json` manteve 12,175/13,978 ms no trecho de vinculação. A divisão seguinte (`customs-construction-bind-stages.json`) mediu apenas 0,084/0,006 ms na malha e 21,861/16,363 ms em `material_override`. O cache de malha foi desfeito manualmente. A hipótese atual é recriação da variante de BaseMaterial ao liberar seu último usuário entre visitas; o código da versão exata do motor possui esse ciclo de vida. Um diagnóstico de retenção apenas do material foi preparado, ainda sem concluir ganho integrado. O preload do script permanece; não se atribui todo o pico de construção ao carregamento do script.

A guarda de consultas de objetos abaixo de `FRAGILE.WOBBLE_SPEED` passou 80 verificações de impactos. O bloco inteiro tinha teto medido de 374,9 ms em 30 s; a economia real é uma fração, sem alegação de resolver a saturação.

`window-verified-trace-abba` terminou quatro segmentos, mas perdeu foco e minimizou. A validação por frame e o observador nativo do Windows reprovaram a rodada. Segmentos ON/OFF/OFF/ON tiveram 27,76/47,82/43,76/88,56 FPS, com apenas 200/0/21/0 intervalos focados respectivamente. Não se usa essa série para atribuir ganho à desativação dos rastros; a melhora também apareceu no último segmento ON. Nenhum launcher foi alterado para desligar diagnóstico.

Às 14:24 o usuário pediu explicitamente remover o círculo transparente do cenário e conservar somente a silhueta do personagem. Isso altera a intenção visual autorizada: a próxima mudança desativa ExteriorReveal no produto, preservando CityLook/occluded_silhouette e os recortes autorais de túneis/interiores. A avaliação do ganho ocorrerá no Main renderizado, com o novo controle de janela.

### Círculo removido e primeira medição com apresentação verificada

ExteriorReveal passou a iniciar desligado. CameraRig evita suas chamadas por frame; desativar restaura imediatamente os materiais. O diagnóstico só o reativa com pedido explícito. `test_exterior_reveal.gd` passou 33 verificações e `test_video_interior_silhouette.gd` passou 32, incluindo profundidade interior e transições a pé/veículo. Túneis e recortes autorais foram preservados.

A primeira captura sem círculo revelou um segundo problema: a silhueta clara antiga quase desaparecia sobre o telhado iluminado. No diagnóstico `silhouette-roof-branches`, magenta opaco com os mesmos filtros de profundidade tornou Dante claramente visível. A variante branca continuou pouco legível. Isso demonstra contraste insuficiente naquele enquadramento; não justificou remover filtros de profundidade. O shader recebeu um ramo somente para Dante a pé, com corpo escuro e borda clara, preservando a saída anterior dos veículos e todos os descartes por profundidade.

O wrapper passou de `Start-Process -WindowStyle Hidden` para `-NoNewWindow`, mantendo o console no processo chamador sem transmitir ocultação ao jogo interativo. A rodada `silhouette-only-readable-walk` completou 30,018 s sem minimizar nem perder foco. O verificador nativo classificou todas as 13 observações dentro da janela como `observed_valid`, com intervalo máximo de 2,621 s; a observação é amostral, complementada pelas guardas por frame do motor. Não houve outra instância detectada nem mudança das fontes durante a execução. O roteador C# estava ativo.

Resultado: **65,19 FPS; p50 13,819 ms; p95 35,814 ms; p99 55,388 ms; máximo 84,332 ms; 122/1.957 intervalos acima de 33,3 ms e três acima de 66,7 ms**. GPU média 3,688 ms/p95 4,796 ms; CPU de render média 1,447 ms/p95 2,068 ms. ExteriorReveal permaneceu desligado, com zero geometrias, materiais, consultas e escritas. População/tráfego naturais de 38; câmera diagonal, Vulkan Mobile, 1920×1080, MSAA 4×, VSync e limite físico do launcher preservados. A captura confirma o telhado opaco sem círculo; o contraste da silhueta ainda requer reforço.

O A/B anterior `circle-vs-silhouette-window-verified` (72,85 FPS com círculo / 104,46 sem) foi **reprovado por janela minimizada** e não comprova ganho de FPS. A rodada válida atual comprova que os picos persistem mesmo sem o círculo. Não se atribui toda a regressão a esse efeito e **a meta de estabilidade continua reprovada**. Evidências em `evidence/harbor-regression-20261009/silhouette-only-readable-walk*` e `evidence/stall-logs/stalls-20261009-144406.log`.

O reforço final estreitou a borda clara e aumentou a opacidade somente da silhueta a pé. `circle-off-final-presented-ab.png` mostra Dante legível sobre o telhado, sem círculo. O A/B dessa execução também não aprova ganho: permaneceu em modo de janela normal, mas perdeu foco em ambas as fases (ON: 1.479 intervalos focados/784 sem foco; OFF: 252/2.400). Resultados diagnósticos de 75,41/88,39 FPS não são comparação aprovada. Ao observar essa execução, o usuário relatou piscadas nas laterais do prédio; a estabilidade visual ficou explicitamente pendente e a investigação passou a captura temporal com ExteriorReveal desligado desde o início. A sequência com o círculo temporariamente ligado não permite atribuir o defeito à configuração final.

### Piscada nas fachadas: sobreposição com o interior preparado

O prédio observado é MarketHall/Breakwater, centro `(109.375,41.5625)`, footprint 30 × 13,75 m e rotação de 180°. Dante caminha a aproximadamente 0,9–1,75 m da entrada, dentro da zona que prepara o interior. O interior permanece visível, enquanto o adaptador externo abre apenas o vão da porta. Paredes de materiais diferentes ocupavam os mesmos planos: laterais em x=94,375/124,375, y=0,12–1,22; fundo em z=48,4375, y=0,12–2,82. O percurso não cruza os limiares de preparação/descarregamento. A falha era geométrica e existia com o círculo desligado.

`market-facade-off-before-temporal.json` contém 340 quadros consecutivos durante 30 s, 114 parado/226 andando, sem falhas nem lacunas no contador de quadros desenhados. As trincas 207/208/209 (18,659–18,825 s, sul) e 252/253/254 (22,636–22,804 s, leste) mostram claro→tijolo escuro→claro. O efeito também ocorre parado. O primeiro analisador foi invalidado por confundir canvas lógico 1280×720 com framebuffer 1920×1080; a pasta `market-facade-off-before-review-v2` corrige a escala de 1,5 e contém a análise válida de todos os quadros.

`HarborBuildingInterior` agora recua somente as faces externas e extremidades em 2 cm. A espessura passa de 24 para 22 cm, com centro deslocado em 1 cm; isso mantém exatamente as faces internas e a circulação. O piso visual recua sob as paredes, mantendo altura/material e collider de suporte integral. Não se ocultou o interior nem se alteraram iluminação, texturas ou ordenação de desenho.

O teste dirigido executou 92 checks: antes, 44 falhas nas separações externas; depois, zero falhas. Cobriu footprints distintos, portas central/descentralizadas e andar superior, preservação dos planos internos e jambs, interseção dos cantos e collider real do piso. A validação renderizada de interiores passou **528 verificações em dois edifícios/quatro níveis**, incluindo cápsulas e circulação de Dante/NPC, colisão e oclusão separadas com controles positivos: `evidence/harbor-building-contract-78364-9663685`.

`market-facade-off-after-temporal.json` contém 348 quadros consecutivos, 116 parado/232 andando, sem falhas ou lacunas. Todos foram analisados; as maiores diferenças e reversões foram inspecionadas. A alternância clara/escura não reaparece. Nas faixas suspeitas, diferença média compensada por movimento ao andar caiu de 19,936 para 1,607 (sul) e de 13,811 para 1,106 (leste), cerca de 92%; **métrica de imagem, não ganho de FPS**. Comparação real: `evidence/harbor-regression-20261009/market-facade-flicker-before-after.png`; fontes e métricas: `market-facade-temporal-comparison.json`.

A evidência temporal cobre somente esse ponto, câmera e percurso. Readback/JPEG síncronos reduziram a cadência a aproximadamente 12 quadros/s; todos os quadros renderizados foram registrados, mas a gravação perturba a execução e seus FPS são explicitamente inválidos. O teste Main de entrada/saída/restauração e a medição sem captura continuam sendo critérios separados.

O walkthrough renderizado de MarketHall e Torque completou **69 checks, zero falhas**, com C# ativo, entrada pelas portas, circulação, acesso à cobertura, save isolado, restauração fria e saída com controle/câmera recuperados. Evidência: `evidence/harbor-building-walkthrough-83604-8694220`, log `wall-clearance-main-walkthrough.log`. Nenhum save pessoal foi utilizado. Os interiores restantes não foram exercitados individualmente nesta rodada.

### Diagnóstico de CPU até 15h10 e limite da aprovação

`final-silhouette-walls-trace-cpu-abba` completou quatro segmentos de 30 s com rastreamento ON/OFF/OFF/ON, sem gravar imagens por frame e com ExteriorReveal desligado o tempo todo. Duas leituras nativas da mesma main thread por segmento mediram 96,7% / 96,3% / 96,7% / 95,3% de CPU sobre tempo de parede. A contagem inclui todo trabalho da thread; não atribui isoladamente esse tempo à física. Nenhum contador falhou e as fontes permaneceram estáveis.

Os segmentos tiveram 59,86 / 75,26 / 57,56 / 94,28 FPS; p95 38,646 / 17,204 / 48,488 / 16,099 ms; máximos 69,159 / 41,049 / 121,106 / 48,442 ms. A variação não sustenta desligar o rastreamento como solução: há lentidão e melhora em ambos os estados, com população/tráfego vivos e diferentes. Não foi alterado o launcher do usuário para remover diagnóstico.

**Essa execução não aprova FPS:** apesar de o motor informar foco durante todos os frames e modo de janela 0, o observador nativo encontrou a janela visível e não minimizada, porém fora do primeiro plano em todas as 50 amostras. O verificador retornou `failed`. Isso reforça a necessidade do critério nativo, além das flags do motor; não se atribui a divergência ao usuário nem se altera a tolerância para aceitar a execução. Os números acima são diagnósticos, não um comparativo final validado.

Estado de entrega desta etapa: círculo removido e silhueta preservada/legível; interferência das fachadas corrigida no recorte temporal observado; contratos geométricos, físicos/de profundidade e fluxo Main aprovados no escopo descrito. **FPS estável sem picos permanece pendente.** A última janela com apresentação nativa aprovada, `silhouette-only-readable-walk`, ainda teve p95 35,814 ms e máximo 84,332 ms. Nenhuma destas correções autoriza afirmar que a regressão inteira foi resolvida.

### Investigação retomada: apresentação nativa e separação dos custos

O encerramento anterior foi prematuro diante do pedido de resolver os engasgos. A investigação continua com três agentes, sem reduzir população, qualidade ou física do produto. O wrapper agora exige um segundo contínuo de apresentação nativa antes do aquecimento, amostra WinAPI a aproximadamente 100 ms e revoga a execução na primeira perda observada. A tentativa normal de foco acontece uma única vez, antes da medição; nenhuma recuperação automática durante a coleta. O controle passou em 17 verificações sintéticas e identificou corretamente uma recusa de foco pelo Windows. Outra inicialização foi encerrada pela guarda do diagnóstico: faltava `HARBOR_MAX_PHYSICS_STEPS=3` no comando direto, deixando o padrão 8; essa tentativa não produziu amostras válidas.

`native-gated-market-frequency-launcher3` completou o experimento 144/30/144 de 30 segundos por trecho, restaurando o limite original. Mesma cena Main, percurso físico, C# ativo, física 60 Hz/teto 3, população 38 e tráfego vivo. Não houve mudança das fontes nem concorrência de Godot detectada. Todas as 699 observações nativas dentro da medição viram a janela correta em primeiro plano, visível e não minimizada. O verificador independente classificou a cobertura temporal como **incompleta**: maior intervalo 0,667 s, acima do critério 0,5 s. Nenhuma tolerância foi alterada para aprovar; os resultados continuam sendo diagnóstico, não certificação final de FPS.

| Trecho | FPS real | CPU principal por segundo | Física real (Hz) | p95 / p99 / máximo (ms) |
|---|---:|---:|---:|---:|
| Limite original 144 | 86,54 | 0,97 s | 60,02 | 16,60 / 18,28 / 29,47 |
| Limite diagnóstico 30 | 28,13 | 0,76 s | 58,16 | 53,98 / 76,44 / 150,25 |
| Retorno ao limite 144 | 92,66 | 0,96 s | 59,46 | 16,07 / 30,37 / 71,34 |

O limite de 30 piorou a cadência e não é solução proposta. A redução de CPU ao reduzir quadros não permite decomposição linear exata: frequência física real e tráfego móvel também variaram. Além disso, `OS_Windows::add_frame_delay` no [motor exato](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c07984/platform/windows/os_windows.cpp#L2433) inclui espera ativa no limitador; tempo de CPU principal não equivale integralmente a trabalho da simulação. A resolução mínima de timer desta máquina foi consultada, sem alteração: 1 ms.

A revisão do perfil antigo encontrou duas perdas de cobertura: limite das 256 funções enviadas e resumo final nativo não cumulativo. As chamadas nativas são recicladas por frame no motor, enquanto contadores dos scripts acumulam; portanto, subtrair o resumo de scripts do tempo de CPU para atribuir o restante ao renderizador seria incorreto. Novo receiver acumula todas as `servers:profile_frame`, separa `self` de scripts e chamadas nativas, não soma tempos inclusivos e verifica saturação, lacunas e assinaturas. O perfil completo em cena real é a próxima etapa. Um segundo diagnóstico por fronteiras nativas de execução está preparado para custos que não aparecem como MethodBind; nenhum dos dois altera o produto.

### Perfil completo e comparação das atualizações de marcas de pneus

O receiver completo (`market-native-functions-allframes.json`) capturou 1.478 frames contíguos, sem saturação do limite de 2.048 funções e sem assinaturas desconhecidas. Em 29,984 s instrumentados: 10,367 s de self em GDScript e 4,952 s em chamadas nativas. `move_and_slide` somou 2,120 s/64.057 chamadas e `test_move`, 0,531 s/33.674 chamadas. Esses tempos não cobrem todo o motor nem devem ser extrapolados para FPS sem profiler. Dez pacotes não decodificados eram `scene:click_ctrl`, fora do fluxo de perfil. A captura separada por fases perdeu primeiro plano após 10,841 s; serve apenas para diagnóstico parcial. Não identificou um único intervalo oculto dominante. TaxiRank não reincidiu: 4,832 ms inclusivos no perfil completo e nenhum `spawn_failed` no log limpo.

O observador nativo deixou de consultar CIM repetidamente para processos conhecidos. A troca do arquivo de heartbeat tornou-se atômica; leituras transitórias preservam somente o prazo original, sem renovar a tolerância de três segundos. As verificações do gate passaram 15 contratos; a próxima comparação manteve o critério independente de intervalo máximo de 0,5 s. `dotnet build Harbor.csproj --no-restore --nologo -v quiet` passou sem erros nem avisos antes das execuções.

Baseline `tire-upload-before-focused-agreed`: **113,032 FPS; p50 9,758 ms; p95 13,383 ms; p99 14,428 ms; máximo 39,900 ms; 1/3.391 intervalos >33,3 ms e zero >66,7 ms**, durante 30,000 s. Apresentação nativa `observed_valid`, fontes estáveis e nenhuma concorrência de Godot. Main real em MarketHall, caminhada física noturna, câmera diagonal, C# ativo, 1920×1080, MSAA 4×, limite 144, VSync, física 60 Hz/teto 3, população e tráfego 38. O pico aos 25,854 s não teve variação de nós, streaming ou pipelines; não há associação demonstrada com pneus. O pico de 312,86 ms em `stalls-20261009-160717.log`, t=130,08, aconteceu após a janela e não entra nessa estatística.

Foi experimentada atualização somente do buffer de cores quando uma marca apenas desvanece, conservando a geometria e recriando a superfície quando contatos são inseridos/expiram. O teste renderizado passou **79 verificações** de posições, normais, empacotamento RGBA8, fade, limite de segmentos e limpeza. A primeira execução identificou uma inferência de tipo inválida no próprio teste, corrigida explicitando `int`; a execução seguinte passou. Isso não prova ganho de FPS.

`tire-upload-after-focused` teve apresentação nativa válida, mas **72,958 FPS; p95 27,604 ms; p99 36,659 ms; máximo 52,642 ms; 42/2.189 intervalos >33,3 ms**. Essa piora impede aprovar a otimização. O código anterior foi recolocado por cópia exata, após conferir os hashes do candidato e do backup, preservando todas as alterações anteriores à experiência. Uma confirmação finita com o original e observação da carga externa determinará se houve regressão do candidato ou variação da máquina/cena. O candidato não está aprovado neste ponto.

### Confirmação do original e interferência externa medida

`original-confirmation-user-ready` completou 30,018 s com apresentação nativa `observed_valid`: **51,902 FPS; p50 17,211 ms; p95 32,925 ms; p99 54,431 ms; máximo 63,685 ms; 75/1.558 intervalos >33,3 ms; zero >66,7 ms**. Mesmas fontes runtime registradas da baseline de 113 FPS, mesmos settings e percurso. População/tráfego naturais partiram de 35 e chegaram a 36, com teto voltando a 38 quando uma unidade de despacho saiu; portanto a composição viva não foi congelada. Não se conclui que o candidato dos pneus causou a diferença anterior. Runtime e teste da experiência foram devolvidos exatamente aos seus backups anteriores, com hashes conferidos, sem descartar alterações locais preexistentes.

Um primeiro coletor que enumerava processos via PowerShell teve custo inadequado (até 775 ms/amostra); foi encerrado **antes** de começar qualquer janela válida. Seu substituto (`monitor-fixed-cpu.ps1`) consulta `GetSystemTimes` e `GetProcessTimes` somente do Godot e do próprio observador, a cada dois segundos. Na janela válida: 14 intervalos completos/28,111 s, custo máximo do corpo de observação 1,513 ms, média 0,700 ms. CPU externa média 54,256% da máquina (mínimo 44,336%, máximo 74,264%); Godot médio 117,187% de um núcleo, aproximadamente 5,86% dos 20 processadores lógicos. Não há conclusão de frequência/temperatura a partir desses contadores.

O alinhamento temporal (`original-confirmation-user-ready-cpu-window.json`) mostra um intervalo de 2,010 s com 74,264% de CPU externa, 21,90 FPS e p95 59,119 ms; com 44,336–50,775% externos, outros intervalos tiveram 67,99–69,96 FPS, p95 17,725–18,530 ms. É associação observacional, não prova de que cada pico tenha causa externa. A identificação pontual em `external-processes-before-cap60.json` encontrou PredatorSense, OneDrive, Node e serviço de acesso remoto entre os principais consumidores; processos protegidos ficaram fora dessa enumeração. Nenhum aplicativo externo foi alterado.

Duas tentativas intermediárias do original não geraram frames válidos: uma não recebeu foreground e outra perdeu foco para a captura de tela durante o aquecimento. Não entram no comparativo. A ativação do wrapper ganhou uma tentativa documentada `AppActivate(PID)` na preparação quando o pedido direto falha; o critério nativo permanece obrigatório e não há recuperação durante a medição.

O primeiro diagnóstico `market-cap60-cadence` foi encerrado antes de aplicar o limite temporário e antes da coleta: em 90 s de preparação, trânsito ficou abaixo do teto exigido. Não produziu evidência de FPS a 60 nem mudou settings salvos. Uma única confirmação finita foi iniciada sob a carga externa mantida pelo usuário. O runner combinado parado30s/caminhando30s também foi preparado e passou `--check-only` no Godot .NET; essa verificação sintática não equivale a executar as fases.

A confirmação `market-cap60-live-load-confirm` completou a preparação, mas não recebeu o primeiro plano no prazo do gate, inclusive após a tentativa normal `AppActivate`. Nenhuma amostra de FPS foi coletada. O sidecar confirma `original_max_fps=144` e `restored_max_fps=144`; não houve gravação de settings. Não foi repetido indefinidamente nem afrouxado o requisito de apresentação. As tarefas externas seguem conforme solicitado pelo usuário. A validação final conjunta parado/andando e a hipótese de cadência a 60 permanecem **não executadas com sucesso**, não aprovadas por inferência. As medições válidas já demonstram que a meta de estabilidade continua descumprida nas condições atuais.
