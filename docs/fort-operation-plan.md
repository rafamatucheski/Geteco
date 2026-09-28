# Forte da Serra: operação militar

Estado em 2026-09-28: o **primeiro nível da operação está implementado**
(ante-sala + sala de operações com combate tático) e a **subida até o esqui**. Salas
adicionais do forte seguem abertas, ver "Próximas etapas".

## O que existe

Lugar oculto `mountain_fort` (`MountainFort.gd`, `MountainFortPlace.gd`), entrada pelo
cofre do túnel secreto (`docs/secret-headquarters.md`).

- **Ante-sala:** posto de guarda com o terminal que abre a porta blindada ("Abrir porta
  blindada"), mapa da serra, jaula de armas, sacos de areia. Sem inimigos.
- **Sala de operações** (atrás da porta, 20 × 18 m): 7 coberturas de altura de peito
  (barreiras de concreto e pilhas de caixas), mesa de comando, saque no canto leste
  (R$ 9.000 + M4A1 com 150 balas, persistidos como recompensa `mountain_fort_stash_*`),
  duas câmeras de vigilância que varrem a sala e duas portas de reforço no fundo.
- **Câmera:** a da ante-sala é fixa; na sala de operações ela acompanha o jogador
  (`FortOperation._follow_camera`).

### Soldados (`fort/FortSoldier.gd`)

- Esquadrão 1: 2 sentinelas, 2 patrulheiros e 1 líder (140 de vida). Reforço: 4 soldados
  (2 flanqueadores, 2 fuzileiros), chamados pelo alarme.
- **Percepção física:** raio contra o cenário; campo de visão de ~136°, alcance 15 m em
  guarda e 24 m em combate. A consciência sobe com a distância (mais rápido de perto):
  entre 35% e 100% eles investigam; a 100% vira combate. Tiros e a porta abrindo são
  ouvidos (`Gameplay.weapon_fired`).
- **Rádio:** quem vê o jogador alerta todo o esquadrão, que passa a mirar na posição
  real por 3 s (e enquanto o alarme durar); depois vale o último ponto conhecido.
- **Tática:** cada soldado escolhe um abrigo escondido da linha do jogador (lados e
  pontas da cobertura vêm de `MountainFort.HALL_COVERS`, então cenário e IA não divergem),
  sem dividir abrigo. Ciclo: esconder → espiar pela ponta com linha de visão → rajada de
  3 a 5 tiros → voltar. Flanqueador prefere abrigos do lado oposto; quem está a 35% de
  vida ou menos recua para o abrigo mais distante e espia raramente; quem perde o jogador
  por 9 s sai investigando.
- **Tiro:** acerto probabilístico (cai com a distância, com alvo em movimento e com o
  soldado ferido), dano 7, traçante e som pelo `Gameplay`. Cobertura bloqueia de verdade.

### Operação (`fort/FortOperation.gd`)

- Câmeras de vigilância: 1,2 s de contato visual disparam o **alarme**: giroflex,
  mensagem, todos em combate e, 5 s depois, o segundo esquadrão sai pelas portas do fundo.
- Navegação: grade A* de 0,5 m gerada dos colisores do interior (refeita quando a porta
  abre).
- Persistência: pegar o saque marca a operação como concluída; na visita seguinte a porta
  já está aberta e não há soldados. Uma luta interrompida recomeça na próxima visita.

## Subida para o esqui e entrada pela pedra

- **Elevador de serviço** no fundo da sala de operações (canto oeste): "Subir pelo
  elevador". Só parte com a sala calma (nenhum soldado em combate). Portas de grade
  fecham, a tela escurece ("Subindo..."), o jogador sai do forte e viaja até a serra.
- **Saída secreta** (`fort/MountainFortExit3D.gd`): afloramento de rocha na área de esqui,
  a leste da Boutique Alpina (mundo 744,5 / -481; serra ~7570 / -2740), no mundo real e
  não em um lugar. Ao chegar, a laje já está aberta; o jogador sai e, alguns segundos
  depois, a laje se **arrasta de volta** sobre a face com poeira de neve.
- **Entrada por fora:** com o cofre aberto, perto da laje aparece "Abrir passagem de
  pedra": a laje corre, a tela escurece e o jogador entra no forte; a porta redonda do
  forte devolve à frente da laje.
- **Mecânica:** `ProductionWorld.travel(região, destino)` ganhou destino próprio; o
  lugar `mountain_fort` aceita entrada de qualquer região (`any_region`) e o retorno é
  definido por quem entra (`MountainFortPlace.next_return`).

Teste: `tests/test_fort_ascent.gd -- --no-save [--shots]`.

## Próximas etapas (decisões suas)

1. **Forte maior:** salas seguintes (alojamento, arsenal, central de comando) entre a
   sala de operações e o elevador. Hoje o lugar é um interior isolado; uma região
   própria (o forte fisicamente sob o Summit) muda catálogo, streaming e save.
2. **Combate:** granadas, soldado com escudo ou franco-atirador, agachar/cobertura baixa
   para o jogador, som de alarme (hoje só luz e mensagem).
3. **Recompensa e história:** o que o saque revela sobre Vicente e o setor lacrado
   (origem segue ambígua por decisão de cânone).
4. **Balanceamento por jogo real:** dano, vida e precisão foram ajustados só por teste
   automatizado; falta sentir o combate jogando.

Teste: `tests/test_fort_operation.gd -- --no-save`.
