const express = require("express");
const { pool, ping } = require("./db");

const app = express();
app.use(express.json());

const PORT = parseInt(process.env.PORT || "3000", 10);

// Banco pode nao estar de pe: respondemos 503 com mensagem clara.
// Isso e proposital, faz parte do aprendizado de rede e ordem de subida.
app.get("/health", async (_req, res) => {
  try {
    await ping();
    res.json({ status: "ok" });
  } catch (err) {
    res.status(503).json({
      status: "erro",
      mensagem: "banco de dados inacessivel: " + err.message,
    });
  }
});

app.get("/recados", async (_req, res) => {
  try {
    const { rows } = await pool.query(
      "SELECT id, autor, texto, criado_em FROM recados ORDER BY id"
    );
    res.json(rows);
  } catch (err) {
    res.status(503).json({
      status: "erro",
      mensagem: "banco de dados inacessivel: " + err.message,
    });
  }
});

app.post("/recados", async (req, res) => {
  const { autor, texto } = req.body || {};
  if (!autor || !texto) {
    return res
      .status(400)
      .json({ status: "erro", mensagem: "informe autor e texto" });
  }
  try {
    const { rows } = await pool.query(
      "INSERT INTO recados (autor, texto) VALUES ($1, $2) RETURNING id, autor, texto, criado_em",
      [autor, texto]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(503).json({
      status: "erro",
      mensagem: "banco de dados inacessivel: " + err.message,
    });
  }
});

app.listen(PORT, () => {
  console.log("Docker ouvindo na porta " + PORT);
});
