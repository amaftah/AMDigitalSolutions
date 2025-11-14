const IORedis = require('ioredis');
const redis = new IORedis(process.env.REDIS_URL);
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const axios = require('axios').default;

async function processJob(job) {
  const jobObj = JSON.parse(job);
  const runId = jobObj.runId;

  const { rows } = await pool.query('SELECT * FROM runs WHERE id=$1', [runId]);
  if (!rows.length) return;
  const run = rows[0];

  const flowRes = await pool.query('SELECT nodes FROM flows WHERE id=$1', [run.flow_id]);
  const nodes = flowRes.rows[0].nodes || [];

  let state = 'running';
  let result = {};

  for (const node of nodes) {
    if (node.type === 'http_request') {
      try {
        const resp = await axios({ method: node.method || 'GET', url: node.url, data: run.payload });
        result[node.id] = { status: 'ok', data: resp.data };
      } catch (e) {
        result[node.id] = { status: 'error', error: e.message };
        state = 'failed';
        break;
      }
    } else if (node.type === 'delay') {
      const ms = node.ms || 1000;
      await new Promise(r => setTimeout(r, ms));
      result[node.id] = { status: 'ok', slept: ms };
    } else if (node.type === 'log') {
      console.log('[run]', runId, 'log:', node.message || JSON.stringify(run.payload));
      result[node.id] = { status: 'ok' };
    }
  }

  const finalState = state === 'failed' ? 'failed' : 'completed';
  await pool.query('UPDATE runs SET state=$1, result=$2, updated_at=now() WHERE id=$3', [finalState, result, runId]);
}

async function main() {
  console.log('worker started, listening for runs_queue');
  while (true) {
    try {
      const job = await redis.rpop('runs_queue');
      if (job) await processJob(job);
      else await new Promise(r => setTimeout(r, 500));
    } catch (e) {
      console.error('worker error', e);
      await new Promise(r => setTimeout(r, 1000));
    }
  }
}

main();
