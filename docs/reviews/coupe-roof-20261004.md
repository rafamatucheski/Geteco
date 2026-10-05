# Porsche: acabamento interno atravessando o teto — 04/10/2026

O `sport_coupe` ganhava duas barras aparentes sobre o teto quando o jogador entrava ou roubava o veículo. A reprodução renderizada confirmou que eram peças do acabamento interno de `VehicleInterior`, criadas com a largura na base das janelas e prolongadas até o vidro traseiro. O teto físico estreita nas laterais e termina antes desse vidro.

O ajuste conserva as peças dentro da cabine: centro lateral em ±0,55 m, altura de 1,215 m e término traseiro em z=0,60 m. Os valores vêm do encontro do teto com o vidro lateral do modelo: x=±0,60 m / y=1,25 m, entre o montante dianteiro z=-0,30 m e a borda traseira z=0,64 m. O forro plano continua desabilitado nesse teto curvo. Os demais veículos usam os valores anteriores.

O interior continua sendo uma malha compartilhada por arquétipo, sem nós, luzes, colisores ou trabalho por frame novos. Câmera, escala do piloto, bancos e animação das portas preservam o fluxo existente. Trata-se de um ajuste local de profundidade da cabine, sem novo acesso ou migração de ambiente: zero novas certificações integrais de lugares.

## Evidências e validação

Evidências locais nesta máquina:

`C:/Users/rafae/.codex/visualizations/2026/10/04/01a1079f-353a-7c40-be4e-580949c4d704/coupe-roof/`

- `before-sport_coupe-{game,game2,side,top}.png` e `after-sport_coupe-{game,game2,side,top}.png`: vistas reais do modelo com o piloto e interior. A pintura sorteada difere entre essas capturas; geometria e enquadramentos são os mesmos.
- `before-crossing-{parked,seated,steady,moving,exited,reentered}.png` e os correspondentes `after-crossing-*`: fluxo real em `Main.tscn`, com pintura vermelha fixa, tráfego e população ativos, dia e tempo seco.
- `test_coupe_cabin.gd`: 7 verificações. Antes da correção, falhou em largura, altura e comprimento das peças superiores; depois passou nas 7. Verifica também presença do acabamento, reuso da malha na reentrada e isolamento do modelo compartilhado pelo tráfego.
- `test_vehicle_doors.gd -- sport_coupe`: 130 verificações aprovadas de abertura, percurso físico do corpo, contato com a porta, folga da cabeça e destino do embarque/saída.
- `test_digo_cabins.gd`: 30 verificações aprovadas nas duas cabines já modificadas por outra sessão, preservando seus ajustes e os valores padrão do acabamento.
- Fluxo real posterior em `Main.tscn`: 17 verificações aprovadas, incluindo roubo/embarque, motorista visível, movimento, saída com controle restaurado, reentrada e ausência de duplicação do interior.
- `Harbor.csproj`: build .NET aprovado, zero avisos/erros. Motor usado: Godot 4.7.2 .NET, executável `_console.exe`.

O contrato do teste de portas cobre colisão e passagem no vão; as imagens renderizadas conferem separadamente a profundidade do acabamento e a visibilidade do motorista. Essa revisão não certifica todos os móveis/interiores do jogo. Os processos de teste receberam `--no-save` quando aplicável. O motor reportou indisponibilidade do armazenamento de certificados do sistema; esse erro de ambiente não interrompeu o carregamento, a renderização nem as verificações locais.

## Performance

Meta provisória: 60 FPS / 16,67 ms. Critério de investigação antes do comparativo: aumento de mais de 5% em p95/p99 exigiria confirmação equivalente; a carga concorrente impede atribuir as diferenças à correção.

Comparação renderizada de 30 segundos, na RTX 4060 Laptop, renderer Mobile, 1920×1080, VSync e limitador desativados pelas configurações locais carregadas pelo jogo. A fixture preserva essas configurações e amostra o Porsche ocupado na mesma posição/câmera, com população e tráfego reais. JSONs incluem todos os intervalos de frame e metadados. A primeira captura junto a uma fachada foi apenas diagnóstica; o comparativo usa o cruzamento, onde o teto fica visível.

| Métrica | Antes | Depois |
| --- | ---: | ---: |
| Duração medida | 30,008 s | 30,002 s |
| Frames | 1.913 | 2.915 |
| FPS médio, frames/tempo | 63,749 | 97,161 |
| Frame time p50 | 15,428 ms | 10,933 ms |
| Frame time p95 | 25,495 ms | 17,197 ms |
| Frame time p99 | 36,350 ms | 26,529 ms |
| Máximo | 75,242 ms | 39,805 ms |
| Frames >33,3 ms | 25 | 9 |
| Frames >66,7 ms | 4 | 0 |

