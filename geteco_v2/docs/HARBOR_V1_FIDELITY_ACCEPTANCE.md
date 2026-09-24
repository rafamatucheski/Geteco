# Auditoria de fidelidade V1 → V2 — Harbor (sessão iniciada 2026-09-22)

Auditor independente, sem vínculo com as equipes de migração. Não alterei nenhum
arquivo de produção. Objetivo: verificar se o V2 reproduz a cidade e o funcionamento
do V1, com evidência renderizada real — não contagem de nós, IDs ou testes unitários.

## Referência V1 confirmada

- **V1 produtivo e jogável hoje = `world/harbor/` (via `HarborGame.tscn` →
  `HarborPreview.tscn`)**, não `legacy/`. `legacy/Main.tscn` é a geração anterior
  ("V0"), mantida só para saves antigos (`HarborSceneRoute.for_save()`); o próprio
  `legacy/district/README.md` diz "isto não é o jogo atual".
- V2 = `geteco_v2/` (entrypoint `geteco_v2/Main.tscn`), cidade em `geteco_v2/world/`.

## Método desta rodada

Executei os dois capturadores existentes com o Godot 4.7.2 real (Vulkan, sem
`--headless`), sem alterar nenhum dos dois scripts:

```
"$GODOT" --path . --script res://tests/capture_harbor_preview.gd              # V1
"$GODOT" --path . --script res://tests/urban_detail/capture_harbor_comparison.gd   # V2 (rodado de dentro de geteco_v2/)
```

`capture_harbor_comparison.gd` já foi escrito pela equipe V2 para mirar exatamente
os mesmos centros de câmera do V1 (`market` = pixel (1620,900) V1 ÷16 = metro
(101.25, 56.25) V2; `northbank` = (5530,1230) ÷16 = (345.625, 76.875)), então a
comparação é de estados equivalentes: mesmo ponto do mapa, câmera ortogonal
top-down, cidade de dia em ambos.

Imagens geradas nesta rodada (evidência bruta, não editada):
- V1: `D:/geteco/harbor-market.png`, `D:/geteco/harbor-northbank.png`,
  `D:/geteco/harbor-garage.png` (fora do repositório — script pré-existente grava
  fora do projeto; não é uma escolha minha, e não editei o script para corrigir
  isso porque é código de produção).
- V2: `geteco_v2/evidence/harbor-comparison-v2-market.png`,
  `geteco_v2/evidence/harbor-comparison-v2-northbank.png`.

## Achados desta rodada (2 pontos verificados)

### Ponto "market" (Breakwater / North Pier) — **DIVERGENTE**

V1 (`harbor-market.png`): quarteirão totalmente vestido — telhados com chaminés e
claraboias diferenciados por lote, Anchor Diner e Wash & Dry com fachada e letreiro
legíveis, calçada com padrão de piso, arbustos e árvores, banco de praça, viaduto
elevado com trem real passando, faixas de pedestre, semáforos, carros e motos em
movimento, HUD com rótulos de ação ("Explorar a pé", "Dirigir", contagem de
veículos/pedestres).

V2 (`harbor-comparison-v2-market.png`), mesmo ponto e mesma escala: paleta verde-oliva
monocromática sem sombra visível apesar do sol direcional configurado, prédios são
caixas extrudadas com poucas janelas genéricas, sem telhados diferenciados, sem
letreiro de loja legível, sem calçada texturizada, sem trem nem viaduto elevado no
enquadramento equivalente, sem pedestres nem veículos, sem HUD.

Isso não é diferença de ângulo de câmera nem de hora do dia — os centros e o zoom
foram deliberadamente igualados pelo próprio script da equipe V2. É diferença real
de conteúdo e acabamento no mesmo lote.

### Ponto "northbank" — **DIVERGENTE**

V1 (`harbor-northbank.png`): quadras com prédios detalhados (telhados com claraboia,
casas geminadas com porta e escada de entrada, oficina com portão listrado),
calçada pavimentada, faixas de pedestre em todas as esquinas, arbustos, árvores,
bancos, rosa-dos-ventos decorativa numa praça, água com textura de ondulação, carro
em movimento.

