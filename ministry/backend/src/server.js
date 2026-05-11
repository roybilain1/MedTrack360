import dotenv from 'dotenv';
import express from 'express';
import cors from 'cors';
import posRoutes from './routes/pos.js';

dotenv.config();

const app = express();
const port = Number(process.env.PORT ?? 3001);
const targetApiBase = (process.env.CENTRAL_BACKEND_API_BASE_URL || 'http://localhost:3000/api').replace(/\/$/, '');

app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/api/health', async (req, res) => {
  try {
    const upstream = await fetch(targetApiBase.replace(/\/api$/, '') + '/health');
    const body = await upstream.json().catch(() => ({}));
    return res.status(upstream.status).json({
      status: upstream.ok ? 'ok' : 'degraded',
      mode: 'dev-proxy',
      source_of_truth: 'medtrack_web/backend',
      upstream: targetApiBase,
      upstream_health: body,
    });
  } catch (error) {
    return res.status(502).json({
      status: 'error',
      mode: 'dev-proxy',
      source_of_truth: 'medtrack_web/backend',
      upstream: targetApiBase,
      message: error.message,
    });
  }
});

app.use('/api/pos', posRoutes);

app.post('/api/gov/price-updates', async (req, res) => {
  return res.status(410).json({
    status: 'deprecated',
    message: 'Local gov price updates are deprecated. Send updates to the central backend only.',
    target: `${targetApiBase}/sync/push`,
  });
});

app.listen(port, () => {
  console.log(`medtrack-pos backend running in dev-proxy mode on http://localhost:${port}`);
  console.log(`Central backend target: ${targetApiBase}`);
  console.log('Production source of truth is medtrack_web/backend.');
});
