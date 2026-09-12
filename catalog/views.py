import io
import json

import openpyxl
from django.db import transaction
from django.http import HttpResponse
from django.utils import timezone
from openpyxl.utils import get_column_letter
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from users.permissions import IsGerantOrReadOnly, get_accessible_magasins, resolve_magasin_for_request

from . import services
from .models import (
    Brand,
    Color,
    ImportBatch,
    ProductCategory,
    ProductNote,
    ProductReference,
    ProductType,
    ProductVariant,
    StockMovement,
)
from .serializers import (
    BrandSerializer,
    BulkPriceUpdateSerializer,
    ColorSerializer,
    ProductCategorySerializer,
    ProductNoteSerializer,
    ProductReferenceAutocompleteSerializer,
    ProductReferenceSerializer,
    ProductTypeSerializer,
    ProductVariantSerializer,
    StockAdjustmentSerializer,
    StockMovementSerializer,
)


class ProductCategoryViewSet(viewsets.ModelViewSet):
    serializer_class = ProductCategorySerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = ProductCategory.objects.filter(magasin__in=get_accessible_magasins(self.request.user))
        magasin_id = self.request.query_params.get("magasin_id")
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def perform_create(self, serializer):
        serializer.save(magasin=resolve_magasin_for_request(self.request))

    def destroy(self, request, *args, **kwargs):
        category = self.get_object()
        if category.types.exists():
            raise ValidationError(
                "Impossible de supprimer une catégorie qui a des sous-types — "
                "supprimez ou déplacez d'abord ses sous-types."
            )
        return super().destroy(request, *args, **kwargs)


class ProductTypeViewSet(viewsets.ModelViewSet):
    serializer_class = ProductTypeSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = ProductType.objects.select_related("category").filter(
            category__magasin__in=get_accessible_magasins(self.request.user)
        )
        category_id = self.request.query_params.get("category")
        if category_id:
            qs = qs.filter(category_id=category_id)
        return qs

    def destroy(self, request, *args, **kwargs):
        type_obj = self.get_object()
        if type_obj.references.exists():
            raise ValidationError(
                "Impossible de supprimer un sous-type qui a des références produit — "
                "supprimez ou déplacez d'abord ses références."
            )
        return super().destroy(request, *args, **kwargs)


class BrandViewSet(viewsets.ModelViewSet):
    serializer_class = BrandSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = Brand.objects.filter(magasin__in=get_accessible_magasins(self.request.user))
        magasin_id = self.request.query_params.get("magasin_id")
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def perform_create(self, serializer):
        serializer.save(magasin=resolve_magasin_for_request(self.request))

    def destroy(self, request, *args, **kwargs):
        brand = self.get_object()
        if brand.references.exists():
            raise ValidationError(
                "Impossible de supprimer une marque qui a des références produit — "
                "supprimez ou déplacez d'abord ses références."
            )
        return super().destroy(request, *args, **kwargs)


class ColorViewSet(viewsets.ModelViewSet):
    serializer_class = ColorSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = Color.objects.filter(magasin__in=get_accessible_magasins(self.request.user))
        magasin_id = self.request.query_params.get("magasin_id")
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def perform_create(self, serializer):
        serializer.save(magasin=resolve_magasin_for_request(self.request))


