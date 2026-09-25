# Revisão do vídeo — quarta fase

Três agentes trabalharam em queda do veículo, custo da Ammu-Nation/explosões e frete do porto. O coordenador integrou o HUD e revisou combate, prévias e controle na bancada. O relatório do Claude foi tratado como evidência para conferir, não como instrução para dispensar verificações.

**Implementações deste lote verificadas funcionalmente, com pendências explícitas.** A queda original continua sem reprodução causal. A Ammu-Nation ainda apresenta travamentos, e a comparação isolada de desempenho depende de liberar a partida do usuário. Editor 76560 e jogo 86396 foram preservados. Não houve commit nem descarte de alterações de outras sessões.

## Combate e bancada

- O clarão, a luz e a origem do disparo agora acompanham cano longo, compensador, choke, bico-de-pato e bicos do lança-chamas. O deslocamento existente do silenciador foi preservado.
- A lista de opções acompanha o foco do controle. O defeito foi reproduzido: a última pintura recebia foco fora da área visível. Teclas A/B e navegação direcional atravessam a sessão e a interface reais no teste.
- Removidas as duas barras genéricas que duplicavam o guarda-mato e apareciam sob o cabo da pistola. A M4 ganhou uma luva curta ligando seu cano às peças, sem mover a ponta ou alterar atributos de combate. Na SMG, foi retirado um dente de trilho que flutuava sobre a parte exposta do cano, nas versões de prévia e gameplay.
- A regressão antiga de combate tinha 18 falhas porque a fixture esperava dano imediato antes do contato da animação e disparava as armas seguintes enquanto esse contato estava pendente. A expectativa foi corrigida para aguardar o contato físico real, preservando os checks de dano e projéteis. **210/210 passaram**; não houve alteração da regra de combate para satisfazer a fixture.

O teste de origem do disparo passou inicialmente **76/76** em 16 casos. A confirmação ampliada passou **89/89** em 18 casos, acrescentando continuidade do encaixe da M4. A bancada passou **59 verificações funcionais + 9 gravações de PNG**, nas resoluções 1280×720 e 1920×1080. Antes havia uma falha de foco fora da área visível; depois, zero falhas. As 18 imagens antes/depois foram inspecionadas, confirmando rótulos, contraste, pistola e M4. Após o cache de materiais e a retirada do dente da SMG, uma confirmação justificada pelas novas mudanças passou novamente 59 + 9; todas as nove fotos finais também foram abertas e inspecionadas.

| Verificação | Evidência |
|---|---|
| Combate: 210/210 | [Log](../evidence/video-review-phase4-20260924/phase4-gameplay-contact-fixture.log) |
| Boca física/clarão/tracejante/encaixe: 89/89 | [Log](../evidence/video-review-phase4-20260924/phase4-muzzle-mount-after.log) |
| Bancada final: 59 funcionais + 9 PNGs | [Log](../evidence/video-review-phase4-20260924/phase4-workbench-final.log) |
| Pistola: guarda-mato correto | [Antes](../evidence/video-review-phase4-20260924/phase4-workbench-before-catalog-pistol-1280.png) · [Depois](../evidence/video-review-phase4-20260924/phase4-workbench-after-catalog-pistol-1280.png) |
| M4: compensador unido ao cano | [Antes](../evidence/video-review-phase4-20260924/phase4-workbench-before-1920-m4a1-compensator.png) · [Depois](../evidence/video-review-phase4-20260924/phase4-workbench-after-1920-m4a1-compensator.png) |
| Controle: última opção inteira na tela | [Antes](../evidence/video-review-phase4-20260924/phase4-workbench-before-controller-last-finish.png) · [Depois](../evidence/video-review-phase4-20260924/phase4-workbench-after-controller-last-finish.png) |
| SMG: dente de trilho flutuante removido | [Antes](../evidence/video-review-phase4-20260924/phase4-workbench-after-1280-smg-drum.png) · [Final](../evidence/video-review-phase4-20260924/phase4-workbench-final-1280-smg-drum.png) |

O teste de combate encerrou com avisos de 18 objetos ObjectDB/5 recursos retidos, contra 24/9 na execução anterior. Essa redução não prova correção de vazamento; não foi isolada a causa do teardown. Mensagens de acesso ao repositório de certificados do Windows também apareceram sem operações de rede nesses testes.

## Queda do carro

**Não encerrada.** O vídeo começa em CONTINUAR; o save inicial exato e a identidade do veículo branco não estão disponíveis. A aparência sugere um cupê junto de um caminhão após o resgate no Maciota, mas não prova seu identificador.

