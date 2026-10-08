#!/usr/bin/env python3
"""
Generate the dashboard access codes (one regional-admin code set + one code per country).

    python scripts/generate_access_codes.py                 # first time: new codes for everyone
    python scripts/generate_access_codes.py --rotate NGA    # give Nigeria a new code, keep the rest
    python scripts/generate_access_codes.py --rotate ADMIN  # new admin code(s)
    python scripts/generate_access_codes.py                 # run again later: keeps existing codes, adds any new country

What it writes / prints
  * config/access_codes.private.csv  -- the master list (key, country, code). It is git-ignored: keep it
    private (the regional office only) and send each country ONLY its own code.
  * It prints the two secret values to paste into Posit Connect Cloud
    (content -> Settings -> Secrets):   IM_ADMIN_CODES   and   IM_COUNTRY_CODES
    After saving the secrets, restart/redeploy the content so they take effect.

The codes are random (secrets module), 12 characters from an alphabet without look-alike
characters (no 0/O, 1/I/L), written XXXX-XXXX-XXXX. Never commit config/access_codes.private.csv
or paste the codes into any tracked file.
"""
import argparse
import csv
import secrets
import sys
from pathlib import Path

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # 31 chars, no 0 O 1 I L
ROOT = Path(__file__).resolve().parent.parent
MAP_CSV = ROOT / "config" / "country_forms.csv"
PRIVATE_CSV = ROOT / "config" / "access_codes.private.csv"


def new_code() -> str:
    raw = "".join(secrets.choice(ALPHABET) for _ in range(12))
    return "-".join(raw[i:i + 4] for i in range(0, 12, 4))


def read_map():
    with open(MAP_CSV, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return {r["country_key"].strip().upper(): r["country_name"].strip() for r in rows}


def read_existing():
    admin, country = [], {}
    if PRIVATE_CSV.exists():
        with open(PRIVATE_CSV, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                key = r["key"].strip().upper()
                if key == "ADMIN":
                    admin.append(r["code"].strip())
                else:
                    country[key] = r["code"].strip()
    return admin, country


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--admin", type=int, default=2, help="number of admin codes to create when none exist (default 2)")
    ap.add_argument("--rotate", default="", help="comma-separated keys to re-issue, e.g. NGA,AGO or ADMIN")
    args = ap.parse_args()

    names = read_map()
    admin, country = read_existing()
    rotate = {k.strip().upper() for k in args.rotate.split(",") if k.strip()}
    unknown = rotate - set(names) - {"ADMIN"}
    if unknown:
        print(f"Unknown key(s): {', '.join(sorted(unknown))}. Valid keys: ADMIN, {', '.join(sorted(names))}", file=sys.stderr)
        return 2

    if "ADMIN" in rotate or not admin:
        admin = [new_code() for _ in range(max(1, args.admin))]
    for key in names:
        if key in rotate or key not in country:
            country[key] = new_code()
    country = {k: v for k, v in country.items() if k in names}

    all_codes = admin + list(country.values())
    if len(set(all_codes)) != len(all_codes):          # astronomically unlikely, but never ship a clash
        print("Duplicate code generated - run again.", file=sys.stderr)
        return 1

    with open(PRIVATE_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["key", "country", "code"])
        for c in admin:
            w.writerow(["ADMIN", "Regional office", c])
        for k in sorted(country):
            w.writerow([k, names[k], country[k]])

    print(f"Wrote {PRIVATE_CSV}  (PRIVATE - git-ignored)\n")
    print("Paste these two values into Posit Connect Cloud -> Settings -> Secrets:\n")
    print("IM_ADMIN_CODES")
    print(";".join(admin))
    print("\nIM_COUNTRY_CODES")
    print(";".join(f"{k}={country[k]}" for k in sorted(country)))
    print("\nThen restart the content so the secrets take effect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
