FROM node:20-alpine
WORKDIR /app

# Copy package files
COPY backend/package*.json ./
RUN npm ci

# Copy source code
COPY backend/ .
COPY shared/ ../shared/

# Build
RUN npm run build

# Fix the path for the shared module imports
# The dist folder will have the compiled JS
CMD ["node", "dist/backend/src/index.js"]