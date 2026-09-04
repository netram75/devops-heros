# Python + Flask hello world.
FROM python:3.12-slim

WORKDIR /app

# requirements.txt first so the pip layer caches independently of app.py.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000
CMD ["python", "app.py"]
