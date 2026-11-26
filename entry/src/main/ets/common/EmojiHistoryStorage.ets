import { EmojiHistory } from './EmojiHistory';

export const emojiHistory: EmojiHistory = new EmojiHistory({
  persist: (key: string, initial: string): void => { PersistentStorage.persistProp(key, initial); },
  read: (key: string): string | undefined => AppStorage.get<string>(key),
  write: (key: string, value: string): void => { AppStorage.setOrCreate(key, value); }
});
