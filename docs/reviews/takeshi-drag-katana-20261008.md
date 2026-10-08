# Takeshi, Supra A80 e katana

Pedido implementado por três agentes de trabalho e integração na sessão principal. Todas as alterações locais anteriores foram preservadas; nenhum checkout, restore, reset ou clean foi usado.

## Fluxo

- Takeshi é um desafio opcional no encontro das drag races, acessível pessoalmente ou pelo botão do quadro. Não ocupa uma posição nem altera os prêmios dos seis rivais do campeonato.
- A fala precede a largada. O duelo usa Toyota Supra A80, preparação de competição e física da arrancada. A primeira vitória registra uma escolha pendente; adiar ou interromper o menu não elimina o prêmio.
- O prêmio é único: Supra com as peças da prova ou katana da família. Escolher o carro libera a katana na Ammu-Nation por $300.000. A transformação em sabre custa $150.000 uma vez; o seletor aceita qualquer cor e as trocas posteriores são gratuitas.
- A katana usa `ual/Sword_Idle` e `ual/Sword_Attack` da biblioteca já existente, com sequência de três cortes. O RAGE recebe carga pelo dano de combate efetivamente descontado da vida, após armadura; frio e invulnerabilidade não dão carga. `V`, clique na barra ou `R3` ativam quando cheia e com a katana equipada.
- O RAGE reduz o tempo global para 0,1 durante 15 segundos reais, preservando movimento, golpe e câmera de Dante. Pausa, modal, troca de arma, veículo, morte, região e encerramento interrompem o efeito e restauram o tempo. Save conserva carga, nunca o efeito ativo.
- Desmembramento é apresentação de NPCs humanos derrotados com rig articulado compatível. Até 12 partes e oito vazamentos simultâneos, com duração limitada. Personagens protegidos e Dante não entram nesse caminho. Rigs especiais sem membros separados conservam sua apresentação de morte.
- O sabre usa geometria emissiva, zumbido e sons sintetizados de corte. Não acrescenta fontes de luz dinâmicas.

## Contratos e evidência

Ambiente: Godot **4.7.2 .NET**, `Harbor.csproj` compilado; C# confirmado na sessão Main. RTX 4060 Laptop, renderer Mobile. Encontro/loja em 1280×720; combate em framebuffer 1920×1080 com UI lógica 1280×720, VSync ativo e limite 144 FPS. Checkpoints e gravações em diretórios exclusivos de `evidence/`; saves pessoais isolados por `--no-save` e fixtures próprios.

| Verificação | Resultado disponível |
|---|---|
| Simulação da arrancada | 6/6; Takeshi 14,550 s, Mirage completo 14,400 s, intermediário 16,400 s, original 19,783 s; completo com erros 15,467 s e sem nitro 14,867 s |
| Supra A80 | 23/23; modelo, integração da frota, rodas, portas, luzes e preparação; 27 lotes e 12.132 triângulos |
| Main: presença, colisões, diálogo, largada, vitória e entrega do Supra | 33/33; `evidence/takeshi-drag-session-layoutfix.log` e `evidence/takeshi-session-195752-6298295/` |
| Main final: katana, revanche e recuperação | 39/39; corrida vencida com física real, escolha da katana, interrupção da fala, nova tentativa, cancelamento e preservação do prêmio; `evidence/takeshi-drag-final.log` e `evidence/takeshi-session-36368-6326600/` |
| Coleção, escolha única, compra, cores, save/load | 37/37; `evidence/takeshi-honor-final.log`; inclui frota completa mais Supra, inventário cheio e save real em disco |
| Katana/RAGE, animação, dano e limpeza | Contrato focado 35/35; dano ambiental 8/8; UAL 12/12; Main RAGE 9/9, tecla V real, duração 15,013 s, deslocamento 1,40 m, câmera com desvio máximo 4,7 px; interrupção pela entrada física na garagem também observada |
| Loja produtiva | 14/14; porta física, balcão, preços, conversão, cor livre, preview e retorno ao jogo; `evidence/takeshi-shop-verified.log` e `evidence/takeshi-shop-199112-6337941/` |
| Regressões da garagem | Recompensas 47/47, restauração do motorista 34/34, transferências físicas 11/11; `evidence/takeshi-garage-rewards.log`, `evidence/takeshi-garage-driver.log`, `evidence/takeshi-garage-transfer.log` |
| Falas PT-BR | 6/6 recursos carregados no Godot .NET; build C# final sem avisos/erros; `evidence/takeshi-voice/bank-test.log` |

