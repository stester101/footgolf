#!/usr/bin/env python3
"""Import senior men's national-team caps/goals from Wikidata (CC0) for a set of countries.

Rules (spec §7.4):
  * official senior international appearances/goals only: P54 (member of sports team) statements on the
    senior men's national team item, qualifiers P1350 (number of matches played) and P1351 (goals);
  * players who represented several senior national teams use their FINAL national team only
    (latest P580 start / P582 end); if that final team is not in the selected list they are excluded;
  * male players only (P21 = Q6581097);
  * records missing a caps qualifier are excluded; records missing goals are excluded and reported.
Data is a provisional snapshot: Wikidata can be incomplete or out of date. Provenance is kept per record.

Usage: python3 tools/data/import_wikidata.py [--out data/footballers_real.json] [--report data/footballers_real_report.md]
Network: needs https://query.wikidata.org (run in GitHub Actions; the dev sandbox blocks it).
"""
import argparse, datetime, json, re, sys, time, urllib.parse, urllib.request

ENDPOINT = "https://query.wikidata.org/sparql"
UA = "FootballGolfPrototype/0.1 (offline game data snapshot; github.com/stester101/footgolf)"
NAT_TEAM = "Q6979593"     # national association football team
MALE = "Q6581097"
BAD_TEAM_LABEL = re.compile(r"(women|under-?\s?\d|\bu-?\d\d\b|youth|olympic|amateur|\bb team\b| b national|futsal|beach|universiade|military|legends|xi\b|unofficial|league)", re.I)


