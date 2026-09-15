# Boeiro secreto — revisão de apresentação

Tampa junto à delegacia em `(1182, 2114)`, 32 unidades abaixo da posição anterior para afastar o acesso da mureta. Escala de 0,72 para 0,50, sem o arco circular externo. Alcance de interação de 68 para 27 unidades. O aro de ferro elíptico pertence ao objeto; não há marcador de chão.

A tampa é uma malha 3D (`ManholeCover3D.gd`), com disco de ferro espesso, aro, grade em relevo e encaixes de levantamento. Usa a apresentação 3D→2D dos objetos do projeto, com SubViewport renderizado uma vez: o arrasto translada a peça sem mudar sua perspectiva. Não há dobradiça ou achatamento. Dante se abaixa e acompanha a tampa por 28 unidades para a esquerda, mantendo a distância de pegada; ao voltar, recoloca a mesma peça no vão.

A descida de superfície dura dois segundos, com três transferências de degrau. Dante se vira para a escada, alterna braços/pernas e mantém a escala original. Os braços usam o solver anatômico do Player e cabeça/ombros acompanham o torso. Um shader temporário recorta o corpo na borda fixa do vão, substituindo o encolhimento e a transparência da apresentação anterior. A saída inverte o percurso, afasta Dante do vão e fecha a tampa. Material, pose, controles e colisões são restaurados.

O interior agora é uma instância de `SewerInterior.tscn` em um SubViewport com **World2D próprio**, não uma sobreposição de colisões na rua. Dante é transferido para essa instância (inventário e saúde continuam sendo os mesmos), e projéteis, explosões, impactos e efeitos são criados nela. O SceneTree mantém a rua residente, com seus scripts/inputs/timers suspensos, para permitir o retorno sem recarregar o distrito. A escada ainda é uma sequência animada, não uma escada controlada manualmente.

A galeria foi reduzida de 1000×620 para 460×270 unidades. Arquitetura 3D com cache de renderização, duas lâmpadas locais, alvenaria, piso irregular, tubulações com conexões e válvula, escada vertical, passarela, prateleiras, quadro elétrico, barris, caixas, mangueira, grelhas, detritos e umidade. A recompensa visual também foi reduzida para ficar proporcional ao Dante.

O arrasto ganhou preparação, transferência de peso, pernas articuladas com sola nivelada, pegada com IK e soltura antes de ir para a escada. A animação mantém o rig de produção, incluindo sua ancoragem atual de cabeça/ombros.

Fontes externas têm pausa e volume preservados/restaurados individualmente; nenhum bus global é silenciado. Tiros, explosões e golpes filtram os alvos por World2D. O WantedManager não aceita crime do interior isolado. Saves feitos lá embaixo conservam os itens coletados e usam a posição segura do boeiro para o próximo carregamento.

## Validação

- `tests/test_manhole_sewer.gd`: 53 verificações passaram na revisão de isolamento, sem erros de script ou vazamentos na última execução. Inclui projétil nativo, granada, dano de explosão e corpo a corpo contra alvos em posições iguais nos dois mundos, áudio externo inaudível, água local audível, suspensão/retorno de scripts, save e inventário.
- `tests/review_manhole_sewer.gd -- --campaign`: percurso na cena HarborGame com inicialização de gameplay, disparo por mouse e retorno com E. As verificações do esgoto passaram e as capturas estão em `D:/geteco/artifacts/manhole-sewer/isolated/`. A execução global não está aprovada: alterações concomitantes expuseram erro em `PlayerCombatPose.gd`, ao acessar `torso_node` de `NPCCombatRig`, fora da implementação deste interior.
- Metadado `harbor_interior` corrigido para booleano, compatível com os sistemas de rua; o teste visual não desativa mais a ferrovia.
- Medição renderizada de 30 segundos por cenário, 1280×720, Mobile, RTX 4060 Laptop, limite de 60 FPS. Tampa fechada: 59,96 FPS, p95 17,233 ms, p99 17,771 ms, máximo 71,155 ms. Ciclos da escada: 59,96 FPS, p95 17,261 ms, p99 17,767 ms, máximo 59,254 ms. Cada cenário teve um quadro acima de 33 ms. Amostras brutas em `D:/geteco/artifacts/manhole-sewer/revision-perf/`.

Essa medição compara os estados da revisão no preview, não versões anterior/posterior em campanha. Validação de performance na sessão completa de HarborGame permanece pendente; não há aprovação global de FPS.

Na investigação do retorno, alternar visibilidade/process_mode do distrito inteiro produziu um quadro de 5268 ms. A versão atual conserva as prévias visuais residentes por trás da apresentação opaca e suspende flags de execução dos scripts, sem remover os corpos de física do mundo da rua. O retorno voltou a concluir a sequência animada. Não considerar o pico resolvido como aprovação de todos os frame times da campanha, especialmente com o erro de NPC citado acima.

A captura/restauração explícita do áudio evita depender apenas de `stream_paused`, que também é alterado automaticamente por notificações da árvore e de pausa no motor ([documentação do Godot](https://docs.godotengine.org/en/4.4/classes/class_audiostreamplayer.html#class-audiostreamplayer-property-stream-paused)).

## Medição da instância isolada — 13/09

Comparação no HarborPreview, mesma GPU/renderer/resolução/limite descritos acima e 30 segundos por estado. Amostras brutas em `isolated-before/` e `isolated-after/`, dentro de `D:/geteco/artifacts/manhole-sewer/`.

- Tampa fechada antes/depois: 60,03/60,05 FPS; p50 16,671/16,666 ms; p95 17,177/17,490 ms; p99 17,566/18,008 ms; máximo 18,143/19,282 ms. Nenhum quadro acima de 33,3 ms em ambas as janelas.
- Interior ativo antes/depois: 60,06/60,03 FPS; p50 16,649/16,666 ms; p95 17,116/16,892 ms; p99 17,391/17,119 ms; máximo 17,771/20,466 ms. Nenhum quadro acima de 33,3 ms em ambas as janelas. CPU física média 3,156/1,015 ms.

Sem sinal acima da tolerância de 5% em p95/p99 nesses estados estáveis. Não mede toda a campanha, a primeira renderização da arquitetura nem garante ausência de pico durante transições. Os arquivos de personagem/cidade receberam mudanças simultâneas, o que limita a atribuição causal fina do comparativo.

## Comparação da tampa 3D

Mesma configuração renderizada acima, 30 segundos por cenário, processos separados: `3d-before/` e `3d-after/` em `D:/geteco/artifacts/manhole-sewer/`. Inclui a mudança solicitada de posição/câmera e mantém a população dinâmica do preview, portanto não isola apenas o custo da malha.

Tampa fechada antes/depois: 60,01/60,01 FPS; p50 16,666/16,655 ms; p95 17,268/17,268 ms; p99 17,721/17,979 ms; máximo 46,784/54,814 ms. Ciclos antes/depois: 59,96/59,96 FPS; p50 16,662/16,675 ms; p95 17,239/17,287 ms; p99 17,851/17,867 ms; máximo 62,147/61,481 ms. Cada janela teve um quadro acima de 33,3 ms e nenhum acima de 66,7 ms. Não houve sinal acima da tolerância de 5% em p95/p99 nesse preview; campanha completa continua não medida.
