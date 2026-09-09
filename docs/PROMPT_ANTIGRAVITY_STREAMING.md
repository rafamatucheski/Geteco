# Prompt para o Antigravity

Trabalhe no GETECO em D:/geteco/game. Leia README.md, CLAUDE.md,
docs/ARCHITECTURE.md e docs/PRESENTATION_BUDGET.md antes de editar.

Objetivo: preparar os modelos de arte para carregamento visual sob demanda,
reduzindo custo de construção sem mudar física, rotas, combate ou missão.

Contexto: os commits 928f8c8 e 29fd0c5 introduziram PresentationBudget.
Moradores, tráfego e Cobras já adiam modelos; emergência constrói no despacho.
O último perfil Vulkan registrou 5047 ms no frame inicial, 118 viewports e
745,3 MB de VRAM. São amostras individuais, não uma prova de causalidade.

Seu escopo é prototypes/gameplay_repair_art_0909/. Faça protótipos isolados
de apresentação reutilizável, com callbacks explícitos de construção/conclusão
e reset de pose, cor, dano e acessórios. Avalie compartilhamento de meshes e
materiais imutáveis; pintura e deformação individuais não podem vazar entre atores.
Preserve silhueta e identidade visual. Documente quais operações exigem o rig pronto.
Não edite arquivos de runtime compartilhado: integração fica com Codex.

Entregue um contrato de integração atualizado, demonstração isolada, tempos de
construção em milissegundos e evidências visuais antes/depois. Meça com Vulkan real,
nunca headless para performance. Grave saídas dentro do projeto, use staging explícito
e commite apenas seu trabalho. Não publique no GitHub sem solicitação do usuário.

Não afirme que os 5 segundos pertencem a um componente sem instrumentá-lo.
Não use call_deferred como garantia de separar frames; a fila pode drenar no mesmo
ciclo. Documente os limites da medição e o que ainda precisa de integração.
