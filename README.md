# Application Stock - Gestion de Users et Produits

## 📋 Description

Cette application Django gère un système multi-rôles pour la gestion de stock avec trois types d'utilisateurs :
- **Admin**: Gère l'ensemble du système
- **Magasin**: Gère son propre magasin et ses produits
- **Employer**: Travaille dans un magasin et gère les produits assignés

## 🏗️ Structure de l'application

```
users/
├── models.py           # Modèles de données
├── views.py            # Vues API
├── urls.py             # Configuration des URLs
├── serializers.py      # Sérialiseurs DRF
├── authentication.py   # Authentification JWT personnalisée
├── permissions.py      # Permissions personnalisées
└── admin.py            # Administration Django
```

## 🗄️ Modèles de données

### CustomUser
Modèle utilisateur personnalisé héritant de `AbstractUser`

**Champs:**
- `full_name`: Nom complet
- `email`: Email unique (USERNAME_FIELD)
- `phone`: Numéro de téléphone (optionnel)
- `role`: Rôle de l'utilisateur (admin/magasin/employer)
- `is_confirmed`: Statut de confirmation du compte
- `created_at`: Date de création
- `updated_at`: Date de dernière mise à jour

**Rôles disponibles:**
- `admin`: Accès complet, admin Django
- `magasin`: Gère un magasin spécifique
- `employer`: Employé d'un magasin

### AdminProfile
Profil pour les administrateurs

**Champs:**
- `user`: Relation OneToOne avec CustomUser
- `company_name`: Nom de l'entreprise
- `logo`: Logo de l'entreprise

### MagasinProfile
Profil pour les gérants de magasin

**Champs:**
- `user`: Relation OneToOne avec CustomUser
- `admin`: ForeignKey vers l'admin propriétaire
- `shop_name`: Nom du magasin
- `shop_logo`: Logo du magasin

### EmployerProfile
Profil pour les employés

**Champs:**
- `user`: Relation OneToOne avec CustomUser
- `magasin`: ForeignKey vers le magasin (optionnel)
- `admin`: ForeignKey vers l'admin (optionnel)
- `position`: Poste de l'employé

### Product
Modèle pour les produits en stock

**Champs:**
- `name`: Nom du produit
- `reference`: Référence unique
- `brand`: Marque (optionnel)
- `category`: Catégorie
- `description`: Description (optionnel)
- `unit_price`: Prix unitaire
- `initial_quantity`: Quantité initiale
- `alert_threshold`: Seuil d'alerte
- `expiry_date`: Date d'expiration (optionnel)
- `magasin`: ForeignKey vers MagasinProfile
- `image1`, `image2`, `image3`: Images du produit (optionnelles)

## 🔌 API Endpoints

Base URL: `/api/users/`

### Authentification

#### POST `/api/users/login/`
Connexion personnalisée avec JWT
- **Body**: `{ "username": "email", "password": "password" }`
- **Response**: Tokens JWT (access + refresh)
- **Note**: Vérifie que le compte est confirmé (`is_confirmed=True`)

#### POST `/api/users/refresh/`
Rafraîchir le token d'accès
- **Body**: `{ "refresh": "refresh_token" }`
- **Response**: Nouveau access token

### Gestion des utilisateurs

#### POST `/api/users/register/`
Inscription d'un nouvel utilisateur
- **Body**: 
  ```json
  {
    "full_name": "string",
    "email": "string",
    "password": "string",
    "phone": "string",
    "role": "admin|magasin|employer",
    "company_name": "string",  // Pour admin
    "shop_name": "string",      // Pour magasin
    "position": "string",       // Pour employer
    "admin_email": "string"     // Email de l'admin (pour magasin/employer)
  }
  ```
- **Response**: Message de succès

#### GET `/api/users/me/`
Profil de l'utilisateur connecté
- **Auth**: Requis (JWT token)
- **Response**: Informations de l'utilisateur connecté

#### PUT `/api/users/approve/<user_id>/`
Approuver un compte utilisateur
- **Auth**: Requis (admin ou magasin uniquement)
- **Response**: Message de succès

### Gestion des produits

#### GET `/api/users/products/`
Liste des produits
- **Auth**: Requis
- **Filtrage par rôle:**
  - Admin: Tous les produits
  - Magasin: Produits de son magasin
  - Employer: Produits de son magasin

#### POST `/api/users/products/`
Créer un produit
- **Auth**: Requis (admin ou magasin uniquement)
- **Body**: Données du produit + `magasin` (optionnel pour admin)

#### GET `/api/users/products/<id>/`
Détails d'un produit
- **Auth**: Requis

