# Aproximação e estacionamento das ambulâncias — 13/09/2026

A aproximação à ocorrência passou a escolher uma posição de atendimento antes de liberar a equipe. O veículo segue uma trajetória contínua, com raio mínimo e varredura de colisão, e termina alinhado à rua. O planejamento usa as faixas e os polígonos reais de asfalto/cruzamentos; não contém coordenadas de um cruzamento específico.

## Correção

- `world/shared/emergency/AmbulanceApproach.gd`: procura posições nas faixas, penaliza cruzamentos, verifica carroceria, portas, circulação lateral, extração da maca e acesso até um posto de atendimento ao redor da vítima. A carroceria usa os limites do modelo 3D, inclusive para a colisão física da ambulância.
- A trajetória pode ter um trecho reto antes da curva, para não cortar por fora de uma esquina. O giro depende do deslocamento; a aproximação não usa deslizamento contra obstáculos. Há até duas tentativas de ré reta de 70 pixels para recuperar espaço de manobra.
- O tráfego recebe uma reserva temporária do trecho de manobra à frente pelo mecanismo existente de frenagem. Ela não cria paredes físicas para pedestres. Depois de estacionar, a zona médica preserva o espaço das portas e da maca durante todo o atendimento, inclusive enquanto a equipe está junto da vítima.
- Se o ponto preferido estiver ocupado, outras posições são examinadas. Paradas excepcionais continuam possíveis, inclusive no sentido atual de uma ambulância em contrafluxo, mas também precisam passar nas verificações de volume e acesso. Apenas estar perto da vítima não libera o desembarque.
- A sequência médica recebe o percurso verificado, incluindo o retorno à traseira. A reativação pelo pool limpa o planejamento e suas reservas.

## Verificações

Motor: Godot 4.7.2; renderização Mobile/Vulkan; GPU RTX 4060 Laptop; viewport de 1280 × 720. Saves dos testes foram direcionados para `D:/geteco/artifacts/ambulance-parking-0913/`.

| Verificação | Resultado |
|---|---|
| `tests/test_ambulance_parking_contract.gd` | 13 verificações aprovadas: volume, semáforo real na traseira e na porta, alternativa bloqueada, trajetória coerente, varredura contra obstáculo estreito, esquina em L, reserva de tráfego e liberação |
| `tests/test_ambulance_forward_return.gd` | Aprovado: faixas dirigidas e invalidação de destino |
| `tests/test_medical_work_zone_vehicles.gd` | Aprovado: carros, ônibus, motos, tráfego de terminal, retorno à circulação e limpeza da proteção |
| `tests/test_medical_choreography_continuity.gd` | Ciclo completo aprovado, incluindo entrega no hospital, retorno da maca e permanência na baia; identidade do paciente preservada; passo visível máximo de 2,067 pixels |
| `tests/test_ambulance_parking_scene.gd -- --capture` | Aprovado em HarborGame, no cruzamento Dock Street × Warehouse Way do vídeo: aproximação, desembarque, retirada da maca, atendimento, retorno e embarque |
| `tests/test_ambulance_parking_scene.gd -- --obstacles --capture` | Aprovado em HarborGame, junto à rodoviária/hospital em Market Street × Warehouse Way, com ônibus, veículos, semáforos e acesso pela calçada; foi usada uma parada alternativa |

O teste de movimento verifica a relação entre giro e deslocamento e registra a posição por quadro. No cruzamento do vídeo, o desvio lateral máximo observado foi de 0,0014 pixel. No segundo local, foi de 0,035 pixel. As gravações mostram a sequência em movimento; não são apenas capturas da posição final.

Evidências:

- `D:/geteco/artifacts/ambulance-parking-0913/junction/maneuver-and-rescue.mp4`
- `D:/geteco/artifacts/ambulance-parking-0913/obstacles/maneuver-and-rescue.mp4`
- Em cada pasta: `report.json`, `motion.csv` e quadros PNG.
- Logs de regressão na pasta `D:/geteco/artifacts/ambulance-parking-0913/`.

## Limites e pendências

- **Performance não certificada.** O baseline geral renderizado, anterior à correção, já ficou abaixo da meta de 60 FPS: 29,69 FPS, p95 de 56,29 ms e p99 de 134,81 ms no percurso de 30 segundos. As capturas médicas fazem leitura e gravação de imagens e não são comparáveis a esse baseline. Havia também outras instâncias do Godot em execução, incluindo o jogo do editor e testes de outra tarefa; não foram encerradas. Os tempos dessas capturas não demonstram aprovação nem regressão atribuível a esta correção. O maior trecho de planejamento observado ficou próximo de 20 ms; falta um comparativo isolado do atendimento sem captura.
- O teste de continuidade terminou com aviso de duas instâncias ObjectDB e um recurso ainda em uso ao encerrar, apesar de todas as verificações funcionais passarem. A origem desse aviso de limpeza não foi isolada nesta tarefa.
- A busca local é finita: ela não garante solução para todo congestionamento, vítima inacessível ou combinação de obstáculos. Quando não há posição/caminho seguro, não autoriza um atendimento atravessando sólidos. A manobra de encaixe final na baia do hospital continua com seu controlador anterior; seu ciclo funcional foi verificado.
- Havia alterações locais anteriores e alterações simultâneas na sequência médica e na apresentação dos socorristas. Elas foram preservadas. Esta correção não editou HUD nem os sistemas de combate.
