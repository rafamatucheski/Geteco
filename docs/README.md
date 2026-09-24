# Documentação do Geteco

Índice por tema. Os documentos foram escritos durante a migração da V1 para o 3D nativo
(setembro de 2026); cada um registra decisões, medições e limites de uma área. Quando um
documento cita `geteco_v2/`, leia como a raiz atual do repositório.

## Padrões obrigatórios

- [Padrão de interiores — Chalé + Maciota](interior-standard.md) e [checklist](interior-standard-checklist.md)
- [Contrato de colisão e profundidade de interiores](interior-physics-and-depth.md)
- [Skill de interiores (cópia versionada)](skills/padrao-interiores/SKILL.md)
- [Prontidão de exportação para Windows](EXPORT_READINESS.md)

## Mundo

- [Mundo e regiões](world-migration.md) · [Cobertura do mapa](MAP_MIGRATION_COVERAGE.md)
- [Relevo da serra](mountain-terrain-migration.md) · [Vegetação e rochas](terrain-dressing-migration.md)
- [Oceano do Harbor](harbor-ocean.md) · [Proteções costeiras](coastal-protection.md)
- [Atmosfera regional](regional-atmosphere-migration.md) ([revisão visual](regional-atmosphere-review.html))
- [Água e frio](water-cold-migration.md) · [Fontes de calor](heat-streaming-integration.md)
- [Visual "cidade de jogo"](CITY_LOOK_2026-09-22.md) · [Modelos e mecanismos do cenário](SCENARIO_MODELS_MIGRATION.md)
- [Santa Mare: doca e porão](SANTA_MARE_3D_CHECKLIST.md) · [Apresentação urbana](urban-transit-presentation.md)
- [Integração de arquitetura urbana e despacho](INTEGRATION_NATIVE_MODULES.md)

## Jogabilidade

- [Combate e emergências](gameplay-migration.md) · [Paridade de combate](combat-parity-v1.md) · [Apresentação de combate](combat-presentation-migration-2026-09-21.md)
- [Física de rua](STREET_PHYSICS_2026-09-22.md) · [Reações civis](civilian-reactions-v1.md) · [NPCs e rotinas](NPC_ROUTINES_MIGRATION.md)
- [Chegada](arrival-migration.md) · [Maciota](maciota-migration.md) · [Garagens e recompensa Cobra](garage-reward-migration.md)
- [Serviços](services-migration.md) · [Banco e posto](robbery-migration.md) · [Entrega na prensa do Neco](neco-delivery-integration.md)
- [Pintura dos veículos](vehicle-paint-migration.md) · [Som e ambiência](AUDIO_AMBIENCE_MIGRATION.md)

## Campanha, progressão e save

- [Campanha, economia e persistência](campaign-migration.md) · [Progressão](progression-migration.md)
- [Revisão dos contratos de save e progressão](SAVE_PROGRESSION_CONTRACT_REVIEW_2026-09-21.md)

## Revisões e auditorias

- [Aceitação do Harbor](HARBOR_GAMEPLAY_ACCEPTANCE.md) · [Fidelidade Harbor V1 → V2](HARBOR_V1_FIDELITY_ACCEPTANCE.md)
- [Operações urbanas do Harbor](HARBOR_URBAN_OPERATIONS_2026-09-21.md) · [Cidade 3D do Harbor](HARBOR_V1_CITY_3D_MIGRATION_2026-09-22.md)
- [Auditoria de paridade V1 → V2](MIGRATION_PARITY_AUDIT.md)
- [Glitches de iluminação](LIGHTING_GLITCH_REVIEW.md) · [Calçadas](SIDEWALK_GLITCH_REVIEW_2026-09-22.md) · [Revisão dos 28 interiores](interior-visual-review.md)
- [Revisões externas](reviews/)

## Histórico

[historico/](historico/) guarda o que serviu para coordenar a migração e não descreve mais
o estado atual: panoramas datados, handoffs entre sessões, caixas de entrada de
relatórios, prompts entre agentes e os registros da primeira base.
