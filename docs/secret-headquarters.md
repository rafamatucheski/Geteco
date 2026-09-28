# Arquivo de Vicente e quartel subterrâneo

## Papel na história

Depois de `cobra_finale`, Maciota reconhece que Dante conquistou sua confiança e
entrega a pasta deixada por Vicente. A conversa não cria missão principal nem
marcador no mapa. A partir daí, o jogador decide se investiga.

A pasta começa com um pedaço de mapa e uma pista numérica. A Casa 1 da Vila
contém outro indício. O acesso abre um anexo doméstico, desce para um porão
comum e só então revela a estante com keypad. Rádio, carimbo e marcas da casa
completam o código `1951` sem exibi-lo inteiro em um único texto.

Atrás da estante existe uma segunda descida física. O caminho passa por pedra
quebrada, água, canos, ratos e iluminação precária até o quartel. O setor selado
usa maca, grades, vidro quebrado e luz de emergência para sugerir experiências
ou contaminação. Nenhuma criatura ou explicação sobrenatural é confirmada.

## Fluxo jogável implementado

1. Concluir `cobra_finale` e conversar opcionalmente com Maciota.
2. Abrir **Arquivo de Vicente** pelo diário.
3. Investigar a Casa 1 da Vila e liberar o anexo.
4. Descer caminhando ao porão, encontrar as pistas e usar o keypad.
5. Atravessar a estante e percorrer o túnel contínuo até o QG.
6. Aproximar-se do setor lacrado para registrar a última peça do mapa.
7. Restaurar energia, registrar a rota da Vila e liberar a rota do esgoto.
8. Viajar ao esgoto de Harbor; a saída desse percurso retorna ao QG.

## Contrato técnico

- `SecretNetworkProgression.gd`: estado estrito, peças, pistas, energia e rotas.
- `SecretFileRuntime.gd`: pasta persistente fora do inventário descartável.
- `TruckersVillageSecretPassage.gd`: casa, anexo, porão, estante e keypad.
- `SecretTunnel3D.gd`: túnel, QG, setor selado, câmera e colisão.
- `SecretTunnelAudio.gd`: ambiência úmida e envio temporário de SFX ao reverb.
- `SecretTunnelRat.gd`: três ratos com rotas fixas e custo suspenso fora do túnel.

O acesso não entra no mapa público nem na lista normal de lugares. A geometria
fica suspensa fora de Harbor e só ativa o custo de áudio, luzes e ratos quando
Dante ocupa o subterrâneo.

## Continuação planejada

- Liberar os ramais do Porto Sul e da serra em terminais físicos próprios.
- Criar gravações reais de Vicente para os quatro registros da pasta.
- Desenvolver o setor selado mantendo a origem ambígua até a decisão de cânone.

## Reforma visual — segunda passagem

O porão recebeu estante com livros, rádio modelado, bancada com pés, rack aberto,
caixas e poças irregulares. No túnel, as paredes têm cursos de pedra com juntas,
arcos parciais, manchas minerais, canos com suportes e luminárias protegidas.
O QG ganhou mesa com mapa e marcadores, equipamentos antigos, quadro mecânico,
gerador e cama de campanha.
A grade permite ver a maca e o vidro do setor lacrado pelo recorte do teto.

As câmeras usam atmosfera própria, sem a neblina exterior, e as fontes de luz
participam da mesma camada visual do subterrâneo. O contorno de rua é suspenso
pela câmera local e restaurado ao sair. A entrada no túnel preserva a câmera
do porão para o retorno físico. Curvas e parede oeste do QG foram abertas;
a soleira da casa recebeu um patamar que liga o terreno ao início da rampa.
O túnel foi orientado para fora da parede real da estante, considerando a
rotação da Casa 1. As bases das rampas se prolongam sob o piso para permitir a
subida sem prender a cápsula do jogador na face de um degrau.
O pivô da estante foi movido para o lado oposto da abertura: a folha aberta
fica ao sul da passagem, enquanto a porta metálica ocupa o lado norte.
Isso libera a circulação junto à escada sem atravessar a porta ainda trancada.

As capturas antes/depois e logs desta revisão ficam em
`C:/Users/rafae/.codex/visualizations/2026/09/28/01a0e984-2604-7161-a752-4b6467689cce/secret-headquarters-v2/`.
A captura integrada aceita `--walk --depth` para percorrer com `Actor.gd` e
registrar Dante/NPC em frente, atrás e ao lado da mesa. O comparativo de frame
time continua pendente enquanto outra execução renderizada ocupa a mesma GPU;
os contadores presentes nas fotos não certificam desempenho.

