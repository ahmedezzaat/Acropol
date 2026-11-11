#!/usr/bin/env python3
"""Enrich the hotels list from maintenance.request.xlsx (an Odoo export of maintenance requests).

  python3 scripts/enrich_hotels.py preview   -> prints what would change, writes docs/hotels-enrich.sql, changes nothing
  python3 scripts/enrich_hotels.py apply     -> runs that SQL

It (1) adds the names that are not customers yet, (2) puts the hotel-like customers that exist elsewhere in the category
فنادق, (3) records each request's status in the customer's notes, (4) records the English name where the file uses one.
Nothing is deleted or merged.
"""
import os, re, subprocess, sys, uuid
import openpyxl

SRC = os.environ.get("REQUESTS_XLSX", "/Users/mac/Downloads/maintenance.request.xlsx")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATEGORY_ID = "462a53da-3521-49c6-b95f-e26673a67fe1"   # سخانات
PIPELINE_ID = "fcb835d5-36ca-4ab0-a071-c4188b24ab13"
STAGE_ID = "f4f1b51e-5d30-40ad-9d21-34695bab74d2"      # تم التشغيل
STATUS_AR = {"New Request": "طلب جديد", "In Progress": "قيد التنفيذ", "Repaired": "تم الإصلاح"}
RANK = {"New Request": 1, "In Progress": 2, "Repaired": 3}

# request subject -> hotel code, where the name differs from ours (English names, spelling, a second name of the same hotel)
ALIAS = {
    "فندق بيراميزا شرم الشيخ": "H&A029", "مارينا راديسون - بورتو غالب": "H&A020", "Future Marsa Alam Hotel": "H&A014",
    "Elysee Hotel": "H&A013", "Mina Mark Hotel": "H&A012", "Old vick Hotel - Sharm": "H&A002", "مستشفى جلوبال كير": "H&A016",
    "جزيرة طويلة": "H&A025", "فندق ايزيس اسوان": "H&A033", "Sultan Sharm Hotel": "H&A001", "El Alizeh Hotel": "H&A003",
    "Charming Inn Hotel": "H&A004", "Sea Club Hotel": "H&A005", "Grand Plaza Hotel": "H&A006", "Orascom El Gouna Hotel": "H&A007",
    "Al Nour Tourism Company - amira hotel ras sedr": "H&A008", "Hollywood Hotel": "H&A009", "Sky View Hotel": "H&A011",
}
# request subject -> an existing customer outside the hotels list (matched by its exact name)
EXISTING = {
    "منتجع لوسيندا": "منتجع لوسيندا - شركة زاد", "فندق لازيب (محمد حافظ )": "فندق لازيب", "مستشفى الطب النفسى": "مستشفي الطب النفسي",
    "المسعود": "شركة المسعود للتنمية السياحية و الفندقية", "دير السيدة العذراء": "دير السيدة العذراء (براموس)",
}
# of those, the ones that are a hotel (the rest keep their category, a hospital goes to شركات ومصانع)
TO_HOTELS = {"منتجع لوسيندا - شركة زاد", "فندق لازيب", "شركة المسعود للتنمية السياحية و الفندقية"}
TO_COMPANIES = {"مستشفي الطب النفسي"}
# left out on purpose: could be the same hotel as another one, to be decided by a person
UNSURE = {"الباتروس اكوا": "may be the aqua park (H&A055) or another hotel", "فندق جورجينا بيتش": "may be جورجونيا بيتش (H&A056)", "Deir El Barsha": "may be the existing customer دير البرشا (not imported)"}
# names that are not customers yet; "company" ones go to شركات ومصانع, the rest to فنادق
NEW_COMPANIES = {"بنك كريدى اجرى كول", "شركة ايجرين"}

def db_url():
    for l in open(os.path.join(ROOT, ".env")):
        if l.startswith("SUPABASE_DB_URL="): return l.strip().split("=", 1)[1].strip('"')
    sys.exit("SUPABASE_DB_URL not found")

def psql(sql):
    r = subprocess.run(["psql", db_url(), "-At", "-F", "\x1f", "-R", "\x1e", "-c", sql], capture_output=True, text=True)
    if r.returncode: sys.exit(r.stderr)
    return [x.strip("\n").split("\x1f") for x in r.stdout.strip("\n\x1e").split("\x1e") if x.strip("\n")]

def q(s):
    return "null" if s in (None, "") else "'" + str(s).replace("'", "''") + "'"

