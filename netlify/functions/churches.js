/**
 * Netlify serverless function — Airtable proxy
 *
 * The Airtable token is stored as a Netlify environment variable (AIRTABLE_TOKEN).
 * It is NEVER sent to the browser. The browser calls this function instead of
 * calling Airtable directly.
 *
 * Endpoint: GET /.netlify/functions/churches
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

exports.handler = async function (event) {
  // Only allow GET requests
  if (event.httpMethod !== "GET") {
    return { statusCode: 405, body: "Method Not Allowed" };
  }

  // Guard: environment variables must be configured
  if (!BASE_ID || !TOKEN) {
    console.error("Missing AIRTABLE_BASE_ID or AIRTABLE_TOKEN environment variables.");
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Server configuration error." }),
    };
  }

  try {
    const [churchRecords, serviceRecords] = await Promise.all([
      fetchTable(CHURCHES_TABLE),
      fetchTable(SERVICES_TABLE),
    ]);

    // Log counts server-side (visible in Netlify function logs)
    console.log(`Fetched ${churchRecords.length} church records and ${serviceRecords.length} service records.`);

    // Include field names from the first record of each table so the client
    // can detect mismatches between what the code expects and what Airtable has.
    const churchFields  = churchRecords.length  ? Object.keys(churchRecords[0].fields)  : [];
    const serviceFields = serviceRecords.length ? Object.keys(serviceRecords[0].fields) : [];

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        // Cache for 5 minutes on Netlify's CDN — reduces Airtable API calls
        "Cache-Control": "public, s-maxage=300, stale-while-revalidate=60",
      },
      body: JSON.stringify({
        churches: churchRecords,
        services: serviceRecords,
        _debug: {
          churchCount:  churchRecords.length,
          serviceCount: serviceRecords.length,
          churchFields,
          serviceFields,
        },
      }),
    };
  } catch (err) {
    console.error(err);
    return {
      statusCode: 502,
      body: JSON.stringify({ error: "Failed to fetch data from Airtable." }),
    };
  }
};
