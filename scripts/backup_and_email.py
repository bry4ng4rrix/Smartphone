#!/usr/bin/env python3
"""Sauvegarde compressée (base SQLite + images uploadées) envoyée par email.

Usage:
    python scripts/backup_and_email.py

Variables d'environnement requises (dans un fichier .env à la racine ou dans l'environnement shell) :
    SMTP_HOST, SMTP_USER, SMTP_PASSWORD, BACKUP_EMAIL_TO

Variables optionnelles :
    SMTP_PORT       (par défaut : 587)
    SMTP_USE_TLS    (par défaut : true)
    BACKUP_EMAIL_FROM (par défaut : SMTP_USER)
"""

import os
import smtplib
import sys
import zipfile
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

BASE_DIR = Path(__file__).resolve().parent.parent
DB_PATH = BASE_DIR / "db.sqlite3"
MEDIA_DIR = BASE_DIR / "media"
BACKUP_DIR = BASE_DIR / "backups"

MAX_ATTACHMENT_SIZE = 24 * 1024 * 1024  # marge sous la limite de 25 Mo de Gmail


def build_archive() -> Path:
    BACKUP_DIR.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    archive_path = BACKUP_DIR / f"backup_{timestamp}.zip"

    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        if DB_PATH.exists():
            zf.write(DB_PATH, arcname="db.sqlite3")
        else:
            print(f"Attention : base de données introuvable ({DB_PATH})", file=sys.stderr)

        if MEDIA_DIR.exists():
            for file_path in MEDIA_DIR.rglob("*"):
                if file_path.is_file():
                    zf.write(file_path, arcname=file_path.relative_to(BASE_DIR))
        else:
            print(f"Attention : dossier media introuvable ({MEDIA_DIR})", file=sys.stderr)

    return archive_path


def send_email(archive_path: Path) -> None:
    smtp_host = os.environ["SMTP_HOST"]
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    smtp_user = os.environ["SMTP_USER"]
    smtp_password = os.environ["SMTP_PASSWORD"]
    use_tls = os.environ.get("SMTP_USE_TLS", "true").lower() in ("1", "true", "yes")
    recipients = [addr.strip() for addr in os.environ["BACKUP_EMAIL_TO"].split(",") if addr.strip()]
    sender = os.environ.get("BACKUP_EMAIL_FROM", smtp_user)

    size = archive_path.stat().st_size
    if size > MAX_ATTACHMENT_SIZE:
        raise SystemExit(
            f"L'archive ({size / 1024 / 1024:.1f} Mo) dépasse la taille maximale autorisée "
            f"({MAX_ATTACHMENT_SIZE / 1024 / 1024:.0f} Mo) pour une pièce jointe email."
        )

    message = EmailMessage()
    message["Subject"] = f"Sauvegarde Stock_v2 - {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    message["From"] = sender
    message["To"] = ", ".join(recipients)
    message.set_content(
        "Sauvegarde automatique de la base de données et des images uploadées.\n"
        f"Fichier : {archive_path.name}\n"
        f"Taille : {size / 1024 / 1024:.2f} Mo"
    )

    with open(archive_path, "rb") as f:
        message.add_attachment(
            f.read(),
            maintype="application",
            subtype="zip",
            filename=archive_path.name,
        )

    with smtplib.SMTP(smtp_host, smtp_port) as smtp:
        if use_tls:
            smtp.starttls()
        smtp.login(smtp_user, smtp_password)
        smtp.send_message(message)


def main() -> int:
    archive_path = build_archive()
    print(f"Archive créée : {archive_path} ({archive_path.stat().st_size / 1024 / 1024:.2f} Mo)")

    try:
        send_email(archive_path)
    except KeyError as exc:
        print(f"Variable d'environnement manquante : {exc}", file=sys.stderr)
        return 1

    print("Email de sauvegarde envoyé avec succès.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
