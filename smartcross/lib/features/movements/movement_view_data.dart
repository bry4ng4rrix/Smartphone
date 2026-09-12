/// Dérivations de l'écran « Mouvements de stock » — équivalent Dart du
/// remapping fait côté web par `djangoClient.movements.list()`
/// (frontend/lib/django-client.ts l.803-828).
///
/// Le modèle [StockMovement] (lib/models/stock.dart) colle au JSON du
/// serveur (`reference_name`, `couleur`, `type`, `quantite`, `origine`…)
/// alors que la page Next.js consomme un objet remappé
/// (`product_name`, `product_reference`, `variant_label`, `change`,
/// `movement_type`…). Tout le remapping vit ici pour ne pas toucher au
/// modèle partagé.
///
/// Champs que le web affiche mais que l'API n'expose PAS (le remapping web
/// ne les renseigne pas non plus, ils y valent `undefined`) :
/// `changed_by_username`, `magasin_name`, `previous_quantity`,
/// `new_quantity`. Ils restent donc vides ici aussi — parité exacte.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../models/stock.dart';


final NumberFormat _decimal = NumberFormat.decimalPattern('fr_FR');

/// Séparateur de milliers à la française, comme `fmt()` de la page web
/// (`Intl.NumberFormat('fr-MG')` + `Math.round`).
String fmtQty(num value) => _decimal.format(value.round());

final DateFormat movementDateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
final DateFormat movementTimeFmt = DateFormat('HH:mm');
final DateFormat movementDayFmt = DateFormat('dd/MM/yyyy');
/// `AAAA-MM-JJ` — valeur brute des `<input type="date">` du web, reprise
/// telle quelle dans le libellé « Période analysée » et le nom du fichier
/// exporté.
final DateFormat movementIsoDayFmt = DateFormat('yyyy-MM-dd');

const List<String> _frWeekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> _frMonths = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

/// `3 février 2026` — libellé du bouton « Filtrer par jour » quand un jour
/// est sélectionné (web : `toLocaleDateString('fr-FR', {day:'numeric',
/// month:'long', year:'numeric'})`).
String frLongDate(DateTime day) => '${day.day} ${_frMonths[day.month - 1]} ${day.year}';

/// Titre d'une carte-jour : « Hier », sinon « Lundi 3 février » (web :
/// `{weekday:'long', day:'numeric', month:'long'}` + classe `capitalize`).
String frDayHeading(DateTime day, DateTime today) {
  final yesterday = today.subtract(const Duration(days: 1));
  if (day.year == yesterday.year && day.month == yesterday.month && day.day == yesterday.day) {
    return 'Hier';
  }
  return _capitalize('${_frWeekdays[day.weekday - 1]} ${day.day} ${_frMonths[day.month - 1]}');
}

/// `origine` → libellé affiché, table `originLabel` du client web.
/// `LIVRE` n'existe pas dans `StockMovement.ORIGINE_CHOICES` côté serveur
/// mais le web le traduit : on le garde pour rester aligné.
String movementTypeLabel(String origine) {
  switch (origine) {
    case 'PREPARATION':
      return 'Préparation de commande';
    case 'RETOUR':
      return 'Retour de commande';
    case 'ANNULATION':
      return 'Annulation de commande';
    case 'LIVRE':
      return 'Commande livrée';
    case 'FOURNISSEUR':
      return 'Réception fournisseur';
    case 'AJUSTEMENT':
      return 'Ajustement manuel';
    default:
      return origine.isEmpty ? 'Mise à jour' : origine;
  }
}

/// Couleur du badge « Type » — `getMovementTypeBadgeClass` du web, converti
/// des classes Tailwind (green/cyan/red/amber/indigo/slate/orange) en
/// couleurs Material (mêmes teintes 600/700).
Color movementTypeColor(String label) {
  switch (label) {
    case 'Réception fournisseur':
      return const Color(0xFF15803D);
    case 'Retour de commande':
      return const Color(0xFF0E7490);
    case 'Annulation de commande':
      return const Color(0xFFB91C1C);
    case 'Préparation de commande':
      return const Color(0xFFB45309);
    case 'Commande livrée':
      return const Color(0xFF4338CA);
    case 'Ajustement manuel':
      return const Color(0xFF475569);
    default:
      return const Color(0xFFC2410C);
  }
}

