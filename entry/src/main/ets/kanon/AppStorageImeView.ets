import { ImeViewPort } from './ImeViewPublisher';

/** ArkUI boundary. Candidate and preedit text stays in memory. */
class AppStorageImeView implements ImeViewPort {
  number(key: string, value: number): void { AppStorage.setOrCreate(key, value); }
  string(key: string, value: string): void { AppStorage.setOrCreate(key, value); }
  boolean(key: string, value: boolean): void { AppStorage.setOrCreate(key, value); }
  strings(key: string, value: string[]): void { AppStorage.setOrCreate(key, value); }
  numbers(key: string, value: number[]): void { AppStorage.setOrCreate(key, value); }
}

export const appStorageImeView: ImeViewPort = new AppStorageImeView();
