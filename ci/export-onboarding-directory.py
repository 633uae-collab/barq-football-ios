"""Export identity metadata from the app's public read-only API for offline onboarding."""
import json
import sys
from pathlib import Path
from urllib.request import Request, urlopen

BASE = "https://barq-football-ios.onrender.com/api"
LEAGUES = (39, 140, 135, 78, 61, 307, 301)

def read(path):
    request = Request(BASE + path, headers={"Accept": "application/json"})
    with urlopen(request, timeout=75) as response:
        return json.load(response)

def identity(row, fields):
    if type(row.get("id")) is not int or row["id"] <= 0 or not isinstance(row.get("name"), str) or not row["name"].strip():
        raise ValueError("Missing identity")
    return {key: row[key] for key in fields if row.get(key) is not None}

def main():
    clubs = {}
    catalog = read("/catalog")
    competitions = [identity(item, ("id","name","ar","country","countryAr","type","logo"))
                    for item in catalog["leagues"] if item.get("type") in ("League", "Cup")]
    if any(not any(row["id"] == league for row in competitions) for league in LEAGUES):
        raise ValueError("Incomplete competition catalog")
    for league in LEAGUES:
        payload = read(f"/standings/{league}")
        if payload["league"]["id"] != league:
            raise ValueError(f"Unexpected league for {league}")
        teams = {}
        for group in payload["groups"]:
            for row in group:
                team = identity(row["team"], ("id","name","logo"))
                teams.setdefault(team["id"], team)
        if not teams:
            raise ValueError(f"Missing clubs in {league}")
        clubs[str(league)] = list(teams.values())
        print(f"league={league} season={payload['league'].get('season')} clubs={len(teams)}", flush=True)
    result = {"clubs": clubs, "competitions": competitions}
    Path(sys.argv[1]).write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"competitions={len(competitions)}")

if __name__ == "__main__":
    main()
