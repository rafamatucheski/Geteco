# Parque Lume e Lago Sereno — ampliação exterior, 07/10/2026

Escopo: preenchimento do Parque Lume com mobiliário, vendedores automáticos e quatro palhaços andando; transferência do pesque-pague para uma área rural arborizada. **Dois exteriores alterados, zero interiores novos ou reformados.** A casa Umbra, os passeios, os segredos e os bloqueios da campanha permanecem fora da reforma. Implementação dividida entre os dois agentes existentes; integração, revisão e comparação de desempenho pelo agente principal.

## Conteúdo

O parque recebe quatro barracas, cinco conjuntos de mesas/bancos/sombreiros, seis canteiros, dois carrinhos, três grupos de balões, bandeirolas e três lixeiras. Os volumes sólidos acompanham o mobiliário; a circulação principal, o acesso à casa, à plataforma, à cabine e aos segredos permanecem livres. A decoração está nos batches estáticos existentes, sem novas luzes ou SubViewports.

Quatro palhaços usam o rig civil, passos e colisão reais, com rotas locais, roupas e acessórios distintos. Sua criação é escalonada; ficam ocultos e desativados no interior e são liberados ao afastar-se do parque. As máquinas **Aurora** e **Pingo** vendem água, suco, barra de cereal e sanduíche pelo sistema de economia/inventário. Cada unidade possui recibo persistente: débito, entrega e estoque são confirmados juntos, com rejeição de saldo/capacidade insuficientes e callbacks repetidos. Estoque inicial: 24 águas, 16 sucos, 16 barras e 12 sanduíches. Não foi acrescentado texto decorativo às fachadas.

O Lago Sereno sai de `(-175, 0, -3)` para **`(-500, 0, -35)`**, aproximadamente 326,6 metros a oeste. Conserva os quatro pontos `sereno_0` a `sereno_3`, a recepção, os cinco pescadores e o histórico da atividade. O local antigo permanece como clareira apoiada e reservada, evitando que saves antigos carreguem dentro de novos troncos ou sobre água.

O acesso parte de `(-340, 0, 18)` no ramal rural existente e segue por uma estrada de terra de 6,5 metros, até a entrada em `(-500, 0, -5)`, com estacionamento e retorno no lago. Trata-se de um acesso local sem geração de tráfego de ônibus/caminhões, preservado também na reconstrução pelo editor. A extensão irregular do terreno pertence ao `NativeRegion`, com apoio físico, classificação como terra na proteção costeira e streaming por chunks. O piso opaco em y=0 cobre o oceano, cuja malha subterrânea permanece em y=-0,94 como no restante do mundo. Há **208 árvores novas**, além das sete do próprio lago, e arbustos distribuídos em MultiMeshes por área, com troncos físicos e afastamentos da estrada, margens e câmera de pesca.

## Validação

Ambiente: Godot **4.7.2 .NET**, `Harbor.csproj` compilado com zero erros/avisos; Main e roteador C# reais, fixtures e saves isolados. Sem descarte de alterações concorrentes ou escrita no progresso pessoal.

| Verificação | Resultado e cobertura |
| --- | --- |
| Máquinas / economia | **43/43** em `tests/test_amusement_park_vending.gd`: preços, capacidade, recibos repetidos, estoque esgotado, save em disco e rejeição por distância, morte ou veículo. |
| Mobiliário / palhaços | **428/428** em `tests/test_amusement_park_dressing.gd`: volumes sólidos, cápsulas de Dante/NPC, interações, 21 pernas completas de patrulha, movimento real e liberação dos quatro corpos. |
| Terreno / acesso rural | **21/21** em `tests/test_fishing_relocation.gd`, após remover a pele duplicada: superfície única, orientação, terra seca, apoio a cada 2 m nos dois rastros de roda, tronco sólido, emenda atravessada com ator real, posições legadas seguras e recarga de chunks. [Log final](../../evidence/fishing-relocation-floor-20261007.log). |
| Lago relocado | **71/71** em `tests/test_fishing_site.gd`, preservando apoio, móveis e acessos da atividade. [Log](../../evidence/fishing-site-relocated-20261007.log). |
| Pesque-pague em Main | **58/58**: save antigo com captura anterior e carteira, C# ativo, embarque/estrada/estacionamento por controles reais, desembarque, caminhada ao balcão/margem, início/cancelamento da pesca, persistência, afastamento/retorno, mapa e ação Marcar. Oclusão do jogador atrás de tronco verificada separadamente da colisão. [Resultado](../../evidence/fishing-relocation-session-144656-7386378/report.json). |
| Parque em Main | A [sessão ampla](../../evidence/amusement-park-life-session-193668-6786040/result.json) verificou entrada→plataforma, casa/retorno, guarda-roupa, quatro patrulhas de 19–23 m, pausa no interior, ameaça/recuperação/morte e descarregamento/reentrada. Os casos de comércio e mesa foram corrigidos e repetidos de forma dirigida, conforme abaixo. |
| Compra / save em Main | **11/11** na [reprise final](../../evidence/amusement-park-life-session-195352-5993121/result.json): botão real, água por R$6, guarda de missão e retry de checkpoint; após liberar somente a campanha da fixture, gravação em disco e restauração confirmam **R$994 / água 1 / estoque 23**. Nenhuma mudança de produto necessária. |

