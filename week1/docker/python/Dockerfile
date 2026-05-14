FROM python:3.9-slim
WORKDIR /app
RUN echo "<h1>Hello world from python server</h1>" > index.html
CMD ["python3", "-m", "http.server", "8000"]
