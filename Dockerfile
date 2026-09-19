FROM python:3.12-slim-bookworm

ARG VCS_REF=""

LABEL org.opencontainers.image.source="https://github.com/phum164/ETL-pipeline" \
      org.opencontainers.image.revision="$VCS_REF"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

RUN useradd --create-home --uid 10001 etl

COPY --chown=etl:etl etl ./etl
COPY --chown=etl:etl warehouse ./warehouse

USER etl

ENTRYPOINT ["python", "-m", "etl"]
CMD ["incremental"]
