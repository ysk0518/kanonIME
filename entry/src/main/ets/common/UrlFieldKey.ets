export const DEFAULT_URL_FIELD_KEY: string = 'www.';
export const HIDDEN_URL_FIELD_KEY: string = 'hide';
export const URL_FIELD_KEY_OPTIONS: string[] = [DEFAULT_URL_FIELD_KEY, '.com', '/', HIDDEN_URL_FIELD_KEY];

export function validUrlFieldKey(value: string): boolean {
  return URL_FIELD_KEY_OPTIONS.includes(value);
}

export function normalizeUrlFieldKey(value: string | undefined): string {
  return value !== undefined && validUrlFieldKey(value) ? value : DEFAULT_URL_FIELD_KEY;
}
