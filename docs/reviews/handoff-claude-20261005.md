# Geteco — passagem de contexto para Claude, 05/10/2026

Este commit consolida todas as alterações locais versionáveis solicitadas pelo usuário, incluindo trabalho concorrente de outras sessões. Não atribua todos os arquivos à investigação de performance. Os relatórios registram o alcance de cada validação; não há aprovação global de FPS ou de todo o jogo.

## Ambiente e regras

- Workspace: `D:/geteco/game`. Leia `AGENTS.md` e siga performance-do-jogo, testes-com-criterio e guardiao-do-jogo nos trabalhos pertinentes.
- Motor obrigatório: Godot **4.7.2 .NET/mono**, commit `ed1daf0bf`, instalação `D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64`. Use `_console.exe` para logs.
- Compile `Harbor.csproj` antes de executar. Último build antes deste commit: sucesso, zero avisos/erros. As capturas e os contratos relevantes exercitaram C# real; não aceitar fallback GDScript como validação desse caminho.
- Preserve saves e alterações concorrentes. Não usar checkout/restore/reset/clean para descartar arquivos locais. O usuário autorizou incluir o estado local completo neste commit, sem push solicitado.

## Performance: mudanças integradas no jogo

1. **Geometria de caixas:** `StaticBoxBatch.gd` reutiliza os arrays CPU de uma caixa unitária, preservando transformações e atributos. Aplicado aos ônibus e depois a `SecretTunnel3D`, `VerticeSiteDressing` e `TruckersVillageHomes`. As operações de append do terminal caíram de cerca de 39 ms para 2,4–2,5 ms. Nos três builders urbanos, reduções locais de aproximadamente 82%/81%/89%; primeiro frame de loading 7,8 s → 6,6–6,8 s no A/B dirigido. Não significa que todo o loading foi eliminado.
2. **Digo:** retenção/preload do script Amarok evita `load` tardio no callback de Motocross, inclusive quando o veículo nem seria criado. Load interativo 69–92 ms → acesso 0,003 ms. O custo inicial passa ao loading.
3. **Rota C# do terminal:** primeira Curve real preparada/reutilizada sob a cortina, com invalidação do contrato existente. Plano interativo 25–32 ms → 0,007–0,008 ms. CLR mostrou contribuição de JIT nessa primeira chamada; não atribuir todos os stalls ao JIT.
4. **Passageiros:** geometria imutável dos KITs dos IDs80–95 preparada antes do gameplay, sem criar/admitir atores, ônibus ou gates antecipadamente. Dezesseis readies 18–20 ms → 4,6–5,1 ms. RNG, identidades e instâncias preservados.
5. **Coaches:** sete ArrayMeshes completos do primeiro corpo visual compartilhados pelos três seguintes; materiais, rodas, portas, labels e colisões continuam próprios. Montagem dos quatro corpos 11,7–13,7 ms → 5,1–5,2 ms.
6. **Sangue:** template de material imutável retido por dono, RID preparado no loading; cada mancha mantém seu material/fade e a mesma geometria/RNG/raycast. Primeira allocation e recriação após zero manchas 18,8–25,5 ms → cerca de0,08 ms nas confirmações finais. Preparação de cerca de20 ms permanece no loading.

As 1233 verificações dirigidas da primeira integração e as 616 da extensão urbana passaram nas rodadas documentadas. Elas verificam contratos/equivalência, não FPS. Não somar tempos inclusivos de pais/filhos nem apresentar as reduções das operações como porcentagem de FPS global.

Leia [relatório inicial](D:/geteco/game/docs/reviews/intermittent-stalls-20261004.md), [continuação](D:/geteco/game/docs/reviews/intermittent-stalls-continuation-20261004.md) e [histórico de 02–03/10](D:/geteco/game/docs/reviews/performance-architecture-20261002.md).

## Cache e ferramentas de medição

- O isolamento de APPDATA/LOCALAPPDATA também criava cache ShaderRD vazio em cada teste. O runner agora declara cenário frio e aceita seed compatível/verificado antes do motor. Dois draws iniciais de54–57 ms ocorreram em ambos controles frios e desapareceram nos dois braços com seed. É correção do protocolo; nenhum cache foi distribuído nem a primeira execução fria deixou de ser relevante.
- Reutilizados StallLog, StallWorkTrace, measure_physics_boundaries e ThreadCpuProbe. O collector guarda detalhes de frames≥25 ms, incluindo abaixo40 ms, com posição/população/filas/entidades/eventos e relógios.
- Corrigido o ring: pico longo retém o prefixo relativo ao START, não somente ao fim. Ainda existe limite de borda POST: último frame cruzante pode perder alguns ms de detalhe; timings brutos permanecem. Cauda finita pode truncar contexto posterior.
- WPR elevado finalmente funcionou. Rec1 expirou durante preparação, sem Game/trace; rec2/rec3 foram os dois jogos efetivos e encerraram/salvaram suas instâncias próprias depois de FINISHED. Perfil1GiB Memory, CSwitch/ReadyThread/SampledProfile/Loader, janela nominal READY85..125, fim real próximo123. Sem suspensão da main, mudanças de prioridade/energia/política, desligamento de Bluetooth ou suporte a controles.
- Helper antigo consultava MainModule repetidamente. Candidata privada QUERY_LIMITED mantém PID/nascimento/imagem/parent/liveness e cleanup. Preflight50 pares iguais+PID próprio encerrado recusado; no gameplay CPU própria durante recording9,423% → 1,581% de um núcleo, redução83,218%. **Melhoria do observador, não Game fix ou ganho de FPS.** Os dois helpers e o perfil foram preservados.
- Analisador scheduler v2 corrigiu ReadyThread anterior a Out e o byte7 DeferredReady confundido com Unknown do enum .NET. Usa pares completos In→Out no mesmo CPU; não interpola estado faltante. ETLs/v1 preservados.

