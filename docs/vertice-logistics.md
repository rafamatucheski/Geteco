# Vértice — transportadora e circuito do Porto Sul

## Empilhadeiras, operadores e escritório — terceira revisão de 28/09

- **Caminhada de ré:** o `Actor` gira o nó `visual` para que o −Z dele siga o
  movimento, mas `CivilianModel`/`DockWorkerModel` têm o peito em +Z. Todos os
  funcionários da Vértice andavam de costas. O modelo agora recebe meia volta
  dentro do `visual` (`VerticeCompany._build_staff`). Os funcionários do porto
  (`PortWorker`) já corrigiam isso por conta própria em `_facing_yaw`.
- **Mais gente:** quatro operadores novos (corredor z −8,5 do galpão, travessia
  z 12, flancos das ilhas de carga), um segundo funcionário de escritório e dois
  funcionários sentados digitando às mesas (somem fora do expediente).
- **Reach-stackers:** os três blocos de caixas viraram máquinas com rodas duplas
  de tração, eixo de direção, capô com grelha e escapamento, cabine envidraçada,
  giroflex, lança telescópica em duas seções, cilindro de elevação e spreader
  com twistlocks. O ciclo de descarga não mudou.
- **Empilhadeiras dirigíveis:** três `port_forklift` (veículo comum, entra e
  dirige) em vagas fora das faixas de caminhão (`VerticeYardForklifts.gd`). A
  cerca segura os lados; no portão há uma parada posicional em z 74,5, não um
  colisor invisível — consultas de raio sem máscara (tiros) bateriam nele.
- **Escritório bagunçado** (`VerticeOfficeClutter.gd`): pilhas tortas de papel,
  pastas, canecas, pizza, bilhetes no monitor, lixeiras transbordando, caixas de
  arquivo (algumas abertas), folhas no chão, impressora com papel enroscado,
  cadeiras largadas, quadro branco rabiscado. Estático e agrupado por material.
  Corredor x 35, passagem z 8, rotas dos funcionários e o envelope escondido
  ficam livres. As cadeiras das mesas ganharam assento, encosto e coluna.
- `test_vertice_yard_layout.gd` (empresa isolada, sem Main): frente dos modelos,
  rotas de operadores/escritório sem sólidos, vagas livres, corredores do
  escritório. `test_vertice_yard_crew.gd` (Main): empilhadeiras nascem, operadores
  andam de frente e percorrem a rota, empilhadeira acelerada para no portão.

## Pátio ocupado e esconderijo — segunda revisão de 28/09

O terreno ganhou duas ilhas centrais de cargas paletizadas, bobinas, paleteira,
caçambas, manutenção lateral, bicicletário e abrigo de descanso. Copa, bancadas
e estantes receberam objetos em escala humana. Duas estações frontais de
embalagem têm balança, impressora, fitas, roletes e carrinhos com caixas.
As faixas de caminhões e rondas
permanecem livres; decoração estática agrupada por material não adiciona luzes
nem lógica por frame ao pátio.

Um alçapão discreto atrás das estantes dá acesso ao esconderijo subterrâneo,
com bancada, ferramentas, armário de munição, cama, rádio e tubulações. O acesso
não aparece no mapa; só exibe o marcador compacto ao chegar perto. Usa as
transições existentes de lugares e retorna ao mesmo corredor. A M4A1 flutua
sobre um círculo, é coletada ao caminhar e tem 90 cartuchos adicionais. Há
também R$ 2.500 em um segundo achado. Ambos têm recibos persistentes próprios,
sem duplicação em reentrada/reload e sem coleta por jogador morto.

- `test_vertice_hideout.gd`: 33 checks aprovados em Main, incluindo caminhada
  até o acesso, entrada/controle/câmera, pickups, nova Main restaurada do save,
  saída física até a escada, retorno e reentrada sem duplicação.
- `test_vertice_company.gd`: horários, portas, NPCs e achados anteriores continuam
  aprovados após a decoração.
- `test_vertice_site_dressing.gd`: 413 checks aprovados, com 62 novos sólidos,
  cápsulas de jogador/NPC e casco carregado percorrendo os acessos às três docas.
- `test_vertice_site_depth.gd`: 51 checks renderizados aprovados, com jogador/NPC
  antes, atrás e ao lado das cargas e mesas, incluindo controles positivos.
- `test_vertice_packing.gd` e `test_vertice_packing_depth.gd`: 49 checks físicos
  e 27 renderizados aprovados nas novas estações, incluindo travessia transversal
  em z=12, corredores longitudinais e as três entradas das docas.
- `test_vertice_undercroft_geometry.gd`: 114 checks físicos e renderizados
  aprovados, cobrindo sólidos, cantos, corredores, spawn e oclusão de jogador/NPC.
  Evidências em `evidence/port-logistics-20260928/undercroft-depth/` e
  `evidence/vertice-detail-20260928/depth/`.

Medição equivalente desta revisão: Main, RTX 4060 Laptop, Mobile/Vulkan,
1280×720, VSync desligado, limite 144 FPS, 8 s de aquecimento + 30 s de amostra.
Nenhum outro Godot concorria. Meta provisória: p95 abaixo de 16,67 ms; aumento
acima de 5% em p95/p99 exigia confirmação finita.

