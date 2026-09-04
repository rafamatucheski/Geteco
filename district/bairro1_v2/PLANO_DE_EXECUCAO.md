# Bairro 1 V2 — plano de execução paralelo

## Decisão de arquitetura

Construir um novo distrito em `district/bairro1_v2/` sem apagar o Bairro 1 atual.
O porto existente permanece como uma âncora do distrito e continua vindo de
`missions/district_one/PortMarkedCarSet.tscn`.

Só depois que a V2 estiver jogável e aprovada ela substituirá a composição
atual em `DistrictOneComplete.tscn` e `Main.tscn`. A remoção do legado será
uma tarefa separada, posterior e revisável.

## Referência espacial obrigatória — V3

**A planta desenhada por Rafael é a referência visual e espacial do Bairro 1.**
As propostas conceituais anteriores do Codex não têm autoridade de layout.
Antes de retomar `layout/` ou `landmarks/`, ler:

- `design/PLANTA_RAF_V3.md`
- `design/DistrictV2RafaelPlan.gd`
- `design/BECOS_E_FUGA.md`

O Terminal é o spawn; porto/canal ficam ao norte; Garagem, Paint & Spray,
Cobra, cemitério/IML, favela e saída leste devem respeitar a planta V3. O trem
é apenas cenário (túnel sul + viaduto do cemitério/saída) e não cria colisão.

## Planta anterior — obsoleta

- Limites: canal/porto ao norte-leste, ferrovia ao sul, viaduto/rodovia ao
  leste, parque ao oeste.
- Circulação: uma avenida de entrada, um eixo comercial, quatro ruas locais,
  três becos e três atalhos para pedestres.
- Marcos: porto, mercado, terminal de ônibus, parque/quadras, oficina, bar,
  lavanderia, escola/centro comunitário, galpão e passagem ferroviária.
- Escopo inicial: 2–3 interiores úteis, 3 atividades e 10 pontos de rumor ou
  pista; os outros imóveis são fachadas até ganharem função.

## Donos e limites de edição

| Responsável | Pode criar/editar | Não deve editar |
| --- | --- | --- |
| Claude Code | `district/bairro1_v2/layout/` | raiz V2, landmarks, gameplay, `Main.tscn`, distrito legado |
| Antigravity | `district/bairro1_v2/landmarks/` | layout, gameplay, cenas-raiz e arquivos globais |
| Codex | `district/bairro1_v2/gameplay/`, `district/bairro1_v2/Bairro1V2.tscn`, integração e testes V2 | arquivos de propriedade exclusiva dos demais, salvo pedido explícito |
| Rafael | aprova marcos, narrativa, referências e prioridades | — |

**Regra:** em caso de necessidade de mudar um contrato entre módulos, registrar
primeiro neste arquivo ou abrir uma mensagem para o dono do módulo. Não editar
o arquivo dele diretamente.

## Contrato entre módulos

Cada módulo expõe uma cena instanciável e não conhece detalhes internos dos
outros módulos:

```text
Bairro1V2.tscn                         # integração, dono: Codex
├── LayoutV2.tscn                      # ruas, colisões e marcadores, Claude
├── LandmarksV2.tscn                   # prédios, props e visuais, Antigravity
├── GameplayV2.tscn                    # interações e pistas, Codex
├── PortMarkedCarSet.tscn              # porto preservado, existente
├── DistrictRailLine.tscn              # infraestrutura existente
└── District1HighwayExit.tscn          # infraestrutura existente
```

### Marcadores obrigatórios do layout

Claude entrega `Marker2D`s com estes nomes estáveis:

- `PlayerSpawn`
- `PortApproach`
- `MarketEntrance`
- `TerminalStop`
- `ParkEntrance`
- `GarageEntrance`
- `WarehouseEntrance`
- `RailUnderpass`
- `ExitDistrict2` e `ExitDistrict3`

Os marcos visuais e o gameplay posicionam conteúdo em relação a esses nomes,
nunca a coordenadas copiadas de outro módulo.

## Ações por IA

### Claude Code — malha e navegação

