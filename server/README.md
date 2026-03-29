# Hostel Management Server

Containerized Django + DRF backend for hostel workflows.

## Services
- `postgres` (local Docker PostgreSQL)
- `redis` (cache + token/session support)
- `pgbouncer` (connection pooling)
- `web` (Django + Gunicorn)
- `nginx` (reverse proxy)

## Quick Start
1. From `server/` run:
   - `docker compose up --build`
2. App URLs:
   - Web dashboards: `http://localhost:8080/`
   - API root routes: `http://localhost:8080/api/`
   - Django admin: `http://localhost:8080/admin/`

## First-Time Setup
1. Create superuser:
   - `docker compose exec web python manage.py createsuperuser`
2. Add users with roles (`ADMIN`, `STUDENT`, `WARDEN`, `MESS_MANAGER`, `LAUNDRY_PERSON`).
3. Map `Student.user` records in admin.

## Core API Routes
- `POST /api/auth/login`
- `GET /api/students/{id}`
- `GET /api/laundry/schedules/qr/{student_id}`
- `GET /api/mess/menu/`
- `POST /api/mess/feedback/`
- `POST /api/mess/poll/vote/`
- `POST /api/complaints/`
- `POST /api/mess/change/`

## CSV Upload
Upload via:
- `POST /api/students/upload-csv`

CSV columns:
- `roll_no,name,block,room_no,mess_type,username,email`

## Security Notes
- Web dashboards use Django sessions + CSRF.
- Mobile uses JWT (`/api/auth/login`).
- Role-based permissions enforced in API views.
- IP and `X-Client-MAC` are request-logged in middleware.
- Set production secrets in Azure Key Vault and inject via environment variables.

## Azure Deployment
- Deployment automation is available in `server/azure/deploy-container-app.ps1`.
- Full instructions are in `server/azure/README.md`.
- This deploys Django to Azure Container Apps with PostgreSQL and Redis.
- Day-to-day operations (start/stop/rebuild/redeploy/troubleshooting) are in `server/DEPLOYMENT_RUNBOOK.md`.

## OTP Configuration
- You do not need Azure hosting first. Configure OTP through environment variables in any environment (local, Docker, Azure).
- Production: keep `DEFAULT_OTP_CODE` unset or empty.
- Development only: set `DJANGO_DEBUG=true` and optionally set `DEFAULT_OTP_CODE=<6-digit-code>` for manual testing.
- Safety guard: if `DEFAULT_OTP_CODE` is set while `DJANGO_DEBUG=false`, server startup fails to prevent insecure deployment.
