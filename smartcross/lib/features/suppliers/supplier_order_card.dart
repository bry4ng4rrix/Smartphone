import 'package:flutter/material.dart';

import '../../models/supplier.dart';
import 'supplier_status.dart';

/// Fiche d'un approvisionnement (§ 16) — cinq blocs : FOURNISSEUR, PRODUIT,
/// PAIEMENTS, TRANSPORT, COÛT. Miroir de `components/suppliers/cost-summary.tsx`
/// : toutes les valeurs viennent de l'API, rien n'est recalculé ici.
class SupplierOrderCard extends StatelessWidget {
  const SupplierOrderCard({super.key, required this.order, this.compact = false, this.onTap});

  final SupplierOrder order;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final o = order;

    Widget bloc(String titre, IconData icon, List<Widget> children, {bool premier = false}) => Container(
          decoration: premier ? null : BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(titre.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        );

    Widget ligne(String label, String valeur, {bool fort = false, Color? couleur}) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: muted)),
              const SizedBox(width: 12),
              Text(valeur, style: TextStyle(fontSize: 13, fontWeight: fort ? FontWeight.w700 : FontWeight.w500, color: couleur)),
            ],
          ),
        );

    final marge = o.margeUnitaire;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bloc('Fournisseur', Icons.factory_outlined, [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.supplierNom.isEmpty ? 'Sans fournisseur' : '${o.supplierNom}${o.supplierPays.isNotEmpty ? ' · ${o.supplierPays}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SupplierStatusBadge(status: o.statut, small: true),
                ],
              ),
              Text('${o.numero} · ${fmtDateIso(o.date)}${(o.description ?? '').isNotEmpty ? ' · ${o.description}' : ''}', style: muted),
            ], premier: true),
            bloc('Produit', Icons.inventory_2_outlined, [
              Text(o.produit?.libelle ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Quantité : ${o.quantite} pièces${o.quantiteRecue > 0 ? ' · reçues : ${o.quantiteRecue}' : ''}', style: const TextStyle(fontSize: 13)),
            ]),
            bloc('Paiements', Icons.payments_outlined, [
              if (o.payments.isEmpty) Text('Aucun paiement enregistré.', style: muted),
              for (final p in o.payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Text(fmtDateIso(p.date), style: muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${fmtDevise(p.montant, p.devise)}${p.devise != 'MGA' ? ' × ${fmtTaux(p.tauxChange)}' : ''} → ${fmtAr(p.montantMga)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              if (o.devise != 'MGA') ligne('Total payé', fmtDevise(o.totalPayeDevise, o.devise)),
              ligne('Total MGA', fmtAr(o.totalPaiementsMga), fort: true),
              if (o.montantPrevu > 0) ...[
                ligne('Montant total prévu', fmtDevise(o.montantPrevu, o.devise)),
                ligne('Reste à payer', fmtDevise(o.resteAPayerDevise, o.devise),
                    couleur: o.resteAPayerDevise > 0 ? const Color(0xFFD97706) : const Color(0xFF059669)),
                if (!compact)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: (o.pourcentagePaye / 100).clamp(0, 1), minHeight: 5),
                  ),
              ],
            ]),
            bloc('Transport', Icons.local_shipping_outlined, [
              ligne('Départ ${o.lieuDepart.isEmpty ? 'Chine' : o.lieuDepart}', fmtDateIso(o.dateExpedition)),
              ligne('Arrivée ${o.destination.isEmpty ? 'Madagascar' : o.destination}', fmtDateIso(o.dateArrivee)),
              if (!compact && (o.transporteur.isNotEmpty || o.modeTransportLabel.isNotEmpty))
                ligne('Transporteur', [o.transporteur, if (o.modeTransport.isNotEmpty) o.modeTransportLabel].where((s) => s.isNotEmpty).join(' · ')),
              if (!compact && (o.tracking.isNotEmpty || o.numeroColis.isNotEmpty))
                ligne('Suivi', [o.tracking, o.numeroColis].where((s) => s.isNotEmpty).join(' · ')),
              ligne('Statut', o.statut.label),
            ]),
            bloc('Coût', Icons.calculate_outlined, [
              ligne('Frais + Douane', fmtAr(o.fraisDouaneMga)),
              ligne('Coût total rendu Madagascar', fmtAr(o.coutTotalMga), fort: true),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
                child: Row(
                  children: [
                    Expanded(child: Text('Coût par pièce', style: muted)),
                    Text(fmtAr(o.coutUnitaireMga), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (o.prixVenteUnitaire > 0)
                ligne('Marge / pièce (vente ${fmtAr(o.prixVenteUnitaire)})', fmtAr(marge),
                    couleur: marge < 0 ? const Color(0xFFDC2626) : const Color(0xFF059669)),
              if (!o.estFinalise) Text('Coût provisoire — figé à la finalisation.', style: muted.copyWith(fontSize: 11)),
            ]),
          ],
        ),
      ),
    );
  }
}
