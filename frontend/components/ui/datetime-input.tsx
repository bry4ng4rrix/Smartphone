"use client";

import { Input } from "@/components/ui/input";

/**
 * Saisie date + heure en deux champs natifs séparés.
 *
 * `<input type="datetime-local">` n'offre pas la même chose selon le
 * navigateur : le sélecteur de Chrome propose date ET heure, celui de Firefox
 * seulement la date (l'heure ne se règle qu'au clavier, ce qui donne
 * l'impression qu'elle n'est pas modifiable). `type="date"` et `type="time"`
 * sont, eux, pleinement pris en charge partout — d'où ce composant.
 *
 * La valeur échangée reste au format `datetime-local` (`YYYY-MM-DDTHH:mm`),
 * donc les appelants existants (états, `new Date(value)`, envoi API) n'ont
 * rien à changer.
 */
export function DateTimeInput({
  value,
  onChange,
  className,
  disabled,
  min,
  max,
}: {
  value: string;
  onChange: (value: string) => void;
  className?: string;
  disabled?: boolean;
  /** Bornes au format `datetime-local` — seule la partie date est appliquée
   *  ici (deux champs séparés ne peuvent pas exprimer "ce jour-là, pas avant
   *  telle heure") ; le serveur reste l'autorité sur la borne exacte. */
  min?: string;
  max?: string;
}) {
  const [datePart = "", timePart = ""] = value ? value.split("T") : [];

  const emit = (date: string, time: string) => {
    if (!date && !time) {
      onChange("");
      return;
    }
    // Une heure seule n'a pas de sens ici : tant qu'aucune date n'est
    // choisie, on n'émet rien (le champ heure reste saisi et réutilisé dès
    // que la date arrive).
    if (!date) return;
    onChange(`${date}T${time || "00:00"}`);
  };

  return (
    <div className={`flex gap-2 ${className ?? ""}`}>
      <Input
        type="date"
        value={datePart}
        disabled={disabled}
        min={min ? min.split("T")[0] : undefined}
        max={max ? max.split("T")[0] : undefined}
        onChange={(e) => emit(e.target.value, timePart)}
        className="flex-1"
      />
      <Input
        type="time"
        value={timePart}
        disabled={disabled}
        onChange={(e) => emit(datePart, e.target.value)}
        className="w-32"
      />
    </div>
  );
}
