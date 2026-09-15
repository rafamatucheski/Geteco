# Canhão de água dos bombeiros

Todos os veículos `rescue_pumper`, incluindo as três baias do quartel, recebem o canhão. No volante, mover o mouse gira o monitor 3D; segurar o botão esquerdo (`fire`, respeitando remapeamento) mantém o jato. A mira indica o alcance máximo de 420 unidades. O controle também usa a mira existente de gamepad/toque.

O primeiro corpo intercepta o jato: paredes bloqueiam, pessoas recebem 3 pontos de dano a cada 0,20 segundo, veículos perdem o resíduo dos pneus e recebem gotas/brilho temporário. A água não recupera saúde nem remove amassados. O som e a emissão param ao soltar, sair do volante, embarcar/desembarcar, pausar, abrir diálogo ou quebrar o caminhão.

A torre é articulada dentro do modelo existente, preservada pelo batcher de malhas. O fluxo usa um raycast por quadro de física, desenho limitado e um emissor reutilizado de 36 partículas. Carros comuns não recebem o componente; a troca de arquétipo remove o canhão.

Validação: `test_vehicle_water_cannon.gd` exercita dano real de pedestre, lavagem de carro real, parede, limite de alcance, pausa, saída, diálogo, embarque, avaria e reciclagem. `capture_vehicle_water_cannon.gd` carrega HarborPreview, verifica as três baias, embarca normalmente e dispara por eventos reais de mouse, verificando também giro da torre e soltura. Evidência em `D:/geteco/artifacts/water-cannon-harbor.png`. A regressão `test_iml_and_fire_truck.gd` passou; os logs também registram avisos preexistentes de inicialização dos atalhos salvos e limpeza do teste legado.
