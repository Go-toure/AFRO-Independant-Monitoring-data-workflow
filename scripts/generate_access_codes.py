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

Code styles (random choice with the secrets module in every style):
  default / --style afro    readable like your focal-point tokens:
                              country   AGO-2026-K7M2QX      (country key - year - 6 random characters)
                              admin     AFRO-ADMIN-2026-K7M2QX
                            codes are UPPER CASE and case-sensitive; the 6 random characters never use
                            look-alike letters/digits (no 0 O 1 I L)
  --admin-code "TEXT"       use exactly this admin code instead of a generated one (12+ characters).
                            Not recommended for a fixed text such as AFRO-ADMIN-2025: anyone who guesses
                            it sees every country's data. Keep a random tail.
  --style words             three easy words + two digits, all lowercase, e.g.  lake-tiger-moon-47
                            (easy to read out on the phone and to type; about 30 bits)
  --style random            12 characters XXXX-XXXX-XXXX from an alphabet without look-alike
                            characters (hardest to guess; harder to type)
    python scripts/generate_access_codes.py --regenerate   # replace EVERY existing code with new ones
Never commit config/access_codes.private.csv or paste the codes into any tracked file.
"""
import argparse
import csv
import secrets
import sys
from pathlib import Path

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # 31 chars, no 0 O 1 I L
WORDS = (
    "apple river tiger maple cloud stone eagle lemon panda piano "
    "ocean sunny green blue brave candy daisy dream earth flame "
    "forest frog garden ginger grape happy honey island jelly jungle "
    "kite lake leaf light lion lucky magic mango melon mirror "
    "moon mouse music night noble olive orange otter pearl pepper "
    "pilot plant plum pond quiet rabbit rain robin rocket rose "
    "sand shell silver smile snow spark spring star storm sugar "
    "summer swan table tulip valley velvet violet water wave wind "
    "winter wolf yellow zebra bread brick bridge brush cabin camel "
    "carpet castle cedar chair cherry circle clover coast copper coral "
    "cotton crown dance desert diamond dolphin dragon drum duck falcon "
    "feather field finch flower giant glass gold goose hammer harbor "
    "hawk heart hill horse house ivory jacket kitten ladder lantern "
    "lime linen marble meadow mint monkey nest nickel oasis orbit "
    "palm paper parrot peach pebble pine planet pocket prism pumpkin "
    "puzzle quartz raven ribbon ring road salmon scarf shadow sheep "
    "ship silk sketch slate spider spoon square stream sunset swift "
    "tent thunder timber toast tower train trumpet turtle walnut whale "
    "window wing wizard yacht young zephyr amber anchor arrow basket "
    "beach berry bicycle bird bloom boat bonfire breeze bubble button "
    "candle canyon canoe carrot cheese clock coconut comet compass cookie "
    "crystal curry doctor engine fabric fiddle fire fish flute galaxy "
    "gate guitar hazel hero igloo jewel ketchup kettle koala llama "
    "lotus magnet mask napkin needle noodle nutmeg onion orchid paddle "
    "pencil picnic pillow pirate popcorn pretzel pudding radish rhythm saddle "
    "salad sailor sandal sausage season shovel signal spice sponge statue "
    "sweater teapot ticket tomato trail tunnel vanilla village violin voyage "
    "wallet wheel whistle willow yogurt zipper "
).split()

ROOT = Path(__file__).resolve().parent.parent
MAP_CSV = ROOT / "config" / "country_forms.csv"
PRIVATE_CSV = ROOT / "config" / "access_codes.private.csv"


STYLE = "afro"
YEAR = str(__import__("datetime").date.today().year)


def rand_tail(n: int = 6) -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(n))


def new_code(key: str = "") -> str:
    if STYLE == "afro":
        return f"{key or 'AFRO-ADMIN'}-{YEAR}-{rand_tail()}" if key else f"AFRO-ADMIN-{YEAR}-{rand_tail()}"
    if STYLE == "words":
        return "-".join(secrets.choice(WORDS) for _ in range(3)) + "-%02d" % (10 + secrets.randbelow(90))
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
    ap.add_argument("--style", choices=("afro", "words", "random"), default="afro", help="code style (default: afro, e.g. AGO-2026-K7M2QX)")
    ap.add_argument("--admin-code", default="", help="use exactly this admin code (12-128 characters) instead of generating one")
    ap.add_argument("--regenerate", action="store_true", help="replace ALL existing codes (admin and countries)")
    args = ap.parse_args()
    global STYLE
    STYLE = args.style

    names = read_map()
    admin, country = read_existing()
    if args.regenerate:
        admin, country = [], {}
    rotate = {k.strip().upper() for k in args.rotate.split(",") if k.strip()}
    unknown = rotate - set(names) - {"ADMIN"}
    if unknown:
        print(f"Unknown key(s): {', '.join(sorted(unknown))}. Valid keys: ADMIN, {', '.join(sorted(names))}", file=sys.stderr)
        return 2

    if "ADMIN" in rotate or not admin:
        if args.admin_code:
            if not (12 <= len(args.admin_code) <= 128):
                print("--admin-code must be 12 to 128 characters long.", file=sys.stderr)
                return 2
            admin = [args.admin_code]
            if __import__("re").fullmatch(r"[A-Za-z _-]+-?\d{0,4}", args.admin_code):
                print("WARNING: that admin code looks guessable (a fixed phrase and a year). Anyone who guesses it "
                      "sees ALL countries' data - prefer the generated one.\n", file=sys.stderr)
        else:
            admin = [new_code() for _ in range(max(1, args.admin))]
    for key in names:
        if key in rotate or key not in country:
            country[key] = new_code(key)
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
