# Backend added to this Flutter project

The original Flutter project files were preserved. The following folders were added at the project root:

- `backend-node/` — James's Node.js/MongoDB health-data backend
- `ml-fastapi/` — Aeron's FastAPI machine-learning service scaffold
- `docs/` — API, database, dataset, and architecture documentation

Do not move `backend-node` into `lib`. Flutter communicates with it through HTTP/HTTPS APIs.

## First backend commands

```bash
cd backend-node
npm install
npm run dev
```

Copy the USDA CSV files into:

```text
backend-node/data/usda/raw/foundation/
backend-node/data/usda/raw/fndds/
```
