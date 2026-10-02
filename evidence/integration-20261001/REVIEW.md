# Consolidacao das sessoes — 01/10/2026

Rafael autorizou integrar as alteracoes das sessoes na copia principal, D:/geteco/game, ramo main. Os testes de jogo ficam com Rafael: esta rodada nao abre Godot nem mede desempenho.

## Conteudo

Base a05474d: roteador C#, launcher e instrumentacao/correcoes de travadas ja commitados.
Consolidacao dos arquivos ativos restantes: streaming e posse de caches, apoio fisico de veiculos e equipes, transito/mapa, transicoes e saves, porto, frota, atividades da vila, audio/queda de corpos, HUD, limpeza de warnings, documentacao e ferramentas/testes correspondentes.

Staging por lista explicita. Nenhuma copia completa usada em medicoes, exportacao ou captura bruta entra no commit. Os arquivos locais sao preservados.
Candidatos que existem apenas nas copias before/after permanecem experimentos. O candidato V1 de terreno tem falhas registradas e nao substitui o terreno ativo.

## Ramos antigos inspecionados

- codex/northgate-repair-spike (dc4b2e9): ancestral de main, nenhum commit exclusivo. Worktree sem alteracoes rastreadas.
- codex/v2-reactions-and-door-camera (e2c38ac): dois commits exclusivos, a6ac77e e e2c38ac. Worktree sem alteracoes rastreadas. Nao mesclados automaticamente: introduzem outro mecanismo de reacao a tiros e fade/transicao de portas em uma base antiga. A main evoluiu para acessos continuos (6ef0a8f), CivilianModel.take_hit e Actor._apply_hit_lean. As quedas direcionais adicionais desse ramo tampouco sao declaradas integradas. Preservado para uma adaptacao especifica futura, evitando substituir o comportamento atual.
- v1-legado e fontes de exportacao Android: historicos; nao integram a consolidacao do jogo atual.

## Revisao e limites

Aplicados os criterios das skills testes-com-criterio, performance-do-jogo e guardiao-do-jogo, alem dos contratos de interiores, transito e iluminacao, no limite da revisao estatica autorizada.
Dependencias literais de runtime presentes e sem marcadores de conflito nos arquivos ativos. O mapa atual e seu backup sao preservados como encontrados; as mudancas semanticas do mapa principal abrangem os acessos memorial/porto/Vertice e pontos de conexao de duas estradas da montanha.
Revisao de codigo nao certifica jogabilidade, colisao, iluminacao ou performance. Testes integrados e comparacao de frame time permanecem pendentes. Nenhum push nesta rodada.

### Ajustes de integracao

- A sonda probe_first_emergency ainda chamava EffectsPrewarm.run com um argumento. A nova API exige mundo e cortina durante o carregamento. A sonda agora confirma o aquecimento feito pelo carregamento, sem tentar executar o prewarm fora desse contrato; --no-prewarm continua sendo a variante fria.
- .gitignore exclui somente as copias congeladas identificadas; elas permanecem no disco.
- Parser externo gdtoolkit: 261 scripts lidos sem erro na primeira passagem; tres rejeicoes de lambdas compactas reproduzidas tambem em HEAD (FortOperation, Weather e ContextualHUDManager). Isso e uma limitacao/preexistencia da verificacao externa, nao compilacao do Godot nem aprovacao de runtime.
- Outras sessoes continuaram editando durante a revisao. Conferir conteudos por hash no staging para identificar alteracoes posteriores, sem sobrescreve-las.

### Fechamento do lote

Incluidas tambem as alteracoes concorrentes de navegacao incremental de policiais, busca incremental de fuga de civis, indice espacial de candidatos de spawn e prewarm visual coberto pela carga. Revisados consumidores, cancelamento/contexto, limites de trabalho e dependencias. Atualizacoes finais da fila preservam trabalho de busca durante movimento normal e solicitam atualizacao curta quando o alvo muda.
A checagem do diff preparado passou; todas as dependencias literais load/preload dos arquivos do lote estao no indice do Git. As tres rejeicoes externas preexistentes continuam sendo ressalvas, e Godot/testes/benchmark nao foram executados.
