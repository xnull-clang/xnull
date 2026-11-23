<p align="center">
  <img src="../assets/logo.png" alt="XNull" width="640">
</p>

# XNull

[English](../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Русский](README.ru.md) | [العربية](README.ar.md) | **Italiano** | [Deutsch](README.de.md)

> Questa traduzione non è ancora allineata all'ultima versione. La versione di riferimento è il [README inglese](../README.md).

**Scrivi codice. Salta la cerimonia.**

Niente lifetime. Niente annotazioni di ownership. Niente `@Override`. Niente `try/catch`. Niente getter e setter. Niente riflessione.

XNull è un nuovo linguaggio di programmazione in cui il compilatore sceglie stack, ARC o GC per ogni oggetto tramite una tabella di decisione scritta nella specifica. Tu scrivi i dati e il comportamento; il runtime esegue la scelta. Gestione della memoria senza annotazioni di ownership — e senza magia nascosta del compilatore.

Gli errori sono valori. Il polimorfismo sono i protocolli. I campi sono campi. La specifica registra ogni decisione, comprese le funzionalità rifiutate e il perché.

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

| Non scrivi più | XNull ti dà |
| --- | --- |
| `Arc<Mutex<T>>`, lifetime | memoria decisa dal compilatore (stack / ARC / GC) |
| `getX()` / `setX()` | campi diretti |
| `extends` + `@Override` | protocolli |
| `try/catch` | `Result<T,E>` + `try` |
| riflessione | non esprimibile |

## Perché XNull

- **Gestione della memoria decisa dal compilatore.** Il codice sorgente non esprime la forza dei riferimenti. Il compilatore sceglie stack, ARC o GC per ogni oggetto tramite la tabella DET-01; il runtime esegue la decisione.
- **Nessun pattern accessor.** I campi sono dati; il comportamento sono metodi con nome verbale. Getter e setter non sono esprimibili.
- **Composizione invece dell’ereditarietà.** Le classi non supportano l’ereditarietà con override. Il polimorfismo passa solo dai protocolli.
- **Gli errori sono valori.** `Result<T,E>`, `try`, `defer`/`errdefer`. Nessuna eccezione, nessuna propagazione implicita.
- **Nessuna riflessione.** Se il sorgente e la specifica non lo determinano, non fa parte del linguaggio.
- **Ogni decisione è documentata.** La specifica registra ciò che XNull supporta, ciò che rifiuta e perché. Originali in cinese con traduzioni in inglese; altre traduzioni sono benvenute.

## Avvio rapido

```sh
# dalla radice del repository
./src/cli/xnull run src/examples/hello.x
```

```text
hello, XNull
1 + 2 = 3
```

La CLI supporta tre engine:

```sh
```

- `mini` — il nuovo compilatore minimale.


## Struttura del repository

```text
assets/               logo e risorse del progetto
docs/                 documenti di architettura, linguaggio e design
README/               README tradotti
ide/                  estensione VS Code e web IDE
src/                  albero di sviluppo
  cli/xnull           CLI unificata
  mini/               compilatore minimale self-hosting
  runtime/            sorgenti e header del runtime C
  xdk/                sorgenti XDK
  ffi/                bridge FFI raw (.xfb)
  toolchain/          script di build e packaging
  examples/           esempi eseguibili

xdk/                  pacchetto di distribuzione XDK
  lib/xdk/            sorgenti dei pacchetti XDK
  runtime/            sorgenti e header del runtime C
  ffi/                bridge FFI raw
  install.sh          installer POSIX sh
```

`src/` è il punto di modifica; `xdk/` è la copia di distribuzione. Dopo aver modificato `src/xdk/`, sincronizzala con `xdk/lib/xdk/`.

## Sviluppo

`src/` è l'albero di sviluppo; `xdk/` è la copia di distribuzione. Dopo aver modificato `src/xdk/`, sincronizzalo con `xdk/lib/xdk/`.


### Installare XDK

```sh
cd xdk
./install.sh --prefix "$HOME/.local"
```

Viene installato in:

```text
<prefix>/share/xnull/xdk
<prefix>/share/xnull/runtime
<prefix>/share/xnull/ffi
```

Per il packaging usare `DESTDIR`:

```sh
DESTDIR=/tmp/xdk-pkg ./install.sh --prefix /usr/local
```

## Stato attuale

| Area | Stato |
| --- | --- |
| Specifiche S1–S6 | Formali; S3 §14 elenca decisioni aperte |
| Catalogo XDK S7 | v3.0.0 bozza; prima il core T0 |
| Toolchain S8 / IDE S9 | Bozza |
| Configurazione progetto S10 | Finale v5.3.0 |
| Toolchain C nativa | Attiva per gli scenari core attuali |
| Compilatore minimale | Linguaggio core + classi di base; copertura in espansione |
| Scenari end-to-end | hello, classi, `import xdk.errors` funzionano; altro in corso |
| Self-hosting | Pianificato |

## Esplicitamente non supportato (per design)

| Funzionalità | Motivo |
| --- | --- |
| Override dei metodi | “Quale metodo è stato realmente eseguito?” deve essere risolvibile dai tipi statici; la dispatch dinamica esiste solo tramite protocolli |
| Accessor / proprietà | Separazione a livello di grammatica: i campi sono dati, il comportamento sono metodi con nome verbale |
| Riflessione | Rompe l’assioma “sorgente + specifica determinano tutto” |
| Eccezioni | Gli errori sono valori: `Result` + `try`; `throw` è solo fatale e non srotola lo stack |

## Roadmap

1. Backend C nativo: un file compila in C, il C compila in un binario, il binario produce il risultato.
2. Completamento incrementale: guidato da scenari eseguibili, non da checklist di funzionalità.
3. Self-hosting: il compilatore riscritto in XNull.

## Investimento angelico

XNull è alla ricerca di un piccolo round angelico o di supporto non diluitivo per finanziare 12–18 mesi di lavoro su compilatore, self-hosting, runtime e XDK. L’obiettivo è ristretto: rendere la toolchain esistente corretta, veloce e utilizzabile prima di espandere il linguaggio.

Se sei interessato, scrivi a **vjsplus@163.com** con oggetto `XNull Angel`. I termini si discutono in privato.

> Questa sezione è solo informativa e non costituisce un’offerta di vendita di valori mobiliari né un invito a offrirne l’acquisto.

## Sostegno

Se XNull ti è utile, un piccolo contributo è benvenuto. Anche poco aiuta.

WeChat Pay (Cina continentale):

<img src="../assets/wechat-pay.jpg" alt="Codice QR per sostenere il progetto con WeChat Pay" width="260">

> Il sostegno è volontario, non è un investimento e non comporta alcuna promessa di rendimento.

## Contribuire

XNull è nato come progetto di design individuale. La fase successiva richiede ingegneri del compilatore, ingegneri del runtime, progettisti XDK/API, critici del design, autori e traduttori. Se pensi che una decisione sia sbagliata, porta un controesempio; un buon argomento diventa una revisione della specifica.

Contatto: vjsplus@163.com · [GitHub Issues](https://github.com/xnull-clang/xnull/issues)

## Licenza

Il codice (`src/`, `xdk/`, `src/examples/`) è rilasciato con licenza Apache-2.0; vedi [LICENSE](../LICENSE). Specifiche e documentazione (`docs/`, `README*.md`) sono rilasciate con licenza CC BY 4.0; vedi [LICENSE-docs.md](../LICENSE-docs.md). Il nome e il logo XNull non sono coperti da queste licenze.
