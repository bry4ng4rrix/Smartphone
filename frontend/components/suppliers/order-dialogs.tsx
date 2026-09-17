'use client';

/**
 * Dialogues d'un approvisionnement : paiement, départ Chine, transit,
 * arrivée Madagascar, Frais + Douane, finalisation (coût + réception stock),
 * modification. Chaque dialogue appelle l'API puis remonte l'appro renvoyé
 * (`onSaved`) — le serveur est la seule source des montants calculés.
 */
import { useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { appToday } from '@/lib/timezone';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { DEVISES, METHODES_PAIEMENT, MODES_TRANSPORT, TYPES_PAIEMENT, fmtAr, fmtDevise, fmtNombre, messageErreur } from './supplier-status';

interface BaseProps {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  order: any;
  onSaved: (order: any) => void;
}

const num = (v: string | number | null | undefined) => {
  const n = Number(String(v ?? '').replace(/\s/g, '').replace(',', '.'));
  return Number.isFinite(n) ? n : NaN;
};

function Pied({ onCancel, onSubmit, submitting, label }: { onCancel: () => void; onSubmit: () => void; submitting: boolean; label: string }) {
  return (
    <DialogFooter>
      <Button variant="outline" onClick={onCancel} disabled={submitting}>Annuler</Button>
      <Button onClick={onSubmit} disabled={submitting}>{submitting ? <Loader2 className="h-4 w-4 animate-spin" /> : label}</Button>
    </DialogFooter>
  );
}

/* -------------------------------------------------------------------------- */
/* Paiement fournisseur (§ 4-6)                                                */
/* -------------------------------------------------------------------------- */

export function PaymentDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [montant, setMontant] = useState('');
  const [devise, setDevise] = useState('USD');
  const [taux, setTaux] = useState('');
  const [date, setDate] = useState(appToday());
  const [type, setType] = useState('ACOMPTE');
  const [methode, setMethode] = useState('VIREMENT');
  const [reference, setReference] = useState('');
  const [commentaire, setCommentaire] = useState('');
  const [enCaisse, setEnCaisse] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open) return;
    setMontant('');
    setDevise(order?.devise || 'USD');
    setTaux(order?.devise === 'MGA' ? '1' : '');
    setDate(appToday());
    setType(Number(order?.total_paiements_mga || 0) > 0 ? 'SOLDE' : 'ACOMPTE');
    setMethode('VIREMENT');
    setReference('');
    setCommentaire('');
    setEnCaisse(false);
  }, [open, order]);

  const m = num(montant);
  const t = devise === 'MGA' ? 1 : num(taux);
  const apercu = Number.isFinite(m) && Number.isFinite(t) && m > 0 && t > 0 ? m * t : null;

  const submit = async () => {
    if (!Number.isFinite(m) || m <= 0) { toast.error('Montant invalide.'); return; }
    if (devise !== 'MGA' && (!Number.isFinite(t) || t <= 0)) { toast.error('Indiquez le taux de change du jour.'); return; }
    setSubmitting(true);
    try {
      const o = await djangoClient.suppliers.addPayment(order.id, {
        montant: m, devise, taux_change: devise === 'MGA' ? 1 : t, date, type_paiement: type, methode, reference, commentaire, en_caisse: enCaisse,
      });
      toast.success(`Paiement enregistré : ${fmtDevise(m, devise)} → ${fmtAr(m * t)}`);
      onSaved(o);
      onOpenChange(false);
    } catch (e) {
      toast.error(messageErreur(e, "Impossible d'enregistrer le paiement"));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Nouveau paiement — {order?.numero}</DialogTitle>
          <DialogDescription>
            Chaque paiement garde son propre taux : montant MGA = montant × taux du jour, jamais recalculé ensuite.
            {Number(order?.montant_prevu) > 0 && <> Prévu {fmtDevise(order.montant_prevu, order.devise)} · payé {fmtDevise(order.total_paye_devise, order.devise)} · reste {fmtDevise(order.reste_a_payer_devise, order.devise)}.</>}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1"><Label>Montant</Label><Input type="number" min={0} step="0.01" value={montant} onChange={(e) => setMontant(e.target.value)} autoFocus /></div>
            <div className="space-y-1"><Label>Date</Label><Input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Devise</Label>
              <Select value={devise} onValueChange={(v) => { setDevise(v); setTaux(v === 'MGA' ? '1' : ''); }}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>{DEVISES.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Taux du jour (Ar pour 1 {devise})</Label>
              <Input type="number" min={0} step="0.0001" value={taux} disabled={devise === 'MGA'} onChange={(e) => setTaux(e.target.value)} placeholder={devise === 'MGA' ? '1' : 'Ex : 4500'} />
            </div>
          </div>
          {apercu !== null && <p className="text-sm">= <strong className="tabular-nums">{fmtAr(apercu)}</strong></p>}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Type</Label>
              <Select value={type} onValueChange={setType}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>{TYPES_PAIEMENT.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Mode de paiement</Label>
              <Select value={methode} onValueChange={setMethode}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>{METHODES_PAIEMENT.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1"><Label>Référence (virement, reçu…)</Label><Input value={reference} onChange={(e) => setReference(e.target.value)} /></div>
          <div className="space-y-1"><Label>Commentaire</Label><Textarea rows={2} value={commentaire} onChange={(e) => setCommentaire(e.target.value)} /></div>
          <label className="flex items-start gap-2 text-sm">
            <Checkbox checked={enCaisse} onCheckedChange={(v) => setEnCaisse(v === true)} className="mt-0.5" />
            <span>Enregistrer la sortie en caisse (achat de stock, session ouverte requise) — référence <code className="text-xs">APPRO:{order?.numero}</code></span>
          </label>
        </div>
        <Pied onCancel={() => onOpenChange(false)} onSubmit={submit} submitting={submitting} label="Enregistrer le paiement" />
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Départ Chine / transit (§ 7-8)                                              */
/* -------------------------------------------------------------------------- */

export function TransportDialog({ open, onOpenChange, order, onSaved, mode }: BaseProps & { mode: 'expedier' | 'transit' }) {
  const [f, setF] = useState({ date_expedition: appToday(), transporteur: '', mode_transport: '', tracking: '', numero_colis: '', lieu_depart: 'Chine', destination: 'Madagascar', commentaire_transport: '' });
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open) return;
    setF({
      date_expedition: order?.date_expedition || appToday(),
      transporteur: order?.transporteur || '', mode_transport: order?.mode_transport || '', tracking: order?.tracking || '',
      numero_colis: order?.numero_colis || '', lieu_depart: order?.lieu_depart || 'Chine', destination: order?.destination || 'Madagascar',
      commentaire_transport: order?.commentaire_transport || '',
    });
  }, [open, order]);

  const submit = async () => {
    setSubmitting(true);
    try {
      const payload: Record<string, string> = {};
      for (const [k, v] of Object.entries(f)) if (v !== '' || k === 'commentaire_transport') payload[k] = v;
      if (mode === 'transit') { delete payload.date_expedition; delete payload.lieu_depart; delete payload.destination; }
      const o = mode === 'expedier' ? await djangoClient.suppliers.expedier(order.id, payload) : await djangoClient.suppliers.transit(order.id, payload);
      toast.success(mode === 'expedier' ? 'Marchandise expédiée depuis la Chine' : 'Marchandise en transit');
      onSaved(o);
      onOpenChange(false);
    } catch (e) {
      toast.error(messageErreur(e));
    } finally {
      setSubmitting(false);
    }
  };

  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{mode === 'expedier' ? 'Départ de Chine' : 'En transit'} — {order?.numero}</DialogTitle>
          <DialogDescription>{mode === 'expedier' ? 'Date de départ, transporteur, suivi et numéro de colis.' : 'Mettez à jour les informations de suivi disponibles.'}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          {mode === 'expedier' && (
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-1"><Label>Date de départ</Label><Input type="date" value={f.date_expedition} onChange={set('date_expedition')} /></div>
              <div className="space-y-1"><Label>Départ</Label><Input value={f.lieu_depart} onChange={set('lieu_depart')} /></div>
              <div className="space-y-1"><Label>Destination</Label><Input value={f.destination} onChange={set('destination')} /></div>
            </div>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1"><Label>Transporteur</Label><Input value={f.transporteur} onChange={set('transporteur')} placeholder="Ex : DHL, MSC…" /></div>
            <div className="space-y-1">
              <Label>Mode de transport</Label>
              <Select value={f.mode_transport || 'NONE'} onValueChange={(v) => setF({ ...f, mode_transport: v === 'NONE' ? '' : v })}>
                <SelectTrigger className="w-full"><SelectValue placeholder="—" /></SelectTrigger>
                <SelectContent><SelectItem value="NONE">—</SelectItem>{MODES_TRANSPORT.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1"><Label>Tracking / référence</Label><Input value={f.tracking} onChange={set('tracking')} /></div>
            <div className="space-y-1"><Label>Numéro de colis</Label><Input value={f.numero_colis} onChange={set('numero_colis')} /></div>
          </div>
          <div className="space-y-1"><Label>Commentaire</Label><Textarea rows={2} value={f.commentaire_transport} onChange={set('commentaire_transport')} /></div>
        </div>
        <Pied onCancel={() => onOpenChange(false)} onSubmit={submit} submitting={submitting} label={mode === 'expedier' ? 'Marquer expédié' : 'Marquer en transit'} />
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Arrivée à Madagascar (§ 9)                                                  */
/* -------------------------------------------------------------------------- */

export function ArriverDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [date, setDate] = useState(appToday());
  const [frais, setFrais] = useState('');
  const [submitting, setSubmitting] = useState(false);
  useEffect(() => { if (open) { setDate(appToday()); setFrais(Number(order?.frais_douane_mga) > 0 ? String(Number(order.frais_douane_mga)) : ''); } }, [open, order]);

  const submit = async () => {
    const f = frais.trim() === '' ? null : num(frais);
    if (f !== null && (!Number.isFinite(f) || f < 0)) { toast.error('Montant Frais + Douane invalide.'); return; }
    setSubmitting(true);
    try {
      const o = await djangoClient.suppliers.arriver(order.id, { date_arrivee: date, frais_douane_mga: f });
      toast.success('Marchandise arrivée à Madagascar');
      onSaved(o);
      onOpenChange(false);
    } catch (e) {
      toast.error(messageErreur(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Arrivée à Madagascar — {order?.numero}</DialogTitle>
          <DialogDescription>Le montant Frais + Douane peut être saisi maintenant ou plus tard, avant la finalisation.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1"><Label>Date d&apos;arrivée</Label><Input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
          <div className="space-y-1"><Label>Frais + Douane (Ar) — facultatif</Label><Input type="number" min={0} value={frais} onChange={(e) => setFrais(e.target.value)} placeholder="Ex : 5000000" /></div>
        </div>
        <Pied onCancel={() => onOpenChange(false)} onSubmit={submit} submitting={submitting} label="Marquer arrivé" />
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Frais + Douane (§ 9) — UN seul montant                                      */
/* -------------------------------------------------------------------------- */

export function FraisDouaneDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [frais, setFrais] = useState('');
  const [enCaisse, setEnCaisse] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  useEffect(() => { if (open) { setFrais(Number(order?.frais_douane_mga) > 0 ? String(Number(order.frais_douane_mga)) : ''); setEnCaisse(false); } }, [open, order]);

  const f = num(frais);
  const totalApercu = Number.isFinite(f) ? Number(order?.total_paiements_mga || 0) + f : null;

  const submit = async () => {
    if (!Number.isFinite(f) || f < 0) { toast.error('Montant invalide.'); return; }
    setSubmitting(true);
    try {
      const o = await djangoClient.suppliers.fraisDouane(order.id, { frais_douane_mga: f, en_caisse: enCaisse });
      toast.success('Frais + Douane enregistrés');
      onSaved(o);
      onOpenChange(false);
    } catch (e) {
      toast.error(messageErreur(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Frais + Douane — {order?.numero}</DialogTitle>
          <DialogDescription>Un seul montant, en ariary, ajouté au total des paiements fournisseur pour obtenir le coût total rendu Madagascar.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1"><Label>Frais + Douane (Ar)</Label><Input type="number" min={0} value={frais} onChange={(e) => setFrais(e.target.value)} autoFocus placeholder="Ex : 5000000" /></div>
          {totalApercu !== null && (
            <div className="rounded-md border p-3 text-sm space-y-0.5">
              <div className="flex justify-between"><span className="text-muted-foreground">Total paiements fournisseur</span><span className="tabular-nums">{fmtAr(order?.total_paiements_mga)}</span></div>
              <div className="flex justify-between"><span className="text-muted-foreground">+ Frais + Douane</span><span className="tabular-nums">{fmtAr(f)}</span></div>
              <div className="flex justify-between font-semibold border-t pt-1 mt-1"><span>Coût total</span><span className="tabular-nums">{fmtAr(totalApercu)}</span></div>
              <div className="flex justify-between"><span className="text-muted-foreground">÷ {fmtNombre(order?.quantite)} pièces = coût par pièce</span><span className="tabular-nums font-semibold">{fmtAr(order?.quantite ? totalApercu / Number(order.quantite) : 0)}</span></div>
            </div>
          )}
          <label className="flex items-start gap-2 text-sm">
            <Checkbox checked={enCaisse} onCheckedChange={(v) => setEnCaisse(v === true)} className="mt-0.5" disabled={order?.caisse?.frais_douane} />
            <span>{order?.caisse?.frais_douane ? 'Sortie déjà enregistrée en caisse.' : 'Enregistrer la sortie en caisse (achat de stock, session ouverte requise)'}</span>
          </label>
        </div>
        <Pied onCancel={() => onOpenChange(false)} onSubmit={submit} submitting={submitting} label="Enregistrer" />
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Finalisation (§ 10-13) : coût figé + réception dans le stock                */
/* -------------------------------------------------------------------------- */

export function FinaliserDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [majPrix, setMajPrix] = useState(true);
  const [quantite, setQuantite] = useState('');
  const [submitting, setSubmitting] = useState(false);
  useEffect(() => { if (open) { setMajPrix(true); setQuantite(String(order?.quantite ?? '')); } }, [open, order]);

  const submit = async () => {
    const q = Math.floor(num(quantite));
    if (!Number.isFinite(q) || q < 0 || q > Number(order?.quantite)) { toast.error(`Quantité reçue entre 0 et ${order?.quantite}.`); return; }
    setSubmitting(true);
    try {
      const o = await djangoClient.suppliers.finaliser(order.id, { mettre_a_jour_prix_achat: majPrix, quantite_recue: q });
      toast.success(`Coût finalisé : ${fmtAr(o.cout_unitaire_mga)} / pièce — ${fmtNombre(q)} pièce(s) reçue(s) en stock`);
      onSaved(o);
      onOpenChange(false);
    } catch (e) {
      toast.error(messageErreur(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Finaliser le coût — {order?.numero}</DialogTitle>
          <DialogDescription>Fige le coût total et le coût par pièce, et réceptionne la marchandise dans le stock (entrée référencée {order?.numero}).</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="rounded-md border p-3 text-sm space-y-0.5">
            <div className="flex justify-between"><span className="text-muted-foreground">Total paiements fournisseur</span><span className="tabular-nums">{fmtAr(order?.total_paiements_mga)}</span></div>
            <div className="flex justify-between"><span className="text-muted-foreground">+ Frais + Douane</span><span className="tabular-nums">{fmtAr(order?.frais_douane_mga)}</span></div>
            <div className="flex justify-between font-semibold border-t pt-1 mt-1"><span>Coût total rendu Madagascar</span><span className="tabular-nums">{fmtAr(order?.cout_total_mga)}</span></div>
            <div className="flex justify-between"><span className="text-muted-foreground">÷ {fmtNombre(order?.quantite)} pièces</span><span className="tabular-nums font-bold">{fmtAr(order?.cout_unitaire_mga)} / pièce</span></div>
          </div>
          {Number(order?.frais_douane_mga) === 0 && (
            <p className="flex items-start gap-2 text-xs text-amber-700 dark:text-amber-400"><AlertTriangle className="h-4 w-4 shrink-0" /> Aucun montant Frais + Douane saisi : le coût total ne comprend que les paiements fournisseur.</p>
          )}
          <div className="space-y-1"><Label>Pièces réellement reçues (entrée de stock)</Label><Input type="number" min={0} max={order?.quantite} value={quantite} onChange={(e) => setQuantite(e.target.value)} /></div>
          <label className="flex items-start gap-2 text-sm">
            <Checkbox checked={majPrix} onCheckedChange={(v) => setMajPrix(v === true)} className="mt-0.5" />
            <span>Mettre à jour le prix d&apos;achat de référence du produit (moyenne pondérée avec le stock existant)</span>
          </label>
        </div>
        <Pied onCancel={() => onOpenChange(false)} onSubmit={submit} submitting={submitting} label="Finaliser et réceptionner" />
      </DialogContent>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Modification (données générales, produit, quantité, transport)             */
/* -------------------------------------------------------------------------- */

export function EditOrderDialog({ open, onOpenChange, order, onSaved }: BaseProps) {
  const [f, setF] = useState({ description: '', quantite: '', devise: 'USD', montant_prevu: '', date: '', date_expedition: '', date_arrivee: '', transporteur: '', tracking: '', numero_colis: '' });
  const [submitting, setSubmitting] = useState(false);
  useEffect(() => {
    if (!open || !order) return;
    setF({
      description: order.description || '', quantite: String(order.quantite ?? ''), devise: order.devise || 'USD',
      montant_prevu: Number(order.montant_prevu) > 0 ? String(Number(order.montant_prevu)) : '', date: order.date || '',
      date_expedition: order.date_expedition || '', date_arrivee: order.date_arrivee || '', transporteur: order.transporteur || '',
      tracking: order.tracking || '', numero_colis: order.numero_colis || '',
    });
  }, [open, order]);

  const submit = async () => {
    const q = Math.floor(num(f.quantite));
    if (!Number.isFinite(q) || q < 1) { toast.error('Quantité invalide.'); return; }
    setSubmitting(true);
    try {
      const o = await djangoClient.suppliers.update(order.id, {
        description: f.description, quantite: q, devise: f.devise, montant_prevu: f.montant_prevu === '' ? 0 : num(f.montant_prevu),
        ...(f.date ? { date: f.date } : {}), date_expedition: f.date_expedition || null, date_arrivee: f.date_arrivee || null,
        transporteur: f.transporteur, tracking: f.tracking, numero_colis: f.numero_colis,
      });
      toast.success('Approvisionnement modifié');
      onSaved(o);
      onOpenChange(false);
    } catch (e) {
      toast.error(messageErreur(e));
    } finally {
      setSubmitting(false);
    }
  };
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Modifier — {order?.numero}</DialogTitle>
          <DialogDescription>Produit : {order?.produit?.libelle}. Le produit lui-même ne change pas (créez un autre approvisionnement).</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1"><Label>Quantité</Label><Input type="number" min={1} value={f.quantite} onChange={set('quantite')} /></div>
            <div className="space-y-1">
              <Label>Devise</Label>
              <Select value={f.devise} onValueChange={(v) => setF({ ...f, devise: v })}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>{DEVISES.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-1"><Label>Montant prévu</Label><Input type="number" min={0} step="0.01" value={f.montant_prevu} onChange={set('montant_prevu')} /></div>
          </div>
          <div className="space-y-1"><Label>Description</Label><Input value={f.description} onChange={set('description')} /></div>
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1"><Label>Date</Label><Input type="date" value={f.date} onChange={set('date')} /></div>
            <div className="space-y-1"><Label>Départ Chine</Label><Input type="date" value={f.date_expedition} onChange={set('date_expedition')} /></div>
            <div className="space-y-1"><Label>Arrivée</Label><Input type="date" value={f.date_arrivee} onChange={set('date_arrivee')} /></div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1"><Label>Transporteur</Label><Input value={f.transporteur} onChange={set('transporteur')} /></div>
            <div className="space-y-1"><Label>Tracking</Label><Input value={f.tracking} onChange={set('tracking')} /></div>
            <div className="space-y-1"><Label>N° colis</Label><Input value={f.numero_colis} onChange={set('numero_colis')} /></div>
          </div>
        </div>
        <Pied onCancel={() => onOpenChange(false)} onSubmit={submit} submitting={submitting} label="Enregistrer" />
      </DialogContent>
    </Dialog>
  );
}