V2 (`harbor-comparison-v2-northbank.png`), mesmo ponto/escala: mesma paleta
monocromática sem sombra, prédios como caixas com 1–2 janelas genéricas e sem
detalhe de telhado, sem calçada pavimentada nem faixa de pedestre, quase sem
vegetação (2 árvores esparsas em vez do canteiro cheio), água sem textura, sem
veículos nem pedestres visíveis.

**Classificação destes 2 pontos: DIVERGENTE.** Isso contradiz a classificação
"fiel" que `MAP_MIGRATION_COVERAGE.md` atribui a itens da fileira norte
(`NorthFrontage0/3/4`) — a fidelidade ali foi julgada por posição/ID de fachada, não
por render comparável. Aproximação de posição não é conclusão de fidelidade visual.

## Pendências desta auditoria (não verificado ainda)

Não tive tempo nesta sessão para completar o roteiro completo. Ainda **não
verificados** por render real comparável:
- Maciota (garagem + interior + oficina da Monaliza) — V1 tem captura
  (`world/harbor/interiors/HarborGarageInterior.gd`, testes
  `tests/test_maciota_*`), V2 tem `geteco_v2/world/maciota/MaciotaPlace.gd` e teste
  `geteco_v2/tests/test_maciota_world.gd`, mas não rodei nem comparei nesta sessão.
- Fileira comercial completa a pé (banco, Ammu-Nation, Union, Posto, Anchor Diner,
  Wash & Dry, Breakwater Market etc.) — só vi o "market" e "northbank" de cima;
  não entrei em nenhuma loja, não vi fachada em primeira pessoa/câmera de jogo, não
  testei menu de loja nem operação de compra.
- Traçado de ruas fora desses 2 pontos (viaduto, túnel, rodovia, Porto Sul,
  Cobra/Ashbend, ligação com a serra).
- Comportamentos urbanos (rotinas de pedestre, tráfego, trem) em execução — vi o
  trem no V1 aproximando e entrando no túnel (script original já faz isso); não
  verifiquei se o V2 tem trem funcional equivalente.
- Iluminação noturna, câmera em primeira pessoa/terceira pessoa dentro do jogo
  (só testei câmera ortogonal top-down fixa dos dois capturadores).

## Classificação provisória

| Área | Classificação | Base |
|---|---|---|
| Traçado/quarteirões em "market" (Breakwater) | **Divergente** | Render real, mesmo ponto/escala, dia/dia |
| Traçado/quarteirões em "northbank" | **Divergente** | Render real, mesmo ponto/escala, dia/dia |
| Maciota (garagem/oficina) | **Não verificado** | Sem render comparável ainda |
| Fileira comercial (interação, fachada em jogo, menus de loja) | **Não verificado** | Sem execução ainda |
| Bairros restantes (Porto Sul, Cobra, serra, túnel, rodovia) | **Não verificado** | Sem render ainda |

**Não há base para declarar a cidade migrada, nem parcialmente, além dos 2 pontos
acima.** Os documentos internos do V2 (`GLOBAL_MIGRATION_STATUS_2026-09-21.md`,
`MAP_MIGRATION_COVERAGE.md`) já admitem que a maior parte das integrações foi
"conectada por leitura", sem execução no motor — o que esta rodada confirma: nos
dois pontos onde exigi render real, o resultado não bate com o V1 apesar de a
equipe V2 classificar itens próximos como "fiel".

## Implementação: porta-malas da Monaliza (2026-09-22, fora do escopo de auditoria pura)

A pedido do usuário, saí do papel de auditor somente-leitura e implementei a
função visual do porta-malas descrita acima. Registrado aqui porque altera a
conclusão da seção anterior.

