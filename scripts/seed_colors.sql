-- Peuple catalog_color (le sélecteur "Choisir une couleur" de Paramètres du
-- catalogue / Nouvelle référence) avec les 16 couleurs déjà réellement
-- utilisées dans les variantes du catalogue Smartphone.Mg — cette table est
-- vide par défaut après un seed_smartphone (elle n'est pas peuplée par la
-- commande, contrairement à ProductCategory/Type/Brand/Reference/Variant).
--
-- Idempotent : ON CONFLICT sur la contrainte unique (magasin_id, nom) —
-- sans risque de le rejouer.
--
-- Usage sur le VPS (depuis ~/Smartphone) :
--   docker compose -f docker-compose.prod.yml exec -T db psql -U "$DB_USER" -d "$DB_NAME" < scripts/seed_colors.sql
-- (DB_USER/DB_NAME = ceux du .env du VPS ; ou ouvrir un psql interactif via
--  `docker compose -f docker-compose.prod.yml exec db psql -U <user> -d <db>`
--  et coller le contenu.)

INSERT INTO catalog_color (magasin_id, nom)
SELECT (SELECT id FROM users_magasinprofile WHERE shop_name = 'Smartphone.Mg' LIMIT 1), c.nom
FROM (VALUES
    ('Bleu'),
    ('Bleu be'),
    ('Bleu ciel'),
    ('Bleu foncé'),
    ('Gris'),
    ('Jaune'),
    ('Marron'),
    ('Noir'),
    ('Orange'),
    ('Rose'),
    ('Rouge'),
    ('Standard'),
    ('Vert'),
    ('Vert be'),
    ('Vert kely'),
    ('Violet')
) AS c(nom)
ON CONFLICT (magasin_id, nom) DO NOTHING;
