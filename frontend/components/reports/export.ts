import * as XLSX from 'xlsx';

export interface Feuille {
  nom: string;
  lignes: Record<string, unknown>[];
}

/** Export Excel multi-feuilles (même mécanisme que la page Mouvements). */
export function exporterExcel(feuilles: Feuille[], nomFichier: string) {
  const wb = XLSX.utils.book_new();
  const noms = new Set<string>();
  for (const f of feuilles) {
    if (!f.lignes.length) continue;
    let nom = f.nom.replace(/[\\/?*[\]:]/g, ' ').slice(0, 31) || 'Feuille';
    let i = 2;
    while (noms.has(nom)) nom = `${nom.slice(0, 28)} ${i++}`;
    noms.add(nom);
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(f.lignes), nom);
  }
  if (!wb.SheetNames.length) return;
  const date = new Date().toISOString().slice(0, 10);
  XLSX.writeFile(wb, `${nomFichier.replace(/\s+/g, '_')}_${date}.xlsx`);
}

/** Export CSV (UTF-8 avec BOM pour Excel) d'une seule table. */
export function exporterCsv(lignes: Record<string, unknown>[], nomFichier: string) {
  if (!lignes.length) return;
  const ws = XLSX.utils.json_to_sheet(lignes);
  const csv = XLSX.utils.sheet_to_csv(ws, { FS: ';' });
  const blob = new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${nomFichier.replace(/\s+/g, '_')}_${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}
