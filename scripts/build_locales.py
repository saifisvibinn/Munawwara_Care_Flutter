#!/usr/bin/env python3
"""Build fa.json from ur.json (Persian script base) and ms.json from id.json."""

from __future__ import annotations

import json
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent / "assets" / "translations"

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

# Urdu UI patterns -> natural Persian (formal app tone)
UR_TO_FA = [
    (r"\bآپ\b", "شما"),
    (r"\bاپ\b", "اپ"),  # keep app
    (r"کریں\b", "کنید"),
    (r"کرے\b", "کند"),
    (r"کر\s", "کن "),
    (r"ہے\b", "است"),
    (r"ہیں\b", "هستند"),
    (r"ہو\b", "باش"),
    (r"ہوگا\b", "خواهد بود"),
    (r"نہیں\b", "نیست"),
    (r"کیا\b", "آیا"),
    (r"سے\b", "از"),
    (r"میں\b", "در"),
    (r"پر\b", "روی"),
    (r"کے\s", " "),
    (r"کی\s", " "),
    (r"کا\s", " "),
    (r"لاگ ان\b", "ورود"),
    (r"سائن\s*آؤٹ\b", "خروج"),
    (r"پاسورڈ\b", "رمز عبور"),
    (r"خوش آمدید\b", "خوش آمدید"),
    (r"تلاش\b", "جستجو"),
    (r"منسوخ\b", "لغو"),
    (r"تصدیق\b", "تأیید"),
    (r"حذف\b", "حذف"),
    (r"ہاں\b", "بله"),
    (r"جی\b", "بله"),
    (r"نہ\b", "خیر"),
    (r"بھیج\b", "ارسال"),
    (r"موصول\b", "دریافت"),
    (r"گروپ\b", "گروه"),
    (r"حاج\b", "زائر"),
    (r"حاجی\b", "زائر"),
    (r"مشرف\b", "ناظر"),
    (r"مڈریٹر\b", "ناظر"),
]

ID_TO_MS = [
    ("Grup", "Kumpulan"), ("grup", "kumpulan"),
    ("Akun", "Akaun"), ("akun", "akaun"),
    ("Nomor", "Nombor"), ("nomor", "nombor"),
    ("Kata sandi", "Kata laluan"), ("kata sandi", "kata laluan"),
    ("Unduh", "Muat turun"), ("unduh", "muat turun"),
    ("Berhasil", "Berjaya"), ("berhasil", "berjaya"),
    ("Silakan", "Sila"), ("silakan", "sila"),
    ("Apakah ", "Adakah "), ("apakah ", "adakah "),
    ("Kirim", "Hantar"), ("kirim", "hantar"),
    ("Pesan", "Mesej"), ("pesan", "mesej"),
    ("Telepon", "Telefon"), ("telepon", "telefon"),
    ("Inggris", "Inggeris"), ("inggris", "Inggeris"),
    ("Hapus", "Padam"), ("hapus", "padam"),
    ("gratis", "percuma"), ("Gratis", "Percuma"),
    ("Masuk", "Log masuk"), ("masuk", "log masuk"),
    ("Keluar", "Log keluar"), ("keluar", "log keluar"),
    ("Coba lagi", "Cuba lagi"), ("coba lagi", "cuba lagi"),
    ("Coba", "Cuba"), ("coba", "coba"),
    ("Unggah", "Muat naik"), ("unggah", "muat naik"),
    ("Diperbarui", "Dikemas kini"), ("diperbarui", "dikemas kini"),
    ("Perbarui", "Kemas kini"), ("perbarui", "kemas kini"),
    ("Bahasa Indonesia", "Bahasa Melayu"),
    ("Selamat datang", "Selamat kembali"),
    ("Daftar", "Daftar"),
    ("Simpan", "Simpan"),
    ("Batal", "Batal"),
    ("Ya", "Ya"),
    ("Tidak", "Tidak"),
    ("orang ", ""), ("Orang ", ""),
    ("Jemaah", "Jemaah"),
    ("Haji", "Haji"),
    ("Umrah", "Umrah"),
]


def ur_to_fa(text: str) -> str:
    out = text
    for pat, repl in UR_TO_FA:
        out = re.sub(pat, repl, out)
    return out


def id_to_ms(text: str) -> str:
    out = text
    for a, b in ID_TO_MS:
        out = out.replace(a, b)
    return out


def main() -> None:
    en = json.loads((BASE / "en.json").read_text("utf-8"))
    ur = json.loads((BASE / "ur.json").read_text("utf-8"))
    ar = json.loads((BASE / "ar.json").read_text("utf-8"))
    id_data = json.loads((BASE / "id.json").read_text("utf-8"))
    keys = list(en.keys())

    fa: dict[str, str] = {}
    for k in keys:
        if k in FA_OVERRIDES:
            fa[k] = FA_OVERRIDES[k]
        elif k in ur:
            fa[k] = ur_to_fa(ur[k])
        elif k in ar:
            fa[k] = ar[k]  # fallback Arabic script
        else:
            fa[k] = en[k]
    (BASE / "fa.json").write_text(
        json.dumps(fa, ensure_ascii=False, indent=2) + "\n", "utf-8")

    ms: dict[str, str] = {}
    for k in keys:
        if k in MS_OVERRIDES:
            ms[k] = MS_OVERRIDES[k]
        elif k in id_data:
            ms[k] = id_to_ms(id_data[k])
        else:
            ms[k] = id_to_ms(en[k]) if False else en[k]
    (BASE / "ms.json").write_text(
        json.dumps(ms, ensure_ascii=False, indent=2) + "\n", "utf-8")

    print(f"en: {len(keys)}")
    print(f"fa: {len(fa)} match={set(fa)==set(en)}")
    print(f"ms: {len(ms)} match={set(ms)==set(en)}")


if __name__ == "__main__":
    main()