| Cenário | FPS antes → final | p95 antes → final (ms) | p99 antes → final (ms) | Máximo final (ms) | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|
| Pátio | 144,01 → 144,01 | 8,410 → 8,461 | 8,582 → 8,669 | 20,936 | 0 / 0 |
| Galpão | 143,98 → 143,97 | 8,540 → 8,635 | 8,775 → 8,885 | 22,103 | 0 / 0 |
| Noite | 140,53 → 140,47 | 8,779 → 8,826 | 9,129 → 9,172 | 51,598 | 11 / 0 |
| Copa/escritório com chuva | 140,70 → 142,20 | 9,737 → 8,954 | 11,444 → 9,257 | 47,104 | 10 / 0 |

O orçamento de regime estável foi atendido nas quatro amostras finais; nenhuma
regressão acima do limiar foi confirmada. Houve um pico de 2.078,727 ms no pátio
na primeira execução intermediária (`detail-after`), com p95 de 9,044 ms. A
confirmação final manteve os objetos e não reproduziu esse pico, conforme a
tabela; a causa do evento isolado não foi determinada. O aquecimento final
atingiu 485,059 ms no pátio e 312,885 ms à noite. Não se afirma ausência de
engasgos na primeira visita. Todas as execuções foram preservadas em
`evidence/port-logistics-20260928/{detail-before,detail-after,detail-final}/`.

Fotos reais finais: [pátio](../evidence/port-logistics-20260928/detail-final/vertice.png),
[galpão com embalagem](../evidence/port-logistics-20260928/detail-final/warehouse-interior.png),
[visão geral](../evidence/port-logistics-20260928/detail-final/vertice-overview.png),
[noite](../evidence/port-logistics-20260928/detail-final/night.png) e
[copa com chuva](../evidence/port-logistics-20260928/detail-final/rain-interior.png).

O subsolo foi medido separadamente na Main, entrando pelo gerenciador real de
lugares e usando os mesmos parâmetros de medição. Suas duas luzes locais não
lançam sombras e só existem enquanto a sala está carregada; a decoração é
estática, e apenas a arma disponível anima enquanto o ambiente está ativo.

| Subsolo | FPS | p50 / p95 / p99 (ms) | Máximo (ms) | Aquecimento máximo (ms) | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|
| Dia | 144,01 | 6,945 / 7,768 / 8,237 | 9,188 | 24,934 | 0 / 0 |
| Noite | 143,96 | 6,944 / 7,674 / 7,867 | 21,364 | 15,629 | 0 / 0 |

Fotos reais do [subsolo de dia](../evidence/port-logistics-20260928/undercroft-final/undercroft.png)
e [à noite](../evidence/port-logistics-20260928/undercroft-night/undercroft.png).
Orçamento provisório aprovado nas amostras registradas, sem promessa universal
de FPS. Os processos renderizados ainda registram avisos de descarte de duas
texturas/RID ao encerrar, também presentes na baseline; não houve erro de
gameplay ou falha de teste associada. Os arquivos JSON preservam todas as
amostras, configurações e aquecimentos.

## Implantação e circuito

A empresa fica além do Neko, em uma extensão arborizada de Harbor, com origem
(-340, 0, -80). O antigo galpão junto à cidade foi substituído. A fachada mostra
somente VÉRTICE; o conjunto tem escritório contínuo, galpão mobiliado, três docas,
pátio cercado, portaria, dois guardas e três funcionários.

O expediente segue o relógio visível do jogo, das 8h às 18h. A porta do escritório
abre por proximidade. O portão mantém saída para quem estiver dentro após o
fechamento e libera os caminhões da frota. Câmera e teto mudam ao atravessar o
limiar e voltam ao exterior ao sair. Os dois achados internos usam recibos únicos
da economia (`vertice_office_envelope`, `vertice_rear_cash`), sem duplicar na
reentrada ou restauração.

Os três caminhões existentes carregam os contêineres no cais, usam ruas dirigidas
do grafo real e a estrada rural, descarregam com manipuladores de pátio e voltam
vazios ao porto. Não são teletransportados para entregar. Após destruição, a vaga
recebe prazo absoluto em `urban_operations.logistics`: 600 unidades virtuais
correspondem a uma volta completa do relógio visível do jogo, incluindo avanço
ao dormir. Esse relógio é independente do calendário de cotas de reboque. O prazo
persiste no save. A reposição física ocorre no porto após o prazo, durante o
expediente em Harbor e quando o ponto de nascimento estiver livre. A frota também
opera quando o jogador visita a empresa sem passar pelo porto. O destroço não é apagado
imediatamente nem reutilizado como caminhão reparado.

## Validação

- `test_port_depot.gd`: 151 verificações aprovadas; cápsulas reais de jogador e NPC,
  móveis, paredes, circulação, portas e pontos dos achados.
- `test_vertice_company.gd`: horários, portão, saída noturna, porta contínua,
  câmera, conversa e recibos de recompensa aprovados na cena Main.