class ProductReferenceViewSet(viewsets.ModelViewSet):
    serializer_class = ProductReferenceSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = ProductReference.objects.select_related("type", "brand", "type__category").prefetch_related(
            "variants"
        ).filter(type__category__magasin__in=get_accessible_magasins(self.request.user))
        type_id = self.request.query_params.get("type")
        brand_id = self.request.query_params.get("brand")
        category_id = self.request.query_params.get("category")
        magasin_id = self.request.query_params.get("magasin_id")
        if type_id:
            qs = qs.filter(type_id=type_id)
        if brand_id:
            qs = qs.filter(brand_id=brand_id)
        if category_id:
            qs = qs.filter(type__category_id=category_id)
        if magasin_id:
            qs = qs.filter(type__category__magasin_id=magasin_id)
        return qs

    @action(detail=False, methods=["get"])
    def autocomplete(self, request):
        """GET /api/catalog/references/autocomplete/?q=...&type=<id>
        Recherche pour le formulaire Nouvelle commande (§6 Smartreadme.md)."""
        qs = self.get_queryset().filter(actif=True)
        q = request.query_params.get("q")
        if q:
            qs = qs.filter(reference_name__icontains=q)
        qs = qs[:20]
        return Response(ProductReferenceAutocompleteSerializer(qs, many=True).data)

    @action(detail=False, methods=["post"], url_path="bulk-update-price")
    def bulk_update_price(self, request):
        """POST /api/catalog/references/bulk-update-price/
        {type_id, prix_achat?, prix_vente?} — modifie prix_achat/prix_vente
        pour TOUTES les références d'un sous-type donné (ex: toutes les
        "Flip cover", quelle que soit la marque), en une seule action."""
        serializer = BulkPriceUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        qs = self.get_queryset().filter(type_id=data["type_id"])
        count = qs.count()
        if count == 0:
            return Response({"error": "Aucune référence pour ce sous-type."}, status=404)

        update_fields = {}
        if "prix_achat" in data:
            update_fields["prix_achat"] = data["prix_achat"]
        if "prix_vente" in data:
            update_fields["prix_vente"] = data["prix_vente"]
        qs.update(**update_fields)

        return Response({"updated": count})

    EXCEL_HEADERS = [
        "Catégorie", "Sous-type", "Marque", "Référence",
        "Couleur", "Prix achat", "Prix vente", "Stock actuel",
        "Seuil alerte", "Actif",
    ]

    @staticmethod
    def _match_ci(qs, **filters):
        """Recherche insensible à la casse (ex: "Noir" / "noir" / " Noir ",
        déjà .strip() en amont) — utilisé par import_excel pour retrouver une
        entrée existante plutôt que d'en créer une en double quand seule la
        casse diffère entre le fichier importé et le catalogue."""
        ci_filters = {f"{k}__iexact": v for k, v in filters.items()}
        return qs.filter(**ci_filters).first()

    @action(detail=False, methods=["get"], url_path="export-excel")
    def export_excel(self, request):
        """GET /api/catalog/references/export-excel/ — une ligne par couleur
        (variante), pour édition hors-ligne puis réimport via import-excel/."""
        refs = self.get_queryset().order_by("type__category__nom", "type__nom", "brand__nom", "reference_name")

        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Catalogue"
        ws.append(self.EXCEL_HEADERS)

        for ref in refs:
            variants = list(ref.variants.all())
            if not variants:
                ws.append([
                    ref.type.category.nom, ref.type.nom, ref.brand.nom, ref.reference_name,
                    "", float(ref.prix_achat or 0), float(ref.prix_vente or 0), "", "",
                    "Oui" if ref.actif else "Non",
                ])
            for v in variants:
                ws.append([
                    ref.type.category.nom, ref.type.nom, ref.brand.nom, ref.reference_name,
                    v.couleur, float(ref.prix_achat or 0), float(ref.prix_vente or 0),
                    v.stock_actuel, v.seuil_alerte, "Oui" if ref.actif else "Non",
                ])

        for i in range(1, len(self.EXCEL_HEADERS) + 1):
            ws.column_dimensions[get_column_letter(i)].width = 18

        buffer = io.BytesIO()
        wb.save(buffer)
        buffer.seek(0)

        response = HttpResponse(
            buffer.getvalue(),
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        response["Content-Disposition"] = 'attachment; filename="catalogue.xlsx"'
        return response

    #: colonnes ajoutées à la suite des 10 colonnes d'export, écrites de
    #: retour dans le fichier renvoyé par import-excel/ — permettent de
    #: reprendre un import interrompu ou étalé sur plusieurs sessions sans
    #: revenir au début du fichier ni retraiter ce qui l'a déjà été (une
    #: ligne dont "Statut" est déjà rempli est sautée telle quelle).
    STATUT_COL = 11
    DATE_COL = 12

    def _import_row(self, *, magasin, values, category_cache, type_cache, brand_cache, user, stats):
        """Traite une ligne de import-excel/ : Catégorie → Sous-type →
        Marque → Référence → Couleur, avec `stats` mis à jour en place.
        Renvoie (statut_texte, erreur_ou_None). Chaque `return` ci-dessous
        sort proprement du `with transaction.atomic()` englobant (commit
        normal, comme un `continue` l'aurait fait dans l'ancienne version en
        boucle plate) — ce qui préserve la Référence déjà créée/mise à jour
        même quand la Couleur de cette ligne est absente ou invalide.
        Lever une exception à l'intérieur, en revanche, annule tout ce que
        cette ligne a fait : c'est le comportement voulu pour une erreur
        réellement inattendue (cf. le bloc except de l'appelant)."""
        (categorie, sous_type, marque, reference_name, couleur,
         prix_achat, prix_vente, stock_actuel, seuil_alerte, actif) = values

        with transaction.atomic():
            cat_key = categorie.lower()
            category = category_cache.get(cat_key)
            if category is None:
                category = self._match_ci(ProductCategory.objects.filter(magasin=magasin), nom=categorie)
                if category is None:
                    category = ProductCategory.objects.create(magasin=magasin, nom=categorie)
                    stats["items"].append({"action": "created_category", "id": category.id, "label": categorie})
                category_cache[cat_key] = category

            type_key = (cat_key, sous_type.lower())
            type_obj = type_cache.get(type_key)
            if type_obj is None:
                type_obj = self._match_ci(ProductType.objects.filter(category=category), nom=sous_type)
                if type_obj is None:
                    type_obj = ProductType.objects.create(category=category, nom=sous_type)
                    stats["items"].append({
                        "action": "created_type", "id": type_obj.id, "label": f"{categorie} / {sous_type}",
                    })
                type_cache[type_key] = type_obj

            brand_key = marque.lower()
            brand = brand_cache.get(brand_key)
            if brand is None:
                brand = self._match_ci(Brand.objects.filter(magasin=magasin), nom=marque)
                if brand is None:
                    brand = Brand.objects.create(magasin=magasin, nom=marque)
                    stats["items"].append({"action": "created_brand", "id": brand.id, "label": marque})
                brand_cache[brand_key] = brand

            try:
                prix_achat_val = float(prix_achat) if prix_achat not in (None, "") else 0
                prix_vente_val = float(prix_vente) if prix_vente not in (None, "") else 0
            except (TypeError, ValueError):
                return None, "Prix achat/vente invalide (nombre attendu)."
            actif_val = str(actif or "").strip().lower() not in ("non", "false", "0")

            ref = self._match_ci(
                ProductReference.objects.filter(type=type_obj, brand=brand),
                reference_name=reference_name,
            )
            ref_created = ref is None
            ref_label = f"{brand.nom} {reference_name}"
            if ref_created:
                ref = ProductReference.objects.create(
                    type=type_obj, brand=brand, reference_name=reference_name,
                    prix_achat=prix_achat_val, prix_vente=prix_vente_val, actif=actif_val,
                )
                stats["created_refs"] += 1
                stats["new_reference_names"].append(ref_label)
                stats["items"].append({"action": "created_reference", "id": ref.id, "label": ref_label})
            else:
                previous_ref = {
                    "prix_achat": float(ref.prix_achat), "prix_vente": float(ref.prix_vente), "actif": ref.actif,
                }
                ref.prix_achat = prix_achat_val
                ref.prix_vente = prix_vente_val
                ref.actif = actif_val
                ref.save(update_fields=["prix_achat", "prix_vente", "actif"])
                stats["updated_refs"] += 1
                stats["updated_reference_names"].append(ref_label)
                stats["items"].append({
                    "action": "updated_reference", "id": ref.id, "label": ref_label, "previous": previous_ref,
                })

            if not couleur:
                return f"Référence {'créée' if ref_created else 'mise à jour'} (sans couleur)", None

            try:
                seuil_val = int(seuil_alerte) if seuil_alerte not in (None, "") else 1
                stock_val = int(stock_actuel) if stock_actuel not in (None, "") else 0
            except (TypeError, ValueError):
                return None, "Stock/Seuil d'alerte invalide (nombre entier attendu)."

            variant = self._match_ci(ProductVariant.objects.filter(product_reference=ref), couleur=couleur)
            variant_created = variant is None
            variant_label = f"{ref_label} — {couleur}"
            if variant_created:
                variant = ProductVariant.objects.create(
                    product_reference=ref, couleur=couleur, seuil_alerte=seuil_val,
                )
                stats["created_variants"] += 1
                movement_id = None
                if stock_val > 0:
                    movement = services.apply_stock_movement(
                        product_variant=variant, movement_type="ENTREE", quantite=stock_val,
                        origine="AJUSTEMENT", user=user, note="Import Excel",
                    )
                    movement_id = movement.id
                stats["items"].append({
                    "action": "created_variant", "id": variant.id, "reference_id": ref.id,
                    "label": variant_label, "movement_id": movement_id,
                })
            else:
                previous_variant = {"seuil_alerte": variant.seuil_alerte, "stock_actuel": variant.stock_actuel}
                if variant.seuil_alerte != seuil_val:
                    variant.seuil_alerte = seuil_val
                    variant.save(update_fields=["seuil_alerte"])
                diff = stock_val - variant.stock_actuel
                movement_id = None
                if diff > 0:
                    movement = services.apply_stock_movement(
                        product_variant=variant, movement_type="ENTREE", quantite=diff,
                        origine="AJUSTEMENT", user=user, note="Import Excel",
                    )
                    movement_id = movement.id
                elif diff < 0:
                    movement = services.apply_stock_movement(
                        product_variant=variant, movement_type="SORTIE", quantite=-diff,
                        origine="AJUSTEMENT", user=user, note="Import Excel",
                    )
                    movement_id = movement.id
                stats["updated_variants"] += 1
                stats["items"].append({
                    "action": "updated_variant", "id": variant.id, "reference_id": ref.id,
                    "label": variant_label, "previous": previous_variant, "movement_id": movement_id,
                })

            return (
                f"Référence {'créée' if ref_created else 'mise à jour'} ; "
                f"couleur {'créée' if variant_created else 'mise à jour'}",
                None,
            )

    @action(detail=False, methods=["post"], url_path="import-excel", parser_classes=[MultiPartParser])
    def import_excel(self, request):
        """POST /api/catalog/references/import-excel/ (multipart, champ
        "file") — crée/actualise Catégorie → Sous-type → Marque → Référence →
        Couleur à partir d'un fichier au format export-excel/. Le stock ne
        change jamais directement (§10 Smartreadme.md) : un écart avec le
        stock actuel déclenche un mouvement ENTREE/SORTIE tracé.

        Renvoie le fichier lui-même (pas du JSON) : chaque ligne traitée
        reçoit une colonne "Statut" + "Date de traitement" (col. 11/12), et
        toute ligne déjà marquée par un import précédent est sautée plutôt
        que retraitée — le fichier reçu en retour peut donc directement être
        réutilisé pour continuer plus tard (ajouter des lignes, corriger les
        erreurs) sans repartir du début. Le résumé chiffré voyage dans des
        en-têtes X-Import-* (voir Stock/settings.py::CORS_EXPOSE_HEADERS)."""
        uploaded = request.FILES.get("file")
        if not uploaded:
            return Response({"error": "Fichier requis (champ 'file')."}, status=400)

        try:
            wb = openpyxl.load_workbook(uploaded, data_only=True)
            ws = wb.active
        except Exception:
            return Response({"error": "Fichier Excel invalide."}, status=400)

        ws.cell(row=1, column=self.STATUT_COL, value="Statut")
        ws.cell(row=1, column=self.DATE_COL, value="Date de traitement")

        magasin = resolve_magasin_for_request(request)
        batch = ImportBatch.objects.create(magasin=magasin, created_by=request.user)
        created_refs = 0
        updated_refs = 0
        created_variants = 0
        updated_variants = 0
        skipped = 0
        errors = []
        new_reference_names = []

        category_cache = {}
        type_cache = {}
        brand_cache = {}

        now_str = timezone.localtime(timezone.now()).strftime("%d/%m/%Y %H:%M")

        stats = {
            "created_refs": 0, "updated_refs": 0,
            "created_variants": 0, "updated_variants": 0,
            "new_reference_names": [], "updated_reference_names": [],
            "items": [],
        }

        for row_index, row in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
            if row is None or all(c in (None, "") for c in row):
                continue

            statut_existant = row[self.STATUT_COL - 1] if len(row) >= self.STATUT_COL else None
            if statut_existant:
                # Déjà traitée lors d'un import précédent de ce même fichier
                # (colonne "Statut" déjà remplie) — on ne la retouche pas.
                skipped += 1
                continue

            (categorie, sous_type, marque, reference_name, couleur,
             prix_achat, prix_vente, stock_actuel, seuil_alerte, actif) = (list(row) + [None] * 10)[:10]

            categorie = str(categorie or "").strip()
            sous_type = str(sous_type or "").strip()
            marque = str(marque or "").strip()
            reference_name = str(reference_name or "").strip()
            couleur = str(couleur or "").strip()

            if not (categorie and sous_type and marque and reference_name):
                msg = "Catégorie/Sous-type/Marque/Référence manquant(e)."
                errors.append(f"Ligne {row_index} : {msg}")
                row_status = f"Erreur : {msg}"
            else:
                try:
                    row_status, err = self._import_row(
                        magasin=magasin,
                        values=(categorie, sous_type, marque, reference_name, couleur,
                                prix_achat, prix_vente, stock_actuel, seuil_alerte, actif),
                        category_cache=category_cache, type_cache=type_cache, brand_cache=brand_cache,
                        user=request.user, stats=stats,
                    )
                except Exception as exc:
                    row_status, err = None, str(exc)
                if err:
                    errors.append(f"Ligne {row_index} : {err}")
                    row_status = f"Erreur : {err}"

            ws.cell(row=row_index, column=self.STATUT_COL, value=row_status)
            ws.cell(row=row_index, column=self.DATE_COL, value=now_str)

        for i in range(1, self.DATE_COL + 1):
            ws.column_dimensions[get_column_letter(i)].width = 18

        buffer = io.BytesIO()
        wb.save(buffer)
        buffer.seek(0)

        response = HttpResponse(
            buffer.getvalue(),
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        batch.items = stats["items"]
        batch.save(update_fields=["items"])

        filename = f"catalogue_import_{timezone.localdate().isoformat()}.xlsx"
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        response["X-Import-Batch-Id"] = str(batch.id)
        response["X-Import-Created-References"] = str(stats["created_refs"])
        response["X-Import-Updated-References"] = str(stats["updated_refs"])
        response["X-Import-Created-Variants"] = str(stats["created_variants"])
        response["X-Import-Updated-Variants"] = str(stats["updated_variants"])
        response["X-Import-Errors-Count"] = str(len(errors))
        response["X-Import-Skipped-Count"] = str(skipped)
        # Bornées : servent à la revue utilisateur post-import (résumé +
        # confirmation d'annulation, voir ImportBatchViewSet.cancel) et à la
        # revue IA optionnelle des doublons probables (handleImportExcel) —
        # pas un journal complet.
        response["X-Import-New-Reference-Names"] = json.dumps(stats["new_reference_names"][:50])
        response["X-Import-Updated-Reference-Names"] = json.dumps(stats["updated_reference_names"][:50])
        return response


class ImportBatchViewSet(viewsets.GenericViewSet):
    """Permet d'annuler un import Excel après coup, une fois le résumé et
    l'analyse IA de doublons présentés à l'utilisateur côté frontend (bouton
    "Annuler" de la boîte de dialogue de revue post-import) — voir
    services.py::revert_import_batch pour le détail de ce qui est défait."""

    queryset = ImportBatch.objects.all()
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        return ImportBatch.objects.filter(magasin__in=get_accessible_magasins(self.request.user))

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        batch = self.get_object()
        if batch.cancelled_at:
            return Response({"error": "Cet import a déjà été annulé."}, status=400)
        services.revert_import_batch(batch)
        batch.cancelled_at = timezone.now()
        batch.save(update_fields=["cancelled_at"])
        return Response({"status": "cancelled"})


class ProductVariantViewSet(viewsets.ModelViewSet):
    serializer_class = ProductVariantSerializer
    permission_classes = [IsGerantOrReadOnly]
    http_method_names = ["get", "post", "delete", "head", "options"]  # stock modifiable via /adjust/, pas ici

    def get_queryset(self):
        qs = ProductVariant.objects.select_related("product_reference", "product_reference__brand").filter(
            product_reference__type__category__magasin__in=get_accessible_magasins(self.request.user)
        )
        reference_id = self.request.query_params.get("reference")
        if reference_id:
            qs = qs.filter(product_reference_id=reference_id)
        return qs

    def perform_create(self, serializer):
        # `stock_actuel` est en lecture seule sur le serializer (le stock ne
        # se modifie jamais hors mouvement tracé, §10 Smartreadme.md) — une
        # nouvelle couleur est donc créée à 0, puis un mouvement d'entrée est
        # appliqué si un stock initial a été demandé, pour garder la trace.
        variant = serializer.save()
        try:
            initial_stock = int(self.request.data.get("stock_actuel") or 0)
        except (TypeError, ValueError):
            initial_stock = 0
        if initial_stock > 0:
            services.apply_stock_movement(
                product_variant=variant,
                movement_type="ENTREE",
                quantite=initial_stock,
                origine="AJUSTEMENT",
                user=self.request.user,
                note="Stock initial à la création de la couleur",
            )
            variant.refresh_from_db()

    @action(detail=True, methods=["post"])
    def adjust(self, request, pk=None):
        """Ajustement manuel du stock — réservé au Gérant (§7.4 Smartreadme.md :
        'Modification manuelle du stock possible par le gérant uniquement')."""
        variant = self.get_object()
        serializer = StockAdjustmentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.apply_stock_movement(
            product_variant=variant,
            movement_type=data["type"],
            quantite=data["quantite"],
            origine="AJUSTEMENT",
            user=request.user,
            note=data.get("note") or None,
        )
        variant.refresh_from_db()
        return Response(self.get_serializer(variant).data)


class StockMovementViewSet(viewsets.ReadOnlyModelViewSet):
    """Historique des mouvements de stock (§7.4/§10 Smartreadme.md) — lecture
    seule, toute écriture passe par catalog.services.apply_stock_movement."""

    serializer_class = StockMovementSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = StockMovement.objects.select_related(
            "product_variant", "product_variant__product_reference", "user"
        ).filter(
            product_variant__product_reference__type__category__magasin__in=get_accessible_magasins(
                self.request.user
            )
        )
        variant_id = self.request.query_params.get("variant")
        if variant_id:
            qs = qs.filter(product_variant_id=variant_id)
        return qs


class ProductNoteViewSet(viewsets.ModelViewSet):
    """Notes produit (produits à commander, pas encore au catalogue) —
    lecture pour tout utilisateur du magasin, écriture réservée au gérant."""

    serializer_class = ProductNoteSerializer
    permission_classes = [IsGerantOrReadOnly]
    http_method_names = ["get", "post", "put", "patch", "delete", "head", "options"]

    def get_queryset(self):
        return (
            ProductNote.objects.select_related("category", "type", "brand", "created_by")
            .filter(magasin__in=get_accessible_magasins(self.request.user))
        )

    def _check_category(self, category):
        if not get_accessible_magasins(self.request.user).filter(id=category.magasin_id).exists():
            raise ValidationError({"category": "Catégorie non autorisée."})

    def perform_create(self, serializer):
        category = serializer.validated_data["category"]
        self._check_category(category)
        serializer.save(magasin=category.magasin, created_by=self.request.user)

    def perform_update(self, serializer):
        category = serializer.validated_data.get("category", serializer.instance.category)
        self._check_category(category)
        serializer.save(magasin=category.magasin)
