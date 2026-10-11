/** Receipt confirmation must refer to a sequence this replica has issued. */
export function validRequestReceipt(actor: string, localActor: string, sequence: number, lastIssued: number): boolean {
  return actor === localActor && Number.isSafeInteger(sequence) && sequence >= 0 && sequence <= lastIssued;
}
