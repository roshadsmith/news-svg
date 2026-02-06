FROM node:20-bookworm-slim
WORKDIR /app
COPY package*.json ./
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
RUN npm ci --omit=dev
COPY src ./src
COPY .dockerignore ./.dockerignore
COPY README.md ./README.md
ENV PORT=8080
ENV DB_PATH=/data/news.db
EXPOSE 8080
CMD ["node", "src/index.js"]
