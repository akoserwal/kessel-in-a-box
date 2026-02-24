FROM python:3.11-slim

WORKDIR /app

# Install requests library
RUN pip install --no-cache-dir requests

# Copy health exporter script
COPY health_exporter.py /app/

# Make script executable
RUN chmod +x /app/health_exporter.py

# Expose metrics port
EXPOSE 9091

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:9091/health', timeout=2)" || exit 1

# Run the exporter
CMD ["python", "/app/health_exporter.py"]
