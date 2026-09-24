# Pintura original dos veículos

Implementado em 21/09/2026. **Não validado no Godot; testes, inspeção visual e medições foram adiados por instrução do usuário.**

`Vehicle.paint_color` agora aplica a cor aos materiais da carroceria. A ligação acontece uma vez na criação, preservando malhas e duplicando somente os materiais de pintura por veículo; mudanças posteriores atualizam esses materiais sem reconstruir geometria nem percorrer a cena por frame.

A identificação usa metadados originais `*_material_key` e `*_surface_material_keys`, inclusive superfícies separadas da geometria preparada do Ironback. Exportações sem esses metadados usam a receita exata de cor, metalicidade e rugosidade da fonte original, registrada para os 49 arquétipos e o Ironback em `runtime/VehiclePaintSources.json`. O manifesto referencia as fontes apenas para rastreabilidade; não carrega scripts V1. Materiais de vidro, borracha, interior, faixas, cromados e luzes não são selecionados por semelhança de cor. A clonagem preserva os demais parâmetros do material original.

Referências: `HarborCoupe.repaint_vehicle`, `RearEngineCoupe.mat`, `EstateBody.build`, `BossMuscleModel._bind_materials` e os modelos indicados no manifesto. Cores iniciais vêm da paleta original do FleetCatalog quando nenhuma cor explícita foi atribuída. Garagens, residência e veículos de missão já atribuem `paint_color` e passam a utilizar o mesmo setter.

`FleetState` grava `paint`, `vehicle_id` e `was_driven`, aceitando saves anteriores sem os três campos. O integrador aplica esses campos ao restaurar o carro e usa a admissão física existente para reembarcar o motorista. Pintar um carro destruído muda os materiais guardados, sem remover o aspecto queimado antes do reparo.

Pendências: carregar scripts, verificar visualmente materiais de todas as famílias, superfícies agrupadas/rodas/interiores, cores independentes em dois carros iguais, reparo após pintura e roundtrip de saves antigos/novos; comparar criação de frota renderizada. Nenhum desses checks é declarado aprovado neste lote.
