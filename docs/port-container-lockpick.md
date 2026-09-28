# Contêineres do porto — 28/09/2026

18 contêineres térreos do pátio receberam interior nativo, portas de duas folhas
com dobradiças e colisão, e arrombamento. Contêineres superiores e cargas de
navios/caminhões não oferecem interação. Não há transferência para outra cena.

## Fluxo implementado

- Ammu-Nation: lockpick por R$ 75, quantidade exibida, limite de 999. Compra
  usa a transação atômica do inventário existente e não equipa uma arma.
- Interagir na porta abre um minigame de ângulo e torque. Mouse ou direções
  ajustam a gazua; interação/clique pressionado gira o cilindro. O ponto correto
  não é exibido: giro parcial e vibração indicam proximidade e esforço.
- Forçar fora do ponto correto desgasta a ferramenta; quebra consome exatamente
  uma. Sucesso conserva a ferramenta. Cancelamento conserva o inventário.
  Não há mais rolagem de probabilidade nem abertura por esperar um timer.
- Ao caminhar para dentro, teto desaparece e câmera sobe em 0,6 s para uma
  vista superior centralizada, com aproximação de 16%. Ao sair, retorna à
  apresentação exterior. Os sólidos permanecem físicos durante o recorte visual.
- As cargas alternam entre dinheiro (R$ 180–450), 24 munições de pistola,
  pistola/escopeta, colete (até 100 de proteção) e vazio. Arma já possuída vira
  12 munições para ela. Colete cheio e munição sem arma/reserva deixam o loot
  disponível. Recibos por contêiner e ciclo impedem duplicação.
- Após 20 minutos ativos desde a abertura, o contêiner pode receber nova carga:
  exige jogador a pelo menos 70 m, fora do enquadramento e nenhum corpo/NPC
  dentro ou na área das portas. Fecha, trava e alterna entre três disposições
  físicas de caixas e baú, mantendo o corredor central livre. Não avança offline.
  O relógio e o ciclo persistem; saves antigos de duas flags continuam válidos.
- Arrombamento em andamento e coleta podem ser denunciados por civis,
  trabalhadores ou policiais vivos: alcance de 22 m, orientação visual e raio
  físico sem parede entre testemunha e jogador. O recorte do teto não remove
  essas paredes. A denúncia ativa ao menos uma estrela e o despacho real de
  viatura; não aumenta estrelas repetidamente pela mesma observação.
- Texturas PBR procedurais compartilhadas: pintura desgastada, oxidação e
  madeira. Chapas corrugadas, revestimento interno, travessas, ferragens,
  barras de trava, piso de tábuas e caixa de loot têm geometria própria.
- O abrigo continua bloqueando chuva mesmo quando o teto fica visualmente oculto.

## Integração

`PortContainerState.gd` define IDs e loot estável; `PortContainerLoot.gd` conecta
sessão, inventário, minigame e presença física. `LootablePortContainer.gd`
constrói visual e colisão a partir das mesmas dimensões. A câmera continua sendo
atualizada apenas por `CameraRig.gd`. Abertura, morte, teleporte e descarregamento
restauram o contexto de apresentação.

