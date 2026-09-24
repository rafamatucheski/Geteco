# Paridade de combate V1 → V2 (rodada de armas, disparos e efeitos)

Data: 21/09/2026. Método: leitura estática do V1 de produção (`characters/Player.gd`, `guns/Bullet.gd`, `GrenadeProjectile.gd`, `FlameJet.gd`, `guns/combat/*`, `ProceduralAudio.gd`, `audio/combat`, `audio/reload`) contra o V2 (`gameplay/Gameplay.gd`, `Projectile.gd`, `WeaponCatalog.gd`, `ArsenalWeapon3D.gd`, `Economy.gd`, `GameState.gd`, `FullSession.gd`).

> **Nada foi executado.** Sem Godot, testes ou benchmarks. "Implementado" e "conectado" significam existência do código e da chamada por leitura. Não há paridade visual, sonora ou de desempenho aprovada.

Legenda: **E** = implementação existente antes da rodada; **C** = conexão estática verificada por leitura; **N** = comportamento não executado.

## Tabela

| Funcionalidade | Fonte V1 | Implementação V2 | Chamada no jogo principal | Correção desta rodada | Pendência |
|---|---|---|---|---|---|
| 16 armas e modelos | `guns/WeaponCatalog.gd`, `scripts/player/ArsenalWeapon3D.gd` | `gameplay/WeaponCatalog.gd` (mesmos 16 ids), `ArsenalWeapon3D.build` cobre os 16 ids (E) | `Gameplay._update_visual` monta o modelo na mão do esqueleto (E, C) | — | Malhas conferidas só por existência do ramo; N |
| Mira, disparo, alcance, dispersão, dano | `Player._shoot_towards`, `Bullet`, `WeaponCatalog.distance_damage` | Raio 3D por pellet, alcance ÷16, queda de dano por distância, `spread` aleatório (E) | `FullSession._process` → `gameplay.fire_at` (E, C) | — | V1 usa projétil com tempo de voo; V2 usa hitscan. Não mudado |
| Munição e recarga | `Player._reload_active_weapon`, `WeaponReload.duration` | `state.consume_ammo`/`reload_weapon` (Economy) (E) | tecla R → `Gameplay.reload_weapon` (E, C) | (1) Pente vazio agora recarrega sozinho quando há reserva, como o V1. Antes só mostrava mensagem, a cada quadro, sem cadência. (2) Duração de recarga = take mais longo do banco V1 (mín. 0,5 s) × `reload_multiplier`, com o tempo antigo como reserva. (3) Toca o take de recarga V1 | Tempos reais dependem da duração dos WAVs; N. Custo de primeira carga dos WAVs não medido |
| Troca de arma (teclas e anterior) | `Player._input` (`weapon_previous`, `weapon_slot_1..10`) | `weapon_previous` e `weapon_slot_*` estavam **mapeadas em `GameInput` e sem consumidor** (defeito) | `FullSession._input` só trata `weapon_next` e `unarmed` | `Gameplay._unhandled_input` trata `weapon_previous` (teclado/controle) e teclas 1–0 na ordem V1 (`SLOT_ORDER`), só em jogo livre; passa por `state.equip_weapon` | Roda do mouse troca nos dois sentidos, como na V1; `CameraRig` não tem mais zoom manual (22/09) |
| Corpo a corpo | `Player._perform_melee_attack` | `Gameplay._melee` (esfera, primeiro alvo, dano e cadência do catálogo) (E) | `fire_at` (E, C) | Som de golpe no ar (punho/soqueira/taco = golpe de punho, faca = `KnifeAudio`, machado = `BatAudio`) e som de contato (faca em corpo = `KnifeAudio.impact`; demais = impacto por material). Antes: silêncio | V1 tem cone, tempo de golpe do machado/taco, animação, `BodyWound`, `AxeSwingTrail` acionado pela pose. V2 não tem pose; o rastro do machado existe em `WeaponPresentation3D` mas **nada chama `update_blade`**. Não conectado |
| Granada | `Player._release_grenade`, `GrenadeProjectile` | `Projectile.gd` (`grenade`), quique 0,42, explosão em `Gameplay.explode` (E) | `fire_at` (E, C) | Alcance agora segue a distância até o alvo (60 px … `throw_range`), antes ~7 m fixos. Estopim 2,0 s (V1), antes 2,3. Som de arremesso V1 | Ponto de queda calibrado por conta (`GRENADE_LANDING_SHARE`), N. Sem som de quique, sem animação de soltura, sem tremor de tela |
| RPG | `Bullet` com `is_explosive`, `RocketBackblast`, `RocketTrail` | Projétil `Projectile.gd`, explode ao bater ou no alcance (E) | `fire_at` (E, C) | O foguete **não fere quem o dispara** (`Bullet._trigger_explosion` exclui `owner_body`); a granada continua ferindo. Som de lançamento V1 (`rpg_launch`) e clarão de boca | Sem rastro, sem sopro traseiro, sem restos/estilhaços: efeitos V1 são 2D |
| Lança-chamas | `FlameJet` (partículas, cone, `PersonBurning`) | Raio com rastro largo + `emergency.ignite` no ponto final (E) | `fire_at` (E, C) | Rugido V1 em rajada reiniciada e parada ao soltar/recarregar/trocar/entrar em área sem armas; clarão de boca alongado como no V1 | V2 acerta um alvo por raio (V1: cone); não queima pessoas; acende o chão no alcance máximo mesmo sem alvo (regra do fogo V2). Crime do jato e dano por frequência: **corrigido na 2ª rodada** (seção ao final) |
| Clarão de boca | `Player._trigger_muzzle_flash_3d` (esfera + OmniLight) | **Ausente** (defeito) | — | `Gameplay._build_muzzle_flash/_flash_muzzle`: esfera emissiva + uma `OmniLight3D` sem sombra, reaproveitadas, escala e duração por arma (V1); silenciador reduz e apaga a luz | **Custo da luz por disparo não medido**; sem comparação renderizada de frame time. Não há garantia de posição do bico em todas as armas/acessórios |
| Rastros e impactos visuais | `Bullet` (traço), `ShotFeedback`, `WeaponEffects.spawn_impact/blood/shell` | Traço em caixa fina (`_trace`, teto 48) (E) | `fire_at` (E, C) | — | `ShotFeedback`, sangue, cápsulas, `ExplosionVisual/Remains`, `GroundBlood`, `PersonBurning`: todos `Node2D`/`_draw`; **não portados** (portar é reescrever, não reaproveitar) |
| Explosão | `ExplosionVisual`, `WeaponBlastDamage` | Esfera emissiva que encolhe + dano com queda + cobertura + `ignite` (E) | `Projectile.detonate` → `Gameplay.explode` (E, C) | Assinatura ganhou `hurt_source := true` (compatível); RPG passa `false` | Sem detritos/restos V1 |
| Áudio de tiro | `ProceduralAudio.get_gunshot_stream` | WAV `assets/gameplay/audio/<tipo>_<0..2>.wav` para 9 tipos (E) | `_sound` (E, C) | Tiro silenciado usa `suppressed_*` V1 (6 armas), −9 dB. `rpg` agora tem amostra | `pitch_variance`/`audio_volume_db` do catálogo continuam ignorados nos tiros (baseline −10 dB do V2 mantido) |
| Áudio de impacto | `CombatImpactAudio` (5 materiais) | **Ausente** | — | `_impact_sound` por material (autoria `impact_material`, gente = corpo, veículo = metal, resto = concreto), agrupa pellets em 40 ms | Materiais madeira/vidro dependem de `impact_material` autorado, que o mundo V2 não define; N |
| Arsenal/porta-malas da Monaliza | `PersonalLoadout`, `Player.can_carry_weapon` | `Economy.can_carry_weapon/enable_personal_loadout/set_personal_slot/claim_monaliza_starter`, `PersonalCar.perform` (E) | tecla `trunk` → `personal_car.perform` (E, C) | Nada alterado. Conferido por leitura: `equip_weapon` recusa arma fora dos slots; `cycle_weapon` e `equip_slot` pulam armas não carregadas; `consume_ammo` só age em arma carregada; munição e propriedade não são tocadas pela rodada | Sem animação de tampa nem visualização 3D; N |
| Garagem sem armas | `Player.weapons_forbidden`, `_block_garage_combat` | `GameState.weapons_allowed/can_attack/set_location` (E) | `attack_allowed()` guarda `fire_at`, `reload_weapon`, `cycle_weapon`, `equip_slot`, flash/áudio de chama; `explode` recusa explosivo do jogador; `set_location` roda em toda restauração (`FullSession` linhas 91, 105, 176, 428, 461, 987; `GameState.restore_snapshot` 89) (E, C) | Guarda extra: `_damage` ignora qualquer nó (ou pai, até 3 níveis) com meta `invulnerable`, além de o corpo dos residentes da garagem não ter `receive_damage`. Recarga, chama e reload cancelam o áudio ao perder `attack_allowed` | `tests/test_gameplay.gd` e o teste de garagem V1 **não foram executados**; auditoria de todo emissor de dano não feita |
| Maciota e mecânico invulneráveis | Modelos sem rotina de dano | `MaciotaPlace._resident`: `Node3D` com meta `invulnerable`, corpo `StaticBody3D` na camada 2 (E) | tiro, golpe e explosão só chamam `receive_damage` se existir; `_damage` agora também checa a meta (C) | Guarda explícita na `_damage` | Fogo (`Fire.gd`) e dano de veículo a essas pessoas não foram auditados |

## Contratos de teste existentes que precisarão de adaptação (não alterados)

- `tests/test_gameplay.gd:138-139`: "empty magazine cannot fire" seguido de `check(gameplay.reload_weapon(), "reload starts")`. Com o pente vazio, `fire_at` agora **inicia** a recarga; o `reload_weapon()` seguinte devolve `false`. Esperar `reload_timer > 0` depois do disparo vazio.
- Testes que contam duração de recarga fixa (1,35/2,2 s) precisam ler `CombatAudio.reload_seconds(id)`.
- `explode` continua com a assinatura antiga (5º parâmetro opcional); testes existentes não quebram por isso.
- Falta teste de: troca por tecla/anterior, granada por distância, RPG sem autodano, clarão de boca, invulnerabilidade por meta, cancelamento do áudio de recarga.

## Hooks para o agente principal (arquivos proibidos nesta rodada)

Nenhum é obrigatório: `Gameplay._unhandled_input` cobre a troca de arma sozinho. Se preferir o tratamento em `FullSession._input`, remova `_unhandled_input` de `Gameplay.gd` (evita troca dupla) e acrescente depois da linha de `weapon_next`:

```gdscript
elif event.is_action_pressed("weapon_previous") and not world.driving.occupied and not event is InputEventMouseButton: world.gameplay.cycle_weapon(-1)
```

e, para as teclas 1–0, um laço sobre `world.gameplay.SLOT_ORDER` chamando `world.gameplay.equip_slot(id)` com o mesmo guard de modal/abertura já usado ali.

## Riscos e o que não foi medido

- **Desempenho:** uma `OmniLight3D` (alcance 2,5 m, sem sombra) e uma esfera emissiva acesas por 35–90 ms a cada disparo; pool de áudio compartilhado; decodificação dos WAVs de recarga/impacto na primeira vez. Nenhum comparativo de frame time. A skill `performance-do-jogo` exige medição renderizada antes/depois em cena real; **não feita**.
- **Áudio:** níveis relativos (−14 dB nos impactos, −10 + `audio_volume_db` nas novas fontes, −19 dB silenciado) são escolhas para ficar coerentes com o baseline −10 dB dos tiros; não foram escutados.
- Os geradores procedurais usam semente fixa (V1 usava `randf`), então a textura é a mesma a cada execução.
- Caches estáticos de `CombatAudio` sobrevivem à saída da cena; pode aparecer aviso de recursos em uso no encerramento (já havia registro parecido no V2).
- GDScript não foi carregado: erro de sintaxe ou de tipo ainda é possível.


---

# 2ª rodada — procurado com lança-chamas e caminhos de dano da garagem

> Continua **sem execução**: nenhum Godot, teste, benchmark ou commit. "Existente" = código já lido antes; "estático" = conexão conferida por leitura; nada foi validado em jogo.

## 1. Procurado com lança-chamas

### Como o V1 pontua (código produtivo)

- **Não há crime por disparo nem por dano.** `Player._shoot_towards` e `FlameJet` nunca chamam `WantedManager`.
- Crime só nos desfechos: civil morto pelo jogador, `AnimatedPedestrian3D._die` → `report_crime(20)` (uma vez); policial ferido pelo jogador, `PoliceOfficer.take_damage` → `ensure_minimum_wanted_level(2)` (piso, idempotente); policial morto, `report_officer_killed` → mínimo 3 estrelas.
- O jato V1 (`FlameJet._apply_fire_damage`) dá **no máximo um dano por alvo a cada 120 ms** e cada jato acerta cada corpo uma vez.
- Guardas locais e cobras: `local_security`/cobra não geram procura por agressão.

### Defeitos demonstráveis no V2 (leitura de `Gameplay.gd` antes desta rodada)

| # | Evidência | Efeito |
|---|---|---|
| A | `fire_at` chamava `register_crime(4)` a cada disparo; o lança-chamas tem `fire_interval 0,05` (`WeaponCatalog`), 20 disparos/s | +80 pontos/s só pelo jato; 6 estrelas (240) em ~3 s |
| B | `_damage` chamava `register_crime(12/18)` a **cada** dano; o jato acertava a cada disparo | +240/s por civil atingido; contagem por frequência de atualização |
| C | `Fire.gd` (linha 55) chama `_damage` a cada 0,5 s por ator no raio enquanto o fogo aceso pelo jogador queima (até ~45 s antes de decair) | +12 por tique por vítima, repetido por dezenas de segundos |
| D | Escopeta (8 chumbos) e serrada (10) chamavam `_damage` por chumbo | uma vítima gerava 96–120 pontos em **um** tiro |
| E | Dano do jato a 20 Hz vs. no máximo ~8/s do V1 (cooldown 120 ms) | 2,4× mais dano por segundo só pela frequência |

### Correções (`gameplay/Gameplay.gd`; `gameplay/emergency/Fire.gd`, uma linha)

- **A:** o jato registra o crime do disparo (+4, mesmo valor V2) **uma vez por 1,0 s** de jato contínuo (`FLAME_SHOT_CRIME_INTERVAL`, `_flame_crime_clock`). Armas de fogo continuam +4 por disparo (+1 silenciada), sem alteração.
- **B/C:** `_damage(..., continuous)`. Jato e fogo passam `true`; `_crime_due` denuncia a mesma vítima **no máximo uma vez a cada 10 s** (`CONTINUOUS_CRIME_COOLDOWN`). A primeira agressão continua denunciada com o valor V2 (12 civil / 18 polícia). `Fire.gd` só ganhou o 4º argumento `true`.
- **D:** dentro do laço de chumbos de `fire_at` (`_in_pellet_volley`), a mesma vítima vale **uma** denúncia por disparo (`_attack_serial`). Chamadas diretas de `_damage` e golpes de disparos diferentes continuam contando: `tests/test_private_security_crime.gd` (três chamadas seguidas) não deve mudar de resultado, por leitura.
- **E:** `_flame_hit_due` limita o dano do jato a um por alvo por 120 ms (`FLAME_HIT_COOLDOWN`, valor V1). Não é balanceamento novo: restaura a taxa V1.
- **Preservado:** autodefesa (`gameplay_role == "cobra"` e raio de defesa em `fire_at`), `local_security`, crime de bala/faca/explosão por golpe, `register_crime` bloqueado na garagem.

### Diferenças V1 → V2 que permanecem (registradas, não corrigidas)

- V1 pontua na **morte** (20) e usa piso de estrelas contra policial; V2 pontua **por agressão** (12/18). Não alterado: seria balanceamento novo.
- Armas automáticas de fogo (SMG, AK, M4) seguem com +4 por tiro (~36/s a 0,11 s). Fora do pedido; decisão de balanceamento.
- A janela de 10 s e o intervalo de 1,0 s são **escolhas minhas, não calibradas**.
- `Actor.receive_damage` (`scripts/Actor.gd:143`) registra +25 por chamada quando o atacante é um veículo do jogador, e `Vehicle` (`scripts/Vehicle.gd:143-145`) chama `receive_damage` a cada quadro de contato com `impact_speed > 4`. Fora do escopo (transporte/atores): **contrato para o integrador**: registrar o atropelamento uma vez por vítima (por exemplo, quando `dead` passa a `true`, ou por janela), como o V1 (`_die` 20 / atropelo 6).
- O fogo aceso pelo lança-chamas segue sendo o sistema de emergência V2 (12 focos, ignição a cada disparo mesmo sem alvo).

## 2. Garagem e personagens protegidos

Caminhos de dano em `geteco_v2/`, conferidos por leitura:

| Caminho | Passa por | Maciota/mecânico (`ResidentBody`, camada 2, sem `receive_damage`; pai com meta `invulnerable`) |
|---|---|---|
| Disparo do jogador | `fire_at` → `_damage` | guarda `_is_invulnerable` (meta em até 3 níveis) + o corpo não tem `receive_damage` |
| Corpo a corpo e punhos | `_melee` → `_damage` | idem; `fire_at` nem executa na garagem |
| Explosão | `explode` → `_damage` | idem; `explode` recusa explosivo do jogador com `weapons_allowed()` falso |
| Fogo | `Fire._physics_process` → `_damage`; `EmergencyManager.ignite` recusa com `weapons_allowed()` falso | idem |
| Tiro de cobras (`CobraAgent.gd:127`) e de guardas (`garage_guards/Shot.gd:15`) | `_damage` | **passa a ser coberto pela guarda** (antes só o corpo sem método o protegia) |
| Atropelamento | `Vehicle.gd:145` chama `target.receive_damage` no **colisor** | o colisor é o `StaticBody3D` sem o método: não é ferido. **Este caminho não passa por `_damage`**: a proteção depende de o corpo não ter `receive_damage` |
| Eventos de missão | busca por dano/morte/`queue_free` ligados a Maciota/mecânico em `MissionWorld`, campanha e `Arrival` | só `Arrival` esconde o modelo (`maciota.hide()`); não achei ferimento |
| `MaciotaModel`/`MechanicModel` | busca por `health`, `receive_damage`, `dead` | nada encontrado |

**Defeito demonstrável:** nenhum que ferisse os dois hoje. O ganho é a guarda explícita em `_damage`, que cobre também tiros de NPC (cobras, guardas) e o fogo.

**Lacuna sem correção nesta frente:** o atropelamento não passa por `_damage`. Se o corpo residente ganhar `receive_damage` (ou for trocado por `Actor`), o veículo o feriria. **Contrato para o integrador** (`world/maciota/MaciotaPlace.gd`, cenário): marcar também o `ResidentBody` com `set_meta("invulnerable", true)` e, em qualquer classe futura desses residentes, fazer `receive_damage` sair sem efeito. Não editado aqui.

### Arma guardada, troca e ataque na garagem

- **Guardar na entrada e ao restaurar:** `GameState.set_location` → `economy.equip_weapon("fists")` quando `weapons_allowed()` é falso. `restore_snapshot` chama `set_location(data.region_id, data.place_id)` (linha 89) e `FullSession` chama nas entradas/saídas (linhas 91, 105, 176, 428, 461, 987). Existente; conexão estática. `Gameplay._update_visual` esconde a arma porque `attack_allowed()` é falso.
- **Bloqueios:** `attack_allowed()` guarda `fire_at` (punhos incluídos), `reload_weapon`, `cycle_weapon`, `equip_slot`, `toggle_flashlight`, coleta de munição e áudio de chama; `GameState.equip_weapon` recusa qualquer arma exceto `fists`; `consume_ammo`/`reload_weapon` exigem `weapons_allowed()`; `register_crime`, `damage_player` e `police_can_see` são ignorados. Laser e lanterna seguem `gun.visible`.
- **Inventário:** nada é removido; a arma equipada volta a `fists` e o uso é liberado ao sair (a arma não é re-equipada sozinha, como no V1).
- **Sem evidência em execução:** `tests/test_gameplay.gd` (garagem, linhas 127-129), o teste de garagem V1 e `tests/garage_guards` **não foram rodados**.

## Contratos de teste a adaptar

- Nenhum teste existente deve mudar por leitura: `test_private_security_crime.gd` continua coerente porque a deduplicação de chumbos só vale dentro de `fire_at`.
- Faltam testes: jato contínuo registra +4 por segundo; jato e fogo denunciam a mesma vítima uma vez por 10 s; escopeta em uma vítima = uma denúncia; cooldown de 120 ms do jato; `_damage` ignora nó com meta `invulnerable`.
- `MIGRATION_PARITY_AUDIT.md` não foi editado (fica para o integrador). Linhas a revisar: S01 e P06 (proteção da garagem) e qualquer menção ao crime do lança-chamas.

## Não medido

