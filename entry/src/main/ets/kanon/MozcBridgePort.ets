/** Engine-facing connection. The runtime owns profile preparation and native loading. */
export interface MozcBridgePort {
  prepare(): Promise<boolean>;
  undo(): Promise<string>;
  executeAsync(operation: string, text: string, candidateId: number): Promise<string>;
}
