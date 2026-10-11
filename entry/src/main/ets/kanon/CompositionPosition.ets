/** Commit length and editor positions are UTF-16 units, not reading length. */
export function advanceCompositionStart(trackedStart: number, fallbackCursor: number, commitLength: number): number {
  const base: number = trackedStart >= 0 ? trackedStart : fallbackCursor;
  return (base >= 0 ? base : 0) + commitLength;
}
