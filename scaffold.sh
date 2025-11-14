#!/usr/bin/env bash
set -e

echo "Creating Digital Solution Starter Repo structure..."

### ROOT FILES ###
mkdir -p digitalsolution-starter
cd digitalsolution-starter

# README.md
cat > README.md << 'EOF'
# Digital Solution — Starter

This repo is a minimal starting point for a flow automation platform.

- backend: Node/Express API
- worker: background queue processor
- frontend: React + React-Flow canvas
- docker-compose: Postgres + Redis + services
EOF

# .env.example
cat > .env.example << 'EOF'
POSTGRES_USER=ds_user
POSTGRES_PASSWORD=ds_pass
POSTGRES_DB=ds_db
POSTGRES_PORT=5432
REDIS_HOST=redis
REDIS_PORT=6379
BACKEND_PORT=4000
DATABASE_URL=postgres://ds_user:ds_pass@postgres:5432/ds_db
REDIS_URL=redis://redis:6379
FRONTEND_PORT=3000
API_BASE_URL=http://localhost:4000/api
EOF

# docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7
    ports:
      - "6379:6379"

  backend:
    build: ./backend
    env_file: .env
    ports:
      - "4000:4000"
    depends_on:
      - postgres
      - redis

  worker:
    build: ./worker
    env_file: .env
    depends_on:
      - redis
      - postgres

  frontend:
    build: ./frontend
    env_file: .env
    ports:
      - "3000:3000"
    depends_on:
      - backend

volumes:
  pgdata:
EOF

### BACKEND ###
mkdir -p backend/src/engine backend/src/routes

cat > backend/package.json << 'EOF'
{
  "name": "ds-backend",
  "version": "0.1.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.0",
    "ioredis": "^5.3.2",
    "body-parser": "^1.20.2",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.22"
  }
}
EOF

cat > backend/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 4000
CMD ["node","src/server.js"]
EOF

# backend/src/db.js
cat > backend/src/db.js << 'EOF'
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function init() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS flows (
      id TEXT PRIMARY KEY,
      org_id TEXT,
      name TEXT,
      version INTEGER DEFAULT 1,
      nodes JSONB,
      created_at TIMESTAMP DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS runs (
      id TEXT PRIMARY KEY,
      flow_id TEXT,
      version INTEGER,
      state TEXT,
      current_node TEXT,
      payload JSONB,
      result JSONB,
      created_at TIMESTAMP DEFAULT now(),
      updated_at TIMESTAMP DEFAULT now()
    );
  `);
}

module.exports = { pool, init };
EOF

# backend/src/engine/runner.js
cat > backend/src/engine/runner.js << 'EOF'
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
EOF

# backend/src/routes/flows.js
cat > backend/src/routes/flows.js << 'EOF'
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
EOF

# backend/src/server.js
cat > backend/src/server.js << 'EOF'
const express = require('express');
const bodyParser = require('body-parser');
const flows = require('./routes/flows');
const { init } = require('./db');

const app = express();
app.use(bodyParser.json());
app.use('/api/flows', flows);

const port = process.env.BACKEND_PORT || 4000;

(async () => {
  await init();
  app.listen(port, () => console.log('backend listening on', port));
})();
EOF

### WORKER ###
mkdir -p worker/src

cat > worker/package.json << 'EOF'
{
  "name": "ds-worker",
  "version": "0.1.0",
  "main": "src/worker.js",
  "dependencies": {
    "ioredis": "^5.3.2",
    "pg": "^8.11.0",
    "axios": "^1.4.0",
    "uuid": "^9.0.0"
  }
}
EOF

cat > worker/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
CMD ["node","src/worker.js"]
EOF

cat > worker/src/worker.js << 'EOF'
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
EOF

### FRONTEND ###
mkdir -p frontend/src/components

cat > frontend/package.json << 'EOF'
{
  "name": "ds-frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "react-flow-renderer": "^11.6.0",
    "axios": "^1.4.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  }
}
EOF

cat > frontend/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
CMD ["npm","start"]
EOF

cat > frontend/src/index.jsx << 'EOF'
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';

createRoot(document.getElementById('root')).render(<App />);
EOF

cat > frontend/src/App.jsx << 'EOF'
import React, { useEffect, useState } from 'react';
import Canvas from './components/Canvas';
import axios from 'axios';

export default function App() {
  const [flows, setFlows] = useState([]);

  useEffect(() => {
    async function load() {
      try {
        const res = await axios.get(`${process.env.API_BASE_URL || 'http://localhost:4000/api'}/flows`);
        setFlows(res.data);
      } catch (e) {
        console.warn('could not load flows', e.message);
      }
    }
    load();
  }, []);

  return (
    <div style={{display:'flex',height:'100vh'}}>
      <div style={{width:300,padding:12,borderRight:'1px solid #eee'}}>
        <h3>Flows</h3>
        <ul>
          {flows.map(f => <li key={f.id}>{f.name || f.id}</li>)}
        </ul>
      </div>
      <div style={{flex:1}}>
        <Canvas />
      </div>
    </div>
  );
}
EOF

cat > frontend/src/components/Canvas.jsx << 'EOF'
import React, { useCallback, useState } from 'react';
import ReactFlow, { MiniMap, Controls, Background } from 'react-flow-renderer';

const initialNodes = [
  { id: '1', type: 'input', data: { label: 'Trigger' }, position: { x: 50, y: 50 } },
  { id: '2', data: { label: 'HTTP Request' }, position: { x: 300, y: 50 } },
  { id: '3', type: 'output', data: { label: 'Done' }, position: { x: 600, y: 50 } }
];

const initialEdges = [
  { id: 'e1-2', source: '1', target: '2' },
  { id: 'e2-3', source: '2', target: '3' }
];

export default function Canvas() {
  const [nodes, setNodes] = useState(initialNodes);
  const [edges, setEdges] = useState(initialEdges);

  const onNodesChange = useCallback(
    (changes) => setNodes((nds) =>
      nds.map((n) => {
        const c = changes.find((x) => x.id === n.id);
        return c ? { ...n, ...c } : n;
      })
    ),
    []
  );

  const onEdgesChange = useCallback(
    (changes) =>
      setEdges((eds) =>
        eds.map((e) => {
          const c = changes.find((x) => x.id === e.id);
          return c ? { ...e, ...c } : e;
        })
      ),
    []
  );

  return (
    <ReactFlow nodes={nodes} edges={edges} onNodesChange={onNodesChange} onEdgesChange={onEdgesChange} fitView>
      <MiniMap />
      <Controls />
      <Background />
    </ReactFlow>
  );
}
EOF

### SCRIPTS ###
mkdir -p scripts

# scripts/bootstrap_codespace.sh
cat > scripts/bootstrap_codespace.sh << 'EOF'
#!/usr/bin/env bash

set -euo pipefail

# ... (omitted for brevity; full script included in PDF)
echo "Bootstrap script placeholder from scaffold."
EOF

# scripts/codespace_post_create.sh
cat > scripts/codespace_post_create.sh << 'EOF'
#!/usr/bin/env bash
set -e
[ -d backend ] && (cd backend && npm ci --silent)
[ -d frontend ] && (cd frontend && npm ci --silent)
[ -d worker ] && (cd worker && npm ci --silent)
echo "Post-create setup complete."
EOF

chmod +x scripts/*.sh

echo "Scaffold created successfully!"
