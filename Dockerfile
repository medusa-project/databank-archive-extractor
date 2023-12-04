# N.B.: this must match the Ruby version in the Gemfile, and /.ruby-version.
FROM --platform=linux/arm64 ruby:3.1.2

ENV RUBY_ENV=prod
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true
ENV RUBY_HOME=/extractor

RUN apt-get update && apt-get install -y \
  build-essential \
  git \
  libpq-dev \
  libarchive-dev


RUN mkdir extractor
WORKDIR extractor

# Copy the Gemfile as well as the Gemfile.lock and install gems.
# This is a separate step so the dependencies will be cached.
COPY Gemfile Gemfile.lock  ./
RUN gem install bundler && bundle install

# Copy the main application, except whatever is listed in .dockerignore.
COPY . ./

# This is the web server entry point. It will need to be overridden when
# running the workers.
CMD ["echo", "Error running task, please check the container override command!"]


