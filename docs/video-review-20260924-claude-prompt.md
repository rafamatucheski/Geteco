# Prompt para o Claude

Você vai colaborar na correção do Geteco V2 em `D:/geteco/game`, simultaneamente com o Codex e três agentes. Execute a sua frente de implementação, não apenas uma análise.

Leia primeiro `AGENTS.md` e `docs/video-review-20260924-action-plan.md`. Leia também o relatório de evidências em `C:/Users/rafae/.codex/visualizations/2026/09/24/01a0d558-4410-7471-98cb-1032e2e21647/relatorio-video.md`, principalmente os itens 30, 32 e 33. O código atual já contém alterações posteriores ao vídeo: confirme os problemas antes de editar.

**Sua frente exclusiva é catálogo e personalização da Ammu-Nation.** Arquivos reservados para você:

- `runtime/HarborAmmunationCatalog.gd`
- `runtime/HarborWeaponWorkbench.gd`
- Testes novos com prefixo `tests/test_claude_arsenal_ui_` e evidências em `evidence/claude-arsenal-ui-20260924/`.

Implemente:

1. Fazer descrição e estado do acessório corresponderem à opção selecionada. O vídeo mostra “Original / Sem acessório” selecionado e “Instalado”, mas descreve silenciador. Diferencie item instalado, prévia selecionada e compra disponível. Não altere preços, saldo, inventário ou regras econômicas para esconder a inconsistência.
2. Melhorar contraste do catálogo/workbench, inclusive abas, opções secundárias, estados desabilitados e arma contra o fundo. Preserve o estilo existente e textos funcionais. Não acrescente slogans ou textos decorativos.
3. Deixar preço e posse claros e consistentes. A pistola inicial tem preço zero no catálogo de dados; não presuma que isso é um bug econômico. Exibir “Já possui” e custo quando pertinente sem comunicar uma compra gratuita indevida.
4. Conferir navegação por mouse/teclado, seleção de categorias, voltar/fechar, troca de acessórios e feedback de compra indisponível. Adicione somente testes proporcionais que validem comportamento real.

**Limites de concorrência:** não edite `FullSession.gd`, `ProductionWorld.gd`, `Services.gd`, `WeaponShopEntrance.gd`, `scripts/Actor.gd`, `scripts/Driving.gd`, `scripts/Vehicle.gd`, `scripts/CameraRig.gd`, sistemas de tráfego/polícia, geometria urbana, modelos/rigs de armas compartilhados, `tests/run_suite.ps1`, `project.godot` ou o checklist de interiores. Codex cuida de estabilidade, veículos, NPCs, interiores, transições e performance. Se precisar de alteração fora dos dois arquivos reservados, descreva a integração necessária no seu relatório, sem invadir outra frente.

Execute `git status` antes de qualquer operação de Git. Existem muitas alterações locais não commitadas de outras sessões: preserve todas. Nunca use `git checkout`, `git restore`, `git reset --hard`, `git clean`, descarte de stash ou sobrescrita de arquivo inteiro para limpar mudanças. Releia os arquivos antes de cada patch e pare a edição do trecho se perceber mudança concorrente inesperada.

Siga `C:/Users/rafae/.agents/skills/testes-com-criterio/SKILL.md`. Se a alteração introduzir custo de renderização, carregue `C:/Users/rafae/.codex/skills/performance-do-jogo/SKILL.md`. Não execute benchmark enquanto o Codex estiver medindo; não encerre processos alheios nem altere saves pessoais. Use saves isolados e registre quando a validação renderizada depender de janela exclusiva. Headless não aprova visual nem FPS.

Entregue implementação, lista exata dos arquivos alterados, testes executados/resultados, capturas reais quando disponíveis e pendências. Não faça commit, merge ou refatoração fora do escopo. Salve o relatório em `docs/claude-arsenal-ui-20260924.md` para o Codex integrar.
