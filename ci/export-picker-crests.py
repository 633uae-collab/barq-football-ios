"""Build the offline picker artwork from the directory's public API-Sports image URLs."""
import io
import json
import sqlite3
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from PIL import Image

def fetch(entry):
    kind, identity, url = entry
    expected = f"https://media.api-sports.io/football/{kind}/{identity}.png"
    if url != expected:
        raise ValueError(f"Unexpected artwork address for {kind}/{identity}")
    for attempt in range(2):
        try:
            with urlopen(Request(url, headers={"Accept": "image/png"}), timeout=20) as response:
                data = response.read(2_000_001)
                if len(data) > 2_000_000 or not data.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise ValueError(f"Non-PNG response for {kind}/{identity}")
            with Image.open(io.BytesIO(data)) as original:
                original.load()
                image = original.convert("RGBA")
                if not image.getbbox():
                    raise ValueError(f"Empty artwork for {kind}/{identity}")
                image.thumbnail((156, 156), Image.Resampling.LANCZOS)
                output = io.BytesIO()
                image.save(output, "WEBP", lossless=True, method=4)
                return kind, identity, output.getvalue()
        except HTTPError as error:
            if error.code in (404, 410):
                return kind, identity, None
            if error.code not in (500, 502, 503, 504) or attempt:
                raise
        except TimeoutError:
            if attempt:
                raise
        time.sleep(2)

def main(directory, output):
    catalog = json.loads(Path(directory).read_text())
    rows = {"teams": [row for teams in catalog["clubs"].values() for row in teams],
            "leagues": catalog["competitions"]}
    entries = sorted({(kind, row["id"], row["logo"]) for kind, items in rows.items() for row in items})
    missing = []
    if Path(output).exists():
        raise FileExistsError(output)
    with sqlite3.connect(output) as database, ThreadPoolExecutor(max_workers=4) as workers:
        database.execute("CREATE TABLE crest(kind TEXT NOT NULL, id INTEGER NOT NULL, image BLOB NOT NULL, PRIMARY KEY(kind,id)) WITHOUT ROWID")
        for kind, identity, image in workers.map(fetch, entries):
            if image is None:
                missing.append(f"{kind}/{identity}")
                continue
            database.execute("INSERT INTO crest VALUES (?,?,?)", (kind, identity, image))
        print("Saved", database.execute("SELECT kind, COUNT(*) FROM crest GROUP BY kind").fetchall())
        print("Unavailable at source:", missing)
        if not all(database.execute("SELECT 1 FROM crest WHERE kind=? AND id=?", item).fetchone()
                   for item in [("teams",529),("teams",2865),("leagues",140),("leagues",2)]):
            raise RuntimeError("Missing representative club or competition")
        database.commit()
        database.execute("VACUUM")
        assert database.execute("PRAGMA integrity_check").fetchone() == ("ok",)

if __name__ == "__main__":
    main(*sys.argv[1:])