- Custo por quadro de `_crime_due` e `_flame_hit_due` (dois dicionários pequenos, podados a 32/64 entradas) e do laço de chumbos: sem medição renderizada. Nenhum desempenho aprovado.


---

# 3ª rodada — atropelamento e procurado, proteção no dano direto, intervalos e pausa

> Sem execução: nenhum Godot, teste, benchmark ou commit. **Implementação** = código escrito; **conexão estática** = chamadas conferidas por leitura; **comportamento validado** = nenhum. Esta seção substitui, onde conflitar, as ressalvas da 2ª rodada sobre atropelamento, `MaciotaPlace` e relógio real.

## Arquivos e funções alterados

| Arquivo | Alteração |
|---|---|
| `gameplay/DamageProtection.gd` (novo) | `is_protected(target)`: meta `invulnerable` no nó **ou em qualquer ancestral** |
| `gameplay/Gameplay.gd` | `_is_invulnerable` passa a usar `DamageProtection`; `report_vehicle_assault`; `_combat_clock`; `_crime_due`, `_flame_hit_due` e o agrupamento de impactos em relógio de combate; `_prune_combat_registers`, `_clear_combat_registers` (chamado por `on_region_changed`) |
| `scripts/Actor.gd` | `receive_damage`: respeita `DamageProtection`; a denúncia de atropelamento vai a `gameplay.report_vehicle_assault` (com retorno ao `register_crime(25)` antigo se o `gameplay` não tiver o método). **Movimento de ski intocado** |
| `scripts/Vehicle.gd` | só a condição do laço de colisão em `_physics_process` (`… and not PROTECTION.is_protected(target)`). **Condução intocada** |

## 1. Atropelamento e procurado

### Evidência

- `Vehicle._physics_process` (linhas 143-145): para cada colisão de deslize com `impact_speed > 4`, chama `target.receive_damage(impact_speed*4, self)` **a cada quadro de física**.
- `Actor.receive_damage` (antes): a cada chamada com `source.is_player_damage_source()` executava `register_crime(25)`, até `dead`. O NPC tem 100 de vida: a 5 m/s são 20 de dano por quadro (5 quadros = 125 pontos); a 10 m/s, 3 quadros = 75. Um único encontro somava mais de meia estrela e podia passar de 3 estrelas.
- V1 (`AnimatedPedestrian3D.get_run_over`, linhas 1893-1925): a função **retorna se a vítima já está morta ou caída** (`is_dead or is_incapacitated`) e exige velocidade mínima; a vítima perde a colisão (`collision_layer = 0`) e cai. Denuncia **uma vez**: 6 se sobrevive (`< 200 px/s`), 20 se é fatal, e **só se o jogador dirige** (`_is_player_driver`).

### Atribuição (preservada)

`Vehicle.is_player_damage_source()` não mudou: `player_damage_attribution and controlled and not external_input`. Tráfego (`controlled` falso), viaturas de despacho (`DispatchVehicle` força `player_damage_attribution = false` e usa `external_input`) e serviços continuam sem denunciar o jogador. A checagem foi repetida na entrada de `report_vehicle_assault`.

### Regra adotada

- Um crime por vítima **por contato**. Cada chamada de dano do veículo renova o instante do último contato; só denuncia se o último contato foi há mais de `VEHICLE_CONTACT_GAP` (1,0 s, relógio de combate).
- **Contato prolongado** (quadro a quadro, empurrão, arrasto) = mesmo atropelamento, uma denúncia. **Novo atropelamento** = a vítima ainda viva foi solta e atingida de novo depois de mais de 1,0 s sem contato.
- **Justificativa:** o V1 resolve isso removendo a vítima da colisão. No V2 a vítima viva continua colidindo e o veículo repete o dano a cada quadro, então é preciso distinguir contato de reincidência. **1,0 s é uma escolha minha, não calibrada** (~60 quadros de física: larga o bastante para tremor de contato, curta o bastante para uma ré seguida de nova batida contar). Nenhum outro valor foi inventado: o crime segue **25**, o valor V2 existente.

### Diferenças V1/V2 que permanecem

- V1: 6 (sobrevive) ou 20 (fatal); V2: 25 na primeira batida do contato, sem distinguir fatal. Se a vítima morre no mesmo contato, **nenhum acréscimo** (V1 daria 20 no lugar de 6).
- V1 exige velocidade mínima de 35 px/s e só age uma vez porque a vítima cai; V2 mantém o limite `impact_speed > 4` do `Vehicle`, a vítima segue viva e colidível e o dano ainda é repetido por quadro (não alterado: é balanceamento e condução de `Vehicle`). Só a **denúncia** foi deduplicada.
- Motoristas, ciclistas e policiais atingidos por veículo: `Actor` só cobre civis e o jogador; `PoliceAgent`/`CobraAgent` não denunciam por atropelamento, como antes.

## 2. Invulnerabilidade no dano direto

- **Evidência:** `Vehicle.gd:145` chama `receive_damage` sem passar por `Gameplay._damage`, então a proteção da 2ª rodada não o alcançava. Hoje o colisor dos residentes (`ResidentBody`, `StaticBody3D`) não tem `receive_damage`, e por isso não são feridos, mas por acidente.
- **Correção:** um único critério, `DamageProtection.is_protected`, nos três caminhos diretos: `Gameplay._damage` (tiro, golpe, explosão, fogo, tiros de cobras e guardas), `Actor.receive_damage` (qualquer origem) e o laço de colisão do `Vehicle`. A marca vale no próprio nó ou em qualquer ancestral, então funciona com o corpo filho do personagem.
- **Sem editar cenário:** `MaciotaPlace.gd` não foi alterado; a marca já existe no ator (`set_meta("invulnerable", true)`). Nenhuma rotina de dano ou vida foi acrescentada aos personagens.
- **Limite:** protege o que passa por esses três pontos. Outro código que chame `receive_damage` direto em nó protegido (por exemplo, futura classe de residente com o método) só é coberto se ele mesmo chamar `DamageProtection.is_protected`, e as classes `PoliceAgent`, `CobraAgent`, `Responder`, `RobberyActor` e `Guard` não foram alteradas. **Não declaro imunidade integral.**

## 3. Intervalos de combate e pausa

- **Evidência:** `_crime_due` e `_flame_hit_due` usavam `Time.get_ticks_msec()` (relógio real, segue correndo com o jogo pausado); o crime do disparo do jato e vários outros temporizadores usam `delta`. Pausar por 10 s consumia a janela de proteção do crime contínuo.
- **Correção:** `_combat_clock` soma o `delta` de `_physics_process` (só avança com o `Gameplay` processando e habilitado). Todos usam esse relógio: `_crime_due` (`CONTINUOUS_CRIME_COOLDOWN`, 10 s), `_flame_hit_due` (`FLAME_HIT_COOLDOWN`, 0,12 s), `report_vehicle_assault` (`VEHICLE_CONTACT_GAP`, 1,0 s), o agrupamento de impactos de áudio (`IMPACT_GROUP_SECONDS`, 0,04 s) e o crime do jato (`_flame_crime_clock`, já por `delta`). Nenhum valor mudou, só a unidade e a fonte do tempo.
- **Limpeza:** os registros por vítima guardam **ids de instância (inteiros), não referências**. `_prune_combat_registers` (a cada 1,0 s de combate) apaga entradas vencidas e de atores que já não existem (`is_instance_id_valid`); `_crime_attack` também é zerado acima de 128 entradas; `on_region_changed` chama `_clear_combat_registers` e zera o relógio do jato. Sem crescimento indefinido por leitura; não medido.

## Contratos de teste afetados

- `tests/test_private_security_crime.gd`: continua coerente (`_damage` direto, `_combat_clock` parado em 0 e `_in_pellet_volley` falso; a janela contínua não é usada).
- Testes que dependiam de `Actor.receive_damage` denunciando 25 por chamada repetida (se existirem no `test_gameplay.gd`) passam a ver **uma** denúncia por contato: adaptar. Não achei tal asserção por leitura, mas não rodei nada.
- `Gameplay._is_invulnerable` deixou de limitar a três ancestrais.
- Faltam testes: contato prolongado = 1 denúncia; nova batida após 1,0 s = nova denúncia; tráfego e viatura de despacho não denunciam; `Vehicle` não chama `receive_damage` em alvo marcado (nem por ancestral); janelas contínuas não avançam com o jogo pausado; região trocada limpa os registros.

## Pendências

- O dano do `Vehicle` por quadro (`impact_speed * 4`) não foi alterado; um contato de 5 m/s mata o NPC em ~5 quadros. Decisão de condução/balanceamento fora do escopo.
- Nenhuma medição de custo (o laço de colisão ganhou uma subida de ancestrais por colisão com `impact_speed > 4`).
- `MIGRATION_PARITY_AUDIT.md` (linhas de atropelamento e proteção da garagem) continua para o integrador.
- Nada foi carregado no Godot: erro de sintaxe ou de tipo do GDScript ainda é possível.


---

# 4ª rodada — combate perceptível e acessível

> **Nada foi executado.** Sem Godot, testes, benchmarks ou commits. Legenda: **E** = código que já existia; **I** = implementado nesta rodada; **C** = conexão conferida por leitura; **V** = comportamento validado em execução (**nenhum**).

## 1. Compilação e carregamento

- **Método:** não havia log de erro utilizável (o terminal do usuário estava vazio; sem `.log` novo). Rodei o analisador sintático **gdparse** (`gdtoolkit`, instalado com `pip`) em todos os `.gd` de `gameplay/`, `scripts/`, `runtime/`, `systems/`, `audio/` e `world/maciota/`. Ele só valida **sintaxe**; não valida tipos nem carregamento no Godot 4.7.
- **Resultado:** todos os arquivos de combate e dependências (`Gameplay`, `CombatAudio`, `CombatEffects`, `DamageProtection`, `Projectile`, `Fire`, `Actor`, `Vehicle`, `Economy`, `WeaponCatalog`, `ArsenalWeapon3D`, `WeaponCustomization`, todo `dispatch/`) analisam sem erro.
- **Tipos:** revisei por leitura cada `:=` novo (só recebem tipo conhecido: `Vector3`, `bool`, `String`, funções estáticas tipadas por `preload`). Chamadas em nós tipados como `Node3D` (`effects.shell(...)`) seguem o padrão já existente do V2 (`emergency.ignite(...)`). Erro de tipo em execução ainda é possível.
- **Fora do escopo, para o integrador:** `gdparse` reporta erro de sintaxe em `runtime/Weather.gd` e `audio/WorldAudio.gd` (arquivos do ambiente/áudio do mundo). Pode ser limite do analisador (sintaxe nova do 4.7) ou edição em andamento; não toquei.
- Não tratei erros em cascata como defeitos independentes; nenhum foi encontrado.

