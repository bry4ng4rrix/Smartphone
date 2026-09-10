import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartcross/core/constants.dart';
import 'package:smartcross/data/repositories/catalog_repository.dart';
import 'package:smartcross/data/repositories/stock_repository.dart';
import 'package:smartcross/features/movements/movements_screen.dart';
import 'package:smartcross/models/catalog.dart';
import 'package:smartcross/models/stock.dart';
import 'package:smartcross/models/user.dart';
import 'package:smartcross/state/auth_provider.dart';
import 'package:smartcross/state/catalog_provider.dart';
import 'package:smartcross/state/stock_provider.dart';

class _FakeStockRepo extends StockRepository {
  @override
  Future<List<StockMovement>> movements({int? variantId}) async => [
        StockMovement.fromJson({
          'id': 1,
          'product_variant': 10,
          'reference_name': 'iPhone 13 Pro Max 256Go',
          'couleur': 'Bleu alpin',
          'type': 'SORTIE',
          'quantite': 3,
          'origine': 'PREPARATION',
          'reference': 'CMD-2026-0001',
          'note': 'Préparation commande client très longue note de test',
          'user_name': 'Rakoto Jean Baptiste',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        StockMovement.fromJson({
          'id': 2,
          'product_variant': 11,
          'reference_name': 'Coque silicone',
          'couleur': 'Standard',
          'type': 'ENTREE',
          'quantite': 12345,
          'origine': 'FOURNISSEUR',
          'note': null,
          'user_name': null,
          'timestamp': DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(),
        }),
        StockMovement.fromJson({
          'id': 3,
          'product_variant': 12,
          'reference_name': 'Chargeur',
          'couleur': 'Noir x2, Blanc x3',
          'type': 'SORTIE',
          'quantite': 5,
          'origine': 'AJUSTEMENT',
          'timestamp': DateTime.now().toUtc().subtract(const Duration(days: 3)).toIso8601String(),
        }),
      ];
}

class _FakeCatalogRepo extends CatalogRepository {
  @override
  Future<List<ProductReference>> references({int? typeId, int? brandId, int? categoryId}) async => [
        ProductReference.fromJson({
          'id': 5,
          'type': 1,
          'type_name': 'Smartphone',
          'category_name': 'Téléphones',
          'brand': 2,
          'brand_name': 'Apple',
          'reference_name': 'iPhone 13 Pro Max 256Go',
          'prix_achat': 1000,
          'prix_vente': 1500,
          'actif': true,
          'variants': [
            {'id': 10, 'couleur': 'Bleu alpin', 'stock_actuel': 4, 'seuil_alerte': 2},
          ],
        }),
        ProductReference.fromJson({
          'id': 6,
          'type': 1,
          'type_name': 'Accessoire',
          'category_name': 'Accessoires',
          'brand': 3,
          'brand_name': 'Generic',
          'reference_name': 'Coque silicone',
          'prix_achat': 1,
          'prix_vente': 3,
          'actif': true,
          'variants': [
            {'id': 11, 'couleur': 'Standard', 'stock_actuel': 40, 'seuil_alerte': 5},
          ],
        }),
      ];
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.role);
  final String role;

  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 1,
          fullName: 'Test',
          email: 't@t.mg',
          role: UserRole.gerant,
          isActive: true,
          rawRole: role,
          isCompanyOwner: true,
        ),
      );
}

Widget _app(String role) => ProviderScope(
      overrides: [
        stockRepositoryProvider.overrideWithValue(_FakeStockRepo()),
        catalogRepositoryProvider.overrideWithValue(_FakeCatalogRepo()),
        authProvider.overrideWith(() => _FakeAuth(role)),
      ],
      child: const MaterialApp(home: MovementsScreen()),
    );

void main() {
  testWidgets('rend sans erreur de layout (admin, écran étroit)', (tester) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app('admin'));
    await tester.pumpAndSettle();

    expect(find.text('Mouvements de stock'), findsOneWidget);
    expect(find.text('Historique des mouvements de stock'), findsOneWidget);
    expect(find.text('3 mouvement(s) affiché(s)'), findsOneWidget);
    expect(find.text('Filtre statistiques produits'), findsOneWidget);
    expect(find.text('Période analysée : toute la période'), findsOneWidget);
    expect(find.byTooltip('Exporter XLSX'), findsOneWidget);
    expect(find.text('iPhone 13 Pro Max 256Go (Bleu alpin)'), findsWidgets);
    // « Coque silicone » : couleur Standard ⇒ pas de suffixe.
    expect(find.text('Coque silicone'), findsWidgets);

    // Faire défiler jusqu'au bloc par jour.
    await tester.dragUntilVisible(
      find.text('Mouvements par jour'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mouvements par jour'), findsOneWidget);
    expect(find.text('Filtrer par jour'), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
  });

  testWidgets('gérant magasin : pas de bouton export', (tester) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app('magasin'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Exporter XLSX'), findsNothing);
    expect(find.byTooltip('Actualiser'), findsOneWidget);
  });

  testWidgets('recherche debouncée filtre la liste', (tester) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app('admin'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'chargeur');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('1 mouvement(s) affiché(s)'), findsOneWidget);
  });

  testWidgets('badge multi-variantes ouvre la feuille', (tester) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app('admin'));
    await tester.pumpAndSettle();

    expect(find.text('2 variantes'), findsWidgets);
    await tester.tap(find.text('2 variantes').first);
    await tester.pumpAndSettle();
    expect(find.text('Variante(s)'), findsWidgets);
    expect(find.text('Noir -2'), findsOneWidget);
    expect(find.text('Blanc -3'), findsOneWidget);
  });
}
