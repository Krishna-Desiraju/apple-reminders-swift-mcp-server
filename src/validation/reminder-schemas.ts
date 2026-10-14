import { z } from 'zod';

/** Same text as the Swift CLI's error, so agents see one message whichever side rejects. */
export const RECURRENCE_NEEDS_DUE_DATE =
  'A recurring reminder needs a due date: pass dueDate as the first occurrence.';

/**
 * Recurrence frequency enum
 */
export const recurrenceFrequencySchema = z.enum(['daily', 'weekly', 'monthly', 'yearly']);

/**
 * Full lowercase English weekday names, Sunday first
 */
export const WEEKDAYS = [
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
] as const;

export const weekdaySchema = z.enum(WEEKDAYS, {
  errorMap: () => ({
    message: `daysOfWeek must use full lowercase weekday names: ${WEEKDAYS.join(', ')}`,
  }),
});

const WEEKDAY_LIST = WEEKDAYS.join(', ');

const DAYS_OF_MONTH_RANGE = 'daysOfMonth must be whole numbers from 1 to 31';
const MONTHS_OF_YEAR_RANGE = 'monthsOfYear must be whole numbers from 1 to 12';
const ORDINAL_RANGE = 'nthWeekday.ordinal must be 1, 2, 3, 4, 5 or -1 (last)';
const END_DATE_FORMAT = 'endDate must be a real calendar date in YYYY-MM-DD format (e.g. 2026-12-31)';

/** True for a real Gregorian calendar date written as YYYY-MM-DD (so not 2026-02-30). */
function isCalendarDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCFullYear(year); // years 0-99 would otherwise be read as 1900-1999
  return (
    date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
  );
}

const nthWeekdaySchema = z
  .object({
    ordinal: z
      .number({ invalid_type_error: ORDINAL_RANGE, required_error: ORDINAL_RANGE })
      .refine((value) => [1, 2, 3, 4, 5, -1].includes(value), ORDINAL_RANGE),
    weekday: z.enum(WEEKDAYS, {
      errorMap: () => ({
        message: `nthWeekday.weekday must use a full lowercase weekday name: ${WEEKDAY_LIST}`,
      }),
    }),
  })
  .strict();

/**
 * Recurrence rule schema. The same checks run again in Swift before any EventKit call
 * (RecurrenceRule.validate), so keep the messages in step.
 */
export const recurrenceRuleSchema = z
  .object({
    frequency: recurrenceFrequencySchema,
    interval: z
      .number({ invalid_type_error: 'interval must be a whole number, 1 or greater' })
      .int('interval must be a whole number, 1 or greater')
      .min(1, 'interval must be a whole number, 1 or greater')
      .default(1),
    daysOfWeek: z
      .array(weekdaySchema)
      .min(1, "daysOfWeek can't be empty: omit it to repeat on the due date's weekday")
      .optional(),
    daysOfMonth: z
      .array(
        z
          .number({ invalid_type_error: DAYS_OF_MONTH_RANGE })
          .int(DAYS_OF_MONTH_RANGE)
          .min(1, DAYS_OF_MONTH_RANGE)
          .max(31, DAYS_OF_MONTH_RANGE)
      )
      .min(1, "daysOfMonth can't be empty: omit it to repeat on the due date's day")
      .optional(),
    nthWeekday: nthWeekdaySchema.optional(),
    monthsOfYear: z
      .array(
        z
          .number({ invalid_type_error: MONTHS_OF_YEAR_RANGE })
          .int(MONTHS_OF_YEAR_RANGE)
          .min(1, MONTHS_OF_YEAR_RANGE)
          .max(12, MONTHS_OF_YEAR_RANGE)
      )
      .min(1, "monthsOfYear can't be empty: omit it to repeat in the due date's month")
      .optional(),
    endDate: z
      .string({ invalid_type_error: END_DATE_FORMAT })
      .refine(isCalendarDate, END_DATE_FORMAT)
      .optional(),
    occurrenceCount: z
      .number({ invalid_type_error: 'occurrenceCount must be a whole number, 1 or greater' })
      .int('occurrenceCount must be a whole number, 1 or greater')
      .min(1, 'occurrenceCount must be a whole number, 1 or greater')
      .optional(),
  })
  .strict()
  .superRefine((rule, ctx) => {
    const reject = (path: string, message: string) =>
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: [path], message });

    if (rule.daysOfWeek !== undefined && rule.frequency !== 'weekly') {
      reject('daysOfWeek', 'daysOfWeek only applies to weekly rules');
    }
    if (rule.daysOfMonth !== undefined && rule.frequency !== 'monthly') {
      reject('daysOfMonth', 'daysOfMonth only applies to monthly rules');
    }
    if (rule.monthsOfYear !== undefined && rule.frequency !== 'yearly') {
      reject('monthsOfYear', 'monthsOfYear only applies to yearly rules');
    }
    if (
      rule.nthWeekday !== undefined &&
      rule.frequency !== 'monthly' &&
      rule.frequency !== 'yearly'
    ) {
      reject('nthWeekday', 'nthWeekday only applies to monthly and yearly rules');
    }
    if (rule.daysOfMonth !== undefined && rule.nthWeekday !== undefined) {
      reject('nthWeekday', 'Use either daysOfMonth or nthWeekday, not both');
    }
    if (
      rule.frequency === 'yearly' &&
      rule.nthWeekday !== undefined &&
      rule.monthsOfYear === undefined
    ) {
      reject(
        'monthsOfYear',
        'A yearly nthWeekday needs monthsOfYear (e.g. the fourth Thursday of November)'
      );
    }
    if (rule.endDate !== undefined && rule.occurrenceCount !== undefined) {
      reject('occurrenceCount', 'Use either endDate or occurrenceCount, not both');
    }
  });

