# Tarefa para Antigravity — arte 3D isolada

Estamos trabalhando em paralelo em D:/geteco/game. Astra integra mundo contínuo, estradas, streaming e gameplay. Três agentes dela cuidam de veículos/câmera, polícia e Dante/armas. Preserve mudanças existentes; não faça reset ou commit geral.

Sua tarefa: melhorar apenas arte procedural 3D em arquivos isolados. Leia os modelos existentes antes de implementar.

1. Melhore `world/mountain_pass/MountainPineTree.gd`: pinheiros naturais low-poly, tronco visível, galhos assimétricos e neve em massas discretas. Remova a aparência de estrelas/serras brancas empilhadas. Preserve interface, escala e colisão. Evite viewport por árvore ou processamento contínuo.
2. Melhore os modelos em `world/mountain_pass/art/winter_props/`, diferenciando abrigo dos lenhadores de um chalé residencial: ferramentas, toras, cobertura, bancos e desgaste discreto, todos em escala humana (referência de 1,8 m).
3. Crie APENAS modelos novos em `world/mountain_pass/art/review_0908/`: `MountainGunShop3D.gd` (fachada), `MountainGunShopInterior3D.gd` (balcão, prateleiras, armas decorativas, bancada e alvos) e `CrashedCargoPlane3D.gd` (avião cargueiro grande acidentado no lago). Todos Node3D autossuficientes, origem no piso, metros como unidade. Avião deve ter fuselagem penetrável visualmente e nó `CutawayRoof`, entrada traseira aberta e espaço para caminhar. Não implemente recompensa, colisão, teleporte ou controlador de jogador; Astra fará a integração.

Não edite MountainPass.gd, MountainSceneryBuilder.gd, MountainInteriorManager.gd, MountainCabin3D.gd, MountainCabinInterior.gd, Player*, qualquer veículo, armas/pickups, polícia, RegionTravel, SaveManager, estradas ou áudio. Não mexa em `HarborAmmunationInterior.gd`: entregue o modelo novo e coordenadas sugeridas em relatório.

Valide no Godot 4.7.2, com capturas REAIS e referência humana ao lado. Executável: `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`. Se não houver acesso, declare testes não executados; não use mockup como prova. Entregue lista de arquivos, dimensões, contagem de meshes e limites de uso. Avise quando terminar para Astra integrar.
