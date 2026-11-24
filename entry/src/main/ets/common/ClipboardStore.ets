import { KANON_CLIPBOARD_HISTORY, KANON_CLIPBOARD_PINS, KANON_CLIPBOARD_REVISION } from './AppStorageKeys';
export const CLIPBOARD_PIN_LIMIT: number = 10;
export const CLIPBOARD_TEXT_LIMIT: number = 2000;
export const CLIPBOARD_HISTORY_LIMIT: number = 20;

// コピー履歴と固定を別に保存する。本文はログへ出さない。
class ClipboardStore {
  initialize(): void {
    PersistentStorage.persistProp(KANON_CLIPBOARD_PINS, '[]');
    PersistentStorage.persistProp(KANON_CLIPBOARD_HISTORY, '[]');
    AppStorage.setOrCreate(KANON_CLIPBOARD_REVISION, 0);
  }

  private read(key: string, limit: number): string[] {
    try {
      const parsed: string[] = JSON.parse(AppStorage.get<string>(key) ?? '[]') as string[];
      if (!Array.isArray(parsed)) { return []; }
      const valid: string[] = [];
      for (const value of parsed) {
        if (typeof value === 'string' && value.length > 0 && value.length <= CLIPBOARD_TEXT_LIMIT &&
          !valid.includes(value)) { valid.push(value); }
        if (valid.length === limit) { break; }
      }
      return valid;
    } catch (e) { return []; }
  }

  getPinned(): string[] { return this.read(KANON_CLIPBOARD_PINS, CLIPBOARD_PIN_LIMIT); }
  getRecent(): string[] { return this.read(KANON_CLIPBOARD_HISTORY, CLIPBOARD_HISTORY_LIMIT); }

  private changed(): void {
    AppStorage.setOrCreate(KANON_CLIPBOARD_REVISION, (AppStorage.get<number>(KANON_CLIPBOARD_REVISION) ?? 0) + 1);
  }

  remember(value: string): void {
    if (value.length === 0 || value.length > CLIPBOARD_TEXT_LIMIT) { return; }
    const recent: string[] = this.getRecent();
    if (recent[0] === value) { return; }
    AppStorage.setOrCreate(KANON_CLIPBOARD_HISTORY,
      JSON.stringify([value].concat(recent.filter((item: string) => item !== value)).slice(0, CLIPBOARD_HISTORY_LIMIT)));
    this.changed();
  }

  pin(value: string): string {
    if (value.length === 0 || value.length > CLIPBOARD_TEXT_LIMIT) { return 'too-long'; }
    const items: string[] = this.getPinned();
    if (items.includes(value)) { return 'exists'; }
    if (items.length >= CLIPBOARD_PIN_LIMIT) { return 'full'; }
    AppStorage.setOrCreate(KANON_CLIPBOARD_PINS, JSON.stringify([value].concat(items)));
    this.changed();
    return 'saved';
  }

  removePinned(value: string): void {
    AppStorage.setOrCreate(KANON_CLIPBOARD_PINS, JSON.stringify(this.getPinned().filter((item: string) => item !== value)));
    this.changed();
  }

  removeRecent(value: string): void {
    AppStorage.setOrCreate(KANON_CLIPBOARD_HISTORY, JSON.stringify(this.getRecent().filter((item: string) => item !== value)));
    this.changed();
  }
  clearRecent(): void { AppStorage.setOrCreate(KANON_CLIPBOARD_HISTORY, '[]'); this.changed(); }
}

export const clipboardStore: ClipboardStore = new ClipboardStore();
