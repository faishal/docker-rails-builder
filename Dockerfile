FROM ruby:2.6.5-stretch
LABEL maintainer="georg@ledermann.dev"

# Add basic packages
RUN apt-get update && apt-get install -y --no-install-recommends apt-transport-https && \
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
  echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
  curl -sL https://deb.nodesource.com/setup_10.x | bash - && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
  git \
  libpq-dev \
  nodejs \
  postgresql-client \
  yarn \
  libv8-dev

WORKDIR /app

# Install standard Node modules
COPY package.json yarn.lock /app/
RUN yarn install

# Install standard gems
COPY Gemfile* /app/
RUN gem install bundler -v 2.1.4
RUN bundle config --global frozen 1 && \
    bundle config --local build.sassc --disable-march-tune-native && \
    bundle install -j4 --retry 3

#### ONBUILD: Add triggers to the image, executed later while building a child image

# Install Ruby gems (for production only)
ONBUILD COPY Gemfile* /app/
ONBUILD RUN gem install bundler -v 2.1.4
ONBUILD RUN bundle install -j4 --retry 3 --without development:test && \
  # Remove unneeded gems
  bundle clean --force && \
  # Remove unneeded files from installed gems (cached *.gem, *.o, *.c)
  rm -rf /usr/local/bundle/cache/*.gem && \
  find /usr/local/bundle/gems/ -name "*.c" -delete && \
  find /usr/local/bundle/gems/ -name "*.o" -delete

# Copy the whole application folder into the image
ONBUILD COPY . /app

# Compile assets with Webpacker or Sprockets
#
# Notes:
#   1. Executing "assets:precompile" runs "yarn:install" prior
#   2. Executing "assets:precompile" runs "webpacker:compile", too
#   3. For an app using encrypted credentials, Rails raises a `MissingKeyError`
#      if the master key is missing. Because on CI there is no master key,
#      we hide the credentials while compiling assets (by renaming them before and after)
#
# ONBUILD RUN mv config/credentials.yml.enc config/credentials.yml.enc.bak 2>/dev/null || true
# Compile assets with webpacker
ONBUILD RUN RAILS_ENV=production \
            SECRET_KEY_BASE=dummy \
            bundle exec rails assets:precompile
# ONBUILD RUN mv config/credentials.yml.enc.bak config/credentials.yml.enc 2>/dev/null || true

# Remove folders not needed in resulting image
ONBUILD RUN rm -rf node_modules tmp/cache vendor/bundle test spec
