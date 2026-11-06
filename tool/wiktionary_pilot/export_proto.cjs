// Execute on the server through interlex's remote_app helper (node - < this file).
// This deliberately bypasses ORM initialization: only a read-only SELECT is needed.
const DB = require('better-sqlite3');
const db = new DB(process.env.SQLITE_DB, {readonly: true, fileMustExist: true});
const rows = db.prepare('SELECT id,lemma,body,source_url AS sourceUrl FROM proto_slavic_words ORDER BY id').all();
process.stdout.write(JSON.stringify({source:'interlex-production',readOnly:true,exportedAtUtc:new Date().toISOString(),rows}));
db.close();
