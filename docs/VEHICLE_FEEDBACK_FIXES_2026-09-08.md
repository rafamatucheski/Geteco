# Correções de veículos, coleta e combate — 08/09/2026

## Entrada e condução

O diagnóstico no Harbor reproduziu uma corrida de entrada/saída: a mesma tecla E que colocava Dante no TrafficVehicle o expulsava no quadro seguinte. A entrada agora aguarda a liberação da tecla antes de aceitar uma saída. Os controles de TrafficVehicle e PlayerCar também aguardam a liberação das teclas de caminhada que estavam pressionadas ao entrar; um novo comando passa a acelerar normalmente.

A entrada limpa velocidade, derrapagem e estado de impacto, e aplica exceções de colisão entre jogador e carro antes de desativar o colisor do jogador. A saída remove essas exceções. O teste reproduziu a expulsão indevida; não reproduziu todas as possíveis situações de explosão relatadas pelo jogador. Os testes corrigidos confirmam entrada estável e aceleração reta sem perda de vida em três veículos de tráfego e entrada estável no SUV nativo.

## Viaturas, dinheiro e sangue

- EmergencyVehicle estava abaixo do asfalto na ordem de desenho. Usa agora camada absoluta 8, restaura visibilidade na ativação e conserva a orientação da textura. As viaturas desse sistema continuam usando seus sprites existentes.
- CashPickup procurava a camada de colisão do cenário em vez da camada 4 do jogador. Corrigido; a coleta física credita dinheiro uma única vez e executa o som existente no canal SFX.
- HarborPreview/HarborGame e MountainPass agora instanciam WeaponEffects, necessário para os efeitos existentes de tiros e sangue. As poças de Player, AnimatedPedestrian3D e PoliceOfficer ficam acima do asfalto, com posição global corrigida após anexação ao cenário.

## Portas e motorista ejetado

VehicleDoor3D separa partes da carroceria e dos vidros do modelo original e as articula numa dobradiça. Compartilha os materiais de pintura e mantém a geometria separada depois do reparo. Carros 3D usam esse componente; os carros 2D conservam sua animação própria. Os viewports são atualizados durante a animação, sem renderização contínua para carros estacionados. O cupê prepara a geometria durante o carregamento para evitar esse trabalho na primeira entrada.

CarjackedDriver usa agora CivilianDriverModel: personagem 3D articulado, camisa verde, jeans, cabelo, rosto e mãos, com escala próxima à de Dante. Mantém suas reações ao roubo e depois inicia uma rotina simples de caminhada, aproveitando os percursos de calçada próximos quando disponíveis. Não é um novo sistema completo de navegação de multidões.

## Validação executada no Godot 4.7.2

- `test_vehicle_pickup_feedback.gd`: aprovado com Vulkan real; dinheiro, áudio, coleta única, viatura visível, sangue, entrada/condução de três variantes, porta da própria malha e caminhada do motorista.
- `test_native_vehicle_doors.gd`: aprovado para os 12 modelos verificados, incluindo cupê, SUV, utilitários e emergência; abertura, fechamento e geometria após reparo.
- `test_region_travel.gd`: aprovado; SUV ocupado permanece parado com teclas de entrada/caminhada seguradas, ida e volta entre regiões preserva veículo/progresso e há exatamente um sistema de efeitos de combate em cada região.
- `test_vehicle_crash_and_explosion.gd`: aprovado; deformação, permanência no veículo em chamas, saída e explosão.
- `test_police_car_alarm_theft.gd`: aprovado; viatura, alarme, estrelas, giroflex, sirene e saída. Corrigido o jogador incompleto do próprio teste, que não tinha câmera.
- `test_mountain_traffic_vehicle.gd` e `test_region_emergency_teardown.gd`: aprovados.

Logs estão em `D:/geteco/vehicle-feedback-test.log`, `D:/geteco/feedback-test_native_vehicle_doors.log`, `D:/geteco/feedback-test_region_travel.log`, `D:/geteco/feedback-crash-regression.log` e `D:/geteco/feedback-test_police_car_alarm_theft.log`.

Captura real de uma cena de verificação: `D:/geteco/vehicle-feedback-review.png`. Não é uma captura de uma sessão normal no Harbor. Alguns testes headless ainda emitem avisos de objetos remanescentes no encerramento; não foram classificados como ausência de vazamentos. Os testes não equivalem a uma campanha inteira jogada manualmente nem estabelecem uma nova medição de FPS.
