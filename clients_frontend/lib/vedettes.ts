/**
 * Vitrine éditoriale de la landing page : 4 modèles d'exemple fixes, choisis
 * à la main — pas une requête vers l'API catalogue. Contrairement au reste
 * de la page (qui n'affiche que des données réelles), ces fiches servent à
 * montrer le rendu d'une fiche produit (couleurs, note, stock) même quand le
 * catalogue réel est vide ou en cours de constitution.
 */
export type CouleurVedette = {
  nom: string;
  /** Chemin public/ — seul le premier modèle a de vraies photos fournies. */
  photo?: string;
};

export type ProduitVedette = {
  id: string;
  marque: string;
  modele: string;
  sousType: string;
  description: string;
  /** Note sur 5. */
  note: number;
  prix: number;
  quantite: number;
  couleurs: CouleurVedette[];
};

export const PRODUITS_VEDETTES: ProduitVedette[] = [
  {
    id: "vedette-s21-ultra-carbon",
    marque: "Samsung",
    modele: "Galaxy S21 Ultra",
    sousType: "Coque Carbon",
    description:
      "Texture carbone fine et antidérapante, coins renforcés, découpe précise autour du bloc photo.",
    note: 4.6,
    prix: 35000,
    quantite: 18,
    couleurs: [
      { nom: "Argent / Noir", photo: "/vedettes/s21-ultra-argent-noir.png" },
      { nom: "Violet / Noir", photo: "/vedettes/s21-ultra-violet-noir.png" },
      { nom: "Bleu / Noir", photo: "/vedettes/s21-ultra-bleu-noir.png" },
    ],
  },
  {
    id: "vedette-iphone15-flip",
    marque: "Apple",
    modele: "iPhone 15",
    sousType: "Flip Cover",
    description:
      "Rabat aimanté avec fenêtre d'affichage, intérieur microfibre, protection intégrale de l'écran.",
    note: 4.3,
    prix: 42000,
    quantite: 9,
    couleurs: [{ nom: "Noir" }, { nom: "Bleu" }, { nom: "Beige" }],
  },
  {
    id: "vedette-redmi-zfold",
    marque: "Xiaomi",
    modele: "Redmi Note 13",
    sousType: "Premium Z-Fold",
    description:
      "Charnière renforcée et finition mate anti-traces, pensée pour un pliage quotidien sans jeu.",
    note: 4.1,
    prix: 38000,
    quantite: 14,
    couleurs: [{ nom: "Gris" }, { nom: "Noir" }],
  },
  {
    id: "vedette-chargeur-intelligent",
    marque: "Smart",
    modele: "Chargeur Intelligent 25W",
    sousType: "Chargeur",
    description:
      "Charge rapide avec protection contre la surchauffe, la surtension et les courts-circuits.",
    note: 4.8,
    prix: 25000,
    quantite: 27,
    couleurs: [{ nom: "Blanc" }, { nom: "Noir" }],
  },
];
