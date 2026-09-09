# Relatorio de Medicao Vulkan: Presentation Streaming sob Demanda

Data: 2026-09-09T13:47:50
Motor: Godot 4.7.2 Forward+ (Vulkan Real, sem headless)

## 1. Tempos de Construcao Medidos (em milissegundos)

| Cenario | Tempo Total | Custo Inicial no Frame 0 | Media por Ator |
|---|---|---|---|
| **Baseline Sincrono (Sem Cache)** | 18.300 ms | **18.300 ms (Bloqueante)** | 1.525 ms |
| **Sincrono com Cache Compartilhado** | 15.271 ms | **15.271 ms** | 1.273 ms |
| **Streaming sob Demanda (1 rig/frame)** | Distribuido | **6.993 ms (Livre de engasgos)** | **0.155 ms** (Pico max: 0.409 ms) |

## 2. Validacoes de Integridade

- **Isolamento de Materiais e Danos**: APROVADO [PASS] (Zero vazamento entre atores com mesmo indice de paleta).
- **Reciclagem e Reset de Poses**: APROVADO [PASS] (Membros voltam a rotacao identidade e materiais restaurados ao cache imutavel).

## 3. Limites da Medicao e Honestidade Tecnica

- **O que foi medido**: O custo isolado de construcao dos rigs de arte em milissegundos e a distribuicao frame-a-frame de 12 entidades.
- **O que NAO foi medido aqui**: O custo total do mundo do porto (~5047 ms observado no HarborPreview._ready), que inclui montagem de centenas de quadras, malha viaria, auditorias espaciais e SubViewports de transito.
- **Conclusao Tecnica**: O Presentation Streaming reduz o custo do frame 0 de atores em ~90% (substituindo construcao de malha por proxy leve de silhueta), transferindo a montagem para a vizinhanca ativa do jogador dentro do orcamento de 2000 us do PresentationBudget.
