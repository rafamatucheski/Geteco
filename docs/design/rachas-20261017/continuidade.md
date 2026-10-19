# Continuação — ambiente, áudio e desafios

Implementação em 18/10/2026, com três agentes (ambiente, áudio e rivais) e integração no mesmo workspace. Este registro complementa a primeira entrega; suas evidências históricas e falhas anteriores permanecem em `implementacao.md`.

## Conteúdo desta rodada

- O percurso ganhou oito grupos de espectadores e carros, com referências visuais diferentes em 201, 402 e 800 metros, redistribuindo o orçamento existente. O desaparecimento de blocos retangulares de vegetação foi localizado no alcance dos MultiMeshes e recebeu fade por pixel limitado às 26 células do corredor.
- Trilha instrumental original de 32 compassos, 104 BPM, com duas camadas sincronizadas. Pátio, preparação, corrida, frenagem e resultado têm transições próprias. Diálogo e rádio têm prioridade; o ajuste Música em zero interrompe as vozes. As falas de cinco personagens preservam sua identidade e não reiniciam a cada volta da pista.
- Seis rivais têm duas provas técnicas cada. Há seis peças exclusivas com vantagens e contrapartidas, obtidas por domínio do carro, sem exigir a própria peça para vencer. Recordes distinguem preparação e distância; até cinco melhorias por rival pagam bônus, sem pagamento repetido do mesmo resultado.
- Noite de Acerto tem Livre e limites de preparação de R$ 6.000 / R$ 12.000. Peças conquistadas também têm valor técnico na categoria. A segunda prova de 402 m preserva o mesmo acerto da primeira.
- A telemetria pós-prova mostra parciais físicas, trocas, limitador, nitro, patinagem e velocidade máxima, com uma dica baseada na passagem. Desafios exibem seu objetivo medido durante a corrida.
- A HUD foi compactada após a revisão do usuário: painel de marcha/velocidade de 312×163 para 224×124, sem borda pesada, com aproximadamente 14 px de separação do conta-giros. Os atalhos ficam em uma linha sem caixas. Capturas reais de preparação e da prova de Lívia em 1280×720 confirmam separação e leitura do objetivo completo.
- O quadro oferece três modelos emprestados, um por vez, com entrada e saída normais. O empréstimo não transfere propriedade: salvar preserva peças e recompensas e restaura o carro original ao carregar. Uma noite salva com carro emprestado permite retirar novamente o mesmo modelo.
- O botão RACHAS no menu usa um perfil separado, com Mirage e R$ 2.000 iniciais pagos uma vez. O ledger de missões começa vazio; a ponte continua fechada segundo sua política normal. Saves da campanha não são selecionados nem substituídos por esse modo.

## Evidência disponível durante a integração

| Cobertura | Resultado |
| --- | --- |
| Composição, limites de entidades, colisões dos espectadores e materiais | 11 verificações, zero falhas: `output/drag-meet-composition-clean-20261018.log` |
| Identidade musical, buses, transições e falas | 33 verificações, zero falhas: `output/drag-audio-identity-final2-20261018.log` |
| Telemetria, cruzamento físico e encerramento na chegada | 10 verificações, zero falhas: `output/drag-telemetry-clean-20261018.log` |
| Perfil isolado, JSON, SaveStore, ponte e preservação da campanha | 19 verificações, zero falhas: `output/drag-profile-json-fixed-20261018.log` |
| Áudio de Main: embarque, 800 m, resultado e retorno | Concluído, zero falhas: `output/drag-audio-capture-final-20261018.log` |
| Áudio após importação dos Ogg pelo editor .NET | 33 verificações, zero falhas: `output/drag-audio-imported-20261018.log`; export PCK não testado |
| Áudio sem callback por frame após estabilizar volumes | 35 verificações, zero falhas: `output/drag-audio-settled-20261018.log`; vozes continuam tocando e mudanças de contexto reativam as transições |
| Desafios, categorias, despacho, painéis, Noite e garagem | 328 verificações focais aprovadas, mais tuning; detalhes no relatório de desafios |
| Doze objetivos em Main com Faísca original | Oito na primeira execução e quatro na retomada; retomada 76/76, instalação real da ECU e snapshot completo aprovados |
| HUD em 1280×720 e 960×540 | 12 capturas isoladas mais duas de confirmação dos controles; teclado/controle, Lívia e Rauhz. `artifacts/rachas-continuation-20261018/hud-review.md` |
| Faróis do rival e regressão de prioridade | 11 + 7 verificações, zero falhas; captura noturna real final com saída limpa |
| Fila completa após correção de encerramento | 29/29, exit 0, sem erros/leaks: `output/drag-queue-shutdown-after-20261018.log` |
| Menu com RACHAS em 1280×720 e 1024×768 | 15 verificações e inspeção visual aprovadas: `output/drag-menu-final-20261018.log` |
| Empréstimo, duas provas físicas e recarga em novo Main | Fluxos aprovados; 48/49 no primeiro runner por uma expectativa incorreta de saldo, seguida de 5/5 na confirmação dirigida dos saves reais |
| Vegetação em lotes de 48 m no corredor | 185/185 no renderer real: buffers equivalentes, índices de quebráveis, impactos, AABBs e descarte; `output/drag-ground-cover-batches-final-20261018.log` |

