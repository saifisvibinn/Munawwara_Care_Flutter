"""Fetch UmmahAPI duas and build assets/muslim/dua_i18n.json (titles per locale)."""
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dua_ar_by_en import AR_BY_EN  # noqa: E402

COLLECTORS = {
    "en": {
        "Sahih Al-Bukhari": "Sahih Al-Bukhari",
        "Sahih Muslim": "Sahih Muslim",
        "Abu Dawud": "Abu Dawud",
        "At-Tirmidhi": "At-Tirmidhi",
        "An-Nasa'i": "An-Nasa'i",
        "Ibn Majah": "Ibn Majah",
        "Al-Bayhaqi": "Al-Bayhaqi",
        "Al-Azraqi": "Al-Azraqi",
        "Al-Hakim": "Al-Hakim",
        "Muslim": "Muslim",
        "Bukhari": "Bukhari",
    },
    "ar": {
        "Sahih Al-Bukhari": "صحيح البخاري",
        "Sahih Muslim": "صحيح مسلم",
        "Abu Dawud": "أبو داود",
        "At-Tirmidhi": "الترمذي",
        "An-Nasa'i": "النسائي",
        "Ibn Majah": "ابن ماجه",
        "Al-Bayhaqi": "البيهقي",
        "Al-Azraqi": "الأزرقي",
        "Al-Hakim": "الحاكم",
        "Muslim": "مسلم",
        "Bukhari": "البخاري",
    },
    "ur": {
        "Sahih Al-Bukhari": "صحیح البخاری",
        "Sahih Muslim": "صحیح مسلم",
        "Abu Dawud": "ابو داود",
        "At-Tirmidhi": "ترمذی",
        "An-Nasa'i": "نسائی",
        "Ibn Majah": "ابن ماجہ",
        "Al-Bayhaqi": "بیہقی",
        "Al-Azraqi": "ازرقی",
        "Al-Hakim": "حاکم",
        "Muslim": "مسلم",
        "Bukhari": "بخاری",
    },
    "fr": {
        "Sahih Al-Bukhari": "Sahih al-Boukhari",
        "Sahih Muslim": "Sahih Muslim",
        "Abu Dawud": "Abou Daoud",
        "At-Tirmidhi": "At-Tirmidhi",
        "An-Nasa'i": "An-Nasa'i",
        "Ibn Majah": "Ibn Majah",
        "Al-Bayhaqi": "Al-Bayhaqi",
        "Al-Azraqi": "Al-Azraqi",
        "Al-Hakim": "Al-Hakim",
        "Muslim": "Muslim",
        "Bukhari": "Boukhari",
    },
    "id": {
        "Sahih Al-Bukhari": "Shahih al-Bukhari",
        "Sahih Muslim": "Shahih Muslim",
        "Abu Dawud": "Abu Dawud",
        "At-Tirmidhi": "At-Tirmidhi",
        "An-Nasa'i": "An-Nasa'i",
        "Ibn Majah": "Ibnu Majah",
        "Al-Bayhaqi": "Al-Bayhaqi",
        "Al-Azraqi": "Al-Azraqi",
        "Al-Hakim": "Al-Hakim",
        "Muslim": "Muslim",
        "Bukhari": "Bukhari",
    },
    "tr": {
        "Sahih Al-Bukhari": "Sahih-i Buhari",
        "Sahih Muslim": "Sahih-i Müslim",
        "Abu Dawud": "Ebu Davud",
        "At-Tirmidhi": "Tirmizi",
        "An-Nasa'i": "Nesai",
        "Ibn Majah": "İbn Mace",
        "Al-Bayhaqi": "Behaki",
        "Al-Azraqi": "Ezraqi",
        "Al-Hakim": "Hakim",
        "Muslim": "Müslim",
        "Bukhari": "Buhari",
    },
}


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.load(resp)


def main() -> None:
    cats = fetch_json("https://ummahapi.com/api/duas/categories")["data"]["categories"]
    titles: dict[str, dict[str, str]] = {}
    locales = ["en", "ar", "ur", "fr", "id", "tr"]

    for cat in cats:
        cid = cat["id"]
        duas = fetch_json(f"https://ummahapi.com/api/duas/category/{cid}")["data"]["duas"]
        for d in duas:
            key = f"{cid}_{d['id']}"
            en_title = d["title"] or ""
            entry = {loc: en_title for loc in locales}
            entry["ar"] = AR_BY_EN.get(en_title, en_title)
            titles[key] = entry

    out = {
        "collectors": COLLECTORS,
        "titles": titles,
    }
    path = Path(__file__).resolve().parent.parent / "assets" / "muslim" / "dua_i18n.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(titles)} titles to {path}")


if __name__ == "__main__":
    main()