/**
 * Location proximity enum
 */
export const locationProximitySchema = z.enum(['enter', 'leave']);

/**
 * Location schema for location-based reminders
 */
export const locationSchema = z.object({
  title: z.string().optional(),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  radius: z.number().positive().default(100),
  proximity: locationProximitySchema.default('enter'),
});

/**
 * Alarm type enum
 */
export const alarmTypeSchema = z.enum(['absolute', 'relative']);

/**
 * Alarm schema
 */
export const alarmSchema = z.object({
  type: alarmTypeSchema,
  absoluteDate: z.string().optional(),
  relativeOffset: z.number().optional(), // seconds
});

/**
 * Schema for creating a reminder
 */
export const createReminderSchema = z
  .object({
    title: z.string().min(1, 'Title is required'),
    notes: z.string().optional(),
    listName: z.string().optional(),
    dueDate: z
      .string()
      .refine((val) => !val || !isNaN(Date.parse(val)), {
        message: 'dueDate must be a valid ISO 8601 date string',
      })
      .optional(),
    priority: z
      .number()
      .int()
      .min(0, 'Priority must be between 0 and 9')
      .max(9, 'Priority must be between 0 and 9')
      .optional()
      .describe('Priority: 0=none, 1=high/urgent (!!!), 5=medium, 9=low'),
    flagged: z.boolean().optional(),
    url: z.string().url('URL must be a valid URL').optional(),
    tags: z.array(z.string()).optional(),
    recurrence: recurrenceRuleSchema.optional(),
    location: locationSchema.optional(),
    alarms: z.array(alarmSchema).optional(),
  })
  .superRefine((input, ctx) => {
    if (input.recurrence && !input.dueDate) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['dueDate'],
        message: RECURRENCE_NEEDS_DUE_DATE,
      });
    }
  });

/**
 * What an update says about the recurrence of a reminder: omitted = unchanged, null = remove the
 * rule, an object = replace it. `get_reminder` shows an unsupported rule as
 * `{ supported: false, rrule }`; that shape is read-only, so say so instead of listing the
 * strict schema's unrelated complaints.
 */
const recurrenceUpdateSchema = z.preprocess((value, ctx) => {
  if (
    typeof value === 'object' &&
    value !== null &&
    'supported' in value &&
    value.supported === false
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message:
        "recurrence can't be sent back in the { supported: false, rrule } form that get_reminder shows for a rule this server can't edit. Pass a new rule to replace it, or recurrence: null to remove it.",
    });
    return z.NEVER;
  }
  return value;
}, recurrenceRuleSchema.nullable().optional());

/**
 * Schema for updating a reminder.
 *
 * `dueDate` and `recurrence` are tri-state: omitted = unchanged, null = cleared, value = set.
 * `.nullable().optional()` keeps an explicit null in the parsed output, so it reaches the CLI.
 */
export const updateReminderSchema = z
  .object({
    id: z.string().min(1, 'Reminder ID is required'),
    title: z.string().min(1, 'Title is required'),
    notes: z.string().optional(),
    listName: z.string().optional(),
    dueDate: z
      .string()
      .refine((val) => !val || !isNaN(Date.parse(val)), {
        message: 'dueDate must be a valid ISO 8601 date string',
      })
      .nullable()
      .optional(),
    priority: z.number().int().min(0).max(9).optional(),
    flagged: z.boolean().optional(),
    url: z.string().url().optional(),
    tags: z.array(z.string()).optional(),
    recurrence: recurrenceUpdateSchema,
  })
  .superRefine((input, ctx) => {
    // Only the case the input alone decides. Whether an existing rule survives a cleared due
    // date depends on the current reminder, so the CLI checks that.
    if (input.recurrence && input.dueDate === null) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['dueDate'],
        message: RECURRENCE_NEEDS_DUE_DATE,
      });
    }
  });

/**
 * Schema for getting a reminder
 */
export const getReminderSchema = z.object({
  id: z.string().min(1, 'Reminder ID is required'),
});

/**
 * Schema for listing reminders
 */
export const listRemindersSchema = z.object({
  completed: z.boolean().optional(),
});

/**
 * Schema for searching reminders
 */
export const searchRemindersSchema = z.object({
  searchText: z.string().min(1, 'Search text is required'),
  completed: z.boolean().optional(),
});

/**
 * Schema for completed reminders query
 */
export const completedRemindersSchema = z.object({
  startDate: z.string().optional(),
  endDate: z.string().optional(),
});

/**
 * Schema for completing a reminder
 */
export const completeReminderSchema = z.object({
  id: z.string().min(1, 'Reminder ID is required'),
});

/**
 * Schema for deleting a reminder
 */
export const deleteReminderSchema = z.object({
  id: z.string().min(1, 'Reminder ID is required'),
});

/**
 * Common validation helper
 */
export function validateInput<T>(schema: z.ZodSchema<T>, input: unknown): T {
  return schema.parse(input);
}