Fotos reais do novo acesso: [entrada da estrada](../../evidence/fishing-relocation-session-144656-7386378/dirt-road-start.png), [estacionamento](../../evidence/fishing-relocation-session-144656-7386378/parking.png), [recepção](../../evidence/fishing-relocation-session-144656-7386378/reception.png), [mapa/destino](../../evidence/fishing-relocation-session-144656-7386378/map-road-destination.png). O carro é posicionado no início somente para preparar a fixture; todo o ramal é dirigido fisicamente. Capturas contínuas limitadas a 30 FPS e gravação de imagens reduzem a cadência: o FPS mostrado nessas fotos não é medição de desempenho normal.

A sessão ampla do parque terminou **23/31**, com oito falhas de fixture/cascata preservadas no resultado: o roteiro tentou atravessar diagonalmente a cabine existente ao ir à máquina; a métrica da mesa misturava corpo e sombra. A [reprise dirigida](../../evidence/amusement-park-life-session-194100-6025826/result.json), com caminho pelo corredor e ROI corporal, passou **11/12**; restou o save bloqueado porque a fixture iniciava com missão ativa. A reprise final de 11/11 testou explicitamente essa guarda e a gravação adiada. Não se apresenta nenhuma dessas tentativas parciais como aprovação integral, nem se repetiram as rotas já comprovadas sem necessidade.

## Profundidade e registro temporal

Barraca: controle corporal visível **32.329 pixels**, atrás do sólido **zero**. Mesa: na faixa coberta pelo tampo/pedestal, **3.530 → zero pixels**; tronco/cabeça acima permanecem visíveis (**10.901 pixels**). Fotos reais [barraca](../../evidence/amusement-park-life-session-193668-6786040/stall_behind.png), [mesa pela frente](../../evidence/amusement-park-life-session-194100-6025826/table_front.png) e [mesa por trás](../../evidence/amusement-park-life-session-194100-6025826/table_behind.png). A física foi verificada separadamente; sombra e HUD não são prova de oclusão corporal.

No bosque, a região corporal atrás de um tronco opaco apresentou **7.690 → zero pixels** ao comparar Dante visível/oculto, com câmera fixa. O contorno externo de cabeça do sistema existente `CityLook/occluded_silhouette` aparece também no controle e foi preservado. A conclusão refere-se à geometria corporal, não à invisibilidade desse indicador externo.

Percurso rural: **1.091 frames / 70,786 s**, sem lacunas no contador renderizado, arquivos ausentes ou corrompidos, fontes estáveis. Foram inspecionadas 70 amostras cobrindo o trajeto, 49 frames consecutivos da emenda x=-430 e 33 do corredor da floresta, além das fotos em 1080p. Nesses recortes, sem buracos, mar atravessando o chão, alternância entre pisos ou vegetação invadindo a faixa de circulação. [Revisão completa e limites](../../evidence/fishing-relocation-session-144656-7386378/visual-review.md), [integridade/análise](../../evidence/fishing-relocation-session-144656-7386378/frame-analysis.json), [vídeo com os intervalos registrados](../../evidence/fishing-relocation-session-144656-7386378/route-timestamped.mp4). A inspeção por amostras e recortes consecutivos não equivale à reprodução humana integral de todos os frames; permanece essa limitação, sem extrapolar para chuva/noite ou iluminação global.

As primeiras tentativas de Main foram interrompidas por inferências inválidas em conteúdo concorrente do fliperama. Correção de integração estritamente local: `action`, `left` e `right` de `activities/arcade/ArcadeScreen.gd` passaram a declarar `String`; `x` de `world/places/arcade/ArcadeFacade.gd` passou a declarar `float`. Expressões, interface e comportamento foram preservados. Outros dois erros concorrentes de tipagem foram corrigidos por suas próprias sessões. As tentativas com erro não são evidência aprovada; o [check-only final das dependências do Main](../../evidence/park-countryside-parse-final.log) passou sem erro. Na revisão rural foi removida a segunda pele do chão: o material da floresta passa a ocupar a própria superfície física nativa, evitando sobreposição de pisos separados por 1 mm.

## Comparação de desempenho

Baseline capturado antes das alterações de produto, com fontes congeladas: [relatório bruto](../../evidence/park-countryside-before-118312-6547764/report.json), [auditoria de processos](../../evidence/park-countryside-before-processes.jsonl). RTX 4060 Laptop, Mobile/Vulkan, 1920×1080, limite normal de 144 FPS e VSync, clima seco, horário inicial 0,45. Câmeras relativas a cada local e janelas de 30 segundos, após aquecimento; screenshots fora da amostragem. Alvo provisório: 60 FPS / 16,67 ms; aumento de p95/p99 acima de 5% exige investigação.