## 2. Cheat de armas do V1

| Item | V1 (produtivo) | V2 |
|---|---|---|
| Fonte | `characters/Player.gd`: `ARSENAL_CHEAT_CODE = "dukenuke"`, `_handle_cheat_key` (linha ~1151), `_activate_arsenal_cheat` (~1185), `can_carry_weapon` (linha 77) | I: `Gameplay._input`/`activate_arsenal_cheat` e `Economy.activate_arsenal_cheat` |
| Acionamento | Digitar as letras `d u k e n u k e` em sequência; ASCII apenas; pausa máxima de 3 s; buffer de 13 letras; ignora Ctrl/Alt/Meta, campo de texto, jogo pausado, remapeamento e quando `_reload_allowed()` é falso (garagem, diálogo, morto, preso…) | Mesmas regras: `attack_allowed()` (garagem, ski, veículo, morto), `_free_play_ok()` (menu, remapeamento, abertura, minigame do cofre), foco em `LineEdit/TextEdit`, modificadores. Tempo pelo `_combat_clock` |
| Efeito | `_cheat_all_weapons = true`; todas as armas do `ORDER` viram posse; pente = capacidade; reserva = `max(9999, atual)`; melee −1; aviso "Cheat ativado". `can_carry_weapon` ignora o porta-malas | `Economy.activate_arsenal_cheat()`: mesma posse/pente/reserva e mesma bandeira `cheat_all_weapons` (volátil) lida por `can_carry_weapon`; `message.emit("Cheat ativado")`; `changed` |
| Persistência | posse e munição vão ao save do V1; `_cheat_all_weapons` **não** | posse e munição vão ao inventário normal (e ao save); `cheat_all_weapons` fica **fora de `_data`**, então nunca é salvo, e uma economia restaurada nasce com ele desligado |
| Garagem | bloqueado por `_reload_allowed()` | bloqueado por `attack_allowed()`; entrar guarda a arma (`set_location`) |
| Slots/propriedade/munição | não mexe nos slots | não mexe nos slots (`_assign_personal_slot` não é chamado), sem recibo, sem cobrança, **sem marcar descoberta** (`grant_weapon` marcaria `mountain_cargo_plane_smg_01` e `mountain_cabin_hunting_rifle`, e afetaria coletáveis/conquistas) |

- **Diferenças:** o V1 mantém `_cheat_all_weapons` até recarregar a cena; no V2 ele dura a sessão da `Economy` (some ao carregar save). Recarregar o save mantém as armas, mas só as do porta-malas podem ser carregadas, como no V1 após reiniciar.
- **Cheat de dinheiro do V1** (`dirtybagmoney`, +100000): existe, mas não é de armas, altera economia e **não foi migrado**.
- **`E` durante a digitação** ainda interage (V1 idem): as teclas não são consumidas, só a última quando completa o código.
- **Como usar:** em jogo livre, fora da garagem, a pé, digitar `dukenuke` com pausas menores que 3 s.
- **Pendente:** teste de `Economy` (posse, munição, bandeira fora do `snapshot`, garagem) e do buffer do teclado.

## 3. Controles de ataque, mira, recarga, troca e seleção

Consumidores conferidos por leitura (`runtime/GameInput.gd` define; consumo em `FullSession` e `Gameplay`):

| Ação | Teclado / mouse / controle (padrão) | Consumidor | Situação |
|---|---|---|---|
| `fire` | botão esquerdo · RT | `FullSession._process` → `fire_at` (automáticas repetem; demais só no `just_pressed`) | E, C. Bloqueado em menu (`modal`), veículo e garagem |
| `aim` | botão direito · LT | só `Robberies` (caixa do banco) | **Sem consumidor de combate.** V1: `weapon_aim_active` (pose, mira do rosto, luneta). Pendente, ver abaixo |
| `reload` | R · X | `FullSession._input` → `reload_weapon` (a pé). `radio_next` também usa R, mas no veículo: separado por contexto | E, C |
| `weapon_next` | Q · roda para cima · RB | `FullSession._input` → `cycle_weapon(1)` | E, C |
| `weapon_previous` | (sem tecla) · roda para baixo · LB | **antes: nenhum**. Agora `Gameplay._unhandled_input` → `cycle_weapon(-1)`, incluindo a roda para baixo | I, C, `tests/test_mouse_wheel_weapon_radio.gd`. Dirigindo, a roda sintoniza a rádio (`WorldAudio`) |
| `weapon_slot_1..10` | 1–0 | **antes: nenhum**. Agora `Gameplay._unhandled_input` → `equip_slot` na ordem V1 (pistola, magnum, SMG, escopeta, serrada, AK, M4, RPG, lança-chamas, granada) | I, C |
| `unarmed` | X · D-pad baixo | `FullSession._input` → `equip_weapon("fists")` | E, C |
| `weapon_flashlight` | G · MISC1 | `FullSession._input` → `toggle_flashlight` | E, C |

- **Remapeamento e menus:** as ações novas leem `InputMap`, então acompanham o remapeamento. Só agem com `_free_play_ok()`: sessão pronta, sem `modal`, sem remapeamento, sem `arrival.controls_locked`/abertura, sem minigame do cofre; e com `attack_allowed()` (garagem, veículo, ski, morte, pausa).
- **Conflitos:** R (recarregar × rádio) separado por veículo; `E` (interação × cheat) não é consumido; a roda do mouse acumula zoom + `weapon_next`, já existente e não alterado.
- **Ordem de eventos:** `_unhandled_input` só recebe o que o `_input` do `FullSession` não consumiu. Se o integrador preferir tratar tudo no `FullSession`, o contrato está na seção "Hooks" da 1ª rodada (remover o `_unhandled_input` do `Gameplay` para evitar troca dupla).
- **`aim` (pendente):** sem pose de mira no V2 (o V1 usa IK sobre o rig Meshy) e sem luneta funcional; nada a ligar sem essas peças. Documentado, não inventado.

## 4. Efeitos de combate

Fonte V1: `guns/combat/WeaponEffects.gd` e `Player._trigger_muzzle_flash_3d`. **Reaproveitável:** paleta, contagens, tempos, física (dividida por 16 px→m). **Precisa de adaptação 3D:** o desenho, porque os efeitos V1 são `Node2D` com `_draw`. Implementação em `gameplay/CombatEffects.gd` (novo) e `Gameplay.gd`.

| Efeito | Fonte V1 | V2 | Chamado por | Limite / descarregamento | Diferença ou pendência |
|---|---|---|---|---|---|
| Clarão de boca | `Player._trigger_muzzle_flash_3d` | (rodada anterior) esfera + `OmniLight3D` | `fire_at` → `_flash_muzzle` | 1 esfera + 1 luz reaproveitadas | luz não medida |
| Cápsulas | `_ShellCasing` (ejeção lateral, 2 quiques, 1,6 s) | `CombatEffects.shell`, caixa de latão com física própria | `fire_at` (armas de fogo; não RPG/chama/granada) | anel de 16 nós; simulação ligada só com cápsula ativa | V1 ejeta por qualquer arma exceto as que optam por não; V2 idem |
| Impactos por material | `_ImpactBurst` (cores por superfície) | `CombatEffects.impact`, 1 emissor `CPUParticles3D` por material (`world`, `flesh`, `concrete`, `metal`, `wood`, `glass`) | `_hit_effect` a partir de tiro, golpe e explosão; material por `_impact_material` | 6 emissores; um impacto novo do mesmo material reinicia o anterior | poeira/faísca só; sem decal de furo nem `ShotFeedback` |
| Sangue | `_BloodBurst` (gotas, gravidade) | `CombatEffects.blood` (emissor único de gotas) + `stain` (mancha no chão quando morre, anel de 12, 20 s) | `_hit_effect` (corpo, não protegido) | 1 emissor + 12 manchas | sem sangue no chão contínuo (`GroundBlood`, `BloodTransferSystem`), sem pegadas, sem `BodyWound`/restos |
| Explosão | `ExplosionVisual`, `ExplosionRemains` | esfera existente + `CombatEffects.explosion`: fagulhas, fumaça e clarão de luz (0,15 s) | `Gameplay.explode` | 2 emissores + 1 luz | sem detritos, sem restos de corpos, sem tremor de câmera (a câmera é do integrador) |
| Rastros | `Bullet` (traço na cor da arma), `RocketTrail`, `RocketBackblast` | traço agora na cor `tracer_color` do catálogo (cache por cor); rastro de fumaça no foguete (`attach_rocket_trail`); sopro traseiro do RPG | `fire_at`, `Projectile._ready` | traços: teto de 48 (já existia); rastro: 1 emissor por foguete, liberado com ele; sopro: 1 emissor | sem faixa de calor do foguete |
| Animação de ataque | `PlayerCombatPose`, `MeshyMeleePose` (IK sobre o rig Meshy) | **parcial**: a arma na mão balança (machado/taco: arco; faca/soqueira: estocada) e o corpo gira alternando lado; sem pose de braço | `fire_at` → `_start_swing`/`_update_swing` | sem instâncias novas | O `dante.glb` do V2 tem clipes `Attack`, `Punch_Combo`, `Punch_Forward_with_Both_Fists`, `Spartan_Kick`, `Rifle_Charge`, mas com 1,5–3,5 s (clipes longos), não usados pelo V1 e não verificados visualmente. **Pendente:** decidir trechos desses clipes ou portar o IK V1. Não declaro paridade |
| Chama / pessoa queimando | `FlameJet`, `PersonBurning` | (rodada anterior) raio + fogo de emergência | — | — | `PersonBurning` (2D) não portado |
| Gemido de dor | `PainReaction` (chance 65%/42%, 6 vozes, 1,8 s por vítima) | `Gameplay._pain_voice`, 6 vozes | `_hit_effect` (corpo) e `_apply_player_damage` | 6 `AudioStreamPlayer3D` | usa `hurt_0..2` (3 dos 5 takes V1) |

Custo de nenhum deles foi medido. Limpeza: `on_region_changed` chama `effects.clear()`; os nós vivem enquanto o `Gameplay` viver.

## 5. Sons de combate e referências aos originais

Tipos de som do catálogo × arquivos em `assets/gameplay/audio/` (verificado por script de existência):