/// `getChangeBadgeClass` du web : bleu pour un transfert, vert en entrée,
/// rouge en sortie, orange quand la variation est nulle.
Color movementChangeColor(int change, String movementType) {
  if (movementType == 'Transfert') return const Color(0xFF1D4ED8);
  if (change > 0) return const Color(0xFF15803D);
  if (change < 0) return const Color(0xFFB91C1C);
  return const Color(0xFFC2410C);
}

/// Couleur des badges « Variante(s) ».
const Color kVariantBadgeColor = Color(0xFF7C3AED);

/// Couleur du badge « Magasin » (colonne réservée au gérant).
const Color kMagasinBadgeColor = Color(0xFF1D4ED8);

/// Une entrée de la colonne « Variante(s) » — `parseVariantEntries` du web.
class VariantEntry {
  const VariantEntry({required this.name, required this.qty});

  final String name;
  final int qty;

  String get label => '$name ${qty > 0 ? '+' : ''}$qty';
}

final RegExp _variantQtyPattern = RegExp(r'^(.*)\s+x(\d+)$', caseSensitive: false);

/// Réplique exacte de `parseVariantEntries(label, fallbackChange)` :
/// découpe sur `,`, reconnaît le suffixe `xN` (signé par le sens du
/// mouvement), retombe sur la variation globale sinon.
List<VariantEntry> parseVariantEntries(String? label, int fallbackChange) {
  return (label ?? '')
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .map((part) {
        final match = _variantQtyPattern.firstMatch(part);
        if (match != null) {
          final qty = int.tryParse(match.group(2)!) ?? 0;
          return VariantEntry(name: match.group(1)!.trim(), qty: fallbackChange < 0 ? -qty : qty);
        }
        return VariantEntry(name: part, qty: fallbackChange);
      })
      .toList();
}

/// Ligne de mouvement telle que la consomme la page web, dérivée du modèle
/// partagé sans le modifier.
class MovementView {
  const MovementView({
    required this.id,
    required this.productVariantId,
    required this.productName,
    required this.productReference,
    required this.variantLabel,
    required this.change,
    required this.movementType,
    required this.note,
    required this.changedByName,
    required this.changedByUsername,
    required this.magasinName,
    required this.createdAt,
    required this.sourceReference,
  });

  /// `id`
  final int id;

  /// `product` côté web — c'est bien l'ID de VARIANTE, pas de référence.
  final int productVariantId;

  /// `product_name` = `reference_name` + ` (couleur)` si la couleur existe
  /// et n'est pas `Standard`.
  final String productName;

  /// `product_reference` = `reference_name`.
  final String productReference;

  /// `variant_label` = `couleur`.
  final String variantLabel;

  /// `change` = `type === 'SORTIE' ? -quantite : quantite`.
  final int change;

  /// `movement_type` = libellé de `origine`.
  final String movementType;

  /// `note`
  final String note;

  /// `changed_by_name` = `user_name` (vide ⇒ « Système »).
  final String changedByName;

  /// `changed_by_username` — jamais renseigné par l'API (ni par le web).
  final String changedByUsername;

  /// `magasin_name` — jamais renseigné par l'API (ni par le web).
  final String magasinName;

  /// `created_at` = `timestamp` (instant UTC renvoyé par le serveur).
  final DateTime? createdAt;

  /// `reference` du modèle serveur (n° de commande/commande fournisseur à
  /// l'origine du mouvement). Absent du remapping web, affiché ici dans la
  /// feuille de détail — information en plus, jamais en moins.
  final String sourceReference;

  /// Jour calendaire du mouvement, à Antananarivo (fuseau métier). Le web
  /// groupe/filtre sur le jour UTC tout en affichant l'heure locale : ici
  /// tout est cohérent sur le fuseau du magasin (voir core/app_time.dart).
  DateTime? get day => createdAt == null ? null : appDay(createdAt!);

  /// Heure d'affichage, à Antananarivo.
  DateTime? get localAt => createdAt == null ? null : appLocal(createdAt!);

  String get changedByLabel => changedByName.isEmpty ? 'Système' : changedByName;

  String get formattedDate => localAt == null ? '-' : movementDateTimeFmt.format(localAt!);

