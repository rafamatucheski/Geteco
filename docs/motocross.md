# Motocross Vértice

Circuito fechado no terreno rural a leste da Vértice, em Harbor. Entrada do pátio: `(-224, 0.15, -37)`, indicada no mapa. A pista mede aproximadamente 402 m, chega a 17 m de elevação e tem mesas de salto, ondulações e curvas inclinadas. O pórtico acompanha a direção da largada.

## Jogar

Interagir com E no pátio para inscrição ou aluguel de treino (R$ 35). W/S aceleram/freiam e dão ré; A/D viram; espaço freia. Na largada, W controla o giro; no ar, W/S inclinam a moto para o pouso. Os saltos vêm da velocidade e do relevo. E abre a desistência na corrida ou devolve/desmonta depois de parar no treino/moto própria.

| Dificuldade | Inscrição | Vitória: total devolvido | Lucro | Voltas | Rivais |
|---|---:|---:|---:|---:|---:|
| Iniciante | R$ 100 | R$ 140 | R$ 40 | 2 | 3 |
| Intermediário | R$ 200 | R$ 280 | R$ 80 | 2 | 4 |
| Avançado | R$ 350 | R$ 490 | R$ 140 | 3 | 5 |
| Expert | R$ 500 | R$ 700 | R$ 200 | 3 | 5 |

Vencer libera o nível seguinte. A primeira vitória no intermediário dá uma moto própria, retirada no pátio. Derrota, desistência e abandono ao fechar o jogo perdem a inscrição; o débito é salvo antes de começar. Transações têm identificadores únicos para impedir prêmio duplicado. Saves antigos sem motocross continuam válidos.

Depois de escolher a prova ou o treino, o menu compara três motos antes da confirmação do pagamento:

| Modelo | Comportamento | Aceleração | Velocidade máxima seca |
|---|---|---:|---:|
| Trilha 250 (laranja) | Equilibrada; maior final | 8,5 m/s² | 64,8 km/h |
| Faísca 250 (vermelha) | Arranca mais rápido, vira menos | 11,5 m/s² | 61,9 km/h |
| Víbora 125 (azul) | Vira e segura melhor nas curvas, menor final | 7,7 m/s² | 60,5 km/h |

Todos têm a mesma inscrição/aluguel. Os atributos modificam a física de aceleração, direção e aderência; o teto real também depende do terreno e da chuva. A moto própria mantém no save o modelo usado na vitória que a desbloqueou. Saves anteriores recebem a Trilha 250.

A prova começa com uma tomada de 2,4 s mostrando o piloto montando; só depois começa a contagem de largada. Os adversários ficam parados, a pausa congela a montagem e desistir/restaurar o mundo encerra a câmera temporária.

Até três pilotos circulam como ambientação ao chegar a 150 m do centro do parque. Eles deixam de simular além de 180 m, ao sair da região ou quando o circuito descarrega. Usam física, quedas e rastros; não geram inscrições ou prêmios. Saem imediatamente quando o jogador inicia prova, aluga ou monta sua própria moto, e retornam quando a pista fica disponível.

O controle valida 32 checkpoints em sequência por volta. Sair da pista retorna ao último checkpoint com tempo de recuperação. Os adversários usam a mesma física do jogador: quedas causam dano e os pilotos se levantam, caminham até a moto e remontam. Na chuva o solo escurece, ganha poças e respingos, e perde aderência; seca gradualmente. Rastros usam um anel limitado a 2.048 marcas, com até seis conjuntos de partículas.

## Dia de corrida (29/09)

**Largada com grade.** Os pilotos alinham numa fila única atrás da grade de largada (6 barras articuladas, 1,7 m entre raias, 18 m antes da linha de chegada). Durante a contagem, W/acelerador sobe o giro e soltar faz cair; o cartão mostra a faixa verde (55–85%). A grade cai num instante sorteado dos últimos 0,6 s dos 3 s, então é preciso *segurar* o giro, não cronometrar:

| Giro na queda da grade | Resultado |
|---|---|
| Na faixa verde | **Holeshot**: aceleração ×1,75 por 1,5 s |
| Acima de 93% | **Empinou**: a frente sobe (pivô no pneu traseiro) e a aceleração cai a 35% por 0,8 s |
| Abaixo de 30% | **Largada lenta**: aceleração ×0,55 por 1,1 s |
| Entre as faixas | Largada normal |

Rivais sorteiam o próprio resultado; no Expert têm 42% de holeshot e 8% de largada lenta (Iniciante: 18% e 28%).

**Pouso.** Com mais de 0,38 s no ar, o pouso é avaliado pela diferença entre a inclinação da moto e a da rampa tocada. No ar, W inclina a frente e S a traseira; o HUD indica `▼ FRENTE (W)`, `▲ TRÁS (S)` ou `● ALINHADO`. Diferença até 0,14 rad é **pouso perfeito** (+12% de velocidade máxima e aceleração ×1,5 por 1,3 s); acima de 0,50 rad é **pouso duro** (−15% de velocidade). Sem mexer, os pousos ficam entre 0,27 e 0,46 rad: limpos, sem bônus nem punição. A inclinação no ar do jogador agora age direto na atitude; antes ela era amortecida duas vezes (~0,24 rad/s) e não mudava o pouso. A IA não inclina e mantém o comportamento anterior.

