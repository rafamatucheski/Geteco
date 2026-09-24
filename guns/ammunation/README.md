# Ammu-Nation compartilhada

As filiais do porto e da serra usam a mesma fachada, sala e catálogo.

- `AmmunationFacade3D.gd`: prédio de 8,4 × 4,4 m, marquise vermelha, emblema e letreiro no telhado.
- `AmmunationBranchView.gd`: fachada projetada, porta deslizante por proximidade e bloqueio físico das folhas fechadas.
- `AmmunationArt.gd`: loja compacta dentro dos 8,4 × 4,4 m do prédio, com expositores laterais, corredor central, balcão e Vance.
- `../../harbor/interiors/HarborAmmunationInterior.gd`: piso no mesmo local da fachada, teto removido na entrada, câmera aproximada e catálogo, também usados na serra.

Para outra filial, reutilize a fachada e chame `bind_entrance` com a sala em `inline_mode`. Posicione a entrada usando `project_floor`. A porta abre ao aproximar e o jogador entra e sai caminhando, sem transferência de posição nem botão de entrada.

A geometria e as colisões usam a mesma projeção do piso. A câmera estática precisa manter a interpolação desativada antes de calcular paredes, expositores e spawn. E continua funcional no balcão para abrir o catálogo; fechar o catálogo libera o movimento.

Validação: `res://tests/test_ammunation_inline.gd` percorre as portas das duas filiais, confere catálogo, colisão e oclusão. `res://tests/test_ammunation_mountain_world.gd` cobre o mapa real da serra e o save. `res://tests/measure_ammunation_cutaway.gd` mede porto exterior e loja renderizados.
