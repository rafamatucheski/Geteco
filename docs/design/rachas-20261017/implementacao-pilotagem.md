# Implementação de pilotagem, instrumentos e mixagem

Atualização: 18 de outubro de 2026. Este documento descreve o código implementado após a escolha do conceito 1. O [diagnóstico anterior](pilotagem.md) registra o estado observado antes das mudanças.

Escopo deste lote: [DesertDrivetrain.gd](../../../gameplay/desert_cars/DesertDrivetrain.gd), [DesertDragHUD.gd](../../../activities/desert_drag/DesertDragHUD.gd), [DesertCarAudio.gd](../../../audio/desert_cars/DesertCarAudio.gd) e o teste novo [test_drag_control_feel.gd](../../../tests/test_drag_control_feel.gd). Os hooks de sessão são integrados pelo agente principal em `DesertDrag.gd`.

## Controle do giro

Antes, o teclado alterava o pedal instantaneamente entre zero e um e atravessava a faixa ideal em cerca de 221 ms. Agora, apenas no modo de arrancada, a entrada digital tem uma transição de pedal de até 200 ms, com giro subindo a 36% e descendo a 28% da redline por segundo. Segurar o acelerador continua levando ao limite; o sistema não escolhe automaticamente o giro ótimo.

A faixa boa ocupa 38–70% da redline. O núcleo ótimo fica em 48–60%. A perda inicial de tração varia continuamente por `smoothstep`; atravessar um limiar de rótulo por poucos RPM não derruba subitamente o desempenho. O gatilho conserva seu alvo analógico proporcional.

A largada permanece automática ao terminar o semáforo. Não foi adicionada uma embreagem manual nem alterada a tecla de largada neste lote.

## Troca contínua

A solicitação de troca não altera instantaneamente RPM ou velocidade. O drivetrain registra a troca, reduz progressivamente o torque na relação atual, engata a nova relação quando a transmissão está descarregada e devolve a força enquanto o giro se ajusta.

| Resultado | Faixa | Duração da transição |
|---|---|---:|
| Troca ideal | 89–94% da redline | 180 ms |
| Boa troca | Faixa boa restante, de 85,54% a 98,5% | 210 ms |
| Antecipada | Abaixo da faixa boa | 440 ms |
| Atrasada | Acima da faixa boa | 360 ms |

O envelope usa 20% do tempo para descarregar, mantém torque zero até 55% e reacopla até o fim. Sua perda integrada teórica equivale a aproximadamente 121,5 ms de força na troca ideal, próxima dos 120 ms de corte completo anteriores. Isso orienta a preservação do ritmo, mas a equivalência competitiva é verificada pelos tempos reais da simulação, não apenas por essa conta.

O ponteiro continua lendo RPM físico diretamente. O áudio da prova também acompanha esse estado; não existe um tween separado para esconder o degrau. A pilotagem comum mantém `race_mode = false` e sua calibração anterior.

## Contratos para integração

| Interface | Uso |
|---|---|
| `drive.race_mode = true` | Ativar nos powertrains criados para a prova; padrão é `false`. |
| `drive.stage(delta, pedal, digital_input = false)` | Passar `true` somente para a entrada de teclado. Gatilho e override analógico conservam `false`. |
| `drive.shift_up()` | Retorna `TROCA IDEAL`, `BOA TROCA`, `ADIANTOU`, `ATRASOU`, `max` ou string vazia. |
| Retorno vazio de troca | Comando não aceito durante outra troca; preservar o feedback anterior e não contar nova tentativa. |
| Retorno `max` | Mostrar “Última marcha”; não emitir outro evento de troca. |
| `drive.launch_quality` | `LARGADA IDEAL`, `BOA LARGADA`, `PATINOU` ou `GIRO BAIXO`. |
| `drive.launch_score` | Medida contínua de zero a um disponível para telemetria; não altera por si só a pontuação da noite. |
| `drive.shift_torque_factor` | Fração atual de transmissão de força, de zero a um. |
| `sound.set_race_role("player")` | Motor de Dante em primeiro plano durante a prova. |
| `sound.set_race_role("rival")` | Adversário da corrida de Dante com mixagem espacial subordinada ao motor próprio. |
| `sound.set_race_role("")` | Restaurar comportamento normal no cleanup de som preexistente. |
| `hud.event_title` | Rótulo real da etapa, como “NOITE DE ACERTO · 1/3”; vazio usa “ARRANCADA · distância”. |

