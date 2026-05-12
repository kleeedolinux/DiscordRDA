FROM ruby:3.4-slim

WORKDIR /app

ENV BUNDLE_WITHOUT=development:test
ENV BUNDLE_PATH=/usr/local/bundle

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

COPY discord_rda.gemspec Gemfile ./
COPY lib ./lib
COPY README.md LICENSE ./

RUN bundle install

CMD ["irb", "-r", "./lib/discord_rda"]
