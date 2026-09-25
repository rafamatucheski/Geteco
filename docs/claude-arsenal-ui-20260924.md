# Ammu-Nation: catálogo e personalização — frente do Claude (24/09/2026)

Itens do relatório do vídeo: **30** (descrição/estado do acessório), **32** (contraste) e
**33** (preço x posse). Sem commit; para o Codex integrar.

## Problemas confirmados no código atual (antes de editar)

- **30** — `HarborWeaponWorkbench.select_candidate` anexava a descrição pelo **slot**
  (`slot == "muzzle"` → texto do silenciador), não pela opção. Com "Original / Sem
  acessório" selecionado o texto falava de silenciador e o botão dizia só "INSTALADO",
  sem distinguir o que está instalado do que está em prévia.
- **32** — as abas inativas recebiam `modulate = #8faaa3`, que escurece texto *e* fundo;
  botões usavam o tema padrão (desabilitado quase invisível); prévia 3D transparente sobre
  painel `#182323`, onde armas escuras somem.
- **33** — o título sempre mostrava o preço da tabela (`$0` para a pistola, `$1200` para a
  MP5) mesmo com a arma já possuída.

## O que mudou

`runtime/HarborWeaponWorkbench.gd`
- `PART_NOTES`: a descrição é da **peça selecionada** (silenciador, lasers, luneta);
  "Original" não herda texto de nenhuma peça.
- Nova linha `status`: `Prévia: X — instalado agora` ou
  `Prévia: X • Instalado agora: Y • custo $N / sem custo / faltam $N`.
- Lista de opções marca `• INSTALADO` na peça instalada (inclusive "Original"),
  `• ADQUIRIDO` e `• $N` nas demais.
- Botão de ação: `JÁ INSTALADO` (desabilitado), `REMOVER <PEÇA>`,
  `INSTALAR (JÁ ADQUIRIDO)`, `COMPRAR E INSTALAR • $N`, `SALDO INSUFICIENTE • $N`
  (desabilitado). Resultado da aplicação vai para a linha de status.
- `style_button()` / `stage_style()` estáticos (usados também pelo catálogo): estados
  normal/hover/foco/pressionado/desabilitado com texto legível; fundo 2D claro
  (`#6f8580`) atrás da prévia 3D. Custo de render: apenas um `StyleBoxFlat` 2D — nenhum
  nó 3D, luz ou passe novo.
- Foco de teclado entra na opção instalada ao abrir a bancada.

`runtime/HarborAmmunationCatalog.gd`
- `price_status()`: título mostra `JÁ POSSUI` para arma possuída, `PROTEÇÃO COMPLETA`
  para colete cheio, `ITEM INICIAL • $0` para a pistola não possuída (preço zero é dado do
  catálogo, **não** foi alterado) e `$N` nos demais.
- Botão de compra: `JÁ POSSUI` / `BLOQUEADA` / `SALDO INSUFICIENTE • $N` /
  `COMPRAR • $N`; o Vance informa `Faltam $N para esta compra.`
- Abas são `toggle_mode` com estado pressionado no lugar de `modulate`; todos os botões
  usam o estilo comum; bancada "PERSONALIZAR ARMA" ganhou estilo de foco/desabilitado.
- Fundo claro atrás da prévia 3D; título e feedback com cor explícita.
- Ao voltar da bancada o foco vai para "PERSONALIZAR ARMA".
- Variável local `price` do bloco de munição renomeada para `ammo_cost` (colidia).

Preços, saldo, inventário e regras econômicas **não** foram alterados.

## Arquivos alterados / criados

- `runtime/HarborAmmunationCatalog.gd`
- `runtime/HarborWeaponWorkbench.gd`
- `tests/test_claude_arsenal_ui_state.gd` (novo)
- `docs/claude-arsenal-ui-20260924.md` (este)

## Testes executados

Rodados em `--headless` (validam comportamento/estado, **não** visual nem FPS), com o
editor e um jogo do usuário abertos pelo editor — nenhuma medição de outra sessão ativa.

