#!/usr/bin/env bash
# Lance le backend en local contre PostgreSQL (voir .env.local) au lieu du
# SQLite par défaut de Stock/settings.py. Utilisation : ./run_local.sh
# (ou ./run_local.sh migrate, ./run_local.sh shell, etc. — tout argument est
# transmis tel quel à manage.py).
set -euo pipefail
cd "$(dirname "$0")"

set -a
source .env.local
set +a

CMD="${*:-runserver 8010}"
exec .venv/bin/python manage.py $CMD