A simulação mede a possibilidade de vencer, sem substituir condução humana. O teste Main percorre a corrida com comandos determinísticos de acelerador, trocas e nitro, usando veículos e física reais. O estado anterior da campanha vem de fixture válida, não de repetição de todas as missões.

Avisos fora da funcionalidade: o runner de recompensas da garagem encerrou com duas instâncias ObjectDB não liberadas; a restauração percorreu uma fala de guarda do porto sem gravação pt_BR. Ambos terminaram sem falhas nas verificações. Esses avisos não foram ocultados nem convertidos em aprovação de toda a sessão.

## Performance e limites

Não há baseline anterior válido: o primeiro runner não conseguiu gravar seus arquivos no sandbox do Godot. A repetição autorizada com acesso de escrita ao workspace resolveu esse impedimento, mas já havia alterações de código. Outras instâncias do Godot foram observadas e preservadas. Portanto não há aprovação de ausência de regressão.

Encontro com o Supra final: 30 s, 144,01 FPS, p95 8,894 ms, p99 11,859 ms, máximo 13,324 ms, nenhum frame acima de 33,3/66,7 ms. As métricas e amostras brutas estão em `evidence/takeshi-session-36368-6326600/metrics.json`. A execução anterior ficou em 143,97 FPS; nela houve um travamento de aproximadamente 7 s na primeira visita, separado da janela estável, cuja causa não foi atribuída à mudança. Não é uma comparação antes/depois da implementação.

Combate atual, com NPCs/tráfego/diretores ativos, população solicitada 8 e invulnerabilidade diagnóstica do jogador: aço 107 FPS, p95 14,16 ms/p99 16,21 ms; sabre sem RAGE 103 FPS, p95 14,18 ms/p99 16,19 ms. RAGE ativo, janela de 30 s incluindo ativação e recuperação: 114,49 FPS, p95 12,608 ms, p99 15,417 ms, máximo 20,12 ms e nenhum frame acima de 33,3 ms. São cenários atuais distintos, não comparação antes/depois. A captura temporal de 30 s foi separada da medição para evitar confundir custo de readback e gravação com gameplay.

Sequência temporal: `evidence/takeshi/katana/katana_rage_30s.mp4`, 841 quadros, 29,966 s, VFR com timebase de 1 ms, sem áudio. É a primeira captura completa, com ativação por API, contador e recuperação após aproximadamente 15 s. A medição posterior de 15,013 s por tecla V está em `evidence/takeshi/katana_rage_final/measure.json`; ela não gerou essa sequência. Imagens finais do Supra em `evidence/supra-a80-185272-6383254/`; pose de corte em `evidence/takeshi/katana_pose/sword_0.55.png`.

Os faróis e lanternas do Supra reutilizam os sistemas do jogo e foram inspecionados em capturas diurnas/noturnas. Não foi registrada sequência temporal noturna do carro; essa cobertura não certifica ausência de flickering à noite.

