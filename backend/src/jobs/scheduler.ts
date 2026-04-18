import { ingestRecentRecalls } from './fdaRecalls';

// ─── Scheduler ────────────────────────────────────────────────────────────────
// Simple setInterval-based scheduler. Prefer BullMQ when the list grows
// beyond ~3 recurring jobs (see CLAUDE.md "Jobs" convention).

const SIX_HOURS_MS = 6 * 60 * 60 * 1000;

let started = false;

export function startScheduler(): void {
  if (started) return;
  started = true;

  // Fire once on startup so a cold boot doesn't wait six hours for the
  // first ingest. Swallow errors — the interval keeps trying.
  void ingestRecentRecalls().catch(err => {
    console.error('[scheduler] initial fdaRecalls run failed:', err);
  });

  setInterval(() => {
    void ingestRecentRecalls().catch(err => {
      console.error('[scheduler] fdaRecalls run failed:', err);
    });
  }, SIX_HOURS_MS);

  console.log('[scheduler] registered fdaRecalls every 6h');
}
