/** Engine-facing connection. The runtime owns profile preparation and native loading. */
export interface MozcBridgePort {
  prepare(): Promise<boolean>;
  executeAsync(operation: string, text: string, candidateId: number): Promise<string>;
}
