# ==============================================================
# Django-Blog (my_site) — Production Multi-Stage Dockerfile
# Runtime: Python 3.8 (runtime.txt) | WSGI: gunicorn my_site.wsgi
# Target : EC2_DOCKER / containerized Linux host
# ==============================================================

# ---------------- Stage 1: Dependency Builder ----------------
FROM python:3.8-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Build toolchain for psycopg2==2.8.5 / cffi (no manylinux wheels on py3.8)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        libpq-dev \
        libffi-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Manifest-first copy for maximal layer caching
COPY requirements.txt .

RUN pip install --prefix=/install --no-warn-script-location -r requirements.txt

# ---------------- Stage 2: Application Assembly ----------------
FROM python:3.8-slim AS app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Runtime libpq only; curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Compiled dependency tree from builder
COPY --from=builder /install /usr/local

# Source tree (backend_dir = repo root; manage.py at root)
COPY . .

# Collect static assets into STATIC_ROOT (/app/staticfiles) at build time.
# Dummy secrets satisfy settings.py import; DEBUG/ALLOWED_HOSTS via runtime env.
RUN BLOG_SECRET_KEY=build-secret DATABASE_URL=sqlite:///tmp-build.db DEBUG=False \
    python manage.py collectstatic --noinput

# Non-root runtime user
RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# ---------------- Stage 3: Production Runtime ----------------
FROM python:3.8-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    DEBUG=False \
    ALLOWED_HOSTS=*

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Installed site-packages + console scripts (gunicorn)
COPY --from=builder /install /usr/local

# Application code + pre-collected staticfiles
COPY --from=app /app /app

RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/ || exit 1

# Boot: migrate idempotently, then serve WSGI per Procfile
# (gunicorn my_site.wsgi). Supply BLOG_SECRET_KEY + DATABASE_URL at runtime.
CMD ["sh", "-c", "python manage.py migrate --noinput && gunicorn my_site.wsgi --bind 0.0.0.0:8000 --workers 3 --timeout 60 --access-logfile - --error-logfile -"]