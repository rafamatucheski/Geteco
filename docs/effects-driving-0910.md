# Tiros, explosões e direção — 10/09/2026

Alterações aplicadas ao jogo Godot em D:/geteco/game.

- Tiros: clarão afunilado, retração do fogo e da luz 3D, fumaça curta e origem dos efeitos projetada da posição real da arma. Cápsulas com altura, giro, sombra, dois quiques e desaparecimento gradual.
- Granada, foguete e carros compartilham uma explosão com pressão inicial, fogo em expansão, fumaça ascendente, fragmentos e marca temporária no chão. Até 16 explosões, 24 marcas e 24 rajadas de destroços simultâneas; limpeza automática.
- Dante: contato abaixo de 85 px/s não gera atropelamento. O sangue com textura de 64 px passou de escala 2–5 para 2/64–5/64, isto é, partículas de 2–5 pixels no mundo. Contato não fatal não gera a poça de morte; emissão se desprende do personagem e é liberada ao terminar.
- Carros dirigidos: máxima de rua passa de 80% para 56% do valor do catálogo, redução de 30%. Força inicial de aceleração passa de 0,362 para 0,248 do valor do catálogo. Ambos os controladores usam a mesma curva; tráfego nas faixas conserva sua velocidade própria.
- Colisão: usa velocidade contra a normal do obstáculo; dano estrutural começa acima de 180 px/s. Uma batida a 300 px/s causa 5 pontos, antes 18. Amassados locais preservam o limite acumulado de 14 cm e a posição/escala do carro. Destroços dependem da força do contato.
- Faróis e lanternas: identificação pelas posições e materiais de cada modelo. Lentes permanecem separadas durante o agrupamento de malhas, e luzes quebradas ficam apagadas. Explosão carboniza carroceria, vidros e rodas, desligando emissões.
- Reparo: restaura geometria, materiais, luzes, velocidade e estado de combustão; limpa rastros antigos. Contagens antigas de explosão são invalidadas quando o carro é reparado ou apagado.

Validação automatizada aprovada: test_effects_driving_0910, test_vehicle_crash_and_explosion, test_vehicle_physics_regressions, test_wheel_body_clearance (14 modelos), test_vehicle_mesh_batcher, test_vehicle_engine_and_name, test_traffic_vehicle_repair_clears_skid e test_combat_audio com combat-only. A fixture de rastro foi adaptada à criação tardia do skid_line.

Captura renderizada em Compatibility e inspecionada: D:/geteco/artifacts/effects-driving-0910/review.png. É um cenário controlado com os modelos e efeitos de produção, não uma avaliação humana da direção durante uma partida.

Limite conhecido da validação: test_vehicle_damage_camera_handoff ainda falha nas assertivas de centro da câmera ao entrar/sair. Suas verificações de deformação passaram. O teste também foi executado com --fixed-fps 60 e continua com as falhas de câmera. Não se declara aprovação da suíte completa. Os scripts de câmera não foram alterados neste trabalho.

Logs e cópias dos arquivos anteriores estão em D:/geteco/artifacts/effects-driving-0910.
