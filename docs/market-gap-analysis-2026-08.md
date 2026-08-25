# Market / gap analiza 2026-08 — šta čini Roblox igru "zaraznom", i gde je Evolution Lab

> Owner research input, 2026-08-25 (verbatim, light formatting). Ovo je analiza koju je Kristina
> dostavila uz otvaranje Phase 33 — ROADMAP je vodi kao izvor za redove 33.x. Odluke vezane za
> nju: boss ~20 swings (33.8), prvo map bugovi pa ovo (33.3 vodi map posao).

## 1. Šta čini Roblox igru "zaraznom" u 2026

Na osnovu top lista i devforum analiza, ovo dominira:

| Trend | Primeri | Zašto radi |
|---|---|---|
| "Verb a Noun" naslovi | Steal a Brainrot, Grow a Garden, Fish it!, Drill Digging Simulator | Instantly digestible — igrač zna šta radi u 1 sekundi. "Evolution Lab" je OK, ali razmisli o podnaslovu. |
| Chunky / Studded estetika | PS99, Grow a Garden, BGS Infinity | Debeli outline-i (4–6px), glossy gradienti, hard drop-shadows, rounded corners po funkciji. Već imaš ovo — UITheme.Radius/Stroke sistem. |
| Personal Space / Baza | Grow a Garden (diorama plot), Steal a Brainrot (base defence) | Igrač ima "svoje" zemljište koje personalizuje. Najjači retention alat u žanru — emocionalna investicija. |
| PvP / Risk mehanike | Grow a Garden 2 (noćna krađa), Brainrot (stealing) | Napetost stvara adrenalin. "Šta imam izgubiti" je moćnije od "šta mogu dobiti". |
| Guilds / Timovi | Grow a Garden 2 (weekly guild rewards) | Social lock-in — ne napuštaš igru jer napuštaš ekipu. |
| Infinite Rebirth Loop | PS99, Drill Digging Simulator | Reset sa permanentnim bonusom = beskonačan endgame. Već imaš — 4 rebirtha, možeš proširiti. |
| FOMO Eventi | Weekend 2x, Season Pass, Limited Skins | Strah od propuštanja. Već imaš — EventService, Weekend Rush, Season Pass. |
| Spectacle Reveals | Hatch sequence, evolve flash, Splicer roll | "Juice" — šta se dešava kad nešto dobiješ. Već imaš — HatchReveal, EvolveReveal, SplicerUI. |
| Trading kao endgame | PS99, Murder Mystery 2, BGS | Kada sve ostalo postane dostupno, trgovina postaje sama igra. Već imaš — TradeService. |

## 2. Analiza ROADMAP-a — šta je već TOP-tier

### Ekonomija i monetizacija
- **ScaleReward sistem** — rešava fundamentalni problem simulatora gde late-game kupovina postaje
  beskorisna. 10,000 DNA pack vredi isto na stageu 1 i 20 — dizajn koji PS99 koristi.
- **Game Pass stackovanje** — VIP 1.5x + 2x DNA = 3x, bounded, nikad broken. Otporno na
  pay-to-win optužbe.
- 17 developer produkata + 9 game passova — pokriveno.
- **Lucky Spin** — gamble ispod safe buy-a (2,260 vs 2,500 expected) — balansirano.

### Kodna disciplina
- PassService fail-closed, pcall + backoff, refresh na join i purchase — production-grade.
- `data.Passes` se resetuje na load — nema exploit-a sa starijim saveovima.
- Trading: duplikacijska zaštita, proximity check, 2-sided confirm, 3s countdown.

### Audio
26 SoundLibrary entry-ja, 3 SoundGroup-a, preload, minGap, vary, variants. Većina Roblox igara
ima 0 zvukova.

### Retencija
Daily rewards, offline earnings (8h cap, 50% rate), codes, season pass, leaderboards,
cross-server announcements, free daily spin — sve prisutno i balansirano.

### Dizajn
- Chunky estetika — UITheme.applyShell, edged/capped, gradienti, gloss, 4-step radius sistem.
- Emoji → Icon sistem — 74 ikone, proceduralno generisane.

## 3. GAP analiza — šta fali za top 10

### 🔴 KRITIČNO — Personal Space / Baza
Najveća rupa. Svaki top simulator 2026. ima "tvoje" zemljište (GaG diorama plot, Brainrot baza,
PS99 bank/garden).
**Preporuka: "Evolution Chamber"** — personalni plot gde igrač postavlja kućice za petove
(visual), trophy standove za leaderboard pozicije, display case-ove za Secret/Celestial petove.
20–30 propova, snap-to-grid, otključava se kroz progression.

### 🟠 VISOKO — Social / Competitive layer
- **Guild System** — GuildService: guild do 10 članova, weekly guild questovi (ubij 10,000
  creatura zajedno), guild-exclusive shop sa kozmetikom. Group sistem (5.5) daje +10% DNA ali
  nema Guild Wars / Guild Leaderboards.
