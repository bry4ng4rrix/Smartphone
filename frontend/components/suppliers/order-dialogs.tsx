'use client';

import { useEffect, useMemo, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { appToday } from '@/lib/timezone';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Badge } from '@/components/ui/badge';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { AlertTriangle, Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import {
  DEVISES, METHODES_ALLOCATION, METHODES_PAIEMENT, MODES_TRANSPORT, TYPES_FRAIS, TYPES_PAIEMENT, fmtAr, fmtDevise,
  fmtNombre, messageErreur,
} from '@/components/suppliers/supplier-status';

interface BaseProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  order: any;
  /** Appelé après un enregistrement réussi (rechargement de la fiche). */
  onSaved: () => void;
}

const num = (v: string | number | null | undefined) => {
  const n = Number(String(v ?? '').replace(',', '.'));
  return Number.isFinite(n) ? n : 0;
};

/** Équivalent Ar d'un montant saisi dans une devise + taux. */
const enAr = (montant: string, devise: string, taux: string) =>
  devise === 'MGA' ? num(montant) : num(montant) * num(taux);

/**
 * Montant décimal pour l'API : DRF (DecimalField) attend une chaîne — un
 * nombre flottant (0.1 + 0.2…) peut dépasser le nombre de décimales admis.
 * `decimales` : 2 pour les montants, 4 pour les prix unitaires et les taux.
 */
const dec = (v: string | number, decimales: number) => {
  const n = num(v);
  const f = n.toFixed(decimales);
  // « 12.50 » → « 12.5 », « 12.00 » → « 12 » (lisible dans les erreurs renvoyées).
  return f.includes('.') ? f.replace(/\.?0+$/, '') : f;
};

