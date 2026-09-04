# Multi-stage on purpose. A built React app is just static files: the whole
# Node toolchain (vite, react, ~200 MB of node_modules) is needed to produce
# them and is dead weight afterwards. Stage 2 keeps only /dist.

# ---- stage 1: build the bundle ----
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# ---- stage 2: serve the static output ----
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80
