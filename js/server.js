#!/usr/bin/env node
/**
 * vcdb HTTP Server
 *
 * A vcdb REST API server for vcdb vector database.
 * Runs on Bun (recommended) or Node.js.
 *
 * Usage:
 *   bun run server.js [--port 6333] [--host 0.0.0.0] [--storage ./storage]
 *   node server.js [--port 6333] [--host 0.0.0.0] [--storage ./storage]
 */

import * as fs from 'fs';
import * as path from 'path';

// Parse command-line arguments
function parseArgs(args) {
  const result = {
    port: 6333,
    host: '0.0.0.0',
    storage: './storage',
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--port' && args[i + 1]) {
      result.port = parseInt(args[i + 1], 10);
      i++;
    } else if (args[i] === '--host' && args[i + 1]) {
      result.host = args[i + 1];
      i++;
    } else if (args[i] === '--storage' && args[i + 1]) {
      result.storage = args[i + 1];
      i++;
    }
  }

  return result;
}

// In-memory database state (collections)
const collections = new Map();

// Storage utilities
function ensureStorageDir(storagePath) {
  if (!fs.existsSync(storagePath)) {
    fs.mkdirSync(storagePath, { recursive: true });
  }
}

function saveCollection(storagePath, name, data) {
  const collectionDir = path.join(storagePath, name);
  if (!fs.existsSync(collectionDir)) {
    fs.mkdirSync(collectionDir, { recursive: true });
  }
  fs.writeFileSync(path.join(collectionDir, 'data.json'), JSON.stringify(data, null, 2));
}