function DeviseTauxFields({
  devise, setDevise, taux, setTaux, order,
}: {
  devise: string; setDevise: (v: string) => void; taux: string; setTaux: (v: string) => void; order: any;
}) {
  return (
    <div className="grid grid-cols-2 gap-3">
      <div className="space-y-1">
        <Label>Devise</Label>
        <Select
          value={devise}
          onValueChange={(v) => {
            setDevise(v);
            if (v === 'MGA') setTaux('1');
            else if (v === order?.devise && order?.taux_change) setTaux(String(Number(order.taux_change)));
            else setTaux('');
          }}
        >
          <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
          <SelectContent>
            {DEVISES.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label>Taux (Ar pour 1 {devise})</Label>
        <Input
          type="number"
          min={0}
          step="0.0001"
          value={taux}
          disabled={devise === 'MGA'}
          onChange={(e) => setTaux(e.target.value)}
          placeholder={devise === 'MGA' ? '1' : 'Ex : 4500'}
        />
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Paiement fournisseur                                                        */
/* -------------------------------------------------------------------------- */

export function PaymentDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [montant, setMontant] = useState('');
  const [devise, setDevise] = useState('MGA');
  const [taux, setTaux] = useState('1');
  const [date, setDate] = useState(appToday());
  const [type, setType] = useState('ACOMPTE');
  const [methode, setMethode] = useState('VIREMENT');
  const [reference, setReference] = useState('');
  const [commentaire, setCommentaire] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open || !order) return;
    const d = order.devise || 'MGA';
    setDevise(d);
    setTaux(d === 'MGA' ? '1' : String(Number(order.taux_change) || ''));
    const reste = Number(order.reste_a_payer_mga) || 0;
    const resteDevise = d === 'MGA' ? reste : reste / (Number(order.taux_change) || 1);
    setMontant(reste > 0 ? String(Math.round(resteDevise * 100) / 100) : '');
    setDate(appToday());
    setType((order.payments || []).length === 0 ? 'ACOMPTE' : 'SOLDE');
    setMethode('VIREMENT');
    setReference('');
    setCommentaire('');
  }, [open, order]);

  const equivalent = enAr(montant, devise, taux);

  const submit = async () => {
    if (num(montant) <= 0) { toast.error('Le montant doit être supérieur à 0'); return; }
    if (devise !== 'MGA' && num(taux) <= 0) { toast.error('Le taux de change est requis'); return; }
    setSubmitting(true);
    try {
      await djangoClient.suppliers.addPayment(order.id, {
        montant: dec(montant, 2),
        devise,
        taux_change: devise === 'MGA' ? '1' : dec(taux, 4),
        date,
        type_paiement: type,
        methode,
        reference,
        commentaire,
      });
      toast.success('Paiement enregistré');
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toast.error(messageErreur(err, "Impossible d'enregistrer le paiement"));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Ajouter un paiement</DialogTitle>
          <DialogDescription>
            Paiement au fournisseur pour l'approvisionnement {order?.numero}. Reste à payer : {fmtAr(order?.reste_a_payer_mga)}.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1">
            <Label>Montant</Label>
            <Input type="number" min={0} step="0.01" value={montant} onChange={(e) => setMontant(e.target.value)} autoFocus />
          </div>
          <DeviseTauxFields devise={devise} setDevise={setDevise} taux={taux} setTaux={setTaux} order={order} />
          {devise !== 'MGA' && (
            <p className="text-sm rounded-md bg-muted px-3 py-2">
              Équivalent : <span className="font-semibold tabular-nums">≈ {fmtAr(equivalent)}</span>
            </p>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Date</Label>
              <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>Type</Label>
              <Select value={type} onValueChange={setType}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {TYPES_PAIEMENT.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Méthode</Label>
              <Select value={methode} onValueChange={setMethode}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {METHODES_PAIEMENT.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Référence</Label>
              <Input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="N° de virement, reçu…" />
            </div>
          </div>
          <div className="space-y-1">
            <Label>Commentaire</Label>
            <Textarea value={commentaire} onChange={(e) => setCommentaire(e.target.value)} rows={2} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>{submitting ? 'Enregistrement…' : 'Enregistrer le paiement'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Frais d'importation                                                         */
/* -------------------------------------------------------------------------- */

export function FeeDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [type, setType] = useState('TRANSPORT');
  const [montant, setMontant] = useState('');
  const [devise, setDevise] = useState('MGA');
  const [taux, setTaux] = useState('1');
  const [date, setDate] = useState(appToday());
  const [prestataire, setPrestataire] = useState('');
  const [description, setDescription] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open || !order) return;
    // Les frais sont le plus souvent payés localement, en ariary.
    setDevise('MGA');
    setTaux('1');
    setType(order.statut === 'ARRIVE' || order.statut === 'PARTIELLEMENT_RECU' || order.statut === 'RECU' ? 'DOUANE' : 'TRANSPORT');
    setMontant('');
    setDate(appToday());
    setPrestataire('');
    setDescription('');
  }, [open, order]);

  const equivalent = enAr(montant, devise, taux);

  const submit = async () => {
    if (num(montant) <= 0) { toast.error('Le montant doit être supérieur à 0'); return; }
    if (devise !== 'MGA' && num(taux) <= 0) { toast.error('Le taux de change est requis'); return; }
    setSubmitting(true);
    try {
      await djangoClient.suppliers.addFee(order.id, {
        type_frais: type,
        montant: dec(montant, 2),
        devise,
        taux_change: devise === 'MGA' ? '1' : dec(taux, 4),
        date,
        prestataire,
        description,
      });
      toast.success('Frais enregistré — coût de revient recalculé');
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toast.error(messageErreur(err, "Impossible d'enregistrer le frais"));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Ajouter un frais d'importation</DialogTitle>
          <DialogDescription>
            Transport, douane, taxes… Le frais est réparti sur les lignes selon la méthode d'allocation.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Type de frais</Label>
              <Select value={type} onValueChange={setType}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {TYPES_FRAIS.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Montant</Label>
              <Input type="number" min={0} step="0.01" value={montant} onChange={(e) => setMontant(e.target.value)} autoFocus />
            </div>
          </div>
          <DeviseTauxFields devise={devise} setDevise={setDevise} taux={taux} setTaux={setTaux} order={order} />
          {devise !== 'MGA' && (
            <p className="text-sm rounded-md bg-muted px-3 py-2">
              Équivalent : <span className="font-semibold tabular-nums">≈ {fmtAr(equivalent)}</span>
            </p>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Date</Label>
              <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>Prestataire</Label>
              <Input value={prestataire} onChange={(e) => setPrestataire(e.target.value)} placeholder="Transitaire, douane…" />
            </div>
          </div>
          <div className="space-y-1">
            <Label>Description</Label>
            <Textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>{submitting ? 'Enregistrement…' : 'Enregistrer le frais'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Transport (expédition ou modification des informations)                    */
/* -------------------------------------------------------------------------- */

export function TransportDialog({
  open, onOpenChange, order, onSaved, mode,
}: BaseProps & { mode: 'expedier' | 'modifier' }) {
  const [dateExpedition, setDateExpedition] = useState('');
  const [transporteur, setTransporteur] = useState('');
  const [modeTransport, setModeTransport] = useState('');
  const [tracking, setTracking] = useState('');
  const [lieuDepart, setLieuDepart] = useState('');
  const [destination, setDestination] = useState('');
  const [dateArrivee, setDateArrivee] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open || !order) return;
    setDateExpedition(order.date_expedition || (mode === 'expedier' ? appToday() : ''));
    setTransporteur(order.transporteur || '');
    setModeTransport(order.mode_transport || '');
    setTracking(order.tracking || '');
    setLieuDepart(order.lieu_depart || '');
    setDestination(order.destination || 'Madagascar');
    setDateArrivee(order.date_arrivee || '');
  }, [open, order, mode]);

  const submit = async () => {
    setSubmitting(true);
    try {
      const payload: Record<string, unknown> = {
        date_expedition: dateExpedition || null,
        transporteur,
        mode_transport: modeTransport,
        tracking,
        lieu_depart: lieuDepart,
        destination,
      };
      if (mode === 'expedier') {
        await djangoClient.suppliers.expedier(order.id, payload as any);
        toast.success('Marchandise expédiée — approvisionnement en transit');
      } else {
        await djangoClient.suppliers.update(order.id, { ...payload, date_arrivee: dateArrivee || null });
        toast.success('Informations de transport mises à jour');
      }
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toast.error(messageErreur(err, 'Enregistrement impossible'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{mode === 'expedier' ? 'Expédier la marchandise' : 'Informations de transport'}</DialogTitle>
          <DialogDescription>
            {mode === 'expedier'
              ? "Renseignez le départ de la marchandise : l'approvisionnement passera « En transit »."
              : 'Modifier les informations logistiques de cet approvisionnement.'}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Date d'expédition</Label>
              <Input type="date" value={dateExpedition} onChange={(e) => setDateExpedition(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>Mode de transport</Label>
              <Select value={modeTransport} onValueChange={setModeTransport}>
                <SelectTrigger className="w-full"><SelectValue placeholder="Choisir…" /></SelectTrigger>
                <SelectContent>
                  {MODES_TRANSPORT.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Transporteur</Label>
              <Input value={transporteur} onChange={(e) => setTransporteur(e.target.value)} placeholder="Ex : DHL, MSC…" />
            </div>
            <div className="space-y-1">
              <Label>Numéro de suivi</Label>
              <Input value={tracking} onChange={(e) => setTracking(e.target.value)} placeholder="Tracking / BL" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Lieu de départ</Label>
              <Input value={lieuDepart} onChange={(e) => setLieuDepart(e.target.value)} placeholder="Ex : Guangzhou" />
            </div>
            <div className="space-y-1">
              <Label>Destination</Label>
              <Input value={destination} onChange={(e) => setDestination(e.target.value)} />
            </div>
          </div>
          {mode === 'modifier' && (
            <div className="space-y-1">
              <Label>Date d'arrivée</Label>
              <Input type="date" value={dateArrivee} onChange={(e) => setDateArrivee(e.target.value)} />
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? 'Enregistrement…' : mode === 'expedier' ? 'Confirmer l\'expédition' : 'Enregistrer'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Arrivée à Madagascar                                                        */
/* -------------------------------------------------------------------------- */

export function ArriverDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [date, setDate] = useState(appToday());
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => { if (open) setDate(order?.date_arrivee || appToday()); }, [open, order]);

  const submit = async () => {
    setSubmitting(true);
    try {
      await djangoClient.suppliers.arriver(order.id, date || undefined);
      toast.success('Marchandise arrivée — vous pouvez saisir la douane et réceptionner');
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toast.error(messageErreur(err, 'Enregistrement impossible'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Marquer comme arrivé</DialogTitle>
          <DialogDescription>Date d'arrivée de la marchandise à Madagascar.</DialogDescription>
        </DialogHeader>
        <div className="space-y-1">
          <Label>Date d'arrivée</Label>
          <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>{submitting ? 'Enregistrement…' : 'Confirmer l\'arrivée'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Réception (totale ou partielle)                                             */
/* -------------------------------------------------------------------------- */

export function ReceptionDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [quantites, setQuantites] = useState<Record<number, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const lines: any[] = order?.lines || [];

  useEffect(() => {
    if (!open || !order) return;
    const init: Record<number, string> = {};
    for (const l of order.lines || []) init[l.id] = String(Math.max(Number(l.quantite) - Number(l.quantite_recue || 0), 0));
    setQuantites(init);
  }, [open, order]);

  const totalMaintenant = lines.reduce((s, l) => s + (num(quantites[l.id]) || 0), 0);
  const totalReste = lines.reduce((s, l) => s + Math.max(Number(l.quantite) - Number(l.quantite_recue || 0), 0), 0);
  const partielle = totalMaintenant < totalReste;

  const submit = async () => {
    const payload: { line_id: number; quantite_recue: number }[] = [];
    for (const l of lines) {
      const reste = Math.max(Number(l.quantite) - Number(l.quantite_recue || 0), 0);
      const q = Math.floor(num(quantites[l.id]));
      if (q < 0) { toast.error('Quantité négative'); return; }
      if (q > reste) { toast.error(`${l.reference_name} (${l.couleur}) : ${q} > ${reste} restant(s)`); return; }
      payload.push({ line_id: l.id, quantite_recue: q });
    }
    if (totalMaintenant <= 0) { toast.error('Aucune quantité à réceptionner'); return; }
    setSubmitting(true);
    try {
      await djangoClient.suppliers.receive(order.id, payload);
      toast.success(partielle ? 'Réception partielle enregistrée — stock mis à jour' : 'Réception complète — stock mis à jour');
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toast.error(messageErreur(err, 'Réception impossible'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Réceptionner la marchandise</DialogTitle>
          <DialogDescription>
            Quantités reçues maintenant par ligne (pré-remplies avec le reste à recevoir). Les quantités entrent en stock immédiatement ; une réception partielle est possible.
          </DialogDescription>
        </DialogHeader>
        <div className="rounded-md border overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-xs text-muted-foreground">
              <tr>
                <th className="text-left px-3 py-2 font-medium">Produit</th>
                <th className="text-right px-3 py-2 font-medium">Commandé</th>
                <th className="text-right px-3 py-2 font-medium">Déjà reçu</th>
                <th className="text-right px-3 py-2 font-medium">Reste</th>
                <th className="text-right px-3 py-2 font-medium w-32">Reçu maintenant</th>
              </tr>
            </thead>
            <tbody>
              {lines.map((l) => {
                const reste = Math.max(Number(l.quantite) - Number(l.quantite_recue || 0), 0);
                return (
                  <tr key={l.id} className="border-t">
                    <td className="px-3 py-2">
                      <span className="font-medium">{l.brand_name ? `${l.brand_name} ` : ''}{l.reference_name}</span>
                      <span className="text-muted-foreground"> — {l.couleur}</span>
                    </td>
                    <td className="text-right px-3 py-2 tabular-nums">{l.quantite}</td>
                    <td className="text-right px-3 py-2 tabular-nums">{l.quantite_recue || 0}</td>
                    <td className="text-right px-3 py-2 tabular-nums">{reste}</td>
                    <td className="px-3 py-2">
                      <Input
                        type="number"
                        min={0}
                        max={reste}
                        className="h-8 text-right"
                        value={quantites[l.id] ?? ''}
                        disabled={reste === 0}
                        onChange={(e) => setQuantites((prev) => ({ ...prev, [l.id]: e.target.value }))}
                      />
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Total reçu maintenant</span>
          <span className="font-semibold tabular-nums">{totalMaintenant} / {totalReste} pièce(s)</span>
        </div>
        {partielle && totalMaintenant > 0 && (
          <Badge variant="secondary" className="w-fit">Réception partielle : l'approvisionnement restera ouvert pour le reste.</Badge>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting || totalMaintenant <= 0}>
            {submitting ? 'Réception…' : 'Confirmer la réception (entrée stock)'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Finalisation du coût                                                        */
/* -------------------------------------------------------------------------- */

export function FinaliserDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [majPrix, setMajPrix] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => { if (open) setMajPrix(true); }, [open]);

  const submit = async () => {
    setSubmitting(true);
    try {
      await djangoClient.suppliers.finaliser(order.id, majPrix);
      toast.success('Coût de revient finalisé et historisé');
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toast.error(messageErreur(err, 'Finalisation impossible'));
    } finally {
      setSubmitting(false);
    }
  };

  const nonRecu = (order?.lines || []).filter((l: any) => Number(l.quantite_recue || 0) < Number(l.quantite));

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Finaliser le coût de revient</DialogTitle>
          <DialogDescription>
            Valeur réelle {fmtAr(order?.cout_total)} pour {fmtNombre(order?.total_qty)} pièce(s), soit {fmtAr(order?.cout_unitaire)} / pièce en moyenne.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="flex items-start gap-3 rounded-md border border-amber-300 bg-amber-50 dark:bg-amber-950/30 dark:border-amber-800 p-3 text-sm">
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0 text-amber-600" />
            <div>
              <p className="font-medium">Action irréversible</p>
              <p className="text-muted-foreground">
                Le coût de revient sera figé et écrit dans l'historique de chaque variante. Il ne sera plus possible d'ajouter des frais, des paiements ni de modifier les lignes.
              </p>
              {nonRecu.length > 0 && (
                <p className="mt-1 text-amber-700 dark:text-amber-300">
                  {nonRecu.length} ligne(s) ne sont pas complètement reçues : le coût sera calculé sur les quantités réellement reçues.
                </p>
              )}
            </div>
          </div>
          <label className="flex items-start gap-3 rounded-md border p-3 cursor-pointer">
            <Checkbox checked={majPrix} onCheckedChange={(v) => setMajPrix(v === true)} className="mt-0.5" />
            <span className="text-sm">
              <span className="font-medium">Mettre à jour le prix d'achat des références avec le coût de revient</span>
              <span className="block text-muted-foreground text-xs mt-0.5">
                Le prix d'achat de chaque référence concernée prendra la valeur du coût de revient unitaire calculé.
              </span>
            </span>
          </label>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>{submitting ? 'Finalisation…' : 'Finaliser le coût'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Modification : informations générales, méthode d'allocation, lignes       */
/* -------------------------------------------------------------------------- */

interface LigneEdit {
  key: string;
  id?: number;
  product_variant: number;
  label: string;
  quantite: string;
  quantite_recue: number;
  prix_unitaire: string;
  allocation_manuelle_mga: string;
}

export function EditOrderDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [description, setDescription] = useState('');
  const [supplier, setSupplier] = useState<string>('');
  const [suppliers, setSuppliers] = useState<any[]>([]);
  const [devise, setDevise] = useState('MGA');
  const [taux, setTaux] = useState('1');
  const [date, setDate] = useState('');
  const [destination, setDestination] = useState('');
  const [methode, setMethode] = useState('VALEUR');
  const [lignes, setLignes] = useState<LigneEdit[]>([]);
  const [submitting, setSubmitting] = useState(false);

  // Ajout d'une ligne : recherche de référence puis choix de la couleur.
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);
  const [selectedRef, setSelectedRef] = useState<any | null>(null);
  const [variantId, setVariantId] = useState('');
  const [newQty, setNewQty] = useState('');
  const [newPrix, setNewPrix] = useState('');

  useEffect(() => {
    if (!open || !order) return;
    setDescription(order.description || '');
    setSupplier(order.supplier ? String(order.supplier) : '');
    setDevise(order.devise || 'MGA');
    setTaux(order.devise === 'MGA' ? '1' : String(Number(order.taux_change) || ''));
    setDate(order.date || '');
    setDestination(order.destination || '');
    setMethode(order.methode_allocation || 'VALEUR');
    setLignes((order.lines || []).map((l: any) => ({
      key: `l-${l.id}`,
      id: l.id,
      product_variant: l.product_variant,
      label: `${l.brand_name ? `${l.brand_name} ` : ''}${l.reference_name} — ${l.couleur}`,
      quantite: String(l.quantite),
      quantite_recue: Number(l.quantite_recue || 0),
      prix_unitaire: String(Number(l.prix_unitaire) || 0),
      allocation_manuelle_mga: l.allocation_manuelle_mga !== null && l.allocation_manuelle_mga !== undefined ? String(Number(l.allocation_manuelle_mga)) : '',
    })));
    setQuery(''); setSuggestions([]); setSelectedRef(null); setVariantId(''); setNewQty(''); setNewPrix('');
    djangoClient.suppliers.suppliersList({ actif: true }).then(setSuppliers).catch(() => {});
  }, [open, order]);

  useEffect(() => {
    if (!open) return;
    if (!query.trim()) { setSuggestions([]); return; }
    setSearching(true);
    const t = setTimeout(() => {
      djangoClient.catalog.references
        .autocomplete(query.trim())
        .then(setSuggestions)
        .catch(() => setSuggestions([]))
        .finally(() => setSearching(false));
    }, 250);
    return () => clearTimeout(t);
  }, [query, open]);

  const ajouterLigne = () => {
    if (!selectedRef || !variantId) { toast.error('Sélectionnez une référence et une couleur'); return; }
    const qty = Math.floor(num(newQty));
    if (qty < 1) { toast.error('Quantité invalide'); return; }
    const couleur = (selectedRef.couleurs || []).find((c: any) => String(c.variant_id) === variantId);
    if (!couleur) return;
    if (lignes.some((l) => l.product_variant === Number(variantId))) { toast.error('Cette variante est déjà dans la commande'); return; }
    setLignes((prev) => [...prev, {
      key: `n-${variantId}-${Date.now()}`,
      product_variant: Number(variantId),
      label: `${selectedRef.brand_name} ${selectedRef.reference_name} — ${couleur.couleur}`,
      quantite: String(qty),
      quantite_recue: 0,
      prix_unitaire: newPrix || '0',
      allocation_manuelle_mga: '',
    }]);
    setSelectedRef(null); setQuery(''); setVariantId(''); setNewQty(''); setNewPrix('');
  };

  const majLigne = (key: string, patch: Partial<LigneEdit>) =>
    setLignes((prev) => prev.map((l) => (l.key === key ? { ...l, ...patch } : l)));

  const totalDevise = useMemo(
    () => lignes.reduce((s, l) => s + num(l.quantite) * num(l.prix_unitaire), 0),
    [lignes],
  );

  const submit = async () => {
    if (devise !== 'MGA' && num(taux) <= 0) { toast.error('Le taux de change est requis pour une devise autre que le MGA'); return; }
    if (lignes.length === 0) { toast.error('Au moins une ligne est requise'); return; }
    for (const l of lignes) {
      const q = Math.floor(num(l.quantite));
      if (q < 1) { toast.error(`${l.label} : quantité invalide`); return; }
      if (q < l.quantite_recue) { toast.error(`${l.label} : ${l.quantite_recue} déjà reçu(s), quantité minimale ${l.quantite_recue}`); return; }
    }
    setSubmitting(true);
    try {
      await djangoClient.suppliers.update(order.id, {
        description,
        supplier: supplier ? Number(supplier) : null,
        devise,
        taux_change: devise === 'MGA' ? '1' : dec(taux, 4),
        date: date || undefined,
        destination,
        methode_allocation: methode,
        lines: lignes.map((l) => ({
          ...(l.id ? { id: l.id } : {}),
          product_variant: l.product_variant,
          quantite: Math.floor(num(l.quantite)),
          prix_unitaire: dec(l.prix_unitaire, 4),
          allocation_manuelle_mga: methode === 'MANUEL' ? (l.allocation_manuelle_mga === '' ? null : dec(l.allocation_manuelle_mga, 2)) : null,
        })),
      });
      toast.success('Approvisionnement mis à jour');
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toast.error(messageErreur(err, 'Mise à jour impossible'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Modifier l'approvisionnement {order?.numero}</DialogTitle>
          <DialogDescription>Informations générales, méthode d'allocation des frais et lignes de produits.</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Fournisseur</Label>
              <Select value={supplier || 'none'} onValueChange={(v) => setSupplier(v === 'none' ? '' : v)}>
                <SelectTrigger className="w-full"><SelectValue placeholder="Aucun" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">— Aucun —</SelectItem>
                  {suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.nom}{s.pays ? ` (${s.pays})` : ''}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Date de commande</Label>
              <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>
          <DeviseTauxFields devise={devise} setDevise={setDevise} taux={taux} setTaux={setTaux} order={order} />
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Destination</Label>
              <Input value={destination} onChange={(e) => setDestination(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>Méthode d'allocation des frais</Label>
              <Select value={methode} onValueChange={setMethode}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {METHODES_ALLOCATION.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1">
            <Label>Description</Label>
            <Textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} />
          </div>

          {/* Lignes */}
          <div className="space-y-2">
            <p className="text-sm font-medium">Lignes de produits</p>
            <div className="rounded-md border overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-muted/50 text-xs text-muted-foreground">
                  <tr>
                    <th className="text-left px-3 py-2 font-medium">Produit</th>
                    <th className="text-right px-3 py-2 font-medium w-24">Quantité</th>
                    <th className="text-right px-3 py-2 font-medium w-32">Prix unit. ({devise})</th>
                    {methode === 'MANUEL' && <th className="text-right px-3 py-2 font-medium w-36">Frais alloués (Ar)</th>}
                    <th className="w-10" />
                  </tr>
                </thead>
                <tbody>
                  {lignes.length === 0 && (
                    <tr><td colSpan={5} className="px-3 py-4 text-center text-muted-foreground">Aucune ligne.</td></tr>
                  )}
                  {lignes.map((l) => (
                    <tr key={l.key} className="border-t">
                      <td className="px-3 py-1.5">
                        {l.label}
                        {l.quantite_recue > 0 && <span className="block text-[11px] text-muted-foreground">{l.quantite_recue} déjà reçu(s)</span>}
                      </td>
                      <td className="px-2 py-1.5">
                        <Input type="number" min={Math.max(l.quantite_recue, 1)} className="h-8 text-right" value={l.quantite} onChange={(e) => majLigne(l.key, { quantite: e.target.value })} />
                      </td>
                      <td className="px-2 py-1.5">
                        <Input type="number" min={0} step="0.0001" className="h-8 text-right" value={l.prix_unitaire} onChange={(e) => majLigne(l.key, { prix_unitaire: e.target.value })} />
                      </td>
                      {methode === 'MANUEL' && (
                        <td className="px-2 py-1.5">
                          <Input type="number" min={0} step="0.01" className="h-8 text-right" value={l.allocation_manuelle_mga} onChange={(e) => majLigne(l.key, { allocation_manuelle_mga: e.target.value })} />
                        </td>
                      )}
                      <td className="px-1 py-1.5 text-right">
                        <Button
                          size="icon"
                          variant="ghost"
                          disabled={l.quantite_recue > 0}
                          title={l.quantite_recue > 0 ? 'Ligne déjà réceptionnée' : 'Retirer'}
                          onClick={() => setLignes((prev) => prev.filter((x) => x.key !== l.key))}
                        >
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="flex justify-end text-sm">
              <span className="text-muted-foreground mr-2">Total fournisseur :</span>
              <span className="font-semibold tabular-nums">{fmtDevise(totalDevise, devise)}</span>
              {devise !== 'MGA' && num(taux) > 0 && (
                <span className="text-muted-foreground ml-2">≈ {fmtAr(totalDevise * num(taux))}</span>
              )}
            </div>

            <div className="border rounded-lg p-3 space-y-2 bg-muted/30">
              <p className="text-sm font-medium">Ajouter une ligne</p>
              <div className="relative">
                <Input
                  placeholder="Rechercher une référence (ex : A15)"
                  value={selectedRef ? `${selectedRef.brand_name} ${selectedRef.reference_name}` : query}
                  onChange={(e) => { setQuery(e.target.value); setSelectedRef(null); setVariantId(''); }}
                />
                {!selectedRef && query.trim() && (
                  <div className="absolute z-10 mt-1 w-full bg-background border rounded-md shadow-md max-h-56 overflow-y-auto">
                    {searching ? (
                      <p className="px-3 py-2 text-sm text-muted-foreground">Recherche…</p>
                    ) : suggestions.length === 0 ? (
                      <p className="px-3 py-2 text-sm text-muted-foreground">Aucun résultat.</p>
                    ) : suggestions.map((s) => (
                      <button
                        type="button"
                        key={s.id}
                        className="w-full text-left px-3 py-2 text-sm hover:bg-muted flex justify-between"
                        onClick={() => { setSelectedRef(s); setQuery(''); setSuggestions([]); }}
                      >
                        <span>{s.brand_name} {s.reference_name} <span className="text-muted-foreground">({s.type_name})</span></span>
                        <span className="text-muted-foreground">{fmtAr(s.prix_vente)}</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
              <div className="grid grid-cols-3 gap-2">
                <Select value={variantId} onValueChange={setVariantId} disabled={!selectedRef}>
                  <SelectTrigger className="w-full"><SelectValue placeholder="Couleur" /></SelectTrigger>
                  <SelectContent>
                    {(selectedRef?.couleurs || []).map((c: any) => (
                      <SelectItem key={c.variant_id} value={String(c.variant_id)}>{c.couleur}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Input type="number" min={1} placeholder="Quantité" value={newQty} onChange={(e) => setNewQty(e.target.value)} />
                <Input type="number" min={0} step="0.0001" placeholder={`Prix unit. (${devise})`} value={newPrix} onChange={(e) => setNewPrix(e.target.value)} />
              </div>
              <Button type="button" variant="secondary" size="sm" onClick={ajouterLigne}><Plus className="h-4 w-4 mr-2" /> Ajouter</Button>
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>{submitting ? 'Enregistrement…' : 'Enregistrer les modifications'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
