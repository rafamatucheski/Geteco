# Geteco — resultado do feedback de 14/09/2026

As alterações estão no projeto local. O fluxo completo da chegada, passeio e garagem passou no teste de integração e na execução renderizada. Os congelamentos gerais continuam reproduzíveis; a dublagem humana ainda depende das gravações.

Atualização de 14/09: o carro do Maciota foi substituído pelo sedã preto de alto desempenho inspirado no M8 Competition, com modelo, colisão, embarque, saída e perfil V8 próprios. As tomadas neurais expressivas continuam integradas como draft; a direção para a gravação humana agora pede uma voz original grave, levemente rouca e carismática, sem imitar personagem ou ator específico.

## Alterações entregues

| Frente | Comportamento implementado |
|---|---|
| Maciota e trânsito | Reserva temporária das vias do passeio, retirada apenas de tráfego ambiente distante e fora da tela, liberação ao desembarcar/cancelar. Desvios pela contramão e calçada usam a largura inteira do carro, curvas verificadas e detecção de pedestres durante a execução. |
| Garagem atual | Aproximação pela rua de serviço e encostada gradual, mantendo o sentido da via. O retorno antigo ao lado dos ônibus articulados foi removido. Estacionamento paralelo à fachada, fora da pista. |
| Embarque e saída | Caminhada com colisão, portas, poses de embarque para Dante e Maciota e profundidade compartilhada com a carroceria. A forma física do sedã M8 vem das malhas, incluindo para-choques, retrovisores e a largura maior. Maciota recebeu um corpo físico para caminhar. Saída bloqueada aguarda espaço; cancelamento pendente continua quando a passagem é liberada. |
| Ritmo das falas | Primeira fala do passeio após uma pausa; falas seguintes respeitam a duração do áudio e um intervalo adicional. Áudios do passeio são preparados antes da partida. |
| Mixagem | Vozes em um grupo próprio; demais sons diminuem 16 dB durante a fala. Entrada e retorno suaves, retenção de 1,2 s entre falas próximas e preservação dos volumes escolhidos pelo jogador. |
| Sedã M8 | Perfil V8 próprio com cinco camadas, timbre e volume revistos, progressão de marchas mais espaçada e retorno à primeira após parar. Aceleração, giro e som acompanham o passeio. |
| Semáforos | Verde mínimo de 7,5 para 5 s, preservando amarelo e intervalos de segurança. Renderização compartilhada em 256 px com antialiasing e maior contraste entre lentes apagadas e acesas. |
| Carros estacionados | Reposição na posição, orientação, modelo e cor originais após 120 s de ausência. Vaga precisa estar livre, distante do jogador e fora da tela. Veículo levado é preservado; limite de três veículos anteriores ainda existentes por vaga. |
| Roubo policial | Aviso vermelho removido de carro e moto; perseguição, estrela de procurado, arrombamento e tripulação policial preservados. |

## Validação

Passaram os testes de missão completa, bloqueio e liberação do desembarque, cancelamento/retomada, persistência dos checkpoints, entrada real pela porta da garagem e liberação do primeiro favor. O teste agora entra pela porta real da delegacia e aguarda os postes de iluminação antes de verificar a rota.

Também passaram: desvios para os dois lados e pedestre entrando no caminho; mixagem e restauração dos volumes; reposição de vaga ocupada/livre e preservação do carro levado; motor do sedã M8, incluindo parada e primeira marcha; contrato de cruzamentos; colisão e ancoragem dos semáforos com renderização real; conservação de carros e motos após visita distante; roubos policiais de carros/motos e proteção de personagens/armas na garagem.

O teste renderizado de profundidade usa Dante e Maciota reais, com controle de visibilidade ao lado do veículo e comparação com a carroceria ocultada. Confirmou oclusão durante o embarque e restauração dos rigs e viewports. As capturas em sequência complementam esse teste.

Comandos principais, a partir de `D:/geteco` (substituir o executável pelo Godot local):