A ida física integrada casa → porão → túnel → QG completou na revisão anterior
ao ajuste do pivô. Na volta, a subida do túnel passou, mas a estante bloqueou a
circulação lateral. O pivô foi corrigido; a repetição integral de ida e volta
após essa última alteração permanece pendente. As fotos finais estão em
`presentation/`; as amostras de oclusão de Dante/NPC junto à mesa, em `review/`.

## Reforma visual — terceira passagem (cenografia dos segredos)

`SecretTunnelDecor.gd` preenche o corte e conta o que o jogador ainda vai achar. Só
visual (mais colisores de mobília); não toca em progressão nem save.

- **Cantos pretos:** o vazio era o fundo da câmera entre as salas. Agora há lajes de
  rocha (abaixo dos pisos, sem colisão), pedras soltas, veios de musgo e dois canais de
  drenagem enterrados. O QG ganhou parede sul (colisor de altura cheia, visual baixo e
  quebrado) — antes o jogador podia cair da borda sul.
- **Linguagem de marcas pintadas:** anel azul = Porto Sul, triângulo ferrugem = serra,
  quadrado verde = esgoto. Aparece nos dois arcos emparedados da galeria longa
  (`route_south_port_drain`, `route_mountain_outfall`) e nas três escotilhas do QG.
- **Galeria:** trilho de serviço com vagonete, escoras de madeira, setas de giz e quadro
  de turnos com traços interrompidos (`audio_maintenance_shift`, `map_service_tunnel`).
- **Bomba e grade de drenagem** (`map_pump_station`, `map_drainage_grid`); **quadro de
  disjuntores** com três faróis e cabos até o QG (`power_*`, `map_power_branch`).
- **QG:** mural com os 6 fragmentos de mapa (o sexto rasgado), fotos do incidente,
  barbantes, prancheta do relatório de energia e crachá (`lab_*`); gaveteiros com gaveta
  aberta; mesa do gravador com uma fita por registro de áudio; tapete, lampião, tambores.
- **Setor lacrado:** manchas, suporte de soro, prateleira de frascos, vidro quebrado,
  arranhões e cadeira tombada; nada confirma a origem.

Orçamento de luzes subiu de 8 para 9 reais (bomba e mural; o resto é emissivo).
Capturas em `evidence/tunel-decor-20260928/{antes,depois}` (fora do Git). A captura
integrada ganhou as fotos `08`–`11` (arcos, bomba, disjuntores).

Verificado: `test_secret_tunnel_assets` (69 checks) e `test_secret_tunnel_traversal`
passam; a ida casa → QG completa a pé. **Não medido:** frame time (as fotos mostram
79–126 FPS com o editor aberto, sem valor de medição). A volta a pé para a casa trava no
último ponto (dentro da Casa 1, y ≈ −0,22), com ou sem esta decoração.

## Cofre e passagem para o forte

- **Entrada do setor lacrado:** o quadro de rede bloqueava fisicamente a abertura e o
  setor não tinha piso com colisão. Agora `power_sealed_sector` (ação "Energizar setor
  lacrado" no console) faz o quadro subir e as duas folhas do portão abrirem; o setor
  ganhou piso físico no nível do QG.
- **Código 3194, um dígito por indício** (`VAULT_DIGITS` em
  `TruckersVillageSecretPassage.gd`): crachá → 3, relatório de energia → 1, foto do
  incidente → 9, fita rotulada → 4 (também registra `audio_sealed_sector`). O teclado do
  cofre só aceita com os quatro e a energia; `can_unlock_final_door` passou a exigir a
  fita, e o restore do save rejeita a porta final sem ela.
- **Cofre:** porta circular no fundo do setor; ao abrir recua para dentro da parede e
  revela o vão. "Atravessar o cofre" leva ao lugar oculto `mountain_fort`
  (`MountainFort.gd`, `MountainFortPlace.gd`); a saída volta ao pedestal.
- **Correção de câmera:** ao sair do túnel para um lugar (esgoto e forte) o túnel
  devolvia a câmera do porão como atual; `set_return_camera` passa a devolver a do mundo.
- **Volta a pé para a casa:** a quina frontal do patamar da escada da Casa 1 ficava ~5 cm
  acima da rampa de 41° e prendia a cápsula; o patamar agora começa onde a rampa termina.

Combate tático e o restante do forte: `docs/fort-operation-plan.md`.
Testes: `tests/test_secret_vault.gd -- --no-save` (dígitos, energia, portão, código
errado/certo, ida ao forte, saída e volta), além dos de progressão, assets e travessia.
