const express = require('express');
const router = express.Router();
const { pool } = require('../db');
const { v4: uuidv4 } = require('uuid');
const runner = require('../engine/runner');

router.post('/', async (req, res) => {
  const id = uuidv4();
  const { name, nodes = [] } = req.body;
  await pool.query('INSERT INTO flows(id, name, nodes) VALUES($1,$2,$3)', [id, name, nodes]);
  res.json({ id, name });
});

router.get('/', async (req, res) => {
  const { rows } = await pool.query('SELECT id, name, nodes FROM flows');
  res.json(rows);
});

router.post('/:flowId/trigger', async (req, res) => {
  const flowId = req.params.flowId;
  const { rows } = await pool.query('SELECT id, name, nodes, version FROM flows WHERE id=$1', [flowId]);
  if (!rows.length) return res.status(404).json({ error: 'flow not found' });

  const flow = rows[0];
  const runId = uuidv4();
  const run = { id: runId, flow_id: flow.id, version: flow.version || 1, state: 'queued', current_node: null, payload: req.body };
  await runner.enqueueRun(run);
  res.json({ runId });
});

module.exports = router;
