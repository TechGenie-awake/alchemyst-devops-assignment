FROM iiidev/iii:latest
ENV III_EXECUTION_CONTEXT=docker
WORKDIR /app
COPY config.yaml /app/config.yaml
EXPOSE 3111 49134
ENTRYPOINT ["/app/iii"]
CMD ["--config", "/app/config.yaml"]
