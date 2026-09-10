import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartcross/core/constants.dart';
import 'package:smartcross/data/repositories/reports_repository.dart';
import 'package:smartcross/features/reports/reports_screen.dart';
import 'package:smartcross/models/user.dart';
import 'package:smartcross/state/auth_provider.dart';
import 'package:smartcross/state/reports_provider.dart';

Map<String, dynamic> _order(int id, String statut, {int qty = 2, double prix = 15000}) => {
      'id': id,
      'statut_courant': statut,
      'client_nom': id.isEven ? 'Rakoto Jean' : '',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'items': [
        {'id': id * 10, 'reference_name': 'Coque silicone', 'couleur': 'Bleu', 'quantite': qty, 'prix_unitaire': prix},
        {'id': id * 10 + 1, 'reference_name': 'Chargeur', 'couleur': 'Standard', 'quantite': 1, 'prix_unitaire': null},
      ],
    };

class _FakeReportsRepo extends ReportsRepository {
  _FakeReportsRepo({this.empty = false});
  final bool empty;

  @override
  Future<ReportsData> fetchAll() async {
    if (empty) {
      return const ReportsData(sales: [], products: [], movements: [], dashboardKpis: {});
    }
    final sales = [
      ...ReportSale.fromOrder(_order(2, 'LIVRE')),
      ...ReportSale.fromOrder(_order(4, 'LIVRE', qty: 7, prix: 3000)),
      ...ReportSale.fromOrder(_order(5, 'NOUVELLE')),
    ];
    return ReportsData(
      sales: sales,
      products: [
        ReportProduct.fromReference({
          'id': 1,
          'reference_name': 'Coque silicone',
          'variants': [
            {'id': 10, 'stock_actuel': 40, 'seuil_alerte': 5},
            {'id': 11, 'stock_actuel': 0, 'seuil_alerte': 2},
          ],
        }),
        ReportProduct.fromReference({
          'id': 2,
          'reference_name': 'Vitre trempée',
          'variants': [
            {'id': 12, 'stock_actuel': 0, 'seuil_alerte': 3},
          ],
        }),
      ],
      movements: [
        ReportMovement.fromJson({
          'id': 1,
          'reference_name': 'Coque silicone',
          'couleur': 'Bleu',
          'type': 'SORTIE',
          'quantite': 3,
          'origine': 'PREPARATION',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        ReportMovement.fromJson({
          'id': 2,
          'reference_name': 'Chargeur',
          'couleur': 'Standard',
          'type': 'ENTREE',
          'quantite': 10,
          'origine': 'FOURNISSEUR',
          'timestamp': DateTime.now().toUtc().subtract(const Duration(days: 3)).toIso8601String(),
        }),
        ReportMovement.fromJson({
          'id': 3,
          'reference_name': 'Vieux stock',
          'couleur': 'Standard',
          'type': 'ENTREE',
          'quantite': 10,
          'origine': 'AJUSTEMENT',
          'timestamp': DateTime.now().toUtc().subtract(const Duration(days: 200)).toIso8601String(),
        }),
      ],
      dashboardKpis: const {'ca': '900000', 'total_profit': 120000, 'total_stock_value': 40000},
    );
  }

  @override
  Future<AiAnalysisResult> analyze(Map<String, dynamic> payload) async =>
      const AiAnalysisResult(analysis: 'Votre CA progresse.\nRéapprovisionnez les vitres.', isError: false);
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

Widget _app(String role, {bool empty = false}) => ProviderScope(
      overrides: [
        reportsRepositoryProvider.overrideWithValue(_FakeReportsRepo(empty: empty)),
        authProvider.overrideWith(() => _FakeAuth(role)),
      ],
      child: const MaterialApp(home: ReportsScreen()),
    );

void main() {
  testWidgets('rend tous les blocs (admin, écran étroit)', (tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app('admin'));
    await tester.pumpAndSettle();

    expect(find.text('Rapports'), findsOneWidget);
    expect(find.text('Analyse des ventes, du stock et des performances'), findsOneWidget);
    expect(find.byTooltip('Actualiser'), findsOneWidget);
    expect(find.text("Chiffre d'affaires"), findsOneWidget);
    expect(find.text('Bénéfice net'), findsOneWidget);
    expect(find.text('Unités vendues'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Produits en stock'), findsOneWidget);
    expect(find.text('Alertes stock'), findsOneWidget);
    expect(find.text("Chiffre d'affaires — 30 derniers jours"), findsOneWidget);
    expect(find.text('7j'), findsOneWidget);
    expect(find.text('30j'), findsOneWidget);
    expect(find.text('90j'), findsOneWidget);

    final scroll = find.byType(Scrollable).first;
    await tester.dragUntilVisible(find.text('Top produits vendus'), scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Classement par quantités vendues'), findsOneWidget);
    expect(find.text('Coque silicone (Bleu)'), findsWidgets);

    await tester.dragUntilVisible(find.text('Ventes à crédit'), scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Paiements en attente ou partiels'), findsOneWidget);
    expect(find.text('Client anonyme'), findsWidgets);
    expect(find.text('En attente'), findsWidgets);

    await tester.dragUntilVisible(find.text('Performance des vendeurs'), scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Non attribué'), findsOneWidget);

    await tester.dragUntilVisible(find.text('Performance par magasin'), scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Magasin inconnu'), findsOneWidget);

    await tester.dragUntilVisible(find.text('Entrées'), scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Mouvements de stock — 30 derniers jours'), findsOneWidget);
    expect(find.text('Sorties'), findsOneWidget);
    expect(find.text('Transferts'), findsOneWidget);

    await tester.dragUntilVisible(find.text('Analyse IA Stratégique'), scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text("Générer l'analyse"), findsOneWidget);
    await tester.tap(find.text("Générer l'analyse"));
    await tester.pumpAndSettle();
    expect(find.textContaining('Votre CA progresse.'), findsOneWidget);
    expect(find.text('Régénérer'), findsOneWidget);
  });

  testWidgets('non-admin : pas de carte magasin ; changement de période', (tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app('magasin'));
    await tester.pumpAndSettle();

    expect(find.text('Performance par magasin'), findsNothing);

    await tester.tap(find.text('90j'));
    await tester.pumpAndSettle();
    expect(find.text("Chiffre d'affaires — 90 derniers jours"), findsOneWidget);

    await tester.tap(find.text('7j'));
    await tester.pumpAndSettle();
    expect(find.text("Chiffre d'affaires — 7 derniers jours"), findsOneWidget);
  });

  testWidgets('états vides', (tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app('admin', empty: true));
    await tester.pumpAndSettle();

    final scroll = find.byType(Scrollable).first;
    await tester.dragUntilVisible(find.text('Aucune vente impayée'), scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Aucune vente enregistrée'), findsWidgets);
    expect(find.text('Aucune vente impayée'), findsOneWidget);
  });
}