1. `tests/test_claude_arsenal_ui_state.gd -- --no-save --skip-arrival` →
   **PASS 25/25**, exit 0. Sessão real (`Main.tscn`), economia e `Gameplay` de produção:
   pistola não possuída/possuída, MP5 possuída sem preço de tabela, compra com saldo curto
   (rótulo, "faltam", saldo e inventário intactos), aba por clique marca só a aba certa,
   setas ←/→, bancada: "Original" instalado sem texto de silenciador, prévia do
   silenciador com instalado visível, bloqueio por saldo sem débito, compra debita $650
   uma vez, lista marca a peça instalada, prévia "Original" oferece remoção gratuita,
   ESC bancada → catálogo, ESC catálogo → `close_requested`.
   - Na primeira execução a asserção de saldo falhou (1000 → 450, esperado 350). O recibo
     mostrou débito correto de $650; a diferença é a conquista `reward:achievement:armed_up`
     (+$100) liberada pela primeira peça. A asserção passou a somar recompensas novas e
     exigir recibo de exatamente $650.
2. `tests/test_harbor_establishments.gd -- --no-save --skip-arrival` → **exit 1, 64/65**.
   Todas as verificações da Ammu-Nation passam (catálogo, `COMPRAR • $0` da pistola,
   escopeta $1800, reposição, bancada, acabamento, ESC). A falha é
   `entrada concluída: harbor_clothing | timeout_frames=180` — entrada da loja de roupas,
   fora destes arquivos; não investiguei nem confirmei se já falhava antes (a árvore tem
   mudanças não commitadas de outras sessões em entradas/transições).

Não executados: suíte mínima estrutural do `CLAUDE.md` (a mudança não é estrutural) e
`run_suite.ps1`.

## Não verificado / pendências

- **Sem capturas renderizadas.** O jogo do usuário estava aberto pelo editor; abrir outra
  janela disputaria GPU e a tela. Para gerar, com janela exclusiva:
  `"$GODOT" --path . --script res://tests/test_claude_arsenal_ui_state.gd -- --no-save --skip-arrival --capture`
  → `evidence/claude-arsenal-ui-20260924/*.png` (4 telas). O contraste (item 32) só é
  aprovado olhando essas capturas ou o jogo; os valores de cor não foram medidos.
- Largura dos novos rótulos (`SALDO INSUFICIENTE • $1800`, linha de status da bancada)
  não foi conferida renderizada; o status usa quebra de linha automática.
- Navegação por controle/`ui_up`/`ui_down` entre botões depende do foco padrão do Godot;
  só as setas ←/→ e ESC têm teste.
- Falha `harbor_clothing` no teste de estabelecimentos é da frente de acessos (Codex).
- Nenhuma integração fora dos dois arquivos reservados é necessária.

---

# Parte 2 — sistema de personalização refeito (pedido do usuário, 24/09 noite)

Pedido: as customizações eram "toscas" e a pintura de fuzil ia para a faca. Por pedido
direto do usuário, esta parte saiu dos dois arquivos reservados e alterou
`gameplay/WeaponCustomization.gd` e `gameplay/WeaponAttachmentVisuals.gd` (sem mudanças
de outras sessões no momento da edição). `Gameplay.gd` **não** foi tocado.

## Desenho

- Cada peça declara as armas em que cabe (`for`) e o efeito (`mul`/`add`/`set`/`special`)
  sobre os mesmos campos que o combate já lê de `weapon_data()`: dano, `fire_interval`,
  `max_range`/`melee_range`, `falloff_start`, `min_damage_ratio`, `spread`, `pellets`,
  `magazine_size`, `projectile_speed`, `reload_multiplier`, `recoil_multiplier`, cor do
  tracejante. Nenhum ramo novo no combate.
