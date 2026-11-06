export interface ContentFieldDefinition {
  key: string;
  label: string;
  kind: 'text' | 'textarea' | 'number' | 'boolean' | 'date' | 'select' | 'image';
  help: string;
  required: boolean;
  publicVisible: boolean;
  filterable: boolean;
  inList: boolean;
  options: { label: string; value: string }[];
}

export interface PublicCollection {
  key: string;
  name: string;
  singular: string;
  description: string;
  publicBase: string;
  hasArchive: boolean;
  features: string[];
  fields: ContentFieldDefinition[];
}

export interface ContentTypeDefinition extends PublicCollection {
  icon: string;
  adminBase: string;
  publicVisible: boolean;
  enabled: boolean;
  system: boolean;
  owner: string;
  capability: string;
  position: number;
  template: string;
  archiveTemplate: string;
  labels: Record<string, string>;
  minimumTitleLength: number;
  minimumContentLength: number;
  minimumExcerptLength: number;
}

export type CustomFieldValue = string | number | boolean | null;
export type CustomFieldValues = Record<string, CustomFieldValue>;

export function collectionLabel(
  type: Pick<ContentTypeDefinition, 'labels' | 'singular'>,
  key: string,
  translate: (key: string, parameters?: Record<string, string | number>) => string,
) {
  const explicit = type.labels[key];
  if (explicit) return translate(explicit);
  const patterns: Record<string, string> = {
    create: 'Create {type}',
    edit: 'Edit {type}',
    save: 'Save {type}',
    title: '{type} title',
  };
  return translate(patterns[key] || type.singular, { type: type.singular });
}

export function readCustomFields(
  encoded: unknown,
  definitions: ContentFieldDefinition[],
  fallback: CustomFieldValues = {},
): CustomFieldValues {
  let source: CustomFieldValues = fallback;
  try {
    const parsed = typeof encoded === 'string' ? JSON.parse(encoded) : encoded;
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) source = parsed;
  } catch {
    source = fallback;
  }
  return Object.fromEntries(
    definitions.map((field) => {
      const value = source[field.key] ?? (field.kind === 'boolean' ? false : null);
      if (field.kind === 'boolean') {
        return [field.key, value === true || value === 1 || value === '1' || value === 'true'];
      }
      if (value !== null && !['number', 'boolean'].includes(field.kind)) {
        return [field.key, String(value)];
      }
      return [field.key, value];
    }),
  );
}