`BOA TROCA` e `BOA LARGADA` representam execução válida. `IDEAL` identifica o núcleo de domínio. A versão atual da pontuação da noite usa os tempos; estes rótulos não criam um bônus oculto.

## HUD do conceito 1

O estilo gratuito `classic` passa a usar meia-lua âmbar, marcha grande, velocidade e nitro juntos, faixas boa/ótima e cinco luzes progressivas. O topo reúne duelo, etapa, distância e tempo. O centro permanece livre para acompanhar os carros.

Depois da primeira captura integrada, o painel foi compactado: raio da meia-lua reduzido de 136 para 122 pixels lógicos, instrução incorporada à asa dos instrumentos e nitro contido no mesmo fundo. Em 1280×720, os instrumentos ocupam aproximadamente a região vertical 505–670; a legenda fica separada abaixo. O canvas comum preserva a disposição proporcional em 960×540.

Durante preparação, o painel básico ensina acelerar, abandonar e pausar; não convida a apertar troca enquanto essa tecla ainda é tratada como queima pela sessão. Durante corrida, a legenda de troca reaparece. Um controle apenas conectado não muda a legenda: a escolha acompanha eventos reais de entrada, começando pelo teclado.

Os nomes das teclas são desenhados literalmente. Isso evita que a tradução de uma ação chamada `SHIFT` transforme a tecla de nitro em “TROCAR” no português.

Os estilos Barras, Street, Pro e Campeão e sua propriedade continuam disponíveis. A apresentação dos estilos adquiridos foi preservada; faixas e indicações funcionais acompanham o novo estado da simulação. As luzes de antecipação também estão disponíveis no circular Street.

## Mixagem do adversário

O listener junto ao carro de Dante já existia. A correção estabelece papéis explícitos por veículo, sem elevar o barramento global nem modificar `EngineDesignVoice.gd` compartilhado.

Para o rival da prova:

- escala espacial de 3 m, em vez de 12 m, nas vozes de motor;
- ganho local de −4 dB;
- teto de −18 dB por voz de motor;
- pan e atenuação espacial preservados.

O papel do jogador força primeiro plano. O papel vazio restaura os parâmetros comuns. Os ajustes abrangem bancos novos e fallback antigo, incluindo a reinstância dos players. Pneus mantêm seu teto específico, e o motor próprio conserva sua referência de ganho.

**Configuração não equivale a aprovação auditiva.** A relação percebida depende dos bancos, carga, escapamento, instante da troca e distância. Ainda é necessário ouvir ou capturar a sequência integrada para afirmar que o rival deixa de encobrir o feedback do próprio motor.

Uma [captura real do mix](../../../evidence/open-drag-37200-7534534/race-audio.wav), feita pelo agente principal durante a prova livre, foi analisada offline com Python. O [relatório quantitativo](../../../artifacts/rachas-implementation-20261018/race-audio-analysis.json) registra 29,323 s de PCM16 estéreo a 48 kHz: pico de −8,54 dBFS, RMS combinado de −20,21 dBFS, nenhuma amostra saturada e nenhuma acima de 98% da escala. O pico com sobreamostragem 4× foi estimado em −8,54 dBFS; essa estimativa não é uma medição calibrada de true peak. Há aproximadamente 8,5 dB de folga no sinal digital capturado.

A gravação soma o barramento Master, incluindo preparação, corrida e frenagem. Ela não contém pistas separadas de Dante e rival, nem uma referência anterior, portanto não permite medir qual motor domina ou alegar melhoria perceptiva comparativa. Não houve audição subjetiva por este agente.

## Validação e evidência

As execuções de Godot/build foram serializadas pelo agente principal. Este agente realizou edição, revisão do código, verificação de whitespace e revisão de uma imagem produzida pela execução integrada; não iniciou Godot por conta própria.

