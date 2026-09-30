FROM public.ecr.aws/docker/library/python:3.12-slim

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py /app/app.py

RUN useradd -m -u 1000 app && chown -R app:app /app
USER app

EXPOSE 8080
CMD ["python", "/app/app.py"]
