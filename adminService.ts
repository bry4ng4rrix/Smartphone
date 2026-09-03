import { djangoClient } from '../django-client';
import { MagasinOverview } from '../types';

export const adminService = {
  /**
   * Récupère la vue d'ensemble détaillée de tous les magasins pour l'administrateur.
   * @returns Une promesse qui résout en un tableau d'objets MagasinOverview.
   */
  getMagasinsOverview: async (): Promise<MagasinOverview[]> => {
    const response = await djangoClient.get('/users/magasins/overview/');
    // L'API Django retourne un objet avec une clé 'magasins' contenant le tableau.
    return response.data.magasins;
  },
};