#### PUT `/api/users/products/<id>/`
Mettre à jour un produit (complet)
- **Auth**: Requis (admin uniquement)

#### PATCH `/api/users/products/<id>/`
Mise à jour partielle d'un produit
- **Auth**: Requis (admin uniquement)

#### DELETE `/api/users/products/<id>/`
Supprimer un produit
- **Auth**: Requis (admin uniquement)

## 🔐 Authentification & Permissions

### JWT Token
L'application utilise `rest_framework_simplejwt` pour l'authentification.

**CustomTokenObtainPairSerializer:**
- Vérifie que `is_confirmed=True` avant d'attribuer un token
- Retourne une erreur si le compte n'est pas approuvé

### Permissions personnalisées

#### IsAdmin
Accès réservé aux utilisateurs avec `role="admin"`

#### IsMagasin
Accès réservé aux utilisateurs avec `role="magasin"`

#### IsEmployer
Accès réservé aux utilisateurs avec `role="employer"`

## 🚀 Comment ajouter de nouvelles fonctionnalités

### 1. Ajouter un nouveau modèle

Dans `models.py`:
```python
class NouveauModele(models.Model):
    nom = models.CharField(max_length=255)
    description = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    
    def __str__(self):
        return self.nom
```

Puis créer les migrations:
```bash
python manage.py makemigrations
python manage.py migrate
```

### 2. Créer un sérialiseur

Dans `serializers.py`:
```python
class NouveauModeleSerializer(serializers.ModelSerializer):
    class Meta:
        model = NouveauModele
        fields = "__all__"
```

### 3. Créer une vue

**Option A - APIView (pour endpoints personnalisés):**
```python
from rest_framework.views import APIView
from rest_framework.response import Response

class NouvelleVue(APIView):
    permission_classes = [IsAuthenticated]  # Optionnel
    
    def get(self, request):
        # Logique GET
        return Response({"data": "resultat"})
    
    def post(self, request):
        # Logique POST
        return Response({"message": "créé"})
```

**Option B - ViewSet (pour CRUD standard):**
```python
from rest_framework import viewsets

class NouveauViewSet(viewsets.ModelViewSet):
    queryset = NouveauModele.objects.all()
    serializer_class = NouveauModeleSerializer
    permission_classes = [IsAuthenticated]
```

### 4. Ajouter l'URL

**Pour APIView:**
```python
from .views import NouvelleVue

urlpatterns = [
    path("nouveau-endpoint/", NouvelleVue.as_view()),
] + router.urls
```

**Pour ViewSet:**
```python
from .views import NouveauViewSet

router.register(
    r"nouveaux",
    NouveauViewSet,
    basename="nouveaux"
)
```

### 5. Créer une permission personnalisée

Dans `permissions.py`:
```python
class IsCustomPermission(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == "role_specifique"
        )
```

Utilisation dans la vue:
```python
from .permissions import IsCustomPermission

class NouvelleVue(APIView):
    permission_classes = [IsCustomPermission]
```

### 6. Personnaliser l'authentification

Dans `authentication.py`, vous pouvez modifier `CustomTokenObtainPairSerializer` pour ajouter des validations supplémentaires:
```python
class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        data = super().validate(attrs)
        # Ajouter vos validations personnalisées ici
        if not self.user.is_active:
            raise serializers.ValidationError("Compte inactif")
        return data
```

## 📝 Workflow de développement

1. **Modifier le modèle** si nécessaire
2. **Créer les migrations**: `python manage.py makemigrations`
3. **Appliquer les migrations**: `python manage.py migrate`
4. **Créer/Modifier le sérialiseur** dans `serializers.py`
5. **Créer/Modifier la vue** dans `views.py`
6. **Ajouter l'URL** dans `urls.py`
7. **Tester** avec Postman ou curl
8. **Mettre à jour la documentation** (ce fichier)

## 🔧 Configuration requise

**Dépendances principales:**
- Django
- Django REST Framework
- djangorestframework-simplejwt

**Settings Django:**
```python
INSTALLED_APPS = [
    ...
    'rest_framework',
    'rest_framework_simplejwt',
    'users',
]

AUTH_USER_MODEL = 'users.CustomUser'
```

## 📚 Notes importantes

- Les comptes magasin et employer doivent être approuvés par un admin ou un magasin (`is_confirmed=True`)
- Seuls les admins peuvent modifier/supprimer des produits
- Les magasins peuvent créer des produits pour leur propre magasin
- Les employés ne peuvent voir que les produits de leur magasin
- L'email sert de username pour la connexion