| `sound_type` | Origem no V2 | Arquivo V1 original |
|---|---|---|
| pistol, magnum, smg, shotgun, sawed_off, ak47, m4a1, hunting_rifle | 3 takes cada (rodadas anteriores) | `audio/combat/*_{0..4}.wav`, `arsenal_v2/` (5 takes; **2 takes não copiados**) |
| rpg | 3 takes (rodada anterior) | `audio/acoustic/rpg_launch_{0..4}.wav` |
| fists, knife, flamethrower, grenade | **sem WAV, de propósito**: `CombatAudio` (procedural) | `ProceduralAudio.gd`, `KnifeAudio.gd`, `BatAudio.gd`: também procedurais no V1 |
| explosion | 3 takes | `audio/acoustic/explosion_{0..4}.wav` |
| recarga (11 armas) | `reload/*` | `audio/reload/` |
| impactos (5 materiais) | `impact_*` | `audio/combat/{flesh,metal,concrete,wood,glass}_*` |
| gemido de dor | `hurt_{0..2}` (novo) | `audio/reactions/hurt_{0..4}.wav`; créditos em `HURT_CREDITS.md` |

**Recursos ausentes no V2** (existem no V1): morte (`death_*`), pânico (`panic_*`), ricochete, takes 3–4 das famílias, `AmmunationArt` etc. Não são de combate direto ou dependem de sistemas fora do meu escopo. Nenhuma referência do combate V2 aponta para arquivo inexistente.
- `pitch_variance` e `audio_volume_db` do catálogo seguem ignorados nos tiros (baseline −10 dB do V2).

## Como acessar os recursos (instruções concretas)

- **Cheat:** a pé, fora da garagem, jogo livre: digitar `dukenuke`. Aparece "Cheat ativado". Trocar de arma com 1–0, Q, LB, X.
- **Armas:** 1 pistola · 2 magnum · 3 SMG · 4 escopeta · 5 serrada · 6 AK · 7 M4 · 8 RPG · 9 lança-chamas · 0 granada; Q/RB próxima; LB anterior; X mãos livres; G lanterna; R recarregar.
- **Efeitos:** atirar em pessoa (sangue, gemido), parede (poeira), carro (faísca metálica); RPG (rastro, sopro, explosão com fagulhas/fumaça/luz); golpear com machado/faca (balanço da arma e giro do corpo).

## Contratos e integrações

- **Nenhum arquivo de integrador foi alterado.** `Economy.gd` recebeu só o cheat (`activate_arsenal_cheat`, `cheat_all_weapons`, `CHEAT_RESERVE`, e `can_carry_weapon`). `Projectile.gd` e `Gameplay.gd` são do combate.
- **Opcional (`FullSession`/HUD):** o aviso "Cheat ativado" sai por `Gameplay.message`; o texto só aparece se o HUD já mostra esse sinal (mesmo caminho de "Recarregando…").
- **Opcional (câmera):** tremor na explosão exige a `CameraRig`; chamar um método de tremor a partir de `Gameplay.explode` (`point`, `radius`).
- **Ambiente/áudio do mundo:** revisar `Weather.gd` e `WorldAudio.gd` (gdparse).

## Testes afetados e pendências

- **Adaptar:** testes que contam filhos do `Gameplay` ou de áudio (o `Gameplay` agora cria `CombatEffects` e 6 vozes de dor); qualquer teste que assuma que `Economy.can_carry_weapon` depende só do porta-malas.
- **Faltam testes:** cheat (código, buffer, garagem, não persistir), troca por teclas/anterior, pool de efeitos (limites), gemido, cores de traço, balanço de golpe.
- **Não medido:** frame time de emissores, luzes (clarão e explosão), sons novos.
- **Sem execução:** nada disto está validado; a aparência dos efeitos (escala, cor, direção dos emissores) e da animação de golpe precisa de olho humano.


---

# 5ª rodada — mira, camada de apresentação de combate e revisão da entrega anterior

> **Nada foi executado.** Sem Godot, testes ou benchmarks. **I** = implementado; **C** = conexão conferida por leitura; **V** = validado em execução (**nenhum**). Esta seção substitui, onde conflitar, a linha "Animação de ataque" e a torção de corpo da 4ª rodada.
> Verificação de sintaxe: o `gdparse` já instalado na rodada anterior foi reaplicado aos três arquivos editados (só sintaxe, não é compilação do Godot). Para medir os clipes do `dante.glb` usei um script Python avulso que lê as chaves de animação do arquivo (fora do repositório); nenhuma ferramenta nova foi instalada. Os avisos de `Weather.gd` e `WorldAudio.gd` continuam **achados não confirmados** para seus responsáveis.

## 1. Mira (ação `aim`)

**Fonte V1** (`characters/Player.gd`, linhas 438-441 e 1659):
`is_aiming = fire || aim || lanterna ligada`; `weapon_aim_active = aim && arma que mira (sem punhos, faca, machado, soqueira, taco, granada)`; o corpo gira para a direção do cursor enquanto `is_aiming`, senão para a do movimento; `weapon_scope_active() = luneta instalada && aim && ataque permitido && fora de interior isolado`. A pose do braço vem de `PlayerCombatPose` (IK sobre o rig Meshy): **não portada**.

**V2 (I, C):** `Gameplay._update_aim` (chamado a cada quadro de física, depois de `_update_visual`).

| Estado | Regra |
|---|---|
| `permitted` | `attack_allowed()` (garagem, veículo, ski, morte, pausa) **e** `player.input_locked` falso **e** `_free_play_ok()` (sessão pronta, sem menu/remapeamento/abertura/minigame do cofre) |
| `aiming` (V1 `is_aiming`) | `permitted` e (`aim` apertado, `fire` apertado, lanterna acesa ou `AIM_HOLD` ativo) |
| `aim_active` (V1 `weapon_aim_active`) | `aim` apertado com arma fora de `NON_AIM_WEAPONS` |
| `scope_active()` | luneta instalada + `aim` + `permitted` + fora de interior isolado |
| Fora de `permitted` | rumo forçado e clipe de combate são zerados no mesmo quadro |

- **Direção efetiva (conflito movimento × corpo × disparo).** Antes, `Actor` girava o corpo para o movimento a cada quadro e só `fire_at` o girava para o disparo por um quadro: andando e atirando, o corpo olhava para um lado e o tiro saía para outro. Agora `Gameplay` escreve `Actor.combat_facing` e o `Actor` aplica o rumo de mira **depois** da rotação da caminhada. Mouse: do jogador a `aim_point`, atualizado por `FullSession` via `aim_from_screen`. Controle/toque: a mesma conta de `GameInput.aim_target_3d` (câmera × `aim_direction`), **lendo** `aim_direction` sem chamar a função, porque ela integra o giro do direcionador e rodaria duas vezes por quadro. Assim rumo do corpo e rumo do disparo (`fire_at(target)`) saem da mesma direção. **C**, não validado.
- **`AIM_HOLD` = 0,3 s (não calibrado, escolha da adaptação):** o V1 solta a mira com o botão; um clique dura um quadro e o corpo piscaria de volta para o movimento.
- **Coice:** `WeaponPoseData.PROFILES[id]` (`recoil` e velocidade de retorno) empurra a arma de fogo para trás e ela volta; o resto do perfil (posição de mão e orientação do IK) **não é usado**.
- **Limitações da adaptação:** sem pose de mira (o V1 levanta o braço por IK); o corpo caminha com o clipe de caminhada olhando para o cursor, então andar de costas parece andar para a frente. O `dante.glb` tem `Walk_Backward_with_Gun`, `Walk_Backward_While_Shooting` e `Walk_Left_with_Gun`; usá-los exige escolher clipe de locomoção em `Actor` por ângulo relativo (não feito).
- **Luneta: contrato de integração (não editei câmera nem interface).** Ler `world.gameplay.scope_active()` e aplicar o zoom. Hoje `CameraRig` só tem `target_size` (14–52) controlado pela roda; a câmera precisa de um modo de zoom por luneta e a HUD, de uma retícula. O V1 não deixou um consumidor de câmera no repositório para copiar.
- **Outros consumidores de `aim`:** `Robberies` (caixa do banco) continua lendo a ação; o estado novo não altera isso.

## 2. Camada de apresentação corporal

### Clipes reais de `assets/dante.glb`
`Running` 0,70 s · `Walking` 1,03 s · `Attack` 2,87 s · `Punch_Combo` 2,53 s · `Punch_Forward_with_Both_Fists` 3,53 s · `Spartan_Kick` 1,50 s · `Rifle_Charge` 0,57 s · `Walk_Backward(_with_Gun / _While_Shooting)` · `Walk_Left_with_Gun` · `Swim_Forward` · `Fast_Ladder_Climb` · `dying_backwards` · `restpose`. O V1 não usa `Attack`/`Punch*` (usa pose procedural por IK).

**Medição** (cinemática direta do esqueleto sobre as chaves, espaço do esqueleto com Y para cima e rosto em +Z):
- `Attack`: mão sobe entre 0,3 e 1,0 s (armar sobre a cabeça) e desce a **19,7 m/s em t = 1,1 s** (golpe descendente com as duas mãos); retorno até ~1,5 s e depois parada até 2,87 s.
- `Punch_Forward_with_Both_Fists`: guarda até 0,5 s, recuo das mãos em 0,6–0,7 s, **extensão frontal em t ≈ 0,95 s** (as duas mãos, vetor ≈ +Z), retorno até ~1,3 s; o resto do clipe é outra sequência.
- `Punch_Combo`: pico de 9,2 m/s **para cima** (t = 1,3 s), sem jabs frontais claros: não serve como soco simples. `Spartan_Kick`: chute, fora do pedido.

### Integração (I, C)
- `Actor.gd` (integração estritamente necessária): campos `combat_facing`, `combat_clip`, `combat_clip_time`, **escritos por `Gameplay` e só lidos pelo `Actor`**. Depois da rotação da caminhada aplica `combat_facing`; na animação, se `combat_clip` não é vazio, toca esse clipe em `combat_clip_time` (mesmo `play` + `seek(…, true)` já usado) em vez de Walking/Running e **não avança `phase`**; vazio, a caminhada retoma sozinha no quadro seguinte. Movimento, ski e correção do quadril seguem como estavam. Só o ator do jogador usa a camada.
- `Gameplay` escolhe trechos e os avança em tempo de física do combate (`MELEE_CLIPS`, 1,0×, sem acelerar):
  - soco e soqueira: `Punch_Forward_with_Both_Fists` de 0,75 a 1,30 s (contato visível ≈ 0,2 s depois do golpe);
  - faca, taco e machado: `Attack` de 1,00 a 1,50 s (contato visível ≈ 0,1 s depois). Golpe de duas mãos mesmo com a faca (limitação).
