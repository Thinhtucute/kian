#!/usr/bin/env python3
"""Bootstrap a generalized dictionary SQLite DB from JMdict XML + Unihan ZIP.

Usage:
  python scripts/import_jmdict_unihan.py \
        --jmdict JMdict_e.xml \
        --unihan Unihan.zip \
        --out dictionary_general.db

If you place the input files next to this script, you can omit the path values
and use the defaults.
"""

from __future__ import annotations

import argparse
import json
import hashlib
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


ORTHOGRAPHY_VALUES = {
    "ateji",
    "ik",
    "io",
    "ok",
    "rk",
    "sik",
    "gikun",
    "jukujikun",
    "okuriari",
    "rare",
    "search-only",
    "irregular-kana",
    "irregular-kanji",
    "old-kana",
    "rare-kanji",
    "kana-only",
}


def now_iso_utc() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def normalize_script(text: str) -> str:
    if not text:
        return "other"

    has_cjk = False
    has_kana = False
    has_hangul = False
    has_latin = False

    for ch in text:
        cp = ord(ch)
        if 0x4E00 <= cp <= 0x9FFF or 0x3400 <= cp <= 0x4DBF or 0xF900 <= cp <= 0xFAFF:
            has_cjk = True
        elif 0x3040 <= cp <= 0x30FF or 0x31F0 <= cp <= 0x31FF:
            has_kana = True
        elif 0xAC00 <= cp <= 0xD7AF:
            has_hangul = True
        elif (0x0041 <= cp <= 0x007A) or (0x00C0 <= cp <= 0x024F):
            has_latin = True

    if has_cjk:
        return "cjk"
    if has_kana:
        return "kana"
    if has_hangul:
        return "hangul"
    if has_latin:
        return "latin"
    return "other"


