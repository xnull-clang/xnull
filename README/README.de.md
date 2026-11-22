<p align="center">
  <img src="../assets/logo.png" alt="XNull" width="640">
</p>

# XNull

[English](../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Русский](README.ru.md) | [العربية](README.ar.md) | [Italiano](README.it.md) | **Deutsch**

**Schreib Code. Lass die Zeremonie weg.**

Keine Lifetimes. Keine Ownership-Annotationen. Kein `@Override`. Kein `try/catch`. Keine Getter und Setter. Keine Reflexion.

XNull ist eine neue Programmiersprache, in der der Compiler für jedes Objekt Stack, ARC oder GC anhand einer Entscheidungstabelle aus der Spezifikation wählt. Du schreibst die Daten und das Verhalten; die Laufzeit führt die Entscheidung aus. Speicherverwaltung ohne Ownership-Annotationen — und ohne versteckte Compiler-Magie.

Fehler sind Werte. Polymorphie sind Protokolle. Felder sind Felder. Die Spezifikation hält jede Entscheidung fest, einschließlich jeder abgelehnten Funktion und der Begründung.

```x
class Counter {
    Int n = 0

    Int add(Int v) {
        self.n = self.n + v
        return self.n
    }
}

static Int main() {
    Counter c = new Counter()
    print(c.add(2))
    return 0
}
```

| Du schreibst nicht mehr | XNull gibt dir |
| --- | --- |
| `Arc<Mutex<T>>`, Lifetimes | Speicher vom Compiler entschieden (Stack / ARC / GC) |
| `getX()` / `setX()` | direkte Felder |
| `extends` + `@Override` | Protokolle |
| `try/catch` | `Result<T,E>` + `try` |
| Reflexion | nicht ausdrückbar |

## Warum XNull

- **Vom Compiler entschiedene Speicherverwaltung.** Der Quelltext drückt nie Referenzstärke aus. Der Compiler wählt für jedes Objekt Stack, ARC oder GC anhand der Entscheidungstabelle DET-01; die Laufzeit führt die Entscheidung aus.
- **Kein Accessor-Muster.** Felder sind Daten; Verhalten sind Methoden mit Verben als Namen. Getter und Setter sind nicht ausdrückbar.
- **Komposition statt Vererbung.** Klassen unterstützen keine überschreibende Vererbung. Polymorphie läuft ausschließlich über Protokolle.
- **Fehler sind Werte.** `Result<T,E>`, `try`, `defer`/`errdefer`. Keine Ausnahmen, kein implizites Stack-Unwinding.
- **Keine Reflexion.** Was Quelltext und Spezifikation nicht bestimmen, gehört nicht zur Sprache.
- **Jede Entscheidung ist dokumentiert.** Die Spezifikation hält fest, was XNull unterstützt, was es ablehnt und warum. Chinesische Originale mit englischen Übersetzungen; weitere Übersetzungen sind willkommen.

## Schnellstart

```sh
# im Repository-Wurzelverzeichnis
./src/cli/xnull run src/examples/hello.x
```

```text
hello, XNull
1 + 2 = 3
```

Die CLI unterstützt drei Engines:

```sh
```

- `mini` — der neue minimale Compiler.


## Repository-Struktur

```text
assets/               Logo- und Projekt-Assets
docs/                 Architektur-, Sprach- und Designdokumente
README/               übersetzte README-Dateien
ide/                  VS-Code-Erweiterung und Web-IDE
src/                  Entwicklungsbaum
  cli/xnull           einheitliche CLI
  mini/               selbsthostender minimaler Compiler
  runtime/            C-Runtime-Quellen und Header
  xdk/                XDK-Quellen
  ffi/                Raw-FFI-Bridges (.xfb)
  toolchain/          Build- und Packaging-Skripte
  examples/           ausführbare Beispiele

xdk/                  XDK-Auslieferungspaket
  lib/xdk/            XDK-Paketquellen
  runtime/            C-Runtime-Quellen und Header
  ffi/                Raw-FFI-Bridges
  install.sh          POSIX-sh-Installer
```

`src/` ist der Änderungspunkt; `xdk/` ist die Auslieferungskopie. Nach Änderungen an `src/xdk/` muss sie mit `xdk/lib/xdk/` synchronisiert werden.

## Entwicklung

