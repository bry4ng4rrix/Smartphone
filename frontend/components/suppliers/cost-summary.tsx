'use client';

import { useMemo } from 'react';
import { Cell, Legend, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { Lock, Calculator } from 'lucide-react';
import { fmtAppDateTime } from '@/lib/timezone';
import {
  STATUTS_RECEPTION, TYPES_FRAIS, fmtAr, fmtDevise, fmtNombre, labelOf,
} from '@/components/suppliers/supplier-status';

/** Ré-export (compatibilité) : la source est `supplier-status.ts`. */
export { STATUTS_RECEPTION };

/* -------------------------------------------------------------------------- */
/* Synthèse du coût réel                                                       */
/* -------------------------------------------------------------------------- */

const COULEURS_FRAIS: Record<string, string> = {
  ACHAT: '#2563eb',
  TRANSPORT: '#f59e0b',
  DOUANE: '#ef4444',
  TAXES: '#8b5cf6',
  AUTRES: '#64748b',
};
const PALETTE_FRAIS = ['#06b6d4', '#f97316', '#16a34a', '#a855f7', '#0ea5e9', '#84cc16', '#e11d48', '#78716c'];

const TYPES_PRINCIPAUX = ['TRANSPORT', 'DOUANE', 'TAXES'];

/**
 * Bloc « combien coûte réellement l'importation, et chaque pièce » :
 * achat fournisseur + frais par type = valeur réelle, coût moyen par pièce,
 * répartition (camembert) et coût de revient par variante.
 */
export function CostSummary({ order }: { order: any }) {
  const devise: string = order?.devise || 'MGA';
  const taux = Number(order?.taux_change) || 1;
  const enReception = (STATUTS_RECEPTION as string[]).includes(order?.statut);
  const finalise = order?.statut === 'COUT_FINALISE';
  const lines: any[] = order?.lines || [];
  const fraisParType: { type: string; label: string; montant_mga: number | string }[] = order?.frais_par_type || [];

  const valeurAchat = Number(order?.valeur_achat_mga) || 0;
  const totalFrais = Number(order?.total_frais_mga) || 0;
  const valeurReelle = Number(order?.cout_total) || valeurAchat + totalFrais;
  const quantite = Number(order?.total_qty) || 0;
  const coutMoyen = Number(order?.cout_unitaire) || (quantite ? valeurReelle / quantite : 0);
  const achatDevise = devise === 'MGA' ? valeurAchat : valeurAchat / (taux || 1);

  const lignesFrais = useMemo(() => {
    const principaux = TYPES_PRINCIPAUX.map((t) => ({
      type: t,
      label: labelOf(TYPES_FRAIS, t).toUpperCase(),
      montant: fraisParType.filter((f) => f.type === t).reduce((s, f) => s + (Number(f.montant_mga) || 0), 0),
    }));
    const autres = fraisParType
      .filter((f) => !TYPES_PRINCIPAUX.includes(f.type))
      .reduce((s, f) => s + (Number(f.montant_mga) || 0), 0);
    return [...principaux, { type: 'AUTRES', label: 'AUTRES FRAIS', montant: autres }];
  }, [fraisParType]);

  const donneesCamembert = useMemo(() => {
    const items: { name: string; value: number; color: string }[] = [];
    if (valeurAchat > 0) items.push({ name: 'Achat fournisseur', value: valeurAchat, color: COULEURS_FRAIS.ACHAT });
    fraisParType.forEach((f, i) => {
      const v = Number(f.montant_mga) || 0;
      if (v > 0) items.push({ name: f.label, value: v, color: COULEURS_FRAIS[f.type] || PALETTE_FRAIS[i % PALETTE_FRAIS.length] });
    });
    return items;
  }, [valeurAchat, fraisParType]);

  const partFrais = valeurReelle > 0 ? (totalFrais / valeurReelle) * 100 : 0;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Calculator className="h-4 w-4" /> Synthèse du coût réel
        </CardTitle>
        <CardDescription className="text-xs">
          {enReception
            ? 'Calculé sur les quantités réceptionnées.'
            : 'Estimation sur les quantités commandées — recalculée à la réception.'}
          {finalise && order?.finalise_at && (
            <span className="inline-flex items-center gap-1 ml-2 font-medium text-teal-700 dark:text-teal-300">
              <Lock className="h-3 w-3" /> Coût figé le {fmtAppDateTime(order.finalise_at)}
            </span>
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        <div className="grid grid-cols-1 lg:grid-cols-5 gap-4">
          {/* Décomposition */}
          <div className="lg:col-span-3 rounded-lg border bg-muted/30 p-4 font-mono text-sm space-y-1.5">
            <div className="flex items-baseline justify-between gap-3">
              <span className="text-xs sm:text-sm font-semibold tracking-wide">
                ACHAT FOURNISSEUR
                {devise !== 'MGA' && (
                  <span className="text-muted-foreground font-normal ml-2">{fmtDevise(achatDevise, devise)}</span>
                )}
              </span>
              <span className="tabular-nums font-semibold">{devise !== 'MGA' ? '≈ ' : ''}{fmtAr(valeurAchat)}</span>
            </div>
            {lignesFrais.map((f) => (
              <div key={f.type} className={`flex items-baseline justify-between gap-3 ${f.montant ? '' : 'text-muted-foreground'}`}>
                <span className="text-xs sm:text-sm tracking-wide">+ {f.label}</span>
                <span className="tabular-nums">{fmtAr(f.montant)}</span>
              </div>
            ))}
            <div className="border-t-2 border-dashed my-2" />
            <div className="flex items-baseline justify-between gap-3 text-base">
              <span className="font-bold tracking-wide">VALEUR RÉELLE</span>
              <span className="tabular-nums font-bold">{fmtAr(valeurReelle)}</span>
            </div>
            {totalFrais > 0 && (
              <p className="text-[11px] text-muted-foreground font-sans">
                Les frais représentent {partFrais.toFixed(1).replace('.', ',')} % de la valeur réelle.
              </p>
            )}
            <div className="grid grid-cols-2 gap-3 pt-3 mt-1 border-t font-sans">
              <div className="rounded-md bg-background border p-3">
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">
                  {enReception ? 'Quantité reçue' : 'Quantité commandée'}
                </p>
                <p className="text-xl font-bold tabular-nums">{fmtNombre(quantite)} <span className="text-sm font-normal text-muted-foreground">pièces</span></p>
              </div>
              <div className="rounded-md bg-background border p-3">
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Coût moyen</p>
                <p className="text-xl font-bold tabular-nums">{fmtAr(coutMoyen)} <span className="text-sm font-normal text-muted-foreground">/ pièce</span></p>
              </div>
            </div>
          </div>

          {/* Répartition */}
          <div className="lg:col-span-2 rounded-lg border p-3">
            <p className="text-xs font-medium mb-1">Répartition de la valeur réelle</p>
            {donneesCamembert.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-10">Aucun montant saisi.</p>
            ) : (
              <div className="h-56 w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={donneesCamembert}
                      dataKey="value"
                      nameKey="name"
                      innerRadius="45%"
                      outerRadius="75%"
                      paddingAngle={2}
                      isAnimationActive={false}
                    >
                      {donneesCamembert.map((d, i) => <Cell key={i} fill={d.color} />)}
                    </Pie>
                    <Tooltip formatter={(v: number) => fmtAr(v)} contentStyle={{ fontSize: 12 }} />
                    <Legend wrapperStyle={{ fontSize: 11 }} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>
        </div>

        {/* Coût de revient par variante */}
        <div>
          <p className="text-sm font-medium mb-2">Coût de revient par variante</p>
          {lines.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucune ligne.</p>
          ) : (
            <div className="overflow-x-auto rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Produit</TableHead>
                    <TableHead>Variante</TableHead>
                    <TableHead className="text-right">Quantité retenue</TableHead>
                    <TableHead className="text-right">Valeur d'achat / pièce</TableHead>
                    <TableHead className="text-right">Frais / pièce</TableHead>
                    <TableHead className="text-right">Coût de revient / pièce</TableHead>
                    <TableHead className="text-right">Prix de vente</TableHead>
                    <TableHead className="text-right">Marge</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {lines.map((l) => {
                    const q = enReception ? Number(l.quantite_recue) || 0 : Number(l.quantite) || 0;
                    const achatU = q ? (Number(l.valeur_achat_mga) || 0) / q : 0;
                    const fraisU = q ? (Number(l.frais_alloues_mga) || 0) / q : 0;
                    const revient = Number(l.cout_unitaire_calcule) || 0;
                    const prixVente = Number(l.prix_vente) || 0;
                    const marge = l.marge_unitaire !== undefined && l.marge_unitaire !== null
                      ? Number(l.marge_unitaire)
                      : prixVente - revient;
                    const margePct = revient > 0 ? (marge / revient) * 100 : null;
                    return (
                      <TableRow key={l.id}>
                        <TableCell className="font-medium whitespace-nowrap">
                          {l.brand_name ? `${l.brand_name} ` : ''}{l.reference_name}
                        </TableCell>
                        <TableCell>{l.couleur || '—'}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmtNombre(q)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmtAr(achatU)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmtAr(fraisU)}</TableCell>
                        <TableCell className="text-right tabular-nums font-semibold">{fmtAr(revient)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmtAr(prixVente)}</TableCell>
                        <TableCell className={`text-right tabular-nums font-medium ${marge < 0 ? 'text-red-600 dark:text-red-400' : 'text-emerald-700 dark:text-emerald-400'}`}>
                          {fmtAr(marge)}
                          {margePct !== null && (
                            <span className="block text-[11px] font-normal text-muted-foreground">
                              {margePct >= 0 ? '+' : ''}{margePct.toFixed(0)} %
                            </span>
                          )}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
