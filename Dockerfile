# Gabarito da sessao 5: build multi-stage e imagem base pequena.
# Imagem final fica abaixo de 200MB. Renomeie para Dockerfile na raiz para usar.

# Etapa de build: instala apenas dependencias de producao.
FROM node:22-alpine AS build
WORKDIR /app
COPY api/package.json ./
RUN npm install --omit=dev

# Etapa final: so o runtime, o node_modules pronto e o codigo.
FROM node:22-alpine
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY api/ ./

EXPOSE 3000

CMD ["node", "server.js"]
