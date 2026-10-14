# Apple Reminders MCP Server

An MCP server that lets agents read and manage a user's Apple Reminders.

## Language

**Reminder**:
A single to-do item in Apple Reminders, belonging to exactly one list.
_Avoid_: Task, event, item

**Recurring reminder**:
A reminder that repeats on a schedule defined by its recurrence rule.
_Avoid_: Recurring event, repeating task

**Recurrence rule**:
The schedule a recurring reminder repeats on: how often, on which days, and when it stops.
_Avoid_: Repeat pattern, RRULE, schedule

**Occurrence**:
One due instance of a recurring reminder.
_Avoid_: Instance, iteration

**Advance**:
What completing an occurrence does: the recurring reminder moves to its next occurrence and stays open.
_Avoid_: Rollover, roll forward, reschedule

**Completed copy**:
The separate, completed, non-recurring reminder left behind when an occurrence is completed.
_Avoid_: Clone, history item

**Last occurrence**:
An occurrence with no next one; completing it completes the recurring reminder for good.
_Avoid_: End of series

**Unsupported recurrence rule**:
A recurrence rule on a reminder that this server can read but not express or edit, such as one set up in Reminders.app with a pattern the server doesn't model.
_Avoid_: Custom rule, unknown rule
