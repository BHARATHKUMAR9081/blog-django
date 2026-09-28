FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=my_site.settings \
    PORT=80

WORKDIR /app

# Install build dependencies and clean up in one layer
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libsqlite3-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Dependency isolation & caching: copy manifest first
COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir gunicorn \
    && pip install --no-cache-dir -r requirements.txt

# Copy the full application source
COPY . .

# Collect static files at build time (SECRET_KEY not required for collectstatic)
RUN python manage.py collectstatic --noinput || true

# Non-root user; ensure writable dirs for sqlite db / media
RUN addgroup --system app && adduser --system --group app \
    && mkdir -p /app/staticfiles /app/media \
    && chown -R app:app /app
USER app

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:${PORT}/ >/dev/null || exit 1

# Run migrations then serve with gunicorn on port 80
CMD ["sh", "-c", "python manage.py migrate --noinput && exec gunicorn my_site.wsgi:application --bind 0.0.0.0:${PORT} --workers 3 --timeout 120 --access-logfile - --error-logfile -"]