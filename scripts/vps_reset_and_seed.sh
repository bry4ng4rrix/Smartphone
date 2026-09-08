#!/usr/bin/env bash
# Réinitialise et reseed la base Postgres du VPS avec le tenant Smartphone.Mg
# (comptes gérant/préparateur/livreur nommés + catalogue réel), après une
# sauvegarde automatique.
#
# À exécuter SUR LE VPS, depuis la racine du repo, après un `git pull` (pour
# récupérer les derniers comptes/migrations — voir roadmap.md §8) :
#
#   cd ~/smartphone && git pull origin main
#   docker compose -f docker-compose.prod.yml up -d --build   # migrations auto au démarrage
#   ./scripts/vps_reset_and_seed.sh
#
# Ce que fait ce script, dans l'ordre :
#   1. Sauvegarde complète de la base Postgres (pg_dump) dans ce dossier,
#      AVANT toute suppression — c'est le seul filet de sécurité.
#   2. S'assure que les migrations sont à jour.
#   3. Demande confirmation, puis supprime tout le tenant Smartphone.Mg
#      existant (commandes, mouvements de stock, catalogue, commandes
#      fournisseur, comptes gérant/préparateur/livreur — voir
#      seed_smartphone.py::Command._reset_tenant) et reseed à neuf :
#        - Gérant : gerant@smartphone.mg
#        - Préparateurs : Lili, Miora, Tiana
#        - Livreurs : Livreko Express, Ambinintsoa, Onitiana, Fenosoa, Zetra Express
#        - Catalogue réel (catalog/management/commands/data/seed_catalogue.sql
#          — ~300 références, ~530 variantes couleur)
#      Mot de passe de tous ces comptes de démo : smartphone2026 (à changer
#      avant d'exposer le VPS publiquement — voir roadmap.md §7).
#
# Ne touche à rien d'autre : autres tenants éventuels, comptes plateforme
# Label Technology, magasins/chat/notifications/caisse d'autres tenants.
#
# ATTENTION : l'étape 3 est destructive pour les données Smartphone.Mg du VPS
# (y compris des commandes/stock en cours). Vérifiez la sauvegarde de
# l'étape 1 avant de confirmer si ce VPS contient des données auxquelles vous
# tenez.

set -euo pipefail
cd "$(dirname "$0")/.."

COMPOSE="docker compose -f docker-compose.prod.yml"

echo "=== 1/3 — Sauvegarde Postgres ==="
BACKUP_FILE="backup_smartphonemg_$(date +%Y%m%d_%H%M%S).sql"
$COMPOSE exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$BACKUP_FILE"
echo "Sauvegarde écrite : $(pwd)/$BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"

echo
echo "=== 2/3 — Migrations ==="
$COMPOSE exec -T backend python manage.py migrate --noinput

echo
echo "=== 3/3 — Reset + reseed du tenant Smartphone.Mg ==="
echo "Ceci va SUPPRIMER les commandes/stock/catalogue/comptes Smartphone.Mg"
echo "existants (la sauvegarde ci-dessus a déjà été faite)."
read -r -p "Continuer ? (oui/non) " confirm
if [ "$confirm" != "oui" ]; then
  echo "Annulé — aucune donnée supprimée (sauvegarde conservée : $BACKUP_FILE)."
  exit 1
fi

$COMPOSE exec -T backend python manage.py seed_smartphone --reset

echo
echo "=== Vérification ==="
$COMPOSE exec -T backend python manage.py shell -c "
from users.models import MagasinProfile, CustomUser
from catalog.models import ProductReference, ProductVariant
m = MagasinProfile.objects.get(shop_name='Smartphone.Mg')
print('Magasin :', m.shop_name)
print('Comptes  :', CustomUser.objects.filter(email__endswith='@smartphone.mg').count())
print('Références :', ProductReference.objects.filter(type__category__magasin=m).count())
print('Variantes  :', ProductVariant.objects.filter(product_reference__type__category__magasin=m).count())
"

echo
echo "Terminé. Sauvegarde conservée : $(pwd)/$BACKUP_FILE"
