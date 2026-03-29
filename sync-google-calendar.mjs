import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { authenticate } from "@google-cloud/local-auth";
import { google } from "googleapis";

const SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"];
const ROOT = process.cwd();
const CREDENTIALS_PATH = path.join(ROOT, "credentials.json");
const TOKEN_PATH = path.join(ROOT, "token.json");
const CONFIG_PATH = path.join(ROOT, "calendar-config.json");
const CACHE_PATH = path.join(ROOT, "calendar-cache.json");

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function readJson(filePath) {
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw);
}

async function loadSavedCredentialsIfExist() {
  if (!(await fileExists(TOKEN_PATH))) {
    return null;
  }

  const saved = await readJson(TOKEN_PATH);
  return google.auth.fromJSON(saved);
}

async function saveCredentials(client) {
  const keys = await readJson(CREDENTIALS_PATH);
  const key = keys.installed || keys.web;

  if (!key) {
    throw new Error("credentials.json mangler installed/web-konfigurasjon.");
  }

  const payload = {
    type: "authorized_user",
    client_id: key.client_id,
    client_secret: key.client_secret,
    refresh_token: client.credentials.refresh_token
  };

  await fs.writeFile(TOKEN_PATH, JSON.stringify(payload, null, 2), "utf8");
}

function startOfToday() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
}

function endOfToday() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
}

function formatLocalTime(value) {
  const date = new Date(value);
  return new Intl.DateTimeFormat("nb-NO", {
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function normalizeEvent(event) {
  const isAllDay = Boolean(event.start?.date);
  const startValue = isAllDay ? event.start.date : event.start.dateTime;
  const endValue = isAllDay ? event.end.date : event.end.dateTime;

  return {
    id: event.id,
    summary: event.summary || "(Uten tittel)",
    location: event.location || "",
    description: event.description || "",
    htmlLink: event.htmlLink || "",
    start: {
      value: startValue,
      label: isAllDay ? "Hele dagen" : formatLocalTime(startValue),
      allDay: isAllDay
    },
    end: {
      value: endValue,
      label: isAllDay ? "Hele dagen" : formatLocalTime(endValue),
      allDay: isAllDay
    }
  };
}

async function getAuth() {
  const existingClient = await loadSavedCredentialsIfExist();
  if (existingClient) {
    return existingClient;
  }

  const client = await authenticate({
    scopes: SCOPES,
    keyfilePath: CREDENTIALS_PATH
  });

  if (client.credentials?.refresh_token) {
    await saveCredentials(client);
  }

  return client;
}

async function readConfig() {
  if (!(await fileExists(CONFIG_PATH))) {
    return {
      calendarIds: ["primary"],
      includeAllDay: true,
      maxResultsPerCalendar: 20
    };
  }

  return readJson(CONFIG_PATH);
}

async function writeCache(payload) {
  await fs.writeFile(CACHE_PATH, JSON.stringify(payload, null, 2), "utf8");
}

async function syncCalendar() {
  if (!(await fileExists(CREDENTIALS_PATH))) {
    throw new Error("Legg inn credentials.json fra Google Cloud i prosjektmappen først.");
  }

  const auth = await getAuth();
  const config = await readConfig();
  const calendar = google.calendar({ version: "v3", auth });
  const calendarIds = Array.isArray(config.calendarIds) && config.calendarIds.length > 0
    ? config.calendarIds
    : ["primary"];

  const timeMin = startOfToday().toISOString();
  const timeMax = endOfToday().toISOString();
  const collected = [];

  for (const calendarId of calendarIds) {
    const result = await calendar.events.list({
      calendarId,
      timeMin,
      timeMax,
      singleEvents: true,
      orderBy: "startTime",
      maxResults: config.maxResultsPerCalendar || 20
    });

    const items = result.data.items || [];
    for (const item of items) {
      const isAllDay = Boolean(item.start?.date);
      if (isAllDay && config.includeAllDay === false) {
        continue;
      }

      collected.push({
        calendarId,
        ...normalizeEvent(item)
      });
    }
  }

  collected.sort((a, b) => {
    const aValue = new Date(a.start.value).getTime();
    const bValue = new Date(b.start.value).getTime();
    return aValue - bValue;
  });

  const payload = {
    status: "ok",
    generatedAt: new Date().toLocaleString("nb-NO"),
    tokenPath: TOKEN_PATH,
    events: collected
  };

  await writeCache(payload);
  return payload;
}

async function main() {
  try {
    const payload = await syncCalendar();
    console.log(`Synket ${payload.events.length} kalenderhendelser.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await writeCache({
      status: "error",
      generatedAt: new Date().toLocaleString("nb-NO"),
      message,
      events: []
    });
    console.error(message);
    process.exitCode = 1;
  }
}

await main();
