# Serra Bruta — mina remota

Implementação de 06/10/2026, no deserto do mapa 2. O ramal de terra sai da rodovia do sal em `(-180, 0, -1540)` e leva ao portão. A progressão que libera o mapa 2 continua pertencendo à última missão de Harbor.

## Conteúdo jogável

- Cava aberta de 28 m, bancadas de minério e estrada particular de 14 m que desce em espiral. Pátio superior com guarita, estacionamento, oficina e sujeira industrial; britador, esteira, pilhas e máquinas distribuídas nas áreas de trabalho.
- Seis mineradores com ferramentas e animação de trabalho; iluminação industrial noturna. Trabalhadores exteriores e bandidos têm ciclos de vida separados.
- Vento com poeira e areia leve junto ao chão; dois emissores, 64 partículas, acompanhando a altura real da cava e suspensos em interiores ou fora da região.
- Retroescavadeira, trator carregador e dois caminhões de mineração usam o embarque, direção, danos e persistência da frota normal.
- **PgUp/PgDn** levantam/baixam a pá; **B** prende/solta uma pedra, um carro vazio ou uma moto próxima. A carga continua física e bloqueia obstáculos. **N**, segurado no caminhão, inclina a caçamba.
- Túnel discreto no fundo, acessado por **E**, leva à Galeria Santa Brasa. Uma ala contém um segredo independente; a outra guarda uma operação clandestina, quatro bandidos armados e uma bolsa de **R$ 12.000**.
- Pegar a bolsa não altera o saldo. O pagamento ocorre uma vez, após sair vivo pelo acesso. Morte, resgate ou cancelamento perdem a bolsa; salvar durante o transporte do dinheiro fica bloqueado. O recibo da recompensa e o estado da fuga são validados juntos ao carregar o save.

A pá frontal da retroescavadeira é operável; o braço traseiro tem geometria e colisão, mas não possui comando hidráulico independente. A basculação do caminhão é articulada, sem simulação de carregamento e despejo de minério a granel. A guarita é um volume exterior fechado, não um segundo interior acessível.

## Contratos da implementação

`MiningLayout` é a fonte das estradas, posições das máquinas, trabalhadores e acesso secreto. O terreno plano original é recortado antes de construir a cava; o mapa e a física usam a mesma linha central com elevação. Tráfego público não é criado na estrada industrial.

A galeria usa as transições de `FullSession` e o indicador compacto compartilhado. O limite de morte por queda acompanha a superfície da cava; não considera o fundo legítimo como queda fora do mundo. O encontro utiliza projéteis, dano, cobertura e munição da implementação de combate existente. Guardas, corpos e seus novos itens largados são liberados ao terminar a visita.

Os modelos estáticos são agrupados por material e chunk; terreno e consulta de altura compartilham faces. Operários têm um relógio comum e deixam de existir com o exterior suspenso. Veículos seguem a residência da frota; pedras são suspensas quando o terreno está distante. Cargas soltas usam um monitor temporário de apoio que impede repouso e herança indevida do movimento da pá, restaurando as configurações ao pousar.

A pá é um corpo articulado separado do chassi. A carga fica acima do topo físico, conserva sua colisão e só recebe tolerância na consulta hidráulica ao se afastar/baixar após soltura. Aproximar a pá novamente contra a carga continua bloqueado. Estacionamento, suspensão, destruição e restauração acompanham o estado do veículo. Um carro padrão criado longe do jogador espera seu chão carregar antes de ativar a física; isso impede uma queda ilimitada que invalidava o save no início remoto da mina.

O plano distante do deserto também é recortado sobre a cava: ele cobria os personagens abaixo de zero e acionava seus contornos de oclusão. O material do terreno utiliza coordenadas locais e alta precisão; o hash sem seno elimina o mosaico de quadrados/triângulos observado no renderer Mobile, mantendo o relevo e as colisões. As tiras retangulares decorativas que pareciam tábuas foram removidas; a estrada conserva sua sujeira contínua. Os estratos dependem da inclinação real, não de estar abaixo de zero: fundo horizontal e estrada compartilham a cor, eliminando a ponta clara da faixa. [Chão corrigido, câmera normal](/D:/geteco/game/evidence/mining-session-82844-5886280/machine-yard.png).

