# Node.js + Express hello world.
FROM node:22-alpine

WORKDIR /app

# Copy the manifests on their own first. This layer only changes when the
# dependencies change, so npm install stays cached across code edits.
COPY package*.json ./
RUN npm install --omit=dev

COPY index.js ./

EXPOSE 3000
CMD ["node", "index.js"]
