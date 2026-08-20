-- The reconciliation route is unmounted, so a component note must state its
-- conflict outright rather than send the reader to a page that no longer
-- answers. Each of these already describes the conflict; only the pointer goes.
UPDATE public.ecosystem_component
   SET status_note = 'Stage summary: debugging and testing, target Q3 2026. Its own slide says "post-Q1 2026" — the overview gives two different quarters.'
 WHERE id = 'sourceless-os';

UPDATE public.ecosystem_component
   SET status_note = btrim(replace(status_note, 'See discrepancies.', ''))
 WHERE status_note LIKE '%See discrepancies.%';

UPDATE public.ecosystem_component
   SET status_note = btrim(replace(status_note, '— see discrepancies.', ''))
 WHERE status_note LIKE '%see discrepancies.%';
