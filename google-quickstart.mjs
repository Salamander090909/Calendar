import path from "node:path";
import process from "node:process";
import { authenticate } from "@google-cloud/local-auth";
import { google } from "googleapis";

const SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"];
const CREDENTIALS_PATH = path.join(process.cwd(), "credentials.json");

async function listEvents() {
  console.log("Starter Google-innlogging...");
  console.log("Hvis ingen nettleser apnes, sjekk om et vindu eller en ny fane ligger i bakgrunnen.");

  const auth = await authenticate({
    scopes: SCOPES,
    keyfilePath: CREDENTIALS_PATH
  });

  console.log("Innlogging fullfort. Henter kalenderhendelser...");

  const calendar = google.calendar({ version: "v3", auth });
  const result = await calendar.events.list({
    calendarId: "primary",
    timeMin: new Date().toISOString(),
    maxResults: 10,
    singleEvents: true,
    orderBy: "startTime"
  });

  const events = result.data.items || [];
  if (events.length === 0) {
    console.log("Ingen kommende hendelser funnet.");
    return;
  }

  for (const event of events) {
    const start = event.start?.dateTime ?? event.start?.date;
    console.log(`${start} - ${event.summary}`);
  }
}

await listEvents();