```text
godot --headless --path game --script res://tests/test_story_arrival_v2.gd
godot --headless --path game --script res://tests/test_maciota_detour.gd
godot --path game --script res://tests/test_maciota_boarding_depth.gd
godot --headless --path game --script res://tests/test_mission_voice_mix.gd
godot --headless --path game --script res://tests/test_parked_vehicle_respawn.gd
godot --headless --path game --script res://tests/test_maciota_engine.gd
godot --headless --path game --script res://tests/test_maciota_m8.gd
godot --headless --path game --script res://tests/test_garage_weapon_restrictions.gd
```

## Desempenho: pendência aberta

Comparação sequencial na mesma máquina, Godot 4.7.2, RTX 4060 Laptop, Vulkan Mobile, 1280 × 720, limite de 60 FPS e VSync ligado. Mesmo roteiro de circulação livre, seed e preparação; aquecimento de 10 s seguido de medição de 30 s. Os processos não concorreram entre si.

| Circulação livre | Antes | Depois |
|---|---:|---:|
| FPS médio | 53,14 | 53,84 |
| p50 | 17,06 ms | 16,95 ms |
| p95 | 25,89 ms | 25,92 ms |
| p99 | 36,42 ms | 32,33 ms |
| Máximo | 121,16 ms | 121,06 ms |
| Quadros > 33,3 ms | 18 | 16 |
| Quadros > 66,7 ms | 10 | 11 |

O desempenho geral ficou próximo do anterior; os picos não foram eliminados. O passeio final de 90 s completou a missão e a caminhada do Maciota até a garagem, mas registrou 54,20 FPS, p95 de 25,20 ms, p99 de 29,13 ms e pico de 234,60 ms. Não atende a uma garantia de 60 FPS estáveis nem permite declarar os freezes resolvidos. As amostras iniciais do passeio tinham rota/preparação diferentes; não devem ser usadas para anunciar uma melhora percentual.

Os CSVs mostram picos de tempo de processo de aproximadamente 70–86 ms em parte dos quadros lentos da circulação livre, com física em torno de 6–7 ms. Isso ajuda a direcionar o perfil, mas não identifica sozinho uma função culpada. A investigação restante está preparada em [antigravity-freezes-2026-09-14.md](antigravity-freezes-2026-09-14.md).

## Dublagem e limites da entrega

O carregador de WAVs humanos, o manifesto e a mixagem estão prontos. Nenhuma gravação humana foi produzida ou contratada. O áudio provisório continua nas falas sem gravação. O [piloto do encontro e passeio](../audio/mission_voices/piloto-maciota.md) contém texto, personagem, intenção e nomes sugeridos dos arquivos.

A amostra do motor foi gravada pelo driver de áudio real, com marcha lenta, aceleração, cruzeiro e frenagem. Os testes verificam camadas, ausência de clipping nos buffers, giro e marchas; a revisão artística do timbre deve ser feita por escuta no jogo.

A reposição das vagas foi validada durante a sessão e a conservação dos veículos após afastamento foi coberta. O temporizador novo da vaga não foi integrado ao formato de save; recarregar uma região recria seus controles de reposição. A entrega não certifica persistência desse prazo entre sessões.

Evidências em `D:/geteco/artifacts/feedback-0914-teste2/`: `story-final-approach.log`, `depth-final.log`, `verified-test_maciota_detour.log`, `final4-test_mission_voice_mix.log`, `final4-test_parked_vehicle_respawn.log`, `verified-test_maciota_engine.log`, `final4-junction_traffic_contract_test.log`, `final8-test_fixed_traffic_signals.log`, `final8-test_taken_vehicle_parking.log`, `final6-test_police_car_alarm_theft.log`, `final7-test_police_theft_crew.log`, `final7-test_garage_weapon_restrictions.log`, `before-stability/`, `after-stability/`, `tour-final/`, `boarding-final/` e `350z/`.
