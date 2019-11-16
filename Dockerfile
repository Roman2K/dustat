# --- Build image
FROM ruby:2.5.5-alpine3.10 as builder

# bundle install deps
RUN apk add --update ca-certificates git build-base openssl-dev
RUN gem install bundler -v '>= 2'

# bundle install
COPY . /app
RUN cd /app && bundle

# --- Runtime image
FROM ruby:2.5.5-alpine3.10

COPY --from=builder /app /app
COPY --from=builder /usr/local/bundle /usr/local/bundle

RUN addgroup -g 122 -S docker
RUN apk --update upgrade \
  && apk add --no-cache ca-certificates docker py-pip
RUN apk --virtual tmp add python-dev openssl-dev build-base
RUN pip install 'docker-compose==1.25.0rc4'
RUN apk del tmp
RUN docker-compose --version

RUN addgroup -g 1000 -S app \
  && adduser -u 1000 -S app -G app \
  && addgroup app docker \
  && chown -R app: /app

USER app
WORKDIR /app
ENTRYPOINT ["./docker/entrypoint"]