A captura de áudio tem 50,432 s, pico de −2,880 dBFS e nenhuma amostra saturada. Com ambos os motores ativos e separação longitudinal de até 12 m, o motor do jogador ficou 6,573 dB acima do rival em RMS antes do mesmo bus SFX. A maior sequência de zeros por fase foi de uma amostra. Esses dados verificam a mixagem capturada; não substituem avaliação subjetiva de timbre e conforto.

Uma captura externa de outro workspace começou entre o inventário de processos e o início da coleta de áudio. A concorrência está registrada em `evidence/drag-audio-identity-140368-7304295/concurrency.json`; não se apresenta essa coleta como benchmark ou prova de cadência sem interferência.

## Encerramento e preservação de recursos

A confirmação headless anterior completou 29/29 verificações, mas registrou 117 folhas GPU destacadas na `GpuReleaseQueue` e 117 instâncias de renderização não liberadas na saída. Essas folhas não pertenciam mais à árvore, e o encerramento não chamava a drenagem existente. A fila agora executa `flush()` no `tree_exiting` da raiz, preservando o descarte gradual durante o jogo. O focal de encerramento confirmou zero pendências; a repetição completa da fila terminou com 29/29 e nenhum erro de recursos, mesmo tendo 99 folhas ainda aguardando descarte antes de sair. A janela noturna renderizada posterior também encerrou sem erros. As falhas anteriores permanecem nos logs.

O amostrador de diagnóstico também verifica `is_inside_tree()` antes de ler a posição global de jogador/carro no último frame de encerramento. A importação dos dois Ogg foi concluída e seus recursos foram carregados pelo focal de áudio, mas o editor headless relatou avisos próprios de encerramento; não se confunde essa execução com uma exportação PCK limpa.

## Empréstimo, perfil e recuperação

O Main iniciou pelo checkpoint do perfil dedicado, com backend C# e campanha vazia. O teste desembarcou pela porta normal, retirou um Faísca, recusou duplicação/devolução com motorista, concluiu fisicamente as duas provas de Digo, conquistou a ECU e confirmou que o Mirage original sobreviveu além do raio normal de descarregamento. Durante o empréstimo, sua marca temporária de residência é preservada e restaurada exatamente na devolução. A captura de save mantém também a região original do carro; o guard de salvar um empréstimo ocupado fora do deserto foi verificado separadamente como condição de contrato, sem afirmar travessia da ponte.

Os saves foram escritos por `SaveStore` em `evidence/drag-loaner-113284-9698046`. O mesmo teste encerrou o mundo, abriu um novo Main pelo checkpoint da noite pendente, retornou a pé, recusou outro modelo, recuperou o Faísca correto com a peça possuída e encerrou/devolveu normalmente. A campanha permaneceu vazia em toda a cadeia; não houve erro de script nem vazamento na saída.

O primeiro runner aprovou 48/49 verificações: a única falha esperava R$ 2.037, ignorando os R$ 50 que a conquista normal `first_grand` concedeu ao entrar com a verba inicial. O arquivo contém R$ 2.087 com os três recibos corretos (2.000 + 50 + 37 da fixture), veículo original e peça conquistada. A expectativa foi corrigida para comparar o saldo observado antes/depois do save. A confirmação dirigida releu os dois arquivos reais pelo contrato completo e aprovou 5/5, incluindo saldo, carro, peça e noite pendente, sem repetir as provas físicas já aprovadas. Logs: `output/drag-loaner-session-20261018.log` e `output/drag-loaner-save-recheck-20261018.log`.

