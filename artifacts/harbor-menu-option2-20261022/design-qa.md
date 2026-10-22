# Harbor — revisão visual dos menus, 22/10/2026

final result: passed

Escopo: composição visual nativa dos menus e do mapa. Não é aprovação de desempenho ou de todo o jogo.

## Referências

- Fonte visual: `selected-option2.png`, segunda imagem apresentada e escolhida pelo usuário, 968×1625, com três telas empilhadas.
- Correções explícitas posteriores têm precedência: tipografia única de mesmo tamanho/peso, inicial maiúscula, acabamento arredondado e antialiasing; água do mundo precisa parecer mar. A captura do usuário com os defeitos é `C:/Users/rafae/AppData/Local/Temp/codex-clipboard-3804d64b-9a12-4203-9809-5d3b178d1099.png`.
- Implementação: `02-pausa-1280.png`, `03-video.png` e `map/world.png`, pixels nativos 1280×720. Tamanhos adicionais: `pausa-800.png`, `settings-800.png`, `map/world-compact.png`, 800×600; `08-pausa-1920.png`, 1920×1080.
- Comparação conjunta: `comparison.png`, 2560×2250, com cada terço da referência normalizado para 1280×720 à esquerda e implementação em pixels nativos à direita. Pixels de viewport Godot; CSS/DPR não se aplicam. O recorte da referência corresponde às três telas do mesmo conceito. Inspeção focada adicional das capturas nativas para tipografia, botões, remapeamento e rodapé.

## Superfícies avaliadas

- **Tipografia:** mesma família Barlow regular, 20 px e peso regular em títulos, ações, opções e textos auxiliares. Antialiasing, mipmaps e oversampling 2; sem contorno/sombra nos controles. Valores de teclas mantêm seus nomes reais. A hierarquia grande/semibold do conceito foi substituída conforme pedido posterior do usuário. Português e inglês conferidos em `pause-english.png` e `settings-english.png`.
- **Espaçamento e layout:** pausa em duas colunas, título fora da rolagem e ações agrupadas. Configurações amplas com navegação por grupos e rodapé fixo. Campos que excedem a área útil permanecem acessíveis por rolagem; nenhum controle persistente ficou fora da tela nos tamanhos conferidos. Cantos 12 px, foco visível e separação por respiro/regras.
- **Cores:** grafite e branco quente, dourado na seleção/ação principal. O mar usa azul profundo e textura de água; a terra mantém os dados reais dos biomas. Descrições funcionais permanecem legíveis no fundo opaco das configurações.
- **Assets:** ícones reais Lucide, licença incluída no repositório. Textura do mar gerada pelo Image Gen, incorporada no projeto e importada com mipmaps; não substitui geometria de terra/lagos. O fundo urbano da montagem da pausa é uma captura estática do jogo; o produto mantém a cena real. Nenhum cenário da imagem conceitual foi pintado por cima do mapa.
- **Texto e estados:** capitalização de frase, idioma consistente, atalhos e remapeamento preservados. A marca segue Harbor. Abas, selecionado, hover/foco, controles desabilitados, filtros e seleção de destino usam os estados nativos.

## Histórico de correções

1. P1: hierarquia de fonte inconsistente e idiomas misturados na captura do usuário. Corrigidos com tipografia compartilhada e traduções explícitas. Evidência: capturas PT/EN finais.
2. P2: caixas angulares incompatíveis com o acabamento pedido. Corrigidas para raio 12 px nos botões, campos e abas. Evidência: `03-video.png` e `settings-800.png`.
3. P2: rótulos do gamepad cortados após unificar a fonte; Shift traduzido como Trocar. Coluna ampliada e tradução automática de teclas desativada. Evidência: `06-controles.png`.
4. P1: mar parecia uma superfície vazia escura. Material oceânico estático em coordenadas reais, azul e ondulações visíveis, atrás da terra. Evidência: `map/world.png` e `map/city.png`.
5. Rótulo da cidade reposicionado com base nas estradas/serviços para não ficar no sopé do deserto. Escala comum das três regiões confirmada nos logs de captura.

Não restam achados P0/P1/P2 de apresentação nas vistas inspecionadas. Diferenças da referência — títulos sem tamanho gigante, cantos arredondados, oceanografia e dimensões reais das regiões — decorrem dos pedidos posteriores e da geometria autoritativa, não de deformação do mundo.

## Verificações e limites

Testes de configurações, remapeamento, navegação do mapa e layout passaram; a suíte de atlas verifica coordenadas e progressão. Fluxo Main anterior confirmou C# ativo e recuperação ao fechar/reabrir. Não houve novo fluxo Main depois das últimas alterações de tipografia/mar. A renderização isolada não certifica FPS, estabilidade temporal global ou export de release. Os números anteriores do mapa ficaram abaixo da meta e o desempenho final continua pendente, conforme `resultado.md`.

## Checklist

- [x] Composição escolhida adaptada aos componentes reais.
- [x] Correções de tipografia, capitalização e arredondamento.
- [x] Capturas e inspeção em português/inglês e tamanhos reduzidos.
- [x] Mar identificável, geografia real e escala regional uniforme.
- [x] Funcionalidade de menus/mapa coberta pelos testes pertinentes.
- [ ] Aprovação de performance da revisão final — pendente, fora desta aprovação visual.
