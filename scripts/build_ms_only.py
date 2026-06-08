#!/usr/bin/env python3
"""Build ms.json from id.json with Malaysian Malay post-processing (no API)."""

from __future__ import annotations

import json
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent / "assets" / "translations"

MS_OVERRIDES: dict[str, str] = {
    "lang_en": "Inggeris",
    "lang_ar": "Arab",
    "lang_ur": "Urdu",
    "lang_fr": "Perancis",
    "lang_tr": "Turki",
    "lang_id": "Indonesia",
    "lang_fa": "Parsi",
    "lang_ms": "Melayu",
    "lang_persian": "Parsi",
    "lang_malay": "Melayu",
    "lang_english": "Inggeris",
    "lang_arabic": "Arab",
    "lang_urdu": "Urdu",
    "lang_french": "Perancis",
    "lang_indonesian": "Indonesia",
    "lang_turkish": "Turki",
    "app_name": "Munawwara Care",
    "app_title": "MUNAWWARA CARE",
    "call_support_display_name": "Munawwara Care",
    "device_care_app_name": "Munawwara Care",
    "btn_login": "Log Masuk",
    "forgot_password_back_to_login": "Kembali ke Log Masuk",
    "login_moderator_title": "Log Masuk Moderator",
    "login_pilgrim_title": "Log Masuk Jemaah",
    "login_as_pilgrim": "Log masuk sebagai jemaah",
    "login_as_moderator": "Log masuk sebagai moderator",
    "area_name_desc_header": "Nama & Penerangan",
    "area_date_label": "Tarikh",
    "area_time_label": "Masa",
    "provisioning_required": "Diperlukan",
    "provisioning_invalid": "Tidak sah",
    "manage_filter_manual": "Manual",
    "welcome_back": "Selamat kembali",
    "inbox_filter_only_you": "Hanya anda",
    "resend_code_countdown": "Hantar semula dalam {}s",
    "forgot_password_resend_countdown": "Hantar semula dalam {}s",
    "nav_provisioning": "PERUNTUKAN",
    "provision_tab_provision": "Peruntukan",
    "reminder_schedule_page_subtitle": (
        "Jadualkan siaran untuk kumpulan atau individu."
    ),
    "reminder_target_audience": "Hantar kepada",
    "reminder_audience_system_wide": "Seluruh Sistem",
    "reminder_label_start_date": "Tarikh",
    "reminder_label_start_time": "Masa",
    "reminder_scheduling_section": "Bila & ulangan",
    "dashboard_delete_body": (
        "Adakah anda pasti mahu memadam \"{name}\"? "
        "Tindakan ini tidak boleh dibuat asal dan semua jemaah "
        "akan dikeluarkan daripada kumpulan."
    ),
    "hint_phone": "+60 12-345 6789",
    "hint_email": "jemaah@contoh.com",
}


