'use client';

import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Check, ChevronDown, ListOrdered } from 'lucide-react';
import { SECTIONS, type Section } from '@/lib/reports';

/**
 * Navigation entre les 8 rapports : onglets sur écran large, bouton
 * « Liste des rapports » avec menu déroulant sur mobile.
 */
export function ReportTabs({ actif, onChange }: { actif: Section; onChange: (s: Section) => void }) {
  const courant = SECTIONS.find((s) => s.key === actif) ?? SECTIONS[0];
  return (
    <div className="print:hidden">
      <div className="hidden lg:block">
        <Tabs value={actif} onValueChange={(v) => onChange(v as Section)}>
          <TabsList className="h-auto flex-wrap justify-start gap-1 bg-muted/60 p-1">
            {SECTIONS.map((s) => (
              <TabsTrigger key={s.key} value={s.key} className="px-3 py-1.5 text-sm">
                {s.label}
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
      </div>
      <div className="lg:hidden">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" className="w-full justify-between h-10">
              <span className="flex items-center gap-2">
                <ListOrdered className="h-4 w-4" />
                Liste des rapports
                <span className="text-muted-foreground">· {courant.label}</span>
              </span>
              <ChevronDown className="h-4 w-4 opacity-60" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-[var(--radix-dropdown-menu-trigger-width)]">
            {SECTIONS.map((s) => (
              <DropdownMenuItem key={s.key} onSelect={() => onChange(s.key)} className="flex items-center justify-between">
                <span>
                  <span className="block">{s.label}</span>
                  <span className="block text-xs text-muted-foreground">{s.description}</span>
                </span>
                {s.key === actif && <Check className="h-4 w-4" />}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
}