def pick_slug(kanji_forms: Sequence[str], reading_forms: Sequence[str]) -> Optional[str]:
    for value in kanji_forms:
        if value:
            return value
    for value in reading_forms:
        if value:
            return value
    return None


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS entry (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            source_id TEXT,
            lang TEXT NOT NULL,
            slug TEXT,
            UNIQUE (source, source_id)
        );

        CREATE TABLE IF NOT EXISTS headword (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            script TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            is_primary INTEGER NOT NULL DEFAULT 0,
            romanization_type TEXT,
            FOREIGN KEY (entry_id) REFERENCES entry(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS headword_tag (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            headword_id INTEGER NOT NULL,
            tag_type TEXT NOT NULL,
            value TEXT NOT NULL,
            FOREIGN KEY (headword_id) REFERENCES headword(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS sense (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            def_lang TEXT NOT NULL DEFAULT 'eng',
            FOREIGN KEY (entry_id) REFERENCES entry(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS definition (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sense_id INTEGER NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            text TEXT NOT NULL,
            type TEXT,
            FOREIGN KEY (sense_id) REFERENCES sense(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS sense_tag (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sense_id INTEGER NOT NULL,
            tag_type TEXT NOT NULL,
            value TEXT NOT NULL,
            FOREIGN KEY (sense_id) REFERENCES sense(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS example (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sense_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            translation TEXT,
            translation_lang TEXT,
            source TEXT,
            FOREIGN KEY (sense_id) REFERENCES sense(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS cjk_char (
            id INTEGER PRIMARY KEY,
            character TEXT NOT NULL UNIQUE,
            codepoint TEXT NOT NULL UNIQUE
        );

        CREATE TABLE IF NOT EXISTS characters (
            code_point INTEGER PRIMARY KEY,
            char TEXT GENERATED ALWAYS AS (char(code_point)) STORED
        );

        CREATE TABLE IF NOT EXISTS unihan_properties (
            code_point INTEGER NOT NULL,
            property TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (code_point, property, value),
            FOREIGN KEY (code_point) REFERENCES characters(code_point) ON DELETE CASCADE
        );

        -- Use an explicit surrogate primary key so FTS can reference it directly.
        CREATE TABLE IF NOT EXISTS cjk_char_property (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            char_id INTEGER NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            UNIQUE (char_id, key, value),
            FOREIGN KEY (char_id) REFERENCES cjk_char(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS headword_char (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            headword_id INTEGER NOT NULL,
            char_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            FOREIGN KEY (headword_id) REFERENCES headword(id) ON DELETE CASCADE,
            FOREIGN KEY (char_id) REFERENCES cjk_char(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS jmdict_entry_meta (
            entry_id INTEGER PRIMARY KEY,
            ent_seq INTEGER NOT NULL UNIQUE,
            FOREIGN KEY (entry_id) REFERENCES entry(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS cedict_entry_meta (
            entry_id INTEGER PRIMARY KEY,
            source_row INTEGER NOT NULL UNIQUE,
            FOREIGN KEY (entry_id) REFERENCES entry(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS import_meta (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            filename TEXT,
            version TEXT,
            entry_count INTEGER,
            imported_at TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_entry_source_source_id ON entry(source, source_id);
        CREATE INDEX IF NOT EXISTS idx_headword_entry_id ON headword(entry_id);
        CREATE INDEX IF NOT EXISTS idx_headword_text ON headword(text);
        CREATE INDEX IF NOT EXISTS idx_headword_script ON headword(script);
        CREATE INDEX IF NOT EXISTS idx_sense_entry_id ON sense(entry_id);
        CREATE INDEX IF NOT EXISTS idx_definition_sense_id ON definition(sense_id);
        CREATE INDEX IF NOT EXISTS idx_sense_tag_sense_id ON sense_tag(sense_id);
        CREATE INDEX IF NOT EXISTS idx_example_sense_id ON example(sense_id);
        CREATE INDEX IF NOT EXISTS idx_headword_char_headword_id ON headword_char(headword_id);
        CREATE INDEX IF NOT EXISTS idx_headword_char_char_id ON headword_char(char_id);

        -- Indexes to speed up character lookups by literal or codepoint
        CREATE INDEX IF NOT EXISTS idx_cjk_char_codepoint ON cjk_char(codepoint);
        CREATE INDEX IF NOT EXISTS idx_cjk_char_character ON cjk_char(character);
        CREATE INDEX IF NOT EXISTS idx_cjk_char_property_char_id ON cjk_char_property(char_id);
        CREATE INDEX IF NOT EXISTS idx_cjk_char_property_key ON cjk_char_property(key);
        CREATE INDEX IF NOT EXISTS idx_cjk_char_property_key_value ON cjk_char_property(key, value);

        CREATE INDEX IF NOT EXISTS idx_unihan_properties_code_point ON unihan_properties(code_point);
        CREATE INDEX IF NOT EXISTS idx_unihan_properties_property ON unihan_properties(property);
        CREATE INDEX IF NOT EXISTS idx_unihan_properties_property_value ON unihan_properties(property, value);

        CREATE VIRTUAL TABLE IF NOT EXISTS headword_fts USING fts5(
            text,
            content='headword',
            content_rowid='id'
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS definition_fts USING fts5(
            text,
            content='definition',
            content_rowid='id'
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS example_fts USING fts5(
            text,
            content='example',
            content_rowid='id'
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS cjk_char_property_fts USING fts5(
            value,
            content='cjk_char_property',
            content_rowid='id'
        );
        """
    )


def normalize_ke_re_inf(code: str) -> str:
    code = (code or "").strip().lower()

    code_map = {
        "ik": "irregular-kanji",
        "iK": "irregular-kanji",
        "io": "irregular-kana",
        "ok": "old-kana",
        "oK": "old-kana",
        "rk": "rare-kanji",
        "sK": "search-only",
        "sk": "search-only",
        "gikun": "gikun",
        "jukujikun": "jukujikun",
        "ateji": "ateji",
    }

    return code_map.get(code, code)


def normalize_misc(code: str) -> str:
    return (code or "").strip().lower()


def clean_text(value) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = str(value)
    if not value:
        return ""
    cleaned = value.replace("", "").strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned


def parse_json_array(raw_value: str) -> list:
    raw_value = (raw_value or "").strip()
    if not raw_value or raw_value == "[]":
        return []
    parsed = json.loads(raw_value)
    if not isinstance(parsed, list):
        raise ValueError("Expected a JSON array")
    return parsed


def insert_headword_tags(
    conn: sqlite3.Connection,
    headword_id: int,
    orthography_codes: Sequence[str],
    priority_codes: Sequence[str],
    restrictions: Sequence[str],
) -> None:
    for code in orthography_codes:
        value = normalize_ke_re_inf(code)
        if not value:
            continue
        conn.execute(
            "INSERT INTO headword_tag (headword_id, tag_type, value) VALUES (?, ?, ?)",
            (headword_id, "orthography", value),
        )

    for code in priority_codes:
        value = (code or "").strip()
        if not value:
            continue
        conn.execute(
            "INSERT INTO headword_tag (headword_id, tag_type, value) VALUES (?, ?, ?)",
            (headword_id, "priority", value),
        )

    for restriction in restrictions:
        value = (restriction or "").strip()
        if not value:
            continue
        conn.execute(
            "INSERT INTO headword_tag (headword_id, tag_type, value) VALUES (?, ?, ?)",
            (headword_id, "restriction", value),
        )


def text_of(elem: Optional[ET.Element]) -> str:
    if elem is None or elem.text is None:
        return ""
    return elem.text.strip()


def parse_jmdict_entries(xml_path: Path) -> Iterable[ET.Element]:
    # Iterparse keeps memory stable for large JMdict files.
    context = ET.iterparse(xml_path, events=("end",))
    for _, elem in context:
        if elem.tag == "entry":
            yield elem
            elem.clear()


def import_jmdict(conn: sqlite3.Connection, jmdict_xml: Path, batch_size: int = 1000) -> int:
    count = 0

    for entry_elem in parse_jmdict_entries(jmdict_xml):
        ent_seq = text_of(entry_elem.find("ent_seq"))
        if not ent_seq:
            continue

        kanji_elems = entry_elem.findall("k_ele")
        reading_elems = entry_elem.findall("r_ele")
        sense_elems = entry_elem.findall("sense")

        kanji_forms = [text_of(k.find("keb")) for k in kanji_elems if text_of(k.find("keb"))]
        reading_forms = [text_of(r.find("reb")) for r in reading_elems if text_of(r.find("reb"))]

        slug = pick_slug(kanji_forms, reading_forms)

        cur = conn.execute(
            """
            INSERT INTO entry (source, source_id, lang, slug)
            VALUES (?, ?, ?, ?)
            """,
            ("jmdict", ent_seq, "jp", slug),
        )
        entry_id = int(cur.lastrowid)

        conn.execute(
            "INSERT INTO jmdict_entry_meta (entry_id, ent_seq) VALUES (?, ?)",
            (entry_id, int(ent_seq)),
        )

        primary_assigned = False

        # k_ele -> cjk headwords
        for pos, k_ele in enumerate(kanji_elems):
            keb = text_of(k_ele.find("keb"))
            if not keb:
                continue

            is_primary = 0
            if not primary_assigned:
                is_primary = 1
                primary_assigned = True

            cur = conn.execute(
                """
                INSERT INTO headword (entry_id, text, script, position, is_primary, romanization_type)
                VALUES (?, ?, ?, ?, ?, NULL)
                """,
                (entry_id, keb, "cjk", pos, is_primary),
            )
            hw_id = int(cur.lastrowid)

            orthography_codes = [text_of(x) for x in k_ele.findall("ke_inf") if text_of(x)]
            priority_codes = [text_of(x) for x in k_ele.findall("ke_pri") if text_of(x)]

            insert_headword_tags(conn, hw_id, orthography_codes, priority_codes, [])

        # r_ele -> kana headwords
        for pos, r_ele in enumerate(reading_elems):
            reb = text_of(r_ele.find("reb"))
            if not reb:
                continue

            is_primary = 0
            if not primary_assigned:
                is_primary = 1
                primary_assigned = True

            cur = conn.execute(
                """
                INSERT INTO headword (entry_id, text, script, position, is_primary, romanization_type)
                VALUES (?, ?, ?, ?, ?, NULL)
                """,
                (entry_id, reb, "kana", pos, is_primary),
            )
            hw_id = int(cur.lastrowid)

            orthography_codes = [text_of(x) for x in r_ele.findall("re_inf") if text_of(x)]
            priority_codes = [text_of(x) for x in r_ele.findall("re_pri") if text_of(x)]
            restrictions = [text_of(x) for x in r_ele.findall("re_restr") if text_of(x)]

            if r_ele.find("re_nokanji") is not None:
                orthography_codes.append("kana-only")

            insert_headword_tags(conn, hw_id, orthography_codes, priority_codes, restrictions)

        # senses + definitions + tags
        for sense_pos, sense_elem in enumerate(sense_elems):
            gloss_elems = sense_elem.findall("gloss")
            def_lang = "eng"
            for g in gloss_elems:
                lang_attr = g.attrib.get("{http://www.w3.org/XML/1998/namespace}lang") or g.attrib.get("lang")
                if lang_attr:
                    def_lang = lang_attr.strip()
                    break

            cur = conn.execute(
                "INSERT INTO sense (entry_id, position, def_lang) VALUES (?, ?, ?)",
                (entry_id, sense_pos, def_lang),
            )
            sense_id = int(cur.lastrowid)

            for def_pos, g in enumerate(gloss_elems):
                text = text_of(g)
                if not text:
                    continue
                g_type = g.attrib.get("g_type")
                conn.execute(
                    "INSERT INTO definition (sense_id, position, text, type) VALUES (?, ?, ?, ?)",
                    (sense_id, def_pos, text, g_type),
                )

            # POS
            for pos_elem in sense_elem.findall("pos"):
                value = text_of(pos_elem)
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "pos", value),
                    )

            # field/misc/dial
            for field_elem in sense_elem.findall("field"):
                value = text_of(field_elem)
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "field", value),
                    )

            for misc_elem in sense_elem.findall("misc"):
                value = normalize_misc(text_of(misc_elem))
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "misc", value),
                    )

            for dial_elem in sense_elem.findall("dial"):
                value = text_of(dial_elem)
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "dial", value),
                    )

            # sense restrictions: stagk/stagr
            for stagk_elem in sense_elem.findall("stagk"):
                value = text_of(stagk_elem)
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "sense_restr", value),
                    )

            for stagr_elem in sense_elem.findall("stagr"):
                value = text_of(stagr_elem)
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "sense_restr", value),
                    )

            # cross-references/antonyms
            for xref_elem in sense_elem.findall("xref"):
                value = text_of(xref_elem)
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "xref", value),
                    )
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "xref_type", "see"),
                    )

            for ant_elem in sense_elem.findall("ant"):
                value = text_of(ant_elem)
                if value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "xref", value),
                    )
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "xref_type", "ant"),
                    )

            # examples from example XML extension (if present)
            for ex_elem in sense_elem.findall("example"):
                jp_text = ""
                en_text = ""

                for ex_sent in ex_elem.findall("ex_sent"):
                    lang = (
                        ex_sent.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")
                        or ex_sent.attrib.get("xml:lang")
                        or ex_sent.attrib.get("lang")
                        or ""
                    ).lower()
                    text = text_of(ex_sent)
                    if not text:
                        continue
                    if lang in {"jpn", "jp"} and not jp_text:
                        jp_text = text
                    elif lang in {"eng", "en"} and not en_text:
                        en_text = text

                if jp_text:
                    conn.execute(
                        """
                        INSERT INTO example (sense_id, text, translation, translation_lang, source)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        (sense_id, jp_text, en_text or None, "eng" if en_text else None, "jmdict"),
                    )

        count += 1
        if count % batch_size == 0:
            conn.commit()
            print(f"Imported JMdict entries: {count}")

    conn.commit()
    conn.execute(
        """
        INSERT INTO import_meta (source, filename, version, entry_count, imported_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        ("jmdict", jmdict_xml.name, None, count, now_iso_utc()),
    )
    conn.commit()

    return count


def populate_headword_char(conn: sqlite3.Connection) -> int:
    rows = conn.execute(
        "SELECT id, text FROM headword WHERE script = 'cjk' ORDER BY id"
    ).fetchall()

    links = 0
    for hw_id, text in rows:
        if not text:
            continue
        for pos, ch in enumerate(text):
            cp = ord(ch)
            codepoint = f"U+{cp:04X}"
            conn.execute(
                "INSERT OR IGNORE INTO cjk_char (id, character, codepoint) VALUES (?, ?, ?)",
                (cp, ch, codepoint),
            )
            conn.execute(
                "INSERT INTO headword_char (headword_id, char_id, position) VALUES (?, ?, ?)",
                (hw_id, cp, pos),
            )
            links += 1

    conn.commit()
    return links


def parse_unihan_line(line: str) -> Optional[Tuple[int, str, str]]:
    line = line.strip()
    if not line or line.startswith("#"):
        return None

    parts = line.split("\t")
    if len(parts) != 3:
        return None

    codepoint_raw, key, value = parts
    m = re.match(r"U\+([0-9A-Fa-f]+)$", codepoint_raw)
    if not m:
        return None

    cp = int(m.group(1), 16)
    return cp, key.strip(), value.strip()


def cedict_source_id(traditional: str, simplified: str, pinyin: str, line_no: int) -> str:
    payload = "|".join([traditional, simplified, pinyin, str(line_no)])
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()


def import_cedict(conn: sqlite3.Connection, cedict_file: Path, batch_size: int = 2000) -> int:
    """Import the enriched TSV format into the generalized schema."""
    count = 0
    row_no = 0

    with cedict_file.open("r", encoding="utf-8", errors="replace") as fh:
        header = fh.readline()
        if not header:
            raise RuntimeError("Enriched TSV file is empty.")

        expected_header = ["#simplified", "traditional", "pinyin", "senses", "examples"]
        if [part.strip() for part in header.rstrip("\r\n").split("\t")] != expected_header:
            raise RuntimeError(
                "Unexpected enriched TSV header. Expected: "
                "#simplified\ttraditional\tpinyin\tsenses\texamples"
            )

        for raw_line in fh:
            row_no += 1
            line = raw_line.strip()
            if not line:
                continue

            parts = raw_line.rstrip("\r\n").split("\t")
            if len(parts) != 5:
                continue

            simplified_raw, traditional_raw, pinyin_raw, senses_raw, examples_raw = parts
            simplified = clean_text(simplified_raw)
            traditional = clean_text(traditional_raw)
            pinyin = clean_text(pinyin_raw)

            senses_data = parse_json_array(senses_raw)
            examples_data = parse_json_array(examples_raw)

            # Use the row order (top-to-bottom) in the enriched TSV as the
            # CC-CEDICT source identifier. This ensures a stable, compact
            # sequential id when the original text file has no native entry id.
            source_id = str(row_no)
            slug = simplified or traditional or pinyin

            cur = conn.execute(
                """
                INSERT INTO entry (source, source_id, lang, slug)
                VALUES (?, ?, ?, ?)
                """,
                ("cedict", source_id, "cn", slug),
            )
            entry_id = int(cur.lastrowid)

            conn.execute(
                "INSERT INTO cedict_entry_meta (entry_id, source_row) VALUES (?, ?)",
                (entry_id, row_no),
            )

            headword_index = 0
            if traditional:
                cur = conn.execute(
                    """
                    INSERT INTO headword (entry_id, text, script, position, is_primary, romanization_type)
                    VALUES (?, ?, ?, ?, ?, NULL)
                    """,
                    (entry_id, traditional, normalize_script(traditional), headword_index, 1),
                )
                trad_hw_id = int(cur.lastrowid)
                insert_headword_tags(conn, trad_hw_id, [], [], [])
                headword_index += 1

            if simplified and simplified != traditional:
                cur = conn.execute(
                    """
                    INSERT INTO headword (entry_id, text, script, position, is_primary, romanization_type)
                    VALUES (?, ?, ?, ?, ?, NULL)
                    """,
                    (entry_id, simplified, normalize_script(simplified), headword_index, 0 if traditional else 1),
                )
                simp_hw_id = int(cur.lastrowid)
                insert_headword_tags(conn, simp_hw_id, [], [], [])
                headword_index += 1

            if pinyin:
                cur = conn.execute(
                    """
                    INSERT INTO headword (entry_id, text, script, position, is_primary, romanization_type)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (entry_id, pinyin, "romanization", headword_index, 0, "pinyin-numeric"),
                )
                pinyin_hw_id = int(cur.lastrowid)
                insert_headword_tags(conn, pinyin_hw_id, [], [], [])

            sense_ids: list[int] = []
            for sense_pos, sense_data in enumerate(senses_data):
                if not isinstance(sense_data, dict):
                    continue

                pos_value = clean_text(sense_data.get("pos"))
                glosses = sense_data.get("glosses") or []
                misc_values = sense_data.get("misc") or []
                field_values = sense_data.get("field") or []
                tag_values = sense_data.get("tags") or []

                cur = conn.execute(
                    "INSERT INTO sense (entry_id, position, def_lang) VALUES (?, ?, ?)",
                    (entry_id, sense_pos, "eng"),
                )
                sense_id = int(cur.lastrowid)
                sense_ids.append(sense_id)

                if pos_value:
                    conn.execute(
                        "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                        (sense_id, "pos", pos_value),
                    )

                for field_value in field_values:
                    cleaned = clean_text(field_value)
                    if cleaned:
                        conn.execute(
                            "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                            (sense_id, "field", cleaned),
                        )

                for misc_value in misc_values:
                    cleaned = normalize_misc(clean_text(misc_value))
                    if cleaned:
                        conn.execute(
                            "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                            (sense_id, "misc", cleaned),
                        )

                for tag_value in tag_values:
                    cleaned = clean_text(tag_value)
                    if cleaned:
                        conn.execute(
                            "INSERT INTO sense_tag (sense_id, tag_type, value) VALUES (?, ?, ?)",
                            (sense_id, "tag", cleaned),
                        )

                for def_pos, gloss in enumerate(glosses):
                    cleaned_gloss = clean_text(gloss)
                    if cleaned_gloss:
                        conn.execute(
                            "INSERT INTO definition (sense_id, position, text, type) VALUES (?, ?, ?, NULL)",
                            (sense_id, def_pos, cleaned_gloss),
                        )

            if not sense_ids:
                cur = conn.execute(
                    "INSERT INTO sense (entry_id, position, def_lang) VALUES (?, ?, ?)",
                    (entry_id, 0, "eng"),
                )
                sense_ids.append(int(cur.lastrowid))

            first_sense_id = sense_ids[0]
            for example_data in examples_data:
                if not isinstance(example_data, dict):
                    continue
                zh_text = clean_text(example_data.get("zh"))
                en_text = clean_text(example_data.get("en"))
                if not zh_text:
                    continue

                conn.execute(
                    """
                    INSERT INTO example (sense_id, text, translation, translation_lang, source)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (first_sense_id, zh_text, en_text or None, "eng" if en_text else None, "cedict_enriched"),
                )

            count += 1
            if count % batch_size == 0:
                conn.commit()
                print(f"Imported enriched TSV entries: {count}")

    conn.commit()
    conn.execute(
        """
        INSERT INTO import_meta (source, filename, version, entry_count, imported_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        ("cedict_enriched", cedict_file.name, None, count, now_iso_utc()),
    )
    conn.commit()

    return count


def import_unihan(
    conn: sqlite3.Connection,
    unihan_zip: Path,
    allowed_keys: Optional[set[str]] = None,
) -> int:
    inserted = 0

    with zipfile.ZipFile(unihan_zip, "r") as zf:
        names = [n for n in zf.namelist() if n.startswith("Unihan") and n.endswith(".txt")]
        if not names:
            raise RuntimeError("No Unihan*.txt files found in zip archive.")

        for name in names:
            with zf.open(name, "r") as fh:
                for raw_line in fh:
                    decoded = raw_line.decode("utf-8", errors="replace")
                    parsed = parse_unihan_line(decoded)
                    if not parsed:
                        continue
                    cp, key, value = parsed

                    if allowed_keys is not None and key not in allowed_keys:
                        continue

                    ch = chr(cp)
                    codepoint = f"U+{cp:04X}"

                    conn.execute(
                        "INSERT OR IGNORE INTO cjk_char (id, character, codepoint) VALUES (?, ?, ?)",
                        (cp, ch, codepoint),
                    )
                    conn.execute(
                        "INSERT OR IGNORE INTO characters (code_point) VALUES (?)",
                        (cp,),
                    )

                    cur = conn.execute(
                        """
                        INSERT OR IGNORE INTO unihan_properties (code_point, property, value)
                        VALUES (?, ?, ?)
                        """,
                        (cp, key, value),
                    )
                    if cur.rowcount and cur.rowcount > 0:
                        inserted += 1

                    conn.execute(
                        """
                        INSERT INTO cjk_char_property (char_id, key, value)
                        VALUES (?, ?, ?)
                        ON CONFLICT(char_id, key, value) DO NOTHING
                        """,
                        (cp, key, value),
                    )

    conn.commit()
    conn.execute(
        """
        INSERT INTO import_meta (source, filename, version, entry_count, imported_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        ("unihan", unihan_zip.name, None, inserted, now_iso_utc()),
    )
    conn.commit()

    return inserted


def rebuild_fts(conn: sqlite3.Connection) -> None:
    conn.execute("INSERT INTO headword_fts(headword_fts) VALUES ('rebuild')")
    conn.execute("INSERT INTO definition_fts(definition_fts) VALUES ('rebuild')")
    conn.execute("INSERT INTO example_fts(example_fts) VALUES ('rebuild')")
    conn.execute("INSERT INTO cjk_char_property_fts(cjk_char_property_fts) VALUES ('rebuild')")
    conn.commit()


def parse_keys_arg(value: str) -> Optional[set[str]]:
    v = value.strip().lower()
    if v in {"", "all"}:
        return None

    if v == "core":
        return {
            "kDefinition",
            "kMandarin",
            "kJapaneseOn",
            "kJapaneseKun",
            "kCantonese",
            "kTotalStrokes",
            "kFrequency",
            "kSimplifiedVariant",
            "kTraditionalVariant",
            "kGradeLevel",
        }

    return {x.strip() for x in value.split(",") if x.strip()}


def validate_args(args: argparse.Namespace) -> None:
    if not args.jmdict.exists():
        raise FileNotFoundError(f"JMdict XML not found: {args.jmdict}")
    if not args.unihan.exists():
        raise FileNotFoundError(f"Unihan ZIP not found: {args.unihan}")

    if args.cedict and not args.cedict.exists():
        raise FileNotFoundError(f"CC-CEDICT file not found: {args.cedict}")

    if args.out.exists() and not args.overwrite:
        raise FileExistsError(
            f"Output DB already exists: {args.out}\\n"
            "Pass --overwrite to recreate it."
        )


def resolve_script_local_path(script_dir: Path, value: Path) -> Path:
    if value.is_absolute():
        return value

    candidate = script_dir / value
    if candidate.exists():
        return candidate

    return value


def resolve_output_path(script_dir: Path, value: Path) -> Path:
    if value.is_absolute():
        return value
    return script_dir / value


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Build generalized dictionary DB from JMdict XML + Unihan ZIP."
    )
    parser.add_argument(
        "--jmdict",
        type=Path,
        default=Path("JMdict_e.xml"),
        help="JMdict XML file name or path (default: JMdict_e.xml beside the script)",
    )
    parser.add_argument(
        "--unihan",
        type=Path,
        default=Path("Unihan.zip"),
        help="Unihan zip file name or path (default: Unihan.zip beside the script)",
    )
    parser.add_argument(
        "--cedict",
        type=Path,
        default=None,
        help="Optional path to CC-CEDICT plain text file",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("dictionary_general.db"),
        help="Output SQLite DB file name or path (default: dictionary_general.db beside the script)",
    )
    parser.add_argument(
        "--unihan-keys",
        default="all",
        help="Unihan key filter: all | core | comma-separated key list (default: all)",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1000,
        help="Commit interval while importing JMdict",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite output DB if it already exists",
    )

    args = parser.parse_args()

    try:
        args.jmdict = resolve_script_local_path(script_dir, args.jmdict)
        args.unihan = resolve_script_local_path(script_dir, args.unihan)
        args.out = resolve_output_path(script_dir, args.out)
        if args.cedict is not None:
            args.cedict = resolve_script_local_path(script_dir, args.cedict)

        validate_args(args)

        if args.out.exists() and args.overwrite:
            args.out.unlink()

        args.out.parent.mkdir(parents=True, exist_ok=True)
        allowed_keys = parse_keys_arg(args.unihan_keys)

        conn = sqlite3.connect(args.out)
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")

        create_schema(conn)

        print("Importing JMdict...")
        jmdict_count = import_jmdict(conn, args.jmdict, batch_size=args.batch_size)
        print(f"JMdict entries imported: {jmdict_count}")

        if args.cedict:
            print("Importing CC-CEDICT...")
            cedict_count = import_cedict(conn, args.cedict, batch_size=args.batch_size)
            print(f"CC-CEDICT entries imported: {cedict_count}")

        print("Linking headword characters...")
        link_count = populate_headword_char(conn)
        print(f"headword_char rows inserted: {link_count}")

        print("Importing Unihan...")
        unihan_count = import_unihan(conn, args.unihan, allowed_keys=allowed_keys)
        print(f"Unihan properties imported: {unihan_count}")

        print("Rebuilding FTS...")
        rebuild_fts(conn)

        conn.execute("ANALYZE")
        conn.commit()
        conn.close()

        print(f"Done. Output DB: {args.out}")
        return 0
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
