FROM python:3.12-alpine
RUN adduser -D -u 10002 telemetry && mkdir /data && chown telemetry /data
COPY collector.py /app/collector.py
USER telemetry
ENV PYTHONUNBUFFERED=1 TELEMETRY_DIR=/data PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["python", "/app/collector.py"]
