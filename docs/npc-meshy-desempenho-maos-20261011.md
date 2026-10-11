# Desempenho das mãos do policial de terno

Continuação de [mãos do Dante](npc-meshy-maos-dante-20261011.md). O objetivo é recuperar a regressão medida sem simplificar mãos, punhos, textura, animação ou arma.

## Alteração

- `PoliceModel`: encerra a projeção iterativa do alcance somente quando o resultado é exatamente igual ao da iteração anterior; consulta a transformação mundial uma vez por solução. Reutiliza os centros constantes das projeções e as bases fixas da pega, preservando a ordem das operações e o arredondamento. Preserva cálculo imediato para disparos, contatos e rapel.
- `MeshyBodyRig`: propaga posições somente pelos seis ancestrais que alimentam os ajustes dos braços. Reutiliza as 13 transformações que a detecção de mudanças acabou de ler e as origens dos braços já calculadas, sem cache entre quadros. Conserva todas as bases, rotações e posições escritas no esqueleto. As demais posições intermediárias não tinham consumidores.
- Os controles A/B mantêm o algoritmo anterior disponível no mesmo processo, com a mesma geometria e o mesmo ritmo de animação.

O GLB V11 permanece byte a byte igual: SHA-256 `9615807B1BEA25C0DD4E6DA7DA5C46CD9D61DAD5FACB994DCF8074152F1CBFFF`. Não foram reduzidos vértices, triângulos, texturas, sombras, resolução ou frequência de atualização.

## Critérios e evidência

Godot 4.7.2 .NET, Vulkan/Forward Mobile, RTX 4060 Laptop, 1280×720. Meta provisória: 16,67 ms; confirmação relativa quando p95/p99 excedem 5%. Medições renderizadas sequenciais, sem outro Godot nem trabalho pesado do agente auxiliar. APPDATA/save isolados. VSync e limite de FPS desligados apenas nos processos de medição; probe separado usa configuração normal.

Raiz das evidências locais: `evidence/npc-meshy/hands-perf-20261011/`. As capturas e amostras brutas não são versionadas.

O profiler de scripts, separado do benchmark, identificou `MeshyBodyRig.sync` como maior custo próprio: 1.421,768 ms/74.520 chamadas, aproximadamente 19,08 µs por corpo e 0,458 ms por quadro com 24 corpos. `_body_weapon_targets` mediu 5,98 µs/chamada. Esses tempos são instrumentados e não substituem frame time renderizado (`profile.json`).

Um cache de morphs estáveis não mostrou ganho convincente; uma experiência com o laço de ossos em C# piorou o desempenho. Ambas foram removidas. A tentativa de conversão direta para quaternion também foi removida por não satisfazer a tolerância numérica escolhida. O código entregue mantém a decomposição original das rotações.

## Verificação de conservação

`test_police_hand_target_equivalence.gd` compara 1.323 pares: sete corpos, três armas, 21 estados e três transformações mundiais. Verifica alvos, frames das palmas, pesos de pega, arma local/mundial, muzzle, contatos, recoil e todas as poses mundiais dos ossos após IK real. No código final, diferença máxima **zero** (`equivalence-constants.log`), tolerância de 0,000001.

## Medições finais

**Estado da confirmação:** o A/B intercalado final confirmou ganho modesto contra as mesmas mãos V11 sem otimização: +2,1%/+2,3% de FPS médio e -3,3%/-1,9% no p95, em duas janelas. O p99 variou -0,9%/+0,5%. Isso aprova a melhoria local medida, **não comprova recuperação integral contra o corpo antigo**. As comparações por blocos longos permaneceram variáveis; seus resultados são preservados abaixo.

### Recuperação contra o corpo anterior

`constant-recovery-stage/ab-police-24.json`, seis rodadas A/B/B/A/A/B de 24 policiais. Ambos os GLBs passam pelo mesmo importador sem LOD; o controle usa o corpo anterior sem as novas mãos e sem os atalhos de pose/projeção. O revisado usa a geometria V11 intacta e a otimização final.

