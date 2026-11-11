#!/usr/bin/env python3
"""Hotels import (الفنادق 2026.xlsx): customers, heater products, maintenance history.

  python3 scripts/import_hotels.py preview   -> reads the sheet, writes docs/hotels-import-preview.csv and prints a summary
  python3 scripts/import_hotels.py sql       -> also writes docs/hotels-import.sql (one transaction, nothing is run)
  python3 scripts/import_hotels.py apply     -> runs that SQL on SUPABASE_DB_URL (needs customers.notes: migration 0159)

The sheet is one block per hotel (a CODE row, then ~20 rows). Columns drift between rows, so every cell is read by what
it contains (a date, a phone number, "N x 300", ...). Only blocks with a hotel name are imported.
"""
import csv, datetime as dt, os, re, subprocess, sys, uuid, collections
import openpyxl

SRC = os.environ.get("HOTELS_XLSX", "/Users/mac/Downloads/الفنادق 2026.xlsx")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATEGORY_ID = "462a53da-3521-49c6-b95f-e26673a67fe1"   # سخانات
PIPELINE_ID = "fcb835d5-36ca-4ab0-a071-c4188b24ab13"
STAGE_ID = "f4f1b51e-5d30-40ad-9d21-34695bab74d2"      # تم التشغيل (what the earlier imports used)
# possible duplicates of customers that already exist (same place, different name): left out until decided
SKIP = {"H&A010", "H&A050"}
NEXT_MONTHS = 6                                         # next maintenance = latest maintenance + 6 months
SIZE = re.compile(r"(\d+)\s*[xX*×]\s*(\d+)")
SIZE_WORD = re.compile(r"(\d+)\s*(?:خزان|تانك|سخان)\s*(\d{3})")
MAINT_WORDS = ("صيانة", "صيانه", "زيت", "هيتر", "ثرموستات", "عامود", "جوان", "سفتى", "شيك بلف", "تنظيف", "تغيير")
isdate = lambda v: isinstance(v, (dt.datetime, dt.date)) and not isinstance(v, dt.time)

def as_date(v):
    if isinstance(v, dt.datetime): return v.date()
    if isinstance(v, dt.date): return v
    if isinstance(v, str):
        m = re.fullmatch(r"\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*", v)
        if m:
            try: return dt.date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
            except ValueError: return None
    return None

def phone(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)) and not (isinstance(v, str) and re.fullmatch(r"[\d\s+\-]+", v or "")): return None
    d = re.sub(r"\D", "", str(int(v)) if isinstance(v, (int, float)) else v)
    if len(d) == 10 and d.startswith("1"): return "+20" + d
    if len(d) == 11 and d.startswith("01"): return "+2" + d
    if d.startswith("20") and len(d) >= 11: return "+" + d
    if len(d) in (8, 9, 10) and d[0] in "23": return "+20" + d       # landline without the 0
    return None

def clean(v):
    return re.sub(r"\s+", " ", str(v)).strip() if v not in (None, "") else ""

def read_blocks():
    ws = openpyxl.load_workbook(SRC, data_only=True).active
    blocks, cur = [], None
    for r in ws.iter_rows(min_row=2, values_only=True):
        if r[0]:
            cur = {"code": clean(r[0]), "rows": []}
            blocks.append(cur)
        if cur is not None and any(v not in (None, "") for v in r):
            cur["rows"].append(r)
    return blocks

AREA_RULES = [  # (words in the address, area name); the area is created when it does not exist yet
    ("القصير", "القصير"), ("شرم", "شرم الشيخ"), ("الغردق", "الغردقه"), ("مرسي علم", "مرسي علم"), ("مرسى علم", "مرسي علم"), ("marsa alam", "مرسي علم"),
    ("الجونة", "الجونة"), ("دهب", "دهب"), ("سفاجا", "سفاجا"), ("القصير", "القصير"), ("بورتو غالب", "بورتو غالب"),
    ("العلمين", "العلمين"), ("سهل حشيش", "سهل حشيش"), ("راس سدر", "رأس سدر"), ("اسوان", "أسوان"), ("اسيوط", "أسيوط"),
    ("المنيا", "المنيا"), ("الفيوم", "الفيوم"), ("الشيخ زايد", "الشيخ زايد"), ("اكتوبر", "اكتوبر"), ("التجمع", "القاهرة الجديدة"),
    ("الساحل الشمالى", "الساحل الشمالي"), ("الساحل الشمالي", "الساحل الشمالي"),
]

