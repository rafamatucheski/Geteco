# Proposta: dublar o resto do jogo na ElevenLabs (PT-BR e inglês)

Situação em 20/10: 51 falas de missão do Dante e do Maciota em PT-BR, mais 7 tons de duas falas
aleatórias (dor do Dante e cumprimento do Maciota), instaladas por cima do banco local
(`audio/mission_voices/directed/elevenlabs.json`). O resto continua com as vozes geradas localmente (Qwen).
Lista completa do que falta: [elevenlabs-falas-restantes.md](elevenlabs-falas-restantes.md).

## Quanto falta

| | Falas | Caracteres | Créditos estimados (v4, ~1/caractere + ~10% de indicações) |
|---|---:|---:|---:|
| PT-BR restante | 512 | 29.344 | ~32.000 |
| Inglês (tudo) | 565 | 34.327 | ~38.000 |
| **Total** | **1.077** | **63.671** | **~70.000** |

São 90 vozes no roteiro: 88 ainda sem escolha (Jessica, Raul, Nelson, Ferrugem, Takeshi, os 6 papéis
de civis, guardas etc.). No ritmo de hoje (uma geração por fala), o custo é praticamente o número de
caracteres. Refazer falas ruins custa de novo.

**Plano de US$ 5:** se forem 30 mil créditos por mês (confirmar no painel), já gastamos ~7.800 hoje.
O total cabe em ~3 meses nesse plano, ou num mês de um plano maior. Conferir preços atuais em
elevenlabs.io/pricing antes de decidir. Usar o modelo Flash cortaria o custo pela metade, mas ele não
entende as indicações de emoção; não recomendo para missões.

## Como fazer

1. **Escolher as vozes antes de gastar.** Para cada personagem eu proponho uma voz da biblioteca pelo
   perfil de `data/dialogue/voice-cast.json` (gênero, idade, temperamento). Você ouve a amostra grátis de
   cada uma no site e aprova a lista. Nada é gerado antes disso.
2. **Inglês com a mesma voz.** O v4 é multilíngue: a mesma voz do Dante fala inglês, o que mantém o
   elenco igual nos dois idiomas. Risco: sotaque brasileiro forte. Teste barato primeiro: 2 falas em
   inglês (Dante e Maciota, ~100 créditos). Se não ficar bom, escolhemos uma voz americana parecida
   para cada um.
3. **Falas aleatórias com vários tons.** Os 6 papéis de civis (amigável, nervoso e reservado, masculino
   e feminino) e os guardas são as falas que mais se repetem. Proposta: 2 a 3 tons para as reações
   curtas (custo extra de ~5.000 créditos no total) e 1 take para as falas de diálogo.
4. **Em lotes por ordem de importância**, cada um terminando instalado no jogo e testado:
   - **Lote A** (~12.000): Dante e Maciota completos — 56 falas PT restantes e todas as 109 em inglês.
   - **Lote B** (~16.000): elenco principal das missões — Jessica, Raul, Nelson, Ferrugem, Takeshi,
     Helena, Vicente, Elias, Joana, Neco — PT e inglês.
   - **Lote C** (~22.000): civis e guardas, com os tons extras.
   - **Lote D** (~20.000): os demais personagens secundários (moradores do deserto, da serra, vila).
5. **Instalação:** `tools/install_elevenlabs_voices.py` passa a ler um plano por lote e grava as falas em
   inglês em `lines.en` do mesmo arquivo; o jogo já escolhe o idioma pela configuração de voz.

## O que preciso de você

- Confirmar o plano e quantos créditos tem por mês.
- Aprovar a lista de vozes do lote A/B quando eu mandar (ouvir as amostras é grátis).
- Dizer se quer ouvir fala por fala antes de instalar ou se aprova em lote como hoje.