Na revelação do segredo, o meteorito começa abaixo da tampa do vagão; as sete pedras suspensas cabem dentro de sua largura antes da subida. A correção evita sua aparição antecipada e preserva os tempos, a iluminação, o estado persistente e a colisão.

## Validação e limites

Ambiente: Godot **4.7.2 .NET**, projeto C# compilado, saves exclusivos em `evidence/`. A versão comum sem .NET não foi usada.

- Contrato físico da galeria: **65/65** após corrigir a rota de teste para contornar a ponta legítima da parede do ramal.
- Máquinas: **33/33** no contrato final, **18/18** em destruição de carga e **11/11** em ciclo de vida/colisão da pá. Logs `mining-machine-separate-final.log`, `mining-death-separate-final.log` e `mining-bucket-lifecycle-contact.log` em `evidence/`.
- Main integrado: **93 verificações**, com duas falhas exclusivamente de descarga de pedra; entrada/segredo/save/poeira e carro/moto passaram (`mining-session-75604-5123596`). A causa da pedra foi corrigida e os casos afetados passaram no Main dirigido **34/34** (`mining-session-53996-8156033`), com recuo físico e pouso. As duas rodadas são complementares; não se reclassifica a primeira como totalmente aprovada.
- Operação clandestina: o Main completo inicial cobriu dano real, pausa, morte/resgate, perda da bolsa e cancelamento. Diagnóstico posterior identificou os bônus independentes de conquistas de R$ 50/R$ 200 e o carro inicial caindo sem piso. Após a correção, **64/64** no Main dirigido de fuga, recibo exato de R$ 12 mil, bônus contabilizados separadamente, save/recarga, rejeição de estado/valor inconsistentes e reentrada sem duplicação (`mining-raid-145572-8466811`, stderr vazio).
- Chão: **812 raios sem buracos/desacordo** de superfície. Main visual **8/8**, com poeira em três posições sobre o piso de -28 m. [Dia](/D:/geteco/game/evidence/mining-visual-repair-159796-7462883/pit-machines-day.png), [noite](/D:/geteco/game/evidence/mining-visual-repair-159796-7462883/pit-machines-night.png) e [visão geral diagnóstica](/D:/geteco/game/evidence/mining-visual-repair-159796-7462883/overview-diagnostic.png).
- Acesso final: **15/15**, com carro comum e caminhão gigante nos dois sentidos, **1.996 amostras por percurso**, nenhum contato, varredura bloqueada ou falta de apoio. Inclui 24 combinações de câmera no fundo (`evidence/mining-access-final.log`). A falha inicial que revelou obstáculos e a quebra brusca de declive permanece registrada em `mining-access-deep.log`.
- Caminhão no Main com direção real: **760 m de descida e 760 m de subida em marcha à ré**, sem correção de transform depois da fixture inicial, zero contato/desapoio e vida 1.600 inalterada. Embarque e saída comuns passaram (`evidence/mining-haul-drive-138988-6927521`, log `mining-haul-drive-final.log`, stderr vazio). A subida usa a mesma estrada; não é uma prova de manobra de retorno no fundo.
- Profundidade final renderizada: **36/36**, com jogador e NPC na frente/atrás/ao lado do vagão, caixas e mesa, controles positivos separados (`evidence/mining-20261006/coal-depth/results.json`; `mining-coal-depth-final.log`, stderr vazio).
- Sequências renderizadas: pátio diurno **889 quadros/30 s**, cava noturna final **898/30 s** e galeria final **900/30 s**, nenhum quadro renderizado omitido. A inspeção foi amostral, com folhas de 24 imagens por cenário e intervalos consecutivos nos eventos suspeitos; não se alegam 2.687 quadros inspecionados individualmente. Na versão final, noite 269–272 e poses 450/700 confirmam piso contínuo e poeira legível. Galeria 149–152, 167–172, 176, 224 e 899 confirmam o segredo surgindo após a abertura. A primeira captura identificou a emenda de material e a aparição antecipada, ambas corrigidas e conferidas novamente.