def parse(block):
    rows = block["rows"]
    first = rows[0]
    h = {"code": block["code"], "name": clean(first[1]), "notes": [], "contacts": [], "hotel_phone": None, "address": "",
         "entries": [], "log": [], "last_maint": None, "flags": []}
    seen_phones = set()
    for i, r in enumerate(rows):
        # more names in the name column: branches or call notes
        if i > 0 and r[1]:
            h["notes"].append(clean(r[1]))
        # phone and contact person (the columns drift: a name can sit in C, a number in C or E)
        cname = clean(r[3]) if isinstance(r[3], str) else (clean(r[2]) if isinstance(r[2], str) else "")
        cph = phone(r[4]) or (phone(r[2]) if not isinstance(r[2], str) else None)
        if i == 0 and phone(r[2]) and not isinstance(r[2], str): h["hotel_phone"] = phone(r[2]); cph = phone(r[4])
        if cph and cph not in seen_phones:
            seen_phones.add(cph); h["contacts"].append((cname, cph))
        elif cname and not cph:
            h["notes"].append("جهة اتصال: " + cname)
        if r[5] and clean(r[5]) != "العنوان" and not h["address"]: h["address"] = clean(r[5])
        # products: "N x 300" in G or H, with the date in the other one (or in I)
        gh = [r[6], r[7]]
        size_cell = next((c for c in gh if isinstance(c, str) and SIZE.search(c)), None)
        d = next((as_date(c) for c in gh if as_date(c)), None)
        if size_cell:
            m = SIZE.search(size_cell)
            h["entries"].append({"qty": int(m.group(1)), "cap": int(m.group(2)), "date": d or as_date(r[8]), "src": clean(size_cell), "from": "sheet"})
        for c in gh:
            if isinstance(c, str) and not SIZE.search(c) and not as_date(c) and c.strip() and "last maint" not in c.lower():
                h["notes"].append(clean(c))
        # last maintenance row
        if isinstance(r[6], str) and "last maint" in r[6].lower() and as_date(r[8]) and isdate(r[8]):
            h["last_maint"] = as_date(r[8])
        # work log: a date in I with what was done in J
        jd = as_date(r[8]) if isdate(r[8]) or isinstance(r[8], str) else None
        jt = clean(r[9]) if isinstance(r[9], str) else ""
        if jd and jt and jt not in ("0",) and not (isinstance(r[6], str) and "last maint" in r[6].lower()):
            h["log"].append((jd, jt))
            m = SIZE.search(jt)
            if m and "توريد" in jt:
                h["entries"].append({"qty": int(m.group(1)), "cap": int(m.group(2)), "date": jd, "src": jt, "from": "log"})
            else:
                w = SIZE_WORD.search(jt)
                if w: h["entries"].append({"qty": int(w.group(1)), "cap": int(w.group(2)), "date": jd, "src": jt, "from": "log"})
    if not h["last_maint"]:
        cands = [d for d, t in h["log"] if any(w in t for w in MAINT_WORDS)]
        if cands: h["last_maint"] = max(cands)
    h["notes"] = list(dict.fromkeys(n for n in h["notes"] if n))
    return h

def area_of(addr, areas):
    norm = lambda s: s.replace("ة", "ه").replace("ى", "ي").replace("أ", "ا").replace("إ", "ا").strip()
    table = {norm(a): a for a in areas}
    for words, name in AREA_RULES:
        if words in addr:
            return table.get(norm(name), name), norm(name) not in table
    if addr and norm(addr) in table: return table[norm(addr)], False
    return None, False

def add_months(d, n):
    y, m = divmod(d.month - 1 + n, 12)
    y, m = d.year + y, m + 1
    day = min(d.day, [31, 29 if y % 4 == 0 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1])
    return dt.date(y, m, day)

def build(areas):
    hotels = [parse(b) for b in read_blocks()]
    hotels = [h for h in hotels if h["name"] and h["code"] not in SKIP]
    for h in hotels:
        h["area"], h["new_area"] = area_of(h["address"], areas)
        if not h["entries"]:
            h["flags"].append("no size: placeholder product")
        h["next_maint"] = add_months(h["last_maint"], NEXT_MONTHS) if h["last_maint"] else None
        if h["next_maint"] and h["next_maint"] < dt.date.today(): h["flags"].append("next maintenance already overdue")
        if any(e["date"] is None for e in h["entries"]): h["flags"].append("a product has no date")
        if h["address"] and not h["area"]: h["flags"].append("area not recognised")
    return hotels

def db_url():
    for l in open(os.path.join(ROOT, ".env")):
        if l.startswith("SUPABASE_DB_URL="): return l.strip().split("=", 1)[1].strip('"')
    sys.exit("SUPABASE_DB_URL not found")

def psql(sql):
    return subprocess.run(["psql", db_url(), "-At", "-c", sql], capture_output=True, text=True).stdout.strip().split("\n")

def q(s):
    return "null" if s in (None, "") else "'" + str(s).replace("'", "''") + "'"

