# VêteMart - Système Complet de Gestion des Stocks de Vêtements

![Version](https://img.shields.io/badge/version-2.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-Production%20Ready-success)

Un système moderne et complet de gestion des stocks de vêtements construite avec **Next.js 16**, **React 19**, **Django Backend**, et **shadcn/ui**.

> **⚡ Migration: Supabase → Django Backend avec JWT Authentication**  
> Cette version utilise un backend Django personnalisé au lieu de Supabase. Voir [MIGRATION_SUMMARY.md](./MIGRATION_SUMMARY.md) pour les détails.

## ✨ Fonctionnalités Principales

### 📊 Dashboard Intelligent
- 4 graphiques analytiques en temps réel
- Vue d'ensemble des stocks
- Alertes visuelles de rupture
- Statistiques clés

### 👔 Gestion Complète des Vêtements
- **Catégories**: Hommes, Femmes, Enfants
- **Tailles**: S, M, XL, XXL
- **Attributs**: Couleur, Matière, Price, Location
- **Import/Export** Excel
- **Recherche** et **filtrage** avancés

### 📸 Images avec Codes QR
- **Upload d'images** facile (Drag & Drop)
- **Génération automatique** de codes QR
- **Identification rapide** des produits
- **Galerie complète** par produit
- **Téléchargement** des QR codes

### 🚨 Système d'Alertes
- **Alertes automatiques** stock bas
- **Notifications rupture** de stock
- **Suivi et résolution** des alertes
- **Dashboard alertes** dédié

### 📈 Rapports Professionnels
- **Top produits** (par ventes)
- **Distribution par taille**
- **Performance catégories**
- **Produits lents**
- **Export Excel** complet

### 📋 Mouvements de Stock
- **Entrées/Sorties** détaillées
- **Historique complet**
- **Notes et commentaires**
- **Audit trail** complet

### 👥 Authentification & Sécurité
- **Authentification Supabase**
- **Row Level Security (RLS)**
- **Contrôle d'accès** par rôle
- **Hash sécurisé** des mots de passe

## 🚀 Démarrage Rapide

### Installation (5 minutes)

```bash
# 1. Cloner le projet
git clone <repository-url> && cd vetement-stock

# 2. Installer les dépendances
pnpm install

# 3. Configuration Supabase
# Copier-coller dans .env.local (voir ENV_A_COPIER.txt):
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_anon_xxx
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...

# 4. Appliquer migrations
pnpm db:migrate

# 5. Lancer serveur développement
pnpm dev

# 6. Ouvrir http://localhost:3000
```

## 📚 Documentation

| Document | Contenu |
|----------|---------|
| **GUIDE_COMPLET.md** | Guide d'utilisation complet (recommandé) |
| **README_VETEMENTS.md** | Spécifications des vêtements |
| **DEMARRAGE_RAPIDE.md** | Installation rapide |
| **TECH_CHANGES.md** | Détails techniques modifications |
| **ENV_A_COPIER.txt** | Variables d'environnement |

👉 **Commencez par**: [GUIDE_COMPLET.md](./GUIDE_COMPLET.md)

## 🏗️ Architecture

```
vetement-stock/
├── app/                      # Next.js App Router
│   ├── (app)/               # Routes protégées
│   │   ├── dashboard/       # Tableau de bord
│   │   ├── products/        # Gestion vêtements
│   │   ├── alerts/          # Alertes stock
│   │   ├── reports/         # Rapports
│   │   ├── movements/       # Mouvements
│   │   ├── suppliers/       # Fournisseurs
│   │   ├── users/           # Utilisateurs
│   │   └── settings/        # Paramètres
│   ├── login/               # Authentification
│   └── layout.tsx           # Layout principal
│
├── components/              # Composants React
│   ├── layout/              # Layout components
│   ├── ui/                  # shadcn/ui components
│   ├── product-image-gallery.tsx
│   └── image-upload.tsx
│
├── lib/                     # Utilitaires
│   ├── supabase/           # Clients Supabase
│   ├── qrcode-generator.ts # Génération QR codes
│   ├── image-service.ts    # Gestion images
│   ├── validation.ts       # Schémas Zod
│   └── utils.ts
│
├── supabase/               # Migrations SQL
│   └── migrations/
│       ├── 20240010_clothing_stock_system.sql
│       └── 20240011_add_images_qrcode.sql
│
└── public/                 # Assets statiques
```

## 🗄️ Schéma Base de Données

### Tables principales

- **products** - Vêtements (SKU, nom, catégorie, prix)
- **product_sizes** - Quantités par taille (S/M/XL/XXL)
- **product_images** - Images avec codes QR
- **stock_alerts** - Alertes stock bas
- **stock_movements** - Historique entrées/sorties
- **product_stats** - Statistiques (ventes, achats)

## 🛠️ Stack Technique

| Layer | Technologie |
|-------|------------|
| **Frontend** | Next.js 16, React 19, TypeScript |
| **Styling** | Tailwind CSS v4, shadcn/ui |
| **Database** | Supabase (PostgreSQL) |
| **Auth** | Supabase Auth |
| **Forms** | React Hook Form + Zod |
| **Charts** | Recharts |
| **QR Codes** | qrcode.react |
| **Excel** | xlsx |
| **Package Manager** | pnpm |

## 📦 Commandes Disponibles

```bash
# Développement
pnpm dev              # Lancer serveur développement
pnpm build            # Build production
pnpm start            # Lancer serveur production
pnpm lint             # Vérifier code lint

# Base de données
pnpm db:migrate       # Exécuter migrations
pnpm db:seed          # Insérer données test
pnpm db:reset         # Réinitialiser DB
pnpm db:migrate:status # Voir statut
```

## 🔐 Sécurité

- ✅ **Authentification JWT** via Supabase
- ✅ **RLS (Row Level Security)** sur toutes les tables
- ✅ **Validation Zod** côté serveur et client
- ✅ **CSRF protection** avec Next.js
- ✅ **Environnement variables** sécurisé
- ✅ **Hash bcrypt** des mots de passe

## 🎯 Cas d'Usage

### Petites Boutiques
- Gérer 50-100 produits
- Suivi simple des stocks
- Alertes de rupture

### Magasins Moyens
- Gestion multi-catégories
- Rapports analytiques
- Export Excel
- Images de produits

### Chaînes de Distribution
- Suivi détaillé variantes
- Analytics avancées
- Codes QR traçabilité
- Audit complet

## 📈 Métriques

Le système suit automatiquement:
- Nombre de ventes par produit
- Nombre d'achats
- Mouvements totaux
- Distribution par taille
- Performance par catégorie

## 🐛 Dépannage

### Le serveur ne démarre pas
```bash
# Vérifier Node.js
node --version

# Réinstaller dépendances
rm -rf node_modules pnpm-lock.yaml
pnpm install
```

### Erreur Supabase
1. Vérifier les clés dans `.env.local`
2. Vérifier que les migrations sont appliquées
3. Vérifier les logs: `pnpm db:migrate:status`

### Images ne s'affichent pas
- Vérifier format (JPEG, PNG, WebP)
- Vérifier taille (< 5MB)
- Vider cache navigateur (Ctrl+Shift+Del)

## 📞 Support

- 📖 Documentation: [GUIDE_COMPLET.md](./GUIDE_COMPLET.md)
- 🐛 Problème: Lire FAQ dans la doc
- 📧 Supabase Help: https://supabase.com/help
- 💬 Next.js Docs: https://nextjs.org/docs

## 📄 Licence

MIT License - Libre d'utilisation

## 🤝 Contribution

Les contributions sont les bienvenues! 

## 🙏 Remerciements

- Supabase pour la base de données
- shadcn/ui pour les composants
- Vercel pour Next.js
- la communauté React

---

**Version**: 2.0.0  
**Dernière mise à jour**: 2024-12-20  
**Statut**: Production Ready ✅

**Prêt à démarrer?** → [Voir le guide complet](./GUIDE_COMPLET.md)
