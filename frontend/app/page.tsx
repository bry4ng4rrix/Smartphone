import { redirect } from 'next/navigation';

export const metadata = {
  title: 'Smartphone.Mg',
};

export default function HomePage() {
  redirect('/login');
}
