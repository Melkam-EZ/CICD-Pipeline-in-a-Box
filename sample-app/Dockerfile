# Multi-stage build. The pipeline builds "--target test" first (runs the unit
# tests inside Docker, so the CI runner needs no Python), then "--target runtime".
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv
COPY app ./app

FROM base AS test
COPY tests ./tests
RUN python -m unittest discover -s tests -v

FROM base AS runtime
ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA} PORT=8080
RUN useradd --system --no-create-home appuser
USER appuser
EXPOSE 8080
CMD ["python", "-m", "app.main"]
