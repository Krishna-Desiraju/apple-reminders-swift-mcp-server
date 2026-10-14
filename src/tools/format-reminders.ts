import type { Reminder } from '../types/reminder.js';
import { recurrenceSummaryLine } from './recurrence-summary.js';

/**
 * Returns extra lines to show under a reminder (without indentation), or none.
 */
export type ReminderLineProducer = (reminder: Reminder) => string[];

/**
 * Extension point: every list tool shows these lines under each reminder's first
 * line, before its own detail lines.
 */
const extraLineProducers: ReminderLineProducer[] = [
  (reminder) => {
    const line = recurrenceSummaryLine(reminder);
    return line ? [line] : [];
  },
];

export interface ReminderListFormat {
  /** Tool-specific first line, without the "N. " prefix */
  firstLine: (reminder: Reminder) => string;
  /** Tool-specific lines under the extra lines, without indentation */
  detailLines?: (reminder: Reminder) => string[];
  /** Placed between entries */
  separator: string;
}

const DETAIL_INDENT = '   ';

/**
 * Format reminders as a numbered list, shared by all list-style tools
 */
export function formatReminderList(reminders: Reminder[], format: ReminderListFormat): string {
  return reminders
    .map((reminder, index) => {
      const lines = [
        ...extraLineProducers.flatMap((produce) => produce(reminder)),
        ...(format.detailLines?.(reminder) ?? []),
      ];
      return [
        `${index + 1}. ${format.firstLine(reminder)}`,
        ...lines.map((l) => DETAIL_INDENT + l),
      ].join('\n');
    })
    .join(format.separator);
}