A [primeira execução](../../../output/drag-control-feel-20261018.log) de `tests/test_drag_control_feel.gd` completou 129 checks, com lista de falhas vazia, mas apresentou erro de parse em uma dependência de progressão. Após corrigir essa dependência, o agente principal produziu uma [revalidação limpa](../../../output/drag-final-test_drag_control_feel.log): **129 checks, nenhuma falha, sem erro registrado**. Este resultado aprova os critérios da simulação isolada, sem substituir a corrida física na cena real.

O teste cobre:

- passagem pela faixa boa e duas pressões digitais deliberadas, em 30/60/120 Hz, sem substituir teclado por pedal analógico perfeito;
- resposta analógica estável;
- continuidade de tração nos quatro limiares de largada;
- ausência de salto de RPM/velocidade ao solicitar troca, envelope parcial de torque, comando repetido e última marcha;
- stock versus preparação e troca antecipada em 800 m;
- ritmo novo versus legado, com tolerância prévia de 5%, e ordem dos rivais autorados.

Na primeira execução, a permanência na faixa boa segurando uma tecla foi de aproximadamente **0,900 s / 0,883 s / 0,883 s**, respectivamente a 30/60/120 Hz. Isso mede tempo disponível no controle, não FPS de renderização. Os comparativos de tempo passaram e as trocas antecipadas continuaram mais lentas.

Tempos de 800 m, em segundos, reproduzidos na revalidação limpa:

| Carro | Legado stock | Novo stock | Novo preparado | Troca antecipada |
|---|---:|---:|---:|---:|
| Faísca | 23,767 | 23,775 | 18,475 | 25,317 |
| Mirage | 19,950 | 19,950 | 15,567 | 21,275 |
| Porto Rosso | 16,433 | 16,433 | 13,108 | 17,625 |

Os rivais autorados produziram 20,592 / 19,083 / 17,800 / 17,375 / 15,650 / 15,208 s, mantendo a ordem Digo, Lívia, Raul, Jéssica, Nadir e Rauhz. Os valores não incluem colisão contra a pista física.

A primeira invocação do [teste de mixers](../../../tests/test_engine_design_mixers.gd) terminou com código 2, [sem executar a suíte](../../../output/drag-final-test_engine_design_mixers.log). A inspeção do código e de SessionDiagnostics encontrou encerramento normal em aproximadamente 155 ms, um frame e nenhum `AudioWorld` ou player criado. Isso corresponde ao guard inicial: exige `--no-save` nos argumentos do usuário e bancos novos habilitados, isto é, ausência de `--legacy-engine-design`. O outro caminho de código 2 seria um timeout de 180 s acompanhado de mensagem de erro, incompatível com esse registro. Como SessionDiagnostics guarda apenas `OS.GetCmdlineArgs()`, sem os argumentos do usuário, não distingue qual pré-condição faltou. Essa invocação não é evidência de falha nem de aprovação do mixer; a execução corrigida deve usar `-- --no-save`, sem o sinalizador legado.

A [invocação corrigida](../../../output/drag-final-mixers-correct-20261018.log) completou **48 checks, nenhuma falha**. Ela valida integração dos adapters, limites de vozes, propriedade única de som por veículo, retomada e desligamento. Isso não substitui avaliação perceptiva da relação entre os dois motores durante a prova.

A [primeira captura integrada](../../../evidence/drag-night-session-2084-9558817/temporal/night_drag_staging.png) mostrou a meia-lua funcional, mas também nitro abaixo do fundo e instrução visualmente separada. Esses dois problemas motivaram o ajuste final de layout descrito acima. A imagem é anterior a esse ajuste e foi capturada com locale global em inglês; não representa o acabamento final em português.

A [captura seguinte em português](../../../evidence/drag-night-session-39512-10081883/temporal/night_drag_staging.png) confirma a asa compacta, a dica incorporada e o nitro dentro do fundo. Ela revelou a tradução indevida da tecla `SHIFT`; a correção literal foi aplicada depois dessa imagem. O acabamento final em ambas as resoluções ainda depende da captura coordenada.

