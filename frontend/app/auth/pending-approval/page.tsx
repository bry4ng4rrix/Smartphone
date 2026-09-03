import { Clock, Mail } from 'lucide-react'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'

export const metadata = {
  title: 'En attente d\'approbation',
  description: 'Votre compte est en attente d\'approbation par un administrateur',
}

export default function PendingApprovalPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-b from-background to-muted/20 p-4">
      <Card className="w-full max-w-md shadow-xl">
        <CardHeader className="text-center pb-6">
          <div className="flex justify-center mb-4">
            <div className="bg-amber-100 dark:bg-amber-950 p-3 rounded-full">
              <Clock className="h-8 w-8 text-amber-600 dark:text-amber-400" />
            </div>
          </div>
          <CardTitle className="text-2xl">En attente d&apos;approbation</CardTitle>
          <CardDescription>Votre compte doit être approuvé par un administrateur</CardDescription>
        </CardHeader>

        <CardContent className="space-y-6">
          <div className="bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-800 rounded-lg p-4 space-y-2">
            <h3 className="font-semibold text-amber-900 dark:text-amber-100 flex items-center gap-2">
              <Mail className="h-4 w-4" />
              Qu&apos;est-ce qui se passe maintenant?
            </h3>
            <ul className="text-sm text-amber-800 dark:text-amber-200 space-y-2">
              <li className="flex gap-2">
                <span className="font-semibold">1.</span>
                <span>Un administrateur examinera votre demande d&apos;inscription</span>
              </li>
              <li className="flex gap-2">
                <span className="font-semibold">2.</span>
                <span>Vous recevrez une notification par email une fois approuvé</span>
              </li>
              <li className="flex gap-2">
                <span className="font-semibold">3.</span>
                <span>Vous pourrez vous connecter avec vos identifiants</span>
              </li>
            </ul>
          </div>

          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Le processus d&apos;approbation peut prendre quelques minutes à quelques heures selon la disponibilité de l&apos;administrateur.
            </p>

            <Link href="/login" className="block">
              <Button variant="outline" className="w-full">
                Retour à la connexion
              </Button>
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
