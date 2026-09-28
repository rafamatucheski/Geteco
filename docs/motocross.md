# Motocross Vértice

Circuito fechado no terreno rural a leste da Vértice, em Harbor. Entrada do pátio: `(-224, 0.15, -37)`, indicada no mapa. A pista mede aproximadamente 402 m, chega a 17 m de elevação e tem mesas de salto, ondulações e curvas inclinadas. O pórtico acompanha a direção da largada.

## Jogar

Interagir com E no pátio para inscrição ou aluguel de treino (R$ 35). W/S aceleram/freiam e dão ré; A/D viram; espaço freia. Os saltos vêm da velocidade e do relevo. E abre a desistência na corrida ou devolve/desmonta depois de parar no treino/moto própria.

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

## Cenário

Motos usam carenagens afuniladas, banco estreito, paralamas curvos, pneus com cravos, aros e raios, quadro, suspensão e escapamento. As geometrias são compartilhadas entre modelos. Pilotos têm capacete fechado com pala e óculos, roupa ajustada ao corpo, luvas, proteções e botas. Braços e pernas articulados mantêm mãos no guidão e solas nas pedaleiras durante direção, inclinação e saltos; as mãos se soltam durante queda e recuperação.

O pé fica apoiado na pedaleira enquanto o cano da bota acompanha a canela, com sobreposição entre as peças. A postura reage à frenagem, ao pouso e aos contatos laterais.

Rivais planejam curvas e ultrapassagens oito vezes por segundo, mantendo a física e o controle suave na frequência do motor. Cada piloto varia o traçado e o ritmo, acelera nas retas, freia antes das curvas e mantém o lado escolhido durante uma tentativa de ultrapassagem. Os pilotos de ambientação usam a mesma lógica. Encostadas leves provocam deslocamento e desequilíbrio; colisões fortes dependem da velocidade relativa e podem derrubar os dois pilotos, que se recuperam pelo ciclo existente. Não há sorteio de quedas.

Casinha fechada com atendimento externo, três motos estacionadas, mesa e três pilotos bebendo, árvores com troncos sólidos fora da faixa de corrida e três barcos com espectadores na água. Torre central com quatro refletores, ativada por horário e proximidade. Não há interior acessível na casinha.

O terreno do parque e da mata usa a mesma textura em coordenadas do mundo. A borda do relevo termina na altura do chão e mistura o barro à grama. Locadora, mesa, estacionamento e acesso compartilham uma clareira contínua, com bordas irregulares e transição suave, sem plataformas retangulares isoladas. O piso da clareira tem colisão triangulada acompanhando a superfície visível; a varanda de madeira continua sendo uma estrutura elevada. A vegetação rasteira é agrupada espacialmente, com alcance de 100 m e sem sombras adicionais.

Os dez espectadores/atendente usam o CivilianModel padrão, com roupas, postura sentada e mãos articuladas. Tiros próximos provocam proteção ou fuga limitada ao piso disponível; impactos causam dano e reação. Barcos mantêm seus passageiros dentro do convés. Motos estacionadas reagem ao impacto, e pilotos ativos reduzem o ritmo ao ouvir disparos próximos; um impacto direto pode derrubá-los. As conexões com combate são removidas no descarregamento.

As rampas conservam o impulso vertical na crista. A postura acompanha a subida, a trajetória no ar e a compressão ao aterrissar. O HUD de corrida concentra posição, volta e cronômetro no topo, com velocidade, estado do salto/frenagem e integridade no canto inferior direito.

## Validação

Scripts dedicados: `tests/test_motocross_progress.gd`, `tests/test_motocross_bike.gd`, `tests/test_motocross_session.gd` e `tests/test_motocross_scenery.gd`. Integração usa `Main.tscn` e `--no-save`, preservando o save do usuário. Medições renderizadas e capturas: `tests/measure/measure_motocross.gd`, artefatos em `evidence/motocross/`.

O orçamento provisório de referência é 60 FPS / 16,67 ms. Comparativos de desempenho são diagnósticos, pois outras sessões Godot do usuário estavam abertas; as amostras e limitações ficam registradas junto das evidências. Testes headless não certificam FPS.

Revisão de terreno, NPCs e saltos (28/09): cenário 24/24, incluindo 154 pontos de apoio e travessia física entre as áreas; combate integrado na Main 9/9; espectadores 15/15; lançamento físico 4/4 (0,49 m de afastamento do solo, 0,45 s no ar e compressão ao pousar). O teste de grupos de motos passou 20/20; árvores, 883/883; regressões da garagem, 84/84. Evidências finais e limitações de desempenho em `evidence/motocross/README.md`. As entradas abaixo também registram revisões anteriores.