| Janela anterior | FPS | p50 / p95 / p99 (ms) | Máximo (ms) | Frames >33,3 / >66,7 ms |
| --- | ---: | ---: | ---: | ---: |
| Parque, câmera de jogo | 143,94 | 6,984 / 10,319 / 13,138 | 32,132 | 0 / 0 |
| Parque, vista geral | 143,99 | 6,078 / 10,158 / 12,948 | 18,036 | 0 / 0 |
| Pesque-pague, entrada | 143,97 | 6,961 / 8,734 / 11,627 | 16,328 | 0 / 0 |
| Pesque-pague, vista geral | 144,01 | 6,953 / 8,678 / 11,610 | 12,378 | 0 / 0 |

A primeira chegada ao parque no baseline teve pico de **171,685 ms**, dois frames >33,3 ms e um >66,7 ms; essa amostra de admissão é separada das janelas estáveis. Na primeira janela a população ambiente cresceu de 14 para 40 pessoas; depois permaneceu em 40 na vista do parque. No lago antigo havia quatro pedestres, sete veículos e cinco pescadores, com o parque ainda residente. A transferência muda intencionalmente a vizinhança e o conjunto residente; a comparação não isola causalidade de cada objeto e não certifica carga máxima de trânsito.

Fotos anteriores: [parque](../../evidence/park-countryside-before-118312-6547764/park_overview.png), [lago](../../evidence/park-countryside-before-118312-6547764/fishing_overview.png).

### Execução final concorrente — desempenho não aprovado

A [execução com o produto final](../../evidence/park-countryside-after-188984-6034472/report.json) terminou com fontes estáveis, mas **56 dos 64 snapshots de processos registraram outro Godot**. Começou sem concorrência; outras sessões abriram jogos e capturas depois. [Auditoria](../../evidence/park-countryside-after-processes.jsonl). Os números abaixo descrevem o que foi observado e **não são um A/B válido para aprovar desempenho ou atribuir regressão/ganho às alterações**.

| Janela concorrente final | FPS | p50 / p95 / p99 (ms) | Máximo (ms) | Frames >33,3 / >66,7 ms |
| --- | ---: | ---: | ---: | ---: |
| Parque, câmera de jogo | 143,71 | 6,963 / 10,400 / 13,166 | 40,862 | 2 / 0 |
| Parque, vista geral | 143,96 | 6,099 / 10,192 / 12,958 | 17,546 | 0 / 0 |
| Pesque-pague, entrada | 143,95 | 6,959 / 8,628 / 12,002 | 16,276 | 0 / 0 |
| Pesque-pague, vista geral | 144,02 | 6,950 / 8,629 / 11,889 | 15,122 | 0 / 0 |

Na admissão, pico do parque **40,880 ms** e do lago **197,828 ms** (um frame >66,7 ms). O lago agora é carregado separadamente do parque; no baseline ambos já conviviam no conjunto residente. Esse pico continua como ponto a medir sem concorrência, não como melhora ou regressão atribuída. População final: parque com 40 pessoas ambiente, 11 carros e quatro palhaços, sem pescadores; lago com zero pedestres ambiente, quatro carros e cinco pescadores, parque/palhaços descarregados. A simulação não foi congelada.

Foi feita **uma reprise final com proteção contra concorrência**, aguardando 15 segundos sem Godot. Outra sessão abriu o motor durante essa tentativa; somente a fixture própria foi encerrada, sem fechar processos alheios. [Log parcial](../../evidence/park-countryside-isolated.log), [auditoria da interrupção](../../evidence/park-countryside-isolated-processes.jsonl). Não houve janela final isolada completa. Entre baseline e final, também houve alteração concorrente de `FullSession.gd`; os demais hashes alterados correspondem às áreas desta tarefa. **Comparação isolada de frame time e aprovação de desempenho permanecem pendentes.** Não foram iniciadas repetições adicionais sem mudança dessa condição externa.

Fotos finais reais, mesmas câmeras relativas do baseline: [parque ampliado](../../evidence/park-countryside-after-188984-6034472/park_overview.png), [lago no bosque](../../evidence/park-countryside-after-188984-6034472/fishing_overview.png), [entrada do lago](../../evidence/park-countryside-after-188984-6034472/fishing_entry.png). Os FPS impressos nas fotos não substituem as amostras nem a ressalva de concorrência.

## Limites de escopo

As evidências anteriores de Umbra e dos cosméticos estão no [relatório original](amusement-park-20261007.md). Esta ampliação não encerra a pendência de observação temporal integral daquele interior, nem certifica todos os horários, clima, dispositivos Android ou desempenho global do jogo. A cobertura final desta alteração é restrita aos percursos e estados explicitamente registrados neste relatório. Funcionalidade, física e oclusão dirigidas concluídas; pendentes o A/B isolado de desempenho e a reprodução humana integral das sequências temporais.
