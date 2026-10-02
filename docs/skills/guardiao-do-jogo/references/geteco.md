# Pontos de partida do Geteco

Inspecionados em 29/09/2026. Confirme caminhos/comportamento antes de executar; este mapa não comprova qualidade.

- Raiz: `D:/geteco/game`. `project.godot` inicia em `ui/MainMenu.tscn`, declara Godot 4.7/Mobile, viewport 1280×720 e limitador de 60 FPS. Medidores usam `Main.tscn`; limite configurado não comprova FPS sustentado.
- Sessão: `runtime/SessionLaunch.gd`, `runtime/FullSession.gd`, `scripts/V2Session.gd`, `scripts/World.gd`. Persistência: `runtime/SaveStore.gd`. Derive inventário de registros/cenas atuais, não de lista histórica congelada.
- Leia AGENTS.md e, nos fluxos acessíveis, `docs/interior-physics-and-depth.md`. Ao alterar interiores, carregue `padrao-interiores` e siga o checklist do projeto. Colisão e oclusão precisam de validações separadas.
- Maciota e seu mecânico são imortais. Garagem guarda arma ao entrar/restaurar save, bloqueia saque/troca/disparos/explosivos/corpo a corpo, preserva inventário e libera ao sair. Verifique ao alterar combate ou transições relacionados.
- Testes: `tests/test_garage_rewards.gd`, `tests/test_garage_driver_restore.gd`, `tests/test_garage_vehicle_transfer.gd`. Não presumir que cobrem todas as restrições de armas.
- Medição: `tests/measure/Measure.ps1`, `measure.gd`, `measure_full.gd`. Leia flags, duração, destino e cena antes de usar. Wrapper tem caminho local de executável; slice/sandbox não substituem gameplay completo. Use prefixo exclusivo, sem concorrência.
- `tests/measure/measure_event_hitches.gd` mede eventos frios/quentes por chamadas diretas e com diretores desligados. Serve ao diagnóstico, não à aprovação end to end. Inspecione destinos fixos para não sobrescrever resultados.
- Reutilize `tests/dispatch/`, `tests/police_response/`, `tests/garage_guards/` e medidores especializados após verificar se exercitam fluxo real ou estado montado artificialmente.
- `docs/HARBOR_GAMEPLAY_ACCEPTANCE.md` fornece roteiro histórico e limitações. Prefixos `geteco_v2` e referências V1/HarborGame podem estar obsoletos para a raiz atual.
- `--no-save` não prova isolamento por si só; confira leitores/caminhos de gravação. Testar persistência exige armazenamento temporário exclusivo e preservação dos slots pessoais.

Localize skills complementares no catálogo ativo. Caminhos conhecidos: `C:/Users/rafae/.codex/skills/performance-do-jogo/SKILL.md` e `C:/Users/rafae/.agents/skills/testes-com-criterio/SKILL.md`. Se indisponíveis, informe e aplique os mínimos do SKILL.md e AGENTS.md: medições comparáveis, hipóteses, tentativas finitas e ausência de mascaramento de falhas.
