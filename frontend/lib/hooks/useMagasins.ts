'use client'

import { useCallback, useEffect, useState } from 'react'
import { djangoClient } from '@/lib/django-client'

export interface Magasin {
  id: number
  shop_name: string
}

/**
 * Magasins accessibles au compte courant.
 *
 * `GET /api/users/magasins/` applique exactement le même périmètre que
 * `get_accessible_magasins` côté serveur (admin : les magasins de sa société ;
 * compte magasin : le sien) — la liste proposée ne peut donc pas contenir un
 * magasin que le serveur refuserait ensuite.
 *
 * `plusieurs` sert à n'afficher le sélecteur que là où il y a réellement un
 * choix à faire : une société mono-magasin ne doit pas voir apparaître une
 * liste déroulante à une seule entrée.
 */
export function useMagasins() {
  const [magasins, setMagasins] = useState<Magasin[]>([])
  const [loading, setLoading] = useState(true)

  const recharger = useCallback(async () => {
    if (!djangoClient.isAuthenticated()) {
      setLoading(false)
      return
    }
    try {
      const data = await djangoClient.magasins.list()
      setMagasins(data.map((m) => ({ id: m.id, shop_name: m.shop_name })))
    } catch {
      // Sans liste, les pages retombent sur « tous les magasins » : le
      // serveur reste la référence, il refusera ce qu'il doit refuser.
      setMagasins([])
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    recharger()
  }, [recharger])

  return { magasins, loading, plusieurs: magasins.length > 1, recharger }
}
