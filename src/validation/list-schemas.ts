import { z } from 'zod';

/**
 * Hex color like "#FF9500" (leading # optional)
 */
export const hexColorSchema = z
  .string()
  .regex(/^#?[0-9a-fA-F]{6}$/, 'color must be a hex color like #FF9500');

const listName = z.string().trim().min(1, 'List name cannot be empty');

/**
 * Schema for creating a list
 */
export const createListSchema = z.object({
  name: listName,
  color: hexColorSchema.optional(),
  source: z.string().min(1).optional(),
});

/**
 * Schema for updating a list. The list is identified by id or name.
 */
export const updateListSchema = z
  .object({
    id: z.string().min(1).optional(),
    name: z.string().min(1).optional(),
    newName: listName.optional(),
    color: hexColorSchema.optional(),
  })
  .refine((val) => val.id || val.name, { message: 'Either id or name is required' })
  .refine((val) => val.newName !== undefined || val.color !== undefined, {
    message: 'Nothing to update: provide newName and/or color',
  });

/**
 * Schema for deleting a list. The list is identified by id or name.
 */
export const deleteListSchema = z
  .object({
    id: z.string().min(1).optional(),
    name: z.string().min(1).optional(),
  })
  .refine((val) => val.id || val.name, { message: 'Either id or name is required' });
