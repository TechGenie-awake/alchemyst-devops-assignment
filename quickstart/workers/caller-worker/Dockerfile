FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
ENV III_URL=ws://engine:49134
CMD ["npx", "tsx", "src/worker.ts"]
