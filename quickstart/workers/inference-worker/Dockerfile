FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir -r requirements.txt
COPY inference_worker.py ./
RUN python -c "from transformers import AutoModelForCausalLM, AutoTokenizer; AutoTokenizer.from_pretrained('ggml-org/gemma-3-270m-GGUF', gguf_file='gemma-3-270m-Q8_0.gguf'); AutoModelForCausalLM.from_pretrained('ggml-org/gemma-3-270m-GGUF', gguf_file='gemma-3-270m-Q8_0.gguf')"
ENV III_URL=ws://engine:49134
CMD ["python", "inference_worker.py"]
