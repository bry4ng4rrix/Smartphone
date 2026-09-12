import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../models/catalog.dart';
import '../../models/stock.dart';

/// `/api/catalog/` — historique et ajustements manuels (gérant uniquement,
/// §7.4 Smartreadme.md). Les ruptures/réappro (§7.5) sont dérivées
/// côté client du catalogue (`catalog/references/`), qui porte déjà
/// `is_rupture`/`is_stock_bas` par variante — pas d'endpoint serveur dédié.
class StockRepository {
  Dio get _dio => ApiClient.instance.dio;

  static final DateFormat _pdfStampFmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<List<StockMovement>> movements({int? variantId}) async {
    final response = await _dio.get('catalog/movements/', queryParameters: {
      'variant': ?variantId,
    });
    return (response.data as List).map((e) => StockMovement.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Correction manuelle : entrée après fournisseur, ajustement inventaire…
  /// (§7.4 Smartreadme.md : réservé au gérant).
  Future<ProductVariant> adjust({
    required int productVariantId,
    required String type, // ENTREE | SORTIE
    required int quantite,
    String note = '',
  }) async {
    final response = await _dio.post('catalog/variants/$productVariantId/adjust/', data: {
      'type': type,
      'quantite': quantite,
      if (note.isNotEmpty) 'note': note,
    });
    return ProductVariant.fromJson(response.data as Map<String, dynamic>);
  }

  /// Variantes en rupture ou sous le seuil d'alerte, dérivées de
  /// `GET /catalog/references/` — mêmes prédicats que la page `/alerts` du
  /// web (`initial_quantity === 0` → rupture, `0 < qté <= seuil` → faible),
  /// portés par le serveur via `is_rupture` / `is_stock_bas`.
  Future<List<RuptureItem>> ruptures() async {
    final response = await _dio.get('catalog/references/');
    final references = (response.data as List)
        .map((e) => ProductReference.fromJson(e as Map<String, dynamic>))
        .toList();
    final items = <RuptureItem>[];
    for (final ref in references) {
      for (final v in ref.variants) {
        if (v.isRupture || v.isStockBas) {
          items.add(RuptureItem(
            id: v.id,
            referenceName: ref.referenceName,
            brandName: ref.brandName,
            typeName: ref.typeName,
            categoryName: ref.categoryName,
            couleur: v.couleur,
            stockActuel: v.stockActuel,
            seuilAlerte: v.seuilAlerte,
            statut: v.isRupture ? 'RUPTURE' : 'STOCK_BAS',
          ));
        }
      }
    }
    // Ruptures d'abord, puis stock bas — au sein d'un groupe, ordre alphabétique marque+référence.
    items.sort((a, b) {
      if (a.isRupture != b.isRupture) return a.isRupture ? -1 : 1;
      final byBrand = a.brandName.compareTo(b.brandName);
      return byBrand != 0 ? byBrand : a.referenceName.compareTo(b.referenceName);
    });
    return items;
  }

  /// PDF de réapprovisionnement (§7.5 Smartreadme.md : "format simple lisible
  /// fournisseur") — généré côté client, il n'y a pas d'endpoint serveur dédié.
  ///
  /// [items] : les alertes déjà affichées à l'écran, pour que le document
  /// corresponde exactement à ce que l'utilisateur voit. Sans [items], la
  /// liste est rechargée depuis le serveur.
  Future<Uint8List> ruptureExportPdfBytes({List<RuptureItem>? items}) async {
    final rows = items ?? await ruptures();
    final nbRuptures = rows.where((it) => it.isRupture).length;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Smartphone.Mg — Liste de réapprovisionnement'),
          // Horodatage au fuseau métier (Antananarivo), jamais l'heure brute
          // de l'appareil.
          pw.Text('Généré le ${_pdfStampFmt.format(appNow())}'),
          pw.Text(
            '${rows.length} produit(s) en alerte — $nbRuptures en rupture, '
            '${rows.length - nbRuptures} en stock faible',
          ),
          pw.SizedBox(height: 12),
          if (rows.isEmpty)
            pw.Text('Aucun produit en rupture ou sous le seuil d\'alerte.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Statut', 'Marque', 'Référence', 'Couleur', 'Sous-type', 'Stock', 'Seuil', 'À commander'],
              data: [
                for (final it in rows)
                  [
                    it.isRupture ? 'Rupture' : 'Faible',
                    it.brandName,
                    it.referenceName,
                    it.couleur,
                    it.typeName,
                    it.stockActuel.toString(),
                    it.seuilAlerte.toString(),
                    it.quantiteACommander.toString(),
                  ],
              ],
            ),
        ],
      ),
    );
    return doc.save();
  }
}