O acabamento urbano respeita `native_dynamic_roof`: não acrescenta outra laje
opaca sobre um teto removível. A transparência usa materiais locais, pois
`GeometryInstance3D.transparency` não funciona no renderer Mobile, conforme a
[documentação do Godot](https://docs.godotengine.org/en/4.4/classes/class_geometryinstance3d.html#class-geometryinstance3d-property-transparency).
Malhas fixas são agrupadas por material; não há novos SubViewports de interiores
nem luzes. A procura por contêiner ocupado/oclusores ocorre a cada 0,1 s e somente
os contêineres carregados participam; tweens existem apenas nas transições.
Reposição verifica no máximo os 18 registros uma vez por segundo. A percepção
durante arrombamento roda a cada 0,5 s e para após a primeira denúncia da tentativa.

## Evidências e validação

Pasta: `evidence/port-lockpick-20260928/`.

- `test_port_container_state.gd`: 51 checks aprovados (compra, capacidade,
  cinco tipos de carga, ciclos, recibos, inventário e validação atômica do save).
- `test_container_lockpick.gd`: 8 checks aprovados (controle angular, giro
  parcial, desgaste, quebra, acerto e cancelamento distinto).
- `test_port_containers.gd`: 55 checks aprovados em Main renderizado após a
  câmera superior. Inclui catálogo real, interação/minigame real, caminhada
  pela porta, coleta, save em arquivo isolado, reconstrução de instância,
  sólidos com jogador/NPC, camada superior inacessível e limpeza de câmera.
- `test_port_container_depth.gd`: 86 checks aprovados nos três layouts, com controle renderizado de jogador/NPC frente,
  atrás e ao lado da caixa/parede; teto realmente oculto no Mobile e restauração
  opaca. Resultados em `depth/results.json`.
- `test_port_container_restock.gd`: 53 checks aprovados em Main renderizado:
  armas, munição de arma repetida, colete cheio, vazio, colisões/circulação dos
  três layouts, bloqueio de reposição com ocupantes, troca de ciclo, streaming,
  SaveStore real, testemunha viva/morta/distante/de costas/atrás de parede e
  denúncia durante controle bloqueado. O despacho criou `police#1`, variante
  `patrol`, a 32,58 m, sem simular a polícia. Log: `restock-final.log`.
  Capturas: `restock-layout-0.png`, `restock-layout-1.png`, `restock-layout-2.png`.
- A validação encontrou uma comparação de arrays de inteiros/floats no contrato
  do motocross que rejeitava o save após JSON. Correção restrita à comparação
  numérica, com regressão dedicada de roundtrip; dados dos contêineres eram válidos.
  `test_motocross_progress.gd`: 27 checks aprovados, log `motocross-json-final.log`.
  Regressão do fluxo original: 55 checks aprovados em `restock-lockpick-regression.log`.
- `capture_port_containers.gd`: câmera superior em três contêineres, permanência
  da vista durante menu, abrigo de chuva e limpeza de câmera/clima na saída
  aprovados. Capturas finais diurnas e noturna/chuvosa inspecionadas.
- Regressões: `test_campaign_economy.gd` (162 checks) e `test_camera_rig.gd`
  aprovadas; não foram alteradas regras de combate/garagem.
- Capturas de jogo: `ammunation-lockpick.png`, `lockpick-minigame.png`,
  `inside.png`, `two-actors.png`, `exit.png`, `final-interior-*.png` e
  `night-rain-interior.png`. Capturas intermediárias de diagnóstico permanecem
  na pasta; usar as de prefixo `final-` para a apresentação final.

## Performance — pendente

Alvo: 60 FPS / 16,67 ms; aumento maior que 5% em p95/p99 exige confirmação.
Ambiente renderizado: Godot 4.7.2, Mobile, RTX 4060 Laptop, 1280×720;
configuração carregada do usuário limita a 144 FPS. Contador em captura não é
aprovação de desempenho.

A tentativa inicial de baseline falhou ao gravar evidências sob a restrição
de acesso do processo. Depois disso, outras sessões mantiveram testes de jogo
e benchmarks em execução. Não foram interrompidas e não se mediu uma comparação
concorrente como se fosse isolada. Não há baseline válida nem aprovação de FPS.
Na ampliação de loot/reposição também havia testes gráficos de frete e do túnel
em outras sessões. As capturas funcionais dos layouts não são benchmark.
Na última checagem, continuavam ativos testes headless de motocross e passarela;
eles também disputam CPU. Não foi declarado isolamento por estarem sem janela.

`tests/measure/measure_port_containers.gd` está preparado para 8 s de aquecimento
+ 30 s de amostras reais por cenário, guardando intervalos, p50/p95/p99, máximo,
frames acima de 33,3/66,7 ms e captura. `--baseline` reconstrói a geometria/corpos
anteriores com o modelo original preservado e acabamento urbano; essa referência
é reconstruída para o regime estável, não mede carregamento da versão anterior.
Executar antes/depois sem outros jogos/testes concorrentes, com `--no-save`.

Estado: implementação funcional validada nos casos acima; certificação integral
dos 18 interiores permanece em andamento até a comparação de performance e
evidência anterior/final equivalentes. Mensagens de liberação de textura no
encerramento do Godot foram observadas nos testes renderizados e estão nos logs.
Durante a última captura, uma alteração concorrente em `CanalTunnel3D.gd`
gerou erros de `surface_get_primitive_type` em BoxMesh durante o pré-aquecimento.
Os checks de contêiner continuaram e passaram; a outra sessão corrigiu depois
o acesso, restringindo-o a ArrayMesh. Esse log não certifica o túnel.
