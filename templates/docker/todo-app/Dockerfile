FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir pymysql
COPY app.py .
COPY .env .
EXPOSE 9100
CMD ["python3", "app.py"]
