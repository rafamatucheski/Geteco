# Revisão renderizada dos 28 interiores

Data: 2026-09-21. Fixture tests/capture/visual_regions.gd usa o Actor.gd real (Dante), câmera ortográfica da FullSession, offset(0,18,15), tamanho por sala e luz/Environment da ProductionWorld. Render Vulkan Mobile real na RTX 4060, 1280x720. Não é benchmark de FPS.

Foram inspecionadas imagens de entrada e posição fisicamente livre atrás de um móvel por interior. O teste de profundidade compara a máscara visível de Dante com sua referência isolada; a contagem exclui sombra no piso. A métrica é apoio à inspeção visual, não prova sozinha aprovação. A primeira captura tinha T-pose por fixture congelada antes da animação; a segunda usa a pose real após update do Actor.

Correções evidenciadas: polícia corte frontal/lintel; bombeiros caixas elevadas das portas; abrigo vigas de teto; Summit divisórias do provador; garagemChefe enquadramento25→20,5. Sólidos nativos permanecem íntegros. Arquivos before-* preservam os defeitos observados.

Escopo de aprovação: enquadramento, leitura de Dante na entrada e oclusão no ponto registrado. Não inclui NPCs/veículos/serviços gerados pela sessão, todos os móveis, todas as poses, percurso completo ou FPS. GaragemChefe sem frota na fixture não comprova paridade de conteúdo. Arte, passagens e sombras dos interiores foram vistas; nenhum lugar recebe aprovação integral de migração com base apenas nesta revisão.

| Interior | Entrada | Atrás do móvel | Leitura visual / profundidade pontual |
|---|---|---|---|
| harbor_bank | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_bank-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_bank-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| harbor_police | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_police-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_police-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| harbor_hospital | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_hospital-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_hospital-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| harbor_fire_station | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_fire_station-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_fire_station-behind.png) | Inspecionado após correção; aprovado neste enquadramento e ponto |
| harbor_clothing | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_clothing-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_clothing-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| harbor_fuel | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_fuel-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_fuel-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_cabin | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_cabin_encosta | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_encosta-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_encosta-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_cabin_forest | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_forest-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_forest-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_bunker | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_bunker-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_bunker-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| lumberjack_shelter | [foto](D:/geteco/game/geteco_v2/evidence/interiors/lumberjack_shelter-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/lumberjack_shelter-behind.png) | Inspecionado após correção; aprovado neste enquadramento e ponto |
| ski_lodge | [foto](D:/geteco/game/geteco_v2/evidence/interiors/ski_lodge-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/ski_lodge-behind.png) | Inspecionado após correção; aprovado neste enquadramento e ponto |
| mountain_mystery_cave | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_mystery_cave-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_mystery_cave-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_outfitters | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_outfitters-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_outfitters-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_boutique | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_boutique-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_boutique-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_village_outfitters | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_village_outfitters-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_village_outfitters-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| harbor_ammunation | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_ammunation-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_ammunation-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_gunshop | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_gunshop-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_gunshop-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| westgate_garden | [foto](D:/geteco/game/geteco_v2/evidence/interiors/westgate_garden-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/westgate_garden-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| quayside_house | [foto](D:/geteco/game/geteco_v2/evidence/interiors/quayside_house-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/quayside_house-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| canal_north | [foto](D:/geteco/game/geteco_v2/evidence/interiors/canal_north-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/canal_north-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| cemetery_keeper | [foto](D:/geteco/game/geteco_v2/evidence/interiors/cemetery_keeper-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/cemetery_keeper-behind.png) | Inspecionado após correção; aprovado neste enquadramento e ponto |
| port_boss_garage | [foto](D:/geteco/game/geteco_v2/evidence/interiors/port_boss_garage-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/port_boss_garage-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| harbor_sewer | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_sewer-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/harbor_sewer-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_cabin_village_1 | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_1-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_1-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_cabin_village_2 | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_2-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_2-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_cabin_village_3 | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_3-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_3-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |
| mountain_cabin_village_4 | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_4-entry.png) | [foto](D:/geteco/game/geteco_v2/evidence/interiors/mountain_cabin_village_4-behind.png) | Inspecionado; aprovado neste enquadramento e ponto |

Dados brutos com posição, sólido, máscara de referência e teste físico: [report.json](D:/geteco/game/geteco_v2/evidence/interiors/report.json).

Resultado final: 28/28 entradas e posições dirigidas inspecionadas visualmente. Todos os pontos atrás dos móveis ficaram fisicamente livres; houve oclusão parcial na máscara em todos (aproximadamente46%–90%visível). Nenhuma falha de apresentação identificada nesta amostra permanece aberta. Isso não significa aprovação de todo percurso nem paridade integral.

A correção mais evidente foi Summit: apenas5,3%de Dante permanecia visível atrás da divisória; após o corte visual,77,6%. Nos bombeiros as três caixas elevadas do portão foram ocultadas após a imagem mostrar que nomes duplicados não identificavam todos os componentes. Polícia, abrigo e enquadramento da garagemChefe também foram recapturados e vistos após ajuste.


### Residentes e carros originais (captura adicional)

Inspecionadas quatro imagens reais da fixture com os oito residentes e cinco modelos de veículos:

- Hospital: Clara atrás do balcão e Miguel junto à circulação; proporções coerentes com Dante. [Imagem](D:/geteco/game/geteco_v2/evidence/interiors/harbor_hospital-populated.png).
- Bombeiros: Capitão Rocha legível na posição original. [Imagem](D:/geteco/game/geteco_v2/evidence/interiors/harbor_fire_station-populated.png).
- Garagem PortBoss: cinco carros originais nas cinco baias, orientação original, sem sobreposição visual. [Imagem](D:/geteco/game/geteco_v2/evidence/interiors/port_boss_garage-populated.png).
- Delegacia: primeira captura encontrou Ferreira escondido pela divisória frontal da cela. Corte visual de1m aplicado à divisória mantendo sólido integral. Recaptura inspecionada: cabeça e torso de Ferreira legíveis acima da divisória; oclusão inferior coerente com o sólido. [Imagem](D:/geteco/game/geteco_v2/evidence/interiors/harbor_police-populated.png).

A fixture povoa apenas apresentação: runtime cria atores e veículos dirigíveis. Capturas não validam diálogos, colisões entre atores, saídas dirigindo, estados salvos ou desempenho da sessão.