**Cronometragem.** Cada passagem pelos 32 pontos de controle é registrada. O HUD mostra a diferença para o piloto à frente (ou a vantagem sobre o de trás) medida no último ponto em comum, e anúncios de volta, última volta, ultrapassagem (só depois de 0,7 s de posição mantida), pouso e saída da pista. Os rivais têm etiqueta com posição e nome. Ao final aparece um cartão de classificação (não modal, 9 s) com diferenças, voltas de atraso, melhor volta, recorde, holeshot e pousos perfeitos.

**Recorde da pista.** A melhor volta, de prova ou de treino, fica no save (`best_lap`, validado entre 15 s e 3.600 s; saves antigos continuam válidos). O treino com moto alugada ou própria agora é cronometrado a partir da primeira passagem pela linha. O menu e o placar mostram o recorde.

**Local.** Estacas e fita vermelha e branca contornam a pista; as estacas ficam mais próximas nas curvas para que a fita reta nunca invada a largura de pilotagem. Fardos de feno cercam o escape das curvas mais fechadas. No lado interno da reta final, uma arquibancada de madeira de três degraus, voltada para a pista e para a câmera, recebe cinco torcedores sentados; atrás dela, o placar da direção de prova mostra largada, volta e líder, treino ou recorde. Faixas de patrocínio ficam na reta, e o pátio ganhou uma tenda de mecânico com bancada, carrinho de ferramentas, galões e rodas.

## Cenário

Motos usam carenagens afuniladas, banco estreito, paralamas curvos, pneus com cravos, aros e raios, quadro, suspensão e escapamento. As geometrias são compartilhadas entre modelos. Pilotos têm capacete fechado com pala e óculos, roupa ajustada ao corpo, luvas, proteções e botas. Braços e pernas articulados mantêm mãos no guidão e solas nas pedaleiras durante direção, inclinação e saltos; as mãos se soltam durante queda e recuperação.

O pé fica apoiado na pedaleira enquanto o cano da bota acompanha a canela, com sobreposição entre as peças. A postura reage à frenagem, ao pouso e aos contatos laterais.

Rivais planejam curvas e ultrapassagens oito vezes por segundo, mantendo a física e o controle suave na frequência do motor. Cada piloto varia o traçado e o ritmo, acelera nas retas, freia antes das curvas e mantém o lado escolhido durante uma tentativa de ultrapassagem. Os pilotos de ambientação usam a mesma lógica. Encostadas leves provocam deslocamento e desequilíbrio; colisões fortes dependem da velocidade relativa e podem derrubar os dois pilotos, que se recuperam pelo ciclo existente. Não há sorteio de quedas.

Casinha fechada com atendimento externo, três motos estacionadas, mesa e três pilotos bebendo, árvores com troncos sólidos fora da faixa de corrida e três barcos com espectadores na água. Torre central com quatro refletores, ativada por horário e proximidade. Não há interior acessível na casinha.

O terreno do parque e da mata usa a mesma textura em coordenadas do mundo. A borda do relevo termina na altura do chão e mistura o barro à grama. Locadora, mesa, estacionamento e acesso compartilham uma clareira contínua, com bordas irregulares e transição suave, sem plataformas retangulares isoladas. O piso da clareira tem colisão triangulada acompanhando a superfície visível; a varanda de madeira continua sendo uma estrutura elevada. A vegetação rasteira é agrupada espacialmente, com alcance de 100 m e sem sombras adicionais.

Os dez espectadores/atendente usam o CivilianModel padrão, com roupas, postura sentada e mãos articuladas. Tiros próximos provocam proteção ou fuga limitada ao piso disponível; impactos causam dano e reação. Barcos mantêm seus passageiros dentro do convés. Motos estacionadas reagem ao impacto, e pilotos ativos reduzem o ritmo ao ouvir disparos próximos; um impacto direto pode derrubá-los. As conexões com combate são removidas no descarregamento.

As rampas conservam o impulso vertical na crista. A postura acompanha a subida, a trajetória no ar e a compressão ao aterrissar. O HUD de corrida concentra posição, volta e cronômetro no topo, com velocidade, estado do salto/frenagem e integridade no canto inferior direito.

## Validação

Scripts dedicados: `tests/test_motocross_progress.gd`, `tests/test_motocross_bike.gd`, `tests/test_motocross_session.gd`, `tests/test_motocross_scenery.gd` e `tests/test_motocross_raceday.gd` (apoio físico da decoração, grade, largada, pouso e recorde). Capturas de revisão: `tests/capture/capture_motocross_raceday.gd`; A/B de desempenho da decoração: `measure_motocross.gd --without-raceday`. Integração usa `Main.tscn` e `--no-save`, preservando o save do usuário. Medições renderizadas e capturas: `tests/measure/measure_motocross.gd`, artefatos em `evidence/motocross/`.

O orçamento provisório de referência é 60 FPS / 16,67 ms. Comparativos de desempenho são diagnósticos, pois outras sessões Godot do usuário estavam abertas; as amostras e limitações ficam registradas junto das evidências. Testes headless não certificam FPS.

Revisão de terreno, NPCs e saltos (28/09): cenário 24/24, incluindo 154 pontos de apoio e travessia física entre as áreas; combate integrado na Main 9/9; espectadores 15/15; lançamento físico 4/4 (0,49 m de afastamento do solo, 0,45 s no ar e compressão ao pousar). O teste de grupos de motos passou 20/20; árvores, 883/883; regressões da garagem, 84/84. Evidências finais e limitações de desempenho em `evidence/motocross/README.md`. As entradas abaixo também registram revisões anteriores.
