# Contrato de persistência das operações urbanas V1

O consumidor central grava este payload em `world_state.urban_operations`. Este
módulo não altera o schema central e aceita somente a versão 1 descrita abaixo.

## Envelope

```text
{
  version: 1,
  port: PortSnapshotV1,
  cemetery: CemeterySnapshotV1
}
```

Se a chave `urban_operations` não existir, a sessão inicia os dois serviços com
estado novo. Se existir e for inválida, `restore_snapshot` retorna `false`; cabe
ao consumidor central aplicar sua política de save inválido. Versões desconhecidas
não são migradas implicitamente.

## `PortSnapshotV1`

```text
{
  version: 1,
  boats: [BoatV1, BoatV1]
}

BoatV1 = {
  id: "south_port_launch_00" | "south_port_launch_01",
  load: inteiro 0..30,
  phase: "loading" | "departing" | "away" | "returning",
  clock: número finito 0..600,
  position: [x, y, z],
  worker: WorkerV1 | {}
}
```

Os dois IDs são obrigatórios e únicos. Cada coordenada deve ser finita e ter
módulo máximo de 100000. `worker: {}` só é válido para uma lancha em `loading`
com `load == 0`; a ativação local reconstrói o carregador inicial.

```text
WorkerV1 = {
  position: [x, y, z],
  velocity: [x, y, z],
  destination: [x, y, z],
  route_index: inteiro 0..10000000,
  carrying: bool,
  crate_stock: [inteiro 0..30, inteiro 0..30],
  deliveries: inteiro 0..10000000,
  source_index: 0 | 1,
  activity: string de até 32 caracteres,
  activity_left: número finito 0..100000,
  travel_left: número finito 0..100000,
  routine_cycle: inteiro 0..10000000,
  dialogue_index: inteiro 0..10000000,
  rng_state: inteiro
}
```

Conservação obrigatória:

- em `loading`: `load + stock[0] + stock[1] + int(carrying) == 30`;
- nas demais fases: `stock[0] + stock[1] + int(carrying) == 3`.

Os carregadores são anexos de runtime. Restore e afastamento substituem ou
suspendem esses anexos; eles nunca são donos do save.

## `CemeterySnapshotV1`

```text
{
  version: 1,
  serial: inteiro 0..10000000,
  secret_known: bool,
  storyteller_stop: inteiro 0..3,
  cases: [CaseV1], // máximo 64
  deaths: [string] // opcional em saves antigos; máximo 386, sem repetição
}

CaseV1 = {
  identity: string única, não vazia, até 128 caracteres,
  name: string de até 96 caracteres,
  phase: "morgue" | "buried" | "unrecovered",
  plot: inteiro -1..11
}
```

Lotes não negativos são únicos. Um caso `buried` exige lote reservado. O mesmo
lote continua pertencendo à identidade durante interrupção e retorno.

### Normalização e migração

Antes de gravar, fases ligadas a anexos não persistentes são normalizadas:

- `collection` e `burial` viram `morgue`, para retomada idempotente;
- `discovered` e `dispatched` viram `unrecovered`, pois o incidente de emergência
  não pertence a este snapshot;
- `morgue`, `buried` e `unrecovered` permanecem iguais.

Agente funerário, carro funerário, visitantes, zelador, contador de histórias,
links de incidentes e áudio não são serializados. Restore encerra os anexos
existentes, reconstrói sepulturas a partir do ledger e, se o local estiver ativo,
retoma no máximo um funeral.

`deaths` preserva as mortes de `keeper`, `storyteller` e participantes identificados
por `<case identity>:cemetery_mortician` ou `<case identity>:cemetery_mourner_00..04`.
IDs de participantes exigem um caso existente. Campo ausente significa nenhuma
morte registrada, preservando saves V1 antigos. Visitantes mortos não reaparecem
na retomada; a morte do agente interrompe o serviço daquele caso, que permanece
na fila do necrotério sem ressuscitar o funcionário. Moradores mortos não são
recriados pela entrada na casa, pelo streaming ou pela restauração do save.

A chegada do funeral aguarda o portão e o carro ficarem fora da câmera; a saída
aguarda todos os sobreviventes completarem o percurso e saírem da câmera.
Violência interrompe a cerimônia sem registrar um sepultamento não concluído.

Snapshots V1 antigos ou sintéticos com `serial` abaixo de uma identidade já
ocupada continuam aceitos. O alocador avança até um `harbor_deceased:%08d` livre,
impedindo que duas mortes compartilhem a mesma identidade sem exigir versão nova.

O módulo não grava recompensa nem altera economia. A conversa do zelador persiste
somente `secret_known`; recompensas/colecionáveis continuam sob seus donos centrais.
