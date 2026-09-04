# Bairro 1 V2 — planta técnica de aprovação

Esta é a fonte única de verdade espacial do bairro. Ela substitui o uso de
offsets livres a partir de `Marker2D`. A imagem de conceito permanece a meta
visual: bairro compacto, densidade urbana, parque a oeste, comércio no centro,
indústria ao leste/sudeste e porto como destino.

## Resultado que a planta exige

- Nenhum prédio, prop sólido ou letreiro solto ocupa rua, faixa, calçada,
  cruzamento, ferrovia, acesso ao porto ou área verde jogável.
- Não existem gramados vazios gigantes: cada vazio é parque, praça, pátio,
  quintal, estacionamento ou área industrial com propósito.
- Mercado e terminal são fachadas do eixo comercial; oficina e galpão são
  fachadas da rua industrial; parque fica a oeste; bar/lavanderia recebe o
  jogador próximo ao spawn.
- A rota inicial é sempre possível: spawn → mercado → oficina → galpão → porto.

## Autoridade e uso

`DistrictV2MasterPlan.gd` é o contrato executável. As coordenadas são locais ao
`LayoutV2`, cujo encaixe físico com o porto continua sendo responsabilidade da
raiz `Bairro1V2`.

| Agente | Pode fazer a seguir | Não pode fazer |
| --- | --- | --- |
| Claude | reconstruir `LayoutV2` usando `get_road_spines()`, lotes e zonas proibidas | mover entradas/lotes sem revisão do contrato |
| Antigravity | reconstruir landmarks dentro de `BUILDABLE_LOTS` | usar fallback ou offsets livres, criar props sólidos fora do lote |
| Codex | validar colisões, rota, camadas e captura visual | aceitar integração sem os gates abaixo |

## Gates obrigatórios

1. **Layout limpo:** captura com asfalto, calçada, lotes e parque; sem prédios,
   setas, linhas ciano, nós, rótulos técnicos ou debug.
2. **Ocupação correta:** cada footprint de landmark está contido em seu lote e
   não cruza a superfície de qualquer rua.
3. **Imagem legível:** captura em visão superior mostra quarteirões compactos,
   parque, núcleo comercial e zona industrial, sem grandes vazios sem função.
4. **Gameplay:** jogador percorre a rota inicial sem colisão bloqueante.

Enquanto os quatro gates não passarem, `Main.tscn` não é alterado e o distrito
legado não é removido.