| Rodada | Condição | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms |
|---|---|---:|---:|---:|---:|---:|
| 0 | corpo anterior | 462,45 | 2,106 | 2,463 | 2,789 | 7,409 |
| 1 | mãos V11 otimizadas | 442,18 | 2,212 | 2,540 | 2,830 | 7,185 |
| 2 | mãos V11 otimizadas | 440,95 | 2,218 | 2,544 | 2,877 | 7,721 |
| 3 | corpo anterior | 457,48 | 2,136 | 2,458 | 2,785 | 7,759 |
| 4 | corpo anterior | 465,07 | 2,102 | 2,421 | 2,722 | 7,633 |
| 5 | mãos V11 otimizadas | 278,58 | 3,320 | 6,943 | 9,654 | 23,265 |

Medianas das três rodadas de cada condição: p50 **2,106→2,218 ms (+5,3%)**, p95 **2,458→2,544 ms (+3,5%)**, p99 **2,785→2,877 ms (+3,3%)**. FPS médio mediano **462,45→440,95 (-4,6%)**. A geometria nova continua tendo custo; o resultado recupera a margem de p95/p99, não demonstra custo zero. Todas as rodadas mantiveram 514 draw calls e zero quadros acima de 33,3/66,7 ms. A última rodada mais variável foi preservada; não se afirma ausência de variação temporal.

O registro original reprovado tinha +11,7%/+14,5% em p95/p99. Candidatos intermediários ainda falharam: atalhos de alvo isolados (`recovery-stage`), origens esparsas (`sparse-recovery-stage`) e reutilização de transformações sem as constantes (`final-recovery-stage`). Eles não foram aprovados nem apagados. A amostra acima sucede a última alteração de código; não é repetição até obter passagem.

### Mesmas mãos antes/depois e cidade

Na Main, `final-main/ab-game.json` intercala ABBA/BAAB por quadro na mesma cidade viva; cada condição acumula pelo menos 30 segundos em cada uma de três janelas, depois de cinco segundos de aquecimento. IA, física, trânsito e despacho continuam ativos. O guard verifica os dois atores da fixture, com perfil de palma, a cada 0,5 s; contar qualquer policial na câmera poderia esconder a perda de um dos atores-alvo. Os timings de render podem refletir submissões anteriores e são diagnósticos, não uma decomposição exata do frame time.

| Janela | Condição | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms | Validade |
|---|---|---:|---:|---:|---:|---:|---|
| 0 | controle | 11,678 | 14,436 | 17,094 | 21,463 | 0 / 0 | válida |
| 0 | otimizado | 11,528 | 14,405 | 17,188 | 30,923 | 0 / 0 | válida |
| 1 | controle | 11,066 | 14,745 | 17,479 | 28,021 | 0 / 0 | inconclusiva |
| 1 | otimizado | 11,055 | 14,496 | 17,298 | 37,596 | 1 / 0 | inconclusiva |
| 2 | controle | 12,450 | 19,940 | 61,367 | 543,641 | 36 / 21 | inconclusiva |
| 2 | otimizado | 12,393 | 19,968 | 56,590 | 175,668 | 36 / 21 | inconclusiva |

Janela válida: FPS médio 95,53→97,06; p95 -0,2%, p99 +0,5%. Os corpos visíveis passaram de 52 para 54 no intervalo compartilhado; draw calls médios 943,135/943,088, CPU de render 1,879/1,883 ms e GPU 2,577/2,577 ms. Não houve regressão acima de 5% nessa janela, mas também não há ganho grande de FPS demonstrado na cidade. O p99 continua acima da meta absoluta de 16,67 ms.