A reconstrução Ammu-Nation → banco → morte/resgate → embarque acompanhou 3.327 frames físicos: **12 verificações passaram**, sem perder o piso. Seis impactos reais de dois modelos de caminhão contra o cupê passaram **18 verificações**, também sem queda. Esses resultados excluem apenas as hipóteses e condições testadas; não reproduzem todo o tráfego, histórico físico ou save do vídeo. Nenhum patch de física foi acrescentado nesta frente.

[Investigação e limitações](../evidence/video-review-phase4-20260924/fall-investigation.md).

Uma causa diferente apareceu durante o frete: ao trocar a seleção para o caminhão distante, o carro anterior perdia seu piso antes do descarte periódico. A persistência podia capturá-lo já caindo. A comparação dirigida em Main começou em Y=0,000219 m; a ablação do callback anterior gravou Y=-0,833114 m, enquanto o callback corrigido manteve a última posição apoiada (9/9 verificações). Saúde, ID e equipamentos atuais continuam preservados. A física distante é descarregada normalmente; a correção conserva um snapshot seguro. Isso não identifica o veículo nem reproduz a queda de 02:21 do vídeo.

## Desempenho

Medições de CPU identificaram custo na construção das armas da Ammu-Nation e na primeira explosão. As comparações renderizadas desta fase são diagnósticas: outra partida permaneceu aberta. Headless, uma captura bonita ou 60 FPS estáveis nesse ambiente não encerram a exigência de comparação isolada.

A montagem das armas expostas passou a agrupar vértices em arrays e reutilizar chanfros de dimensões idênticas, com caches limitados. Uma prova independente de **144 verificações** compara triângulos, normais, UV, cores, materiais, transformações e partes móveis. Separadamente, a arte da loja reutiliza caixas/chanfros/materiais; **29 verificações** confirmaram geometria e isolamento entre armas e salas, incluindo o vidro que precisa de material exclusivo. No kit Harbor testado, as 614 instâncias de malha são preservadas, enquanto recursos distintos de malha caem de 614 para 192 e materiais de 606 para 150. Não se retiraram objetos da sala para acelerar o render.

A primeira comparação de Main, após otimizar somente as armas, reduziu a etapa de arte de 106,8 para 96,6 ms na entrada, mas o pico do frame permaneceu **186,2 → 182,5 ms**. Com os caches da sala, a confirmação final registrou **151,35 ms na primeira entrada e 114,78 ms na reentrada**, ainda travamentos significativos. A arte consumiu 77,55/68,61 ms; na janela estável de 30 s, p95/p99 ficaram em 17,521/17,912 ms, sem quadros acima de 33,3 ms. Houve diferenças de população dinâmica e mudanças paralelas no código da sessão; esses números não permitem atribuir ganho global ou certificar FPS. O ganho causal de construção foi medido separadamente em fixtures do kit.

Na explosão, preparar as duas texturas carbonizadas durante o carregamento retirou aproximadamente **4,39 ms** da criação da primeira carcaça: 6,523 → 2,137 ms no ensaio de CPU em Main. O custo de cerca de 4,5 ms foi transferido para o carregamento, não eliminado. As três detonações reais passaram; quatro PNGs foram inspecionados e os dados das texturas são binariamente idênticos antes/depois. Restam 12–14 ms iniciais na cadeia de explosão sem atribuição interna e a comparação renderizada isolada. [Investigação, hashes, fotos e limitações](../evidence/video-review-phase4-20260924/explosion-investigation.md).

A autorização para encerrar somente a partida preexistente foi solicitada; nenhuma resposta foi presumida. A comparação isolada depende dessa liberação ou do encerramento da partida pelo próprio usuário.

[Relatório da Ammu-Nation](../evidence/video-review-phase4-20260924/ammunation/phase4-ammo-handoff.md): ambiente, amostras brutas, métricas completas, seis fotos das três etapas, hashes e limites. A meta provisória de 60 FPS/16,67 ms não foi aprovada.

## Porto

Três cargas existentes podem ser assumidas legitimamente, uma por vez, e entregues ao depósito por R$300 cada. O ciclo usa os mesmos caminhões/guindastes e limita a recompensa total a R$900; não acrescenta frota ou trabalhadores. Os marcadores e objetivos funcionais acompanham a carga no HUD/minimapa, respeitando introdução e campanha. Aceite e entrega são ações explícitas junto ao caminhão parado; a entrega exige desembarque e devolve o veículo ao percurso do NPC.

O percurso físico de aproximadamente 230 m foi exercitado com a carga presa ao caminhão. A primeira execução completa encontrou falhas na restauração do motorista; não é registrada como suíte aprovada. O snapshot completo produzido no depósito foi conservado e usado para reduzir a reprodução, sem repetir o percurso a cada correção.

