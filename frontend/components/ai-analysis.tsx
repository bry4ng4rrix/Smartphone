'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Sparkles } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';

export interface AIAnalysisData {
  periode?: string;
  ca?: number;
  beneficeNet?: number;
  valeurStock?: number;
  beneficeEstimeStock?: number;
  ventesImpayeesCount?: number;
  topProduits?: { name: string; qty: number; revenue?: number; profit?: number }[];
  produitsSansMouvement?: { name: string }[];
  rupturesStock?: { name: string; stock?: number }[];
  stockBas?: { name: string; stock?: number; seuil?: number }[];
  repartitionMouvements?: Record<string, number>;
  topVendeurs?: { name: string; revenue: number }[];
  topMagasins?: { name: string; revenue: number }[];
}

// Analyse générée par un modèle Ollama local (voir frontend/app/api/ai/analyze/route.ts).
export function AIAnalysis({ data }: { data: AIAnalysisData }) {
  const [analysis, setAnalysis] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  const generateAnalysis = async () => {
    setLoading(true);
    setError(false);
    try {
      const res = await fetch('/api/ai/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      const result = await res.json();
      setAnalysis(result.analysis);
      if (!res.ok) setError(true);
    } catch (err) {
      console.error(err);
      setAnalysis("Erreur réseau lors de l'appel à l'analyse IA.");
      setError(true);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card className="bg-gradient-to-br from-indigo-50 to-purple-50 dark:from-indigo-950/20 dark:to-purple-950/20 border-indigo-100 dark:border-indigo-900/50">
      <CardHeader>
        <CardTitle className="text-lg flex items-center text-indigo-700 dark:text-indigo-400 gap-2">
          <Sparkles className="h-5 w-5" />
          Analyse IA Stratégique
        </CardTitle>
        <CardDescription>
          Générez une analyse basée sur le CA, le bénéfice, le stock et les produits les plus vendus.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {!analysis && !loading ? (
          <Button onClick={generateAnalysis} className="bg-indigo-600 hover:bg-indigo-700 text-white">
            <Sparkles className="h-4 w-4 mr-2" />
            Générer l'analyse
          </Button>
        ) : loading ? (
          <div className="space-y-2">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-[90%]" />
            <Skeleton className="h-4 w-[80%]" />
            <Skeleton className="h-4 w-[85%]" />
          </div>
        ) : (
          <div className="space-y-3">
            <div className={`text-sm whitespace-pre-wrap leading-relaxed ${error ? 'text-red-600 dark:text-red-400' : 'text-gray-800 dark:text-gray-200'}`}>
              {analysis}
            </div>
            <Button size="sm" variant="outline" onClick={generateAnalysis} disabled={loading}>
              <Sparkles className="h-3.5 w-3.5 mr-2" />
              Régénérer
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
