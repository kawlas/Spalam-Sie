# Audio Player Vision — "Spalam Sie Player"

**CEO Recommendation** | 2026-07-02

---

## Architectural Decision: SFBAudioEngine

Po dogłębnej analizie 15+ istniejących playerów macOS, rekomenduję **SFBAudioEngine** jako silnik audio.

| Engine | Licencja | Bit-Perfect | DSD | Gapless | Wady |
|--------|----------|-------------|-----|---------|------|
| **SFBAudioEngine** | **BSD (free)** | ✅ HAL exclusive | ✅ DSF/DFF | ✅ sample-accurate | Wymaga nauki API |
| BASS | ~$1,000+ komercyjna | ✅ Hog Mode | ❌ (base) | ✅ | Droga licencja |
| AVAudioEngine | Wbudowana | ❌ | ❌ | ⚠️ limited | Nie można bit-perfect |
| ffmpeg (Bòcan) | LGPL | ❌ | ✅ | ✅ | Brak exclusive mode |

**SFBAudioEngine** jest używany przez Orange Music Player — najlepsze open source reference. BSD = brak kosztów, można użyć komercyjnie.

---

## Rekomendowana architektura

```
┌─────────────────────────────────────────────┐
│               SwiftUI Frontend              │
│  Album grid | Now Playing | Mini Player     │
│  Smart playlists | Folder browser           │
├─────────────────────────────────────────────┤
│           SFBAudioEngine (CoreAudio HAL)     │
│  Bit-perfect | Sample rate switch | DSD     │
├─────────────────────────────────────────────┤
│         Metadata Layer (MusicBrainz + ...)   │
│  Tag reading | Cover Art | Last.fm          │
├─────────────────────────────────────────────┤
│         Internet APIs                       │
│  MusicBrainz | Last.fm | LRCLIB | Discogs   │
└─────────────────────────────────────────────┘
```

---

## Feature List — co proponuję dodać

### Must Have (MVP Playera)
1. **Album grid view** — największa dziura na rynku, żaden player nie robi tego dobrze z album art + szybki scroll
2. **Bit-perfect playback** przez SFBAudioEngine (exclusive/hog mode)
3. **Wszystkie formaty**: FLAC, ALAC, WAV, AIFF, MP3, AAC, OGG, Opus, APE, WavPack, DSD (DSF/DFF)
4. **Gapless** — sample-accurate przez SFBAudioEngine
5. **CUE sheet support** — importujemy z istniejącego CUEParser, to nasz unikalny atut
6. **Folder browser** + kolumnowy przeglądarka (jak Swinsian)
7. **Floating mini-player** — zawsze-na-wierzchu, podstawowe sterowanie

### Quality of Life
8. **MusicBrainz** — tagowanie, identyfikacja, okładki (Cover Art Archive)
9. **Last.fm scrobbling** — druga najczęściej żądana funkcja na forach
10. **Smart playlists** — regułowe (gatunek, rok, ocena, liczba odtworzeń)
11. **ReplayGain** — normalizacja głośności między utworami
12. **LRCLIB.net lyrics** — synchornizowane teksty (open source, bez opłat)
13. **Signal path display** — pokazuje "bit-perfect chain" dla audiofilów

### Design (inspiracje z researchu)
14. **Immersive album art** — full-screen tryb z płynną animacją (Orange, BitMuse)
15. **Dark mode first** — z eleganckim glassmorphism (Bòcan)
16. **Natychmiastowe uruchomienie** — <1 sekunda, leniwe ładowanie biblioteki
17. **Keyboard shortcuts** — globalne hotkeys, MediaRemote (systemowe klawisze multimedialne)

### Integracja z resztą appki
18. **Import z Audio CD** — nagrane audio CD ładuje się do playera
19. **Playlista z BurnSession** — możesz odtworzyć to co zaraz wypalisz
20. **Wspólne metadata store** — edytuj tagi w playerze, użyj ich przy wypalaniu

### Stretch Goals (po wersji 1.0)
21. **DSD native** (DSD64-DSD512 przez DoP)
22. **Parametric EQ** z presets
23. **BS2B crossfeed** (słuchawki)
24. **Discogs API** — dodatkowe źródło okładek i informacji o wydaniach
25. **Artist info/biography** — pobierane z Last.fm / Wikipedia
26. **Web remote** — sterowanie z telefonu (jak BitMuse)
27. **AI-generated playlists** — nikt tego nie ma, luka rynkowa

---

## Dlaczego to ma szansę być lepsze od istniejących?

| Problem rynkowy | Jak my to rozwiązujemy |
|---|---|
| Brak album grid view | ✅ Album grid będzie domyślnym widokiem |
| Brak CUE sheet support | ✅ Mamy już CUEParser w projekcie |
| Bit-perfect = drogie (Audirvana $150) | ✅ SFBAudioEngine jest darmowy (BSD) |
| Płytkie metadata u konkurencji | ✅ MusicBrainz + Last.fm + LRCLIB (3 źródła) |
| Brak integracji z burnerem | ✅ Spalam Sie wypala PŁYTY — unikalne USP |
| Ciężkie i wolne starty | ✅ Cel: <1s startup, <50MB RAM |
| Design odstaje od macOS | ✅ SwiftUI native, dark mode, glassmorphism |

---

## Plan implementacji (po Sprint 2)

1. **SFBAudioEngine** — dodać jako SPM dependency
2. **AudioPlayerEngine** — przepisać od nowa na SFBAudioEngine (obecny stub był testem koncepcji)
3. **MetadataManager** — MusicBrainz API + Last.fm + LRCLIB
4. **NowPlayingView** — immersive album art
5. **MiniPlayer** — floating window
6. **AlbumGridView** — główny widok biblioteki
7. **SmartPlaylistEngine** — regułowe playlisty
8. **Integracja z BurnSession** — odtwarzaj przed wypaleniem

---

*Koniec dokumentu wizji — do zatwierdzenia przez CEO (Ciebie)*