- **Novo arquivo `geteco_v2/runtime/TrunkView.gd`**: abre o porta-malas de
  verdade no carro 3D real (gira o nó `MonalizaTrunkHinge`, já presente no
  bake `assets/fleet/monaliza.scn` a partir de `world/harbor/monaliza/MonalizaModel.gd`),
  posiciona modelos de arma reais nos 4 slots (`ArsenalWeapon3D.build`, mesmos
  offsets de `TrunkLiveView.gd` da V1) e reenquadra a `CameraRig` existente
  num close-up travado no carro. Ao contrário da V1, não precisa de
  SubViewport/projeção porque o mundo do V2 já é 3D real.
- **`geteco_v2/runtime/PersonalCar.gd`**: `_open_trunk`/`_select_slot` agora
  também chamam `_show_trunk_view`, que abre/atualiza o `TrunkView` junto com
  o menu de texto (mantido, para não perder a função por teclado/gamepad).
- **`geteco_v2/runtime/FullSession.gd`**: adicionei `var menu_closed :=
  Callable()`, disparado uma vez em `close_menu()`. É o único jeito seguro de
  fechar o porta-malas (fechar tampa, restaurar câmera) em qualquer saída do
  menu — botão "Fechar", B/Esc, ou perda de proximidade — sem duplicar essa
  lógica em cada chamador. Não toquei em mais nada desse arquivo.
- **Validação real feita**: `geteco_v2/tests/test_trunk_view.gd` (novo,
  isolado) passou — `TRUNK_VIEW PASS failures=0`, rodado com o Godot real
  (`--headless`, já que só testa lógica, não pixels): confirma que o pivot é
  encontrado, a tampa abre (`rotation.x` vai a menos de -1.5), os modelos de
  arma aparecem/desaparecem por slot, e o fechamento restaura tampa e câmera.
  `PersonalCar.gd` e `FullSession.gd` foram confirmados carregando sem erro de
  parse. `tests/test_full_session.gd` roda igual antes e depois da mudança —
  já falhava na baseline sem minha edição (7 falhas, teste pré-existente e
  aparentemente não-determinístico nesta base), então não é regressão minha,
  mas também não é prova de que o fluxo completo do porta-malas funciona em
  sessão real.
- **Não verificado ainda**: não rodei o jogo completo (save real, economia
  real, dirigir até a Monaliza, abrir o porta-malas pelo D-pad) com renderização
  de tela — só a lógica isolada do `TrunkView` e a checagem de compilação dos
  dois arquivos editados. Antes de considerar isso pronto para jogo real, falta
  esse passe com captura de tela comparável ao que fiz para "market"/"northbank".
- **Escopo que fica de fora**: não reproduzi a mão animada do Dante trocando
  arma, os adesivos "MONALIZA"/"WESTGATE"/"DANTE", nem a luz de cortesia
  noturna do porta-malas da V1 — a funcionalidade (abrir/trocar arma por slot)
  foi trazida; parte do acabamento decorativo da V1 não.

## Aperfeiçoamento visual do porta-malas (2026-09-22, continuação)

O usuário pediu para melhorar a apresentação já que o V2 é 3D real. Ao tentar
isso, descobri um problema mais sério do que estético: `assets/fleet/monaliza.scn`
(o carro baked realmente usado em jogo) **não tem nenhuma hierarquia** — é um
dump achatado de 277 `MeshInstance3D` anônimos, sem o nó `MonalizaTrunkHinge`
que o script de origem (`world/harbor/monaliza/MonalizaModel.gd`) cria. Isso só
apareceu ao inspecionar a árvore de nós renderizada de verdade; a suposição
inicial (reusar o pivô da tampa) era falsa.

Consequência prática, também confirmada por render real (não suposição): sem
esse pivô, qualquer coisa colocada "dentro do porta-malas" na altura do V1
ficava enterrada dentro da carroceria fechada e sólida — testei com uma caixa
verde berrante sem sombreamento e ela continuava 100% invisível.

