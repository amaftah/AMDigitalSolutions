const { pool } = require('../db');
const IORedis = require('ioredis');
const redis = new IORedis(process.env.REDIS_URL);
const axios = require('axios').default;

async function enqueueRun(run) {
  await pool.query(
    'INSERT INTO runs(id, flow_id, version, state, current_node, payload) VALUES($1,$2,$3,$4,$5,$6)',
    [run.id, run.flow_id, run.version, run.state, run.current_node, run.payload]
  );
  await redis.lpush('runs_queue', JSON.stringify({ runId: run.id }));
}

module.exports = { enqueueRun };
