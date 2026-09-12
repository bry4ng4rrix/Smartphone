import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/app_time.dart';
import '../core/constants.dart';
import '../models/delivery_zone.dart';
import '../models/order.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String arFmt(num v) => '${_moneyFmt.format(v.round())} Ar';

/// Le préparateur/livreur voit toutes ses commandes à venir (planning) mais
/// ne peut agir dessus qu'à partir de son OUVERTURE : 19h00 la veille pour le
/// préparateur, minuit le jour J pour le livreur (§ demande).
///
/// Le calcul vit dans core/app_time.dart et reprend exactement celui du
/// serveur (orders/services.py::ouverture_actions), qui reste seul juge.
bool isJourJ(DateTime? dateCommande, UserRole role) => actionOuverte(dateCommande, role);

final _dueDateFmt = DateFormat("dd/MM/yyyy 'à' HH'h'mm");

/// Libellé du moment où l'action se débloquera — pas la date de livraison :
/// c'est ce que le bouton doit annoncer (`fmtOuverture` du web).
String dueDateLabel(DateTime dateCommande, UserRole role) =>
    _dueDateFmt.format(appLocal(ouvertureActions(dateCommande, role)));

/// Mot à retaper avant de confirmer une transition (§ demande) — miroir de
/// `MOTS_CONFIRMATION` de page.tsx.
///
/// Réservé à « Retour » déclaré directement : la commande se ferme sans rien
/// livrer, et le bouton se touche vite par accident sur un téléphone en
/// tournée. Sans accent, pour rester tapable au pavé tactile.
///
/// « Livré » n'en fait PAS partie : le pointage des articles y tient lieu de
/// confirmation délibérée — oui/non pour un article unique, cases à cocher
/// au-delà (voir [OrderConfirmForm]).
const Map<OrderStatus, String> kMotsConfirmation = {OrderStatus.retour: 'RETOUR'};

/// Mot à retaper avant d'annuler une commande (gérant) — irréversible.
const String kMotConfirmationAnnulation = 'ANNULER';

/// Le mot saisi débloque-t-il la confirmation ? Comparaison tolérante : casse
/// et espaces autour ne doivent pas bloquer (même règle que le web).
bool motConfirmationValide(String? attendu, String saisie) =>
    attendu == null || saisie.trim().toLowerCase() == attendu.trim().toLowerCase();

/// La photo ne sert de preuve qu'au passage « Prête » (préparateur/gérant).
bool photoPourStatut(OrderStatus target) => target == OrderStatus.prete;

/// Pointage des articles au moment de livrer : proposé à tout passage
/// « Livré », retrait sur place compris (`items` de NoteForm côté web).
bool pointagePourStatut(OrderStatus target) => target == OrderStatus.livre;

/// Résultat de [showOrderConfirmDialog] / [OrderConfirmForm] : la note saisie
/// (chaîne vide possible), le chemin local de la photo choisie si elle a été
/// proposée (preuve de préparation — § demande) et, si le pointage des
/// articles a été proposé, les identifiants des articles RÉELLEMENT remis.
class OrderConfirmResult {
  const OrderConfirmResult({required this.note, this.photoPath, this.itemsLivres});
  final String note;
  final String? photoPath;

  /// `null` = pas de pointage (tout est remis). Liste vide = rien n'a été
  /// remis : le serveur enregistre la commande comme un Retour.
  final List<int>? itemsLivres;

  /// Vrai si le pointage a conclu qu'aucun article n'a été remis.
  bool get rienRemis => itemsLivres != null && itemsLivres!.isEmpty;
}

/// Confirmation avant toute action de statut (préparateur/livreur/gérant) —
/// résumé de la commande (client, téléphone, articles, prix) puis le
/// formulaire [OrderConfirmForm] (note, photo, pointage, mot à retaper).
///
/// [target] dérive automatiquement les règles du web pour la transition :
/// photo au passage « Prête », pointage des articles au passage « Livré »,
/// mot à retaper pour « Retour ». [showPhoto], [confirmWord] et
/// [pointageArticles] permettent de forcer chacun de ces choix.
/// [hideAmounts] masque tous les montants (commande déjà réglée d'avance :
/// le livreur n'a rien à encaisser — § demande). Retourne `null` si annulé.
Future<OrderConfirmResult?> showOrderConfirmDialog(
  BuildContext context, {
  required String title,
  required Order order,
  OrderStatus? target,
  bool? showPhoto,
  bool hideAmounts = false,
  String? confirmWord,
  bool? pointageArticles,
}) {
  return showDialog<OrderConfirmResult>(
    context: context,
    builder: (context) => _OrderConfirmDialog(
      title: title,
      order: order,
      showPhoto: showPhoto ?? (target != null && photoPourStatut(target)),
      hideAmounts: hideAmounts,
      confirmWord: confirmWord ?? (target == null ? null : kMotsConfirmation[target]),
      items: (pointageArticles ?? (target != null && pointagePourStatut(target))) ? order.items : null,
    ),
  );
}

