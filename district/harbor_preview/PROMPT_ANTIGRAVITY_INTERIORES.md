# Prompt para o Antigravity — interiores vivos do Breakwater

Trabalhe no projeto Godot em `D:/geteco/game`. Quero implementar interiores
jogáveis para o protótipo independente
`res://district/harbor_preview/HarborPreview.tscn`. Não é uma tarefa de gerar
apenas imagens ou mockups: preciso entrar, andar, conversar, interagir e voltar
ao exterior no jogo real. Leia os AGENTS.md aplicáveis e o estado do Git antes
de editar; preserve trabalho existente e não faça commit sem autorização.

## O que já existe — não refaça as portas

As fachadas do protótipo não têm nomes escritos. Sua identidade é arquitetônica
e visual: garagem industrial/amarela, polícia azul com escudo, hospital claro
com símbolo médico, bombeiros com três baias. Preserve esse princípio; não
acrescente letreiros para compensar interiores indistinguíveis. Textos funcionais
de diálogo/menus são permitidos, não são placas decorativas nas fachadas.

Leia primeiro:

- `district/harbor_preview/HarborEntrance.gd`
- `district/harbor_preview/HarborBuilding.gd`
- `district/harbor_preview/HarborDistrict.gd`
- `district/harbor_preview/HarborNorthDistrict.gd`
- `scripts/entrances/BuildingEntrance.gd` e `.tscn`
- `scripts/entrances/EntranceRouter.gd`
- `interiors/CentralGarageInterior.gd`
- `DistrictInteriorManager.gd` e `.tscn` (referência, não ligar o distrito legado inteiro)
- `JagerNPC.gd`
- `tests/test_harbor_entrances.gd`, `tests/test_garage_door_and_npcs.gd`

HarborEntrance já herda BuildingEntrance e reutiliza seu sensor, sinais e API.
As portas abrem por aproximação e fecham depois de o jogador se afastar.
`interior_available` é **false**: até agora isso é só animação de fachada, sem
teleporte ou interior. `BuildingSolid` continua bloqueando o prédio. Não remova
esse sólido inteiro para fazer parecer que entrar funcionou.

Portas já autoradas na cena:

| Nó relativo à raiz do protótipo | Destino sugerido |
| --- | --- |
| `District/Garage/Entrance` | Garagem com Maciota |
| `District/Police/Entrance` | Recepção da delegacia |
| `District/Clinic/Entrance` | Recepção/triagem do hospital |
| `NorthDistrict/MotorWorkshop/Entrance` | Oficina menor |
| `NorthDistrict/NorthFireStation/Entrance0`, `Entrance1`, `Entrance2` | Mesmo quartel, retorno à baia usada |

Cada porta tem um Marker2D `OutsideReturn`. Use sua posição global real para
voltar ao exterior — o hospital entra pelo **norte**, as demais pelo sul. Não
copie coordenadas de retorno da garagem do distrito legado. O `destination_id`
é estável: `harbor/<provider>/<prédio>/<porta>`. `get_entrance_state()` publica
posição global do limiar, ponto externo de aproximação, direção, largura e estado.

O componente também suporta os tipos `ammunation` e `morgue`/`iml`, mas **não há
lotes desses dois tipos nesta cena ainda**. Prepare interiores reutilizáveis
para eles, sem inventar um lote, mover prédios ou abrir ruas por conta própria.
Não alegue que estão acessíveis pela cidade enquanto não houver entrada autorada.

## Garagem: reutilize o Maciota correto

O personagem roxo já criado é **Jäger “Maciota”**, classe `JagerNPC`, em
`res://JagerNPC.gd`. É um rig procedural 3D em SubViewport, com traje roxo,
fedora, óculos, corrente e bengala. Reutilize esse personagem/visual/animações;
não substitua por um NPC genérico, outra cor, retrato ou asset gerado do zero.

`CentralGarageInterior.gd::_build_jager_lounge()` instancia o nó `JagerMaciota`
a partir desse script. Reaproveite essa composição quando apropriado. O
`MechanicTito`, mecânico azul, é **outro** personagem: não o chame de Maciota.
A referência visual existente é `res://tests/garage_npcs_view.png`.

Maciota já tem oito falas, animações e sinais `dialogue_opened`/`dialogue_closed`.
O diálogo existente é linear: não alegue opções ramificadas sem implementá-las.
Preserve sua identidade/persona e faça dele um personagem com quem realmente
se possa conversar dentro da garagem, não apenas uma estátua de decoração.

## Conteúdo obrigatório — não entregar uma sala cuja única ação seja sair

O jogador deve ter motivo para permanecer no local. Cada interior precisa de:

1. Layout reconhecível, com circulação e colisões coerentes: recepção, área de
   atendimento/trabalho e detalhes específicos do estabelecimento. Não copie
   uma sala vazia mudando a cor. Escala, portas, balcões e mobiliário precisam
   caber no movimento do Player real, sem spawn dentro de paredes ou móveis.
