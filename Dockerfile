######################
# Stage: Builder
FROM ruby:2.4.4-alpine3.7 as Builder

RUN apk add --update --no-cache \
    build-base \
    postgresql-dev \
    git \
    imagemagick \
    nodejs-current \
    yarn \
    tzdata

WORKDIR /home/app

# Install gems
ADD Gemfile* /home/app/
RUN bundle config --global frozen 1 \
 && bundle install --without development test -j4 --retry 3 \
 # Remove unneeded files (cached *.gem, *.o, *.c)
 && rm -rf /usr/local/bundle/cache/*.gem \
 && find /usr/local/bundle/gems/ -name "*.c" -delete \
 && find /usr/local/bundle/gems/ -name "*.o" -delete

# Add the Rails app (but without spec folder, because it's not needed in production)
ADD . /home/app
RUN rm -rf /home/app/spec

# Precompile assets
RUN RAILS_ENV=production SECRET_KEY_BASE=foo bundle exec rake assets:precompile --trace

###############################
# Stage wkhtmltopdf
FROM madnight/docker-alpine-wkhtmltopdf as wkhtmltopdf

###############################
# Stage Final
FROM ruby:2.4.4-alpine3.7
LABEL maintainer="mail@georg-ledermann.de"

# Add Alpine packages
RUN apk add --update --no-cache \
    postgresql-client \
    imagemagick \
    tzdata \
    file \
    # needed for wkhtmltopdf
    libcrypto1.0 libssl1.0 \
    ttf-dejavu ttf-droid ttf-freefont ttf-liberation ttf-ubuntu-font-family

# Copy wkhtmltopdf from former build stage
COPY --from=wkhtmltopdf /bin/wkhtmltopdf /bin/

# Add user
RUN addgroup -g 1000 -S app \
 && adduser -u 1000 -S app -G app
USER app

# Copy app with gems from former build stage
COPY --from=Builder /usr/local/bundle/ /usr/local/bundle/
COPY --from=Builder --chown=app:app /home/app /home/app

# Set Rails env
ENV RAILS_LOG_TO_STDOUT true
ENV RAILS_SERVE_STATIC_FILES true
ENV EXECJS_RUNTIME Disabled

WORKDIR /home/app

# Expose Puma port
EXPOSE 3000

# Save timestamp of image building
RUN date -u > BUILD_TIME

# Start up
CMD ["docker/startup.sh"]
