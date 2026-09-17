'use client';

/**
 * Fiche d'un approvisionnement (§ 16) — cinq blocs : FOURNISSEUR, PRODUIT,
 * PAIEMENTS, TRANSPORT, COÛT. Toutes les valeurs viennent de l'API
 * (suppliers/services.py) : rien n'est recalculé ici.
 */
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Building2, Package, CreditCard, Truck, Calculator } from 'lucide-react';
import {
  DEVISES,
  MODES_TRANSPORT,
  fmtAr,
  fmtDate,
  fmtDevise,
  fmtNombre,
  fmtTaux,
  labelOf,
  statutInfo,
} from './supplier-status';

function Bloc({ titre, icon: Icon, children }: { titre: string; icon: React.ComponentType<{ className?: string }>; children: React.ReactNode }) {
  return (
    <section className="border-t first:border-t-0 px-4 py-3">
      <p className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground mb-1.5">
        <Icon className="h-3.5 w-3.5" aria-hidden /> {titre}
      </p>
      {children}
    </section>
  );
}

function Ligne({ label, valeur, fort }: { label: string; valeur: React.ReactNode; fort?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className={`text-right tabular-nums ${fort ? 'font-semibold' : ''}`}>{valeur}</span>
    </div>
  );
}

export function CostSummary({ order, compact = false }: { order: any; compact?: boolean }) {
  const s = statutInfo(order.statut);
  const symbole = DEVISES.find((d) => d.value === order.devise)?.symbole ?? order.devise;
  const paiements: any[] = order.payments ?? [];
  const prevu = Number(order.montant_prevu || 0);

  return (
    <div className="rounded-lg border bg-card">
      <Bloc titre="Fournisseur" icon={Building2}>
        <div className="flex items-center justify-between gap-2">
          <p className="font-medium">{order.supplier_nom || <span className="text-muted-foreground">Sans fournisseur</span>}{order.supplier_pays ? <span className="text-muted-foreground font-normal"> · {order.supplier_pays}</span> : null}</p>
          <Badge className={`${s.color} border-0 whitespace-nowrap`}>{s.label}</Badge>
        </div>
        <p className="text-xs text-muted-foreground mt-0.5">{order.numero} · {fmtDate(order.date)}{order.description ? ` · ${order.description}` : ''}</p>
      </Bloc>

      <Bloc titre="Produit" icon={Package}>
        <p className="font-medium">{order.produit?.libelle ?? '—'}</p>
        <div className="flex flex-wrap gap-x-4 text-sm">
          <span>Quantité : <strong className="tabular-nums">{fmtNombre(order.quantite)} pièces</strong></span>
          {order.quantite_recue > 0 && <span className="text-muted-foreground">reçues : {fmtNombre(order.quantite_recue)}</span>}
          {order.produit?.type_name && <span className="text-muted-foreground">{order.produit.type_name}</span>}
        </div>
      </Bloc>

      <Bloc titre="Paiements" icon={CreditCard}>
        {paiements.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucun paiement enregistré.</p>
        ) : (
          <ul className="space-y-0.5 text-sm">
            {paiements.map((p) => (
              <li key={p.id} className="flex items-baseline justify-between gap-3">
                <span className="text-muted-foreground whitespace-nowrap">{fmtDate(p.date)}</span>
                <span className="tabular-nums">
                  {fmtDevise(p.montant, p.devise)}
                  {p.devise !== 'MGA' && <span className="text-muted-foreground"> × {fmtTaux(p.taux_change)}</span>}
                  {' → '}
                  <strong>{fmtAr(p.montant_mga)}</strong>
                </span>
              </li>
            ))}
          </ul>
        )}
        <div className="mt-2 space-y-0.5">
          {order.devise !== 'MGA' && <Ligne label={`Total payé (${symbole})`} valeur={fmtDevise(order.total_paye_devise, order.devise)} />}
          <Ligne label="Total MGA" valeur={fmtAr(order.total_paiements_mga)} fort />
          {prevu > 0 && (
            <>
              <Ligne label="Montant total prévu" valeur={fmtDevise(order.montant_prevu, order.devise)} />
              <Ligne label="Reste à payer" valeur={<span className={Number(order.reste_a_payer_devise) > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-emerald-600 dark:text-emerald-400'}>{fmtDevise(order.reste_a_payer_devise, order.devise)}</span>} />
              {!compact && <Progress value={Number(order.pourcentage_paye || 0)} className="h-1.5 mt-1" />}
            </>
          )}
        </div>
      </Bloc>

      <Bloc titre="Transport" icon={Truck}>
        <div className="space-y-0.5">
          <Ligne label={`Départ ${order.lieu_depart || 'Chine'}`} valeur={fmtDate(order.date_expedition)} />
          <Ligne label={`Arrivée ${order.destination || 'Madagascar'}`} valeur={fmtDate(order.date_arrivee)} />
          {!compact && (order.transporteur || order.mode_transport) && (
            <Ligne label="Transporteur" valeur={[order.transporteur, labelOf(MODES_TRANSPORT, order.mode_transport) !== '—' ? labelOf(MODES_TRANSPORT, order.mode_transport) : ''].filter(Boolean).join(' · ')} />
          )}
          {!compact && (order.tracking || order.numero_colis) && (
            <Ligne label="Suivi" valeur={[order.tracking, order.numero_colis].filter(Boolean).join(' · ')} />
          )}
          <Ligne label="Statut" valeur={s.label} />
        </div>
      </Bloc>

      <Bloc titre="Coût" icon={Calculator}>
        <div className="space-y-0.5">
          <Ligne label="Frais + Douane" valeur={fmtAr(order.frais_douane_mga)} />
          <Ligne label="Coût total rendu Madagascar" valeur={fmtAr(order.cout_total_mga)} fort />
          <div className="flex items-baseline justify-between gap-3 pt-1 mt-1 border-t">
            <span className="text-sm text-muted-foreground">Coût par pièce</span>
            <span className="text-lg font-bold tabular-nums">{fmtAr(order.cout_unitaire_mga)}</span>
          </div>
          {Number(order.prix_vente_unitaire) > 0 && (
            <Ligne
              label={`Marge / pièce (vente ${fmtAr(order.prix_vente_unitaire)})`}
              valeur={<span className={Number(order.marge_unitaire) < 0 ? 'text-red-600 dark:text-red-400' : 'text-emerald-600 dark:text-emerald-400'}>{fmtAr(order.marge_unitaire)}</span>}
            />
          )}
          {order.statut !== 'COUT_FINALISE' && <p className="text-[11px] text-muted-foreground mt-1">Coût provisoire — figé à la finalisation.</p>}
        </div>
      </Bloc>
    </div>
  );
}