  String get formattedTime => localAt == null ? '-' : movementTimeFmt.format(localAt!);

  String get signedChange => '${change > 0 ? '+' : ''}$change';

  List<VariantEntry> get variantEntries => parseVariantEntries(variantLabel, change);

  /// Champs balayés par la recherche plein texte du web : product_name,
  /// product_reference, changed_by_name, changed_by_username, magasin_name,
  /// note.
  String get searchHaystack => [
        productName,
        productReference,
        changedByName,
        changedByUsername,
        magasinName,
        note,
      ].join(' ').toLowerCase();

  factory MovementView.fromModel(StockMovement m) {
    final parts = _splitVariantLabel(m.variantLabel);
    final referenceName = parts.$1;
    final couleur = parts.$2;
    return MovementView(
      id: m.id,
      productVariantId: m.productVariantId,
      productName: couleur.isNotEmpty && couleur != 'Standard' ? '$referenceName ($couleur)' : referenceName,
      productReference: referenceName,
      variantLabel: couleur,
      change: m.type == StockMovementType.sortie ? -m.quantite : m.quantite,
      movementType: movementTypeLabel(m.origine),
      note: m.note ?? '',
      changedByName: m.userName ?? '',
      // L'API ne renvoie ni l'email de l'auteur ni le magasin du mouvement :
      // le web les laisse `undefined`, on reste identique.
      changedByUsername: '',
      magasinName: '',
      createdAt: m.timestamp,
      sourceReference: m.reference ?? '',
    );
  }
}

/// [StockMovement.variantLabel] fusionne `reference_name` et `couleur` sous
/// la forme `Référence — Couleur`. On les resépare pour retrouver les trois
/// champs distincts du web (`product_name`, `product_reference`,
/// `variant_label`).
(String, String) _splitVariantLabel(String label) {
  const separator = ' — ';
  final index = label.lastIndexOf(separator);
  if (index <= 0) return (label, '');
  return (label.substring(0, index), label.substring(index + separator.length));
}

// ---------------------------------------------------------------------------
// Export tableur
// ---------------------------------------------------------------------------

/// En-têtes du fichier exporté, dans l'ordre exact de `handleExportExcel`.
const List<String> kMovementsExportHeaders = [
  'Date',
  'Produit',
  'Référence',
  'Type',
  'Quantité',
  'Stock avant',
  'Stock après',
  'Note',
  'Utilisateur',
  'Email',
  'Magasin',
];

/// Une ligne du fichier exporté (mêmes colonnes, mêmes valeurs que le web —
/// « Stock avant »/« Stock après »/« Email »/« Magasin » restent vides,
/// l'API ne les fournit pas).
List<Object?> movementExportRow(MovementView m) => [
      m.formattedDate,
      m.productName,
      m.productReference,
      m.movementType,
      m.change,
      null,
      null,
      m.note,
      m.changedByLabel,
      m.changedByUsername,
      m.magasinName,
    ];

/// Nom du fichier exporté : `mouvements_AAAA-MM-JJ.xlsx` (jour métier).
String movementsExportFileName() => 'mouvements_${movementIsoDayFmt.format(appToday())}.xlsx';

const String kXlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Construit un vrai classeur `.xlsx` (OOXML) à partir des lignes fournies.
///
/// La page web utilise la lib JS `xlsx`; côté Flutter aucun paquet tableur
/// n'est déclaré dans `pubspec.yaml` (et le portage ne doit pas y toucher),
/// on écrit donc directement le format : un `.xlsx` n'est qu'une archive ZIP
/// de quelques fichiers XML. Les entrées sont stockées sans compression
/// (méthode 0), ce qu'Excel et LibreOffice acceptent.
Uint8List buildMovementsXlsx({
  required List<String> headers,
  required List<List<Object?>> rows,
  String sheetName = 'Mouvements',
}) {
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetData>');

  var rowIndex = 1;
  void writeRow(List<Object?> cells) {
    sheet.write('<row r="$rowIndex">');
    for (var c = 0; c < cells.length; c++) {
      final value = cells[c];
      if (value == null) continue;
      final cellRef = '${_columnName(c)}$rowIndex';
      if (value is num) {
        sheet.write('<c r="$cellRef"><v>$value</v></c>');
      } else {
        final text = value.toString();
        if (text.isEmpty) continue;
        sheet.write('<c r="$cellRef" t="inlineStr"><is><t xml:space="preserve">${_escapeXml(text)}</t></is></c>');
      }
    }
    sheet.write('</row>');
    rowIndex++;
  }

  writeRow(headers);
  for (final row in rows) {
    writeRow(row);
  }
  sheet
    ..write('</sheetData>')
    ..write('</worksheet>');

  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>';

  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="${_escapeXml(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';

  const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>';

  return _buildZip({
    '[Content_Types].xml': utf8.encode(contentTypes),
    '_rels/.rels': utf8.encode(rootRels),
    'xl/workbook.xml': utf8.encode(workbook),
    'xl/_rels/workbook.xml.rels': utf8.encode(workbookRels),
    'xl/worksheets/sheet1.xml': utf8.encode(sheet.toString()),
  });
}

