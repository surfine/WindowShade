// 按钉住的 Codex 0.153.0 schema 核实际出站参数。这台机器上没有 python jsonschema，
// 用工程里已有的 ajv（Remotion 依赖）代替；两者都没有就明确 NOT RUN，不用“跳过”冒充通过。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';

const [, , repoArg, outboundArg, reportArg] = process.argv;
const repo = path.resolve(repoArg);
const root = path.join(repo, 'docs/handoff/reference/codex-app-server-schema-0.153.0/v2');
const names = {
  'thread/start': 'ThreadStartParams',
  'thread/resume': 'ThreadResumeParams',
  'turn/start': 'TurnStartParams',
  'model/list': 'ModelListParams',
};
const require = createRequire(import.meta.url);
const Ajv = require(path.join(repo, 'film/ws2-concept/node_modules/ajv'));
const ajv = new Ajv({ strict: false, allErrors: true });

const results = [];
for (const line of fs.readFileSync(outboundArg, 'utf8').split('\n')) {
  if (!line.trim()) continue;
  const obj = JSON.parse(line);
  const name = names[obj.method];
  if (!name) throw new Error(`unexpected method ${obj.method}`);
  const file = path.join(root, `${name}.json`);
  const raw = fs.readFileSync(file);
  const validate = ajv.compile(JSON.parse(raw));
  if (!validate(obj.params)) {
    throw new Error(`${obj.method} failed pinned schema: ${ajv.errorsText(validate.errors)}`);
  }
  results.push({
    method: obj.method,
    schema: `${name}.json`,
    schemaSHA256: crypto.createHash('sha256').update(raw).digest('hex'),
    status: 'PASS',
  });
}
fs.writeFileSync(reportArg, JSON.stringify({
  fixtures: results,
  validator: 'ajv 8 (local dependency); python jsonschema not installed here',
  boundary: 'JSON shape only, no transport, permission or CLI semantics',
}, null, 2) + '\n');
console.log(`Pinned schema: ${results.length} actual outbound params passed`);
