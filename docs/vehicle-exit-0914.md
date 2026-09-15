# Desembarque junto à porta — 14/09/2026

O vídeo do guincho mostrava Dante saindo da cabine e sendo deslocado para a
lateral do centro da carroceria. `VehicleBoarding` agora encerra a saída na
projeção da porta nativa, com até 24 pixels de folga lateral e consulta do corpo
completo contra veículo, cenário e outros atores. A conclusão conserva esse
ponto e zera a velocidade. Se não houver espaço, tenta a outra porta; com ambas
bloqueadas, conserva o personagem sentado e permite nova tentativa.

Motoristas NPCs retirados de veículos usam a mesma geometria. A pausa inicial
do motorista não aplica mais o recuo automático de 24 pixels por segundo.
Rotinas posteriores de caminhada/reação continuam funcionando.

Validação em Godot 4.7.2:

- `test_vehicle_boarding_animation.gd`: 12 modelos, dois lados, posição junto à
  porta, continuidade ao concluir e estabilidade após voltar à física; zero
  falhas. Log: `D:/geteco/artifacts/exit-final.log`.
- Mesmo teste renderizado com `--truck-focus`: guincho, ambos os lados; zero
  falhas. Vulkan Mobile, RTX 4060 Laptop. Log: `D:/geteco/artifacts/exit-render.log`.
  Capturas: `D:/geteco/artifacts/vehicle-exit-0914/`.
- `test_vehicle_exit_npc.gd`: retirada real de motorista em carro, guincho e
  moto, posição e pausa sem recuo; portas bloqueadas e nova tentativa; zero
  falhas. Log: `D:/geteco/artifacts/exit-npc-cleanup.log`.
- `test_vehicle_boarding_sides.gd` no HarborGame renderizado não concluiu.
  Registrou erros repetidos de `tour_lane_reservation` no sistema de tráfego;
  não produziu o resumo final. Log: `D:/geteco/artifacts/exit-harbor-live.log`.
  A causa da interrupção não foi comprovada; integração no mapa permanece pendente.

Não houve comparação de frame time antes/depois no mapa real. Performance não
certificada. As consultas novas ocorrem somente ao solicitar desembarque.
Estes resultados não certificam interiores nem todos os serviços de transporte.
