// Align stored native libraries before signing a HAP. Never modify a signed HAP.
const fs = require('fs');
const [input, output] = process.argv.slice(2);
if (!input || !output || input === output) throw new Error('Usage: align-hap.cjs unsigned.hap aligned.hap');
const data = fs.readFileSync(input);
let end = data.length - 22;
while (end >= 0 && data.readUInt32LE(end) !== 0x06054b50) end--;
if (end < 0) throw new Error('ZIP end record missing');
const count = data.readUInt16LE(end + 10);
let centralPos = data.readUInt32LE(end + 16);
const locals = [], centrals = [];
let offset = 0;
for (let i = 0; i < count; i++) {
  if (data.readUInt32LE(centralPos) !== 0x02014b50) throw new Error('Invalid central record');
  const nameLen = data.readUInt16LE(centralPos + 28);
  const extraLen = data.readUInt16LE(centralPos + 30);
  const commentLen = data.readUInt16LE(centralPos + 32);
  const central = Buffer.from(data.subarray(centralPos, centralPos + 46 + nameLen + extraLen + commentLen));
  const name = central.subarray(46, 46 + nameLen).toString();
  const oldOffset = central.readUInt32LE(42);
  const localNameLen = data.readUInt16LE(oldOffset + 26);
  const localExtraLen = data.readUInt16LE(oldOffset + 28);
  const headerLen = 30 + localNameLen + localExtraLen;
  const size = central.readUInt32LE(20);
  if (central.readUInt16LE(8) & 8) throw new Error('Data descriptors not supported');
  const header = Buffer.from(data.subarray(oldOffset, oldOffset + headerLen));
  let pad = Buffer.alloc(0);
  if (name.endsWith('.so')) {
    if (central.readUInt16LE(10) !== 0) throw new Error('Native library must be stored');
    let length = (4096 - ((offset + headerLen) % 4096)) % 4096;
    if (length > 0 && length < 4) length += 4096;
    if (length) {
      pad = Buffer.alloc(length);
      pad.writeUInt16LE(0xd935, 0);
      pad.writeUInt16LE(length - 4, 2);
      header.writeUInt16LE(localExtraLen + length, 28);
    }
    console.log(name + ': aligned offset ' + (offset + headerLen + pad.length));
  }
  central.writeUInt32LE(offset, 42);
  locals.push(header, pad, data.subarray(oldOffset + headerLen, oldOffset + headerLen + size));
  offset += headerLen + pad.length + size;
  centrals.push(central);
  centralPos += central.length;
}
const directory = Buffer.concat(centrals);
const trailer = Buffer.from(data.subarray(end));
trailer.writeUInt32LE(directory.length, 12);
trailer.writeUInt32LE(offset, 16);
fs.writeFileSync(output, Buffer.concat([...locals, directory, trailer]));
