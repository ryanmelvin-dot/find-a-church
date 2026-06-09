/**
 * Netlify serverless function — Airtable proxy (Functions 2.0 syntax)
 *
 * The Airtable token is stored as a Netlify environment variable (AIRTABLE_TOKEN).
 * It is NEVER sent to the browser. The browser calls this function instead of
 * calling Airtable directly.
 *
 * Endpoint: GET /.netlify/functions/churches
 *   Append ?debug=1 to include table field names in the response
 *   (useful when diagnosing Airtable column renames).
 */

const BASE_ID        = process.env.AIRTABLE_BASE_ID;
const TOKEN          = process.env.AIRTABLE_TOKEN;
const CHURCHES_TABLE = process.env.CHURCHES_TABLE || "Churches";
const SERVICES_TABLE = process.env.SERVICES_TABLE || "Services";

// Fetch all records from a table, handling Airtable's 100-record pagination
async function fetchTable(tableName) {
  const records = [];
  let offset    = null;

  do {
    const url = `https://api.airtable.com/v0/${BASE_ID}/${encodeURIComponent(tableName)}`
      + (offset ? `?offset=${encodeURIComponent(offset)}` : "");

    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${TOKEN}` },
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`Airtable ${res.status} on "${tableName}": ${body}`);
    }

    const json = await res.json();
    records.push(...json.records);
    offset = json.offset || null;
  } while (offset);

  return records;
}

export default async function handler(req) {
  // Only allow GET requests
  if (req.method !== "GET") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Guard: environment variables must be configured
  if (!BASE_ID || !TOKEN) {
    console.error("Missing AIRTABLE_BASE_ID or AIRTABLE_TOKEN environment variables.");
    return Response.json({ error: "Server configuration error." }, { status: 500 });
  }

  try {
    const [churchRecords, serviceRecords] = await Promise.all([
      fetchTable(CHURCHES_TABLE),
      fetchTable(SERVICES_TABLE),
    ]);

    // Log counts server-side (visible in Netlify function logs)
    console.log(`Fetched ${churchRecords.length} church records and ${serviceRecords.length} service records.`);

    const payload = {
      churches: churchRecords,
      services: serviceRecords,
    };

    // Schema diagnostics are opt-in (?debug=1) so field names aren't
    // advertised to every caller of this public endpoint.
    if (new URL(req.url).searchParams.get("debug") === "1") {
      payload._debug = {
        churchCount:   churchRecords.length,
        serviceCount:  serviceRecords.length,
        churchFields:  churchRecords.length  ? Object.keys(churchRecords[0].fields)  : [],
        serviceFields: serviceRecords.length ? Object.keys(serviceRecords[0].fields) : [],
      };
    }

    return Response.json(payload, {
      headers: {
        // Browsers always revalidate; Netlify's CDN serves a shared copy for
        // 5 minutes — keeps traffic off Airtable's 5 req/sec rate limit.
        "Cache-Control": "public, max-age=0, must-revalidate",
        "Netlify-CDN-Cache-Control": "public, s-maxage=300, stale-while-revalidate=60",
      },
    });
  } catch (err) {
    console.error(err);
    return Response.json({ error: "Failed to fetch data from Airtable." }, { status: 502 });
  }
}