- **Dano inalterado:** continua sendo aplicado por `fire_at` no aperto do botão, com a cadência do catálogo. O clipe não emite evento nem causa dano; o impacto visual chega 0,1–0,2 s depois do dano.
- **Interrupção e retorno:** o clipe para (e a locomoção retoma) ao trocar/guardar a arma (`equipped()` ≠ arma do golpe), morrer, entrar em garagem/veículo/ski/transição/menu (`attack_allowed()` ou `_free_play_ok()` falsos), trocar de região, terminar o trecho ou descarregar. Na **pausa** `Gameplay` e `Actor` não processam: a pose congela e continua ao retomar.
- **Sem clipe** (`animation` ausente ou clipe inexistente): cai no balanço procedural da arma (machado/taco: arco; faca/soqueira: estocada), agora **sem** a torção do corpo da 4ª rodada, que brigaria com o rumo de mira.
- **A arma na mão** segue o osso da mão (BoneAttachment), mas `_update_visual` mantém a orientação do modelo alinhada ao rumo da mira (sem isso o osso não está calibrado para o cano): a arma acompanha a posição da mão no golpe, **não a rotação**.
- **Limitações:** corte seco entrando no trecho (sem mistura com a caminhada), sem recuperação/`Spartan_Kick`, sem combo, sem pose por arma de fogo, punhos com os dois braços ao mesmo tempo. **Aparência não validada; não declaro animação aprovada.**

## 3. Revisão da entrega anterior (por leitura)

| Item | Achado | Ação |
|---|---|---|
| Reset dos objetos reutilizados em `CombatEffects` | Cápsulas: posição, rotação, visibilidade e estado são reescritos a cada uso; manchas: transformação completa e idade reescritas; emissores: `restart()` a cada disparo com velocidade/direção reescritas; luz: energia, alcance e visibilidade reescritos. **Defeito:** `clear()` só fazia `emitting = false`, e partículas em voo continuavam visíveis | `clear()` agora faz `restart()` e depois `emitting = false` (descarta as partículas vivas) |
| Encerramento ao descarregar | `Gameplay._exit_tree` parava as vozes; **faltava** apagar a luz do clarão, a lanterna, os emissores e a camada de combate do ator | `_exit_tree` agora zera a camada do `Actor`, apaga as luzes e chama `CombatEffects.shutdown()` (sem `restart()`, porque os filhos podem já ter saído da árvore); `CombatEffects` também chama `shutdown()` no próprio `_exit_tree` |
| Referências a alvos destruídos | Registros por vítima guardam **ids inteiros** e são podados (`is_instance_id_valid`, vencimento, região). **Defeito:** `_hit_effect` usava `hit.collider` sem checar se ainda existia | `is_instance_valid(collider)` antes do uso |
| Cheat durante digitação em interface | `_input` ignora `LineEdit`/`TextEdit` focados, menu (`modal`), remapeamento, abertura, minigame do cofre, pausa, Ctrl/Alt/Meta, garagem, veículo, ski, morte | sem defeito; nenhuma alteração |
| Aviso do cheat | `Gameplay.message.emit("Cheat ativado")`; `runtime/FullSession.gd:257` conecta `world.gameplay.message` a `show_message` (rótulo por 5 s, escondido em menu). Conexão **por leitura** | sem defeito; sem alteração |

Custos de tudo isto seguem **sem medição**.

## Integrações externas ainda necessárias

- **Câmera/interface (outra equipe):** zoom da luneta lendo `gameplay.scope_active()`; retícula.
- **Controles gerais (outra equipe):** nenhuma mudança; a `aim` do `InputMap` é lida como está. Se o remapeamento passar a expor a ação por outro nome, ajustar as duas chamadas `InputMap.has_action("aim"/"fire")` em `_update_aim`.
- **Locomoção (`Actor`/transporte):** escolher clipes `Walk_Backward_with_Gun`/`Walk_Left_with_Gun` por ângulo relativo à mira, se quiserem passo lateral e de costas.
- **Edição concorrente:** `Actor.gd` foi lido logo antes da edição (última alteração 15:31); a edição foi um bloco exato e nenhum trecho concorrente foi sobrescrito. `Economy.gd`, `FullSession.gd`, `GameState.gd`, `project.godot`, câmera, menus, NPCs, transporte e despacho não foram tocados nesta rodada.

## Diferenças V1/V2 que permanecem

- V1: pose de mira e golpe por IK sobre o rig Meshy, solta a mira com o botão. V2: mira só orienta o corpo e a arma; golpe por trecho de clipe; mira segurada por 0,3 s.
- V1: luneta com zoom pela câmera do jogador. V2: só o estado (`scope_active`).
- Sem strafe/costas com arma, sem pose de arma de fogo, sem recuperação dos golpes.

## Validações pendentes

- Aparência: trechos de clipe (início abrupto, contato, retorno), escala e direção de todos os efeitos.
- Direção efetiva do tiro com mouse e com controle, andando e parado.
- Interrupções: morte, troca de arma, pausa, garagem e veículo no meio do golpe.
- Testes: mira (estados por guarda), camada do `Actor`, `MELEE_CLIPS`, cheat, limpeza de `CombatEffects`.
- Desempenho não medido; nenhuma paridade completa declarada.


---

# 6ª rodada — consolidação: tipagem, corrida, locomoção armada, transições e contrato da luneta

> **Nada foi executado.** Sem Godot, testes, benchmarks, parsers ou instalações. **I** = implementado; **C** = conexão conferida por leitura; **V** = validado em execução (**nenhum**). Não declaro compilação, aparência nem desempenho aprovados.

## 1. Tipagem (revisão de leitura)

- Releitura de `Gameplay.gd` (as linhas mudaram: 1341 agora), `CombatEffects.gd`, `Projectile.gd` e `Actor.gd`. Não sei qual ponto bloqueou a tentativa integrada; o log não está no repositório. O trecho mais sujeito a rejeição que encontrei foi o de `_update_aim`: `var permitted := attack_allowed() and … and not player.input_locked …` inferia o tipo de uma cadeia `and` com um acesso dinâmico (`player.input_locked`, `player` é `CharacterBody3D`). Não afirmo que o Godot rejeite esse padrão; troquei por **tipos explícitos** (`: bool`, `: float`, `: Vector3`, `bool(...)`) nas linhas de mira, para não depender da inferência.
- Conferidos sem alteração: todos os `var x := …` restantes de `Gameplay` recebem `Dictionary`/`Vector3`/`float` de funções ou APIs tipadas; `CombatEffects` e `Projectile` idem. Chamadas em nós tipados `Node3D` (`effects.shell(...)`) seguem o padrão já existente (`emergency.ignite(...)`).
- `gdparse` **não** foi executado nesta rodada e nunca equivale à compilação do Godot. Os avisos sobre `Weather.gd` e `WorldAudio.gd` continuam **achados não confirmados** para seus responsáveis.
- Em uma leitura anterior achei que os quatro arquivos estavam em CRLF; a verificação era pouco confiável. Nesta rodada o script de edição detecta o fim de linha e o preserva (o resultado ficou LF). Se algum editor converter para CRLF, não afeta o GDScript.

## 2. Corrida alternável (I, C)

`Actor._physics_process` (ramo do jogador) passou de `Input.is_action_pressed("sprint")` para `get_node("/root/GameInput").sprinting()`. `GameInput.sprinting()` devolve `sprint_toggled` no controle (alternado pelo botão do direcional esquerdo) e `is_action_pressed("sprint")` no teclado. Não mexi em `GameInput`. Preservados: movimento automático (`controlled_automatically`), ski (a velocidade do ski substitui `target_speed` depois), NPCs (não passam pelo ramo do jogador) e `input_locked` (zera a direção). **Observação:** o botão de correr do controle também alterna quando a sessão está em menu; isso é de `GameInput` (`_input`), não do `Actor`.

## 3. Locomoção armada por direção relativa à mira (I, C)

Clipes reais medidos no `dante.glb` (cinemática direta do esqueleto; Y para cima, rosto em +Z; lado esquerdo = +X pelos pés):

| Clipe | Duração | Quadril (movimento de raiz) | Velocidade nativa | Direção real |
|---|---|---|---|---|
| `Walk_Backward_with_Gun` | 1,07 s | −0,91 m em Z | 0,85 m/s | para trás |
| `Walk_Backward_with_Grenade` | 1,30 s | −1,06 m em Z | 0,82 m/s | para trás |
| `Walk_Backward` | 0,97 s | −0,91 m em Z | 0,94 m/s | para trás, sem arma (não usado) |
| `Walk_Backward_While_Shooting` | 1,33 s | −0,83 m em Z | 0,62 m/s | para trás atirando (não usado) |
| `Walk_Left_with_Gun` | 1,30 s | **−0,89 m em X** | 0,68 m/s | **para o lado direito do personagem** (o pé direito lidera) |
| `Walking` / `Running` | 1,03 s / 0,70 s | ~0 (no lugar) | — | — |

- **O clipe `Walk_Left_with_Gun` se move para a direita.** Nome e medição divergem; conferi os pés (`LeftFoot` em +X, `RightFoot` em −X; ao andar, `RightFoot` chega a −1,04 e `LeftFoot` a −0,84) antes de usá-lo. Uso-o só como **passo à direita**. **Não há clipe de passo à esquerda nem de frente armado**, e **não espelhei o rig**: nesses casos fica a caminhada comum.
- **Seleção (`Actor._armed_clip`):** só com o jogador mirando (`combat_facing` ativo) e `combat_stance` (`"gun"` ou `"grenade"`, escrito por `Gameplay._update_aim` a partir do catálogo). Direção do movimento contra o rumo da mira: cone de ±45° em torno de **trás** (arma de fogo ou granada) ou de **direita** (só arma de fogo). Corpo a corpo e mãos livres nunca usam clipe armado.
- **Sem deslizamento por construção, com uma recusa:** o movimento de raiz é zerado pelo `Actor` (correção do quadril); o ciclo é **travado na distância percorrida** (`stride`), como a caminhada. Mas a caminhada comum já roda ~2× (3,5 m/s contra 1,75 m/s nativos) e estes clipes nativos são ≤ 0,85 m/s: a 3,5 m/s seriam ~4–5×, um borrão. Por isso `ARMED_MAX_RATE = 2,0`: o clipe armado só é usado se a velocidade real for ≤ 2× a nativa. **Consequência: a 3,5 m/s (teclado ou controle com o direcional no fundo) a seleção recusa os três clipes e cai na caminhada comum; só entra com inclinação parcial do direcional analógico (≤ ~1,7 m/s para trás, ~1,4 m/s para o lado).** É honesto, mas o efeito visível padrão é nulo. Para usá-lo em velocidade normal a equipe de movimento precisaria reduzir a velocidade enquanto mira (fora do meu escopo; `Actor` foi preservado).
- **Não validado:** nenhuma aparência.