class _OrderConfirmDialog extends StatelessWidget {
  const _OrderConfirmDialog({
    required this.title,
    required this.order,
    required this.showPhoto,
    required this.hideAmounts,
    required this.confirmWord,
    required this.items,
  });
  final String title;
  final Order order;
  final bool showPhoto;
  final bool hideAmounts;
  final String? confirmWord;
  final List<OrderItem>? items;

  @override
  Widget build(BuildContext context) {
    final isRecuperation = order.estRecuperation;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Commande ${order.numero} — vérifiez le résumé avant de confirmer.', style: muted),
              const SizedBox(height: 10),
              row('Client', order.clientNom),
              if (order.telephone != null) row('Téléphone', order.telephone!),
              if (order.telephone2 != null) row('Autre téléphone', order.telephone2!),
              row('Zone', DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
              if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
                row('Adresse', order.adresseLivraison!),
              if (!isRecuperation) row('Paiement', order.modePaiement.label),
              const Divider(height: 20),
              Text('Articles', style: muted),
              for (final item in order.items) row(item.libelle, 'x${item.quantite}'),
              // Commande déjà réglée : le livreur n'a rien à encaisser, on
              // masque tous les montants et on l'annonce clairement (§ demande).
              if (hideAmounts) ...[
                const Divider(height: 20),
                row('À encaisser', 'Rien — déjà payé', bold: true),
              ] else if (order.totalAPayer != null) ...[
                const Divider(height: 20),
                if (!isRecuperation && order.fraisLivraison != null) ...[
                  row('Prix de vente', arFmt(order.totalAPayer! - order.fraisLivraison!)),
                  row('Frais de livraison', arFmt(order.fraisLivraison!)),
                ],
                row('Total', arFmt(order.totalAPayer!), bold: true),
              ],
              const SizedBox(height: 12),
              OrderConfirmForm(
                showPhoto: showPhoto,
                confirmWord: confirmWord,
                items: items,
                onCancel: () => Navigator.of(context).pop(),
                onSubmit: (result) => Navigator.of(context).pop(result),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formulaire de confirmation d'une transition — `NoteForm` du web.
///
/// * note optionnelle ;
/// * si [showPhoto], photo de la préparation : appareil photo OU fichier,
///   aperçu et « Retirer » ;
/// * si [items] est fourni, pointage des articles remis au client
///   (§ demande — livraison partielle) : oui/non pour un article unique,
///   cases à cocher au-delà ; décoché = rapporté en stock et retiré du
///   total ; rien de coché = la commande sera enregistrée comme un Retour ;
/// * si [confirmWord] est fourni, mot à retaper qui débloque « Confirmer »
///   (comparaison tolérante à la casse et aux espaces).
///
/// Affiche ses propres boutons « Annuler » / « Confirmer », pour pouvoir
/// vivre aussi bien dans une boîte de dialogue qu'en ligne dans une fiche.
/// Aucune validation sur la note : elle peut rester vide.
class OrderConfirmForm extends StatefulWidget {
  const OrderConfirmForm({
    super.key,
    required this.onSubmit,
    this.onCancel,
    this.showPhoto = false,
    this.confirmWord,
    this.items,
    this.submitting = false,
    this.confirmLabel = 'Confirmer',
  });

  final ValueChanged<OrderConfirmResult> onSubmit;
  final VoidCallback? onCancel;
  final bool showPhoto;
  final String? confirmWord;
  final List<OrderItem>? items;

  /// Envoi en cours : « Confirmer » est désactivé, la saisie est conservée
  /// (en cas d'échec on reste sur le formulaire, rien n'est perdu).
  final bool submitting;
  final String confirmLabel;

  @override
  State<OrderConfirmForm> createState() => _OrderConfirmFormState();
}

class _OrderConfirmFormState extends State<OrderConfirmForm> {
  final _note = TextEditingController();
  final _saisie = TextEditingController();
  XFile? _photo;
  // Tout est coché au départ : le cas courant reste « tout a été remis ».
  late final Set<int> _livres = {for (final i in widget.items ?? const <OrderItem>[]) i.id};

  bool get _motValide => motConfirmationValide(widget.confirmWord, _saisie.text);

  @override
  void dispose() {
    _note.dispose();
    _saisie.dispose();
    super.dispose();
  }

  /// `capture="environment"` du web ouvre l'appareil photo arrière ; sans
  /// l'attribut, c'est le sélecteur de fichiers — ici la galerie.
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);
      if (file != null && mounted) setState(() => _photo = file);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? "Impossible d'ouvrir l'appareil photo sur cet appareil."
                : "Impossible d'ouvrir le sélecteur de fichiers sur cet appareil.",
          ),
        ),
      );
    }
  }

  void _submit() {
    widget.onSubmit(
      OrderConfirmResult(
        note: _note.text.trim(),
        photoPath: _photo?.path,
        itemsLivres: widget.items == null ? null : _livres.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = widget.items;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Note (optionnel)', hintText: 'ex : client absent'),
          maxLines: 2,
          enabled: !widget.submitting,
        ),
        if (widget.showPhoto) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.camera_alt_outlined, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              const Expanded(child: Text('Photo de la préparation (optionnel)')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.submitting ? null : () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Prendre une photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.submitting ? null : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Choisir un fichier'),
                ),
              ),
            ],
          ),
          if (_photo != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(_photo!.path), width: 80, height: 80, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.submitting ? null : () => setState(() => _photo = null),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Retirer'),
                ),
              ],
            ),
          ],
        ],
        if (items != null && items.length == 1) ...[
          const SizedBox(height: 12),
          _PointageCard(
            children: [
              const Text("L'article a-t-il été remis au client ?", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${items.first.libelle} x${items.first.quantite}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _livres.isNotEmpty
                        ? FilledButton(
                            onPressed: widget.submitting ? null : () => setState(() => _livres.add(items.first.id)),
                            child: const Text('Oui, livré'),
                          )
                        : OutlinedButton(
                            onPressed: widget.submitting ? null : () => setState(() => _livres.add(items.first.id)),
                            child: const Text('Oui, livré'),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _livres.isEmpty
                        ? FilledButton(
                            onPressed: widget.submitting ? null : () => setState(_livres.clear),
                            child: const Text('Non, retour'),
                          )
                        : OutlinedButton(
                            onPressed: widget.submitting ? null : () => setState(_livres.clear),
                            child: const Text('Non, retour'),
                          ),
                  ),
                ],
              ),
              if (_livres.isEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'La commande sera enregistrée comme un Retour.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ],
          ),
        ],
        if (items != null && items.length > 1) ...[
          const SizedBox(height: 12),
          _PointageCard(
            children: [
              const Text('Articles remis au client', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Décochez ce que vous rapportez : ces articles repartent en stock et sortent du total à encaisser.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              for (final it in items)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _livres.contains(it.id),
                  onChanged: widget.submitting
                      ? null
                      : (coche) => setState(() {
                          if (coche == true) {
                            _livres.add(it.id);
                          } else {
                            _livres.remove(it.id);
                          }
                        }),
                  title: Text(
                    '${it.libelle} x${it.quantite}',
                    style: _livres.contains(it.id)
                        ? null
                        : TextStyle(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant),
                  ),
                ),
              if (_livres.isEmpty)
                const Text(
                  'Aucun article remis : la commande sera enregistrée comme un Retour.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
            ],
          ),
        ],
        if (widget.confirmWord != null) ...[
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Pour confirmer, tapez '),
                TextSpan(
                  text: widget.confirmWord,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _saisie,
            decoration: InputDecoration(hintText: widget.confirmWord),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            enabled: !widget.submitting,
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onCancel != null) ...[
              OutlinedButton(onPressed: widget.submitting ? null : widget.onCancel, child: const Text('Annuler')),
              const SizedBox(width: 8),
            ],
            FilledButton(
              onPressed: (!_motValide || widget.submitting) ? null : _submit,
              child: widget.submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.confirmLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// Encadré du pointage des articles (bordure + fond léger, comme le
/// `rounded-md border bg-muted/10` du web).
class _PointageCard extends StatelessWidget {
  const _PointageCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
