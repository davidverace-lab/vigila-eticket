import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for z in d:
    for p in z.get("prices", []):
        for t in p.get("types", []):
            promo = " [PROMO con codigo]" if t.get("promotionId") else ""
            print("%s | %s | %s | $%s%s" % (z.get("description"), p.get("description"), t.get("type"), t.get("total"), promo))
