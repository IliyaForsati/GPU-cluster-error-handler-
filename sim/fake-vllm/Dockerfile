FROM python:3.12-slim

WORKDIR /app
COPY app.py .
# Stub "vllm" package so KubeAI's Model CR (engine: VLLM) can run this
# fake image with its real launch command - see
# vllm/entrypoints/openai/api_server.py for why.
COPY vllm ./vllm

EXPOSE 8000
CMD ["python", "app.py"]
