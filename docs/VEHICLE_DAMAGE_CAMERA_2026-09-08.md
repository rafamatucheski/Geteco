# Dano de carroceria e transição de câmera — 08/09/2026

## Alterações

- `TrafficVehicle.gd`: substituídas placas Polygon2D persistentes e fragmentos em todo contato por dano na própria malha 3D ou pequenos riscos nos veículos 2D. Contato visual tem intervalo de 500 ms. Fumaça do motor usa textura suave em vez de quadrados sólidos.
- `VehicleSurfaceWear2D.gd`: helper compartilhado de riscos de até 6,4 px, espessura 0,85 px, dentro da carroceria. Limite de seis marcas, removendo imediatamente as anteriores do container. Pode ser utilizado também pelo EmergencyVehicle, cujo arquivo pertence ao agente da polícia.
- `PlayerCar.gd`: mantém corpo rígido e usa o mesmo helper para veículos 2D; cupês nativos continuam no caminho de dano 3D.
- `CoupeDamageModel.gd`: deformação local gradual com limite acumulado de 0,14 m, medido no espaço do modelo, inclusive em peças com escala. Removidos tubos de arranhão posicionados pela equação de teto exclusiva do cupê, que não descrevia SUVs, vans e caminhões. Dano não cria peças fora da carroceria.
- `VehicleDoor3D.gd`: descarta o buffer de vértices deformados quando recorta uma superfície da porta. A nova topologia não pode reutilizar a contagem/ordem de vértices anterior.
- `DynamicCamera.gd`, `PlayerCar.gd`, `TrafficVehicle.gd`: captura centro e zoom antes de mover o ator, transfere esse enquadramento à próxima câmera e reinicia smoothing antes da ativação. Corrigida a conversão do deslocamento de antecipação, antes calculado em coordenadas globais e aplicado como coordenada local de um carro girado.

## Evidências

- `tests/test_vehicle_damage_camera_handoff.gd`: aprovado headless e com Vulkan real / RTX 4060. Entrada e saída preservam enquadramento em três veículos de tráfego, PlayerCar e HarborCoupe; cenário desloca o carro 6.000–8.000 px enquanto o jogador oculto fica no ponto de entrada. A câmera não retorna ao ponto antigo. Teste inclui impacto, abertura de porta após dano, novo impacto e reparo.
- Deformações medidas após impactos repetidos: Summit SUV 0,04569 m; Arctic Jeep 0,14 m. Assert exige dano real maior que zero e menor ou igual ao limite.
- `tests/test_native_vehicle_doors.gd`: aprovado para os 12 modelos.
- `tests/test_vehicle_crash_and_explosion.gd`: aprovado; colisão, carro em combustão, saída voluntária e explosão.
- `tests/test_vehicle_pickup_feedback.gd`: aprovado com Vulkan real, incluindo coleta, sangue, ocupante 3D, portas e condução.
- `git diff --check` dos arquivos alterados: aprovado.

Captura real de cenário de verificação: `D:/geteco/vehicle-damage-camera-review.png` (seis variantes após doze impactos). Logs: `D:/geteco/vehicle-agent-handoff-rendered.log`, `D:/geteco/vehicle-agent-compile.log`, `D:/geteco/vehicle-agent-crash-regression.log`, `D:/geteco/vehicle-agent-feedback-final.log`.

O teste de renderização ainda informa objetos remanescentes ao encerrar rapidamente a cena; não é evidência de ausência de vazamentos. A captura é de uma cena de verificação, não de uma sessão manual no Harbor. Nenhum save foi alterado por este subtrabalho.
