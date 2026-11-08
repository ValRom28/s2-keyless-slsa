FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_HOST=0.0.0.0 \
    FLASK_PORT=8080 \
    DB_PATH=/data/app.db \
    FILES_DIR=/data/files

# Correctifs de securite du systeme de base + ping pour /api/ping
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends iputils-ping \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# Seul le code applicatif entre dans l'image (voir aussi .dockerignore)
COPY app/ ./app/

RUN useradd --system --no-create-home --uid 10001 appuser \
 && mkdir -p /data/files \
 && chown -R appuser:appuser /data
USER appuser

EXPOSE 8080
CMD ["gunicorn", "--chdir", "app", "--bind", "0.0.0.0:8080", "--workers", "2", "--preload", "app:app"]
