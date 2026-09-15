# Passada do policial armado

A passada de `PoliceOfficer` agora avança pela distância física percorrida, usando a projeção da câmera e a escala do personagem, como no Dante. Antes, uma frequência fixa de 4,8 radianos/s a 125 pixels/s e amplitude de 0,10 unidade deixavam os pés muito lentos em relação ao corpo. A amplitude passou a 0,18, com compensação de altura para conservar o apoio no piso.

As pernas acompanham a direção real do desvio, independentemente da mira. Ao recuar, o ciclo se inverte sem torcer os joelhos em 180 graus. A navegação e as velocidades de gameplay permanecem as existentes.

Validação Godot 4.7.2, headless, fixed-fps 60:

- `test_police_foot_tactics.gd`: zero falhas; dez portes, passos repetidos em movimento, avanço/recuo, apoio e nivelamento dos sapatos, empunhadura, desembarque e cobertura.
- `test_responder_routines.gd`: zero falhas, incluindo contorno físico de parede.
- `test_police_alley_navigation.gd`: zero falhas nos dois becos e sentidos, sem teleporte.

Logs em `D:/geteco/artifacts/police-walk-0913/`. O teste de tática avisa de seis objetos no encerramento. Revisão visual em movimento e comparação renderizada de desempenho não realizadas; jogo/editor e outras tarefas estavam ativos. Não há aprovação de FPS. O custo novo é constante por policial em movimento (projeção de dois pontos e cálculo de direção); não acrescenta busca de caminhos, população ou viewports.
