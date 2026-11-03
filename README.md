# Peterson 3D Crash Simulator (Godot 4)

> **Didaktisches Showcase-Projekt:** Betriebssysteme (BS) & Interaktive Grafikanwendungen (IGA)  
> **Thema:** Wechselseitiger Ausschluss (Mutual Exclusion), Race Conditions & Peterson-Algorithmus  
> **Technologie:** Godot 4.7 (Forward+ / GL Compatibility für Web WASM), GDScript 2.0  
> **Kategorie:** `artifacts/consumers/education/godot/gd-godot-peterson`

---

## 🎮 Konzept: Die Eingleisbrücken-Metapher

Petersons Algorithmus löst das Problem des kritischen Abschnitts für zwei nebenläufige Prozesse ohne spezielle Hardware-Unterstützung (wie Test-and-Set) durch die Kombination aus **Interessensbekundung** (`interested[2]`) und einer **Höflichkeits-Variable** (`_turn`).

In diesem 3D-Simulator wird das abstrakte Konzept physisch begreifbar gemacht:
* **Thread 0 (Blau)** und **Thread 1 (Orange)** steuern Hochgeschwindigkeitszüge auf zwei parallelen Strecken.
* **Kritischer Abschnitt (Critical Section):** Eine schmale, eingleisige Brücke über eine tiefe Schlucht.
* **Sensoren (`interested[0]`, `interested[1]`):** Kontaktleisten vor der Brücke schalten bei Annäherung auf Leucht-Cyan bzw. Leucht-Orange um.
* **Höflichkeits-Weiche (`_turn`):** Eine 3D-Drehscheibe mit Richtungsanzeiger. Setzt ein Thread `_turn = other`, dreht sich der Pfeil zum anderen Gleis (*"Nach Ihnen!"*). Wer als Zweiter schreibt, gewährt dem Ersten den Vortritt.
* **Schranken & Signale:** Zeigt die Auswertung `while (interested[other] && _turn == other)` an, schließt sich die Schranke auf Rot und der Zug wartet aktiv mit rotierenden Rädern. Sobald der andere Zug die Brücke verlässt (`interested[other] = false`), öffnet sich die Schranke auf Grün.

---

## 🕹️ Interaktive Szenarien

1. **🛡️ 1. Peterson (Sicher):**
   * Beide Züge starten und führen die vollständige Peterson-Synchronisation aus.
   * Die Höflichkeitsvariable `_turn` bricht die Symmetrie deterministisch.
   * Ein Zug wartet an der Schranke, der andere passiert die Brücke. Keine Kollision ($0$ Crashes).
2. **💥 2. Unsynchronisiert (Race Condition Crash):**
   * Keine Synchronisation aktiv. Beide Züge rasen ungebremst auf die Brücke zu.
   * Physikalischer Zusammenstoß mit Screen-Shake und berstenden Trümmerteilen, die in den Abgrund stürzen.
   * Status: *"MUTUAL EXCLUSION VERLETZT!"*.
3. **⚠️ 3. Ohne Turn (Deadlock / Livelock):**
   * Naive Synchronisation nur mit `interested[0]` und `interested[1]` (ohne `_turn`).
   * Beide Züge bekunden Interesse und warten endlos aufeinander an der Haltelinie.
4. **⏭️ 4. Einzelschritt-Modus (Step-by-Step):**
   * Manuelles Durchsteppen jeder einzelnen Anweisung.
   * Codezeilen in den Swimlanes werden synchron zum 3D-Zustand farblich hervorgehoben.

---

## 🧪 Headless-Testlauf

Das Projekt enthält eine vollständige, automatisierte Test-Suite, die alle 4 Szenarien headless verifiziert:

```bash
godot --headless -s test_gameplay.gd
```

---

## 🌐 Web-Export (WASM / GitHub Pages)

Das Projekt ist für den Godot 4 Web-Export (`gl_compatibility`) vorkonfiguriert und wird via GitHub Action (`.github/workflows/export.yml`) als statisches WebAssembly-Bundle auf GitHub Pages publiziert. Es kann direkt per `<iframe>` in Quarto-Vorlesungsfolien (z. B. `md/quarto/bs/`) eingebettet werden.