`src/` ist der Entwicklungsbaum, `xdk/` die Auslieferungskopie. Nach Änderungen an `src/xdk/` muss nach `xdk/lib/xdk/` synchronisiert werden.


### XDK installieren

```sh
cd xdk
./install.sh --prefix "$HOME/.local"
```

Installiert wird nach:

```text
<prefix>/share/xnull/xdk
<prefix>/share/xnull/runtime
<prefix>/share/xnull/ffi
```

Für das Packaging `DESTDIR` verwenden:

```sh
DESTDIR=/tmp/xdk-pkg ./install.sh --prefix /usr/local
```

## Aktueller Status

| Bereich | Status |
| --- | --- |
| Spezifikationen S1–S6 | Formal; S3 §14 listet offene Entscheidungen |
| XDK-Katalog S7 | v3.0.0 Entwurf; zuerst T0-Kern |
| Toolchain S8 / IDE S9 | Entwurf |
| Projektkonfiguration S10 | Final v5.3.0 |
| Native C-Toolchain | Für die aktuellen Kern-Szenarien einsatzbereit |
| Minimaler Compiler | Kernsprache + Basisklassen; Abdeckung wird erweitert |
| End-to-End-Szenarien | hello, Klassen, `import xdk.errors` funktionieren; mehr in Arbeit |
| Self-Hosting | Geplant |

## Ausdrücklich nicht unterstützt (per Design)

| Funktion | Begründung |
| --- | --- |
| Methoden-Override | „Welche Methode tatsächlich lief“ muss aus statischen Typen beantwortbar sein; dynamische Dispatch existiert nur über Protokolle |
| Accessors / Properties | Trennung auf Grammatikebene: Felder sind Daten, Verhalten sind Methoden mit Verben als Namen |
| Reflexion | Bricht das Axiom „Quelltext + Spezifikation bestimmen alles“ |
| Ausnahmen | Fehler sind Werte: `Result` + `try`; `throw` ist nur fatal und rollt den Stack nicht zurück |

## Roadmap

1. Natives C-Backend: eine Datei kompiliert zu C, das C zu einem Binary, das Binary liefert das Ergebnis.
2. Inkrementelle Vervollständigung: getrieben von ausführbaren Szenarien, nicht von Feature-Checklisten.
3. Self-Hosting: der Compiler, neu geschrieben in XNull.

## Angel-Investition

XNull sucht eine kleine Angel-Runde oder nicht-verwässernde Unterstützung für 12–18 Monate Arbeit an Compiler, Self-Hosting, Runtime und XDK. Das Ziel ist eng: die bestehende Toolchain zuerst korrekt, schnell und nutzbar machen, dann die Sprache erweitern.

Bei Interesse schreiben Sie an **vjsplus@163.com** mit dem Betreff `XNull Angel`. Konditionen werden privat besprochen.

> Dieser Abschnitt dient nur der Information und stellt kein Angebot zum Verkauf von Wertpapieren oder eine Aufforderung zum Kauf dar.

## Unterstützung

Wenn XNull dir hilft, freuen wir uns über eine kleine Spende. Auch kleine Beiträge helfen.

WeChat Pay (Festlandchina):

<img src="../assets/wechat-pay.jpg" alt="WeChat-Pay-QR-Code für Unterstützung" width="260">

> Unterstützung ist freiwillig, stellt keine Investition dar und verspricht keine Rendite.

## Mitmachen

XNull begann als Ein-Personen-Designprojekt. Die nächste Phase braucht Compiler-Ingenieure, Runtime-Ingenieure, XDK/API-Designer, Designkritiker, Autoren und Übersetzer. Wenn du eine Entscheidung für falsch hältst, bring ein Gegenbeispiel mit; ein gutes Argument wird zu einer Spezifikationsrevision.

Kontakt: vjsplus@163.com · [GitHub Issues](https://github.com/xnull-clang/xnull/issues)

## Lizenz

Code (`src/`, `xdk/`, `src/examples/`) steht unter Apache-2.0; siehe [LICENSE](../LICENSE). Spezifikationen und Dokumentation (`docs/`, `README*.md`) stehen unter CC BY 4.0; siehe [LICENSE-docs.md](../LICENSE-docs.md). Der Name und das Logo von XNull sind von diesen Lizenzen nicht abgedeckt.
