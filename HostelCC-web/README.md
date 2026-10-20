# React web application

React 19, Vite, Tailwind CSS and the Spring Boot API. Node 22.12+ is required.

```sh
npm ci
npm run dev
npm run lint
npm run build
```

Vite proxies `/api` to localhost:8080. Production Nginx serves the built SPA and proxies API requests to the Java container. Browser sessions use HttpOnly cookies, with CSRF tokens attached to mutations.

Records are searched and paginated by the API. The People screen provides administrator CSV validation/import; searchable selectors find students and staff outside the current page. Cloakroom QR scanning uses the browser camera or manual pass input. Browser camera access requires localhost or HTTPS.

The Playwright workflow expects a fresh database bootstrapped with admin@hostelcc.local and the isolated test SMTP service (docker-compose.test.yml). It creates test records and must not run against a live installation:

```powershell
$env:HOSTELCC_BASE_URL='http://localhost:18080'
$env:TEST_MAILBOX_URL='http://localhost:18025'
npx playwright test
```

Use an isolated Compose project and empty volume for each run. See VALIDATION.md at the repository root.

Floor plans support custom room placement and room/student history navigation. Dining supports CSV/JSON menu uploads, anonymous session feedback and food/caterer performance. Reports provide selectable columns, CSV downloads and print/PDF output. Menu templates are in public/.
