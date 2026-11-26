import { KANON_EMOJI_HISTORY } from './AppStorageKeys';
import { isPanelEmoji } from '../model/EmojiData';

const EMOJI_HISTORY_LIMIT: number = 32;

export interface EmojiHistoryStorage {
  persist: (key: string, initial: string) => void;
  read: (key: string) => string | undefined;
  write: (key: string, value: string) => void;
}

export class EmojiHistory {
  private storage: EmojiHistoryStorage;

  constructor(storage: EmojiHistoryStorage) { this.storage = storage; }

  initialize(): void {
    this.storage.persist(KANON_EMOJI_HISTORY, '[]');
  }

  getRecent(): string[] {
    try {
      const parsed: string[] = JSON.parse(this.storage.read(KANON_EMOJI_HISTORY) ?? '[]') as string[];
      if (!Array.isArray(parsed)) { return []; }
      const recent: string[] = [];
      for (const value of parsed) {
        if (isPanelEmoji(value) && !recent.includes(value)) { recent.push(value); }
        if (recent.length === EMOJI_HISTORY_LIMIT) { break; }
      }
      return recent;
    } catch (e) { return []; }
  }

  remember(value: string): void {
    if (!isPanelEmoji(value)) { return; }
    const recent: string[] = this.getRecent();
    if (recent[0] === value) { return; }
    const updated: string[] = [value].concat(recent.filter((item: string) => item !== value));
    this.storage.write(KANON_EMOJI_HISTORY, JSON.stringify(updated.slice(0, EMOJI_HISTORY_LIMIT)));
  }

  clear(): void { this.storage.write(KANON_EMOJI_HISTORY, '[]'); }
}
