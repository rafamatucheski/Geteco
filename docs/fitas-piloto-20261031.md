# Fitas do piloto: lugares e estado (31/10/2026)

Card do Trello "Dez fitas e esconderijo secreto do piloto". Plano: [plano-coletaveis-20260928.md](plano-coletaveis-20260928.md).
Código: `data/catalogs/PilotTapes.gd` (ids, pontos, galpão), pickups em `activities/Activities.gd`,
nomes em `data/catalogs/CollectibleCatalog.gd`, marcador do galpão em `ui/hud/WorldMapData.gd`.
Teste: `tests/test_pilot_tapes.gd`.

## Como funciona

- Cada fita é um colecionável comum (o mesmo caminho das cartas de Vicente): pickup que gira e flutua,
  `Economy.collect` com recibo `collectible:<id>`, então o save guarda a fita e ela não conta nem paga
  duas vezes. Ordem livre.
- Modelo: a mesma `BoxMesh` + `StandardMaterial3D` do achado de papel, só com outra cor e tamanho
  (cassete escura, 20 x 13 cm). Nenhum shader ou material de tipo novo.
- Ao pegar: aviso comum "Fitas X/10. Próxima: \"<dica>\"" com a dica (tabela abaixo) da fita que
  falta mais perto na mesma região; sem nenhuma na região, a primeira que falta. O diário (J →
  Informações) lista "Fitas do piloto X/10" e as dicas das que faltam, a partir da primeira fita.
- Portão (31/10/2026, parte 2): a porta de enrolar física do Digo (`world/desert/DigoVehicleGate.gd`,
  sem arte nova) fica em `HIDEOUT_POINT`, montada uma vez na primeira passagem por Harbor e
  estacionada fora dele (escondida, colisão aberta). Trancada: ação "Abrir portão" →
  "Fechado. Algo aqui espera dez fitas.". Com o recibo `pilot_tapes_hideout` ela sobe e para de bloquear.
- Na décima: recibo `pilot_tapes_hideout` (uma vez só, sem dinheiro),
  aviso de que o galpão abriu, save, e o marcador "Galpão do piloto" aparece no mapa de Harbor.

## Os dez lugares

Coordenadas em metros de mundo (x, z). Harbor e serra usam o ponto de retorno de um lugar que já existe
em `world/places/PlaceCatalog.gd` (área que o jogo já mantém livre na saída), deslocado 1,5 a 2 m; o
pickup se prende ao chão pelo raio dele. Deserto: ao lado de um lugar de `RoadsideLayout.SITES`, 3 m
fora do raio do lugar, no eixo paralelo à estrada (o centro fica a ~22 m da pista).

| # | Região | Lugar | Ponto | Dica | Por que é legal |
|---|---|---|---|---|---|
| 1 | Harbor | Garagem do Chefe, porto sul | (338.7, 366.9) | "Onde o chefe guarda o que não é dele." | Ponta sul do porto, área restrita do desmanche. |
| 2 | Harbor | Quartel Northgate | (369.8, -75.2) | "Sirene vermelha, portão grande." | Portão do quartel de bombeiros, no norte. |
| 3 | Harbor | Jardim de Westgate | (17.1, 15.2) | "A casa do jardim, no extremo oeste." | Bairro residencial calmo, oposto ao porto. |
| 4 | Harbor | Boca do esgoto | (75.6, 132.1) | "Embaixo da cidade tem outra cidade." | Ao lado do bueiro que leva ao esgoto da polícia. |
| 5 | Serra | Cume Branco (Summit) | (716.5, -476.0) | "Lá em cima, onde se aluga esqui." | Topo da serra, neve e vista. |
| 6 | Serra | Cabana do Cavaleiro | (656.5, -900.6) | "A cabana que ninguém marca no mapa." | Lugar mais escondido da serra (espada e escudo). |
| 7 | Serra | Abrigo dos Lenhadores | (766.5, -252.5) | "Cheiro de serragem." | Junto da serraria, pé da serra. |
| 8 | Deserto | Torre de rádio | (-825, -518) | "Quem sobe vê tudo." | A torre que revela segredos do deserto. |
| 9 | Deserto | Ferro-velho do Nonato | (-1036, -619) | "Entre carcaças, uma fita inteira." | Faz sentido para um piloto: peças e sucata. |
| 10 | Deserto | Salinas Estrada do Sal | (306, -960) | "Branco que não é neve." | Paisagem mais estranha do mapa, longe de tudo. |

