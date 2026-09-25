# Explosão inicial — atribuição de CPU, fase 4

## Resultado

**Corrigida uma parcela demonstrada do custo inicial; desempenho renderizado continua pendente.** A única mudança de runtime desta frente é em `runtime/ProductionWorld.gd::_prewarm_regions`: gera o cache existente de texturas carbonizadas durante o carregamento, após a guarda `--no-prewarm`/`skip_prewarm` e antes de liberar o jogo. Não cria fogo, carcaça ou custo por frame. `VehicleDamage.gd` foi preservado, inclusive seu hash.

Com o hook real de Main, a primeira destruição consumiu **15,905 ms de CPU**, incluindo **2,137 ms de carcaça**, contra 20,927/6,523 ms antes. A parcela da carcaça caiu cerca de **4,39 ms**; as três detonações foram confirmadas e concluíram com zero falhas/exit 0. O cache já estava pronto antes da primeira explosão. O custo de aproximadamente **4,5 ms foi transferido para o carregamento**, não eliminado. Tempos totais de startup variaram sob o jogo do usuário aberto e não servem como comparação isolada.

Main real, veículo criado por `ProductionWorld.spawn_vehicle`, primeira destruição e duas repetições com reparo, mesma posição/seed. Cada destruição produziu exatamente um `Gameplay.explosion_occurred`, carcaça e fogo. Processos separados para baseline e ablação: a única preparação adicional da segunda execução foi gerar o cache das duas texturas carbonizadas de `VehicleDamage._char`.

| Condição | Explosão | `receive_damage` total | Cadeia de explosão | Criação da carcaça |
|---|---:|---:|---:|---:|
| Cache frio | 1 | 20,927 ms | 14,404 ms | 6,523 ms |
| Cache frio | 2 | 9,660 ms | 8,381 ms | 1,279 ms |
| Cache frio | 3 | 10,027 ms | 8,881 ms | 1,146 ms |
| Apenas textura preparada | 1 | 13,480 ms | 12,184 ms | 1,296 ms |
| Apenas textura preparada | 2 | 8,481 ms | 7,253 ms | 1,228 ms |
| Apenas textura preparada | 3 | 9,409 ms | 8,272 ms | 1,137 ms |

Preparar o cache custou **4,524 ms** fora da detonação. A primeira criação da carcaça caiu de **6,523 para 1,296 ms**, próxima das repetições. O código produz duas imagens 128×128 com ruído/pixels/mipmaps no primeiro uso. Essa ablação demonstra custo inicial evitável nessa rotina; não prova resolução do travamento total nem ganho equivalente de FPS.

A cadeia da explosão ainda consumiu **12–14 ms no primeiro uso**, contra 7–9 ms nas repetições. Inclui áudio, fogo, consultas/dano, partículas e notificações. Ainda não foi atribuída a uma dessas partes; não recomendar remoção de efeito com esses dados.

## Método e limites

`tests/measure/video_phase4_explosion.gd` cronometra `receive_damage` e registra um callback de `destroyed` depois do callback real de produção. A diferença entre o fim desse sinal e o retorno de `receive_damage` corresponde à construção de `VehicleDamage.wreck`. O probe não substitui os métodos de runtime.

Godot 4.7.2; headless, tráfego 0, população 0, despacho desligado, `--no-save`, passo fixo 60 acelerado. O jogo do usuário permaneceu aberto. Portanto são tempos síncronos de **diagnóstico de CPU**, não benchmark isolado, nem custo de GPU ou aprovação do alvo 60 FPS/16,67 ms. Os monitores de CPU salvos por frame também não são um perfil de GPU.

Ambas as execuções: `exit 0`, zero falhas de workload. A execução com cache preparado emitiu, após o resultado, aviso de 14 instâncias ObjectDB e 5 recursos retidos no encerramento; o processo encerrou. O baseline não emitiu esse aviso. Nenhum processo do usuário foi encerrado ou save sobrescrito.

## Lacuna do benchmark existente

`tests/measure/measure_vehicle_wreck.gd` destrói o `world.driving.car` inicial. Por leitura das conexões atuais, esse carro possui o callback de `Driving`, mas não o callback de explosão ligado por `ProductionWorld.spawn_vehicle`. Quando vazio, sua destruição mede principalmente a carcaça, sem comprovar a cadeia de efeitos completa. O probe novo conta o sinal de explosão e usa veículo criado pela produção para evitar essa lacuna.

