/**
 * Scheduled Netlify function — automatic geocoding
 *
 * Runs daily. Finds churches in Airtable that have an address but no
 * Latitude/Longitude, geocodes them with the free US Census API, and writes
 * the coordinates back into Airtable. The website reads those fields on every
 * load, so new churches get a dot on the map with no manual steps.
 *
 * Requirements:
 *   - "Latitude" and "Longitude" number fields on the Churches table
 *   - AIRTABLE_WRITE_TOKEN env var: a Personal Access Token scoped to this
 *     base with data.records:read AND data.records:write
 *     (the read-only AIRTABLE_TOKEN used by the churches function stays as-is)
 *
 * Coordinates can also be corrected by hand in Airtable — this function only
 * fills in rows where both fields are empty, so manual values are never
 * overwritten. Addresses the Census can't match are retried on later runs;
 * enter their coordinates manually to settle them.
 */

const BASE_ID        = process.env.AIRTABLE_BASE_ID;
const WRITE_TOKEN    = process.env.AIRTABLE_WRITE_TOKEN;
const CHURCHES_TABLE = process.env.CHURCHES_TABLE || "Churches";
const MAX_PER_RUN    = 15;   // keeps the run well inside the function time limit

export const config = {
  schedule: "0 11 * * *",   // daily at 11:00 UTC (~6am Eastern)
};

const tableUrl = () =>
  `https://api.airtable.com/v0/${BASE_ID}/${encodeURIComponent(CHURCHES_TABLE)}`;

async function fetchAllChurches() {
  const records = [];
  let offset = null;
  do {
    const url = tableUrl() + (offset ? `?offset=${encodeURIComponent(offset)}` : "");
    const res = await fetch(url, { headers: { Authorization: `Bearer ${WRITE_TOKEN}` } });
    if (!res.ok) throw new Error(`Airtable read ${res.status}: ${await res.text()}`);
    const json = await res.json();
    records.push(...json.records);
    offset = json.offset || null;
  } while (offset);
  return records;
}

async function geocodeAddress(street, city, state, zip) {
  const oneLine = [street, city, [state, zip].filter(Boolean).join(" ")]
    .filter(Boolean).join(", ");
  const url = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
    + `?address=${encodeURIComponent(oneLine)}`
    + "&benchmark=Public_AR_Current&format=json";
  const res = await fetch(url);
  if (!res.ok) return null;
  const json  = await res.json();
  const match = json?.result?.addressMatches?.[0];
  if (!match) return null;
  return {
    lat: Math.round(match.coordinates.y * 1e5) / 1e5,
    lng: Math.round(match.coordinates.x * 1e5) / 1e5,
  };
}

async function patchRecords(updates) {
  // Airtable allows at most 10 records per PATCH
  for (let i = 0; i < updates.length; i += 10) {
    const res = await fetch(tableUrl(), {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${WRITE_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ records: updates.slice(i, i + 10) }),
    });
    if (!res.ok) throw new Error(`Airtable write ${res.status}: ${await res.text()}`);
  }
}

export default async function handler() {
  if (!BASE_ID || !WRITE_TOKEN) {
    console.log("Geocoding skipped: AIRTABLE_WRITE_TOKEN (or AIRTABLE_BASE_ID) is not set.");
    return Response.json({ skipped: "missing configuration" });
  }

  const records = await fetchAllChurches();

  const pending = records.filter((r) => {
    const f = r.fields;
    const hasCoords  = f.Latitude != null && f.Longitude != null;
    const hasAddress = f["Physical Address (Street)"] && f["Physical Address (City)"];
    return !hasCoords && hasAddress;
  });

  if (!pending.length) {
    console.log(`All ${records.length} churches with addresses already have coordinates.`);
    return Response.json({ checked: records.length, geocoded: 0 });
  }

  // Shuffle so persistent Census misses don't permanently hog the per-run cap
  const batch = pending
    .map((r) => ({ r, k: Math.random() }))
    .sort((a, b) => a.k - b.k)
    .slice(0, MAX_PER_RUN)
    .map(({ r }) => r);

  const updates = [];
  for (const rec of batch) {
    const f = rec.fields;
    const coords = await geocodeAddress(
      f["Physical Address (Street)"],
      f["Physical Address (City)"],
      f["Physical Address (State/Province)"],
      f["Physical Address (ZIP/Postal Code)"]
    ).catch((err) => {
      console.error(`Geocode failed for ${f["Account Name"] || rec.id}: ${err.message}`);
      return null;
    });
    if (coords) {
      updates.push({ id: rec.id, fields: { Latitude: coords.lat, Longitude: coords.lng } });
    }
  }

  if (updates.length) await patchRecords(updates);

  console.log(
    `Geocoded ${updates.length} of ${batch.length} attempted ` +
    `(${pending.length - updates.length} still pending).`
  );
  return Response.json({
    checked: records.length,
    pending: pending.length,
    attempted: batch.length,
    geocoded: updates.length,
  });
}
