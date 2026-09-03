import { RegisterForm } from '@/components/auth/register-form';

export const metadata = {
  title: 'Inscription - E-kajy Entana',
};

export default function RegisterPage() {
  return (
    <div className="min-h-screen flex items-center min-w-fit justify-center bg-linear-to-br from-background to-muted p-4">
     
    
        <RegisterForm />

    </div>
  );
}
