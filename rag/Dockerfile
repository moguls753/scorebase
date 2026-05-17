FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY requirements-prod.txt .
RUN pip install --no-cache-dir -r requirements-prod.txt

ENV HF_HOME=/home/rails/.cache/huggingface
RUN mkdir -p "$HF_HOME" && \
    python -c "from sentence_transformers import SentenceTransformer; \
    SentenceTransformer('BAAI/bge-m3')" && \
    chown -R rails:rails "$HF_HOME"

COPY --chown=rails:rails src/ ./src/

# Pre-create the chroma persist path owned by the rails user.
# Docker copies image contents (including ownership) into empty named volumes
# on first mount, so this ensures `scorebase_chroma:/data/chroma` is writable
# by UID 1000 from the moment the volume is created. Without this, Docker
# would create the mount point as root:root and the rails user would get
# EACCES when chromadb tries to create its sqlite metadata files.
RUN mkdir -p /data/chroma && chown -R 1000:1000 /data

USER 1000:1000
ENV PYTHONUNBUFFERED=1
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD curl -fsS http://localhost:8001/ || exit 1

CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8001"]
