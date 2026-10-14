import { isUnsupportedRecurrence } from '../types/reminder.js';
import type { Reminder, ReminderRecurrence, Weekday } from '../types/reminder.js';

/** Sunday first, the order Reminders.app lists weekdays in. */
const WEEKDAYS: Array<{ name: Weekday; abbreviation: string }> = [
  { name: 'sunday', abbreviation: 'Sun' },
  { name: 'monday', abbreviation: 'Mon' },
  { name: 'tuesday', abbreviation: 'Tue' },
  { name: 'wednesday', abbreviation: 'Wed' },
  { name: 'thursday', abbreviation: 'Thu' },
  { name: 'friday', abbreviation: 'Fri' },
  { name: 'saturday', abbreviation: 'Sat' },
];

const UNITS = {
  daily: 'day',
  weekly: 'week',
  monthly: 'month',
  yearly: 'year',
} as const;

const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const MONTH_ABBREVIATIONS = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const ORDINAL_WORDS: Record<number, string> = {
  1: 'first',
  2: 'second',
  3: 'third',
  4: 'fourth',
  5: 'fifth',
  [-1]: 'last',
};

/** 1 -> "1st", 12 -> "12th", 22 -> "22nd" */
function ordinalNumber(n: number): string {
  const lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return `${n}th`;
  const suffix = { 1: 'st', 2: 'nd', 3: 'rd' }[n % 10] ?? 'th';
  return `${n}${suffix}`;
}

/** ["a", "b", "c"] -> "a, b and c" */
function joinList(items: string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`;
}

function sortedUnique(values: number[]): number[] {
  return [...new Set(values)].sort((a, b) => a - b);
}

function capitalize(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1);
}

/** "2026-12-31" -> "Dec 31, 2026", read straight from the string so no time zone can shift it */
function formatEndDate(endDate: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(endDate);
  const month = match ? MONTH_ABBREVIATIONS[Number(match[2]) - 1] : undefined;
  if (!match || !month) return endDate;
  return `${month} ${Number(match[3])}, ${Number(match[1])}`;
}

/** Never includes the RRULE: only get_reminder shows that. */
const UNSUPPORTED_SUMMARY = "Repeats on a custom schedule this server can't edit";

/**
 * Describe a recurrence rule the way Reminders.app does, e.g. "Every 2 weeks on Mon, Wed".
 * Deterministic: no locale or clock involved.
 */
export function formatRecurrenceSummary(rule: ReminderRecurrence): string {
  if (isUnsupportedRecurrence(rule)) return UNSUPPORTED_SUMMARY;

  const unit = UNITS[rule.frequency];
  const interval = rule.interval ?? 1;
  let summary = interval === 1 ? `Every ${unit}` : `Every ${interval} ${unit}s`;

  const months = sortedUnique(rule.monthsOfYear ?? []).map((month) => MONTH_NAMES[month - 1]);
  const nth = rule.nthWeekday
    ? `${ORDINAL_WORDS[rule.nthWeekday.ordinal]} ${capitalize(rule.nthWeekday.weekday)}`
    : undefined;

  if (rule.frequency === 'weekly' && rule.daysOfWeek && rule.daysOfWeek.length > 0) {
    const days = WEEKDAYS.filter((day) => rule.daysOfWeek?.includes(day.name))
      .map((day) => day.abbreviation)
      .join(', ');
    summary += ` on ${days}`;
  } else if (rule.frequency === 'monthly' && nth) {
    summary += ` on the ${nth}`;
  } else if (rule.frequency === 'monthly' && rule.daysOfMonth && rule.daysOfMonth.length > 0) {
    summary += ` on the ${joinList(sortedUnique(rule.daysOfMonth).map(ordinalNumber))}`;
  } else if (rule.frequency === 'yearly' && nth) {
    summary += months.length > 0 ? ` on the ${nth} of ${joinList(months)}` : ` on the ${nth}`;
  } else if (rule.frequency === 'yearly' && months.length > 0) {
    summary += ` in ${joinList(months)}`;
  }

  if (rule.endDate) {
    summary += `, until ${formatEndDate(rule.endDate)}`;
  } else if (rule.occurrenceCount !== undefined) {
    const count = rule.occurrenceCount;
    summary += `, ${count} ${count === 1 ? 'occurrence' : 'occurrences'} left`;
  }
  return summary;
}

/**
 * The "🔁 <summary>" line for a recurring reminder, or undefined for any other reminder.
 */
export function recurrenceSummaryLine(reminder: Reminder): string | undefined {
  return reminder.recurrence ? `🔁 ${formatRecurrenceSummary(reminder.recurrence)}` : undefined;
}
