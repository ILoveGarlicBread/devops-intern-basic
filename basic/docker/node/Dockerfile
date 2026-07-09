FROM node:alpine
WORKDIR /app
RUN npm install -g http-server
RUN echo "<h1>Hello world from Node.js server</h1>" > index.html
CMD ["http-server", "-p", "8080"]
