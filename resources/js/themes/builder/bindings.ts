import type { ContentItem, SharedProps } from '../../types';
import type { DesignBlock } from './types';

export interface BindingContext {
  site: SharedProps['site'];
  item?: ContentItem | null;
  collection?: Record<string, unknown> | null;
  page: Record<string, unknown>;
}
export function bindingValue(context: BindingContext, path: string): unknown {
  const keys = path.split('.');
  if (!['site', 'item', 'collection', 'page'].includes(keys[0])) return '';
  let value: unknown = context;
  for (const key of keys) {
    if (
      ['__proto__', 'constructor', 'prototype'].includes(key) ||
      value === null ||
      typeof value !== 'object' ||
      !Object.hasOwn(value, key)
    )
      return '';
    value = (value as Record<string, unknown>)[key];
  }
  return value;
}
export function boundText(
  node: DesignBlock,
  field: string,
  fallback: string,
  context: BindingContext,
): string {
  const path = node.bindings?.[field];
  if (!path) return fallback;
  const value = bindingValue(context, path);
  return ['string', 'number', 'boolean'].includes(typeof value) ? String(value) : '';
}
export function isVisible(node: DesignBlock, context: BindingContext): boolean {
  if (!node.condition?.field) return true;
  const value = bindingValue(context, node.condition.field);
  if (node.condition.operator === 'equals') return String(value ?? '') === node.condition.value;
  const present = value !== '' && value !== null && value !== undefined && value !== false;
  return node.condition.operator === 'empty' ? !present : present;
}

export function linkValue(value: string): string {
  if (!value) return '';
  return /^(\/(?!\/)|#[A-Za-z]|https?:\/\/|mailto:|tel:)/.test(value) &&
    !/[\x00-\x20\x7f\\]/.test(value)
    ? value
    : '';
}
export function imageValue(value: string, pattern?: string, themeId?: string): string {
  if (!value) return '';
  const managed = pattern && new RegExp(pattern).test(value);
  const prefix = '/theme-assets/' + themeId + '/';
  const ownImage =
    themeId &&
    value.startsWith(prefix) &&
    /^ta_[A-Za-z0-9_-]{32}\.(jpg|png|webp|gif)$/.test(value.slice(prefix.length));
  return managed || ownImage ? value : '';
}
