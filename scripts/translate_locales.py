#!/usr/bin/env python3
"""Build fa.json and ms.json via MyMemory (rate-limit friendly)."""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

from deep_translator import GoogleTranslator, MyMemoryTranslator

BASE = Path(__file__).resolve().parent.parent / "assets" / "translations"
DELAY = 0.55

PROTECTED = sorted([
    "Munawwara Care", "MUNAWWARA CARE", "munawwaracare@gmail.com",
    "Agora", "WebRTC", "Google Maps", "GPS", "SOS", "TTS", "QR", "PDF",
    "Face ID", "Wi-Fi", "Android", "Samsung", "Xiaomi", "Redmi", "POCO",
    "Huawei", "Honor", "Oppo", "Realme", "OnePlus", "Vivo", "iQOO",
    "Zamzam", "Mecca", "Makkah", "Medina", "Madinah", "Jeddah", "Hijaz",
    "Haram", "Kaaba", "Qibla", "Tashera", "Morafeq", "EL WAKEL",
    "MC4K7H2NP", "HAJJ-2024-X", "pilgrim@example.com", "999", "911",
    "Assalamu Alaykum", "Sahih al-Bukhari", "Sahih Muslim",
    "Sunan Abu Dawud", "Jami' at-Tirmidhi", "Sunan an-Nasa'i",
    "Sunan Ibn Majah", "Muwatta Malik", "Al-Asma Al-Husna", "Du'aa",
    "Azkar", "Adhkar", "Dhikr", "Tahajjud", "qiyam", "Imsak", "Fajr",
    "Dhuhr", "Asr", "Maghrib", "Isha", "Muharram", "Safar", "Ramadan",
    "Shawwal", "Rajab", "Sha'ban", "Mina",
], key=len, reverse=True)

PH = re.compile(r"(\{\}|\{[a-zA-Z_][a-zA-Z0-9_]*\}|\{[0-9]+\})")
TOK = "§{}§"

FA_OVERRIDES = {
    "lang_en": "انگلیسی", "lang_ar": "عربی", "lang_ur": "اردو",
    "lang_fr": "فرانسوی", "lang_tr": "ترکی", "lang_id": "اندونزیایی",
    "lang_fa": "فارسی", "lang_ms": "مالزی", "lang_persian": "فارسی",
    "lang_malay": "مالایی", "lang_english": "انگلیسی", "lang_arabic": "عربی",
    "lang_urdu": "اردو", "lang_french": "فرانسوی",
    "lang_indonesian": "اندونزیایی", "lang_turkish": "ترکی",
    "app_name": "Munawwara Care", "app_title": "MUNAWWARA CARE",
    "call_support_display_name": "Munawwara Care",
    "device_care_app_name": "Munawwara Care",
    "greeting_prefix": "Assalamu Alaykum,",
    "home_greeting": "Assalamu Alaykum, ",
    "splash_tagline": "Serving the Guests of Rahman with excellence and ease.",
    "translate_mock_clinic_output": "أين تقع أقرب عيادة طبية؟",
    "hint_email": "pilgrim@example.com", "hint_national_id": "A1234567",
    "login_code_hint": "e.g. MC4K7H2NP",
    "join_group_code_hint": "EX: HAJJ-2024-X",
}

MS_OVERRIDES = {
    "lang_en": "Inggeris", "lang_ar": "Arab", "lang_ur": "Urdu",
    "lang_fr": "Perancis", "lang_tr": "Turki", "lang_id": "Indonesia",
    "lang_fa": "Parsi", "lang_ms": "Melayu", "lang_persian": "Parsi",
    "lang_malay": "Melayu", "lang_english": "Inggeris", "lang_arabic": "Arab",
    "lang_urdu": "Urdu", "lang_french": "Perancis",
    "lang_indonesian": "Indonesia", "lang_turkish": "Turki",
    "app_name": "Munawwara Care", "app_title": "MUNAWWARA CARE",
    "call_support_display_name": "Munawwara Care",
    "device_care_app_name": "Munawwara Care",
}


