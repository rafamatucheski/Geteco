# Weapon contact Foley

Short offline edits of the CC0 recordings already retained in
`audio/contact_foley/source`. Original sources and licenses are listed in
[the contact bank credits](../contact_foley/CREDITS.md): Kenney Impact Sounds
and Independent.nu / qubodup's crunch recordings.

These are designed game Foley, not recordings of real cartridges. Three takes
per contact family use faster playback, filtering, a short decay and headroom;
no new noise generators, runtime DSP or audio players. Hard floor, metal, wood,
soft ground and snow have separate contacts. Soil and snow bullet impacts avoid
the concrete/metal timbre. Rebuild using `python audio/weapon_contacts/build_bank.py`.
