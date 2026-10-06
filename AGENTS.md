## Motor do projeto: Godot .NET e C#

- O projeto usa GDScript e C#; use sempre **Godot 4.7.2 .NET (mono)** para editar, executar e validar. A edição comum sem .NET não é o ambiente do projeto.
- Instalação local: `D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64`.
- `Editar.cmd` e `Jogar.cmd` preparam e compilam `Harbor.csproj` antes de abrir. No editor .NET, F5 executa esse mesmo projeto com os scripts C# compilados.
- Para testes diretos, compile `Harbor.csproj` antes de iniciar o motor; use a variante `_console.exe` dessa instalação para capturar logs. Os runners principais fazem essa compilação automaticamente.
- Preserve a coexistência GDScript/C#; não converta sistemas sem necessidade do pedido. Não valide silenciosamente pelo fallback GDScript quando o teste exigir o caminho C#.

## Progressão da cidade 1 para o mapa 2

- A ponte da cidade 1 para o mapa 2 deve estar visivelmente em construção e bloquear a travessia enquanto a última missão da cidade 1 não estiver concluída.
- A obra só termina e a passagem para o mapa 2 só é liberada ao concluir a última missão da cidade 1. Preserve essa condição ao alterar a ponte, as missões, a progressão ou a restauração de saves.
- Preserve a disposição da V1: a continuação para o mapa 2 segue para cima/norte no mapa; a montanha tem uma saída lateral à direita/leste, com alça de acesso reconhecível e independente. O acesso à montanha fica disponível antes da barreira da obra. Não bloquear a ponte da montanha ao fechar a continuação norte nem criar ligação entre pistas que apenas se cruzam em alturas diferentes.
- Enquanto a ponte estiver em construção, mantenha barreiras físicas, operários trabalhando e o canteiro fora das rotas dos carros. A apresentação da obra e sua remoção devem acompanhar a mesma conclusão final da campanha.

## Montanha de gelo na campanha

- A montanha de gelo deve ter pelo menos duas missões ou side quests autoradas, com objetivos cumpridos no próprio mapa e ligação com a história de Dante. As provas de esqui e os colecionáveis existentes complementam esse conteúdo.
- O avião acidentado pertence aos Cobras e deve participar de uma investigação de carga. Na caverna próxima, Dante encontra uma pista de Vicente, seu irmão, indicando que passou por ali e que Dante chegou perto de encontrá-lo. Preserve a revelação maior do passado para o ato 2.
- Incluir uma corrida noturna de descida de carro em alta velocidade contra seis NPCs competitivos: seis adversários mais Dante, sete carros no total.
- Criar uma trilha própria para corrida de jipe por checkpoints e adaptar o cenário aos acessos, percurso, largada e chegada dessas atividades.
- O roteiro e o estado da implementação estão em [plano-montanha-cobras-20261005.md](docs/plano-montanha-cobras-20261005.md). Essas atividades ainda precisam ser implementadas e validadas; não conte este registro como conteúdo jogável.

# Preferências visuais do projeto

## Direção visual da cidade 4

- A cidade 4 é a última cidade do jogo. Sua atmosfera deve ter como referência a cidade de GTA IV: mais escura, com neblina e uma paleta mais acinzentada e menos saturada.
- Siga essa direção nas futuras implementações e revisões visuais da cidade 4.

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

## Qualidade e estabilidade da iluminação

- Ao criar ou alterar luzes de carros, postes, cidade, sombras ou reflexos, ou investigar flickering e popping, carregue `validar-iluminacao`. Cópia versionada: [SKILL.md](docs/skills/validar-iluminacao/SKILL.md).
- Exija evidência temporal na cena real renderizada e comparação de performance. Screenshot isolado e teste headless não comprovam ausência de flickering. Não aprove piscadas involuntárias nem oculte defeitos apagando luzes necessárias ou degradando a qualidade global.
- Restrinja a conclusão aos cenários efetivamente validados e registre pendências; a skill não certifica automaticamente toda a iluminação do jogo.

## Segurança do Git e Trabalho Concorrente (CRÍTICO)

- NUNCA execute `git checkout`, `git restore`, `git reset --hard`, `git clean` ou qualquer comando que descarte alterações locais em arquivos que tenham modificações não commitadas — nem para desfazer a própria edição, nem para "limpar" conflitos.
- Este repositório opera com múltiplas sessões simultâneas de IA sem commits imediatos. Descartar arquivos locais destrói trabalho em andamento de outras sessões.
- Antes de qualquer ação que envolva estado do git, execute `git status` primeiro.
- Caso precise desfazer alterações:
  - Para reverter apenas a sua própria alteração, desfaça a edição manualmente no arquivo ou utilize `git stash` (NUNCA utilize `stash drop` ou descarte stash sem verificar o conteúdo).
  - Se houver conflito ou arquivo alterado por outra sessão, NUNCA tente resolver descartando ou sobrescrevendo: notifique o usuário imediatamente.

## Auditoria da malha viária

- Para auditar ruas, conexões, cruzamentos, semáforos e coerência do trânsito, carregue `auditoria-viaria`. Cópia versionada: [SKILL.md](docs/skills/auditoria-viaria/SKILL.md). Aplique os critérios pertinentes também na validação de alterações nesses sistemas, sem exigir auditoria da cidade inteira para uma mudança local.
- Compare geometria, grafo dirigido, sinalização visível e comportamento na cena real. Teste isolado de fases não aprova todos os cruzamentos; registre cobertura e pendências. Auditar não autoriza redesenhar o mapa fora do pedido.

## Qualidade integrada e estabilidade

- Em auditorias do jogo ou mudanças que atravessam sistemas ou alteram carga/ciclo de vida compartilhados, carregue [guardiao-do-jogo](docs/skills/guardiao-do-jogo/SKILL.md).
- Dimensione a validação pelo impacto: cadeia afetada em mudanças locais; inventário de áreas, transições e sistemas em auditorias amplas. Inclua jogo normal, caos plausível e recuperação pertinentes, com evidência real e lacunas explícitas.
- Esta skill complementa performance-do-jogo e testes-com-criterio; não exige auditoria global a cada ajuste nem benchmark para documentação.
