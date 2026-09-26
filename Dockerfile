# syntax=docker/dockerfile:1

FROM python:3.8-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --prefix=/install --no-warn-script-location -r requirements.txt

FROM python:3.8-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=my_site.settings \
    PORT=8000

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system appuser && useradd --system --gid appuser --create-home appuser

WORKDIR /app

COPY --from=builder /install /usr/local

COPY . .

RUN python manage.py collectstatic --noinput

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

CMD ["sh", "-c", "python manage.py migrate --noinput && gunicorn my_site.wsgi:application --bind 0.0.0.0:8000 --workers 3 --timeout 60 --graceful-timeout 10"]