2. Pelo menos um personagem animado e conversável: Maciota na garagem,
   atendente/enfermeiro no hospital, policial na recepção, vendedor na loja de
   armas, funcionário no IML. Conversa deve abrir, avançar e fechar de verdade.
3. Animações de ambiente relevantes, além da porta: trabalho do mecânico,
   ventilação/equipamentos, monitor de triagem, rádio da polícia, bancada ou
   sistema de refrigeração. Pelo menos duas ações animadas perceptíveis por
   interior; não apenas um cenário estático com uma luz piscando.
4. Pelo menos uma interação útil além de conversar e sair, compatível com o
   lugar. Exemplos: serviço de garagem existente, triagem/atendimento, consulta
   no balcão ou inspeção contextual de equipamento com uma resposta real.
   Reutilize serviços já implementados quando possível. Não invente compra,
   reparo, cura ou recompensa fictícia: se a integração não existir, implemente
   uma interação contextual honesta e relate a limitação.

“Não basta sair da sala” é um requisito de conteúdo, **não** autorização para
aprisionar o jogador: mantenha saída funcional e cancelamento de diálogo.
Não bloqueie a saída até comprar algo ou esgotar falas sem uma missão autorada.

## Integração segura

- Faça primeiro a garagem ponta a ponta e valide; depois replique o contrato,
  não a decoração, para os demais interiores.
- Prefira novas cenas/scripts sob `district/harbor_preview/interiors/` e um
  coordenador local. Reutilize Player, Maciota e recursos existentes sem criar
  outro jogador ou importar toda a cena Main para este protótipo.
- A entrada exige uma interação deliberada. Não teleporte quem apenas passa
  pela porta automática. `handle_input_locally` está false; coordene a ação
  `interact`/`request_interaction(actor)` com o foco de interação existente.
- Os portões também reconhecem um carro controlado pelo jogador, ignorando
  carros estacionados. Não confunda esse ator com o Player: no fluxo a pé,
  estacione/desembarque antes de entrar; se implementar entrada dirigindo,
  preserve motorista, veículo e câmera juntos. Não teleporte só o carro deixando
  o Player oculto e sem controle no exterior. Teste também a saída desse estado.
- Só ative `interior_available` depois de registrar o destino. O sinal
  `destination_requested` é herdado de BuildingEntrance. EntranceRouter já
  transfere para marcadores na mesma cena; para PackedScene externa ele apenas
  emite `external_destination_requested`. Não confunda isso com carregamento
  implementado: crie o consumidor/lifecycle necessário se usar cenas externas.
- Aguarde a animação da porta, faça uma transição curta e posicione o Player
  num SpawnPoint físico válido. Ao sair, restaure a câmera e use OutsideReturn
  da porta exata que foi utilizada. Zere velocidade residual e evite reentrada
  automática, teleporte em loop, duplicação de NPC ou perda do estado do jogador.
- Maciota usa E/Espaço/Esc no diálogo. Os sinais atuais não bloqueiam sozinhos
  movimento e disparos do Player. Implemente foco/modal corretamente: o mesmo E
  não pode entrar, iniciar conversa e avançar três falas no mesmo frame.
  Desabilite ações incompatíveis durante conversa/transição e restaure-as ao
  fechar, inclusive em cancelamento ou remoção da cena.
- Não transforme telhado em piso nem deixe o jogador desaparecer atrás da
  renderização. Preserve o estilo 2.5D/3D já usado pelo jogo.
- Não altere malha viária, navio, trem, CityLot, CityRoadCurve, addons, missões,
  save/settings ou menu para esconder problemas de interior. Não ative missão,
  respawn ou recompensa nova sem escopo explícito. Se uma dependência exigir
  ampliar o escopo, explique antes.

## Prova de funcionamento e entrega

Para cada interior conectado, teste com o Player e o input reais: aproximar,
abrir porta, entrar, andar, conversar, executar uma interação útil, sair e voltar
ao ponto externo correto. Repita três ciclos. Verifique que não existem colisões
indevidas, diálogos sobrepostos, perda de controles, NPC duplicado ou dupla entrada.
Teste também recusar/cancelar diálogo, tentar interagir longe e sair durante o
estado permitido. A garagem precisa mostrar o **Maciota roxo existente** animado.

Execute os testes de entrada, de espaço físico do distrito e os contratos novos
dos interiores. Capture imagens/vídeo com renderizador real; headless sozinho
não prova animação, identidade visual nem visibilidade do personagem. Não basta
compilar ou chamar diretamente um teleporte para declarar o fluxo aprovado.

Há uma falha de circulação anterior em `test_harbor_life.gd`, em Courtyard Lane,
registrada em `D:/geteco/harbor_ship_regression_20260904/RESULTS.md`. Não apague
essa evidência, não enfraqueça o teste e não use isso para alegar que seus testes
passaram. Separe regressões novas de problemas anteriores comprovados.

Entregue arquivos alterados, interiores realmente conectados, interações/NPCs
implementados, evidências dos testes, como jogar e limitações. Não chame uma sala
decorativa ou uma animação sem destino de “interior completo”.
