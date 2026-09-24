# Oceano do Harbor — primeira implementação

Implementado em 22/09/2026 para a câmera ortográfica atual do v2. A imagem conceitual orienta a paleta; esta etapa não transforma o porto em praia nem acrescenta natação, barcos ou horizonte para uma câmera em perspectiva.

## Integração

`world/regions/NativeRegion.gd` substitui a caixa estática Water por `HarborOcean.gd` somente nos chunks de Harbor. Mantém o topo original em -0,94 m e não cria colisores. Terrenos, cais, pontes, lagos da montanha e regras de movimento permanecem sob seus controladores existentes.

Cada chunk de 64 m usa 289 vértices e 512 triângulos. Todos compartilham um ShaderMaterial opaco, sem transparência, cópia da tela, refração, luzes adicionais ou sombras projetadas pela água. Duas ondas analíticas usam coordenadas globais e TIME; não há atualização de malha por frame. As normais reagem à iluminação já existente. Distância às bordas dos terrenos originais e superfícies extras é calculada ao criar os vértices; controla a transição turquesa/azul e uma faixa discreta de espuma.

O descarregamento acompanha os chunks existentes. A distância é uma aproximação visual interpolada em grade de 4 m, não profundidade física; detalhes estreitos da costa podem exigir refinamento. O custo de construir essa grade durante streaming ainda precisa de medição.

## Evidência e limites

- `tests/test_harbor_ocean.gd`: PASS, distância em metros, limite de geometria, material compartilhado, altura original, ausência de colisão e igualdade dos vértices/cores nas emendas.
- `tests/measure/measure_harbor_ocean.gd --capture-only`: executado em Main.tscn real, Mobile/Vulkan, RTX 4060 Laptop, 1280×720, população solicitada 24, sem gravar save. Capturas de dia, caminhada e noite inspecionadas; execução renderizada sem erros no stderr.
- Imagens: `evidence/harbor-ocean.png`, `evidence/harbor-ocean-walk.png`, `evidence/harbor-ocean-night.png`.
- A execução funcional headless passou, mas o sandbox emitiu avisos de acesso aos logs de usuário e à loja de certificados. A execução renderizada posterior gravou logs no workspace.
- **Performance pendente por solicitação do usuário.** Nenhum FPS ou frame time desta entrega foi aprovado. Havia processos Godot de outras sessões; não foram encerrados. Não foi capturada baseline antes da edição.

## Comparativo preparado

Em janela isolada, executar o script de medição com `--no-save --skip-arrival --benchmark --population=24`, primeiro com `--baseline`, depois sem. O controle reconstrói a caixa/material anterior, inclusive altura, cor, roughness e sombras. É um controle reconstruído, não uma captura histórica anterior à mudança. Ambos usam a mesma cena, câmera, rota no cais, população, luz e configuração normal de VSync/limite de FPS. O script herdado registra 5 segundos de aquecimento e 30 segundos de amostras, p50/p95/p99, máximo e frames acima de 33,3/66,7 ms.

Alvo provisório: 60 FPS / 16,67 ms. Aumento acima de 5% em p95 ou p99 exige confirmação finita equivalente, sem alterar o critério após a medição. O controle reconstrói a apresentação após o carregamento inicial: medir primeira visita/streaming separadamente, além do regime estável. A rota preparada cobre o cais oeste; ponte e outros trechos continuam necessários antes de aprovação ampla.

Referência de shader: https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html

## Refinamento de contato — 22/09

As faixas largas de espuma calculadas pela distância interpolada foram removidas do material base. `HarborShoreWash.gd` gera faixas de até 1,7 m nas bordas expostas dos polígonos existentes, incluindo o casco autorado de Santa Mare. Bordas internas cobertas por terra são excluídas; a geometria é recortada por chunk e descarrega junto com Water. Em águas abertas não há mesh adicional.

`harbor_shore_wash.gdshader` anima uma crista que se aproxima da borda, intensifica uma espuma fina no contato e retorna mais fraca. O ciclo dura aproximadamente 8,7 segundos, com pequenas variações ao longo da borda. É uma representação visual para obstáculos estáticos, não simulação física nem rastro de embarcação em movimento.

A superfície principal continua opaca. Este refinamento acrescenta uma passagem transparente estreita por chunk com costa, com material compartilhado e sem sombras projetadas, luzes, colisores ou callbacks por frame. Há custo adicional de geometria, preparação e pixels transparentes; **benchmark continua pendente por orientação expressa do usuário**.

O teste funcional passou novamente, incluindo presença do efeito na costa e ausência em chunk de mar aberto. A captura com `--capture-only --shore-detail` registra dia, noite e 16 fases junto ao navio; não executa a medição de 30 segundos.

Captura final concluída com stderr vazio. Fases inspecionadas junto ao casco/cais e na orla; prévia animada em `evidence/harbor-shore-motion.gif`. A espuma usa variação irregular para evitar as marcas periódicas da primeira tentativa. Testes físicos anteriores permanecem válidos: as faixas são exclusivamente visuais e não introduzem corpos físicos.