1. Criar `layout/LayoutV2.tscn` e `layout/LayoutV2.gd`.
2. Definir a área jogável e os limites físicos, preservando o acesso viário ao
   porto.
3. Implementar a hierarquia de vias: avenida, eixo comercial, ruas locais,
   becos, atalhos e passagem ferroviária.
4. Criar colisores, calçadas e rotas compatíveis com o sistema existente de
   tráfego e pedestres.
5. Publicar os marcadores obrigatórios e os dois pontos de saída futura.
6. Entregar uma captura de debug e uma breve lista de IDs/rotas de rua.

**Aceite:** jogador, carro, pedestres e tráfego atravessam o distrito sem
teleporte, bloqueio ou colisão atravessável; porto, ferrovia e duas saídas são
alcançáveis.

### Antigravity — identidade, marcos e variação urbana

1. Criar `landmarks/LandmarksV2.tscn` e `landmarks/LandmarksV2.gd`.
2. Montar um kit modular de fachada, telhado, muro, poste, vegetação e props
   reutilizáveis; evitar prédios copiados sem variação.
3. Criar os marcos únicos: mercado, terminal, parque/quadras, oficina, bar,
   lavanderia, escola/centro comunitário e galpão.
4. Preencher os becos com leitura clara: mural, escada oculta, área de carga e
   pontos de observação.
5. Posicionar os marcos usando apenas os marcadores definidos pelo layout.
6. Garantir que visuais não criem colisões novas sem sinalizar Claude.

**Aceite:** o jogador consegue reconhecer cada marco a distância, nenhuma
fachada bloqueia ruas/calçadas e o bairro tem rotas visuais distintas de dia e
à noite.

### Codex — integração, atividades, pistas e qualidade

1. Criar a cena-raiz `Bairro1V2.tscn` e instanciar layout, landmarks,
   gameplay, porto, ferrovia e viaduto sem tocar na cena atual.
2. Criar `gameplay/GameplayV2.tscn`, os três primeiros loops de atividade e
   os dez pontos de rumor/pista.
3. Ligar NPCs, tráfego, entradas e limites de progressão aos marcadores
   públicos do layout.
4. Fazer adaptadores mínimos para os sistemas atuais de estrada, população,
   missões e restrição de distrito.
5. Criar testes V2 de boot, porto, acessibilidade, tráfego e marcadores.
6. Integrar na cena principal somente após aceite de Rafael.

**Aceite:** novo jogo inicia na V2; três atividades funcionam; as dez pistas
podem ser encontradas; porto continua presente; testes básicos passam.

## Ordem de trabalho

### Marco 0 — congelamento seguro

- Ninguém remove arquivos legados.
- Cada IA trabalha somente na sua pasta nova.
- Codex mantém este plano e resolve contratos de integração.

### Marco 1 — distrito cinza jogável

- Claude entrega layout navegável e marcadores.
- Codex conecta-o em uma cena de preview e valida o acesso ao porto.
- Rafael aprova escala, ritmo das ruas e posição dos marcos antes de arte.

### Marco 2 — bairro reconhecível

- Antigravity entrega landmarks e kit de variação.
- Codex integra população, luz, atividades e pistas.
- Rafael avalia personalidade, densidade e legibilidade.

### Marco 3 — vertical slice

- Uma sequência completa: spawn → mercado → beco → oficina/galpão → porto.
- Tráfego, pedestres, colisão, ferrovia e retorno ao jogo são validados.

### Marco 4 — substituição

- Codex apresenta comparação V1/V2 e resultados dos testes.
- Rafael aprova a troca.
- Só então a cena principal passa a usar V2. O legado permanece até uma
  validação final; apagar é uma tarefa posterior, isolada e confirmada.

## Comunicação curta obrigatória

Ao encerrar cada entrega, cada IA publica:

1. arquivos criados/alterados;
2. contrato ou marcador novo/alterado;
3. como testar;
4. bloqueio concreto, se houver.

Isso evita conflitos silenciosos e permite integrar em pequenas mudanças.
