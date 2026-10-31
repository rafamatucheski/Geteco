# Roteiro de teste — ramo `viagem-lages-testar` (31/10/2026)

Tudo deste ramo foi feito só por leitura do código, sem Godot nem Windows: nada foi
compilado, importado, testado nem jogado. Este roteiro é a primeira verificação real.

## Baixar

```bash
git fetch origin viagem-lages-testar && git checkout viagem-lages-testar
```

## Ordem

1. `tools/run_godot_locked.sh --path . --import` (texturas BC7 novas e normal maps).
2. `tools/run_core_suite.sh full`, os 4 testes do CLAUDE.md e os testes tocados hoje:
   `test_mining_raid`, `test_mining_yard_job`, `test_static_review_recheck`,
   `test_money_received_notice`, `test_infinite_money`, `test_contextual_ui`, `test_compact_hud`.
   Se algo quebrar ao abrir, suspeitos: divisão de `Gameplay.gd`/`FullSession.gd` e os `preload` novos.
3. `Jogar.cmd` e conferir:
   - morte/prisão e respawn, troca e recarga de arma (AK, RPG), lanterna, explosões em cadeia,
     tiro da polícia, drops, menus/lojas/diário/diálogo, salvar e carregar;
   - carros amassados, interior de veículo, polícia, esgotos, fachadas do litoral (MeshArrayCache:
     malha "contaminando" outra é o sintoma);
   - postes da serra à noite (LightBudget; `GETECO_LIGHT_BUDGET=0` volta ao antigo);
   - oficina do Digo e ônibus articulado (texturas);
   - ganhar dinheiro: aviso central "RECEBIDO · origem / +R$" com o som de caixa; dois ganhos
     seguidos somam; carregar save não avisa; saldo agora em "R$";
   - Limpeza da cava: entregar 3 pedras, pausar, falar com o operário e receber direto;
   - cair do mapa dirigindo: o carro volta ao último apoio com o jogador dentro e mensagem;
   - chegada: desembarcar e tentar Carregar durante a transição (botão desabilitado);
   - entrar na pedreira pelo portão da estrada; dirigir pelo deserto (paredes invisíveis);
   - atalhos movidos para `tools/launchers/`.
4. Export release: `tools/perf_cross_bench.sh` (A/B do cache de malhas e dos postes) e o
   benchmark de direção na rota oeste, agrupando `fall_points` do resumo
   (ver `docs/quedas-carro-benchmark-20261031.md`).

## Para revisar sem jogar

- Roteiros das gravações de Vicente: `docs/roteiros-arquivo-vicente-20261031.md` (aprovar antes
  de gerar as vozes).
- Achados reconferidos: `docs/reviews/static-review-recheck-20261031.md`.
- Mensagens encurtadas pelo aviso de dinheiro: "Neco pagou.", "Caixa roubado", "Dinheiro recolhido".