- Armas de fogo ganharam as abas CANO, MUNIÇÃO e GATILHO. Novas peças: compensador,
  choke apertado e bico-de-pato (escopetas), cano longo e cano curto, tambor de 75,
  engate rápido, speedloader, ponta oca, perfurante, carga +P, balote (escopeta vira
  projétil único), chumbo grosso 00, munição de competição, gatilho de competição,
  ferrolho aliviado, bomba polida, empunhadura angular e acabamento em ouro. O
  lança-chamas tem abas próprias: BICO (concentrado/leque) e TANQUE (tanque duplo).
- Armas brancas têm abas próprias e **não aceitam mais** acabamento, laser ou bocal de arma de fogo:
  - faca: LÂMINA (serrilha, tanto, balanceada), CABO (paracord, guarda-soqueira),
    acabamento (óxido negro, aço espelhado);
  - taco: CABEÇA (pregos, arame farpado, alumínio), CABO (fita, cabo estendido),
    acabamento (verniz, pintura de time, queimado);
  - machado: LÂMINA (cabeça de bombeiro, fio amolado), CABO (fibra, estendido),
    acabamento (vermelho bombeiro, aço negro);
  - soqueira: PUNHO (espigões, aço temperado, liga leve), PALMA (acolchoada, lâmina de
    empurrar), acabamento (cromo negro, prata escovada).
- Acabamentos e peças de arma branca recolorem só o material certo (madeira do taco, aço
  da lâmina, latão da soqueira), por superfície.
- Bancada: cada opção mostra o efeito ao lado ("+35% dano, −5% cadência"). O painel
  compara os números atuais com a prévia ("Dano 25 → 31 ▲ • Golpes/s 2.3 → 2.2 ▼ …") e
  exibe a nota da peça. Lista rolável.
- Mantidos ids, preços e efeitos das peças já existentes (`suppressor`, `extended` 12→18,
  lasers, `matte`, `scope_2x`...). Mudanças: os lasers agora também reduzem a dispersão e
  atrasam a queda de dano; o silenciador tira 8% de dano e 10% de alcance.

## Riscos / integração pendente

- **Saves antigos:** peças que deixaram de caber (pintura de fuzil em arma branca,
  silenciador em escopeta) são descartadas pelo `normalize`, **sem reembolso**.
- `FullSession.gd:1131` lê `automatic` do catálogo cru, não de `weapon_data()`. Por isso
  não criei kit full-auto. Para existir, a linha precisa usar `world.gameplay.weapon_data(id)`.
- `Gameplay.gd:455` só desloca a boca (flash/tracejante) para o silenciador. Com cano longo,
  o flash sai ~7,5 cm atrás da ponta. Integração sugerida: somar
  `WeaponAttachmentVisuals.LONG_BARREL` quando `barrel == "barrel_long"`.
- As posições das peças 3D novas foram medidas no código dos modelos, **não vistas
  renderizadas**. Precisam de revisão visual.

## Testes (headless: comportamento, não aparência)

- `tests/test_claude_arsenal_ui_parts.gd` (novo): **PASS**, 172 combinações arma×peça,
  774 checks. Toda peça funcional altera o combate, mantém números válidos, sobrevive ao
  `normalize` e gera visual sem erro; arma branca recusa peça de fogo; valores
  específicos (serrilha 25→31, balote 1×46, tambor 75, ampliado 12→18). A primeira
  execução achou dois defeitos reais: laser sem efeito em pistola/revólver (dispersão base 0)
  e soqueira com só duas abas. Os dois foram corrigidos.
- `test_claude_arsenal_ui_state.gd`: PASS 25/25.
- `test_harbor_establishments.gd`: **PASS 77/77** (inclui bancada real e acabamento).
- `test_gameplay.gd`: **exit 1**. Os checks de peças passam, mas 18 checks de `fire_at`
  falham para **todas** as armas, inclusive punhos, granada e RPG, que não passam pela
  customização. Com customização vazia, `effective_data` produz os mesmos valores de antes,
  mas não provei que a falha já existia antes desta mudança.
- Não executado: `test_civilian_reactions.gd` (exige janela real; o jogo do usuário estava
  aberto) e capturas renderizadas.