## 4. Transição golpe ↔ locomoção (I, C)

- **Antes:** corte seco ao entrar e sair do clipe de golpe (pose de locomoção → pose do clipe no mesmo quadro).
- **Agora:** o `Actor` mistura poses durante `COMBAT_BLEND` = 0,08 s (não calibrado): em cada quadro da janela avalia a locomoção e o clipe, captura posições e rotações dos ossos (`Skeleton3D`) e aplica `lerp`/`slerp` com o peso. Fora da janela é uma pose só (custo normal). Ao sair, o clipe **congela no último instante** e é misturado de volta para a locomoção. Depende do mesmo comportamento que o `Actor` já usava (ler os ossos logo depois do `seek(…, true)`); **não validado**.
- **Preservado:** `fire_at` continua sendo o único lugar que aplica dano (uma vez por golpe, na cadência do catálogo). Clipes e mistura não emitem evento nem dano.
- **Interrupções** (por leitura): morte, troca de arma, garagem, veículo, ski, transição, menu, região e descarga zeram o clipe; o peso volta a zero em 0,08 s. Pausa: `Gameplay` e `Actor` não processam, a pose congela junto.

## 5. Limpeza durante morte, garagem, veículo, região e descarga (por leitura)

| Situação | O que zera | Onde |
|---|---|---|
| Morte, garagem, veículo, ski, menu, transição (`permitted` falso) | rumo de mira e postura no `Actor`, clipe, `_aim_hold`; a arma some (`gun.visible`), a lanterna e o laser seguem `gun.visible`; o clarão hesita até `_muzzle_timer`; o áudio do jato para em `_update_muzzle_and_flame` | `_update_aim`, `_update_visual`, `_update_muzzle_and_flame` |
| Troca de região | mira, clipe, recuo, clarão e luz, áudio do jato e da recarga, camada do `Actor` e `CombatEffects.clear()` (emissores, cápsulas, manchas, luz) | `on_region_changed` (**estendido nesta rodada**) |
| Descarga | camada do `Actor`, luzes (clarão e lanterna), `CombatEffects.shutdown()`, vozes | `_exit_tree` |
| Referências a alvos removidos | registros por vítima são ids inteiros, podados por tempo, por existência e na região; `_hit_effect` e `_pain_voice` checam `is_instance_valid` | `_prune_combat_registers`, `_hit_effect`, `_pain_voice` |

Não achei referência a alvo destruído que sobreviva. **Sem execução.**

## 6. Contrato de `scope_active()` para a câmera (sem zoom nem retícula aqui)

- **API:** `world.gameplay.scope_active() -> bool` e `world.gameplay.scope_part() -> String` (`"none"` se não há luneta na arma equipada; o nome da peça serve para escolher o zoom).
- **Verdadeiro enquanto todas valem no passo de física atual:** luneta instalada na arma equipada; `aim` apertado **agora** (sem retenção: solta, falso no passo seguinte); ataque permitido e jogo livre (sem pausa, menu, remapeamento, abertura, minigame do cofre, garagem, veículo, ski, morte, entrada travada ou transição); fora de interior isolado.
- **Duração e frequência:** atualizado a cada `_physics_process` (60 Hz) e relido com `attack_allowed()` na chamada. Quem lê em `_process` vê o valor do último passo de física (até ~1/60 s de atraso). Trocar de arma, morrer ou entrar em veículo zera no mesmo passo. Sem suavização: quem faz o zoom deve interpolar.
- **Fora daqui (outra equipe):** modo de zoom da câmera (hoje só `target_size` de 14 a 52, controlado pela roda), retícula na HUD.

## 7. Integridade de `combat-parity-v1.md`

Conferida por leitura: as cinco seções (rodada 1 com a tabela, e as rodadas 2 a 5) estão presentes, com os cabeçalhos `#` esperados, e o arquivo é **idêntico** à reconstrução (histórico de arquivos da sessão + o texto da 5ª rodada). **Limite:** o histórico só guarda o que esta sessão escreveu; uma edição de terceiros feita no intervalo entre o último snapshot e o truncamento acidental não seria detectável. Nenhuma foi observada. Esta seção foi anexada lendo o arquivo antes de escrevê-lo.

## Integrações externas necessárias

- **Câmera/interface:** zoom e retícula da luneta (item 6).
- **Movimento:** velocidade reduzida ao mirar de costas/de lado, se quiserem os clipes armados em uso normal (item 3).
- **Controle:** o alternar da corrida no menu (item 2).
- **Edições concorrentes:** `Gameplay.gd`, `Actor.gd` e `CombatEffects.gd` foram modificados por outro agente às 16:02 (o `Actor` e as partes de `Gameplay` que li estavam como eu os deixei; não fiz diferença completa); reli os arquivos antes de editar e preservei o fim de linha. `Economy`, `GameInput`, `FullSession`, `ProductionWorld`, `GameState`, `Vehicle`, câmera, menus, áudio do mundo, despacho e mapa não foram tocados.

## Diferenças V1/V2 que permanecem e validações pendentes

- V1: pose de arma por IK; V2: sem pose, com locomoção armada só em faixa lenta.
- Validar em jogo: rumo do corpo × disparo (mouse e controle); mistura de 0,08 s dos golpes; passo para trás/direita com direcional parcial; corrida alternável; limpeza em morte, garagem, veículo e região; tipagem no carregamento do Godot; custo dos dois `seek` por quadro durante a mistura.


---

# 7ª rodada — validação do combate real e correções (com execução)

> Esta rodada **executou o Godot 4.7.2** (Vulkan, RTX 4060 Laptop) na sessão de produção, com `--no-save --skip-arrival` (sem gravação, dados isolados). Cada afirmação abaixo diz **o que foi executado**. Validação de **dano**, **aparência**, **som** e **desempenho** estão separadas. Nada é declarado aprovado porque o projeto abriu.
> Contrato preservado: `Gameplay.handle_arsenal_input` é chamado por `FullSession` antes da interação; o antigo consumidor `_input` **não** foi restaurado; `tests/test_arsenal_input_integration.gd` passou (`ARSENAL_INPUT_PASS`).

## Testes executados

| Teste | Como | Resultado |
|---|---|---|
| `tests/test_combat_flow.gd` (novo, durável) | sessão de produção, janela real, entrada real (`Input.parse_input_event` para teclas, `Input.action_press` para `fire`/`aim`/movimento, `GameInput.touch_aim` para a direção) | **62 checks, 0 falhas, 0 linhas `ERROR`** na execução final |
| `tests/test_arsenal_input_integration.gd` | entrada real, `dukenuke` | `ARSENAL_INPUT_PASS` |
| `tests/test_gameplay.gd` | headless, 208 checks | 0 falhas. **Adaptei** um contrato: pente vazio agora inicia a recarga sozinho (V1) e a duração vem do banco de recarga (pistola 1,69 s, antes 1,35 s); o teste esperava a recarga manual |
| `tests/test_private_security_crime.gd`, `test_maciota_world.gd`, `test_environment_damage.gd`, `test_vehicle_equipment.gd`, `tests/garage_guards/test_guards.gd` (18 checks) | headless | 0 falhas |
| `tests/measure_combat.gd` (novo) | janela real, ver "Desempenho" | amostras abaixo |

O teste obrigatório da garagem de V1 (`tests/test_garage_weapon_restrictions.gd`) **não existe no V2**; a cobertura equivalente foi o bloco de garagem de `test_combat_flow` (entrada real por `enter_place`) e o de `test_gameplay` (linhas de bloqueio).

## Fluxo real (`test_combat_flow`) — o que funcionou

- **Cheat e entrada:** digitar `dukenuke` concede o arsenal (pistola com pente 12 e reserva 9999), o aviso chega a `Gameplay.message`, a tecla `1` equipa a pistola.
- **Mira:** `aim` liga `aiming`/`aim_active`; o corpo (`visual.rotation.y`) e a arma (`gun`) ficam alinhados com o alvo (arma com produto escalar > 0,98).
- **Disparo → dano → morte → crime/emergência (pistola):** um disparo tira **exatamente 16** (dano único, sem duplicidade), consome uma munição, gera crime; a vida só diminui; o NPC morre, cai e perde a colisão; o crime escala para procurado (3–4 estrelas); a morte cria ocorrência de emergência (`medic`/`mortician`).
- **Escopeta:** vários chumbos acertam (dano múltiplo de 8); crime = 4 por disparo + 12 **por vítima ferida** (uma denúncia por vítima, não por chumbo).
- **Corpo a corpo (soco, faca, taco, machado):** dano único igual ao do catálogo; clipe de combate ativo (`Punch_Forward_with_Both_Fists` / `Attack`); volta à locomoção (`Walking`).
- **Lança-chamas:** fere o alvo (18,6 em 1 s), o crime do jato não escala por quadro (16 em 1 s), acende fogo.
- **Explosivos:** RPG fere o alvo e **não** fere quem dispara; granada mirada a 8 m fere o alvo.
- **Garagem** (entrada real): guarda a arma; bloqueia disparo, soco, saque, troca, tecla de arma, recarga, lanterna, explosivo e o cheat; preserva o inventário; **restaurar um save com a pistola equipada e o local na garagem guarda a arma e preserva o inventário**; ao sair o uso é liberado. Maciota e o mecânico continuam com a marca `invulnerable`, e o corpo residente é protegido por ancestral, após `_damage` e `explode` de 500 (não exercitei atropelamento real; ver pendências).
- **Interrupções:** entrada travada no meio do golpe zera clipe, mira e postura; a rotina de descarga do `Gameplay` no meio do golpe libera a camada do ator e apaga as luzes; troca de região zera a camada.

## Defeitos encontrados na execução e correções

| # | Defeito (evidência) | Correção |
|---|---|---|
| 1 | **Arma e laser apontavam para o cursor com controle/toque.** `FullSession` reescreve `aim_point` todo quadro com a posição do mouse mesmo quando o disparo vem do direcional (`aim_target_3d`). No teste, `aim_point` era outro e a arma ficou virada (produto escalar −0,97) enquanto o tiro saía para o alvo | `_update_visual` e o laser passam a usar `_aim_direction()`: a mesma fonte do corpo e do disparo |
| 2 | **Corpo a corpo tinha zona morta.** A esfera de acerto ficava centrada em `alcance − 0,5`: soco, taco e machado **não acertavam alvo colado** (`dano=0` a 1,3 m com punhos, taco e machado; só a faca acertava) | Caixa do corpo até o alcance, acerta o mais próximo. Verificado: soco a 0,6 m e a 2,4 m acerta, a 4,5 m não; machado a 3,6 m acerta |
| 3 | Locomoção armada nunca entrava na velocidade normal (recusada a 3,5 m/s) | ver "Locomoção armada" |
| 4 | Morte virava o corpo num quadro; ferimento não tinha reação; mancha de sangue era um quadrado | queda em 0,22 s, reação de 0,2 s ao ferimento, mancha redonda e maior |

