import { describe, expect, it } from 'vitest';
import {
  createListSchema,
  deleteListSchema,
  updateListSchema,
} from '../../src/validation/list-schemas.js';

describe('createListSchema', () => {
  it('accepts a name with optional color and source', () => {
    expect(
      createListSchema.parse({ name: 'Groceries', color: '#34c759', source: 'iCloud' })
    ).toEqual({ name: 'Groceries', color: '#34c759', source: 'iCloud' });
  });

  it('trims the name and rejects blank names', () => {
    expect(createListSchema.parse({ name: '  Work  ' }).name).toBe('Work');
    expect(() => createListSchema.parse({ name: '   ' })).toThrow();
  });

  it('accepts hex colors with or without #', () => {
    expect(() => createListSchema.parse({ name: 'A', color: 'FF9500' })).not.toThrow();
    expect(() => createListSchema.parse({ name: 'A', color: 'orange' })).toThrow();
    expect(() => createListSchema.parse({ name: 'A', color: '#FFF' })).toThrow();
  });
});

describe('updateListSchema', () => {
  it('requires id or name', () => {
    expect(() => updateListSchema.parse({ newName: 'B' })).toThrow(/id or name/);
  });

  it('requires something to change', () => {
    expect(() => updateListSchema.parse({ id: 'abc' })).toThrow(/Nothing to update/);
  });

  it('accepts a rename by name', () => {
    expect(updateListSchema.parse({ name: 'A', newName: 'B' })).toEqual({
      name: 'A',
      newName: 'B',
    });
  });
});

describe('deleteListSchema', () => {
  it('requires id or name', () => {
    expect(() => deleteListSchema.parse({})).toThrow(/id or name/);
    expect(deleteListSchema.parse({ id: 'abc' })).toEqual({ id: 'abc' });
  });
});