A inicialização cancelava a própria animação de embarque porque a sessão ainda não estava pronta. A exceção agora vale somente para concluir essa animação de restauração; F, interação, tiro, inventário, diário e pausa continuam bloqueados. Modal, resgate, prisão, respawn e viagem não podem usar a exceção. A posição de aproximação usa a porta real de caminhões/ônibus; as posições dos carros e das garagens foram preservadas.

A confirmação final em Main renderizado passou **42/42 verificações funcionais + 3 PNGs**: motorista ocupado no mesmo caminhão, visita preservada, HUD/minimapa, desembarque, pagamento único, reconciliação de recibo repetido, devolução ao NPC, compatibilidade do snapshot legado e perda definitiva do caminhão removido. A regressão do carro anterior passou **12/12**; a comparação física de posição apoiada passou **9/9**, após falha causal da captura anterior. A regressão de restauração nas garagens passou **26/26**, incluindo arma guardada e bloqueada. São provas distintas, com sobreposição; não se somam para alegar cobertura integral.

O carro anterior mantém identidade, dano e equipamentos quando o streaming o descarrega; devolver o empréstimo não substitui um veículo diferente selecionado depois. A remoção do caminhão salva somente após os callbacks de aposentadoria do veículo, impedindo ressuscitá-lo pelo autosave. O checkpoint histórico conserva a coordenada incorreta anterior do cupê, sem adulteração; a correção da posição foi demonstrada separadamente no teste físico comparativo.

As seis fotos do fluxo final e o baseline foram abertos e inspecionados. A cabine opaca não apresenta motorista NPC modelado; o controle e a retomada do percurso foram verificados funcionalmente. Essas imagens não aprovam a arte ou a oclusão de toda a área.

[Handoff do porto](../evidence/video-review-phase4-20260924/port-freight-handoff.md), [log final](../evidence/video-review-phase4-20260924/phase4-port-reload-final.log), [oferta](../evidence/video-review-phase4-20260924/phase4-port-after-offer.png), [entrega](../evidence/video-review-phase4-20260924/phase4-port-after-delivery.png) e [pagamento/devolução](../evidence/video-review-phase4-20260924/phase4-port-after-paid.png). O handoff preserva as tentativas falhas, o checkpoint histórico e os comandos de reprodução. A comparação de FPS do novo frete permanece pendente; o teste usou `--no-save` e exercitou JSON/GameState em uma nova sessão, sem escrever no save pessoal.

## Arquivos e reprodução

As alterações desta fase estão concentradas em:

- `PortFreightDelivery.gd` (novo), `PortCargoOperations.gd` e `UrbanOperations.gd`: ciclo de carga, persistência e devolução.
- `FullSession.gd`, `Driving.gd`, `ClassicGameplayHUD.gd` e `HarborMinimap3D.gd`: restauração do motorista, bloqueios de entrada e objetivo do frete.
- `ProductionWorld.gd`: preparação das texturas da carcaça e identificação do descarregamento por distância.
- `AmmunationArt.gd` e a cópia source de `WeaponFinish3D.gd`: caches e montagem das armas. A cópia de gameplay recebeu somente a retirada do detalhe flutuante da SMG.
- `Gameplay.gd`, `WeaponAttachmentVisuals.gd` e uma linha de `HarborWeaponWorkbench.gd`: origem dos efeitos, encaixe da M4 e acompanhamento do foco. As demais alterações da bancada pertencem à entrega do Claude e foram preservadas.
- Testes dirigidos `test_video_phase4_*`, probes `video_phase4_*` e a fixture de contato em `test_gameplay.gd`.

Motor utilizado: Godot **4.7.2 stable**, executável console local em `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`. Os handoffs de cada frente registram comandos e artefatos. Saves de teste são isolados; capturas renderizadas não constituem benchmark de FPS.

Os arquivos rastreados alterados nesta fase passaram `git diff --check`, sem erro de whitespace; houve somente avisos de conversão LF/CRLF. O estado local inclui trabalho de outras sessões e foi preservado. Todos os processos criados por esta fase foram encerrados normalmente; os dois processos preexistentes continuaram abertos.

## Limites mantidos

- A contagem permanece **9 acessos automáticos/9 interiores**, restando **23 acessos/21 interiores** para avaliação e implementação próprias. Esta fase não migra acessos.
- Não há nova certificação integral de interiores: circulação/colisão e oclusão de todos os ambientes, qualidade artística ampla, vazio e iluminação noturna continuam abertos.
- Capturas da bancada em duas resoluções e fluxo de controle não equivalem a revisar todas as combinações visuais de peças ou todos os dispositivos.
- O conteúdo do porto acrescenta um ciclo jogável concreto; não declara concluída a revisão ampla de toda a área.