- `test_vertice_depth.gd`: 51 verificações renderizadas aprovadas; frente, lado e
  atrás de mesa/estante, jogador e NPC, com controle positivo. Evidências em
  `evidence/port-logistics-20260928/depth/`.
- `test_port_logistics.gd`: 22 verificações aprovadas na cena Main com trânsito:
  carga física, chegada, descarga, retorno e nova carga no mesmo caminhão;
  destruição, prazo de 24 horas, serialização, rejeição de prazo inválido e
  reposição única. A validação encontrou e corrigiu acesso que tocava o muro do
  Neko e geração indevida de trânsito na estrada particular. O caminhão longo
  também pode recuar fisicamente, com a retaguarda comprovadamente livre, para
  dar passagem a um veículo atravessado em cruzamento.
- `test_port_logistics_clock.gd`: relógio visível, meia-noite, avanço ao dormir,
  independência das cotas de reboque e restauração do prazo aprovados. A
  equivalência não depende da duração real do dia configurada no clima.
  A repetição física focada (`--cooldown-only`) passou 18 verificações com esse
  relógio: caminhão sai do nascimento, é destruído no cais e recebe uma única
  reposição nova após o prazo persistido.
- Frete conduzido pelo jogador: a execução integral fez 30 verificações e falhou
  somente ao esgotar o limite da condução automática do teste, em
  (82,20; 136,00), com contato contra outro `CharacterBody3D`. A consulta do casco
  completo nessa posição/orientação encontrou zero sólidos estáticos sobre o
  piso. Isso não aprova a viagem manual completa. O modo explícito
  `--lifecycle-only`, com fixture no destino, passou 62 verificações: nova Main
  restaura posição, carga e motorista; entrega paga R$ 300 uma única vez;
  devolução retoma a rota NPC e preserva o carro pessoal; replay de save e
  remoção do caminhão não ressuscitam nem duplicam a carga.
  Um probe focado de remoção confirmou também que a carga compartilhada é
  preservada ao sair da árvore, sem consultar transformação global inválida.

## Imagens e desempenho renderizado

Fotos reais: [visão geral](../evidence/port-logistics-20260928/after/vertice-overview.png),
[escritório com funcionário](../evidence/port-logistics-20260928/after/interior.png),
[noite](../evidence/port-logistics-20260928/after-weather-fixed/night.png) e
[chuva](../evidence/port-logistics-20260928/after-weather-fixed/rain.png).

Main, Godot 4.7.2, Mobile/Vulkan, RTX 4060 Laptop, 1280×720, VSync desligado,
limite 144 FPS; 8 segundos de aquecimento e 30 de amostragem por cenário.
Não havia outra instância Godot ao iniciar a medição final. A meta provisória
de 60 FPS foi atendida nas amostras atuais da empresa e da estrada.

| Cenário novo | FPS | p50 / p95 / p99 (ms) | Máximo (ms) | Quadros >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|
| Pátio de dia | 142,10 | 6,962 / 9,830 / 10,513 | 60,045 | 8 / 0 |
| Interior | 141,50 | 6,958 / 9,653 / 16,407 | 22,589 | 0 / 0 |
| Estrada arborizada | 143,97 | 6,955 / 9,357 / 9,816 | 24,270 | 0 / 0 |
| Pátio à noite, corrigido | 143,99 | 6,951 / 8,096 / 8,439 | 17,772 | 0 / 0 |
| Chuva | 143,95 | 6,958 / 8,849 / 9,394 | 24,119 | 0 / 0 |

A primeira amostra noturna revelou uma regressão real: 9,55 FPS e p95 de
207,442 ms. Os caminhões suspensos à noite solicitavam terreno fora da câmera,
enquanto o streaming o removia por estarem sem física; isso reconstruía os
chunks continuamente. A correção conserva as luzes e suspende a preparação de
terreno dos caminhões estacionados. A repetição equivalente é a linha noturna
corrigida acima; não se usou redução visual para obter o resultado.

Comparação com a baseline inicial dos pontos existentes:

| Cenário | FPS antes → depois | p95 antes → depois (ms) | p99 antes → depois (ms) |
|---|---:|---:|---:|
| Porto | 30,00 → 143,97 | 34,286 → 10,011 | 35,770 → 10,304 |
| Antiga localização junto ao Neko | 29,99 → 129,57 | 35,917 → 11,997 | 38,844 → 28,246 |
| Avenida | 28,67 → 97,85 | 47,738 → 13,994 | 64,436 → 15,540 |

A baseline histórica foi capturada com outras sessões ativas e não isola o
efeito desta implementação: esses números **não comprovam ganho causado pela
mudança**. O orçamento atual dos cenários novos foi medido, mas a comparação
histórica rigorosa permanece inconclusiva. A primeira visita ao porto teve
pico de 1.267 ms durante aquecimento; o aquecimento do pátio novo atingiu
57,528 ms e o do interior, 27,852 ms. Não se declara ausência de engasgos.
Dados brutos, duração e quantidades de frames estão em
`evidence/port-logistics-20260928/{before,after,after-weather,after-weather-fixed}/`.

Não foram alteradas as regras de combate ou entrada da garagem do Maciota.
