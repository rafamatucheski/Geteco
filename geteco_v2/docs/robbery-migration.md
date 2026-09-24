# Banco e posto: runtime nativo

`runtime/Robberies.gd` porta ações de `world/harbor/interiors/RobberyRoom3D.gd`, a consequência de `events/BankAftermath.gd` e o minigame original `ui/BankLockpick.gd`. Não adiciona depósitos, saques ou abastecimento inexistentes na fonte. `BankGuardModel` reaplica a roupa original do segurança ao rig policial nativo; `FuelCashierModel` e `CashierBaseModel` preservam o caixa original. Tesouro de `BankVaultTreasure` preserva geometria e materiais, agrupando caixas repetidas em MultiMesh.

## Contrato de integração

- Criar/adicionar Node; restaurar `state.world_state.robberies` quando existir; chamar `configure(session)`. Estado inválido deve bloquear autosave do save original. `snapshot()` retorna dados JSON, `restore_snapshot` valida antes de substituir; `validate_snapshot` também deve ser chamado por GameState.
- Priorizar `nearest_action()` e encaminhar `perform(action.target)`. Ação usa id `robbery`; apertar E inicia contagem, soltar ou se afastar cancela. Não conceder itens/recompensas diretamente na interface.
- Bloquear entrada `harbor_bank` se `can_enter_bank()` retornar false. A saída permanece livre. Banco fecha somente depois que jogador deixa o interior; quatro dias de600s reabrem e repõem tesouro, como a fonte.
- Retornar cedo em `FullSession._input` se `robberies.lockpick.active`: o CanvasLayer do minigame precisa receber Space/clique/Esc e manter jogador parado. O mundo continua ativo durante o minigame; alarme não desaparece ao cancelar.
- Para Primeiro Giro, consultar `bank_unavailable()` e `helena_position()`. A fonte oferece segunda via por ligação exterior na fachada quando Helena morreu/banco fechou/alarme disparou, sem procurado. Falas `bank_unavailable` já existem em OriginalDialogue. Sem esse hook, a progressão pode ficar bloqueada após assalto.
- Gameplay emite `weapon_fired(weapon_id,origin)` após tiro efetivo; módulo conecta esse sinal. `interior_actor=true` impede despacho médico para coordenadas técnicas de interiores.
- World fornece `NativePlace.set_vault_open(amount)`; apenas a porta gira/desliga sólidos, sem retirar partições. Coordenadas de guardas, caixa, cofre e três pilhas foram verificadas pelo agente de mundo com cápsula física.

## Comportamentos e persistência

Banco: disparo/dano alarma, guardas50HP, atendentes80HP, cartão cai ao derrubar segurança. Recolher cartão exige1,2s; interagir no cofre0,6s inicia disco original: três acertos, tolerância angular0,32, três erros cancelam. Sucesso inicia abertura de3s. Cada pilha exige presença e1,2s segurando; valores4000/3000/3000 e IDs bank_cash0..2. Recibos usam ID original mais ciclo de reabertura para permitir novo roubo após investigação, preservando idempotência dentro do ciclo. Saúde, cartão, pilhas, fase da porta, alarmes, timers e dias persistem.

Posto: caixa vivo80HP, arma equipada, mira ativa, distância<220/16m, alinhamento dot>.94 e raio desobstruído na altura dos olhos. Três segundos contínuos pagam180 uma vez com ID fuel_register. Resistência25% é sorteada uma vez e persistida; resistente não entrega dinheiro. Alarme despacha Wanted após30s e não pode ser repetido para criar múltiplos despachos. Dinheiro solto do interior, quando configurado pelo mundo, continua sendo recompensa independente do caixa.

Limitações explícitas: guardas atiram com visada real, mas não perseguem como V1; faltam fuga dos civis, drops de arma/colete e apresentação completa de corpos. Wanted recebe evento e posição exterior; isso não equivale ao bloqueio de viaturas e três dias de patrulha da fonte. Interdição deve ser representada no acesso pelo integrador. Não há comprovação visual/renderizada deste módulo apenas por teste headless.

## Testes

`tests/test_robberies.gd`: execução final32checks aprovada em Godot4.7.2, exit0, após corrigir inferência de tipo. Exercita guardas/modelos nativos com armas originais, eventos de tiro, cartão, falha/sucesso do lockpick, abertura progressiva, coleta/pagamento único, JSON, fechamento/reabertura, paredePhysics3D bloqueando mira, resistência do caixa e temporização do pagamento. A sessão de teste substitui a cena completa; física das salas foi verificada separadamente pelo agente de mundo. A execução restrita relatou somente logs user:// e certificados do SO indisponíveis, sem erros de script.
