# Bancos, fogo e união do terreno — 02/10/2026

Escopo solicitado: padronizar a qualidade dos bancos e fogueiras do jogo, preservando os estilos de cada ambiente; eliminar a aparência de placas sobrepostas entre trilhas, acostamentos e neve da montanha.

## Terreno

- Trilhas e acostamentos passam a integrar o material opaco do próprio terreno. Uma máscara por trecho de 64 m combina os caminhos pelo máximo de cobertura, sem acumular transparência nos cruzamentos.
- A máscara usa amostras coincidentes nas bordas, textura de 129 × 129 pixels e uma consulta por fragmento; é liberada junto do trecho. Não há processamento novo por quadro nem alteração da malha física.
- As antigas superfícies visuais elevadas de trilha/acostamento deixam de ser desenhadas na montanha. O suporte e os contornos de colisão existentes permanecem.
- Duas placas de neve sobrepostas da vila foram retiradas. O terreno nativo já fornece neve contínua e apoio. Pavimentação, praça e parada de ônibus permanecem como superfícies construídas.

## Bancos

Treze famílias receberam geometria/acabamento compartilhados: StreetBench (HarborProp/HarborPublicRealm), CityPropKit, vila da montanha, terminal marítimo, estações urbanas, vila/casas dos caminhoneiros, depósito portuário, cemitério, abrigo PortLife, bancos do braseiro do resort, alojamento dos lenhadores, banco de botas do Summit e bancos estofados das lojas. Bancos ripados HarborRoute, assento de tora da cabine e bancos de concreto da polícia preservam o desenho, com material melhorado. Sofás Summit e bancos Cobra já detalhados foram inspecionados e preservados.

Não são contados como bancos de praça: bancadas de trabalho, assentos de veículos/teleférico e cadeiras individuais. Variantes antigas de MountainVillage/MountainTerminal e Sawmill sem chamada no jogo atual não foram migradas. Não há alegação de número global fixo de instâncias: algumas são produzidas pelo carregamento dinâmico.

Geometria compartilhada em duas superfícies opacas; CityPropKit mantém sua malha agrupada. Dimensões e alturas dos assentos foram mantidas. A revisão física corrigiu a transformação de bancos na vila dos caminhoneiros e a colisão da nova malha dos bancos da vila da montanha.

Um diagnóstico adicional de cantos encontrou quatro falhas em uma consulta única de movimento de 3 m nos bancos sobre a plataforma do terminal da vila. Raios acertaram o colisor correto; movimentos reais em passos de 5 cm pararam contra o próprio VillageBench a 0,366/0,410 m do início, antes de alcançar o canto a 0,5 m. Não se ampliou o móvel nem seu colisor para contornar a consulta. O teste de jogabilidade passou a reproduzir o percurso em passos; o diagnóstico da consulta longa permanece em `../bench-corner-diagnostic-20261002.log` e não é alegado como aprovado.

## Fogo

Sete fontes exteriores: logging_camp, summit_camp, smuggler_camp, outfitters_heater, patrol_shelter, transit_village e resort_brazier. Lenha com material, brasas, pedras e cubas ocas; chama curva compartilhada substitui cones/esferas. As dez lareiras interiores utilizam a mesma família de efeito; arquitetura das lareiras, regras térmicas, iluminação e quantidade/cadência dos elementos animados permanecem.

## Validação

- Godot 4.7.2 .NET, Harbor.csproj compilado antes da execução.
- `test_mountain_trail_blend.gd`: 552 verificações aprovadas; continuidade X/Z, união sem escurecimento duplicado, isolamento do chão distante e altura renderizada.
- `test_mountain_terrain_contract.gd`: 107 verificações aprovadas; malha/colisão, raios físicos, emendas e remoção/recriação de trechos.
- Bancos: 54 verificações do helper e 405 verificações físicas em 24 bancos de famílias distintas, sem falhas no percurso validado. Quatro anomalias da consulta longa são registradas separadamente, conforme diagnóstico acima. Logs `../bench-finish-20261002.log` e `../bench-native-collision-20261002.log`.
- Fogo: 80 verificações de forma, limites físicos, integração e recarga; 11 de admissão e 121 térmicas, sem falhas.
- Fogo renderizado: sete fotos reais em `../fire-review-20261002/temporal/source_<id>.png`. Sequências de 30 s no resort de dia/noite e no interior Summit: 4.034 quadros. A análise da região das chamas não encontrou apagões; os pares de maior variação foram inspecionados sem popping. Isso cobre esses três cenários, não todas as fontes em movimento. O custo de gravar cada quadro impede usar a sequência como benchmark.
- Capturas e medições iniciais em `before/`, Main renderizado em 1280 × 720, Mobile, RTX 4060 Laptop, 30 s por cenário, sem salvar.

## Comparação renderizada

Main terminou sem erros de script/renderização. Capturas equivalentes `before/ground.png` e `after/ground.png` mostram a remoção da faixa retangular escura junto à fachada. Três ângulos adicionais em `after/ground-angle-*.png`; três raios físicos no local confirmaram apoio a y=0 (`after/ground-support.json`). `after/outfitters.png` também registra a correção do nome “Último Abrigo”.

| Cenário | FPS antes/depois | p95 ms antes/depois | p99 ms antes/depois |
|---|---:|---:|---:|
| Resort | 289 / 322 | 6,86 / 6,04 | 8,73 / 7,04 |
| Frente da loja | 269 / 179 | 7,48 / 11,55 | 8,47 / 12,79 |
| Vila | 162 / 137 | 10,47 / 13,04 | 11,74 / 14,85 |
| Lenhadores | 177 / 144 | 9,09 / 10,83 | 10,26 / 11,80 |
| Harbor | 363 / 144 | 5,70 / 10,80 | 7,07 / 11,90 |

**Performance não aprovada:** houve piora nas amostras de quatro cenários. O monitor `after-processes.jsonl` registrou outra captura (`capture_cobra_pose.gd`) durante a sequência. O estado do código e a carga também são compartilhados por sessões concorrentes. Não é possível atribuir essas diferenças exclusivamente a esta alteração nem alegar ausência de regressão. Relatórios brutos registram todas as amostras, p50/p95/p99/máximo e quadros acima de 33/66 ms. Não houve queda para 12–15 FPS sustentada nestes cinco intervalos, mas isso não substitui comparação isolada.

A praça construída da vila conserva contorno/colisão e passa a usar pedra aparente, distinguindo-a do terreno nevado contínuo: `final-village/village.png`, Main sem erros.

Oito fotos complementares dos bancos foram inspecionadas em `../bench-families-20261002/`: cemetery, ferry_shelter, truckers, depot, ski_lodge, lumberjack_shelter, harbor_clothing e harbor_police. A introdução foi corretamente pulada na execução final. A saída da Union bloqueou a sequência após a sétima foto; a delegacia foi capturada em execução independente, encerrada normalmente. A revisão visual dos oito ambientes foi concluída, mas esta sequência não certifica o retorno exterior da Union. Nenhuma regra de admissão/saída foi relaxada para obter as fotos.
