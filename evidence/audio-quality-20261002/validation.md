# Revisão dos efeitos de contato — 02/10/2026

Substituídas 41 amostras de atropelamento, queda, carroceria, moto, vidro,
madeira, metal e concreto. Fontes, licenças e edição reproduzível estão em
`audio/contact_foley/CREDITS.md` e `build_bank.py`. A reprodução em runtime não
foi alterada. O banco final ocupa 2.818.030 bytes em WAV mono PCM 16-bit/44,1 kHz.
Originais preservados em `before/`; prévias em `before-preview.wav` e
`after-preview.wav`: atropelamento, queda, para-choque, metal, acidente forte,
vidro e madeira. Essas prévias são dos arquivos, sem atenuação espacial.

## Validação funcional

- `dotnet build Harbor.csproj --no-restore`: sucesso, zero avisos/erros.
- Importação com Godot 4.7.2 .NET: concluída para as 41 amostras.
- `test_body_impact_audio`: 33 verificações, zero falhas.
- `test_vehicle_contact_audio_prewarm`: 82 verificações, zero falhas.
- `test_contact_audio`: 27 verificações, zero falhas; colisões físicas com muro,
  poste e pessoa emitiram som.
- Dois testes emitiram avisos ObjectDB e recursos em uso durante o encerramento.
  Não foram classificados como corrigidos ou comprovadamente preexistentes.
- Conferência dos 41 arquivos: mono, 44,1 kHz, extremidades em zero,
  sem amostras saturadas, importação PCM; hashes finais iguais ao manifesto.
- Captura renderizada `contact_audio_live.gd`, cena Main: 18 emissões, 9 ciclos.
  Gravações SFX e contatos com sinal presente e zero amostras saturadas.
- Captura renderizada `measure_body_impact_sound.gd`, cena Main: 3 impactos de
  atropelamento, 8 sons de queda, 3 voos e aterrissagens concluídos, 5 saídas
  de veículo aceitas. Master e contatos com sinal e zero amostras saturadas.

Os scripts foram executados com `--no-save` e raiz de save isolada. Logs e
gravações estão nesta pasta. Verificação de sinal comprova reprodução e ausência
de clipping digital, não substitui avaliação auditiva humana do timbre/mixagem.

## Performance — pendente

Risco: maior memória de amostras PCM e alteração das durações; continuam o mesmo
pool de 12 vozes, prewarm e limites de contato. Nenhum processamento adicional
por frame. Meta provisória 60 FPS/16,67 ms, com aumento de p95/p99 superior a 5%
exigindo investigação em comparativo isolado equivalente.

Havia testes e capturas de outras sessões durante a tarefa (inventário em
`concurrent-processes.json`). Não foi possível obter baseline isolado antes da
alteração. As capturas atuais usam RTX 4060 Laptop, renderer Mobile e gravação
de áudio: não são evidência de ausência de regressão nem aprovação de FPS.

Observações contaminadas por concorrência e gravação, conservadas apenas para
diagnóstico: contatos, 30,008 s / 4016 frames, 133,83 FPS, p50 6,172 ms,
p95 13,123 ms, p99 16,689 ms, máximo 84,747 ms, 5 frames >33,3 ms e 1 >66,7 ms;
atropelamentos, 30,001 s / 2080 frames, 69,33 FPS, p50 12,984 ms,
p95 31,114 ms, p99 65,336 ms, máximo 203,919 ms, 73 frames >33,3 ms e 20 >66,7 ms.
Dados brutos, resolução, VSync e limite de FPS nos respectivos JSONs.

Pendente: comparação renderizada antes/depois sem concorrência e sem gravação,
com cenários equivalentes, e avaliação auditiva da nova mixagem.
