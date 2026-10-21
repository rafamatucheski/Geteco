# Proposta: dublar o resto do jogo (PT-BR e inglês)

Decisão de 21/10: **ElevenLabs só para o elenco central** — Dante, Maciota (inclusive a voz ao
telefone), Helena, Takeshi e Vicente —, porque as falas deles são longas e precisam de contexto e
emoção. **Todos os outros** (NPCs da rua, mendigos, civis, guardas, aleatórios e o resto do elenco)
usam o banco local Qwen. Acompanhamento no painel "Dublagem Geteco"; lista completa em
[elevenlabs-falas-restantes.md](elevenlabs-falas-restantes.md). Os números abaixo saem de
`tools/build_voice_dashboard_data.py`.

## Situação em 21/10 (lote A/B gerado e instalado)

| Personagem | Voz PT-BR | Voz inglês | PT-BR | Inglês |
|---|---|---|---|---|
| Dante | Otto | Otto | 66/66 | 66/66 |
| Maciota (e voz ao telefone) | Lucas | Mason | 47/47 | 47/47 |
| Helena (bancária) | Juliana Gheno | Juliana Gheno | 2/2 | 2/2 |
| Takeshi | Kei (sotaque japonês, pedido do usuário) | Kei | 7/7 | 7/7 |
| Vicente | Dantas | Dantas | 6/6 | 6/6 |

Elenco ElevenLabs completo nos dois idiomas (inglês do Maciota gerado com o Mason, ~6.300 créditos).

## ElevenLabs (estimativa original)

| Lote | Quem | Falas | Falta PT-BR | Falta inglês | Créditos estimados |
|---|---|---:|---:|---:|---:|
| A | Dante e Maciota (com a voz ao telefone) | 113 | 60 | 113 | ~13.400 |
| B | Helena, Takeshi e Vicente | 19 | 19 | 19 | ~3.400 |
| **Total** | | **132** | **79** | **132** | **~16.800** |

Estimativa: 1 crédito por caractere mais ~10 por fala de indicação de emoção. Com 30 mil créditos
por mês (confirmar no painel da ElevenLabs) e ~7.800 já gastos, cabe no plano atual, uma geração
por fala. Refazer uma fala custa de novo.

- **Helena, Takeshi e Vicente precisam de voz.** Eu proponho uma voz da biblioteca para cada um pelo
  perfil de `data/dialogue/voice-cast.json`; você ouve a amostra grátis e aprova antes de gastar.
- **Inglês com a mesma voz.** O v4 fala inglês com a mesma voz, o que mantém o elenco igual nos
  dois idiomas. Teste primeiro com 2 falas (~100 créditos) para ver se o sotaque fica aceitável;
  se não ficar, escolhemos vozes americanas parecidas.

## Banco local Qwen (sem créditos, tempo de GPU)

433 falas de 84 personagens. Faltam **374 gravações em PT-BR e 377 em inglês**: hoje elas não têm
áudio nenhum. Geram com o fluxo já documentado em `docs/directed-voice-production.md`
(`tools/build_voice_bank.py render` e `publish`), em lotes retomáveis, no tempo livre da GPU.
As reações aleatórias (civis, guardas, dor) podem ganhar 2 ou 3 tons cada no mesmo fluxo.

## Ordem sugerida

1. Teste de inglês com Dante e Maciota (~100 créditos).
2. Lote A completo: PT-BR restante e inglês.
3. Escolher e aprovar as vozes de Helena, Takeshi e Vicente; lote B.
4. Em paralelo, quando a GPU estiver livre: lotes do Qwen para quem não tem áudio, começando
   pelas falas principais (Jessica, Raul, Ferrugem, Neco e o resto do elenco das missões).

Depois de cada lote: instalar no jogo, rodar os testes de voz, gerar de novo os dados do painel.