## Desempenho desta continuação

Base desta rodada: `evidence/drag-design-183220-8346714/metrics.json`. Mesmo runner `measure_design.gd`, Main real, Godot 4.7.2 .NET, RTX 4060 Laptop, Vulkan Mobile, 1280×720, noite fixa 0,9, VSync desligado e FPS livre somente no processo. Pátio/quadro têm 30 s cada; duas passadas somam cerca de 41,4 s. As imagens ficam fora das janelas amostradas.

| Cenário | Base: FPS / p95 / p99 ms | Primeiro depois | Confirmação direta |
| --- | --- | --- | --- |
| Pátio | 277,7 / 5,692 / 6,325 | 196,2 / 7,899 / 9,096 | 261,0 / 6,309 / 7,874 |
| Quadro | 392,9 / 4,096 / 5,266 | 267,2 / 6,831 / 7,396 | 374,0 / 4,350 / 5,416 |
| Corrida 1 | 264,9 / 6,113 / 8,405 | 254,3 / 5,883 / 7,075 | 246,9 / 6,243 / 7,718 |
| Corrida 2 | 286,8 / 5,563 / 6,987 | 257,9 / 5,734 / 7,880 | 249,7 / 6,150 / 8,568 |

O primeiro depois (`evidence/drag-design-96764-7986057/metrics.json`) foi iniciado por `Start-Process -WindowStyle Hidden`, embora o runner force modo de janela normal. O monitor de processos não registrou outros Godot/ffmpeg. Para evitar atribuir a diferença à forma de lançamento, a confirmação voltou à mesma invocação direta do baseline (`evidence/drag-design-173968-9367732/metrics.json`). Um teste externo de direção rodou no aquecimento dessa confirmação e terminou antes das janelas amostradas; o inventário temporal está em `artifacts/rachas-continuation-20261018/performance-confirm-processes.json`. A amostragem do inventário é de 2 s, não uma prova de ausência de processos mais curtos.

Na confirmação, pátio/quadro mantiveram exatamente o censo da base: 27 residentes admitidos, 24 espectadores, 14 modelos e 14 drivers ativos, 31 chunks e 26 células do corredor. As corridas têm três drivers ativos em vez de quatro por causa da redistribuição local do público. A confirmação registrou zero frames acima de 33,3/66,7 ms, com máximos 12,346 / 19,343 / 13,266 / 20,917 ms. A meta absoluta de 60 FPS foi atingida nesse hardware, mas as caudas de pátio e segunda corrida excedem a tolerância de 5% em ambas as execuções; portanto **não se aprova equivalência de desempenho**. O aumento antigo de custo do pátio na primeira rodada também continua preservado no registro histórico.

O A/B dirigido da vegetação confirmou seis lotes adicionais no frustum e 261.462 vértices processados por frame ao corrigir o corte precoce. O dither isolado não apresentou regressão consistente, e houve deriva entre as repetições do estado atual. O monitor externo, amostrado a cada 2 s, não registrou outros Godot/ffmpeg durante esse A/B (`artifacts/rachas-continuation-20261018/ground-cover-ab-processes.json`). Isso identifica custo geométrico, sem atribuir toda a diferença de tempo à vegetação.

Somente no corredor, os lotes de 96 m foram subdivididos em 48 m, preservando as linhas dos buffers geradas no retângulo original. As posições, cores, densidade, materiais e fade permanecem iguais; o remapeamento antecede o registro dos quebráveis. Os limites geométricos são computados durante a geração fatiada e o upload também respeita o orçamento entre lotes. O focal renderizado aprovou 185/185 verificações nas 26 células, incluindo impacto real nos quatro quadrantes. O renderer dummy headless não devolveu os transforms enviados em lote; essa tentativa foi preservada como diagnóstico, sem alterar produção para contorná-la.

A confirmação temporal (`evidence/drag-cover-temporal-151408-9076191`) registrou 900 frames em 30,161 s, sem saltos ou falhas, e confirmou 494 lotes com exatamente 112.776 instâncias, todos com AABBs e margens válidos. A inspeção dirigida preservou continuidade nos pontos de ida/volta; o vazio à esquerda também existe na captura anterior. Houve captura externa durante o carregamento: os custos registrados em StallWork não aprovam streaming nem equivalência de carregamento frio. O cenário, a população e a qualidade visual não foram reduzidos.

