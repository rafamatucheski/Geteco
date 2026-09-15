# Chegada à serra e lojas de roupa

Na chegada à serra, uma dica contextual recomenda comprar ou equipar uma parka
no Último Abrigo ou na Union, identificadas pela camiseta no minimapa. Usa o
apresentador existente, que evita repetir a dica durante a sessão e respeita
combate, direção rápida e janelas abertas.

O frio continua restrito à zona de exposição. Os primeiros 15 segundos não
consomem temperatura; nos 15 seguintes a intensidade cresce gradualmente. O HUD
só aparece com exposição relevante ou temperatura baixa, desaparece após a
recuperação e fica oculto durante o atendimento. A integração da curva independe
da taxa de quadros. A parka mantém o preço de $1800 e a proteção de 80%; veículos,
fogueiras e interiores continuam recuperando calor.

A Union ganhou vitrine e identificação própria. As duas lojas compartilham
interior com madeira, tapete, araras, manequins e detalhes em tons quentes. O
catálogo destaca a coleção de inverno; na serra, sugere a parka quando o traje
atual tem pouca proteção. Experimentar não compra; comprar equipa a roupa.

Correções funcionais:
- A loja da montanha usa apenas a porta e o interior de MountainInteriorManager.
- ContinuousWorld preserva a visibilidade individual dos menus nas transições;
  não força mais todos os CanvasLayers a aparecerem a cada atualização regional.
- Balcão e saída têm áreas de interação separadas.
- A prévia 3D começa de frente e para de renderizar com o catálogo fechado.
- O personagem tem escala proporcional ao interior.

Validação em Godot 4.7.2:
- `test_cold_onboarding.gd`: 12 verificações passaram.
- `test_mountain_refinement.gd`: 22 verificações passaram, incluindo portas reais,
  interação do balcão, liberação dos controles, abrigo e restauração da roupa.
- `test_clothing_shops.gd`: passou no mundo contínuo, incluindo compra, reutilização
  sem nova cobrança, saldo insuficiente, serialização, duas lojas e menus fechados
  na chegada, após fechar o catálogo e após sair e retornar à região.
- Capturas renderizadas de ambas as fachadas, interiores e catálogos em
  `D:/geteco/artifacts/winter-clothing-0910/`.

Arquivos de captura: `tests/capture_winter_clothing.gd` e
`tests/capture_clothing_world.gd`. As capturas usam o código real do jogo.

## Revisão após feedback: Dante e interface compacta

A prévia agora chama `DanteVisualAdapter.build_dante_rig`, o mesmo construtor
usado pelo Player, por meio de um host visual sem lógica de gameplay. Rosto,
cabelo, corpo e roupas correspondem ao modelo de produção. O construtor antigo
do boneco da loja foi removido. Girar fica a cargo do jogador ao arrastar.

O catálogo ocupa uma janela central de 800 × 540 unidades, com duas categorias
(Inverno/Todas), nomes curtos, saldo discreto, proteção resumida e preço no botão
de compra. Foram removidos o banner, os filtros por distrito, o pedestal e os
textos repetidos. Experimentar continua sem alterar o jogador ou cobrar.

Validação adicional: `test_clothing_preview.gd` compara a geometria e as
transformações do rosto/cabelo com o Player real, percorre os dez trajes,
verifica que a prévia não cria outro jogador nem altera o guarda-roupa, e testa
compra, saldo insuficiente, troca e suspensão da renderização. Passou, assim como
`test_mountain_refinement.gd`. Interface renderizada em 1280 × 720, 1024 × 768 e
1920 × 1080.
