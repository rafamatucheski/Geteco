# Ammu-Nation compartilhada

As filiais do porto e da serra usam a mesma fachada, sala e catálogo.

- `AmmunationFacade3D.gd`: prédio de 8,4 × 4,4 m, marquise vermelha, emblema e letreiro no telhado.
- `AmmunationBranchView.gd`: projeção da fachada e atualização da textura ao entrar na câmera.
- `AmmunationArt.gd`: mobiliário, armas de exposição, coletes, granadas e o armeiro Vance.
- `../../harbor/interiors/HarborAmmunationInterior.gd`: sala jogável e catálogo, também herdados pela filial da serra.

Para outra filial, reutilize a fachada e conecte uma `BuildingEntrance` ao gerenciador de interiores da região. Posicione a porta e o retorno usando `project_floor`. Os gerenciadores existentes guardam a origem para devolver o jogador à filial correta.

A geodata do interior usa a mesma projeção do piso. A câmera estática precisa manter a interpolação desativada antes de calcular paredes, expositores, spawn e saída. A entrada do catálogo ocorre no balcão; fechar o catálogo libera o movimento, e E na saída retorna ao exterior.

Validação: `res://tests/test_ammunation_identity_navigation.gd` percorre as duas filiais com as ações reais de movimento, verifica compras, reposição, bloqueios, colisões e retorno. Execute com renderização para gravar as capturas em `artifacts/ammunation-0910`.