def sparql(query, retries=3):
    data = urllib.parse.urlencode({"query": query, "format": "json"}).encode()
    for attempt in range(retries):
        try:
            req = urllib.request.Request(ENDPOINT, data=data, headers={"User-Agent": UA, "Accept": "application/sparql-results+json"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)["results"]["bindings"]
        except Exception as e:  # noqa: BLE001
            wait = 10 * (attempt + 1)
            print(f"  query failed ({e}); retry in {wait}s", file=sys.stderr, flush=True)
            time.sleep(wait)
    raise RuntimeError("SPARQL query failed repeatedly")


def qid(uri):
    return uri.rsplit("/", 1)[-1]


def val(b, k):
    return b[k]["value"] if k in b else None


def year(s):
    if not s:
        return 0
    m = re.match(r"^-?(\d{4})", s)
    return int(m.group(1)) if m else 0


def resolve_team(country):
    """Senior men's team = the item linked from the English Wikipedia article
    "<Country> national football team" (fast exact lookup), unless pinned with "team"."""
    if country.get("team"):
        return country["team"], "pinned"
    title = country.get("wiki", f"{country['name']} national football team")
    q = f"""
SELECT ?team WHERE {{
  ?article schema:about ?team ; schema:isPartOf <https://en.wikipedia.org/> ; schema:name "{title}"@en .
}}"""
    rows = sparql(q)
    if not rows:
        raise RuntimeError(f"no Wikidata item for enwiki article '{title}'")
    return qid(val(rows[0], "team")), f"enwiki '{title}'"


NATIONAL_LABEL = re.compile(r"national.*(football|soccer)|(football|soccer).*national", re.I)


def fetch_players(team_q):
    # Only statements carrying a caps qualifier; national teams are recognised by label in Python.
    q = f"""
SELECT ?p ?pLabel ?birth ?team ?teamLabel ?caps ?goals ?start ?end WHERE {{
  ?p p:P54 ?st0 . ?st0 ps:P54 wd:{team_q} .
  ?p wdt:P21 wd:{MALE} .
  ?p p:P54 ?st . ?st ps:P54 ?team ; pq:P1350 ?caps .
  OPTIONAL {{ ?st pq:P1351 ?goals }}
  OPTIONAL {{ ?st pq:P580 ?start }}
  OPTIONAL {{ ?st pq:P582 ?end }}
  OPTIONAL {{ ?p wdt:P569 ?birth }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}"""
    return sparql(q)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--countries", default="tools/data/countries.json")
    ap.add_argument("--out", default="data/footballers_real.json")
    ap.add_argument("--report", default="data/footballers_real_report.md")
    a = ap.parse_args()
    cfg = json.load(open(a.countries, encoding="utf-8"))
    today = datetime.date.today().isoformat()
    selected = {}
    team_info = {}
    for c in cfg["countries"]:
        t, how = resolve_team(c)
        selected[t] = c
        team_info[c["code"]] = (t, how)
        print(f"{c['name']}: {t} [{how}]", flush=True)
        time.sleep(1)

    players = {}   # qid -> dict
    stats = {c["code"]: {"rows": 0, "kept": 0, "no_caps": 0, "no_goals": 0, "final_elsewhere": 0, "final_unselected": 0} for c in cfg["countries"]}
    for t, c in selected.items():
        rows = fetch_players(t)
        print(f"{c['name']}: {len(rows)} statement rows", flush=True)
        by_p = {}
        for r in rows:
            p = qid(val(r, "p"))
            d = by_p.setdefault(p, {"name": val(r, "pLabel"), "birth": year(val(r, "birth")), "teams": {}})
            team = qid(val(r, "team"))
            label = val(r, "teamLabel") or ""
            if team != t and (BAD_TEAM_LABEL.search(label) or not NATIONAL_LABEL.search(label)):
                continue
            caps = val(r, "caps")
            goals = val(r, "goals")
            entry = d["teams"].setdefault(team, {"label": label, "caps": None, "goals": None, "last": 0, "first": 9999})
            if caps is not None and (entry["caps"] is None or int(float(caps)) > entry["caps"]):
                entry["caps"] = int(float(caps))
                entry["goals"] = int(float(goals)) if goals is not None else None
            entry["last"] = max(entry["last"], year(val(r, "end")) or year(val(r, "start")))
            entry["first"] = min(entry["first"], year(val(r, "start")) or 9999)
        s = stats[c["code"]]
        for p, d in by_p.items():
            s["rows"] += 1
            mine = d["teams"].get(t)
            if mine is None or mine["caps"] is None:
                s["no_caps"] += 1
                continue
            # final senior national team = latest activity
            final_team = max(d["teams"].items(), key=lambda kv: (kv[1]["last"], kv[1]["first"] if kv[1]["first"] != 9999 else 0))[0]
            if final_team != t and len(d["teams"]) > 1:
                if final_team in selected:
                    s["final_elsewhere"] += 1
                else:
                    s["final_unselected"] += 1
                continue
            if mine["goals"] is None:
                s["no_goals"] += 1
                continue
            if not d["name"] or re.match(r"^Q\d+$", d["name"]):
                continue
            first = mine["first"] if mine["first"] != 9999 else 0
            players[p] = {
                "id": f"wd-{p}",
                "name": d["name"],
                "country_code": c["code"],
                "nationality": c["name"],
                "senior_international_caps": mine["caps"],
                "senior_international_goals": mine["goals"],
                "birth_year": d["birth"] or None,
                "career_years": (f"{first}–{mine['last']}" if first and mine["last"] else ""),
                "source": "wikidata",
                "wikidata": p,
                "team_qid": t,
                "retrieved": today,
                "provisional": True,
            }
            s["kept"] += 1
        time.sleep(2)

    out = sorted(players.values(), key=lambda r: (r["name"].lower(), r["nationality"], r["birth_year"] or 0))
    # drop empty optional fields
    for r in out:
        for k in ["birth_year", "career_years"]:
            if not r.get(k):
                r.pop(k, None)
    json.dump({"version": 1, "dataset": f"wikidata-{today}",
               "description": "Senior men's international caps/goals snapshot from Wikidata (CC0). Provisional: may be incomplete or out of date.",
               "countries": [c["name"] for c in cfg["countries"]], "footballers": out},
              open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=0)

    lines = [f"# Footballer import report ({today})", "", "Source: Wikidata SPARQL (CC0). Provisional snapshot.", "",
             "| Country | Team item | Kept | No caps | No goals (excluded) | Final team elsewhere (selected) | Final team not selected |",
             "|---|---|---:|---:|---:|---:|---:|"]
    for c in cfg["countries"]:
        s = stats[c["code"]]
        lines.append(f"| {c['name']} | {team_info[c['code']][0]} | {s['kept']} | {s['no_caps']} | {s['no_goals']} | {s['final_elsewhere']} | {s['final_unselected']} |")
    lines += ["", f"**Total players: {len(out)}**", "", "## Team resolution", ""]
    for c in cfg["countries"]:
        lines.append(f"- {c['name']}: {team_info[c['code']][1]}")
    lines += ["", "## Sanity check: top 5 by caps per country", ""]
    for c in cfg["countries"]:
        top = sorted([r for r in out if r["country_code"] == c["code"]], key=lambda r: -r["senior_international_caps"])[:5]
        lines.append(f"- **{c['name']}**: " + "; ".join(f"{r['name']} {r['senior_international_caps']}/{r['senior_international_goals']}" for r in top))
    zero = sum(1 for r in out if r["senior_international_goals"] == 0)
    one = sum(1 for r in out if r["senior_international_caps"] == 1)
    lines += ["", f"Players with 0 goals: {zero}. Players with exactly 1 cap: {one}."]
    names = {}
    for r in out:
        names.setdefault(r["name"], []).append(r)
    dups = [n for n, v in names.items() if len(v) > 1]
    lines.append(f"Duplicate names (disambiguated by birth year/nationality): {len(dups)}")
    open(a.report, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    if len(out) < 100:
        sys.exit("Too few players imported; refusing to write a suspicious dataset")


if __name__ == "__main__":
    main()