def sql_of(hotels, admin_id):
    out = ["begin;"]
    for a in sorted({h["area"] for h in hotels if h["new_area"] and h["area"]}):
        out.append(f"insert into service_areas (name, sort_order) select {q(a)}, coalesce((select max(sort_order) from service_areas), 0) + 1 where not exists (select 1 from service_areas where name = {q(a)});")
    for h in hotels:
        cid = str(uuid.uuid4())
        main = h["hotel_phone"] or (h["contacts"][0][1] if h["contacts"] else None)
        extras = [c for c in h["contacts"] if c[1] != main]
        if not h["hotel_phone"] and h["contacts"]: main_name = h["contacts"][0][0]
        else: main_name = ""
        contact_name = (main_name or (h["contacts"][0][0] if h["contacts"] else "")) or h["name"]
        notes = "\n".join(h["notes"])
        arr = lambda xs: "array[" + ",".join(q(x) for x in xs) + "]::text[]" if xs else "'{}'::text[]"
        area = f"(select id from service_areas where name = {q(h['area'])} limit 1)" if h["area"] else "null"
        out.append(
            "insert into customers (id, name, company, phone, extra_phones, extra_phone_names, address, area_id, notes, created_by) values "
            f"({q(cid)}, {q(contact_name)}, {q(h['name'])}, {q(main)}, {arr([c[1] for c in extras])}, {arr([c[0] for c in extras])}, {q(h['address'])}, {area}, {q(notes)}, {q(admin_id)});")
        entries = h["entries"] or [{"qty": 1, "cap": None, "date": None, "src": "", "from": "none"}]
        products = []
        for e in entries:
            pid = str(uuid.uuid4()); products.append((pid, e))
            name = f"سخان {e['cap']} لتر" if e["cap"] else "سخانات"
            note = ("الكمية غير محددة: تحتاج استكمال" if e["from"] == "none" else f"من الملف: {e['src']}" + (" (من سجل الأعمال)" if e["from"] == "log" else ""))
            nxt = f"{h['next_maint'].isoformat()} 07:00:00+00" if h["next_maint"] else None
            out.append(
                "insert into customer_products (id, customer_id, name, category_id, quantity, contract_code, contract_date, operation_date, last_maintenance_on, next_maintenance_at, notes, pipeline_id, stage_id, created_by) values "
                f"({q(pid)}, {q(cid)}, {q(name)}, {q(CATEGORY_ID)}, {e['qty']}, {q(h['code'])}, {q(e['date'])}, {q(e['date'])}, {q(h['last_maint'])}, {q(nxt)}, {q(note)}, {q(PIPELINE_ID)}, {q(STAGE_ID)}, {q(admin_id)});")
        # the work log goes on the product with the most units (it is the hotel's, not one product's)
        main_pid = max(products, key=lambda p: p[1]["qty"])[0]
        for d, text in h["log"]:
            kind_done = any(w in text for w in MAINT_WORDS)
            out.append(
                "insert into product_maintenance_log (product_id, kind, happened_at, done_on, note, marked_done, created_by) values "
                f"({q(main_pid)}, {q('done' if kind_done else 'note')}, {q(d.isoformat() + ' 12:00:00+00')}, {q(d)}, {q(text)}, {'true' if kind_done else 'false'}, {q(admin_id)});")
    out.append("commit;")
    return "\n".join(out) + "\n"

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "preview"
    areas = [a for a in psql("select name from service_areas") if a]
    hotels = build(areas)
    path = os.path.join(ROOT, "docs", "hotels-import-preview.csv")
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["code", "hotel", "contact", "phones", "address", "area", "new area?", "products (qty x size @ date)", "units", "latest maintenance", "next maintenance (+6m)", "history lines", "notes", "flags"])
        for h in hotels:
            main = h["hotel_phone"] or (h["contacts"][0][1] if h["contacts"] else "")
            w.writerow([h["code"], h["name"], "; ".join(f"{n} {p}" for n, p in h["contacts"]), main, h["address"], h["area"] or "", "yes" if h["new_area"] else "",
                        "; ".join(f"{e['qty']}x{e['cap']} @ {e['date']}" for e in h["entries"]) or "(placeholder سخانات x1)",
                        sum(e["qty"] for e in h["entries"]) or 1, h["last_maint"] or "", h["next_maint"] or "", len(h["log"]), " | ".join(h["notes"]), "; ".join(h["flags"])])
    units = sum(e["qty"] for h in hotels for e in h["entries"])
    c = collections.Counter(fl for h in hotels for fl in h["flags"])
    print(f"hotels {len(hotels)} | products {sum(max(1, len(h['entries'])) for h in hotels)} | units {units} | history lines {sum(len(h['log']) for h in hotels)}")
    print(f"with phone {sum(1 for h in hotels if h['hotel_phone'] or h['contacts'])} | with last maintenance {sum(1 for h in hotels if h['last_maint'])} | with notes {sum(1 for h in hotels if h['notes'])}")
    print("new areas:", sorted({h['area'] for h in hotels if h['new_area'] and h['area']}))
    print("flags:", dict(c))
    print("preview written:", path)
    if mode in ("sql", "apply"):
        admin = psql("select id from profiles where email = 'ahmedezzaat@gmail.com'")[0]
        sql = sql_of(hotels, admin)
        sp = os.path.join(ROOT, "docs", "hotels-import.sql")
        open(sp, "w", encoding="utf-8").write(sql)
        print("sql written:", sp, f"({sql.count(chr(10))} statements)")
        if mode == "apply":
            r = subprocess.run(["psql", db_url(), "-v", "ON_ERROR_STOP=1", "-1", "-q", "-f", sp], capture_output=True, text=True)
            print(r.stdout[-400:], r.stderr[-800:])
            sys.exit(r.returncode)

main()
