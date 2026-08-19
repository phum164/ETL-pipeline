FROM python:3.12.4-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY etl ./etl
COPY warehouse ./warehouse

ENTRYPOINT ["python", "-m", "etl"]
CMD ["incremental"]
