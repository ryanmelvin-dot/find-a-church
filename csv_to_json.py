import csv
import json
from pathlib import Path

"""
Simple CSV -> JSON helper for the Find a Church project.

Usage (from this folder):
  1. Update the paths below to point to your two CSV exports.
  2. Run:
       python csv_to_json.py
  3. Copy the printed JSON arrays into CHURCHES and SERVICES in scripts.js.
"""

# TODO: Update these to your actual CSV locations
CHURCHES_CSV = Path(r"c:\Users\Ramel\Downloads\report1773167544362.csv")
SERVICES_CSV = Path(r"c:\Users\Ramel\Downloads\report1773167579946.csv")


def load_churches(path: Path):
  churches = []
  with path.open(newline="", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
      gcfa = (row.get("GCFA#") or "").strip()
      if not gcfa:
        continue
      churches.append(
        {
          "gcfa": gcfa,
          "name": (row.get("Account Name") or "").strip(),
          "district": (row.get("District") or "").strip(),
          "phone": (row.get("Phone") or "").strip(),
          "email": (row.get("Primary Email") or "").strip(),
          "street": (row.get("Physical Address (Street)") or "").strip(),
          "city": (row.get("Physical Address (City)") or "").strip(),
          "state": (row.get("Physical Address (State/Province)") or "").strip(),
          "zip": (row.get("Physical Address (ZIP/Postal Code)") or "").strip(),
        }
      )
  return churches


def load_services(path: Path):
  services = []
  with path.open(newline="", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
      gcfa = (row.get("GCFA#") or "").strip()
      if not gcfa:
        continue
      services.append(
        {
          "gcfa": gcfa,
          "serviceName": (row.get("Service Name") or "").strip(),
          "serviceTime": (row.get("Service Time") or "").strip(),
          "serviceDay": (row.get("Service Day") or "").strip(),
          "serviceType": (row.get("Service Type") or "").strip(),
        }
      )
  return services


def main():
  churches = load_churches(CHURCHES_CSV)
  services = load_services(SERVICES_CSV)

  print("# --- Paste this into scripts.js as CHURCHES ---")
  print("CHURCHES = ")
  print(json.dumps(churches, indent=2))
  print("\n# --- Paste this into scripts.js as SERVICES ---")
  print("SERVICES = ")
  print(json.dumps(services, indent=2))


if __name__ == "__main__":
  main()

