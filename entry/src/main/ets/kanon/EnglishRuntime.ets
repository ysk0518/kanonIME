import {
  KANON_CANDIDATES_EXPANDED, KANON_ENGLISH_COMPOSING, KANON_ENGLISH_UNDO, KANON_ID_LIST, KANON_LIST,
  KANON_MODE, KANON_SEL
} from '../common/AppStorageKeys';
import { EnglishPrediction, EnglishPredictionUiPort } from './EnglishPrediction';

/** Shared runtime instance for the engine, controller and direct English path. */
class AppStorageEnglishPrediction implements EnglishPredictionUiPort {
  undoChanged(visible: boolean): void { AppStorage.setOrCreate(KANON_ENGLISH_UNDO, visible); }
  cleared(): void {
    AppStorage.setOrCreate(KANON_ENGLISH_COMPOSING, false);
    if (AppStorage.get<string>(KANON_MODE) === 'EN') { AppStorage.setOrCreate(KANON_SEL, -1); }
  }
  selectionAbandoned(): void {
    if (AppStorage.get<string>(KANON_MODE) !== 'EN') { return; }
    AppStorage.setOrCreate(KANON_LIST, [] as string[]);
    AppStorage.setOrCreate(KANON_ID_LIST, [] as number[]);
    AppStorage.setOrCreate(KANON_CANDIDATES_EXPANDED, false);
  }
}

export const englishPrediction: EnglishPrediction = new EnglishPrediction(new AppStorageEnglishPrediction());
