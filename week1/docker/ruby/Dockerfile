FROM ruby:slim
RUN gem install webrick
WORKDIR /app
COPY app.rb .
CMD ["ruby", "app.rb"]
