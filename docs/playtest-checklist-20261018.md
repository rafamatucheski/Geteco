# Playtest checklist — changes from 18/10/2026

About 15 minutes. Nothing below has been seen by a person in the running game yet; the
automated tests only prove the code paths. Play with `Jogar.cmd`. In-game text is shown as it
appears with English text selected (Portuguese in parentheses).

For each item: do the step, compare with **Expect**, and if it differs, note what you saw.

## 1. Death and arrest cost something (commit 0ecd01a0)

1. In Harbor, with some cash, get killed (fall, fight, traffic).
   **Expect:** you wake at the **Bay Medical door**, and a notice says
   "Hospital bill: − R$ X" ("Conta do hospital"), where X is 10% of your cash, at most R$ 2,000.
   With no cash, no bill.
2. Get one wanted star and let the police arrest you.
   **Expect:** you leave through the **police station door**, a notice says
   "Arrest fine: − R$ X · Ammo confiscated: N rounds". Your guns are still in the inventory,
   but empty. Ammo in the car trunk is not taken.
3. Die in the mountain, far from the bridge.
   **Expect:** you respawn normally; you should never get stuck on
   "Local de resgate ocupado" (fixed in e1fad702).

## 2. Story pays, tow jobs unlock with the story (commit 76453082)

1. Load a save that already finished some Harbor missions.
   **Expect:** once, right after loading: "Bonus for missions already completed: + R$ X".
   Loading again does not pay again.
2. Finish a Harbor mission.
   **Expect:** "<mission> complete · + R$ X" (first mission R$ 1,000 … last one R$ 8,000).
3. At the "Towing service" ("Serviço de guincho") early in the game.
   **Expect:** only "First haul" (R$ 600) is offered at the start; better jobs appear as
   missions are completed (up to R$ 2,400).
4. After the Harbor finale, rob an armored truck.
   **Expect:** R$ 20,000 per truck (was 40,000).

Tell me if the money feels too tight or too loose; that is the one thing tests cannot judge.

## 3. Journal shows every story (commit 3ce8877d)

Press **J** in Harbor.
**Expect:** besides the Harbor missions, lines for the mountain story ("Cobras' Cargo · …" or
"Vicente's Trail · …"), the Serra Forge once you've met Seu Bento, Tonico once you've started
his job, and, after the Harbor finale, "Desert · …". Finished stories disappear.

## 4. Desert (commits 1d417437, e1fad702 and this one)

1. Reach the desert cave with the cash tin (cave_vulture, around x -600, z -1410).
   **Expect:** the note appears and R$ 420 goes into your wallet. Quit, reload, go back:
   nothing is paid again.
2. Drive near the drag strip and the outlaw camps with **fps limit 60** (the default).
   **Expect:** the outlaw camps, the bandit camp, the desert residents and the cargo-heist truck
   appear within a second or two of getting close, not half a minute later.

## 5. Crime is consistent (commits 1d417437 and this one)

Shoot an angler at the lake, a resident inside a building, or a guest at the classic meet.
**Expect:** the same police response as killing a pedestrian in the street (murder level, not
"assault"). Running over a Cobra does **not** count as a civilian murder.

## 6. A broken save can be recovered (commit 1d417437)

Uses **slot 5**, which is empty; your real slots are not touched. In a terminal, make a copy of
slot 1 with one block deliberately broken:

```
python -I -c "import json,os;d=os.path.expandvars(r'%APPDATA%\GetecoV2\GetecoV2\saves');t=d+r'\slot_05.json';assert not os.path.exists(t),'slot 5 is not empty';s=json.load(open(d+r'\slot_01.json',encoding='utf-8'));s['world']['skate']='broken';json.dump(s,open(t,'w',encoding='utf-8'))"
```

Then open **Load Game**.
**Expect:** slot 5 shows "Recoverable — resets: skate" ("Recuperável — volta ao padrão").
"Continue" does not pick it. Choosing it loads the game with a notice that the skate progress
went back to default, and `slot_05.json.pre-recovery.<number>` sits next to the file with the
original bytes. Delete slot 5's files afterwards if you like.

## 7. Quick sanity

- Main menu, new game, first minutes: nothing looks or sounds different from before.
- Saving with F5 works; if saving were ever turned off, a red icon with the reason now stays in
  the bottom-right corner instead of failing silently.
