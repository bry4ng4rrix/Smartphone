import { GrilleSkeleton, Skeleton } from "@/components/ui/skeleton";

export default function Loading() {
  return (
    <div className="mx-auto w-full max-w-[1400px] px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <Skeleton className="h-3 w-20" />
      <Skeleton className="mt-3 h-9 w-56" />
      <Skeleton className="mt-3 h-4 w-80" />
      <div className="mt-8">
        <Skeleton className="mb-6 hidden h-20 w-full lg:block" />
        <GrilleSkeleton />
      </div>
    </div>
  );
}
