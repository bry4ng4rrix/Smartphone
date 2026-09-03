import Link from 'next/link';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Clock, LogOut } from 'lucide-react';

export default function PendingApprovalPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-muted/30 p-4">
      <Card className="w-full max-w-md shadow-xl text-center">
        <CardHeader className="space-y-1">
          <div className="mx-auto bg-amber-100 w-16 h-16 rounded-full flex items-center justify-center mb-4">
            <Clock className="h-8 w-8 text-amber-600" />
          </div>
          <CardTitle className="text-2xl font-bold">Compte en attente</CardTitle>
          <CardDescription>
            Votre accès doit être approuvé par un administrateur.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground">
            Merci de votre patience. Un administrateur examine actuellement votre demande. 
            Vous recevrez un accès complet dès que votre compte sera approuvé.
          </p>
          <div className="pt-4 flex flex-col gap-2">
            <Button asChild className="w-full">
              <Link href="/login">
                Actualiser la page
              </Link>
            </Button>
            <Button asChild variant="ghost" className="w-full text-muted-foreground">
              <Link href="/logout">
                <LogOut className="mr-2 h-4 w-4" />
                Se déconnecter
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