Galpão: **Pátio dos Armazéns**, baia de carga dos fundos do ColdStorage ("COLD STORAGE / 04"), Harbor
(164.5, 35.525), yaw 180° (portão voltado para a foundry_avenue). Movido em 01/11/2026: o ponto antigo
(124, 59.5) era o centro do drift "harbor_cold_storage". Conta da posição no comentário de
`PilotTapes.HIDEOUT_POINT` (fachada pintada "camara-fria", 16 m × 17,5 m, vão sem folha dos fundos com
centro em x local +2,0, parede em z=35,625). Fica a ~47 m do centro do drift (~39 m da borda do
círculo de 8,1 m); o teste exige >= 12 m de todos os pontos amostrados do círculo.

### Como as coordenadas foram conferidas (e o que não foi)

- Conferido no código: cada ponto sai de dados que existem (PlaceCatalog: exterior + porta do tipo
  `WALKUP_DOOR_Z` + 1 m de retorno; RoadsideLayout: centro, giro e raio do lugar). O teste exige 4/3/3,
  pontos finitos e nenhuma fita a menos de 30 m de outra ou de uma carta de Vicente (a primeira escolha,
  Quayside, ficava a 22 m da carta nº 2 e foi trocada por Westgate Garden).
- **Não conferido:** sem Godot nesta sessão, nada foi carregado no mundo. Não há prova de que cada ponto
  está fora de parede, de poste, de pedra decorativa do deserto ou de pista de trânsito. Antes de fechar o
  card, rodar uma passada a pé como `tests/test_vicente_letters.gd` (sessão real, teleporta, raio de chão,
  confere a coleta) e ajustar os pontos que falharem.

## Pendências

1. **Passada a pé no mundo real** (acima). Teste novo com sessão real, nos moldes de `test_vicente_letters.gd`.
2. **Galpão como lugar:** o portão agora encosta no vão sem folha dos fundos do ColdStorage (acima),
   fora do drift, e o aço dele é desenhado no `LateSurfacePrewarm` (roda em toda partida, Harbor
   incluído). **Não conferido no mundo** (sem Godot na sessão de 01/11): o portão (3,3 m) é mais baixo
   que o vão pintado (~72 % da parede), então sobra faixa escura do corredor acima dele; aberto, atrás
   dele está a colisão do prédio (não há interior). Conferir numa passada a pé que ele não fica atrás de
   poste/árvore da calçada da foundry_avenue e que o raio de chão (1,5 m para fora) acerta a calçada.
   A sonda de pipelines (GETECO_PIPELINE_PROBE) não foi rodada para provar que o aço não compila mais.
   Falta o interior com a exposição das 10 fitas e o troféu.
3. **Carro exclusivo:** a frota não tem esportivo com faróis escamoteáveis (o mais próximo é o comentário
   de farol "deitado no capô" em `tools/fleet_fixups/detail_fleet_lamps_20261029.gd`, sem mecanismo de
   abrir/fechar). O nitro existe só nos carros do deserto (`DesertTuning` slot "nitro", `DesertDrivetrain`).
   Entregar um carro de Harbor com nitro pede ligar esse drivetrain fora do deserto. Proposta: modelo novo
   com faróis animados (malha pré-aquecida), entregue no galpão com `nitro_street`, pelo mesmo padrão do
   Coyote do Vicente (`DesertWilds`: recibo + registro na garagem).
4. **Pista de saltos:** exige geometria nova (rampas, colisão, desafio de tempo). Não iniciada.
5. **Pistas visuais entre fitas:** a dica em texto já aparece no jogo (aviso e diário); falta a pista pela
   aparência que o plano pede.
