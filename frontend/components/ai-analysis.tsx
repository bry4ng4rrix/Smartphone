'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Sparkles } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';

export function AIAnalysis({ fastest, slowest, expiring }: { fastest: any[]; slowest: any[]; expiring: any[] }) {
  const [analysis, setAnalysis] = useState('');
  const [loading, setLoading] = useState(false);

  const generateAnalysis = async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/ai/analyze-movements', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fastest, slowest, expiring }),
      });
      const data = await res.json();
      setAnalysis(data.analysis);
    } catch (error) {
      console.error(error);
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
          Générez une analyse basée sur vos produits les plus vendus, vos stocks morts et les produits proches de la péremption.
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
          <div className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap leading-relaxed">
            {analysis}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
