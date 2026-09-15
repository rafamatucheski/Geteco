# Revisão da iluminação viária — 11/09/2026

Implementação aplicada à cena de jogo `HarborGame`, à prévia do porto e à serra carregada pelo mundo contínuo.

## Diagnóstico

| Área | Problema encontrado | Correção |
| --- | --- | --- |
| Ponte Foundry e ponte da serra | Círculos decorativos no desenho, sem fontes que iluminassem o asfalto | Holofotes duplos elevados, carcaças 3D, difusores luminosos, barras industriais de LED e iluminação da pista |
| Northbank e Northgate | Apenas seis posições de postes em cada distrito, apesar das várias avenidas | Preenchimento das lacunas a partir da geometria real das ruas |
| Memorial, avenidas do porto e Ashbend | Cobertura irregular entre postes e nas curvas/cruzamentos | Postes adicionais com o foco dirigido para a pista, incluindo os dois sentidos de circulação |
| Ligação norte | Pontos decorativos e trechos longos sem iluminação; vias sobrepostas | Holofotes e barras seguindo as curvas da ponte; luminárias fixadas nos guarda-corpos dos acessos inferiores |
| Túnel da serra | Luzes de aproximadamente 115 px de diâmetro separadas por 180 px | Barras 3D a cada 140 px, dos dois lados, com projeções sobrepostas; funcionamento permanente |
| Estrada da serra e acessos às vilas | Longos trechos dependiam dos faróis | Postes orientados para a estrada e inclusão dos três acessos aos pontos de parada |
| Noite | Modulação RGB de 0,18 / 0,22 / 0,38 escondia detalhes fora dos focos | Ajuste moderado para 0,25 / 0,29 / 0,40, preservando a aparência noturna |

## Resultado medido

| Área | Vias analisadas | Novos postes | Amostras de cobertura | Amostras abaixo do mínimo após a intervenção |
| --- | ---: | ---: | ---: | ---: |
| Porto, bairros e acessos norte | 38 | 213 | 2.769 | 0 |
| Serra e acessos às vilas | 4 | 41 | 342 | 0 |
| Total | 42 | 254 | 3.111 | 0 |

Além dos postes, o mundo completo instancia **127 luminárias elevadas**, entre barras de LED e holofotes. As carcaças incluem suportes, aletas de dissipação e lentes segmentadas. As barras de cada lado da ponte compartilham a projeção no chão para limitar a sobreposição de fontes.

A medição usa o centro e duas posições laterais de cada via, em intervalos de no máximo 85 px. Soma o alcance e a intensidade das texturas de iluminação transformadas para o espaço do mapa, com mínimo de 0,18. É uma auditoria geométrica de cobertura, não uma medição física de lux nem uma garantia sobre cada pixel. As capturas no renderizador Vulkan Mobile complementam essa verificação.

## Integração e desempenho

O jogo apresenta modelos 3D em `SubViewport` sobre um mundo de circulação 2D. Os novos holofotes têm geometria e focos 3D no modelo; as fontes `PointLight2D` correspondentes iluminam o asfalto, os personagens e os veículos da cena. Os feixes discretos e os difusores luminosos tornam a origem da luz visível.

As carcaças compartilham imagens renderizadas por tipo e estado de iluminação; os postes compartilham modelos por orientação e cor. As texturas de luz também são compartilhadas. Os modelos não exigem renderização 3D contínua e as projeções/feixes deixam de ser desenhados quando seu alcance sai da tela. A análise de cobertura usa uma grade espacial e ocorre na construção da região.

A revisão visual encontrou cortes causados pela sobreposição de muitas fontes. Os pares de luminárias da ponte passaram a compartilhar a projeção no chão; a apresentação do tabuleiro superior no cruzamento norte foi dividida em setores pequenos e os acessos inferiores receberam uma máscara de luz própria e malhas estáticas divididas em setores. Isso leva em conta o limite de luzes por objeto do motor. [Discussão técnica no repositório oficial do Godot](https://github.com/godotengine/godot-proposals/discussions/9336).

## Colisões, horário e testes

- Luminárias elevadas: nenhum corpo de colisão, nenhuma API de dano ou impacto de veículo.
- Postes ao nível da rua: conservam colisão, queda e desligamento após impacto forte.
- Novos postes: posicionamento fora do asfalto, das entradas reservadas e dos obstáculos estáticos existentes; braços orientados para o lado da via.
- Dia/noite e tempestade: integração com o gerenciador existente. Túneis continuam iluminados durante o dia.
- `tests/test_road_lighting.gd`: **zero falhas**, carregando a cena de jogo e a serra; verifica cobertura, colisões dos postes, ausência de colisão/dano das luminárias elevadas, horário, tempestade, desligamento fora da tela e queda de poste.
- `tests/test_harbor_bridge.gd`: **zero falhas**; carro percorreu aproximadamente 1.386 px em cada sentido, sem colisões. Inclui 15 sondagens da pista e 10 da água. O teste foi atualizado para a ação atual de movimento e para aguardar a animação de entrada no carro.
- Capturas: Foundry, Northbank, Northgate, ligação norte, Market Street, porto, ponte da serra, túnel e curva da serra.

## Evidências

- [Dados completos da auditoria](D:/geteco/artifacts/road-lighting-0911/coverage.json)
- [Log dos testes de iluminação](D:/geteco/artifacts/road-lighting-0911/coverage.log)
- [Log de travessia da ponte](D:/geteco/artifacts/road-lighting-0911/bridge.log)
- [Ponte Foundry antes](D:/geteco/artifacts/road-lighting-0911/before-foundry.png) · [depois](D:/geteco/artifacts/road-lighting-0911/after-foundry.png)
- [Northbank antes](D:/geteco/artifacts/road-lighting-0911/before-northbank.png) · [depois](D:/geteco/artifacts/road-lighting-0911/after-northbank.png)
- [Ligação norte depois](D:/geteco/artifacts/road-lighting-0911/after-connector.png)
- [Curva da serra depois](D:/geteco/artifacts/road-lighting-0911/after-mountain-curve.png)
- [Túnel depois](D:/geteco/artifacts/road-lighting-0911/after-mountain-tunnel.png)

Reprodução: executar os scripts de teste com Godot 4.7.2, `--headless --path D:/geteco/game --audio-driver Dummy --script res://tests/test_road_lighting.gd`. As capturas usam `res://tests/visual/capture_road_lighting.gd`, sem `--headless`; adicionar `-- --mountain` para a serra.
