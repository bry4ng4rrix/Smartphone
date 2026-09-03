import { redirect } from 'next/navigation';

export const metadata = {
  title: 'E-kajy Entana',
};

export default function HomePage() {
  redirect('/login');
}
