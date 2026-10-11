import { ImeRuntimeBindings, ImeRuntimeBindingsPort } from './ImeRuntimeBindings';
import { appStorageImeView } from './AppStorageImeView';
import { realEditorPort } from './RealEditorPort';
import { readSharedFlickEnabled } from '../common/KeyboardConfig';
import { keyboardSettingsSync } from '../common/KeyboardSettingsSync';

/** Platform wiring for settings reads, saves and display updates. */
const port: ImeRuntimeBindingsPort = {
  readString: (key: string): string | undefined => AppStorage.get<string>(key),
  readNumber: (key: string): number | undefined => AppStorage.get<number>(key),
  string: (key: string, value: string): void => appStorageImeView.string(key, value),
  number: (key: string, value: number): void => appStorageImeView.number(key, value),
  boolean: (key: string, value: boolean): void => appStorageImeView.boolean(key, value),
  flickEnabled: (): boolean => readSharedFlickEnabled(),
  saveLayoutOrder: async (order: string): Promise<void> => {
    await keyboardSettingsSync.save({ layoutOrder: order }, false);
  },
  getEpoch: (): number => realEditorPort.getEpoch(),
  queryCursor: (): Promise<number> => realEditorPort.queryCursor()
};

export const imeRuntimeBindings: ImeRuntimeBindings = new ImeRuntimeBindings(port, {
  normal: InputType.Normal, password: InputType.Password,
  numberPassword: InputType.NUMBER_PASSWORD, newPassword: InputType.NEW_PASSWORD
});
