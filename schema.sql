-- ============================================================
-- Smartphone.Mg — Schema base de données
-- Genere a partir du cahier des charges (section 11) + stock Loyverse a jour
-- Moteur cible : MySQL 8+ / MariaDB (adaptable PostgreSQL facilement)
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ---------- Utilisateurs & droits ----------
CREATE TABLE User (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    nom             VARCHAR(100) NOT NULL,
    role            ENUM('GERANT','PREPARATEUR','LIVREUR') NOT NULL,
    telephone       VARCHAR(20),
    actif           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ---------- Catalogue ----------
CREATE TABLE ProductCategory (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    nom             VARCHAR(50) NOT NULL UNIQUE,   -- HOUSSE, CACHE ECRAN, CHARGEUR...
    ordre           INT DEFAULT 0
);

CREATE TABLE ProductType (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    category_id     INT NOT NULL,
    nom             VARCHAR(50) NOT NULL,          -- FLIP COVER, Z-FOLD, Z-FLIP, PRIVACY
    UNIQUE KEY uq_type (category_id, nom),
    FOREIGN KEY (category_id) REFERENCES ProductCategory(id)
);

CREATE TABLE Brand (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    nom             VARCHAR(50) NOT NULL UNIQUE    -- Samsung, iPhone, Redmi, Xiaomi, Poco...
);

CREATE TABLE ProductReference (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    type_id         INT NOT NULL,
    brand_id        INT NOT NULL,
    reference_name  VARCHAR(100) NOT NULL,         -- ex: "A15", "S25 Ultra", "15 Pro Max", "6" (gen Z-Fold)
    prix_vente      DECIMAL(10,2) NOT NULL,
    actif           BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE KEY uq_reference (type_id, brand_id, reference_name),
    FOREIGN KEY (type_id) REFERENCES ProductType(id),
    FOREIGN KEY (brand_id) REFERENCES Brand(id)
);

CREATE TABLE ProductVariant (
    id                      INT AUTO_INCREMENT PRIMARY KEY,
    product_reference_id    INT NOT NULL,
    couleur                 VARCHAR(50) NOT NULL DEFAULT 'Standard',
    sku_loyverse            VARCHAR(30),            -- SKU d'origine Loyverse, pour tracabilite migration
    stock_actuel            INT NOT NULL DEFAULT 0,
    seuil_alerte            INT NOT NULL DEFAULT 1,
    UNIQUE KEY uq_variant (product_reference_id, couleur),
    FOREIGN KEY (product_reference_id) REFERENCES ProductReference(id)
);

-- ---------- Commandes ----------
CREATE TABLE `Order` (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    numero              VARCHAR(30) NOT NULL UNIQUE,   -- genere: ex SPMG-20260903-0001
    date_commande       DATE NOT NULL,
    client_nom          VARCHAR(100) NOT NULL,
    telephone           VARCHAR(20) NOT NULL,          -- format +261XXXXXXXXX
    livraison_zone      ENUM('ZONE1','ZONE2','ZONE3','RECUPERATION') NOT NULL,
    frais_livraison     DECIMAL(10,2) NOT NULL,
    total_a_payer       DECIMAL(10,2) NOT NULL,
    note                TEXT,
    statut_courant      ENUM('NOUVELLE','EN_PREPARATION','PRETE','EN_LIVRAISON','LIVRE','RETOUR') NOT NULL DEFAULT 'NOUVELLE',
    created_by_user_id  INT,
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by_user_id) REFERENCES User(id)
);

CREATE TABLE OrderItem (
    id                      INT AUTO_INCREMENT PRIMARY KEY,
    order_id                INT NOT NULL,
    product_variant_id      INT NOT NULL,
    prix_unitaire           DECIMAL(10,2) NOT NULL,    -- snapshot du prix au moment de la vente
    quantite                INT NOT NULL DEFAULT 1,
    FOREIGN KEY (order_id) REFERENCES `Order`(id),
    FOREIGN KEY (product_variant_id) REFERENCES ProductVariant(id)
);

CREATE TABLE OrderStatusHistory (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    order_id            INT NOT NULL,
    ancien_statut       VARCHAR(20),
    nouveau_statut      VARCHAR(20) NOT NULL,
    changed_by_user_id  INT,
    timestamp           DATETIME DEFAULT CURRENT_TIMESTAMP,
    note_eventuelle     TEXT,
    FOREIGN KEY (order_id) REFERENCES `Order`(id),
    FOREIGN KEY (changed_by_user_id) REFERENCES User(id)
);

-- ---------- Stock ----------
CREATE TABLE StockMovement (
    id                      INT AUTO_INCREMENT PRIMARY KEY,
    product_variant_id      INT NOT NULL,
    type                    ENUM('ENTREE','SORTIE') NOT NULL,
    quantite                INT NOT NULL,
    origine                 ENUM('LIVRE','RETOUR','FOURNISSEUR','AJUSTEMENT') NOT NULL,
    reference               VARCHAR(50),                -- order_id ou supplier_order_id
    timestamp               DATETIME DEFAULT CURRENT_TIMESTAMP,
    user_id                 INT,
    FOREIGN KEY (product_variant_id) REFERENCES ProductVariant(id),
    FOREIGN KEY (user_id) REFERENCES User(id)
);

-- ---------- Fournisseurs ----------
CREATE TABLE SupplierOrder (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    numero              VARCHAR(30) NOT NULL UNIQUE,
    date                DATE NOT NULL,
    description         TEXT,
    statut              ENUM('BROUILLON','COMMANDE','RECU') NOT NULL DEFAULT 'BROUILLON',
    total_qty           INT,
    prix_fournisseur    DECIMAL(12,2),
    fret_import         DECIMAL(12,2),
    douane              DECIMAL(12,2),
    meta_ads            DECIMAL(12,2),
    cout_total          DECIMAL(12,2) GENERATED ALWAYS AS
                            (IFNULL(prix_fournisseur,0)+IFNULL(fret_import,0)+IFNULL(douane,0)+IFNULL(meta_ads,0)) STORED,
    cout_unitaire       DECIMAL(12,2) GENERATED ALWAYS AS
                            (CASE WHEN total_qty > 0 THEN
                                (IFNULL(prix_fournisseur,0)+IFNULL(fret_import,0)+IFNULL(douane,0)+IFNULL(meta_ads,0)) / total_qty
                             ELSE 0 END) STORED
);

CREATE TABLE SupplierOrderLine (
    id                          INT AUTO_INCREMENT PRIMARY KEY,
    supplier_order_id           INT NOT NULL,
    product_variant_id          INT NOT NULL,
    quantite                    INT NOT NULL,
    cout_unitaire_calcule       DECIMAL(10,2),
    total_ligne                 DECIMAL(12,2),
    FOREIGN KEY (supplier_order_id) REFERENCES SupplierOrder(id),
    FOREIGN KEY (product_variant_id) REFERENCES ProductVariant(id)
);

SET FOREIGN_KEY_CHECKS = 1;