Nas janelas 1 e 2, apenas um dos dois policiais originais permaneceu na população ativa. Ambas foram invalidadas, mesmo com a chegada de outros policiais. Houve picos grandes durante o crescimento da população até 69 corpos visíveis; não se isolou sua causa nesta tarefa. Os dados foram preservados e não se repetiu a Main até conseguir três passagens. **A comparação integrada tem uma janela válida e duas inconclusivas; isso não aprova estabilidade/performance global da cidade nem a chegada pelo despacho.** Carregamento, caminhada pela física, isolamento do save e presença do roteador C# foram verificados na Main renderizada.

### Confirmação com janela monitorada

A coleta `constant-stage` ficou presa ao esperar o próximo desenho com a janela minimizada (confirmado por `IsIconic` do Windows). Foi interrompida e descartada. O runner passou a encerrar com erro se a janela for minimizada; `visible-stage` detectou uma segunda minimização e também foi descartado. O usuário confirmou que manteria a janela aberta.

`three-way-final/ab-police-24.json` concluiu nove rodadas com esse guard: anterior/V11-controle/V11-otimizado, controle/otimizado/anterior, otimizado/anterior/controle. Mesma importação para os três controles, 5+30 s por rodada, 24 policiais e 514 draw calls. A versão sem atalhos compartilha a referência local do array de frames da palma com a otimizada, mas conserva os cálculos de projeção/cadeia anteriores.

| Condição | FPS médio mediano | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| Corpo anterior | 365,09 | 2,668 | 3,386 | 4,313 |
| Mãos V11 sem atalhos | 354,60 | 2,760 | 3,298 | 3,970 |
| Mãos V11 otimizadas | 357,71 | 2,697 | 3,561 | 4,387 |

São medianas dos três resultados por condição, não percentis de um conjunto agregado. Nesta confirmação, p95/p99 do otimizado ficaram **+8,0%/+10,5% contra o controle V11** e **+5,2%/+1,7% contra o corpo anterior**. O FPS médio mediano melhorou 0,9% contra V11, mas isso não aprova os percentis. Máximo de 411,680 ms no primeiro controle antigo, com um quadro >33,3/66,7 ms; as outras oito rodadas não ultrapassaram 33,3 ms. Todos os dados foram mantidos.

Durante essa coleta, uma amostra de processos mediu, em dois segundos, 2,27 s de CPU no Godot e 1,16+1,06 s em dois processos `claude`, além de 0,30 s em outro. Isso documenta concorrência e variação, **não prova que todo aumento veio dela**. Foi solicitada pausa dessas outras sessões antes de uma confirmação isolada. As mãos estão preservadas, mas a recuperação de desempenho ainda requer confirmação consistente.

### Após a pausa solicitada e correção do método

O usuário informou que pausaria as outras sessões. O build .NET passou novamente sem avisos/erros e não havia outro Godot. Ainda havia consumo dos processos Claude no início: 0,969/0,578/0,281/0,219 s de CPU em uma janela de dois segundos. Não se considerou a máquina totalmente isolada.

`paused-sessions-final/ab-police-24.json` repetiu uma única vez as nove rodadas para verificar a hipótese de interferência. Medianas: anterior 375,10 FPS / p95 3,410 / p99 4,702 ms; V11 sem atalhos 293,86 / 4,486 / 6,586; V11 otimizada 315,56 / 5,240 / 8,714. A divergência entre ganho médio e piora dos percentis continuou. Essa coleta não foi aprovada nem apagada.

Para reduzir a confusão entre variante e carga do computador em momentos diferentes, `measure_meshy_hand_interleaved.gd` alterna quatro combinações **quadro a quadro no mesmo grupo de 24 atores**, na mesma instância do motor: nenhum atalho, somente arma, somente cadeia, ambos. A sequência balanceada distribui as combinações pelo mesmo intervalo; cada tempo decorrido é atribuído à combinação aplicada no intervalo anterior. Foram definidos dois grupos de amostras, cinco segundos de aquecimento e pelo menos 30 segundos acumulados por combinação em cada grupo. A janela minimizada interrompe a execução. Não há mudança de malha, resolução, iluminação ou frequência produtiva. A coleta inteira levou cerca de quatro minutos em uma abertura do Godot.

