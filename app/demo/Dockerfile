FROM public.ecr.aws/docker/library/python:3.13.15-alpine3.24

WORKDIR /app
COPY app.py /app/app.py

RUN addgroup -S app && adduser -S -G app app
USER app

EXPOSE 8080
CMD ["python", "/app/app.py"]
