import { EnglishPrediction, EnglishPredictionUiPort } from './EnglishPrediction';

/** Shared runtime instance for the engine, controller and direct English path. */
class AppStorageEnglishPrediction implements EnglishPredictionUiPort {
  undoChanged(visible: boolean): void { AppStorage.setOrCreate('kanonEnglishUndo', visible); }
  cleared(): void {
    AppStorage.setOrCreate('kanonEnglishComposing', false);
    if (AppStorage.get<string>('kanonMode') === 'EN') { AppStorage.setOrCreate('kanonSel', -1); }
  }
  selectionAbandoned(): void {
    if (AppStorage.get<string>('kanonMode') !== 'EN') { return; }
    AppStorage.setOrCreate('kanonList', [] as string[]);
    AppStorage.setOrCreate('kanonIdList', [] as number[]);
    AppStorage.setOrCreate('kanonCandidatesExpanded', false);
  }
}

export const englishPrediction: EnglishPrediction = new EnglishPrediction(new AppStorageEnglishPrediction());