Os arquivos históricos `evidence/wreck-collision-0924/{before,after,confirmation}.json` já apresentam aumento de p99 de 20,912 ms para 34,081/35,057 ms e frames >33,3 ms de 2 para 23/22. Eram 30 s em 3440×1440/Mobile/RTX 4060 Laptop/24 NPCs, com 42/43 carros e sem marcadores de cada explosão. Essa diferença merece investigação, mas não permite atribuir a causa à textura, ao novo corpo físico ou ao runtime atual.

## Aparência e integridade

Quatro capturas reais de Main foram abertas e inspecionadas, nos mesmos quadros após a explosão (30/239), câmera e condições. Carcaça, padrões carbonizados, brasa, fumaça e fogo preservados. PNGs efetivos em **2560×1440**, Mobile/RTX 4060 Laptop; o projeto sobrescreveu a resolução de janela solicitada. São capturas funcionais, não benchmark de FPS.

- `explosion-render-before-f030.png` e `explosion-render-before-f239.png`
- `explosion-render-after-f030.png` e `explosion-render-after-f239.png`

As texturas lidas do render têm conteúdo binário idêntico antes/depois, incluindo mipmaps: albedo `de5de5e6acc4a69931b6d7f815a633079acc3af5c0d21323fba0059527bf6cd6`; brasa `0d2f4528a8d9b88d801922c510a175ad2ffdd0d126d1425310e469ffd40762b1`. Ambos os materiais continuam usando as mesmas texturas 128×128/RGB8. Cache antes da primeira detonação: `false` no BEFORE, `true` no AFTER. As imagens inteiras variam com o relógio dos semáforos; não foi alegada igualdade pixel a pixel da cena inteira.

`VehicleDamage.gd` permaneceu SHA256 `114CE11EDA63EE9391FD815874B6CA18B245083870BA4F28BFB2D817D7E11117`. `ProductionWorld.gd` passou de `E767E537F6D7A422724520027C22041193D11CC51D2DA900C87B33DA05AB80AF` para `65D4C3BA721D9B81530D14E0FCDB76C54467033FC2B6A3D7540EB5FBD88D416D`, com somente a chamada de cache e dois comentários adicionados por esta frente; demais mudanças locais preservadas. Processos BEFORE105520/AFTER87632 e CPU encerrados; os dois renders e o CPU AFTER não emitiram erros de encerramento.

Esse hash `65D4…` identifica **o momento do ensaio de explosão**. Depois desses testes entrou, em outra correção, a marca `distance_despawn` no descarte de veículos distantes para preservar o snapshot do carro anterior ao frete. Esse hook não participou do comparativo acima e não faz parte da otimização da textura; o hash histórico foi preservado.

## Arquivos e reprodução

- `explosion-cold.json` / `.log`
- `explosion-char-primed.json` / `.log`
- `explosion-load-primed.json` / `.log` (hook real após o patch)
- `explosion-render-before.json` / `explosion-render-after.json` (hashes de textura e workload)
- Script: `D:/geteco/game/tests/measure/video_phase4_explosion.gd`

```text
Godot_v4.7.2-stable_win64_console.exe --headless --path D:/geteco/game --log-file D:/geteco/game/evidence/video-review-phase4-20260924/explosion-cold.log --script res://tests/measure/video_phase4_explosion.gd --fixed-fps 60 --max-fps 0 -- --no-save --no-traffic --population=0 --causal-headless
```

Os dados BEFORE acima foram coletados antes da alteração. No código atualizado, o comando padrão mede o hook real; para voltar somente o cache ao estado frio no diagnóstico, adicionar `--cold-char` (o fixture limpa as duas referências antes da primeira explosão, sem alterar arquivos de runtime). Para reproduzir a ablação manual, usar outro processo com `--cold-char --prime-char` e outro nome de log. Esse seletor foi acrescentado depois dos dados para reprodução futura; não foi usado nas medições apresentadas.

Próximo passo pendente: atribuir os 12–14 ms restantes da cadeia e medir frames na cena renderizada isolada, com explosões comprovadas e marcadores de evento. O patch não resolve sozinho shaders, efeitos, física ou a regressão histórica de p99.
