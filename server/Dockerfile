FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV PORT=8080
ENV DB_PATH=/data/news.db
EXPOSE 8080
CMD ["node", "src/index.js"]
