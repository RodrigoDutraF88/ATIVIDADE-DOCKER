const { Pool } = require("pg");

// Configuracao apenas por variavel de ambiente.
const connectionString = process.env.DATABASE_URL;

const pool = new Pool({
  connectionString,
  // Falha rapido em vez de travar quando o banco nao esta acessivel.
  connectionTimeoutMillis: 3000,
});

// Usado por /health para checar se o banco responde.
async function ping() {
  const client = await pool.connect();
  try {
    await client.query("SELECT 1");
  } finally {
    client.release();
  }
}

module.exports = { pool, ping };
