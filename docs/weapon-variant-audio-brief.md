# Sons das variantes de armas

> **27/10/2026 (tarde) — tiros refeitos.** As tomadas de tiro geradas no site da ElevenLabs
> (conta grátis, sem licença comercial) saíram ruins: tiro duplo dentro da tomada, tiro que só
> começa 0,2 s depois do gatilho, blocos de ruído com envelope retangular e corte seco, e cliques de
> 20-40 ms sem nada abaixo de 150 Hz. `tools/audio/rebuild_weapon_banks.py` remonta os quatro bancos
> (`shot_0..4`) só com gravações licenciadas que o jogo já usa (Firefly e V1): estalo de uma tomada
> sobre o corpo grave de outra, cauda aparada, estalo de ferrolho sintético na silenciada e na
> semiautomática, nível casado pela energia dos primeiros 120 ms. O mesmo script nivelou as tomadas
> antigas que destoavam (pistola, magnum, SMG, escopeta, serrada, rifle de caça, bombeada e as
> silenciadas do V1). Originais e prévias antes/depois em `evidence/weapon-audio-20261027/` (fora
> do Git). As recargas das variantes continuam as da conta grátis (não refeitas; licença pendente).

As quatro armas novas já têm áudio jogável temporário: gravações existentes com timbre ajustado e camadas sintéticas curtas, preparadas durante o carregamento. A versão silenciada usa o banco de tiros abafados existente. A escopeta semiautomática tem recarga sintética própria, sem bombeamento manual. Para identidade sonora definitiva, produzir os 32 arquivos abaixo. O jogo detecta os arquivos importados automaticamente, substitui os temporários e mantém o tom original das gravações novas.

## Entrega para Claude

Produzir efeitos para um jogo de ação em terceira pessoa. WAV PCM 16-bit, mono, 48 kHz. Sem música, fala, silêncio inicial, clipping, reverb longo ou rajada embutida. Cada tiro deve ser um disparo único: a cadência vem do jogo. Manter ataque imediato, transiente definido e variações naturais entre takes; não basta mudar o volume da mesma amostra. Pico máximo -3 dBFS, preservar dinâmica e deixar headroom para impactos e ambiente.

| Pasta em `audio/weapon_variants/` | Tiros | Identidade desejada | Recargas completas |
|---|---|---|---|
| `pistol_suppressed` | `shot_0.wav` a `shot_4.wav`, 0,20–0,40 s | Estalo abafado, curto, com mecanismo audível; ainda reconhecível como tiro, sem efeito de laser | `reload_0.wav` a `reload_2.wav`, **1,50 s**; retirada/encaixe de carregador e manipulação do ferrolho |
| `smg_compact` | `shot_0.wav` a `shot_4.wav`, 0,12–0,22 s | Estalo seco, mais agudo, agressivo, cauda muito curta; precisa funcionar a 13,3 tiros/s | `reload_0.wav` a `reload_2.wav`, **1,30 s**; carregador leve, encaixe rápido e ferrolho curto |
| `smg_tactical` | `shot_0.wav` a `shot_4.wav`, 0,20–0,35 s | Corpo mais grave e mecanismo firme, menos estridente que a compacta; disparos legíveis a 7,4 tiros/s | `reload_0.wav` a `reload_2.wav`, **2,00 s**; carregador, encaixe sólido e fechamento do ferrolho |
| `shotgun_auto` | `shot_0.wav` a `shot_4.wav`, 0,35–0,65 s | Baque de calibre 12 com ação semiautomática curta; **sem bombeamento manual** no tiro | `reload_0.wav` a `reload_2.wav`, **3,30 s**; cartuchos alimentados no tubo e finalização do mecanismo, sem troca de carregador destacável |

Nas recargas de pistola/SMGs, alinhar retirada a 9–20%, encaixe a 30–47% e ferrolho a 66–81% da duração. Na escopeta, concentrar alimentação de cartuchos em 12–35% e 39–66%, finalizando até 94%. Pequenos sons de roupa/manuseio podem preencher os intervalos, sem voz.

Não embutir queda da cápsula, acerto no alvo nem zunido no tiro: esses eventos usam bancos separados e dependem da superfície e trajetória. O volume de supressão é aplicado pelo jogo; entregar takes consistentes e não silenciar o arquivo artificialmente. Não normalizar cada take para intensidade perceptiva radicalmente diferente.

## Instalação e conferência

1. Colocar os arquivos exatamente nas pastas/nomes acima e abrir com Godot **4.7.2 .NET** para importar.
2. Reiniciar a sessão, pois os bancos são preparados e retidos no carregamento.
3. Conferir tiros isolados e sustentados, recarga e cancelamento da recarga, com volume normal do jogo. A nova entrega desativa o ajuste temporário de timbre e a camada sintética da respectiva arma.
4. Validar o som no jogo e no exportado. Arquivo carregado e teste automatizado não equivalem a aprovação auditiva.

Os sons existentes da pistola 9 mm, Magnum, MP5, pump e serrada continuam em uso. Melhorá-los é opcional e não é necessário para completar este pacote.
