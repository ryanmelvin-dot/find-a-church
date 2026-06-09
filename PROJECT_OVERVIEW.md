# Find a Church — Indiana Conference UMC
## Project Overview & How It Works

---

## What Was Built

A public-facing **"Find a Church" web directory** for the Indiana Conference of The United Methodist Church. The site allows anyone to search and browse churches across Indiana, filtering by service day, service time, and district, with three display options: Cards, List, and Map.

The site is themed to match **INUMC.org** — dark charcoal header, red accent color (#f61b37), gold secondary accent, Poppins body font, and Lora serif headings — giving it a consistent, on-brand look and feel.

---

## Files in This Project

| File | Purpose |
|---|---|
| `index.html` | The public-facing webpage — all layout and structure |
| `styles.css` | All visual styling, colors, fonts, and responsive layout |
| `scripts.js` | All JavaScript logic — fetches data, filters, and renders views |
| `netlify/functions/churches.js` | Secure serverless function — calls Airtable API server-side |
| `netlify.toml` | Netlify deployment configuration |
| `.env` | Local development secrets (never committed to git) |
| `.gitignore` | Prevents secrets and junk files from being committed |

---

## How the Data Works — Live Airtable Integration

### The key idea: update Airtable, the website updates automatically

The website has no local copy of church data baked into the code. Instead, every time a visitor opens the page, it makes a live request to Airtable and fetches the most current data. **No code changes, no redeployment — just update Airtable and it's live.**

### Data structure in Airtable

The directory uses two tables inside one Airtable base, joined together by the `GCFA#` field (the unique identifier for each church):

**Churches table** — one row per church
- `GCFA#` — unique church identifier (the join key)
- `Account Name` — church name
- `District` — conference district
- `Phone`
- `Primary Email`
- `Physical Address (Street)`, `(City)`, `(State/Province)`, `(ZIP/Postal Code)`
- `Website`

**Services table** — one row per worship service (a church can have multiple)
- `GCFA#` — links back to the church
- `Service Name` — e.g., "Sunday Morning Worship"
- `Service Time` — e.g., "9:00 AM"
- `Service Day` — e.g., "Sunday"
- `Service Type` — e.g., "In-Person", "Online"

When the page loads, the code fetches both tables, matches each service to its church using the `GCFA#` field, and displays the combined result as a card, list row, or map pin.

---

## How the Security Works

A major concern with web directories is keeping API credentials out of the hands of the public. Here is how that is handled:

### The problem with putting tokens in a website
Any value written directly in a `.js` file is visible to anyone who opens their browser's developer tools. Putting an Airtable API token in the JavaScript code would mean anyone could copy it and read (or write to) your Airtable base.

### The solution: a serverless proxy function
Rather than calling Airtable directly from the browser, the website calls a **Netlify serverless function** (`netlify/functions/churches.js`) hosted on your own Netlify site.

```
Visitor's browser
      │
      │  GET /.netlify/functions/churches
      ▼
Netlify server  ◄── AIRTABLE_TOKEN lives here (environment variable, never sent to browser)
      │
      │  GET https://api.airtable.com/v0/...
      ▼
Airtable API
      │
      │  Returns church + service records
      ▼
Netlify server packages the data as JSON
      │
      ▼
Visitor's browser receives clean JSON — no token ever exposed
```

The Airtable token is stored as a **Netlify environment variable** — it exists only on Netlify's servers and is injected into the function at runtime. It is never included in the files that are sent to visitors.

---

## How to Update Church Data

**No developer or code change needed.** Anyone with access to the Airtable base can:

- **Add a new church** → add a row to the Churches table
- **Update a service time** → edit the row in the Services table
- **Remove a church** → delete its row from both tables
- **Add a new service** → add a row to the Services table with the matching `GCFA#`

The next time anyone visits the website, they will see the updated data. Changes are reflected **within seconds** of being saved in Airtable (subject to a 5-minute CDN cache on Netlify, which improves performance by reducing the number of calls to Airtable).

---

## What Users Can Do on the Website

### Search
A text search bar filters results by church name, city, ZIP code, district, or service name simultaneously.

### Filters
- **Service Day** — filter by day of the week (Sunday, Saturday, Wednesday, etc.)
- **Service Time** — filter by time of day (Morning 6am–Noon, Afternoon 12–6pm, Evening 6pm+)
- **District** — a dropdown populated dynamically from whatever districts exist in Airtable at the time of the page load

### Three view modes
| View | What it shows |
|---|---|
| **Cards** | Visual cards with church name, location, service details, and contact links |
| **List** | Compact table view — good for scanning a large number of results |
| **Map** | Side-by-side list and embedded Google Map — click any church to see its location |

---

## Deployment

The site is hosted on **Netlify** (free tier is sufficient). Netlify handles:
- Serving the HTML, CSS, and JS files
- Running the serverless function that proxies Airtable requests
- Storing the API token securely as an environment variable
- A 5-minute CDN cache on the function response to reduce Airtable API calls

### Environment variables required in Netlify
Set these under **Site configuration → Environment variables**:

| Variable | Value |
|---|---|
| `AIRTABLE_TOKEN` | Your Airtable Personal Access Token (read-only, scoped to this base) |
| `AIRTABLE_BASE_ID` | `appewRNunToaMj9Om` |
| `CHURCHES_TABLE` | `Churches` |
| `SERVICES_TABLE` | `Services` |

---

## Local Development

To run the site on your own computer (the serverless function requires a local server — you cannot just open `index.html` as a file):

1. Make sure Node.js is installed
2. Install the Netlify CLI: `npm install -g netlify-cli`
3. Fill in your `.env` file with a valid token and base ID
4. Run `netlify dev` from the project folder
5. Open `http://localhost:8888` in your browser

---

## Technology Used

| Technology | Role |
|---|---|
| HTML / CSS / JavaScript | Frontend — no framework, no build step |
| Poppins (Google Fonts) | Body text font |
| Lora (Google Fonts) | Heading font (matches INUMC.org serif style) |
| Airtable | Data backend — stores all church and service records |
| Airtable REST API | How the serverless function reads data |
| Netlify Functions | Serverless proxy — keeps the API token secure |
| Netlify Hosting | Static site hosting + function runtime |
| Google Maps (embed) | Map view — no API key required |

---

## Contact for Data Updates

To report inaccuracies in the directory: **communications@inumc.org**

To update church or service records: log into Airtable and edit the Churches or Services table directly.

---

*Last updated: March 2026*
