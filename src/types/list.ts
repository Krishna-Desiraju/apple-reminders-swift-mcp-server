/**
 * Reminder list (calendar) data model
 */
export interface ReminderList {
  id: string;
  title: string;
  /** Hex color, e.g. "#FF9500" */
  color?: string;
  type: string;
  /** Account the list belongs to, e.g. "iCloud" */
  source?: string;
  allowsContentModifications: boolean;
}

/**
 * Result of deleting a list
 */
export interface DeleteListResult {
  deleted: boolean;
  id: string;
  title: string;
  remindersDeleted: number;
}