O comparativo final dessa versão, já com o callback de áudio estabilizado, usou novamente a invocação direta e encerrou sem erros (`output/drag-polish-final-20261018.log`, `evidence/drag-design-163404-7424393/metrics.json`). O monitor de 2 s não registrou outros Godot/ffmpeg em toda a execução (`artifacts/rachas-continuation-20261018/performance-final-processes.json`).

| Cenário | FPS | p50 / p95 / p99 ms | Máximo ms | Frames >33,3 / >66,7 ms |
| --- | ---: | --- | ---: | --- |
| Pátio | 213,5 | 4,058 / 7,164 / 8,571 | 12,234 | 0 / 0 |
| Quadro | 281,8 | 3,163 / 5,608 / 6,712 | 23,555 | 0 / 0 |
| Corrida 1 | 211,8 | 4,491 / 7,604 / 8,633 | 16,029 | 0 / 0 |
| Corrida 2 | 214,6 | 4,363 / 6,994 / 8,994 | 22,693 | 0 / 0 |

O censo permaneceu igual à confirmação anterior. A meta absoluta foi atendida nesse hardware, mas a regressão relativa continua acima da tolerância: **desempenho não aprovado**. A diferença entre processos não demonstra que a subdivisão seja a causa.

A última comparação localizada (`evidence/drag-batches-ab-222496-8130303/metrics.json`) reuniu cópias dos mesmos 112.776 elementos em lotes de 96 m dentro do mesmo Main, preservando material, fade, câmera e censo. Somente a visibilidade de cada representação foi alternada, sem registrar quebráveis duplicados. As três janelas de 30 s terminaram com restauração exata e saída limpa. O monitor de 2 s não registrou externos entre 12:14:12,499 e 12:17:03,143 UTC (`artifacts/rachas-continuation-20261018/ground-batches-ab-processes.json`); um teste externo identificado após a saída não foi observado durante essa janela. Processos mais curtos que o intervalo do monitor não estão excluídos por essa evidência.

| Variante no mesmo Main | FPS | p95 / p99 ms | Draw calls / primitivas |
| --- | ---: | --- | --- |
| Lotes de 48 m | 307,1 | 5,217 / 6,542 | 153 / 403.996 |
| Mesmos elementos reunidos em 96 m | 265,0 | 7,196 / 7,724 | 168 / 699.350 |
| Lotes de 48 m restaurados | 465,8 | 3,532 / 4,158 | 153 / 403.996 |

**Decisão: manter a subdivisão localizada.** As duas janelas favorecem o ajuste, e os contadores confirmam menos 295.354 triângulos (886.062 vértices) processados fora do enquadramento. A revisão das imagens das duas variantes preservou a cena visível. A deriva entre as repetições impede atribuir um percentual exato de ganho ao ajuste; essa comparação não substitui a reprovação relativa do comparativo completo. Não houve redução de qualidade, densidade ou público. A investigação localizada terminou aqui, sem ampliar mudanças para outros sistemas concorrentes.

## Pendência e limites da entrega

Permanece pendente resolver a regressão do comparativo integrado e aprovar desempenho frente à base. O A/B resolveu a decisão sobre o agrupamento da vegetação, mas não isolou a origem de toda a diferença entre execuções do workspace compartilhado. Os recursos funcionais descritos acima estão implementados e validados na cobertura registrada; isso não equivale à aprovação de todos os sistemas do jogo ou a FPS universal.

A sequência inicial dos desafios aprovou as oito provas de Digo, Lívia, Raul e Jessica, mas encontrou corte indevido em Nadir: o limite de oito segundos após a chegada do rival também encerrava a prova técnica. Esse corte foi removido somente enquanto Dante ainda está concluindo um desafio técnico, mantendo o limite absoluto de 60 s e a recuperação de rival que não chega. A retomada aprovou as quatro provas de Nadir e Rauhz, incluindo a permanência da prova além dos oito segundos após a chegada do adversário.

A revisão temporal de ambiente cobre dia, retorno lento ao entardecer e noite com clima global de tempestade. O bioma seco suprimiu a precipitação: não há evidência de chuva nem relâmpagos nessa captura. Os detalhes e limites estão no relatório do ambiente.

Detalhes: [ambiente](continuidade-ambiente.md), [desafios e economia](desafios-rivais-implementacao.md).
