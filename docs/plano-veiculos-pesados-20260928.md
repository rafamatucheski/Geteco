# Veículos pesados — detalhamento (28/09/2026)

Pedido do usuário: "caminhões e empilhadeiras precisam de mais detalhe, estão POBRES
demais". Antes/depois: `evidence/fleet-models/pesados_antes.png` e `pesados_depois.png`.

## Feito em 28/09 — etapa 1: acabamento

`runtime/HeavyVehicleDetail.gd`, chamado por `FleetCatalog.create` (mesmo padrão do
`PoliceTransportModel.decorate`). Uma malha por modelo, montada uma vez e em cache,
material de cor por vértice (`CityPropKit.material()`): **+1 draw call por veículo
pesado**, sem colisão, sem luz, nada preso às rodas nem ao carro de garfos.

Por que não nos `.scn`: os `.scn` da frota têm mudanças não commitadas de outra sessão
e `tools/fleet_fixups` pula modelos já na versão atual (subir a versão reaplicaria as
correções antigas e duplicaria peças).

| Modelo | O que ganhou |
|---|---|
| `port_forklift` | correntes com elos e roldanas no mastro, cilindros de elevação e de inclinação, mangueiras, cilindro de GLP com cintas e válvula, zebrado amarelo/preto e lanternas no contrapeso, pino de reboque, estribos, faixa lateral, alças, painel com mostrador, retrovisores |
| `cargo_flatbed_truck`, `american_dump_truck`, `american_tanker_truck` (cabine comum) | retrovisores West Coast com espelho convexo, frisos e maçanetas de porta, aletas no capô, para-sol, buzinas a ar, moldura cromada da grade, ornamento, ganchos de reboque, neblina, caixa de bateria; traseira com para-choque anti-encaixe refletivo, para-barros, lanternas e placa |
| plataforma | catracas com cinta, faixa refletiva, caixas de ferramenta, grade na proteção da cabine, correntes |
| basculante | faixa refletiva, escada, cilindro basculante, trava da tampa, lona enrolada |
| tanque | bocas de visita, guarda-corpo da passarela, porta-mangueiras, losangos de risco, válvulas de descarga |
| `boxrunner` | retrovisores, portas, grade e para-choque, faixa de marca, luzes de posição, dobradiças e travas das portas traseiras, degrau |
| `towmaster` | retrovisores, portas, comandos da plataforma, estrobos, corrente de segurança, calços, cabo do guincho, grade |

## Problema encontrado (não é deste trabalho)

Os `.scn` da frota foram regravados em 28/09 às 09:00 por outra sessão. No
`cargo_flatbed_truck.scn` atual a cabine está quebrada (painéis vermelhos do capô e
do teto em pé), visível no modelo puro, sem o kit:
`evidence/fleet-models/puro_cargo_flatbed_truck_fl.png`. O `.scn` do último commit
está salvo em `evidence/fleet-models/head_cargo_flatbed_truck.scn` para comparação.
Confirmar com o usuário/sessão responsável antes de mexer.

## Próximas etapas

2. **Luzes à noite**: marcadores âmbar, lanternas e zebrado com emissivo pelo
   material de neon/lâmpada da cidade (acende com `CityLookMaterials.set_night`).
3. **Carga visível**: plataforma com madeira/aço amarrado quando o frete não usar a
   carga de gameplay (`PortFreightDelivery`/`PortCargoOperations` já colocam carga —
   não duplicar); basculante com brita.
4. **Sujeira e desgaste**: faixas de barro nas rodas e para-barros, ferrugem na
   caçamba.
5. **Outros pesados**: `snow_plow_truck`, `dock_delivery_van`, `rescue_pumper`,
   `medic_box`, `route_city` (ônibus) no mesmo kit.
6. Medir custo na Main renderizada com tráfego industrial (p50/p95/p99 em ms).
