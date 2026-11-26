FROM python:3.11-slim

WORKDIR /app
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY requirements-prod.txt .
RUN pip install --no-cache-dir -r requirements-prod.txt

ENV HF_HOME=/home/rails/.cache/huggingface \
    MLATEON_INDEX_PATH=/data/mlateon/current \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    TOKENIZERS_PARALLELISM=false PYTHONUNBUFFERED=1
USER 1000:1000
COPY --chown=1000:1000 src/ ./src/
RUN python -c "from huggingface_hub import snapshot_download; from src.pipeline.mlateon import MODEL, REVISION; snapshot_download(MODEL, revision=REVISION, allow_patterns=['*.json','*.safetensors']); from src.pipeline.mlateon import Encoder; Encoder()"
ENV HF_HUB_OFFLINE=1

EXPOSE 8001
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s \
    CMD python -c "from urllib.request import urlopen; urlopen('http://127.0.0.1:8001/', timeout=4).close()"

CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8001"]
