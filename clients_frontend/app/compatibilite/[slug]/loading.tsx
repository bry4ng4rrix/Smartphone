import { Skeleton } from "@/components/ui/skeleton";

export default function Chargement() {
  return (
    <div className="mx-auto w-full max-w-[1400px] px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <Skeleton className="h-3 w-20" />
      <Skeleton className="mt-3 h-8 w-64" />
      <div className="hairline mt-8 rounded-xl bg-surface/60 p-5 sm:p-7">
        <Skeleton className="h-6 w-80 max-w-full" />
        <Skeleton className="mt-2 h-4 w-96 max-w-full" />
        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <Skeleton className="h-16" />
          <Skeleton className="h-16" />
        </div>
        <Skeleton className="mt-6 h-13 w-full sm:w-40" />
      </div>
    </div>
  );
}