def norm(s):
    s = re.sub(r"\s+", " ", s.strip().lower())
    for a, b in (("ة", "ه"), ("ى", "ي"), ("أ", "ا"), ("إ", "ا")): s = s.replace(a, b)
    return s

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "preview"
    ws = openpyxl.load_workbook(SRC, data_only=True).active
    reqs = [(str(r[0]).strip(), r[4]) for r in ws.iter_rows(min_row=2, values_only=True) if r[0]]
    hotels = {c: (cid, name.strip()) for c, cid, name in psql("select distinct p.contract_code, c.id, c.company from customers c join customer_products p on p.customer_id=c.id where p.contract_code like 'H&A%'")}
    by_name = {norm(n): (cid, c) for c, (cid, n) in hotels.items()}
    existing = {n: cid for cid, n in psql("select id, coalesce(nullif(company,''), name) from customers")}
    admin = psql("select id from profiles where email = 'ahmedezzaat@gmail.com'")[0][0]
    cats = {n: i for n, i in psql("select name, id from customer_categories")}

    target, new_names, unsure, notfound = {}, [], [], []   # customer id -> {"status", "english", "name"}
    for subj, stage in reqs:
        if subj in UNSURE: unsure.append(subj); continue
        cid = None; label = None
        if subj in ALIAS and ALIAS[subj] in hotels: cid, label = hotels[ALIAS[subj]][0], hotels[ALIAS[subj]][1]
        elif norm(subj) in by_name: cid, label = by_name[norm(subj)][0], subj
        elif subj in EXISTING and EXISTING[subj] in existing: cid, label = existing[EXISTING[subj]], EXISTING[subj]
        if cid:
            t = target.setdefault(cid, {"status": stage, "english": set(), "name": label, "subjects": []})
            if RANK[stage] > RANK[t["status"]]: t["status"] = stage
            t["subjects"].append(subj)
            if re.search(r"[A-Za-z]{3}", subj) and norm(subj) != norm(label): t["english"].add(subj)
        else:
            if subj not in [n for n, _ in new_names]: new_names.append((subj, stage))
            else: pass
    # a name repeated in the file counts once (the most advanced status)
    out = ["begin;"]
    nextno = 107
    for subj, stage in new_names:
        cid = str(uuid.uuid4()); pid = str(uuid.uuid4())
        cat = cats["شركات ومصانع"] if subj in NEW_COMPANIES else cats["فنادق"]
        code = f"H&A{nextno}"; nextno += 1
        note = f"طلب صيانة (ملف الطلبات): {STATUS_AR[stage]}"
        out.append(f"insert into customers (id, name, company, category_id, notes, created_by) values ({q(cid)}, {q(subj)}, {q(subj)}, {q(cat)}, {q(note)}, {q(admin)});")
        out.append(f"insert into customer_products (id, customer_id, name, category_id, quantity, contract_code, notes, pipeline_id, stage_id, created_by) values ({q(pid)}, {q(cid)}, 'سخانات', {q(CATEGORY_ID)}, 1, {q(code)}, 'الكمية غير محددة: تحتاج استكمال (من ملف طلبات الصيانة)', {q(PIPELINE_ID)}, {q(STAGE_ID)}, {q(admin)});")
    for cid, t in target.items():
        lines = [f"طلب صيانة (ملف الطلبات): {STATUS_AR[t['status']]}"]
        if t["english"]: lines.append("الاسم بالإنجليزية: " + " / ".join(sorted(t["english"])))
        add = "\n".join(lines)
        # appended once: not again if it is already there
        out.append(f"update customers set notes = case when coalesce(notes,'') like '%طلب صيانة (ملف الطلبات)%' then notes else concat_ws(E'\\n', nullif(notes,''), {q(add)}) end where id = {q(cid)};")
        if t["name"] in TO_HOTELS: out.append(f"update customers set category_id = {q(cats['فنادق'])} where id = {q(cid)};")
        if t["name"] in TO_COMPANIES: out.append(f"update customers set category_id = {q(cats['شركات ومصانع'])} where id = {q(cid)};")
    out.append("commit;")
    sql = "\n".join(out) + "\n"
    path = os.path.join(ROOT, "docs", "hotels-enrich.sql")
    open(path, "w", encoding="utf-8").write(sql)
    print(f"requests {len(reqs)} | matched customers {len(target)} | new customers {len(new_names)} | left for a person {len(unsure)}")
    print("new:", [(n, "شركات" if n in NEW_COMPANIES else "فنادق", STATUS_AR[s]) for n, s in new_names])
    print("reclassified to فنادق:", sorted(TO_HOTELS), "| to شركات ومصانع:", sorted(TO_COMPANIES))
    print("with an English name recorded:", sum(1 for t in target.values() if t["english"]))
    print("status counts:", {STATUS_AR[k]: sum(1 for t in target.values() if t["status"] == k) for k in RANK})
    print("left for a person:", unsure)
    print("sql:", path, f"({sql.count(chr(10))} lines)")
    if mode == "apply":
        r = subprocess.run(["psql", db_url(), "-v", "ON_ERROR_STOP=1", "-q", "-f", path], capture_output=True, text=True)
        print(r.stdout[-300:], r.stderr[-600:]); sys.exit(r.returncode)

main()