### Desempenho renderizado

Godot 4.7.2 .NET, Forward Mobile, RTX 4060 Laptop, i7-13650HX, 1280×720, MSAA 2×, VSync e limite de FPS desligados somente no processo de medição. Janelas de 30 s após aquecimento de 10 s, sem captura/encodificação dentro da janela. As gravações subsequentes usam limite temporário de 30 FPS e **não** medem desempenho. Meta provisória: 60 FPS / 16,67 ms; aumento >5% em p95/p99 pede confirmação finita.

| Cenário | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pátio sem mina | 836,9 | 1,086 | 1,859 | 2,459 | 7,763 |
| Pátio com mina, primeira medição | 651,4 | 1,338 | 2,606 | 4,016 | 18,955 |
| Pátio com mina, confirmação | 465,8 | 1,961 | 3,389 | 4,421 | 7,723 |
| Local da cava sem mina, piso y=0 | 718,8 | 1,253 | 2,266 | 3,316 | 13,167 |
| Cava y=-28, confirmação anterior ao último ajuste de material | 489,4 | 1,862 | 3,280 | 4,263 | 9,541 |
| Cava final, piso uniforme e areia | 526,0 | 1,677 | 3,242 | 4,254 | 6,774 |
| Galeria final | 363,1 | 2,553 | 4,147 | 5,887 | 11,673 |

Todos esses intervalos estáveis tiveram zero frames acima de 33,3/66,7 ms. O custo adicional da área está confirmado: p95 noturno final +43,1% e p99 +28,3% em relação ao local vazio; o dia variou mais entre medições. A meta absoluta tem folga nesse hardware, mas **não está aprovada ausência de regressão**. Não reduzir iluminação/jogabilidade para esconder o custo. A comparação é do conteúdo completo contra o deserto vazio, não uma atribuição do custo somente à areia. São solicitados 24 NPCs ambientes, com zero transeuntes naturais nesses pontos remotos; seis mineiros são registrados separadamente, e há 4/5 veículos na mina contra 1 na referência. A galeria é nova e não possui interior anterior equivalente.

Chegadas/aquecimentos têm amostras separadas: houve picos de 79–98 ms nas primeiras preparações da mina/realocação da fixture e **154,733 ms** na chegada direta ao fundo da rodada final, contra 74,2 ms no pátio vazio e 12,6 ms no local plano da cava. A galeria final teve um intervalo de 33,684 ms durante sua preparação. Não misturar esses picos com o regime estável nem tratá-los como medição de condução na estrada; a causa de cada pico não foi isolada. O percurso físico foi validado separadamente.

Evidências em `evidence/mining-measure-92564-5740617` (referência), `mining-measure-28548-5280762` (primeira captura/medição), `mining-measure-31076-7268508` (confirmação) e `mining-measure-47248-7113958` (material e revelação finais). Os três primeiros têm os mesmos 134 hashes; no último mudaram somente o shader da mina e a altura/geometria visual do segredo, correções descritas acima. Cada execução manteve suas fontes estáveis. As alterações finais não entram na variante sem mina. Logs de erro vazios; saves isolados preservados.

### Inspeção visual e limites

As seis fontes exteriores ficam com energia zero no dia e nominal à noite, com transição suave de relógio; não acrescentam sombras locais. A galeria usa sete luminárias e a luz do meteorito, duas delas com sombra. A poeira tem dois emissores/64 partículas e seu sampler acompanha o piso a -28 m; entrada na galeria interrompe emissão e simulação. Os trechos examinados não mostraram lampejos involuntários nem o mosaico anterior. Não foram certificados todos os pontos do mapa, amanhecer/anoitecer, chuva ou travessias de streaming em vídeo. As partículas não simulam colisão individual com cada bancada.

O vento e a poeira **não deixam pegadas persistentes** ao caminhar. Esse recurso não está implementado neste lote.

Nenhuma certificação global de interiores, iluminação ou performance decorre dos testes isolados acima.
