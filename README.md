# TODO-sidepanel

Liten Windows-app i PowerShell som viser dagens oppgaver i et lite vindu pa hoyre side av skjermen.

## Kjor appen

```powershell
powershell -ExecutionPolicy Bypass -File .\app.ps1
```

Appen viser:

- manuelle TODO-er fra `tasks.json`
- dagens Google Calendar-hendelser fra `calendar-cache.json`

## Sett opp autostart

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-startup.ps1
```

Dette lager en snarvei i Windows Startup-mappen slik at appen starter nar du logger inn.

## Endre oppgaver

Rediger `tasks.json`.

- `weekdays` gir standardoppgaver per ukedag
- `overrides` lar deg overskrive en bestemt dato med format `yyyy-MM-dd`
- `task-state.json` blir laget automatisk og lagrer hva du har krysset av for dagen

## Koble til Google Calendar

Dette oppsettet bruker Googles anbefalte Node.js-oppsett for lokal desktop-autentisering med OAuth-klient for desktop-app. Du trenger derfor en egen `credentials.json` fra Google Cloud i prosjektmappen.

1. Lag en Google Cloud-prosjekt og aktiver Google Calendar API.
2. Lag en OAuth-klient av typen `Desktop app`.
3. Last ned JSON-filen og lagre den som `credentials.json` i denne mappen.
4. Installer pakkene:

```powershell
npm install
```

5. Kjor synk for forste gang:

```powershell
npm run sync:calendar
```

Forste gang apnes en nettleser der du logger inn med Google-kontoen din og godkjenner lesetilgang til kalenderen. Etter vellykket innlogging lagres token lokalt i `token.json`.

Du kan ogsa trykke `Sync Google` inne i appen etter at `npm install` og `credentials.json` er pa plass.

Hvis du vil teste med Googles minimale quickstart-flyt for feilsoking, kan du kjorе:

```powershell
npm.cmd run sync:test
```

## Kalenderinnstillinger

Rediger `calendar-config.json` for aa bestemme hvilke kalendere som skal leses.

Eksempel:

```json
{
  "calendarIds": [
    "primary",
    "jobb@group.calendar.google.com"
  ],
  "includeAllDay": true,
  "maxResultsPerCalendar": 20
}
```

Eksempel:

```json
"overrides": {
  "2026-03-30": [
    "Mote kl. 09:00",
    "Send ferdig rapport",
    "Trening kl. 18:00"
  ]
}
```
