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
