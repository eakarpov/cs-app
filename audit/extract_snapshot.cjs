// Read BSON directly; no database connection or environment credentials.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const root = process.argv[2] || '/Users/georgecarpow/Documents/own/typikon-web';
const output = process.argv[3] || '/private/tmp/typikon-lexems-audit.json';
const { BSON } = createRequire(path.join(root, 'package.json'))('mongodb');
const buffer = fs.readFileSync(path.join(root, 'csl-db/typikon-csl/lexems.bson'));
const rows = [];
for (let offset = 0; offset < buffer.length;) {
  const size = buffer.readInt32LE(offset);
  if (size < 5 || offset + size > buffer.length) throw new Error('Invalid BSON document boundary');
  rows.push(BSON.deserialize(buffer.subarray(offset, offset + size)));
  offset += size;
}
fs.writeFileSync(output, JSON.stringify(rows));
console.log(JSON.stringify({ rows: rows.length, output }));
