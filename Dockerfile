FROM node:22
WORKDIR /app
COPY api/package.json ./
RUN npm install
COPY api/ ./
EXPOSE 3000
CMD ["node", "server.js"]