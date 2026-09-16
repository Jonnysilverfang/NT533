FROM public.ecr.aws/docker/library/python:3.13-alpine

WORKDIR /app
COPY app.py /app/app.py

RUN addgroup -S app && adduser -S -G app app
USER app

EXPOSE 8080
CMD ["python", "/app/app.py"]
