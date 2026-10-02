# Claude — corrigir performance do caos no Geteco

Você vai colaborar com o Codex. Sua responsabilidade é identificar e corrigir custos excessivos de despacho, polícia e emergência sob carga. O Codex cuida da condução, dos sistemas compartilhados e da execução das medições integradas. Trabalhe até entregar uma correção revisável, ou um diagnóstico preciso caso ainda não exista causa demonstrada. Não faça otimizações especulativas para produzir um diff.

## Contexto obrigatório

Projeto: D:/geteco/game.

Leia AGENTS.md e estas skills, incluindo referências pertinentes:
- D:/CodexData/codex-home-clean/skills/guardiao-do-jogo/SKILL.md
- C:/Users/rafae/.codex/skills/performance-do-jogo/SKILL.md
- C:/Users/rafae/.agents/skills/testes-com-criterio/SKILL.md

Se um caminho estiver indisponível, procure a cópia do catálogo atual e informe a limitação.

Leia D:/geteco/game/evidence/guardiao-20260929/report.md e os dados em recovery/report.json. A revisão auditada é 622ea480c6169bfe08299005b095f36119e0e72a COM alterações locais: HEAD sozinho não representa o estado medido. Os hashes em recovery/source-before.json ajudam a conferir compatibilidade. Não faça checkout/reset/restore/clean nem descarte trabalho local; execute git status antes de operações Git.

## Evidência existente

Na RTX 4060 Laptop, i7-13650HX, Godot 4.7.2/Mobile, 1280×720, VSync e limite de 60 FPS:
- Estado normal: 59,7 FPS, p99 20,8 ms.
- Stress de 35 s: 22 FPS, p95 120,3 ms, p99 215,8 ms, máximo 1.400,1 ms.
- A carga admitiu 106 tiros, quatro explosões via API, seis estrelas e oito unidades de despacho ao final. Chegou a onze unidades depois de cessar os ataques.
- A vida era reposta durante a carga; depois houve morte e resgate produtivos. Ao fim de 60 s estavam zerados polícia, despacho, fogo e incidentes; últimos 30 s em ~59 FPS.
- Memória estática: ~383,9 MiB antes, ~415,9 MiB após carga, ~405 MiB depois da recuperação. Um ciclo não demonstra vazamento.

Isso demonstra custo integrado excessivo, mas ainda NÃO identifica um único sistema culpado. Não confunda o cenário preparado com gameplay humano end to end. Os avisos de recursos no encerramento também não provam vazamento durante a partida.

## Divisão de arquivos

Seu escopo de correção:
- gameplay/dispatch/**
- gameplay/police_response/**
- gameplay/emergency/**
- Testes diretamente relacionados em tests/dispatch/** e tests/police_response/**.

Arquivos compartilhados sob responsabilidade do Codex: scripts/**, runtime/**, world/**, gameplay/Gameplay.gd, gameplay/NativeTrafficRoutes.gd, gameplay/VehicleInterior.gd, gameplay/traffic_yield/**, project.godot e assets/**. Pode lê-los livremente. Se a causa estiver ali, entregue o ponto exato, evidência e a alteração proposta separadamente; não expanda silenciosamente sua frente.

## Execução paralela sem conflitos

O Codex será o único executor de Godot nesta rodada. Não inicie Godot, editor adicional, testes headless ou benchmarks enquanto o Codex mede: eles também competem por recursos. Entregue comandos e expectativas para o Codex executar. Isso não significa que testes ou performance já estão aprovados.

Prepare suas mudanças em um checkout/cópia isolado do ESTADO ATUAL relevante, preservando alterações locais existentes. Um worktree criado apenas de HEAD não contém esse estado. Se não houver isolamento confiável, produza uma proposta de patch sobre cópias dos arquivos que precisa editar. Não altere o runtime do checkout compartilhado durante a investigação/medição do Codex.

Entregue patch unificado com caminhos relativos ao projeto e hashes dos arquivos-base. O Codex confere, aplica sem descartar mudanças e executa validação dirigida. Não publique, faça push ou altere evidências históricas.

## Trabalho esperado

1. Mapear crime/estrelas → despacho → criação de viaturas/equipes → navegação/física → fogo/feridos → atendimento → encerramento/reciclagem. Identificar ownership, limites, callbacks, timers, filas e trabalho por frame/entidade.
2. Usar os dados existentes e leitura do código para priorizar hipóteses. Distinguir fatos, suspeitas e causas medidas. Se faltar perfil para decidir, entregar instrumentação pequena, temporária e desligada por padrão, com cenário e métrica necessários. Não aplicar uma otimização sem fundamento apenas porque parece cara.
3. Para causas demonstráveis, buscar trabalho redundante, planejamento repetido de rotas, consultas de física repetidas, criação de recursos e custos concentrados num frame. Reutilizar resultados com invalidação correta e distribuir tarefas respeitando prazos/reação do gameplay. Não introduzir cache sem contrato de invalidação, fila sem limite/limpeza, nem simplificar NPCs visíveis sem preservar comportamento.
4. Manter resposta policial, ameaças, dano, perseguição, atendimento, colisões e recursos visuais. Não reduzir a dificuldade, população, contagem esperada de unidades ou qualidade global para obter FPS. Preservar ownership único do despacho e limpeza idempotente.
5. Preservar Maciota/mecânico imortais e a garagem sem armas. Se tocar uma fronteira relacionada, indicar os testes necessários para essas regras. Não remodelar interiores nesta frente.
6. Acrescentar teste durável apenas para uma propriedade importante ou regressão demonstrada. Reutilizar suítes existentes. Não testar simplesmente a forma do novo código, enfraquecer assertions ou repetir até passar.

## Validação que o Codex executará

- Conferência dos hashes e revisão do patch; baseline nova apenas quando a evidência anterior não for comparável.
- Testes funcionais dos componentes alterados e suas fronteiras reais, incluindo ciclo de vida, cancelamento e recuperação pertinentes.
- Mesmo stress renderizado, população/configuração/carga equivalentes, warmup separado, janelas >=30 s e frames brutos. Relatar FPS médio, p50/p95/p99, máximo, frames >33,3 e >66,7 ms, carga efetiva e memória/entidades antes/pico/depois.
- Uma passagem no jogo normal para garantir que a correção de caos não prejudicou condução ou uso comum.
- Melhoria não basta para aprovação se ainda houver quedas severas ou meta descumprida. Mudanças de comportamento precisam ser identificadas, não escondidas no resultado de performance.

## Entrega

Use um diretório exclusivo em evidence/claude-caos-20260929/ para seus artefatos, sem sobrescrever arquivos existentes. Entregue:
- handoff.md: causa demonstrada versus hipóteses, mudanças, contratos preservados, riscos e pendências.
- changes.patch: correção/instrumentação revisável, quando houver.
- base-hashes.json: hashes SHA-256 e caminhos relativos dos arquivos-base.
- Lista curta de testes/comandos e resultados esperados; indique explicitamente o que NÃO foi executado.

Se concluir que falta uma medição específica, entregue primeiro o instrumento e a pergunta que ela responderá. O Codex executa e devolve o resultado; não invente uma causa nem declare performance aprovada. Evite relatórios extensos e refatorações laterais: a entrega deve permitir revisar, aplicar e medir a correção.