Falhas que **não** eram do produto (corrigidas no teste): o `parse_input_event` do mouse não move a posição do mouse do viewport e o cursor real do usuário interfere; NPCs de teste empilhados se lançavam para cima (sobreposição de `CharacterBody3D`); liberar corpos referenciados por equipes de emergência gerou erros em `Responder.gd:70` e `DispatchUnit` (o teste passou a afastar os NPCs em vez de liberá-los).

## Apresentação de ferimento e morte (aparência: vista em capturas, não aprovada)

- **Existente reaproveitado, sem dano novo:** o dano continua aplicado uma vez em `Actor.receive_damage`.
- **Ferimento:** o civil se curva para trás por 0,2 s (`rotation.x`, `FLINCH_ANGLE` 0,22 rad). Teste: `rot.x = −0,127` logo após o acerto.
- **Morte:** o corpo cai em 0,22 s até o mesmo estado final de antes (deitado de lado, 0,3 m). A colisão some no mesmo instante do dano, então a integração com a emergência não muda.
- **Sangue:** mancha redonda (gradiente radial, escala 0,6 m) sob o corpo, além das gotas; nas capturas o ferimento aparece como pontos vermelhos e a morte como o corpo caído com mancha (`evidence/combat/03`, `04`, `06`). **Fraco visualmente** em relação ao V1 (poça, pegadas): pendente de decisão de arte.

## Locomoção armada (regra V1 e resultado)

- **Regra V1** (`Player._physics_process`): a velocidade **não muda** ao mirar, recuar ou andar de lado (`current_speed` só depende de correr). Por isso **não reduzi o movimento**: o teste mediu 3,50 m/s recuando com a mira.
- **Antes:** os clipes armados (0,68–0,85 m/s nativos) eram recusados a 3,5 m/s, então recuar mirando usava a caminhada comum para a frente (pés andando ao contrário do movimento).
- **Agora:** ao recuar (cone de 45° para trás da mira) sem clipe armado que caiba, a **caminhada comum roda com a fase invertida** (a fase já é travada na distância, então não desliza e não acelera). Verificado: `anim = Walking`, `stance = gun`, fase seguindo `−distância/1,8 m` (0,00 → 0,22, esperado 0,22). Os clipes armados continuam usados só quando a velocidade cabe (direcional parcial).
- **Pendente:** passo à direita usa a caminhada comum (o clipe `Walk_Left_with_Gun` só entra em velocidade baixa) e à esquerda também; não espelhei o rig. **Aparência do recuo não validada** (uma captura `10_recuando_mirando.png`, sem julgamento).

## Som (o que se sabe)

- **Executado:** os sons novos são tocados sem erro nem aviso no log (recarga, impacto, gemido, golpe, tiro silenciado, chama). O caminho de reprodução funcionou e a duração da recarga vem dos WAVs.
- **Não avaliado:** a **qualidade auditiva**, o balanço de volume e a mistura. Ninguém escutou; volumes são escolhas minhas.

## Desempenho (janela real; 60 FPS é o limite do projeto; sem VSync alterado; amostra de 30 s por fase, 8 s de aquecimento descartados)

Outras sessões do Godot (editor, capturas e um teste headless de outras equipes) rodaram em alguns momentos; só iniciei quando não havia outra instância não-editor, mas outras subiram durante as amostras 1 e 4 (contaminação possível). Valores em **ms**:

| Amostra | Fase | p50 | p95 | p99 | máx. | quadros > 33,3 ms |
|---|---|---|---|---|---|---|
| 1 (polícia despachada) | parado | 16,67 | 17,17 | 17,67 | 18,99 | 0 |
| 1 | combate (SMG + explosão a cada 3 s) | 16,67 | 17,60 | 22,47 | 70,19 | 2 |
| 3 (procurado zerado por quadro) | parado | 16,67 | 17,09 | 18,11 | 19,69 | 0 |
| 3 | combate | 16,66 | 17,08 | 17,69 | **167,63** | 1 |
| 4 (idem, com primeira visita medida à parte) | parado | 16,66 | 17,17 | 17,47 | 18,34 | 0 |
| 4 | combate | 16,66 | 17,27 | 18,74 | 28,12 | 0 |

- **Primeira visita** (amostra 4): primeiro tiro 25,9 ms, primeira explosão 16,8 ms (pior quadro nos 6 seguintes).
- **Leitura:** no regime estável o tempo de quadro fica no teto de 60 FPS; p95 sobe 0,1 a 0,6 ms; p99 vai de −2% a +27% conforme a amostra. **Não há evidência de queda** a 12–15 FPS, mas: (a) **picos isolados de 70 ms e 167 ms apareceram em 2 de 3 amostras de combate e não os expliquei** (a amostra 4 não os reproduziu; a primeira visita da explosão não os causou); (b) o teto de 60 FPS **esconde folga**; (c) na amostra 1 a polícia despachada pode explicar parte do p99. **Estado: não aprovado, não reprovado.** É necessário repetir com a máquina sem outras sessões (pelo menos 3 amostras por fase) e investigar os picos com o profiler.
- Uma tentativa de amostra com `--no-dispatch` travou sem produzir saída (o flag não é compatível com este script); descartada.

## Diferenças V1/V2 que permanecem

- Mira: V1 tem pose de braço por IK e luneta com zoom; V2 orienta corpo/arma, usa clipes do `dante.glb` nos golpes e recuo por fase invertida. Luneta é contrato (`scope_active()`), sem zoom.
- Sangue e morte: sem poça, pegadas, restos, `PersonBurning` nem reação de pânico dos civis (o civil fica parado depois de levar tiro; comportamento de NPC não é desta frente).
- Lança-chamas: traço largo e fogo de emergência; V1 tem jato de partículas em cone.
- Efeitos por arma seguem pequenos na vista de cima (ponto vermelho, poeira).

## Pendências e contratos externos

- **Emergência/despacho (`Responder.gd:70`, `DispatchUnit`)**: atribuem uma instância já liberada quando o ator de uma ocorrência aberta é liberado por fora. No jogo o `EmergencyManager` só libera o ator depois da ocorrência, mas qualquer outro `queue_free` do ator (troca de região, saneamento) reproduz o erro. Para os responsáveis.
- **Economia:** a HUD passou de R$ 0 a R$ 100 e R$ 200 durante o fluxo (`dukenuke` e o abate). **Hipótese não confirmada:** recompensas de conquistas por número de armas. Para a equipe de progressão.
- **Mouse:** o disparo por mouse **não foi exercitado** (o cursor real do usuário interfere na janela de teste); a mira e o disparo foram validados pelo caminho de toque/controle (`aim_target_3d`). O caminho do mouse usa `aim_point`, sem alteração.
- **Veículo e morte do jogador no meio do golpe:** por leitura (`attack_allowed()` falso) e por `input_locked`; não exercitados com veículo real nem com a morte real do jogador.
- **Aparência e som:** aguardam julgamento humano; nenhum foi aprovado.

---

# Fechamento policial e explosões — 2026-09-21

Referência conferida novamente no V1 produtivo: `police/PoliceOfficer.gd` e
`guns/combat/WeaponReload.gd`. Os erros intermediários de compilação em
`was_dead`/`killed` não existem no código atual: `tests/test_gameplay.gd`
compilou e passou 208 verificações antes e depois da integração.

## Contratos fechados

- `Gameplay.explode` publica `explosion_occurred(origin, radius, source)` uma
  única vez por detonação admitida, depois de aplicar dano e efeitos. A fonte é
  a mesma usada pelo dano; `null` permanece desconhecido.
- `CivilianReactionDirector.configure(world, gameplay)` conecta esse sinal com
  guarda contra conexão duplicada. Não há chamada direta paralela a
  `report_explosion` no caminho produtivo.
- Patamares policiais seguem o V1: patrulha = pistola/6/rajada 2;
  detetive = SMG/6/rajada 3; SWAT, FBI e Exército = M4A1/8/rajada 3. Pentes vêm
  do `WeaponCatalog`, pausas são de 1,7–2,5 s e a recarga usa a duração e o som
  do banco real.
- `PoliceAgent.receive_damage` conclui a atualização de `dead` antes de
  encaminhar um atropelamento. O encaminhamento preserva o veículo como fonte;
  `Gameplay` só registra crime se `is_player_damage_source()` confirmar o
  controle do jogador. Tráfego, viatura e fonte desconhecida não são
  atribuídos ao jogador.

## Evidência dirigida desta rodada

- `test_police_combat_closure.gd`: **30/30** — arma, vida, dano por patamar,
  rajada, pente, recarga, fonte e ordem do atropelamento.
- `test_police_crime_contract.gd`: **10/10** — agressão/morte policial,
  explosão autorada, atropelamento fatal pelo `PoliceAgent` e deduplicação.
- `test_civilian_reactions.gd`, sessão produtiva renderizada: **36/36** — tiro
  real, silenciador, continuidade cidade–serra e explosão real com um evento e
  fuga do civil.
- `test_actor_locomotion_idle.gd`: **13/13**; integração independente do
  repouso de Dante: **8/8**; apresentação das 16 armas: **148/148**.
- `test_combat_flow.gd`: 66/67 na execução válida para lógica. Cheat, dano,
  explosivos, garagem, proteção, interrupções e economia passaram. A única
  falha foi a amostra tardia da curvatura transitória do civil ferido
  (`rotation.x=-0,019`, limiar `>0,020`); não foi usada para alterar animação
  nem para declarar apresentação aprovada.

Todos os cenários usaram `--no-save` e perfis temporários separados. Nenhum
save pessoal foi aberto. Benchmark não foi iniciado porque o editor Godot
permaneceu ativo, conforme a proibição de medição concorrente.

## Pendente explícito

- **Prisão/rendição:** existe no V1 e continua ausente no V2. Fora do escopo
  desta rodada; não implementado.
- Produtores futuros de explosão devem chamar `Gameplay.explode` exatamente
  uma vez com a fonte real (ou `null`). Não devem chamar
  `CivilianReactionDirector.report_explosion` em paralelo.
