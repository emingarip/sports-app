FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
# Tarayicilari paylasilan bir yola kur; boylece root olarak kurup
# uygulamayi root OLMAYAN kullaniciyla calistirabiliyoruz.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

WORKDIR /app

RUN pip install --no-cache-dir --upgrade pip

COPY pyproject.toml README.md ./
COPY app ./app
COPY alembic.ini ./
COPY alembic ./alembic

# [scrape] = playwright. Sofascore saglayicisi Chromium ile veri cekiyor;
# bu olmadan sofascore-football senkronu "Playwright is required" ile duser.
RUN pip install --no-cache-dir ".[dev,scrape]"

# Chromium + sistem bagimliliklari (libnss3, libgbm, fontlar, ...).
RUN playwright install --with-deps chromium \
    && chmod -R a+rX /ms-playwright

# Chromium root olarak --no-sandbox'siz calismaz ve saglayici launch()'a
# ekstra arg gecmiyor; bu yuzden kodu degistirmek yerine root olmayan
# kullaniciya geciyoruz.
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
