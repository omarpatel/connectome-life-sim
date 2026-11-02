# Node-only local world runtime. Build site/instar_sim.wasm before building
# this image; the runtime uses the checked-in program IDL, not Rust sources.
FROM node:24-slim
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund --omit=dev

COPY . .

ENV PORT=8787
ENV DATA_DIR=/data
EXPOSE 8787

CMD ["npm", "start"]
