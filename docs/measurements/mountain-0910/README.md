# Serra: trânsito, colisões e povoado — 10/09/2026

## Alterações

- O controlador de cruzamentos do porto rejeitava as posições de nascimento de outra região e mandava toda a frota da serra para o mesmo fallback. A validação agora respeita o grafo proprietário da pista; nascimento também considera outros veículos.
- A transferência pela ponte aguarda espaço na faixa receptora. Nas curvas da serra, os veículos antecipam a redução de velocidade e comparam as carrocerias nas posições atuais antes de avançar.
- A colisão oceânica de Northbank atravessava a terra da montanha, inclusive a grama diante do primeiro abrigo. O recorte remove apenas a área de terra e preserva as barreiras de água.
- Último Abrigo reposicionado fora da via, dimensionado pela projeção de 18 px/m e conectado a um interior de roupas do mesmo sistema do porto. Sensores das portas reconhecem a camada real do jogador vindo do mapa 1.
- Chalés e galpão da serraria usam modelos 3D existentes. Timberline saiu da estrada. Pinheiros usam oito vistas 3D estáticas compartilhadas por floresta; colisões de troncos permanecem.
- 15 moradores de inverno, três paradas na neve, oito veículos circulando com sete tipos de catálogo e três veículos estacionados adicionais.
- Corrigidas expressões de teclado inválidas encontradas em sete scripts de interiores durante a integração; apenas essas linhas foram incluídas, preservando as outras alterações em andamento.

## Verificação

Godot 4.7.2. Testes funcionais em modo headless e capturas reais em Vulkan/Forward+ na RTX 4060 Laptop. Os resultados refletem o workspace integrado, que continha outras alterações simultâneas; não constituem medição de FPS.

| Verificação | Resultado |
|---|---|
| `test_mountain_world_consistency.gd` | Passou: nascimento separado (mínimo 509,9 px), população/frota, fila na transferência, curva sem sobreposição, entrada/saída por sete portas, condução na grama e cinco amostras de costa/terra |
| `diagnose_mountain_roads.gd` | Percorreu a rota a cada 24 px com as oito carrocerias: nenhum conflito com sólidos estáticos do mapa |
| `test_continuous_ambient_traffic.gd` | Passou: transferência bidirecional do mesmo veículo e suspensão/retomada por distância |
| `junction_traffic_contract_test.gd` | Passou: sinais, reservas exclusivas, conexões e limite de segurança |
| `test_mountain_life.gd` | 22 verificações passaram |
| `test_mountain_cabin_scale.gd` | 17 verificações passaram |
| `tools/check_references.py` | 611 referências verificadas, nenhuma quebrada |

Logs nesta pasta. O teste integrado terminou com aviso de quatro instâncias ObjectDB no encerramento; não houve falha de asserção. Alguns testes também registram o aviso de Camera2D ajustada ao modo físico pela interpolação.

## Capturas

| Região | Antes | Depois |
|---|---|---|
| Primeiro abrigo | [Antes](before/arrival.png) | [Depois](arrival.png) |
| Chalés | [Antes](before/chalets.png) | [Depois](chalets.png) |
| Parada na neve | [Antes](before/snow.png) | [Depois](snow.png) |
