const FORBIDDEN_CLIENT_ENV_KEYS = [
  'VITE_DB_HOST',
  'VITE_DB_PORT',
  'VITE_DB_USER',
  'VITE_DB_PASSWORD',
  'VITE_DB_NAME',
  'VITE_DATABASE_URL',
  'VITE_PGHOST',
  'VITE_PGUSER',
  'VITE_PGPASSWORD',
  'VITE_PGDATABASE',
];

for (const key of FORBIDDEN_CLIENT_ENV_KEYS) {
  if (import.meta?.env?.[key]) {
    throw new Error(`Forbidden client env key detected: ${key}. Database credentials must stay server-side.`);
  }
}

export const API_BASE_URL =
  import.meta?.env?.VITE_API_BASE_URL || 'http://localhost:3000';

export const WEB_API = `${API_BASE_URL}/api/web`;
export const POS_API = `${API_BASE_URL}/api/pos`;
