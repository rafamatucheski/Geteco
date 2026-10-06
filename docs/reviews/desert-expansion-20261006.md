# Expansão ambiental do deserto — 6 de outubro de 2026

Implementação do pedido de acrescentar lugares antigos afastados, ferrovia abandonada, segredos, rochas e animais, com três agentes dedicados a relevo, ruínas e ecologia. Integração e validação realizadas no Main do Godot 4.7.2 .NET, com `Harbor.csproj` compilado.

## Conteúdo integrado

| Conteúdo | Localização aproximada X/Z | Comportamento |
|---|---|---|
| Quatro dunas baixas | -25 / -622 | Relevo de até 2,1 m, com malha física correspondente |
| Leito seco sinuoso | -650 / -1080 | Margens erodidas, solo rachado e marcas antigas de pneus |
| Salina | -790 / -1420 | Contorno irregular e crosta rachada sobre o terreno |
| Arco natural | -790 / -690 | Abertura física livre de 16 m de largura e 7,4 m de altura |
| Coluna erodida, basalto e pedra equilibrada | Arredores do arco | Silhuetas e colisões próprias |
| Ferrovia abandonada | X -1370 a -430, Z próximo de -550 | 940 m, dormentes, trechos de ferro faltantes, ferrugem e postes quebrados |
| Estação antiga | -1100 / -585 | Ruína aberta, plataforma junto à ferrovia e rampa de acesso |
| Mina desativada | -1400 / -1080 | Pórtico, equipamento, vagonete e trilhos curtos |
| Vagão descarrilado | -872 / -550 | Carga caída com esconderijo |
| Caminhonete abandonada | -650 / -580 | Carcaça e maleta escondida |
| Flora | Distribuição esparsa fora de acessos | Cactos arredondados, palmas, agaves, arbustos e árvores secas |
| Fauna | Oito territórios fixos | Lebres e lagartos em movimento, ativados por proximidade |
| Vento | Três áreas | Dois arbustos rolantes e redemoinho de poeira intermitente |

Os quatro esconderijos usam a interação contextual existente. Pagam R$ 950, R$ 1.650, R$ 1.250 e R$ 700 uma única vez. O estado `desert_discoveries` e os recibos da economia persistem no save; os achados não avançam a campanha. O bônus normal `first_grand` acrescenta R$ 50 quando aplicável, sem fazer parte das quatro recompensas.

Não foram criadas fachadas com textos explicativos, novas fontes de luz ou cenas interiores fechadas. A estação e a mina são ruínas abertas no mundo. As aves e o áudio regional já existentes continuam presentes.

## Integração e custo

Os módulos ficam em `world/desert/expansion` e `runtime/desert/expansion`. `DesertRegion` cria o relevo durante a admissão física do chunk, antes da decoração adiada, e distribui ruínas/flora pela fila de construção existente. Os sólidos, malhas e decorações são liberados com o chunk. Reservas impedem que a distribuição anterior de objetos invada os novos marcos e seus acessos.

O relevo prepara seus recursos durante a tela de carregamento: 28 células candidatas, das quais 18 contêm geometria. Templates `PackedScene` reutilizam malhas e formas físicas imutáveis; a liberação dos nós do mundo preserva esses recursos para a próxima visita. O cache aceita no máximo 32 células por provedor e dois provedores, com referências fracas e descarte de provedores destruídos. Callables customizados usam o gerador original. Não há novo processamento por frame no relevo.

A flora estática é agrupada por chunk. Os animais compartilham malhas; a lógica de decisão e obstáculos roda a 4 Hz, com movimento físico interpolável. A ecologia suspende processamento e visibilidade em interiores e quando a região é liberada. O redemoinho reutiliza o material de poeira existente.

As alterações concorrentes no restante do deserto, inclusive locais antigos e conteúdo ao sul, foram preservadas. Não há alteração de progressão da ponte, missões da montanha, combate ou garagem do Maciota.

## Evidência funcional e física

Todos os runners usam saves isolados. Execuções do motor são serializadas por `D:/geteco/artifacts/runtime-queue/Run-DesertCheck.ps1` e registram eventual sobreposição de processos. Nenhum resultado headless é usado para aprovar FPS ou aparência.

