FROM node:20-alpine
WORKDIR /app

# Copy backend package files and install deps
COPY backend/package*.json ./backend/
RUN cd backend && npm ci

# Copy all source code (backend and shared)
COPY backend/ ./backend/
COPY shared/ ./shared/

# Build from the backend directory
WORKDIR /app/backend
RUN npm run build

# tsconfig has rootDir="..", so src/**/* compiles to dist/backend/src/
CMD ["node", "dist/backend/src/index.js"]
