# Propostas parciais contra HEAD — arquivos compartilhados

Revisão estática de 16/10/2026. Não houve edição de produção, staging, commit ou execução do motor. Os arquivos `*.HEAD.gd` são cópias de `git show HEAD:<arquivo>`; `*.full-working.diff` registram o delta observado no início desta revisão, inclusive trabalho concorrente, somente para rastreabilidade.

## NativeRegion

`NativeRegion.HEAD-proposed.patch` reapresenta exatamente os trechos atuais relacionados à ponte sobre o contexto de HEAD: material compartilhado, exclusão do piso regional, recorte físico/visual de `_land_piece`, helper `_land_outside_bridge`, recorte exato da pintura e intervalo de 75 cm após a saída. O combinado corresponde exclusivamente aos três deltas originais own + land + paint. Não inclui as salvaguardas adicionais atuais de `_authored_surface` contra arestas/triângulos degenerados; a raiz deve atribuí-las separadamente se necessárias ao registro final. Não inclui `GPU_RELEASE`, mudanças da fila de liberação, material woodland/motocross nem alteração de sombras de woodland.

A proposta não depende dessas alterações concorrentes dentro do arquivo. `GROUND_CUT.subtract_exact`, `bounds`, `flat_mesh` e `_without_degenerate_edges` já existem em HEAD. A execução depende naturalmente de registrar o novo `UnifiedBridgeKit.gd` e seus recursos junto da implementação da ponte. O código proposto está em `NativeRegion.HEAD-proposed.gd.txt` apenas como evidência; não substituiu a produção.

## CityChunkDressing

`CityChunkDressing.HEAD-proposed.patch` contém apenas os três trechos do own.patch atual: preload do kit, reconhecimento do asfalto contínuo em `_road_clearance`, e exclusão dos remendos em `_road_wear`. Não inclui ranges/seleção de sombras, mudanças de telhados ou outros ajustes de performance concorrentes. As funções alvo e o contexto necessário já existem em HEAD. Depende do novo kit da ponte, sem dependência interna da reforma concorrente de dressing.

## HarborUrbanSurface

Não existe proposta alternativa contra HEAD. Preservado `HarborUrbanSurface.own.patch` como registro exato do trabalho da ponte em cima do working observado. O hunk do recorte chama `_rounded_parts(source,clipped)`, lê/altera `part.polygons` e agrupa `grouped[key].polygons`; HEAD não tem `_rounded_parts` e usa `group.rects`, convertido em polígonos somente em `_add_group`. O delta concorrente acrescenta `_rounded_parts`, `_round_outline`, metadados court/garden/finish/neighbour e muda `_add_group` para consumir polygons. Copiar o own.patch para HEAD sem esses pré-requisitos não é uma alteração parcialmente completa. Trazer esse contexto inteiro capturaria a reforma alheia de pátios, jardins e materiais.

Portanto, registrar o own.patch como artefato com esta dependência explícita preserva a autoria sem alegar que ele se aplica isoladamente a HEAD. Uma implementação alternativa adaptada ao caminho de retângulos de HEAD não corresponde ao código validado e não faz parte destas propostas.

## Verificação de aplicação, sem índice

`HEAD-proposals-check.json`: NativeRegion e CityChunkDressing aplicam com `git apply --check` em diretórios temporários contendo exclusivamente os arquivos copiados de HEAD; uma aplicação real apenas nessas cópias temporárias reproduziu byte a byte o texto proposto. Nenhum índice Git foi utilizado.

`original-patches-HEAD-check.json`: os own.patch originais de NativeRegion e CityChunkDressing falham contra essas mesmas cópias de HEAD, mas passam ao normalizar somente CRLF para LF. Logo, nesses dois casos a falha original de aplicação não comprova dependência alheia. HarborUrbanSurface continua falhando depois dessa normalização, coerente com a dependência estrutural acima. Os originais foram preservados sem alteração.

Esta verificação comprova aplicabilidade textual. Não adiciona validação de software, campanha, física, iluminação temporal ou performance às já documentadas no relatório principal. A raiz decide o que registrar e aplicar; o trabalho concorrente permanece intacto.

## Patches LF solicitados para a decisão da raiz

Salvos `NativeRegion.own.LF.patch`, `NativeRegion.land.LF.patch`, `NativeRegion.paint.own.LF.patch` e `CityChunkDressing.own.LF.patch`. A única transformação nesses quatro arquivos é CRLF → LF. Os três Native foram verificados e aplicados nessa ordem exclusivamente sobre uma cópia temporária de HEAD; o resultado gera o combinado `NativeRegion.HEAD-proposed.patch`, sem acrescentar outros hunks. Nenhum staging foi realizado.