def protect(text: str) -> tuple[str, list[str]]:
    tokens: list[str] = []

    def ph(m: re.Match[str]) -> str:
        tokens.append(m.group(0))
        return TOK.format(len(tokens) - 1)

    s = PH.sub(ph, text)
    for term in PROTECTED:
        while term in s:
            tokens.append(term)
            s = s.replace(term, TOK.format(len(tokens) - 1), 1)
    return s, tokens


def restore(text: str, tokens: list[str]) -> str:
    out = text
    for i, t in enumerate(tokens):
        out = out.replace(TOK.format(i), t)
    return out


def clean_ms(text: str) -> str:
    out = re.sub(r"\s*»\s*$", "", text.strip())
    out = re.sub(r"\s*\([A-Za-z][^)]*\)\s*$", "", out)
    return out.strip()


def translate_safe(text: str, source: str, target: str) -> str:
    if not text.strip():
        return text
    protected, tokens = protect(text)
    mm_src = "en-US" if source == "en" else "id-ID"
    mm_tgt = "fa-IR" if target == "fa" else "zsm-MY"
    for attempt in range(5):
        try:
            tr = MyMemoryTranslator(
                source=mm_src, target=mm_tgt,
            ).translate(protected)
            out = restore(tr, tokens)
            return clean_ms(out) if target == "ms" else out.strip()
        except Exception:
            time.sleep(2 ** attempt)
    try:
        tr = GoogleTranslator(source=source, target=target).translate(protected)
        out = restore(tr, tokens)
        return clean_ms(out) if target == "ms" else out.strip()
    except Exception:
        return text


def build(
    keys: list[str],
    en: dict[str, str],
    id_data: dict[str, str],
    mode: str,
    out_path: Path,
) -> None:
    partial_path = out_path.with_suffix(".partial.json")
    done: dict[str, str] = {}
    if partial_path.exists():
        done = json.loads(partial_path.read_text("utf-8"))
    overrides = FA_OVERRIDES if mode == "fa" else MS_OVERRIDES
    done.update(overrides)

    total = len(keys)
    for i, key in enumerate(keys):
        if key in done:
            continue
        if mode == "fa":
            src, sl, tl = en[key], "en", "fa"
        elif key in id_data:
            src, sl, tl = id_data[key], "id", "ms"
        else:
            src, sl, tl = en[key], "en", "ms"
        done[key] = translate_safe(src, sl, tl)
        if (i + 1) % 10 == 0:
            partial_path.write_text(
                json.dumps(done, ensure_ascii=False, indent=2), "utf-8")
            print(f"{mode}: {i + 1}/{total}", flush=True)
        time.sleep(DELAY)

    ordered = {k: done[k] for k in keys}
    out_path.write_text(
        json.dumps(ordered, ensure_ascii=False, indent=2) + "\n", "utf-8")
    if partial_path.exists():
        partial_path.unlink()
    print(f"{mode} done: {len(ordered)} keys", flush=True)


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "both"
    en = json.loads((BASE / "en.json").read_text("utf-8"))
    id_data = json.loads((BASE / "id.json").read_text("utf-8"))
    keys = list(en.keys())
    print(f"en keys: {len(keys)}", flush=True)
    if mode in ("fa", "both"):
        build(keys, en, id_data, "fa", BASE / "fa.json")
    if mode in ("ms", "both"):
        build(keys, en, id_data, "ms", BASE / "ms.json")
    for name in ("fa", "ms"):
        if mode not in (name, "both"):
            continue
        got = json.loads((BASE / f"{name}.json").read_text("utf-8"))
        print(
            f"{name} match en: {set(got.keys()) == set(keys)} ({len(got)})",
            flush=True,
        )


if __name__ == "__main__":
    main()
