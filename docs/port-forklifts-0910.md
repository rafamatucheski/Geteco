# Empilhadeiras do cais — 10/09/2026

As duas empilhadeiras decorativas do Porto Sul agora usam o veículo dirigível
da frota. O modelo original foi mantido, com carro dos garfos articulado,
rodas giratórias e esterçamento traseiro. Há seis caixas em paletes próximas.

- E: entrar; WASD/setas: dirigir; F/Enter: sair.
- Segurar mouse esquerdo: erguer. Parar com os garfos baixos sob a carga inicia o transporte.
- Segurar mouse direito: abaixar; ao chegar ao chão, soltar em espaço livre.
- Velocidade máxima efetiva: 90 px/s vazia, 55 px/s carregada. Elevação: até 1,65 m.
- Caixas e veículos pequenos vazios e parados podem ser carregados; uma carga por máquina.
- A carga conserva objeto, aparência e dano. Seu casco acompanha a empilhadeira e bloqueia muros, inclusive ao virar.
- Não é possível entrar num veículo suspenso nem puxar uma carga através de paredes.
- Atropelamentos funcionam a partir de 35 px/s; usam a reação física e o socorro dos pedestres existentes.
- A destruição abaixa os garfos; remover a empilhadeira restaura a carga.

Foram retirados os textos do navio, acesso ao convés, números das baias e
estados de carregamento vistos na imagem. Pintura do piso, guindastes e
rotinas de carga continuam presentes.

Validação: `test_port_forklift.gd`, `test_vehicle_wheel_steering.gd` e
`test_south_port.gd`, além de `capture_port_forklift.gd` com jogador real e
evento de mouse na cena HarborPreview. Os testes antigos de rodas foram
adaptados para motos e eixo traseiro direcional; o teste de cais retira os
cascos dos caminhões congelados apenas durante o cenário de guindaste sem
caminhão, restaurando-os antes do teste de carregamento real.

Evidências em `D:/geteco/artifacts/forklift-01-quay.png`,
`forklift-02-crate.png` e `forklift-03-car.png`.