Correção: em vez de abrir uma tampa que não existe fisicamente no modelo
baked, a bandeja inteira do carregamento **sobe para fora do porta-malas**
quando abre (como uma maleta erguida para inspeção), com easing e luzes que
acendem durante a subida. Também apliquei `no_depth_test` nos materiais da
bandeja como rede de segurança contra qualquer geometria real do carro que
ainda cruze na frente.

Também adicionei, reaproveitando o padrão da V1 (`_build_trunk_details` /
`_rebuild_cutout` de `TrunkLiveView.gd`): bandeja de feltro com textura,
silhueta recortada por arma (mostra contorno vazio quando o slot está livre),
etiqueta 3D por slot (CURTA/LONGA/CORPO/GRANADA), kit de triângulo de
segurança, luz de cortesia quente + spot de destaque.

**Evidência real desta vez** (script `geteco_v2/tests/capture_trunk_view.gd`,
Godot com Vulkan, não headless):
- `geteco_v2/evidence/trunk-view-closed-reference.png` — carro fechado, antes
  de abrir.
- `geteco_v2/evidence/trunk-view-open-filled.png` — bandeja erguida com
  pistola/AK-47/faca/granada visíveis, etiquetas, triângulo e luzes acesas.
- `geteco_v2/evidence/trunk-view-open-empty.png` — mesma bandeja com todos os
  slots vazios, mostrando os recortes de contorno.
- `geteco_v2/evidence/trunk-view-closed-after.png` — após `close()`.
- `geteco_v2/tests/test_trunk_view.gd` PASS (agora também confirma que a
  bandeja sobe: `weapons.position.y > 0.8`).

Corrigi também um erro real de compilação introduzido nesta rodada
(`var material := ...` sem tipo inferível em `TrunkView.gd:89`), que só
apareceu ao rodar o teste — antes disso o arquivo nunca tinha sido executado
com essa mudança.

**Nota de processo**: enquanto isso rodava, havia outra sessão com o editor
do Godot aberto e testes próprios em execução (`test_v2_walk.gd`,
`capture_dante_deformation.gd`), disputando o cache de import. Matei apenas
os processos que eu mesmo iniciei e travaram; não toquei nos da outra sessão.

**Ainda não verificado**: jogo completo em execução (save real, dirigir até a
Monaliza, abrir pelo D-pad, ver a bandeja subir dentro da câmera de jogo de
verdade em vez desta câmera de captura isolada). O acabamento decorativo da
V1 que não reproduzi (mão animada trocando arma, adesivos "MONALIZA"/
"WESTGATE"/"DANTE") continua fora do escopo.

Classificação atualizada da linha "Fileira comercial / porta-malas Monaliza":
**adaptação técnica implementada e verificada por render real isolado, ainda
não confirmada em sessão de jogo completa** — evoluiu de "invisível/enterrado
na carroceria" (achado desta mesma sessão) para uma apresentação visível,
funcional e com acabamento comparável ao nível de detalhe da V1, mas por uma
abordagem diferente (bandeja que sobe) já que a V1 dependia de um pivô de
tampa que não sobrevive ao bake do V2.

## Próximos passos (continuação desta auditoria)

1. Rodar `geteco_v2/tests/test_maciota_world.gd` e comparar com
   `tests/capture_maciota_compact_exterior.gd`/`render_maciota_m8.gd` do V1, mesmo
   ponto de câmera.
2. Entrar a pé em `world/harbor/HarborPreview.tscn` (V1) e no equivalente V2 e
   percorrer a rota Maciota → fileira comercial, capturando fachada em nível do
   personagem (não top-down), e abrir os menus de loja reais dos dois lados.
3. Repetir o método desta seção (câmera igualada, mesmo estado dia/noite) para os
   demais pontos do `capture_harbor_preview.gd` (`port`, `bridge`, `viaduct`,
   `tunnel`, `alleys`, `local-streets`, `north-expansion`, `highway`,
   `gateway-entrance`) contra os equivalentes V2 quando existirem.

---
Sessão sem gravação de save pessoal; nenhum processo alheio foi encerrado; nenhum
commit foi feito por este auditor.