Ambas as amostras terminaram com 35 pessoas / 42 veículos, Porsche em `(66, 0,000219, 141)`, yaw -π/2 e câmera de tamanho 10. Arquivos `before-crossing-main.json` / `after-crossing-main.json`. São intervalos reais entre frames, sem identificação separada do tempo GPU. O aquecimento foi aguardado antes da janela de 30 s; seus intervalos não foram registrados, portanto não há certificação de stalls da primeira visita.

Estado da primeira correção: barras do teto corrigidas nos cenários descritos; **performance isolada pendente**. As caudas já excediam 16,67 ms no baseline e continuam excedendo esse orçamento após. A redução observada não pode ser atribuída à geometria corrigida. Essas amostras antecedem o ajuste do painel descrito abaixo.

Outras sessões executaram instâncias de Godot e alteraram sistemas compartilhados durante a revisão. Inventários `processes-before.json` / `processes-after.json` registram concorrência. Nenhum processo alheio foi encerrado; as alterações existentes foram preservadas. Por essa razão, as amostras não permitem aprovar performance isolada ou atribuir melhora/regressão a este ajuste.

## Segunda correção: painel atravessando o para-brisa

O usuário apontou o volume preto saindo à frente da cabine na própria captura anterior. Era a cobertura dos instrumentos, junto ao painel, colocada adiante do plano do para-brisa. Esse defeito visível passou na primeira revisão e não era coberto pelo teste das barras do teto.

A medição do vidro original encontrou borda inferior em y=0,82 / z=-0,88 e borda superior em z=-0,30, com y entre 1,25 nas laterais e 1,325 no centro. O painel agora começa 2 cm atrás da borda inferior; o volume mínimo tem 10 cm de profundidade. A cobertura dos instrumentos ficou em z=-0,75, com elevação de 2 cm sobre o painel e profundidade de 12 cm. Os mostradores acompanham a face dessa cobertura. Banco, escala corporal, volante e alvos das mãos/pés não foram deslocados.

- Teste `test_coupe_cabin.gd` ampliado para **10 verificações**: instrumentos presentes e todas as peças dianteiras altas abaixo do limite conservador do vidro, com 1 cm de folga. O teste reproduziu a falha antes do ajuste e passou depois, mantendo os 7 checks anteriores.
- Portas do cupê na versão atual: **128 verificações, zero falhas**. Cabines do Digo: **30 verificações, zero falhas**.
- Imagens reais após o ajuste, com pintura vermelha fixa: `panel-final-sport_coupe-{game,game2,side,top,front}.png`. Antes: `after-sport_coupe_game.png` e as vistas correspondentes, produzidas na correção das barras.
- Novas amostras em Main: `panel-before-*` / `panel-after-*`, com o mesmo roteiro de roubo, direção, saída e reentrada. A versão posterior concluiu **17 verificações, zero falhas**, com piloto visível e sem duplicação da cabine.

| Métrica do ajuste do painel | Antes | Depois |
| --- | ---: | ---: |
| Duração | 30,004 s | 30,005 s |
| Frames | 2.940 | 3.477 |
| FPS médio | 97,986 | 115,882 |
| p50 | 11,347 ms | 9,402 ms |
| p95 | 15,224 ms | 13,500 ms |
| p99 | 18,645 ms | 15,392 ms |
| Máximo | 46,285 ms | 38,659 ms |
| Frames >33,3 ms | 2 | 1 |
| Frames >66,7 ms | 0 | 0 |

Mesmo hardware/renderer/resolução/configurações e posição/câmera. A população dinâmica diferiu: **40 pessoas / 47 veículos antes**, **35 / 42 depois**. As sessões concorrentes também variaram (`panel-processes-before.json` / `panel-processes-after.json`). A diferença de carga impede atribuir a variação de FPS ao painel; **performance isolada continua pendente**. As imagens e o fluxo aprovam apenas o encaixe/funcionamento descritos. Não houve alteração relevante nos arquivos de Vehicle, Driving, World ou project.godot entre os hashes registrados imediatamente antes/depois do ajuste (`panel-sources-*.json`); outros arquivos continuaram recebendo alterações das demais sessões.

![Cabine com o painel encaixado](C:/Users/rafae/.codex/visualizations/2026/10/04/01a1079f-353a-7c40-be4e-580949c4d704/coupe-roof/panel-final-sport_coupe_game.png)
