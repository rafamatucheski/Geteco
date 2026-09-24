# Vegetação rasteira e rochas 3D

## Fontes e escopo

O V1 produtivo possui `world/mountain_pass/ForestFloorDetails.gd` (detritos, gravetos, pedras pequenas e cobertura de neve) e `MountainForestStreamer.gd` (árvores/rochas residentes por célula). No V2, `NativeRegion._prepare_forest` e `NativePine.gd` já representam a floresta; `NativeLake.gd` preserva polígonos e detalhes dos lagos. Esses elementos não foram substituídos.

`world/regions/TerrainDressing3D.gd` acrescenta tufos geométricos opacos, pedras pequenas e rochas com volume. É enriquecimento 3D autorizado, não reprodução exata de cada detrito V1. Não desloca árvores, ruas, lagos ou construções. Harbor retorna vazio deliberadamente: cobertura urbana precisa de polígonos próprios de jardim/canteiro para não ocupar calçadas.

## Contrato de integração

`build_chunk(rect: Rect2, region_id: String, height_at: Callable, is_reserved: Callable) -> Node3D`

- `rect` e argumentos dos Callables usam metros globais X/Z, incluindo o offset da serra.
- `height_at(Vector2) -> float` deve consultar a mesma superfície usada pela colisão do terreno. Altura não finita rejeita a amostra.
- `is_reserved(Vector2, radius: float) -> bool` deve retornar `true` para qualquer footprint que toque estrada, entrada/saída, lago/margem, trilha, atividade, construção, árvore existente ou zona sem implantação. A ausência de qualquer Callable retorna nó vazio.
- O integrador adiciona o resultado ao chunk, cujo transform deve continuar identidade. Descarregar o chunk remove MultiMeshes e colisões juntos. Não há cadastro global de instâncias nem processamento por frame.
- O módulo não está conectado por si só: a chamada em NativeRegion pertence ao integrador. Esta documentação não comprova execução dessa chamada.

## Limites e apresentação

Por chunk de até 64 × 64 m: no máximo 144 tufos, 36 pedras pequenas e 8 rochas sólidas, com tentativas únicas (reservas reduzem a contagem). Chunks maiores não aumentam esses tetos; menores reduzem proporcionalmente. Seed fixa por coordenada de chunk conserva o resultado ao descarregar/recarregar, desde que superfície e reservas permaneçam iguais.

Até cinco MultiMeshes por chunk compartilham malhas/materiais. Tufos têm cinco triângulos opacos, sem transparência nem sombras; pequenas pedras também não projetam sombras. Rochas maiores projetam sombra e recebem convex hull derivado da própria geometria transformada, sem escala não uniforme no corpo físico. Pedras pequenas são decoração sem colisão, não obstáculos físicos. A neve segue o limite geográfico original da serra; não há simulação climática dinâmica nem animação de vento nesta etapa. As amostras rejeitam encostas íngremes para limitar flutuação/penetração, mas isso não substitui inspeção visual do terreno.

## Estado e validação pendente

Implementação e revisão estática apenas. Não foram executados Godot, testes, benchmarks ou commits, conforme escopo. Compilação, colisão, oclusão, densidade visual e ausência de decoração em acessos precisam ser verificadas na cena integrada. A meta provisória é 60 FPS / 16,67 ms; hardware e baseline não foram fornecidos. Performance não aprovada: medir primeira visita e retorno à floresta, neve e margens, mantendo câmera, resolução, tráfego e clima comparáveis, especialmente custo de construção de convex hulls durante streaming. Limites finitos reduzem exposição, mas não demonstram desempenho.
