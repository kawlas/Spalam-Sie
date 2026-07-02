# Spalam Sie — Project Governance

## Role

| Rola | Odpowiedzialność |
|------|-----------------|
| **CEO (pi)** | Zarządza całym projektem, rozdziela zadania agentom, kontroluje jakość, podejmuje decyzje architektoniczne |
| **Reviewer Agent** | Review kodu, testów, architektury przed każdym merge'm. Sprawdza: poprawność, coverage, bezpieczeństwo, zgodność z TDD |
| **Worker Agent** | Implementacja zadań zdefiniowanych przez CEO |
| **Planner Agent** | Tworzy plany implementacji z podziałem na kroki |
| **Developer (człowiek)** | Testuje manualnie, dostarcza feedback, uruchamia aplikację |

## Development Workflow (TDD)

### Cykl: Red → Green → Refactor

```
1. CEO pisze TEST (RED)
   ↓
2. Reviewer weryfikuje test (czy testuje właściwy przypadek)
   ↓
3. Worker implementuje kod (GREEN)
   ↓
4. swift test (wszystkie testy muszą przejść)
   ↓
5. Reviewer weryfikuje kod + testy
   ↓
6. Refactor jeśli potrzeba (GREEN nadal)
   ↓
7. swift build -c release && deploy do .app
```

### Zasady

1. **TDD bezwzględne** — test przed kodem produkcyjnym. Żadnej luki.
2. **Testy muszą odpalać się lokalnie** — bez mocków na zewnętrzne narzędzia (cdrdao, ffmpeg) tam gdzie to możliwe.
3. **Każda zmiana w TOC/burn engine** — test integracyjny który generuje TOC i weryfikuje strukturę.
4. **Nie modyfikować macOS poza scope appki** — żadnych `diskutil`, `drutil` bez potrzeby. Nie zostawiać zamontowanych woluminów.
5. **Commit tylko gdy 100% testów przechodzi** — 0 failures, 0 unexpected.
6. **Kod podpisany ad-hoc przed deployem** — `codesign --force --deep --sign -`.

## Agent Workflow

```
CEO (pi)
  ├── planner (opcjonalnie) → plan implementacji
  ├── worker → implementacja kodu
  ├── reviewer → code review + test review
  └── researcher (opcjonalnie) → research rozwiązań
```

### Komendy

| Komenda | Akcja |
|---------|-------|
| `swift test` | Uruchom testy |
| `swift build -c release` | Build release |
| `swift run` | Uruchom z konsoli |
| `open Spalam Sie.app` | Uruchom z Findera |

## Quality Gates (przed deployem)

- [ ] Wszystkie testy przechodzą (`swift test`)
- [ ] Build release (`swift build -c release`)
- [ ] Reviewer approved
- [ ] `.app` podpisany (`codesign`)
- [ ] Test manualny (symulacja + real burn)

## Stack Technologiczny

- **Język**: Swift 6
- **UI**: SwiftUI (macOS 14+)
- **Build**: Swift Package Manager
- **Testy**: XCTest
- **Burning**: cdrdao 1.2.6
- **Audio**: ffmpeg, flac, lame (przez Process)
