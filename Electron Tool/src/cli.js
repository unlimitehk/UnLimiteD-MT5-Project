const fs = require('fs');
const path = require('path');

const runtimeDir = process.env.RR_RUNTIME_DIR || path.resolve(__dirname, '..', 'runtime');
const setupsFile = path.join(runtimeDir, 'RRAvailableSetups.csv');
const commandsFile = path.join(runtimeDir, 'RRExternalCommands.csv');
const resultsFile = path.join(runtimeDir, 'RRExternalResults.csv');

function readCsv(filePath) {
  if (!fs.existsSync(filePath)) return [];
  const raw = fs.readFileSync(filePath, 'utf8').trim();
  if (!raw) return [];
  return raw.split(/\r?\n/).map((line) => line.split(','));
}

function appendCsv(filePath, columns) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.appendFileSync(filePath, `${columns.join(',')}\n`, 'utf8');
}

function nextCommandId() {
  const rows = readCsv(commandsFile);
  const last = rows.length ? Number(rows[rows.length - 1][0]) : Date.now();
  return Number.isFinite(last) ? last + 1 : Date.now();
}

function placeBySymbol(symbol) {
  const rows = readCsv(setupsFile);
  if (rows.length <= 1) {
    throw new Error('RR setup index is empty. MT5 EA side is not publishing RRAvailableSetups.csv');
  }

  const body = rows.slice(1).map((r) => ({ base: r[0], symbol: r[1], armed: Number(r[2]) }));
  const armed = body.find((r) => r.symbol === symbol && r.armed >= 0.5);

  if (!armed) {
    throw new Error(`RR描画ツールが ${symbol} でARMされていないため発注できません。`);
  }

  const id = nextCommandId();
  appendCsv(commandsFile, [id, symbol, 'EXEC_MARKET']);
  return id;
}

function waitResult(commandId, timeoutMs = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const rows = readCsv(resultsFile);
    const hit = rows.find((r) => Number(r[0]) === commandId);
    if (hit) return { status: hit[2], message: hit[3] };
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 200);
  }
  return { status: 'TIMEOUT', message: 'Result not received from MT5 EA' };
}

function main() {
  const [, , cmd, symbol] = process.argv;
  if (cmd !== 'place' || !symbol) {
    console.log('Usage: node src/cli.js place <SYMBOL>');
    process.exit(1);
  }

  try {
    const id = placeBySymbol(symbol);
    console.log(`Command queued: id=${id}, symbol=${symbol}`);
    const result = waitResult(id);
    console.log(`Result: ${result.status} - ${result.message}`);
    if (result.status !== 'OK') process.exit(2);
  } catch (error) {
    console.error(error.message);
    process.exit(2);
  }
}

main();
