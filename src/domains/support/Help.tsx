import { BookOpen, Search } from 'lucide-react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { EmptyState } from '@/components/ui/states';
import { Section } from './shared';

/**
 * Answers.
 *
 * This page has no content, and that is the finding rather than an omission.
 *
 * There is no table anywhere in `database.types.ts` that holds published help
 * content. Everything with a promising name was checked and none of it is an
 * answers list:
 *
 *  - `arx_documentation_vault` is the ARX governance document store — legal and
 *    audit filings, gated by `access_level`/`allowed_roles` to club members with
 *    a governance role. It is not member-facing and must not be surfaced here.
 *  - `support_ticket_analyses`, `support_ticket_fix_jobs` and
 *    `support_ticket_fix_history` are administrator tooling that runs bulk fixes
 *    over tickets. They contain job state, not answers.
 *  - The member's own resolved tickets carry `admin_notes`, which is the note
 *    staff write for each other. It is not written to be read by the member and
 *    routinely refers to other members, so it is not fetched anywhere in this
 *    domain and is not a source for this page either.
 *
 * The alternative would be to write a dozen plausible FAQ entries into this
 * file. That is worse than an empty page: hardcoded answers drift from the
 * product silently, and v2 shipped exactly that — help text in JSX describing a
 * withdrawal flow that had been replaced twice. An honest empty state can be
 * fixed by adding content; an invented one has to be discovered first.
 *
 * TODO(server): a `support_articles` table — `id, slug, title, body, category,
 * published, updated_at` — readable by any authenticated member through a
 * `published = true` policy, writable by admin only. Once it exists the search
 * box below becomes a filter over `title` and `body` and this empty state
 * becomes the no-results case.
 */
export default function Help() {
  return (
    <>
      <PageHeader
        title="Answers"
        description="Published help articles. Nothing has been published yet."
      />

      <Section
        title="Search answers"
        description="This search will cover published articles once there are any to cover."
      >
        <div className="space-y-2">
          <div className="relative">
            <Search
              className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
              aria-hidden="true"
            />
            <Input
              disabled
              className="pl-9"
              placeholder="Search is not available yet"
              aria-label="Search answers"
              aria-describedby="why-no-search"
            />
          </div>
          <p id="why-no-search" className="text-xs text-muted-foreground">
            Disabled because there is no article store to search. TODO(server): a{' '}
            <code className="rounded bg-elevated px-1 py-0.5">support_articles</code> table
            (id, slug, title, body, category, published, updated_at) readable by any signed-in
            member where <code className="rounded bg-elevated px-1 py-0.5">published</code> is
            true, writable by admin only.
          </p>
        </div>

        <div className="mt-4 border-t border-border pt-4">
          <EmptyState
            title="No published answers"
            description="No table in this platform holds member-facing help content. Nothing is written into this page by hand, so it stays empty until that content has somewhere real to live."
            icon={<BookOpen className="size-5" />}
            action={
              <Button asChild variant="secondary" size="sm">
                <Link to="/support">Open a ticket instead</Link>
              </Button>
            }
          />
        </div>
      </Section>

      <Card className="mt-6">
        <CardContent className="space-y-2 py-4 text-sm text-muted-foreground">
          <p className="font-medium text-foreground">Where the content would come from</p>
          <p>
            The ARX documentation vault holds governance and audit filings, but it is scoped to
            club members holding a governance role and is not member help. The support-ticket
            analysis tables are administrator tooling. Neither is an answers list, so neither is
            read here.
          </p>
        </CardContent>
      </Card>
    </>
  );
}
