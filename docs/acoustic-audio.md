# Banco acústico de veículos e combate

Os sons são síntese original orientada por acústica, não gravações de veículos ou
armas reais e não uma simulação física calibrada. A aprovação perceptiva depende
de escuta no jogo, além das verificações automatizadas.

## Estrutura

- `tools/build_acoustic_bank.py`: geração determinística offline (Python, NumPy,
  SciPy). Não executa durante uma partida.
- `audio/acoustic/engine_profiles.json`: perfis de combustão, cilindros,
  ressonâncias e rotações extraídos do controlador existente.
- `audio/acoustic/AcousticBank.gd`: índice gerado de PCM mono compartilhado.
- `audio/VehicleEngineSound.gd`: transmissão e mistura por giro/carga; sete
  faixas nominais por família de combustão, até duas vozes de motor simultâneas.
  Rolagem, turbo e freios continuam com controles próprios. O elétrico mantém
  sua síntese específica, sem introduzir combustão.
- `audio/combat/CombatAudioBank.gd`: cinco tomadas sem repetição consecutiva,
  reutilizando o banco e a espacialização existentes.

O banco substitui disparos de pistola, magnum, submetralhadora, AK, M4, rifle,
escopeta e cano serrado; variantes com silenciador; impactos em concreto, madeira,
metal, vidro e personagens; explosões, ricochetes e lançamento de RPG.
Gravações específicas de veículo ainda têm precedência. Rádio, diálogos,
ambientes climáticos, recargas e as gravações existentes de colisões de veículos
não foram regenerados. Portanto, isto não substitui todo som do projeto.

Derrapagem usa cinco famílias de atrito/squeal de pneu, selecionadas pelo mesmo
resolvedor do motor, com volume por velocidade e pitch por deslizamento lateral.
As duas classes de carro usam SFX. Ao iniciar uma saída aceita, motor e todas as
vozes auxiliares, derrapagem e rádio param antes da animação da porta. O carro
vazio não deve reativar o motor. `tests/test_vehicle_audio_exit.gd` exercita os dois
controladores, inclusive restauração pelo caminho real de save e nova saída.

## Decisões sonoras

Motores combinam pulsos de combustão com irregularidades discretas, reflexões de
escape, ressonâncias, admissão e componentes específicas de diesel/turbo. Faixas
mais próximas reduzem a transposição necessária. Mistura de potência constante
evita queda de volume no meio da passagem entre duas faixas. A curva de tração
alongou a aceleração; parar seleciona a primeira marcha em todas as famílias.
Cada família de carro a combustão recebeu uma marcha adicional: os pontos das
trocas iniciais permanecem e o antigo trecho final é dividido em dois. Sedã e
cupê esportivo passam de cinco para seis; muscle de quatro para cinco. Motos e
tração elétrica direta mantêm as relações anteriores.
A última relação dos carros limita o giro de cruzeiro a 87% do corte, deixando
reserva. A passagem de giro e a pequena variação de pressão do escape permanecem
audíveis sem acionar o limitador continuamente.

Disparos combinam pressão bipolar curta, turbulência, corpo grave, mecanismo e
reflexões discretas. Não há recarga embutida no disparo. A posição da onda
balística depende da geometria real; o banco não afirma simular trajetórias
acústicas ou identidade exata de calibre. Silenciadores reduzem e filtram o corpo
do disparo sem silenciar completamente o mecanismo.

O importador WAV usa `edit/loop_mode=2` para loop forward; o enum do recurso
AudioStreamWAV usa outro valor. Os loops têm 22050 frames e oito frames de guarda.
Não há síntese por amostra no controlador em tempo de jogo. Sete nós por motor
podem existir, mas apenas duas faixas são reproduzidas; os recursos são comuns a
todos os veículos da família. Isso é um limite de trabalho, não prova de FPS.

## Referências

- [Audiokinetic / Wreckfest, desenho de motores por RPM e carga](https://www.audiokinetic.com/media/blog/LoopBasedCarEngineDesign/vehicle_audio_modding_guide_for_wreckfest-Wwise2019_2_9.pdf).
- [Maher e colaboradores, variações de formas de onda de disparos](https://pubmed.ncbi.nlm.nih.gov/21476632/).
- [Maher, registros de disparos e geometria acústica](https://www.montana.edu/rmaher/publications/maher_aesconf_0608_1-8.pdf).
- [Godot, importação WAV](https://docs.godotengine.org/en/latest/classes/class_resourceimporterwav.html).

São referências de estrutura; nenhum áudio dessas fontes foi copiado.

## Validação

`tests/test_acoustic_bank.gd` confere banco selecionado, cinco tomadas,
loops/guardas, limite de duas vozes, parada/reengate e aceleração progressiva.
Os testes existentes cobrem combate real, recarga, proteção da garagem,
personalidade, preparação/cache e ciclo de vida de áudio dos carros.

Evidências da sessão ficam em `_codex_diag/audio-redesign`. A prévia grava a
saída do barramento SFX no Godot; não substitui aprovação auditiva do usuário.
Os hashes de `audio/reload` são comparados para assegurar preservação exata.

O alvo provisório é 60 FPS (16,67 ms). O comparativo renderizado usa HarborGame,
1920×1080, Mobile/Vulkan, RTX 4060 Laptop, VSync e limitador desativados, semente
fixa e 30 segundos de aceleração após carregamento/entrada no carro. Não confundir
testes headless com aprovação de desempenho. As primeiras tentativas usavam a
ação antiga `ui_up`, que não dirige o carro atual; essas amostras imóveis foram
descartadas como baseline de condução. Métricas finais e limitações devem ser
consultadas no relatório de medições desta pasta.