A [captura final de preparação em 1280×720](../../../evidence/drag-night-session-43108-7127425/temporal/night_drag_staging.png) confirma `SHIFT` literal no nitro, texto funcional em português e o conjunto contido no painel. A geometria continua proporcional em 960×540, mas esta revisão visual não substitui uma captura específica dessa resolução.

### Defeito físico identificado na corrida integrada de 800 m

A sessão integrada seguinte terminou os 800 m do Mirage em aproximadamente 25,615 s, apesar dos 19,950 s da simulação isolada. A inspeção somente de leitura da [sequência temporal](../../../evidence/drag-night-session-39512-10081883/temporal/sequence.json) encontrou duas perdas abruptas de velocidade, com a terceira marcha mantida e sem feedback de troca:

| Instante da corrida | Posição após a perda | Velocidade aproximada no HUD | Quadros |
|---|---|---|---|
| 6,517 → 6,550 s | x = −769,923 m | 126 → 64 km/h | [02065](../../../evidence/drag-night-session-39512-10081883/temporal/02065.jpg) → [02066](../../../evidence/drag-night-session-39512-10081883/temporal/02066.jpg) |
| 10,417 → 10,450 s | x = −673,984 m | 114 → 50 km/h | [02180](../../../evidence/drag-night-session-39512-10081883/temporal/02180.jpg) → [02181](../../../evidence/drag-night-session-39512-10081883/temporal/02181.jpg) |

As perdas acontecem aproximadamente 2 m antes de duas fronteiras consecutivas de célula, separadas por 96 m. Esse é o tamanho de célula de `DesertRegion`. O código de `_move_car` copia a velocidade efetiva de `move_and_slide()` para o drivetrain quando encontra resistência física. Inicialmente isso sustentou a hipótese de contato na emenda do piso. Não houve alteração de drivetrain para mascarar essa perda.

O [probe de emendas](../../../artifacts/rachas-implementation-20261018/probe_seams.gd), executado pelo agente principal, [registrou cinco perdas nos dois carros](../../../output/drag-seam-probe-20261018.log). Os contatos identificaram arestas dos colliders `WeatheredAsphalt` e `DesertGround`, incluindo normais horizontais `[-1, 0, 0]` contra o movimento. Assim, a origem física nas fronteiras da malha ficou confirmada; o drivetrain apenas refletia a resistência recebida.

O agente principal implementou [DragTrackSupport](../../../world/desert/DragTrackSupport.gd): uma superfície física finita e contínua na reta, com recorte dos triângulos originais somente dentro dessa faixa. O asfalto visual, os obstáculos e o retorno conservam sua geometria. A [nova sessão real](../../../output/drag-night-seams-fixed-20261018.log) completou **58 checks, nenhuma falha**, quatro passadas e nenhum evento de desaceleração abrupta superior a 5 m/s. Os 800 m terminaram em **19,938656 s**, contra aproximadamente 25,615 s antes da correção; Digo marcou 20,597460 s. O tempo voltou a corresponder aos 19,950 s da simulação isolada.

A [revisão offline da sequência nova](../../../artifacts/rachas-implementation-20261018/seam-fix-analysis.json) também encontrou zero quedas superiores a 5 m/s na velocidade derivada das posições do jogador nas quatro passadas. Nos pontos das duas perdas anteriores, a captura mostra 126→127 km/h nos quadros [02147](../../../evidence/drag-night-session-43108-7127425/temporal/02147.jpg) → [02149](../../../evidence/drag-night-session-43108-7127425/temporal/02149.jpg) e 152→153 km/h nos quadros [02221](../../../evidence/drag-night-session-43108-7127425/temporal/02221.jpg) → [02223](../../../evidence/drag-night-session-43108-7127425/temporal/02223.jpg). Essa evidência confirma a correção no percurso e carros exercitados; não certifica toda a malha do deserto.

Pendências ao registrar este documento: captura específica em 960×540; avaliação auditiva; comparação de frame time antes/depois coordenada na cena real. A captura temporal foi limitada a 30 Hz e inclui seu próprio custo, portanto não serve de benchmark. O resultado de performance do projeto e a integração das demais frentes devem ser reportados pelo agente principal, sem inferir aprovação a partir destes testes lógicos.