As seis falas foram sintetizadas localmente em português pelo Qwen3-TTS VoiceDesign, mantendo o perfil autorado de Takeshi: 43,09 s em WAV mono 24 kHz/16 bits. Foram integradas e carregadas pelo banco real, com as 87 gravações anteriores preservadas e seis novas entradas. Cinco falas passaram na conferência de transcrição; a palavra “subestimei” da vitória continua com revisão auditiva pendente: a transcrição float32 sem prompt reconheceu “subeste-mei”, com o restante íntegro. Isso é ambiguidade de reconhecimento, não comprovação de pronúncia correta nem incorreta. A pendência está explícita em `audio/mission_voices/takeshi_drag/production.json`; auditoria e teste estão em `evidence/takeshi-voice/`.

A importação terminou com exit 0 e avisos ao fechar o editor (uma DummyTexture, um CanvasItem, quatro ObjectDB, um resource e EditorSettings export/android); o teste dedicado do banco de vozes terminou sem esses avisos. Não foi feita limpeza nem alteração de configurações de exportação fora do pedido.

O gerador isolado usa produção em etapas, uma thread, GPU limitada a 60%, residência máxima de 2 GiB e limite de memória privada de 8 GiB, condicionado a pelo menos 10 GiB de RAM livre. O teto anterior de 6.000 MiB impedia o primeiro forward; o pico observado foi 6.348 MiB privados, que incluem backing de CUDA no Windows. O gerador compartilhado não foi alterado.

A validação visual se limita aos enquadramentos e sequências efetivamente registrados. Transcrição e existência de streams de áudio não equivalem à aprovação auditiva de atuação e continuidade da voz.

## Revisão de golpes e RAGE — 8 de outubro

Katana ajustada para 45 de dano e intervalo de 0,78 s: dois golpes em PoliceAgent comum (50 HP), três em Actor (100 HP). Três trajetórias autoradas de duas mãos substituem a repetição do clipe: vertical, diagonal e ascendente, com antecipação, quadril, recuperação e hit-stop de 55 ms. Corrida usa locomoção com guarda baixa, sem Sword_Idle sobreposto. Referência de apresentação: [AUSKF Iaido Judging Points](https://www.auskf.org/department/iaido/iaido-judging-points); não é certificação de técnica marcial.

RAGE passa a contar dano de combate absorvido pelo colete e completa com 40 pontos de dano; HUD mostra porcentagem. Invencibilidade continua sem gerar carga. Ativação exige katana equipada e barra cheia (V/R3). Não foi reproduzido o relato de carga totalmente imóvel em jogo normal: o caminho real Actor.receive_damage → Gameplay → HUD → tecla V passou. O teste anterior usava carga direta e não cobria essa cadeia. Uma falha intermediária veio de loot de arma nova equipando-a automaticamente; a fixture agora possui previamente a arma do policial e verifica a katana equipada em cada golpe, preservando o comportamento produtivo de loot.

Build .NET: 0 erros/avisos. Teste dedicado: 35 checks aprovados, incluindo proteção e interrupção na garagem. Cena Main renderizada: 36 checks aprovados, RAGE de 15,009 s reais, movimento 3,03 m durante efeito, apoio no cabo com erro observado de 0,8–3,4 cm nos contatos amostrados. Capturas de preparação/corte e corrida em `evidence/katana-final/`; log `evidence/katana-final.log`. Saves do usuário não foram modificados nesta revisão.

Performance **não aprovada**. Baseline de aço em `evidence/katana-fix-before/`: 99,59 FPS, p95 14,91 ms, p99 17,607 ms. Final: 58,98 FPS, p95 29,128 ms, p99 37,273 ms, máximo 72,716 ms, 44 frames acima de 33,3 ms e 2 acima de 66,7 ms em 30,012 s. Sabre/RAGE final: 62,21 FPS, p95 32,260 ms, p99 45,043 ms. Editor, preview de deserto e testes de outra sessão foram observados durante as medições e preservados; há variação entre execuções, mas isso não demonstra a causa da piora nem permite atribuí-la somente à concorrência. Comparação isolada e investigação de frame time permanecem pendentes. Capturas com readback foram feitas fora das janelas de benchmark e seus contadores de FPS não representam essas janelas.
