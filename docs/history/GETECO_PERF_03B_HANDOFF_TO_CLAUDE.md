# GETECO-PERF-03B — Transição Antigravity para Claude

**Data**: 2026-09-16  
**Origem**: Antigravity  
**Destino**: Claude  
**Base HEAD**: `6f09c7dc7f2147d28c5669c91ed364b1c7517f48`  
**Escopo**: Conclusão da Validação Integrada da 03B e Fechamento Documental do Benchmark Corrigido.

---

## 1. Regras Críticas de Trabalho Concorrente e Git
- **NUNCA** execute `git checkout`, `git restore`, `git reset --hard` ou `git clean`.
- O repositório contém alterações locais legítimas de ambas as sessões (inclusive a soundscape restaurada em `a76adbf` e os 6 arquivos de produção da Mountain Pass).
- Não altere arquivos do jogo em `world/`, `characters/`, etc. O escopo é estritamente o instrumento de teste (`tests/perf_audit_antigravity/`).
- Use sempre `tests/perf_audit_claude/Invoke-GodotTestLocked.ps1` para qualquer execução do Godot.

---

## 2. O que já foi realizado e validado pelo Antigravity

1. **Correção Completa dos 8 Vícios do Coletor Original**:
   - `tests/perf_audit_antigravity/benchmark_session.gd` foi totalmente reescrito e corrigido:
     - **Tráfego e física 100% de produção**: Remoção das linhas que zeravam `collision_layer` e desativavam `_physics_process`.
     - **Carro pessoal legítimo**: Usa `PersonalCarManager.car` (`Monaliza`), com embarque real.
     - **Direção autônoma por entradas de jogo**: Substituição total de teleporte/cinemática por simulação de entradas analógicas/digitais (`Input.action_press/release`).
     - **Transições naturais**: Observação passiva do ciclo de `ContinuousWorld._process()`, sem chamadas manuais a `_update_region()`.
     - **Contagem recursiva de nós**: Implementada a verificação profunda de subárvore via `_count_nodes_recursive()`.
     - **Desembarque natural**: Via ação `exit_vehicle`.
     - **Amostragem contínua sem lacunas**: `ContinuousSampler` em prioridade `-1000` cobrindo todas as fases continuamente, gerando `frame_times.csv`.

2. **Prova de Contabilidade do Coletor (APROVADO 5/5)**:
   - O teste `tests/perf_audit_antigravity/test_collector_accounting.gd` foi executado pelo runner e **passou com Exit Code 0**:
     - Fechamento da soma de deltas contra o relógio monotônico: `diff = 0 µs`.
     - Fronteira final capturada perfeitamente.
     - Detecção de timeout e rejeição de avanço falso comprovada.

3. **Validação da Condução Ativa na Montanha (Fase 4)**:
   - Na última execução da sessão piloto (`wall_s = 201.2s`):
     - **3 voltas completas** no circuito da montanha foram executadas com sucesso (`actual_drive_duration_s = 83.966s`).
     - **3.258 quadros** coletados em condução ativa, média de **25.77 ms (~38.8 FPS)**, zero congelamentos graves na montanha.

---

## 3. Ponto Exato Onde Parou (Diagnóstico da Última Execução)

Na sessão piloto recém-concluída, o carro completou com sucesso a travessia de ida e as 3 voltas ativas na montanha. Ao retornar pela ponte inbound (Fase 5), ele encontrou o veículo de tráfego `MountainTraffic7` parado na ponte em `x = 7065.0, y = -4601.1` (no final de seu trajeto da montanha antes da transferência de fronteira).

O controle do carro do jogador detectou o veículo à frente e parou atrás dele com segurança (`tgt_spd = 50.0`, `spd = 8.8`, `dist = 88.1`). Como o `MountainTraffic7` estava estacionário e o waypoint alvo do jogador estava a 98 px de distância, a condição `lead_to_wp.length() < 70.0` não avançou o waypoint, gerando timeout na rota inbound.

### A Solução Simples e Imediata:
Na travessia inbound de retorno (em `HarborMountainConnector.gd`), a ponte tem **largura livre de mais de 200 pixels** (guard-rails em `y = -4725` e `y = -4395`, enquanto a pista central fica em `-4591` a `-4640`).

Basta aplicar no contorno de veículos estacionários na ponte inbound o mesmo desvio lateral que já funciona perfeitamente na ponte outbound para o `HarborTraffic_41`:
- Quando `lead_node` estiver parado (`lead_ls < 5.0`) e `pos.x < 7300.0 and pos.x > 6200.0`:
  - Desviar levemente para o acostamento norte da ponte (`y = -4540.0` ou `-4530.0`), ultrapassando o veículo parado com 50 px de folga a 75 px/s e continuando suavemente até o Harbor!

---

## 4. O que o Claude precisa fazer para encerrar a entrega

1. **Ajustar o desvio do veículo parado na ponte inbound** em `benchmark_session.gd` (linhas 530-540) para desviar caso encontre veículo com `lead_ls < 5.0` na ponte.
2. **Executar a Sessão Piloto Final**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/perf_audit_claude/Invoke-GodotTestLocked.ps1 -ScriptPath res://tests/perf_audit_antigravity/benchmark_session.gd -Run pilot_corrected -OutDir D:/geteco/game/tests/perf_audit_antigravity/results/pilot_corrected_runner -TimeoutSec 360
   ```
3. **Confirmar os Artefatos Gerados**:
   - `tests/perf_audit_antigravity/results/pilot_corrected/report.json` com `exit_code: 0`.
   - `tests/perf_audit_antigravity/results/pilot_corrected/frame_times.csv` contínuo.
4. **Escrever a Documentação**:
   - `docs/history/GETECO_PERF_03B_BENCHMARK_CORRECTION.md` contendo:
     - Errata detalhada do relatório anterior preliminar.
     - Diff e explicação das correções do coletor.
     - Prova de contabilidade (`test_collector_accounting.gd`).
     - Tabela com as métricas consolidadas da sessão piloto.
5. **Gerar o pacote de entrega**:
   - Criar `tests/perf_audit_antigravity/results/GETECO_PERF_03B_BENCHMARK_CORRECTION_package.zip`.
