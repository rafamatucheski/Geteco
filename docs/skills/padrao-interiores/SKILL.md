---
name: padrao-interiores
description: Criar, reformar ou revisar interiores acessíveis do Geteco e seus acessos conforme o padrão Chalé + Maciota, incluindo câmera, materiais, iluminação, profundidade e indicadores de entrada e saída.
---

# Padrão de interiores do Geteco

Antes de criar ou alterar um interior em `D:/geteco/game`, leia `AGENTS.md`, `docs/interior-standard.md` e, para alterações físicas, `docs/interior-physics-and-depth.md`. O padrão vale em todos os mapas, incluindo entradas exteriores e saídas interiores.

- Combine atmosfera, materiais e volume do chalé das três armas com clareza espacial, circulação e acabamento da garagem do Maciota. Referências não certificam seus comportamentos atuais.
- Use os defaults recomendados como ponto de partida ajustável. Cada estabelecimento mantém sua identidade. Não migre ambientes fora do pedido.
- Descreva brevemente câmera, escala humana, circulação, luz e interações antes de implementar. Resolva escolhas rotineiras dentro da autorização; não crie aprovação adicional obrigatória.
- Reutilize projeção de sólidos, apresentação de atores, indicador compartilhado e gerenciador de transições. Confira caminhos atuais. Diferencie fachadas que compartilham sala de interiores independentes e preserve o retorno ao acesso usado.
- Compare vendedores, funcionários e seguranças ao lado de Dante: altura e largura humanas, sem multiplicadores legados ou membros esféricos volumosos. Northgate Auto está excluída da reforma a pedido: manter apenas serviço e animação de entrada/saída do carro, conforme o padrão versionado.
- Orientação do usuário em 10/10/2026: portas de passagem a pé abrem ao caminhar contra a folha bem de perto, com gesto de empurrar; aproximação ou presença parada não abrem. Travessia a pé, teto e câmera por presença, sem E ou texto flutuante de entrada. Remover o retângulo laranja do chão em todos os acessos. Preserve interações funcionais, restrições e remapeamento nos acessos que ainda usam transferência por interação.
- Em implementações, siga `performance-do-jogo` e `testes-com-criterio` nos caminhos indicados pelo projeto. Documentação isolada não exige benchmark.
- Mantenha `docs/interior-standard-checklist.md` com total de lugares físicos, interiores distintos, concluídos, em andamento e restantes. Só conte como concluído após todos os critérios aplicáveis; marque evidências ausentes como pendentes.
- Para cada ambiente trabalhado, apresente fotos reais antes/depois e estado dos checks de visual, entrada/saída/controle, colisão/spawn, oclusão de jogador/NPC e desempenho renderizado. Registre caminhos das evidências. Não use imagem gerada como comprovação do jogo.
- Nunca transforme resolução, limite de FPS, captura isolada ou teste headless em aprovação de desempenho. Criar esta skill não migra nem certifica interiores atuais.