def id_to_ms(text: str) -> str:
    """Convert Indonesian UI strings to Malaysian Malay."""
    reps: list[tuple[str, str]] = [
        ("Grup", "Kumpulan"),
        ("grup", "kumpulan"),
        ("Akun", "Akaun"),
        ("akun", "akaun"),
        ("Rekening", "Akaun"),
        ("rekening", "akaun"),
        ("Nomor", "Nombor"),
        ("nomor", "nombor"),
        ("Kata Sandi", "Kata Laluan"),
        ("Kata sandi", "Kata laluan"),
        ("kata sandi", "kata laluan"),
        ("Unduh", "Muat turun"),
        ("unduh", "muat turun"),
        ("Berhasil", "Berjaya"),
        ("berhasil", "berjaya"),
        ("Silakan", "Sila"),
        ("silakan", "sila"),
        ("Apakah ", "Adakah "),
        ("apakah ", "adakah "),
        ("Kirim", "Hantar"),
        ("kirim", "hantar"),
        ("Pesan", "Mesej"),
        ("pesan", "mesej"),
        ("Telepon", "Telefon"),
        ("telepon", "telefon"),
        ("Inggris", "Inggeris"),
        ("inggris", "Inggeris"),
        ("Prancis", "Perancis"),
        ("prancis", "Perancis"),
        ("Hapus", "Padam"),
        ("hapus", "padam"),
        ("gratis", "percuma"),
        ("Gratis", "Percuma"),
        ("Coba lagi", "Cuba lagi"),
        ("coba lagi", "cuba lagi"),
        ("Coba", "Cuba"),
        ("coba", "cuba"),
        ("Unggah", "Muat naik"),
        ("unggah", "muat naik"),
        ("Diperbarui", "Dikemas kini"),
        ("diperbarui", "dikemas kini"),
        ("Perbarui", "Kemas kini"),
        ("perbarui", "kemas kini"),
        ("Bahasa Indonesia", "Bahasa Melayu"),
        ("orang ", ""),
        ("Orang ", ""),
        ("Jamaah", "Jemaah"),
        ("jamaah", "jemaah"),
        ("Peziarah", "Jemaah"),
        ("peziarah", "jemaah"),
        ("Shalat", "Solat"),
        ("shalat", "solat"),
        ("Dzuhur", "Zohor"),
        ("dzuhur", "zohor"),
        ("Ashar", "Asar"),
        ("ashar", "asar"),
        ("Luring", "Luar talian"),
        ("luring", "luar talian"),
        ("Gabung", "Sertai"),
        ("gabung", "sertai"),
        ("Bergabung", "Menyertai"),
        ("bergabung", "menyertai"),
        ("Obrolan", "Sembang"),
        ("obrolan", "sembang"),
        ("Kedaluwarsa", "Tamat tempoh"),
        ("kedaluwarsa", "tamat tempoh"),
        ("Tertunda", "Belum selesai"),
        ("tertunda", "belum selesai"),
        ("bertahun-tahun", "tahun"),
        ("PROVISI", "PERUNTUKAN"),
        ("Provisi", "Peruntukan"),
        ("provisi", "peruntukan"),
        ("Penyediaan", "Peruntukan"),
        ("penyediaan", "peruntukan"),
        ("Hanya kamu", "Hanya anda"),
        ("hanya kamu", "hanya anda"),
        ("Kamu ", "Anda "),
        ("kelompok", "kumpulan"),
        ("Tercover", "Dilindungi"),
        ("tercover", "dilindungi"),
        ("Sumber Daya", "Sumber"),
        ("sumber daya", "sumber"),
        ("Log masukkan", "Masukkan"),
        ("Log Masukkan", "Masukkan"),
        ("Segarkan", "Muat semula"),
        ("segarkan", "muat semula"),
        ("Pengaturan", "Tetapan"),
        ("pengaturan", "tetapan"),
        ("Aplikasi", "Apl"),
        ("aplikasi", "apl"),
        ("{}d", "{}s"),
        (" {}d", " {}s"),
        ("Kirim ulang dalam {}d", "Hantar semula dalam {}s"),
        ("Kirim Ulang", "Hantar Semula"),
        ("kirim ulang", "hantar semula"),
        ("Kirim Ulang Kode", "Hantar Semula Kod"),
        ("Kode", "Kod"),
        ("kode", "kod"),
        ("Seluruh sistem", "Seluruh sistem"),
        ("SASARAN AUDIENS", "SASARAN AUDIENS"),
        ("TANGGAL MULAI", "TARIKH MULA"),
        ("WAKTU MULAI", "MASA MULA"),
        ("Opsi penjadwalan", "Bila & ulangan"),
        ("Name & Description", "Nama & Penerangan"),
        ("Date", "Tarikh"),
        ("Time", "Masa"),
        ("Required", "Diperlukan"),
        ("Invalid", "Tidak sah"),
        ("petunjuk", "Manual"),
        ("Sunting", "Sunting"),
        ("Grup pencarian", "Cari kumpulan"),
        ("check-in to", "daftar kehadiran ke"),
        ("Check In", "Daftar Kehadiran"),
        ("check-in", "daftar kehadiran"),
        ("Check-in", "Daftar kehadiran"),
        ("Mekkah", "Makkah"),
        ("Madinah", "Madinah"),
        ("Masjidil Haram", "Masjid al-Haram"),
        ("zam-zam", "Zamzam"),
        ("Zam-zam", "Zamzam"),
    ]
    out = text
    for old, new in reps:
        out = out.replace(old, new)
    return out


def main() -> None:
    en: dict[str, str] = json.loads((BASE / "en.json").read_text("utf-8"))
    id_data: dict[str, str] = json.loads((BASE / "id.json").read_text("utf-8"))
    keys = list(en.keys())
    ms: dict[str, str] = {}
    for key in keys:
        if key in MS_OVERRIDES:
            ms[key] = MS_OVERRIDES[key]
        elif key in id_data:
            ms[key] = id_to_ms(id_data[key])
        else:
            ms[key] = en[key]
    ordered = {k: ms[k] for k in keys}
    (BASE / "ms.json").write_text(
        json.dumps(ordered, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"ms.json: {len(ms)} keys")
    print(f"match en: {set(ms.keys()) == set(keys)}")


if __name__ == "__main__":
    main()