## Trava de1,7 s: permanece aberta

Controle `shader-cache-a1`, frame16083, READY+102,102540 s, durante gameplay/recuperação, jogador perto107,99/23,3 estrelas/4 unidades. Frame1709,627 ms; draw3,660 ms; callback físico8,701 ms. Gap **1694,572 ms depois do último callback físico e antes do próximo process_frame**, sem avanço dos contadores CPU quantizados. Isso não distingue Waiting/Ready nem identifica solver, driver, GC ou carga externa. Catch-up vem depois. O frame15918/street_pre1486 ms é outra localização e não deve ser agrupado automaticamente.

As sete capturas desta investigação dirigida não reproduziram essa assinatura longa. Dois controles de carga ccusage próprios também foram negativos para≥250 ms, mesmo com CPU/RAM elevadas: inconclusivo. Dono atual de ccusage identificado como OpenUsage; temporariamente pausado apenas naquele experimento e restaurado sem mudança de settings. Nas duas WPR finais ficou ativo normal; nenhum burst positivo de ccusage foi observado em gameplay. Não assumir que fechar OpenUsage resolveria1,7 s.

WPR rec2 teve recuperação1 estrela/5 unidades e transição a custódia em+116,59 s, zerando ambas. Prisão é inferência forte a partir da posição/caminho de respawn/eventos, sem sinal específico player_arrested coletado. Rec3 manteve3 estrelas/4 unidades/local original perto97/102 s, sem pausa≥250. Condições nominais não garantem trajetórias/carga/host idênticos.

Nova família rec2: seis tailframes105–121 ms, gap80–94 ms **post_draw→primeiro callback físico**. Perfil diferencia espera em contexto PeekMessage/NtUserPeekMessage e residência/amostras DirectInput/RegOpenKeyExW/NtOpenKeyEx, compatíveis com detecção SDL. Stacks disponíveis ligam CSwitch-IN, não o Out iniciador; não é duração exclusiva de API ou prova do lock/sinalizador. Sem correção dessa família e sem atribuição à pausa histórica. Usuário informou nenhum controle conectado/em uso; presença PnP Bluetooth de DualSense pode ser pareamento, não conexão. SDL_HINT_JOYSTICK_THREAD=1 já é definido pelo motor, portanto não proponha isso como solução nova.

Sem PDB nativo Godot compatível aprovado: use módulo/RVA e inferência de fonte/callsite explicitada; export vizinho NoHotPatch não nomeia função. Scheduled running inclui interrupções não separadas. Perfil não tem DPC/IRQ/hard faults; não provar paging por PageFaultCount agregado ou RAM livre baixa. Pre/post_draw é wall de caminho de desenho, não GPU exclusiva.

Últimas métricas GP120 s: rec2 p50/p95/p99=5,603/12,988/14,624 ms, máximo83,432,9 frames>33,3 e3>66,7; rec3=6,198/14,026/15,735, máximo94,667,13 e4. Rec3 p95/p99 maiores e caudas em estados distintos: não aprovar ganho global. Loading/primeira passagem permanecem nas análises separadas.

Leia [investigação central](D:/geteco/game/docs/reviews/stall-1709-investigation-20261005.md), [auditoria rec2](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-causal-audit.md), [auditoria rec3](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-causal-audit.md) e as sínteses nativas correspondentes. Os lotes finitos foram encerrados: próximo experimento exige hipótese nova/positivo discriminante, não repetição até passar. Preserve qualidade/população/colisão/gameplay e teto físico herdado3; reduzi-lo não remove gatilho.

## Outros trabalhos concorrentes incluídos

- Empinada em motos de rua e motocross, Shift/L3/toque/remapeamento, pose/pivô traseiro/descida suave; correção do toque que FullSession consumia antes do overlay. Relatório registra217 checks funcionais; performance de rua inconclusiva e motocross com manobra ainda sem benchmark completo.
- Intro de barco de73 s/1080p30, versão noturna chuvosa, poses próprias do celular, áudio/legendas PT/EN, Arrival e reprodução/skip/restore. Cidade oculta deixa de renderizar durante o filme; isso não mede performance da cidade ativa. Assets de produção e mídia fazem parte do estado solicitado.
- Torque substitui fachada Aurora e diversifica seis carros do encontro; preserva calendário/população/fluxos/colisão/iluminação. Performance comparativa inconclusiva por concorrência.
- Cabines Gol/Amarok e cupê: dimensões, acabamento/painel/teto/portas e ocupante; recorte de terra sob deck do Digo; demais ajustes e testes de profundidade, pose, marcas viárias e dano. Não atribuir ganhos de FPS às medições concorrentes desses trabalhos.

Consulte os relatórios específicos em `docs/reviews/`. Esta síntese não reexecuta suas suítes nem certifica todas as features em conjunto. Saves pessoais, caches .godot, ETLs, dumps privados, payloads de billing e snapshots enormes continuam locais/ignorados. Resumos e helpers selecionados do diagnóstico são versionados; caminhos de evidência bruta podem exigir esta máquina.
