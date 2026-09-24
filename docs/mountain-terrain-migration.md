# Relevo da serra: adaptação 3D

## Fonte e escopo

Fontes lidas: `world/mountain_pass/MountainPass.gd`, `MountainSkiArea.gd`, `MountainSkiLayout.gd`; no V2, `OriginalWorldData.json`, `NativeRegion.gd`, `NativeLake.gd`, `PlaceCatalog.gd` e `OriginalVillageLayout.gd`.

O V1 fornece geografia horizontal, estrada e posições autoradas. A elevação nova não é altura recuperada do V1: é uma adaptação determinística 3D entre áreas reservadas. Não desloca ruas, edifícios, lagos ou acessos. Não representa, isoladamente, migração completa do mapa.

## Implementação e contrato de integração

`world/regions/MountainTerrain3D.gd` é `RefCounted`, sem atualização por quadro.

- `configure(roads: Array, entries: Array, clearings: Array) -> void`: recebe estradas NativeRegion; entradas e definições PlaceCatalog; clareiras adicionais `Rect2`. Todas as coordenadas são métricas globais XZ. Configure uma vez após reunir essas fontes.
- `build_chunk(parent: Node3D, rect: Rect2) -> MeshInstance3D`: aceita exclusivamente chunks 64 × 64 m alinhados à origem global, cria malha e StaticBody3D camada 1 com os mesmos triângulos. Retorna null com erro para dimensões desalinhadas. O pai deve usar transformação identidade, conforme os chunks atuais de NativeRegion.
- `height_at(point: Vector2) -> float`: altura contínua geradora dos vértices; não é a interpolação física entre vértices.
- `surface_height_at(point: Vector2) -> float`: altura interpolada no triângulo realmente criado, adequada para árvores, pedras e vegetação.
- `is_reserved(point: Vector2, radius: float = 0.0) -> bool`: reserva compartilhada para impedir decoração em estradas/acessos e locais autorados.

O integrador deve substituir MountainGround somente na serra, manter uma instância configurada por região e assentar árvores existentes usando `surface_height_at`. Não sobrepor o antigo colisor plano à malha. Toda decoração e colisão gerada fica filha do chunk: o descarregamento existente libera os recursos. Os índices de estradas e reservas pertencem à instância por região; não há cache global de malhas.

## Reservas e limites

Pista e calçada: meia largura da estrada + 3 m de acostamento/calçada + 6 m de margem para a triangulação. Entradas, retornos e fachadas: quadrados de 44 m centrados em cada posição fornecida. Clareiras adicionais recebem 6 m de margem.

Reservas base convertidas das coordenadas originais via `(p + MOUNTAIN_OFFSET) / 16`:

| Área | Retângulo V1 (x, y, largura, altura) |
| --- | --- |
| Lago alpino | 6680, -320, 800, 700 |
| Lago secreto / avião | 5080, -1500, 740, 680 |
| Vila | 7310, -2010, 690, 720 |
| Serraria | 6100, 350, 510, 430 |
| Ski / teleférico / lodge | 6100, -5050, 2050, 2350 |
| Heliponto / passarela | 6200, -2930, 380, 300 |

São envelopes conservadores das instalações existentes, não novas delimitações geográficas. Essas áreas continuam planas para não enterrar geometrias/objetivos que ainda usam y=0. Elevar pistas de ski exige migrar o contrato do controlador e das estações; está pendente, não foi simulado visualmente por uma superfície incompatível.

Entre reservas: ondulações suaves de 0 a 7,5 m, transição de 28 m, grade fixa de 4 m. Cores interpolam solo, rocha e neve por posição/altura, sem textura nova, luz, transparência ou animação. 289 vértices / 512 triângulos por chunk; uma malha, um corpo estático e uma forma côncava. Normais são calculadas por coordenadas globais, inclusive nos limites, evitando descontinuidade de iluminação causada pelo streaming. Índice espacial de segmentos por célula reduz buscas para altura.

## Evidência e pendências

Implementação revisada por leitura, incluindo interpolação da diagonal e ciclo de vida. A conexão em NativeRegion é responsabilidade da integração; este documento não a presume. Não foram executados Godot, compilação, testes, benchmarks ou commits. Não há comportamento, colisão, oclusão ou desempenho aprovados.

Pendências de validação autorizada futura: atravessar limites positivos/negativos dos chunks; caminhar sobre relevo, acostamentos e retorno às entradas; verificar rodas, pés e troncos; lagos sem terreno acima da água; acesso a vila, serraria, heliponto e ski; restauração de posição fora das clareiras; tráfego sem mudança de pista; inspeção visual da face superior e colisão do trimesh. Comparar frame time renderizado antes/depois na mesma rota, incluindo primeira carga. Meta provisória 60 FPS/16,67 ms, hardware ainda não definido; custo de criação do trimesh é risco de streaming e permanece sem medição.
