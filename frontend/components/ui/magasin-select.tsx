'use client'

import { Store } from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Label } from '@/components/ui/label'
import type { Magasin } from '@/lib/hooks/useMagasins'

/** Valeur du choix « Tous les magasins ». `null` ne passe pas dans un Select. */
export const TOUS_MAGASINS = 'tous'

/**
 * Sélecteur de magasin, partagé par Produits, Commandes et Nouvelle commande.
 *
 * Deux usages, d'où `avecTous` :
 *
 *  * pour FILTRER une liste, « Tous les magasins » est le défaut et affiche
 *    l'ensemble de la société ;
 *  * pour CRÉER (catégorie, marque, couleur…), il faut une boutique précise —
 *    le serveur refuse de deviner dès qu'il y en a plusieurs, et il a raison :
 *    deviner, ce serait créer au mauvais endroit.
 *
 * Ne s'affiche pas quand la société n'a qu'un magasin : il n'y a alors aucun
 * choix à faire, et le serveur le déduit tout seul.
 */
export function MagasinSelect({
  magasins,
  valeur,
  onChange,
  avecTous = true,
  label = 'Magasin',
  placeholder = 'Choisir un magasin',
  className,
  disabled,
}: {
  magasins: Magasin[]
  /** `null` = tous les magasins. */
  valeur: number | null
  onChange: (id: number | null) => void
  avecTous?: boolean
  label?: string | null
  placeholder?: string
  className?: string
  disabled?: boolean
}) {
  if (magasins.length <= 1) return null

  return (
    <div className={className}>
      {label ? (
        <Label className="mb-1.5 block text-xs text-muted-foreground">{label}</Label>
      ) : null}
      <Select
        value={valeur === null ? TOUS_MAGASINS : String(valeur)}
        onValueChange={(v) => onChange(v === TOUS_MAGASINS ? null : Number(v))}
        disabled={disabled}
      >
        <SelectTrigger className="min-w-48">
          <Store className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <SelectValue placeholder={placeholder} />
        </SelectTrigger>
        <SelectContent>
          {avecTous && <SelectItem value={TOUS_MAGASINS}>Tous les magasins</SelectItem>}
          {magasins.map((m) => (
            <SelectItem key={m.id} value={String(m.id)}>
              {m.shop_name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}
