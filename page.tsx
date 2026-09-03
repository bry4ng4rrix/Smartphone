'use client';

import React, { useEffect, useState } from 'react';
import { adminService } from '@/lib/services/adminService';
import { MagasinOverview } from '@/lib/types';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

const SuperAdminOverviewPage: React.FC = () => {
  const [magasinsOverview, setMagasinsOverview] = useState<MagasinOverview[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchOverview = async () => {
      try {
        setLoading(true);
        const data = await adminService.getMagasinsOverview();
        setMagasinsOverview(data);
      } catch (err) {
        console.error('Échec du chargement de la vue d\'ensemble des magasins :', err);
        setError('Échec du chargement de la vue d\'ensemble des magasins. Veuillez réessayer.');
      } finally {
        setLoading(false);
      }
    };

    fetchOverview();
  }, []);

  if (loading) {
    return <div className="text-center py-8">Chargement de la vue d'ensemble des magasins...</div>;
  }

  if (error) {
    return <div className="text-center text-red-500 py-8">{error}</div>;
  }

  return (
    <div className="container mx-auto py-8">
      <h1 className="text-3xl font-bold mb-6">Vue d'ensemble des Magasins (Admin)</h1>

      {magasinsOverview.length === 0 ? (
        <p className="text-gray-600">Aucun magasin trouvé ou associé à cet administrateur.</p>
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>Statistiques par Magasin</CardTitle>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nom du Magasin</TableHead>
                  <TableHead>Valeur Stock Totale</TableHead>
                  <TableHead>Bénéfices Totaux</TableHead>
                  <TableHead>Nombre de Produits</TableHead>
                  <TableHead>Ventes / Semaine</TableHead>
                  <TableHead>Nombre d'Employés</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {magasinsOverview.map((magasin) => (
                  <TableRow key={magasin.magasin_id}>
                    <TableCell className="font-medium">{magasin.shop_name}</TableCell>
                    <TableCell>{magasin.total_stock_value.toFixed(2)} €</TableCell>
                    <TableCell>{magasin.total_profit.toFixed(2)} €</TableCell>
                    <TableCell>{magasin.number_of_products}</TableCell>
                    <TableCell>{magasin.number_of_sales_week}</TableCell>
                    <TableCell>{magasin.number_of_employees}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}
    </div>
  );
};

export default SuperAdminOverviewPage;