- `test_desert_expansion_landforms.gd`: 36 verificações e 355 raios físicos aprovados (`expansion-landforms-2`), incluindo correspondência entre relevo e colisão, polígonos, inclinação, abertura do arco e travessia da borda da duna com um corpo físico nas dimensões do Bison.
- `test_desert_discoveries.gd`: 199 verificações aprovadas (`expansion-discoveries-4`), incluindo idempotência, restauração de recibos, carteira cheia, personagem morto, plataforma/rampa, espaçamento em relação aos trilhos, restrição dos metadados de degrau aos trilhos e malha física contínua do lastro.
- `desert_expansion_relic_depth.gd`: 157 verificações aprovadas. Colisão de cápsulas de jogador/NPC, acessos aos quatro achados e profundidade nativa com controles positivos. Evidência: `evidence/desert-expansion-20261006/relic-depth-1`.
- `test_desert_expansion_admission.gd`: oito verificações aprovadas. A colisão elevada existe antes de concluir a decoração, inclusive após liberar e reconstruir o chunk (`expansion-admission-3`, já com cache).
- `test_desert_expansion_landforms_cache.gd`: 12 verificações aprovadas (`expansion-landform-cache-1`). Compara as 28 células com o gerador original, incluindo vértices, normais, cores, transformações, colisões e metadados. Também verifica reutilização dos recursos, ausência de nova geração na reconstrução, isolamento entre provedores e limpeza de referências expiradas.
- `desert_expansion_session.gd`: coleta por interação real, rejeição de repetição, ocultação do conteúdo, gravação em disco, destruição do Main e recarga a frio preservaram marcadores e saldo R$ 4.600. Travessia do arco e duna, presença de lebre/lagarto, vento e suspensão/retorno da ecologia na entrada/saída do banco também passaram. Registro `evidence/desert-expansion-session-87124-5311015/report.json`: 74 checagens, com duas falhas referentes à travessia dos trilhos antes da correção.
- Revalidação dirigida dos trilhos: sete verificações aprovadas após separar o corpo físico baixo do ferro e habilitar o degrau já existente dos pedestres. Caminhada atravessou ambos os trilhos sem reposicionamento; `evidence/desert-expansion-session-156816-5447452/report.json`. Móveis e vagonetes continuam sólidos e não escaláveis.
- `desert_expansion_drive.gd`: 36 verificações aprovadas e fontes estáveis em `evidence/desert-expansion-drive-94056-5570522/report.json`. Bison com entrada analógica normal, sem invulnerabilidade e sem escrever pose/velocidade durante a condução: 57,2 m subindo/descendo a duna, 130,1 m pelo leito seco e 30,0 m cruzando os trilhos. Foram 2.032 raios sob o casco, sem apoio ausente, quedas, contatos laterais ou perda de saúde. Duna e leito atravessaram limites reais de chunks. Embarque e desembarque normais também passaram.
- `desert_expansion_gallery.gd`: 26 verificações aprovadas e 22 capturas de 11 locais no Main real, após o carregamento de cada entorno. `evidence/desert-expansion-gallery-80264-6383982` contém pares com câmera normal e câmera de inspeção. As vistas de inspeção não alteram a câmera do jogo.
- Galeria dirigida final: oito verificações aprovadas em `evidence/desert-expansion-gallery-86840-7034220`, com quatro novas capturas de vagão/caminhonete examinadas. O fixture agora posiciona o jogador no acesso real pelo chão; as primeiras fotos desses dois objetos usavam um raio sobre o centro do objeto e colocavam o ator no teto/carga. Era posicionamento do runner, não falha de spawn do jogo. Para esses dois locais, as fotos válidas são as da galeria dirigida final.

Os testes de condução identificaram duas falhas reais e direcionaram as correções: a borda constante de 16 mm da duna e a face vertical do ferro. A borda das dunas/leito agora começa na altura exata do terreno; a ferrovia ganhou lastro contínuo, com rampas laterais e nas pontas, preservando os trilhos sólidos. Os registros originais foram mantidos (`desert-expansion-drive-63276-5713684` e `desert-expansion-drive-49240-5194125`); o resultado aprovado é o da execução posterior acima.

