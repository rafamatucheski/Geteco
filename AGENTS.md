# Preferências visuais do projeto

## Padrão obrigatório de interiores

- Antes de criar, reformar ou alterar apresentação, câmera, mobiliário ou acessos de interiores em qualquer mapa, carregue a skill `padrao-interiores`. Cópia versionada: [SKILL.md](docs/skills/padrao-interiores/SKILL.md).
- Siga [o padrão Chalé + Maciota](docs/interior-standard.md), combinando atmosfera e volume do chalé das três armas com clareza espacial e acabamento da garagem do Maciota. Entradas exteriores e saídas interiores usam o indicador compacto compartilhado.
- Mantenha [o checklist de migração](docs/interior-standard-checklist.md) com contagem de lugares e interiores distintos, fotos reais e validações. Não conte como concluído com checks obrigatórios pendentes.
- As referências não dispensam validação física e de performance nem autorizam migrar ambientes fora do pedido.

## Regras permanentes da garagem

- Maciota e o mecânico dele nunca podem morrer, em nenhuma circunstância: armas, explosões, fogo, atropelamentos ou eventos de missão. Preserve a ausência de rotinas de dano/morte nesses personagens; qualquer futura integração ao combate deve manter essa proteção.
- A garagem do Maciota é uma área sem armas. Guardar automaticamente a arma na entrada e na restauração de save; bloquear saque, troca, disparos, explosivos e ataques corpo a corpo enquanto estiver dentro. Preservar o inventário e liberar o uso ao sair.
- Validar essas regras ao alterar combate, os personagens ou transições da garagem. O teste dedicado da V1 (`tests/test_garage_weapon_restrictions.gd`) ficou no ramo `v1-legado`; na V2 use os testes de garagem em `tests/` (`test_garage_rewards.gd`, `test_garage_driver_restore.gd`, `test_garage_vehicle_transfer.gd`) e acrescente a verificação de armas quando mexer nessas regras.

- Para todo ambiente acessível e suas interações, siga obrigatoriamente [o contrato de colisão e profundidade](docs/interior-physics-and-depth.md). Jogador e NPCs não podem atravessar sólidos, nascer sobre móveis ou aparecer andando por cima deles. Valide colisão e oclusão separadamente; qualquer falha bloqueia a entrega.

- O usuário não quer textos descritivos ou decorativos explicando lojas, objetos, ambientes ou elementos visuais. Comunique essas informações pela aparência.
- Em fachadas, deixe somente o nome próprio do estabelecimento. Não acrescente categorias, slogans, legendas, descrições de produtos ou chamadas de coleção.
- Aplique essa orientação a novas implementações e às telas e ambientes que forem alterados. Preserve textos funcionais necessários para jogar, como ações, diálogos e objetivos.
- Vitrines de roupas devem usar manequins vestidos com proporções naturais, em vez de peças de roupa gigantes e isoladas.

## Performance do jogo

- Antes de implementar e ao validar mudanças com custo em runtime (iluminação, sombras, efeitos, modelos, SubViewports, NPCs, tráfego, física, streaming ou loops por frame), carregue e siga `C:/Users/rafae/.codex/skills/performance-do-jogo/SKILL.md`.
- Exija comparação de frame time antes/depois na cena real renderizada e nos cenários afetados. Teste headless, cobertura de luz e captura bonita não comprovam FPS. Preserve a intenção visual e a jogabilidade.
- Não declare performance aprovada com regressão confirmada, queda reproduzível para 12–15 FPS ou sem medição; informe precisamente a pendência. Mudanças apenas de texto/documentação dispensam benchmark.
- Se a skill estiver indisponível, informe e aplique estes critérios diretamente, junto de `testes-com-criterio` na validação de software.

## Segurança do Git e Trabalho Concorrente (CRÍTICO)

- NUNCA execute `git checkout`, `git restore`, `git reset --hard`, `git clean` ou qualquer comando que descarte alterações locais em arquivos que tenham modificações não commitadas — nem para desfazer a própria edição, nem para "limpar" conflitos.
- Este repositório opera com múltiplas sessões simultâneas de IA sem commits imediatos. Descartar arquivos locais destrói trabalho em andamento de outras sessões.
- Antes de qualquer ação que envolva estado do git, execute `git status` primeiro.
- Caso precise desfazer alterações:
  - Para reverter apenas a sua própria alteração, desfaça a edição manualmente no arquivo ou utilize `git stash` (NUNCA utilize `stash drop` ou descarte stash sem verificar o conteúdo).
  - Se houver conflito ou arquivo alterado por outra sessão, NUNCA tente resolver descartando ou sobrescrevendo: notifique o usuário imediatamente.
