import { useId } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { cn } from '@/lib/utils';

/**
 * Charts.
 *
 * The five series colours live in --chart-1..5 and were selected by running the
 * palette validator, not by eye: an earlier violet-heavy set that matched the
 * brand more closely collapsed to deltaE 3.0 under protanopia, meaning two
 * adjacent series were the same colour to a red-blind reader. The set in use
 * passes the lightness band, chroma floor, CVD separation, normal-vision floor
 * and contrast checks against both the light and dark chart surfaces.
 *
 * Identity is never carried by colour alone - every series is also named, in a
 * legend or a direct label - so the charts still read in greyscale, in print,
 * and in forced-colors mode.
 */

const SERIES = ['hsl(var(--chart-1))', 'hsl(var(--chart-2))', 'hsl(var(--chart-3))', 'hsl(var(--chart-4))', 'hsl(var(--chart-5))'];

/** Fixed assignment by index, never cycled. A sixth series folds into "Other". */
export const seriesColor = (i: number) => SERIES[i] ?? 'hsl(var(--muted-foreground))';

const AXIS = { stroke: 'hsl(var(--muted-foreground))', fontSize: 11 };

function TooltipBox({
  active,
  payload,
  label,
  format,
}: {
  active?: boolean;
  payload?: { name?: string; value?: number; color?: string; payload?: Record<string, unknown> }[];
  label?: string | number;
  format?: (v: number) => string;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border border-border bg-elevated px-3 py-2 shadow-lg">
      {label !== undefined && <p className="mb-1 text-xs text-muted-foreground">{String(label)}</p>}
      {payload.map((p, i) => (
        <div key={i} className="flex items-center gap-2 text-sm">
          <span
            className="size-2.5 shrink-0 rounded-sm"
            style={{ background: p.color }}
            aria-hidden="true"
          />
          <span className="text-muted-foreground">{p.name}</span>
          <span className="tabular ml-auto font-medium">
            {format ? format(Number(p.value)) : Number(p.value).toLocaleString()}
          </span>
        </div>
      ))}
    </div>
  );
}

export interface CompositionDatum {
  label: string;
  value: number;
}

/**
 * Horizontal bars for "how much of each".
 *
 * Deliberately not a pie: comparing angles is harder than comparing lengths,
 * and holdings routinely differ by orders of magnitude, which a pie renders as
 * an unreadable sliver. Each bar is directly labelled, so the colour is
 * decoration rather than the only key.
 */
export function CompositionChart({
  data,
  format,
  height = 200,
  className,
}: {
  data: CompositionDatum[];
  format?: (v: number) => string;
  height?: number;
  className?: string;
}) {
  const id = useId();
  if (!data.length) return null;

  return (
    <div className={cn('w-full', className)}>
      <ResponsiveContainer width="100%" height={height}>
        <BarChart data={data} layout="vertical" margin={{ top: 4, right: 16, bottom: 4, left: 4 }}>
          <CartesianGrid horizontal={false} stroke="hsl(var(--border))" strokeDasharray="2 4" />
          <XAxis type="number" {...AXIS} tickLine={false} axisLine={false} />
          <YAxis
            type="category"
            dataKey="label"
            {...AXIS}
            width={72}
            tickLine={false}
            axisLine={false}
          />
          <Tooltip
            cursor={{ fill: 'hsl(var(--muted-foreground) / 0.08)' }}
            content={<TooltipBox format={format} />}
          />
          {/* 4px rounded ends on the free end only, anchored to the baseline. */}
          <Bar dataKey="value" name="Amount" radius={[0, 4, 4, 0]} barSize={18}>
            {data.map((d, i) => (
              <Cell key={`${id}-${d.label}`} fill={seriesColor(i)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

export interface TrendDatum {
  label: string;
  value: number;
}

/**
 * Area chart for change over time. One series, so no legend box - the panel
 * title names it.
 */
export function TrendChart({
  data,
  format,
  colorIndex = 0,
  height = 200,
  className,
}: {
  data: TrendDatum[];
  format?: (v: number) => string;
  colorIndex?: number;
  height?: number;
  className?: string;
}) {
  const id = useId();
  const color = seriesColor(colorIndex);
  if (!data.length) return null;

  return (
    <div className={cn('w-full', className)}>
      <ResponsiveContainer width="100%" height={height}>
        <AreaChart data={data} margin={{ top: 8, right: 12, bottom: 4, left: 4 }}>
          <defs>
            <linearGradient id={`fill-${id}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.28} />
              <stop offset="100%" stopColor={color} stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid vertical={false} stroke="hsl(var(--border))" strokeDasharray="2 4" />
          <XAxis dataKey="label" {...AXIS} tickLine={false} axisLine={false} minTickGap={24} />
          <YAxis {...AXIS} tickLine={false} axisLine={false} width={56} />
          <Tooltip
            cursor={{ stroke: 'hsl(var(--muted-foreground))', strokeDasharray: '3 3' }}
            content={<TooltipBox format={format} />}
          />
          <Area
            type="monotone"
            dataKey="value"
            name="Value"
            stroke={color}
            strokeWidth={2}
            fill={`url(#fill-${id})`}
            dot={false}
            activeDot={{ r: 4, strokeWidth: 2, stroke: 'hsl(var(--surface))' }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

/** Legend for multi-series charts. Identity is text + swatch, never colour alone. */
export function ChartLegend({ items }: { items: { label: string; index: number }[] }) {
  return (
    <ul className="flex flex-wrap items-center gap-x-4 gap-y-1.5">
      {items.map((it) => (
        <li key={it.label} className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <span
            className="size-2.5 rounded-sm"
            style={{ background: seriesColor(it.index) }}
            aria-hidden="true"
          />
          {it.label}
        </li>
      ))}
    </ul>
  );
}
