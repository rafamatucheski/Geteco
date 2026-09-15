# Dante: proporções e movimento — 10/09/2026

Referência visual: `prototypes/menu_concept/dante_sunset_preview.png`.
Relato: vídeo `20260910-1515-21.2611405.mp4`, com cabeça desproporcional e braços abertos durante a locomoção.

O rig usado por `Player.gd` recebeu rosto menor com mandíbula modelada, barba curta, cabelo em mechas afiladas, pescoço mais estreito, sobrecamisa contínua, xadrez menos contrastante e jeans escuro. A camisa interna deixou de atravessar as costas. A recuperação do efeito de dano restaura a cor real do traje.

A caminhada/corrida usa alvos de apoio e elevação dos pés, joelhos dobrando para trás, tornozelos articulados e compensação da altura do quadril. Os cotovelos dobram para trás do tronco em vez de se abrirem lateralmente. Braços e pernas alternam em oposição; a cadência para quando uma parede bloqueia o deslocamento. Velocidades e colisões de gameplay foram preservadas.

## Validação

- `test_dante_natural_gait.gd`: aprovado. Verifica joelhos, solas niveladas, ausência de penetração no piso, contato durante apoio, ancoragem da cabeça, postura, repouso, roupa, recuperação de dano e deslocamento nativo até uma parede.
- `test_player_combat_pose.gd`: aprovado, 13 armas, zero falhas de empunhadura, apoio, recuo e contato com as mãos.
- `capture_dante_menu_fidelity.gd -- --motion`: renderização Vulkan do rig real em quatro direções e seis segundos de transição entre parado, caminhada, corrida e parada.
- `capture_dante_shop_motion.gd`, com `--fixed-fps 30`: renderização da loja e do Player de produção numa cena isolada, usando as ações nativas `move_*` e colisão real. Não representa uma validação do carregamento de HarborGame inteiro.

A primeira execução de `test_harbor_dante_contract.gd` comprovou deslocamento de 50/75 pixels ao caminhar/correr, mas encontrou quatro falhas na interação com o carro. As mesmas quatro falhas foram reproduzidas com os scripts anteriores a esta tarefa, restaurados apenas em memória. Durante a revisão, alterações concorrentes introduziram `GameInput` e migraram o movimento de `ui_*` para `move_*`; os testes deste trabalho foram adaptados. A última execução do mapa completo ficou bloqueada por erros de carregamento em `HarborGarageInterior.gd` e `HarborPoliceInterior.gd`, fora dos arquivos modificados aqui. A suíte global não está aprovada.

## Evidências

Arquivos em `D:/geteco/artifacts/dante-0910/`:

- `comparacao.png`: referência do menu, antes e depois, com mesma câmera/luz para ambos os modelos.
- `dante-animacao.mp4`: movimento do rig real em aproximação.
- `dante-na-loja.mp4`: movimento nativo no interior isolado.
- `natural-gait.log`, `combat.log`, `baseline-contract.log` e `harbor-contract-final.log`.

O resultado aproxima a identidade da ilustração dentro do modelo 3D estilizado do jogo; não reproduz a renderização desenhada do menu pixel a pixel.

## Revisão do cabelo após feedback

As pontas triangulares foram substituídas por uma base contínua com linha do cabelo definida e mechas curvas de volume baixo. As laterais acompanham a cabeça; a franja tem comprimentos variados e o material é preto fosco. Esta revisão altera apenas a construção do cabelo em `DanteVisualAdapter.gd`. Conferência por renderização Vulkan em quatro direções e aproximação do rosto, sem erros de script. Evidências em `D:/geteco/artifacts/dante-hair-0910/after.png` e `cabelo-detalhe.png`.