function loadCollections(storagePath) {
  if (!fs.existsSync(storagePath)) {
    return;
  }

  const dirs = fs.readdirSync(storagePath, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  for (const name of dirs) {
    const dataPath = path.join(storagePath, name, 'data.json');
    if (fs.existsSync(dataPath)) {
      try {
        const data = JSON.parse(fs.readFileSync(dataPath, 'utf-8'));
        collections.set(name, data);
        console.log(`Loaded collection: ${name} (${data.points?.length || 0} points)`);
      } catch (e) {
        console.error(`Failed to load collection ${name}:`, e.message);
      }
    }
  }
}

// Vector math utilities
function dotProduct(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

function magnitude(v) {
  return Math.sqrt(dotProduct(v, v));
}

function cosineSimilarity(a, b) {
  const magA = magnitude(a);
  const magB = magnitude(b);
  if (magA === 0 || magB === 0) return 0;
  return dotProduct(a, b) / (magA * magB);
}

function l2Distance(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const diff = a[i] - b[i];
    sum += diff * diff;
  }
  return -sum; // Negative because higher = better
}

function getSimilarity(metric, a, b) {
  switch (metric?.toLowerCase()) {
    case 'l2':
      return l2Distance(a, b);
    case 'dot':
      return dotProduct(a, b);
    case 'cosine':
    default:
      return cosineSimilarity(a, b);
  }
}

// Request handlers
function handleHealth() {
  return { status: 'ok' };
}

function handleServiceInfo() {
  return {
    name: 'vcdb',
    version: '0.1.0',
    description: 'MoonBit vector database (JS server)',
  };
}

function handleListCollections() {
  const result = [];
  for (const [name, data] of collections) {
    result.push({
      name,
      vectors_count: data.points?.length || 0,
      dim: data.dim || 0,
      metric: data.metric || 'cosine',
      strategy: data.strategy || 'bruteforce',
    });
  }
  return { collections: result };
}

function handleCreateCollection(name, body, storagePath) {
  if (collections.has(name)) {
    return { error: `Collection already exists: ${name}` };
  }

  const config = body || {};
  const collection = {
    name,
    dim: config.vectors?.size || config.dim || 128,
    metric: config.vectors?.distance || config.metric || 'Cosine',
    strategy: config.strategy || 'hnsw',
    points: [],
  };

  collections.set(name, collection);
  saveCollection(storagePath, name, collection);

  return { status: 'ok' };
}

function handleGetCollection(name) {
  const collection = collections.get(name);
  if (!collection) {
    return { error: `Collection not found: ${name}` };
  }

  return {
    name: collection.name,
    vectors_count: collection.points?.length || 0,
    dim: collection.dim,
    metric: collection.metric,
    strategy: collection.strategy,
  };
}

function handleDeleteCollection(name, storagePath) {
  if (!collections.has(name)) {
    return { error: `Collection not found: ${name}` };
  }

  collections.delete(name);

  const collectionDir = path.join(storagePath, name);
  if (fs.existsSync(collectionDir)) {
    fs.rmSync(collectionDir, { recursive: true });
  }

  return { status: 'ok' };
}

function handleUpsertPoints(name, body, storagePath) {
  const collection = collections.get(name);
  if (!collection) {
    return { error: `Collection not found: ${name}` };
  }

  const points = body.points || [];
  let upserted = 0;

  for (const point of points) {
    const id = point.id;
    const vector = point.vector;
    const payload = point.payload || {};

    if (!vector || !Array.isArray(vector)) {
      continue;
    }

    // Check dimension
    if (collection.dim && vector.length !== collection.dim) {
      return { error: `Dimension mismatch: expected ${collection.dim}, got ${vector.length}` };
    }

    // Update dimension if not set
    if (!collection.dim) {
      collection.dim = vector.length;
    }

    // Find existing point or add new
    const existingIdx = collection.points.findIndex(p => p.id === id);
    if (existingIdx >= 0) {
      collection.points[existingIdx] = { id, vector, payload };
    } else {
      collection.points.push({ id, vector, payload });
    }
    upserted++;
  }

  saveCollection(storagePath, name, collection);

  return { status: 'ok', upserted };
}

function handleSearch(name, body) {
  const collection = collections.get(name);
  if (!collection) {
    return { error: `Collection not found: ${name}` };
  }

  const queryVector = body.vector;
  const limit = body.limit || 10;
  const withPayload = body.with_payload !== false;
  const withVector = body.with_vector === true;

  if (!queryVector || !Array.isArray(queryVector)) {
    return { error: 'Invalid query vector' };
  }

  // Score all points
  const scored = collection.points.map(point => ({
    id: point.id,
    score: getSimilarity(collection.metric, queryVector, point.vector),
    payload: withPayload ? point.payload : undefined,
    vector: withVector ? point.vector : undefined,
  }));

  // Sort by score descending
  scored.sort((a, b) => b.score - a.score);

  // Return top-k
  return {
    result: scored.slice(0, limit),
    time: 0,
  };
}

function handleGetPoint(name, id) {
  const collection = collections.get(name);
  if (!collection) {
    return { error: `Collection not found: ${name}` };
  }

  const point = collection.points.find(p => p.id === id);
  if (!point) {
    return { error: `Point not found: ${id}` };
  }

  return {
    id: point.id,
    payload: point.payload,
    vector: point.vector,
  };
}

function handleDeletePoint(name, id, storagePath) {
  const collection = collections.get(name);
  if (!collection) {
    return { error: `Collection not found: ${name}` };
  }

  const idx = collection.points.findIndex(p => p.id === id);
  if (idx < 0) {
    return { error: `Point not found: ${id}` };
  }

  collection.points.splice(idx, 1);
  saveCollection(storagePath, name, collection);

  return { status: 'ok' };
}

// Route request
function route(method, pathname, body, storagePath) {
  const segments = pathname.split('/').filter(s => s.length > 0);

  // Root
  if (segments.length === 0) {
    return handleServiceInfo();
  }

  // Health check
  if (segments[0] === 'healthz') {
    return handleHealth();
  }

  // Collections
  if (segments[0] === 'collections') {
    // GET /collections
    if (segments.length === 1 && method === 'GET') {
      return handleListCollections();
    }

    // POST /collections/{name}
    if (segments.length === 2 && method === 'POST') {
      return handleCreateCollection(segments[1], body, storagePath);
    }

    // GET /collections/{name}
    if (segments.length === 2 && method === 'GET') {
      return handleGetCollection(segments[1]);
    }

    // DELETE /collections/{name}
    if (segments.length === 2 && method === 'DELETE') {
      return handleDeleteCollection(segments[1], storagePath);
    }

    // PUT /collections/{name}/points
    if (segments.length === 3 && segments[2] === 'points' && method === 'PUT') {
      return handleUpsertPoints(segments[1], body, storagePath);
    }

    // POST /collections/{name}/points/search
    if (segments.length === 4 && segments[2] === 'points' && segments[3] === 'search' && method === 'POST') {
      return handleSearch(segments[1], body);
    }

    // GET /collections/{name}/points/{id}
    if (segments.length === 4 && segments[2] === 'points' && method === 'GET') {
      const id = parseInt(segments[3], 10);
      return handleGetPoint(segments[1], id);
    }

    // DELETE /collections/{name}/points/{id}
    if (segments.length === 4 && segments[2] === 'points' && method === 'DELETE') {
      const id = parseInt(segments[3], 10);
      return handleDeletePoint(segments[1], id, storagePath);
    }
  }

  return { error: 'Not found' };
}

// Main server
async function main() {
  const args = process.argv.slice(2);
  const config = parseArgs(args);

  console.log('vcdb HTTP Server');
  console.log(`Storage: ${config.storage}`);

  ensureStorageDir(config.storage);
  loadCollections(config.storage);

  // Detect runtime
  const isBun = typeof Bun !== 'undefined';

  if (isBun) {
    // Bun server
    Bun.serve({
      port: config.port,
      hostname: config.host,
      async fetch(req) {
        const url = new URL(req.url);
        const method = req.method;
        let body = null;

        if (method === 'POST' || method === 'PUT') {
          try {
            body = await req.json();
          } catch {
            body = {};
          }
        }

        // Handle CORS preflight
        if (method === 'OPTIONS') {
          return new Response(null, {
            status: 204,
            headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
              'Access-Control-Allow-Headers': 'Content-Type',
            },
          });
        }

        const result = route(method, url.pathname, body, config.storage);
        const status = result.error ? (result.error.toLowerCase().includes('not found') ? 404 : 400) : 200;

        return new Response(JSON.stringify(result), {
          status,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        });
      },
    });

    console.log(`Server running at http://${config.host}:${config.port} (Bun)`);
  } else {
    // Node.js server
    const http = await import('http');

    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, `http://${req.headers.host}`);
      const method = req.method;

      // CORS headers
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
      res.setHeader('Content-Type', 'application/json');

      // Handle CORS preflight
      if (method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      let body = null;
      if (method === 'POST' || method === 'PUT') {
        body = await new Promise((resolve) => {
          let data = '';
          req.on('data', chunk => data += chunk);
          req.on('end', () => {
            try {
              resolve(JSON.parse(data));
            } catch {
              resolve({});
            }
          });
        });
      }

      const result = route(method, url.pathname, body, config.storage);
      const status = result.error ? (result.error.toLowerCase().includes('not found') ? 404 : 400) : 200;

      res.writeHead(status);
      res.end(JSON.stringify(result));
    });

    server.listen(config.port, config.host, () => {
      console.log(`Server running at http://${config.host}:${config.port} (Node.js)`);
    });
  }
}

main().catch(console.error);
