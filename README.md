# Urlaubskasse (schlank)

Ein eigenständiges Flutter-Projekt für **Ausgaben + Abrechnung**, das auf deine
bestehende Supabase-Datenbank zugreift. Es ist ein **Neubau** der Funktionen –
nicht dein Original-Code – und behebt dabei den Anzeige-Bug: Ausgaben werden
über `trip_id` geladen, also sehen **alle** Beteiligten alle Kosten, nicht nur
der Zahler.

## Was drin ist
- Liste aller Ausgaben der Reise (mit Zahler und Beteiligten)
- Abrechnung: Stand pro Person + „wer schuldet wem wie viel"
- Neue Ausgabe eintragen (Zahler, Beteiligte, gleichmäßig / Anteile / feste Beträge)

Nur diese Supabase-Tabellen werden genutzt: `urlaub_trips`, `urlaub_persons`,
`urlaub_expenses`, `urlaub_expense_participants`.

## 1. Supabase-Daten eintragen
Zwei Wege (einer reicht):

**A) Direkt im Code** — `lib/config.dart` öffnen und `supabaseUrl` +
`supabaseAnonKey` eintragen (Supabase → Project Settings → API).

**B) In Codemagic** — die Werte als Umgebungsvariablen `SUPABASE_URL` und
`SUPABASE_ANON_KEY` setzen (in `codemagic.yaml` sind die Platzhalter markiert).
Der Build reicht sie dann per `--dart-define` durch.

## 2. In Git packen
```bash
cd urlaubskasse_app
git init
git add .
git commit -m "Urlaubskasse: Ausgaben + Abrechnung"
# Neues leeres Repo auf GitHub anlegen, dann:
git remote add origin https://github.com/DEINNAME/urlaubskasse.git
git branch -M main
git push -u origin main
```

## 3. Mit Codemagic bauen
1. Auf codemagic.io mit GitHub anmelden, das Repo hinzufügen.
2. Codemagic erkennt die `codemagic.yaml` automatisch.
3. Build starten. Der Pipeline-Schritt erzeugt zuerst den `android/`-Ordner
   (liegt bewusst nicht im Repo), stellt die Internet-Berechtigung sicher und
   baut dann die Release-APK.
4. Nach dem Build die APK unter „Artifacts" herunterladen.

Die APK ist mit dem Debug-Schlüssel signiert – zum Sideloaden auf eigene Geräte
völlig ausreichend (kein Play-Store-Upload nötig). Zum Installieren auf dem
Handy ggf. „Unbekannte Quellen / Aus dieser Quelle installieren" erlauben.

## Hinweise
- Getestet werden konnte das Projekt vor der Übergabe nicht kompiliert – falls
  der erste Build meckert, schick mir das Codemagic-Log, dann fixe ich es.
- Die Aufteilungslogik interpretiert `share`/`split_method` nach bestem Wissen.
  Stimmt eine Abrechnungssumme nicht, kurz Bescheid geben.
- Lokal bauen geht auch (`flutter create --platforms=android .` einmalig, dann
  `flutter run`), ist aber nicht der vorgesehene Weg.
