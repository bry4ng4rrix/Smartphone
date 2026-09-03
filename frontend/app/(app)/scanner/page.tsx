"use client";

import { useState, useEffect, useRef } from "react";
import Link from "next/link";
import { djangoClient } from "@/lib/django-client";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { QrCode, Search, Package } from "lucide-react";
import { toast } from "sonner";

// Recherche rapide dans le catalogue (§8 Smartreadme.md). La vente
// instantanée a été retirée : le seul flux de vente est désormais le module
// Commandes (§5-§7.1) — ce lookup renvoie vers "Nouvelle commande".
export default function ScannerPage() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const search = async (q: string) => {
    if (!q) {
      setResults([]);
      return;
    }
    try {
      setLoading(true);
      const data = await djangoClient.products.search(q);
      setResults(data);
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la recherche");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    const timer = setTimeout(() => search(query), 350);
    return () => clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const stockStatus = (p: any) => {
    if (p.initial_quantity === 0)
      return { label: "Rupture", class: "bg-red-100 text-red-800" };
    if (p.initial_quantity <= p.alert_threshold)
      return { label: "Faible", class: "bg-orange-100 text-orange-800" };
    return { label: "En stock", class: "bg-green-100 text-green-800" };
  };

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
          <QrCode className="h-8 w-8 text-blue-600" /> Recherche produit
        </h1>
        <p className="text-muted-foreground mt-1">
          Recherchez une référence du catalogue par nom, marque ou modèle.
        </p>
      </div>

      <div className="relative max-w-xl">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          ref={inputRef}
          placeholder="Marque, référence..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="pl-10"
        />
      </div>

      {(query || results.length > 0) && (
        <div>
          {loading ? (
            <p className="text-muted-foreground text-sm">Recherche...</p>
          ) : results.length === 0 ? (
            <Card>
              <CardContent className="flex flex-col items-center py-12 text-muted-foreground gap-2">
                <Package className="h-10 w-10" />
                <p>Aucun produit trouvé pour « {query} »</p>
              </CardContent>
            </Card>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {results.map((p) => {
                const status = stockStatus(p);
                return (
                  <Card key={p.id} className="hover:shadow-md transition-shadow">
                    <CardHeader className="pb-2">
                      <div className="flex items-start justify-between gap-2">
                        <CardTitle className="text-base">{p.name}</CardTitle>
                        <Badge className={status.class}>{status.label}</Badge>
                      </div>
                      <p className="text-xs text-muted-foreground font-mono">{p.brand}</p>
                    </CardHeader>
                    <CardContent className="space-y-2">
                      <div className="grid grid-cols-2 gap-1 text-sm">
                        <div>
                          <p className="text-muted-foreground text-xs">Catégorie</p>
                          <p className="font-medium">{p.category || "-"}</p>
                        </div>
                        <div>
                          <p className="text-muted-foreground text-xs">Stock</p>
                          <p className="font-semibold">{p.initial_quantity} u.</p>
                        </div>
                        <div className="col-span-2">
                          <p className="text-muted-foreground text-xs">Prix vente</p>
                          <p className="font-medium">{new Intl.NumberFormat("fr-MG").format(p.shell_price || 0)} Ar</p>
                        </div>
                      </div>
                      <Button asChild className="w-full mt-2" size="sm">
                        <Link href="/orders">Créer une commande</Link>
                      </Button>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          )}
        </div>
      )}

      {!query && results.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center py-16 text-muted-foreground gap-3">
            <QrCode className="h-16 w-16 opacity-20" />
            <p className="text-lg font-medium">Tapez pour rechercher un produit</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