Dados: `interleaved-stage/ab-police-24.json`, oito arquivos de amostras brutas e duas capturas. Todos mantiveram 514 draw calls.

| Janela | Combinação | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---|---:|---:|---:|---:|---:|---:|
| 0 | original | 292,10 | 3,088 | 5,654 | 7,923 | 68,648 | 2 / 1 |
| 0 | somente arma | 294,68 | 3,047 | 5,612 | 8,009 | 39,468 | 1 / 0 |
| 0 | somente cadeia | 294,38 | 3,046 | 5,565 | 7,946 | 64,379 | 2 / 0 |
| 0 | ambas | 298,17 | 3,012 | 5,466 | 7,848 | 53,523 | 3 / 0 |
| 1 | original | 331,44 | 2,796 | 4,346 | 6,614 | 11,495 | 0 / 0 |
| 1 | somente arma | 335,38 | 2,757 | 4,290 | 6,554 | 17,084 | 0 / 0 |
| 1 | somente cadeia | 335,41 | 2,761 | 4,280 | 6,634 | 11,950 | 0 / 0 |
| 1 | ambas | 339,02 | 2,723 | 4,262 | 6,650 | 18,693 | 0 / 0 |

As duas otimizações contribuíram e juntas apresentaram o melhor FPS médio/p50/p95 nas duas janelas. O p99 ficou dentro da margem de 5% em ambas. Houve picos em todas as combinações na primeira janela: esta medição não comprova eliminação de stutter. A conclusão é **ganho pequeno e consistente sobre o runtime V11**, com conservação visual já comprovada. A comparação integrada da Main anterior continua limitada a uma janela válida; não há aprovação global da cidade ou prova de recuperação integral do custo da geometria nova.

Os testes funcionais e as 36 comparações de imagem não foram repetidos: nenhum código produtivo mudou nesta confirmação. Somente o método de medição foi acrescentado. Reiniciar o motor é reservado a isolamento necessário; as combinações de desempenho compatíveis são medidas juntas.

## Capturas e testes funcionais

`compare-m4/` e `compare-smg/`: frente, lado e lado oposto, em mira, busca/inserção/acionamento da recarga, corrida e repouso. **36 pares antes/depois idênticos pixel a pixel**, com pose, câmera e luz congeladas. Registro `image-comparison.json`. Foram inspecionadas diretamente frente/lado da mira e recarga, além da pega da SMG. O GLB continua com o SHA-256 inicial. Isso comprova conservação visual nos estados capturados, não FPS.

Build .NET: zero avisos/erros. O lote `suite-2026-10-11_135301_905-58a9b211b4ba4b3bb55c49955bcc7a3c.json` passou 8/9: admission, ponte, contatos/morte, direção C#, fechamento de combate, equipamento, catálogo policial e regiões. O runner registrou alterações de fontes de outras sessões durante o lote; os arquivos da otimização ficaram congelados. Nesta execução, regiões encerrou sem os vazamentos registrados anteriormente.

O probe `normal-main.log`/`normal-main/fixture.png` também passou com as configurações normais de VSync/limite de FPS: carregamento real, caminhada pela física, dois policiais importados visíveis e roteador C# ativo. Esse probe não mede FPS.

Balística executou suas 107 verificações, mas falhou inicialmente porque seu estado simplificado não implementava `owns_weapon`, agora consultado pelo visual da katana em Gameplay. A fixture passou a declarar que o alvo não possui arma. O encerramento então revelou cinco streams/14 playbacks de áudio ainda retidos: dois frames headless não davam ao mixer tempo de liberar as referências. A fixture aguarda 0,1 s depois de destruir o mundo, sem mudar as asserções de balística. O runner dirigido passou 1/1 (`suite-2026-10-11_140533_037-72b53af22a8249cf9f61ab6fe0fc611c.json`), incluindo encerramento sem erros. Não houve alteração de áudio ou katana produtivos nesta tarefa.