A sessão gravou 4.126 quadros renderizados durante os percursos, com timestamps e IDs de frame. Quadros representativos do arco, duna, animais e vento foram examinados. Essa gravação usa cap de 30 FPS e captura em disco por frame, portanto **não constitui benchmark** nem certificação global de ausência de flicker. A aprovação de profundidade das ruínas vem do teste específico, separadamente da colisão.

Vistas de inspeção capturadas no Main, com câmera afastada apenas pelo runner:

![Mina desativada](../../evidence/desert-expansion-gallery-80264-6383982/mine-overview.png)

![Arco natural](../../evidence/desert-expansion-gallery-80264-6383982/desert_natural_arch-overview.png)

## Desempenho

Meta provisória: 60 FPS / 16,67 ms. Hardware desta máquina: RTX 4060 Laptop e i7-13650HX, Vulkan Mobile, 1280×720; backend C# compilado. A configuração solicitada de população é 24, mas nos pontos remotos medidos havia **zero pedestres de mundo e um veículo**. O caso de ecologia tinha um animal ativo. Esses resultados não representam uma cidade com 24 NPCs em cena.

O comparador `tests/measure/measure_desert_expansion.gd` mede 3 s de primeira visita, 10 s de aquecimento e 30 s estabilizados por cenário. Estação/dunas/leito seco/salina/ecologia de dia e mina à noite. Preserva intervalos brutos, p50/p95/p99, máximo, contagem de frames longos, câmera, população, hashes de fontes e capturas reais. O modo `--without-expansion` desliga a geração de relevo, ruínas, flora e fauna por metadado de debug; não altera saves nem opções do jogador. O componente de interação dos achados permanece instalado nos dois lados: o par isola o custo do cenário/fauna e não mede separadamente todo o novo runtime de interação. A checagem com limite normal usa 60 FPS e VSync.

O baseline anterior à integração (`evidence/desert-expansion-measure-48368-5227784/report.json`) foi preservado, mas não substitui o par final equivalente: outros trabalhos do deserto entraram depois. Seu indicador bruto de fontes instáveis se refere a dois arquivos novos ainda não referenciados naquele momento. A tentativa anterior com janela minimizada é inválida e não entra no comparativo.

### Custo da expansão

Par completo sem limite de FPS: `evidence/desert-expansion-measure-3668-6041404/report.json` sem expansão e `evidence/desert-expansion-measure-69596-6159725/report.json` com expansão. Ambos têm fontes estáveis e idênticas entre si, sem sobreposição de outro jogo. Os valores abaixo são p95 / p99 dos intervalos renderizados, em ms:

| Cenário | Sem expansão | Com expansão |
|---|---:|---:|
| Estação de dia | 1,872 / 2,436 | 2,177 / 2,848 |
| Dunas de dia | 1,827 / 2,425 | 1,819 / 2,257 |
| Leito seco de dia | 1,817 / 2,404 | 1,842 / 2,257 |
| Salina de dia | 1,894 / 2,532 | 1,933 / 2,463 |
| Mina à noite | 1,837 / 2,377 | 1,925 / 2,454 |
| Ecologia de dia | 1,764 / 2,223 | 1,892 / 2,417 |

Todos os trechos estabilizados desse par ficaram abaixo de 8 ms. Os draw calls na estação passaram de 108 para 118; na ecologia, de 114 para 118. Esses resultados antecedem o cache de recursos de relevo.

O sinal acima de 5% na estação/ecologia motivou uma confirmação finita com fontes equivalentes: `desert-expansion-measure-84852-5350291` sem expansão e `desert-expansion-measure-120056-5788575` com expansão. Na estação, p95 foi de 1,537 para 1,790 ms (**+0,253 ms / 16,5%**) e p99 de 1,936 para 2,291 ms. Na ecologia, p95 foi de 1,639 para 1,795 ms (**+0,156 ms / 9,5%**) e p99 de 2,119 para 2,234 ms. Não houve quadros acima de 33,3 ms nos períodos estabilizados. A regressão local de custo permanece registrada; a folga frente a 16,67 ms não constitui aprovação de ausência de regressão.