- **PvP Risk faza** — "Corruption Event": svakih 30 min zona postane "corrupted", creaturi
  elite, payout 3x; PvP flag dozvoljava napadanje flagged igrača i krađu 10% DNA zarade u toj
  sesiji. Risk/reward odluka.

### 🟡 SREDNJE — Side activities (anti-grind)
**"Fishing Pond"** u Forest hub-u — svaki catch daje DNA buff potion ili shard-ove. Low-stakes,
drugačiji rhythm. (Opcije: mining/digging, racing između zona.)

### 🟢 NISKO — Cosmetic depth
Trails (iza lika), Emotes (dance/cheer/taunt), Name Tags (customizable, ne samo VIP). Čisto
kozmetički, ali retencija raste 3–5x sa social featureima.

## 4. Detaljne preporuke po kategorijama

### A. HUD & UI layout
Već dobro: capsule strip, UITheme 4 radius stepa + 3 stroke weight-a, TextFits provere.

| Element | Preporuka | Prioritet |
|---|---|---|
| Damage Popups | dodaj screen-space varijantu pored world-space | Srednja |
| Combo Counter | "x5 Kill Streak!" — adrenalin, feedback | Srednja |
| Zone Transition Card | dodaj screenshake i sound sting | Niska |
| Mobile Swipe Gestures | swipe levo/desno za panele — ZASEBAN LocalScript, ne MainUI | Visoka |
| Toast Stack | grouping — "5x Crit! +160T" za burst kritove | Srednja |

**Tehničko upozorenje:** MainUI je na 170–181 top-level local-a (Luau limit 200). Svaka nova
stvar ide u IIFE blokove ili novi modul. Planirati split MainUI na 2–3 fajla (HUD, Panels,
Trade) pre zida.

### B. Dizajn mape
Već dobro: 20 zona sa unique paletama, terrace/ramp sistem, HubPlaza kao social prostor, solid
prop audit.
- **Photo Spot** — posebna pozadina + frame overlay na marki (social share = free marketing).
- **Secret Areas** — easter egg lokacije (npr. ispod CelestialThrone platforme), exclusive skinovi.
- **Dynamic Weather** — rain u Forest, ash u Volcano, sparkles u Celestial. Samo particles.
- **Interactive Props** — klupa (emote trigger), zid za lean.
- **Base Plot zona** — instancirani "pocket dimension" po igraču.

### C. Funkcionalnost i mehanike
- **"Corruption Invasion"** (PvE+PvP hibrid) — vidi 🟠 iznad; "Steal a Brainrot" mehanika na
  naš žanr.
- **"Pet Ranch"** — Ranch plot u Forest hub-u; ostaviš do 5 petova, pasivno generišu DNA
  (10% od Auto Collect); petovi vizuelno trče/spavaju/se igraju; retention hook = vratiš se da
  pokupiš.
- **"Enchant Transfer"** — za 100 Diamonds prebaci enchant sa pet-a na pet. Smisao Diamondima
  posle svih upgrade-ova.

### D. Retencija i monetizacija

| Sistem | Opis |
|---|---|
| Achievement Board | 50+ achievementa (prvi rebirth, prvi Secret, 1M kila) → title-ovi |
| Title System | "Apex Hunter", "DNA Billionaire", "Lucky Roller" — equipable, vidljivo |
| Weekly Challenges | Globalni goal ("svi zajedno 1B creatura") — reward za sve |
| Referral System | "Pozovi prijatelja" — obojica dobiju exclusive pet |
| Robux → Cosmetics | Trail/aura/emote shop — bez gameplay advantage |

## 5. Prioritet

- **Faza A "The Missing Half" (2–3 nedelje):** Evolution Chamber (personal plot) · Mobile
  gesture support (poseban modul) · Achievement + Title sistem.
- **Faza B "Social Layer" (1–2 meseca):** Guild system · Corruption Invasion · Pet Ranch.
- **Faza C "Polish & Scale" (ongoing):** MainUI split · Dynamic Weather + Secret Areas ·
  Cosmetic shop.

### Tehnički dug (hitno)
- Studio ↔ src sync disciplina (pre-commit dump preko HTTP bridge-a) — bez toga svaka faza
  rizikuje regresiju. (NAPOMENA agenta: ovo postoji — `tools/push_files.py` + hash sweep + board
  sync guard; disciplina je bila povremena, R24/R26 je zapisala pravilo.)
- MainUI register cap — IIFE ili novi modul za svaki dodatak; planiraj split.

## Kratka verzija

Igra već ima bolju ekonomiju, kodnu disciplinu i audio od 95% Roblox simulatora. Od top 10 deli
je: **personal space (baza/plot), social layer (guilds, PvP risk) i side activities
(mini-games)**. HUD i chunky estetika su na nivou — ne dirati što radi, dodati što fali.
