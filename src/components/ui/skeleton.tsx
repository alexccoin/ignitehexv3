import { cn } from '@/lib/utils';

/** Loading placeholder. Shaped like the content it replaces, so the layout
 *  does not jump when real data arrives. */
export const Skeleton = ({
  className,
  as: Tag = 'div',
}: {
  className?: string;
  /** Use "span" when the placeholder sits inside a <p> or other inline
   *  context — a <div> there is invalid HTML and React warns about it. */
  as?: 'div' | 'span';
}) => (
  <Tag
    className={cn(
      'relative overflow-hidden rounded-md bg-elevated',
      Tag === 'span' && 'inline-block align-middle',
      className
    )}
  >
    <span className="absolute inset-0 -translate-x-full animate-shimmer bg-gradient-to-r from-transparent via-foreground/5 to-transparent" />
  </Tag>
);