Uma repetição intermediária (`174236-5480435`) não foi emparelhada com o baseline seguinte, pois uma alteração concorrente de câmera ocorreu entre eles. O par de confirmação acima já usa a mesma versão da câmera.

### Primeira visita e cache

Par com conteúdo idêntico, alternando somente o bypass de cache: `desert-expansion-measure-140308-5238708` e `desert-expansion-measure-90244-5712030`. Fontes idênticas e estáveis; nenhuma sobreposição de jogo.

| Cenário | Admissão síncrona sem/com cache | Maior quadro na primeira visita sem/com cache |
|---|---:|---:|
| Dunas | 53,997 / 0,672 ms | 67,428 / 56,752 ms |
| Leito seco | 29,491 / 0,604 ms | 34,447 / 7,989 ms |

As 28 células estavam preparadas antes da admissão. O cache retirou a geração de geometria desse caminho síncrono, mas **permaneceu um pico de 56,752 ms na primeira visita às dunas**. O dado não identifica sozinho a causa desse quadro residual.

O log de pré-aquecimento global das regiões marcou 13,422 s sem cache e 16,708 s com cache nesse par. É um custo observado de carregamento, não uma medição isolada do novo prewarm; não há alegação de carregamento mais rápido ou de memória sem custo.

Nesse par, p95/p99 estabilizados subiram de 1,951/2,903 para 2,564/3,703 ms nas dunas e de 1,912/2,499 para 2,383/3,341 ms no leito. Não se atribui automaticamente essa diferença ao cache nem se declara neutralidade de custo.

A confirmação dirigida (`desert-expansion-measure-92644-6330795`) teve fontes estáveis e nenhuma sobreposição de jogo, mas **não serve como confirmação A/B equivalente**: alterações concorrentes em `DesertAmbientLife`, `DesertTerrainCamera` e `DesertTerrainMesh` entraram antes dela. O fixture também passou a incluir ecologia no modo cap, sem modificar os casos sem limite. Nessa versão posterior, a admissão continuou em 0,718/0,728 ms; o maior quadro de primeira visita foi 71,334 ms nas dunas e 11,328 ms no leito. p95/p99 estabilizados foram 3,610/4,753 e 3,545/4,602 ms, respectivamente. O pico de primeira visita e a comparação de custo estabilizado permanecem pendentes, sem novas rodadas abertas de tentativas.

### Limite normal e conclusão

`desert-expansion-measure-78636-8082688` executou o Main final com limite de 60 FPS e VSync. Fontes estáveis, sem outro jogo simultâneo, backend nativo e um animal ativo no cenário de ecologia:

| Cenário | FPS médio | p95 / p99 | Maior quadro estabilizado |
|---|---:|---:|---:|
| Estação de dia | 60,004 | 18,789 / 19,254 ms | 20,651 ms |
| Mina à noite | 60,004 | 18,801 / 19,161 ms | 20,486 ms |
| Ecologia de dia | 60,005 | 18,851 / 19,313 ms | 20,730 ms |

Não houve quadros acima de 33,3 ms nos períodos estabilizados. A média de 60 FPS não significa que todos os quadros ficaram abaixo de 16,67 ms. No período inicial da estação houve um quadro de 80,430 ms; a admissão síncrona nesse ponto foi 0,033 ms. Mina/ecologia não tiveram quadros iniciais acima de 33,3 ms nessa execução.

**Conclusão:** conteúdo integrado e percursos/interações validados nos cenários descritos. Performance **não aprovada como isenta de regressões**: permanece o aumento local confirmado de custo da estação/ecologia, a comparação estabilizada do cache sem confirmação equivalente e picos de entrada/primeira visita de até 80,430 ms nas execuções finais. A atribuição dos picos e o custo isolado do componente de interação exigem investigação própria; não há resultado de profiler que sustente atribuí-los a um único sistema. Não há aprovação global de performance, iluminação ou malha viária do jogo.
