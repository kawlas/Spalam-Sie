# Spalam Sie — Developer Guide

## Lint & Code Quality

### SwiftFormat / SwiftLint (opcjonalnie)

Jeśli zainstalowane:
```bash
brew install swiftlint
cd ~/Desktop/Spalam\ Sie && swiftlint
```

### Ręczne zasady

- **Nazewnictwo**: `camelCase` dla zmiennych/funkcji, `PascalCase` dla typów
- **Wcięcia**: 4 spacje (Swift domyślne)
- **Max linia**: 120 znaków
- **Importy**: tylko potrzebne, w kolejności: `Foundation` → `AppKit` → `SwiftUI`
- **Marki**: `// MARK: - Nazwa sekcji` do podziału plików
- **Guard early**: `guard` na początku funkcji dla warunków brzegowych
- **Force unwrap**: zakazane w kodzie produkcyjnym. Używać `guard let` / `if let`
- **Błędy**: własne typy `Error` (enum), nie gołe stringi

### Debug

```bash
# Podgląd generowanego TOC (bez zapisu na płytę)
swift run 2>&1 | grep "TOC\|ERROR\|CD_DA\|TRACK"

# Test z verbose
swift test 2>&1 | head -50

# Podgląd wykrytego napędu
/opt/homebrew/bin/cdrdao scanbus 2>&1

# Sprawdź status napędu
drutil status

# Czyszczenie .build (przy dziwnych błędach builda)
swift package clean
```

## Struktura projektu

```
Spalam Sie/
├── Spalam Sie.app/         ← Aplikacja (kliknij i działa)
├── Sources/
│   ├── Audio/              ← Konwersja FLAC/MP3 → WAV
│   ├── Burning/            ← cdrdao, wykrywanie napędu
│   ├── CDText/             ← CD-TEXT + TOC generator
│   ├── Metadata/           ← ffprobe wrapper
│   ├── Parsing/            ← CUE parser
│   └── Spalam Sie/         ← SwiftUI (App, Views, Models)
├── Tests/                  ← XCTest (18 testów)
├── docs/                   ← Dokumentacja projektu
├── Package.swift
├── PLAN.md
├── README.md
├── SOFTWARE_DESIGN.md
├── TESTING_STRATEGY.md
└── LOG.md                  ← Historia zmian
```
