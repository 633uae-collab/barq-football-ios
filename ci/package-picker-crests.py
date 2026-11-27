"""Compact a verified picker artwork export into the app's offline resource."""
import hashlib
import io
import sqlite3
import sys
from pathlib import Path

from PIL import Image


def main(source, target):
    if not Path(source).is_file() or Path(target).exists():
        raise ValueError("Expected an existing export and a new output path")
    with sqlite3.connect(source) as original, sqlite3.connect(target) as package:
        package.executescript("""
            PRAGMA page_size=1024;
            CREATE TABLE artwork(asset INTEGER PRIMARY KEY, image BLOB NOT NULL);
            CREATE TABLE identity(kind TEXT NOT NULL, id INTEGER NOT NULL,
                asset INTEGER NOT NULL REFERENCES artwork(asset), PRIMARY KEY(kind,id)) WITHOUT ROWID;
            CREATE VIEW crest AS SELECT identity.kind, identity.id, artwork.image
                FROM identity JOIN artwork USING(asset);
        """)
        seen = {}
        for kind, identity, data in original.execute("SELECT kind,id,image FROM crest ORDER BY kind,id"):
            digest = hashlib.sha256(data).digest()
            if digest not in seen:
                with Image.open(io.BytesIO(data)) as image:
                    compact = io.BytesIO()
                    image.save(compact, "WEBP", quality=88, method=5, alpha_quality=100)
                encoded = min(data, compact.getvalue(), key=len)
                seen[digest] = package.execute("INSERT INTO artwork(image) VALUES(?)", (encoded,)).lastrowid
            package.execute("INSERT INTO identity VALUES(?,?,?)", (kind, identity, seen[digest]))
        package.commit()
        package.execute("VACUUM")
        print(package.execute("SELECT kind, COUNT(*) FROM crest GROUP BY kind").fetchall())
        assert package.execute("PRAGMA integrity_check").fetchone() == ("ok",)


if __name__ == "__main__":
    main(*sys.argv[1:])