String _columnName(int index) {
  var i = index;
  final buffer = StringBuffer();
  do {
    buffer.write(String.fromCharCode(65 + (i % 26)));
    i = (i ~/ 26) - 1;
  } while (i >= 0);
  return String.fromCharCodes(buffer.toString().codeUnits.reversed);
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

// --- ZIP (entrées non compressées) -----------------------------------------

List<int>? _crcTable;

List<int> _buildCrcTable() {
  final table = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[i] = c;
  }
  return table;
}

int _crc32(List<int> data) {
  final table = _crcTable ??= _buildCrcTable();
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void _writeUint16(BytesBuilder out, int value) {
  out.addByte(value & 0xFF);
  out.addByte((value >> 8) & 0xFF);
}

void _writeUint32(BytesBuilder out, int value) {
  out.addByte(value & 0xFF);
  out.addByte((value >> 8) & 0xFF);
  out.addByte((value >> 16) & 0xFF);
  out.addByte((value >> 24) & 0xFF);
}

Uint8List _buildZip(Map<String, List<int>> files) {
  final now = appNow();
  final dosTime = (now.hour << 11) | (now.minute << 5) | (now.second ~/ 2);
  final dosDate = ((now.year - 1980) << 9) | (now.month << 5) | now.day;

  final body = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;

  files.forEach((name, data) {
    final nameBytes = utf8.encode(name);
    final crc = _crc32(data);

    _writeUint32(body, 0x04034B50); // signature entête local
    _writeUint16(body, 20); // version nécessaire
    _writeUint16(body, 0x0800); // drapeaux : noms de fichiers en UTF-8
    _writeUint16(body, 0); // méthode 0 = stocké
    _writeUint16(body, dosTime);
    _writeUint16(body, dosDate);
    _writeUint32(body, crc);
    _writeUint32(body, data.length);
    _writeUint32(body, data.length);
    _writeUint16(body, nameBytes.length);
    _writeUint16(body, 0); // pas de champ « extra »
    body.add(nameBytes);
    body.add(data);

    _writeUint32(central, 0x02014B50); // signature entête central
    _writeUint16(central, 20); // version d'écriture
    _writeUint16(central, 20); // version nécessaire
    _writeUint16(central, 0x0800);
    _writeUint16(central, 0);
    _writeUint16(central, dosTime);
    _writeUint16(central, dosDate);
    _writeUint32(central, crc);
    _writeUint32(central, data.length);
    _writeUint32(central, data.length);
    _writeUint16(central, nameBytes.length);
    _writeUint16(central, 0); // extra
    _writeUint16(central, 0); // commentaire
    _writeUint16(central, 0); // disque
    _writeUint16(central, 0); // attributs internes
    _writeUint32(central, 0); // attributs externes
    _writeUint32(central, offset);
    central.add(nameBytes);

    offset += 30 + nameBytes.length + data.length;
  });

  final centralBytes = central.takeBytes();
  final out = BytesBuilder()
    ..add(body.takeBytes())
    ..add(centralBytes);

  _writeUint32(out, 0x06054B50); // fin du répertoire central
  _writeUint16(out, 0);
  _writeUint16(out, 0);
  _writeUint16(out, files.length);
  _writeUint16(out, files.length);
  _writeUint32(out, centralBytes.length);
  _writeUint32(out, offset);
  _writeUint16(out, 0); // commentaire d'archive

  return out.takeBytes();
}
