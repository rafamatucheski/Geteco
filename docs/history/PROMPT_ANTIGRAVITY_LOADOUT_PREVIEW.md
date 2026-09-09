# Antigravity — arte isolada do porta-malas

Crie uma prévia 3D procedural de um porta-malas aberto para o Summit SUV, com compartimento de arma longa, estojo de pistola, suporte de faca e pequenos detalhes de tecido/borracha. Use o estilo e a escala do veículo existente. Leia a prévia da Astra em prototypes/loadout/index.html para entender três slots: curta, longa e corpo a corpo. Não altere a prévia.

Trabalhe exclusivamente em world/mountain_pass/art/loadout_preview/ e tests/test_loadout_art_preview.gd. Exponha métodos set_open(bool) e set_loadout(Dictionary), sem implementar inventário, compras ou persistência. Faça dobradiça coerente e animação suave. A lógica de integração ficará com a Astra.

Não altere Player.gd, SaveManager.gd, TrafficVehicle.gd, PlayerCar.gd, portas existentes, câmeras, pontes, streaming, áudio ou UI compartilhada. Não substitua o carro oficial. Sem dependências externas. Faça uma cena de demonstração com personagem de 1,80 m ao lado, capture no Godot e encerre automaticamente o teste. Relate arquivos, dimensões, contagem de meshes e resultados reais. Não faça commit/reset nem desligue o computador.
