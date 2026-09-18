FROM python:3.12-slim-bookworm

WORKDIR /app
COPY . /app

RUN pip install flask

EXPOSE 5000
CMD ["python", "app.py"]