# Áudio responsivo dos veículos

Implementação de 29/09/2026:

- O mixer diferencia acelerar de usar o comando contrário para frear. Soltar o acelerador reduz carga e rotação sem apagar a rotação transmitida pelas rodas.
- Rodagem do veículo controlado usa os contatos físicos já sondados pelos pneus: asfalto, grama, terra, neve e água/piso molhado. Cinco vozes fixas, recursos compartilhados, mistura a cada 50 ms, sem novos raycasts. Os quatro novos WAVs são síntese original offline; `audio/vehicle_fx/generate_surface_loops.py` permite reproduzi-los.
- Transições de piso fazem fade; velocidade governa volume e cadência. Rodas sem apoio, carro parado, saída, suspensão de física e apresentação desativada silenciam os loops. O tanque conserva as esteiras próprias.
- Canto de borracha exige contato com piso duro. Contatos leves a partir de 0,75 m/s produzem áudio sem criar faíscas.
- Colisões identificam metal, madeira e vidro por metadado `impact_material` ou nomes existentes; demais sólidos mantêm os takes de para-choque/colisão por intensidade. Reutiliza assets existentes e cooldowns. Impactos do carro controlado compensam a distância da câmera ortográfica.
- Corrigida a precedência do gramado autorado no piso compartilhado do porto. Estradas da montanha carregam identificação explícita de terra/asfalto.

## Validação (29/09, com as portas e o piloto sentado já no HEAD)

Godot 4.7.2, sem saves:

- `tests/test_vehicle_responsive_audio.gd`: 82 checks, 0 falhas.
- `tests/test_vehicle_effects.gd`: 40 checks, 0 falhas.
- `audio/test_vehicle_sound_migration.gd`: PASS.
- `tests/tank_control/test_tank_audio.gd`: 38 checks aprovados. Antes não compilava: sobrava código
  morto depois do `return` em `ServiceVehicleAudio._load_bank` (referenciava `bank`, já removido),
  e o teste assumia PCM de 16 bits.
- Os erros "externos" de compilação em `VehicleInterior.gd` e `NativePlace.gd` das rodadas
  anteriores não reaparecem.

Bug achado na verificação (não é do áudio responsivo): `TankAudio._stream` fechava o laço com
`data.size() / 2`, o que só vale para PCM 16 bits. Os WAVs entram como QOA (`compress/mode=2`),
então o laço do motor e das esteiras do blindado fechava aos ~0,4 s de um som de 2 s. Agora usa
`TankAudio.frame_count`. Como o recurso importado é QOA, o teste do tanque só mede pico/RMS quando
o formato é PCM; em QOA confere mono, duração, laço e tamanho do laço.

Não medido: custo de quadro das cinco vozes de rodagem e a percepção auditiva das misturas (só
verificação numérica dos mixers).
