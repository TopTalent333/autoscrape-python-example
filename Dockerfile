# 1.1 integration-test deps
# Depends on pybuild because integration tests run Django shell to fiddle
# with database.
FROM python:3.6.6-slim-stretch AS base

RUN apt-get update \
    && rm -rf /var/lib/apt/lists/*

RUN pip install pipenv==2018.11.26

RUN true \
    && echo '#!/bin/sh\ncd /app\nexec pipenv run python "$@"' >/usr/bin/pipenv-run-python \
    && chmod +x /usr/bin/pipenv-run-python

# Install the Python deps (common across worker & web server, for now)
RUN mkdir /app
WORKDIR /app

COPY autoscrape/ /app/autoscrape/
COPY Pipfile Pipfile.lock /app/
RUN pipenv install # --dev --system --deploy

# Flask API server
FROM base AS autoscrape-server-deps
COPY autoscrape-server.py /app/
COPY www/ /app/www/

# Install AutoScrape & celery dependencies (Firefox, etc)
FROM base as autoscrape-worker-deps

# Install Firefox deps (and curl, xvfb, vnc). Debian Stretch has Firefox v52,
# which is way too old; but we'll install 52's dependencies and hope they
# satisfy Firefox v63
RUN apt-get update \
    && bash -c 'apt-get install -y --no-install-recommends $(apt-cache depends firefox-esr | awk "/Depends:/{print\$2}")' \
    && apt-get install --no-install-recommends -y \
        curl \
        xauth \
        xvfb \
        bzip2 \
        build-essential \
        cython \
    && rm -rf /var/lib/apt/lists/*

# Install Firefox. It's a separate step so it's easier to resume docker build.
RUN curl -L https://download-installer.cdn.mozilla.net/pub/firefox/releases/64.0.2/linux-x86_64/en-US/firefox-64.0.2.tar.bz2 \
        | tar jx -C /opt \
        && ln -s /opt/firefox/firefox /usr/bin/firefox

# Install geckodriver. It's a separate step so it's easier to resume docker build.
RUN curl -L https://github.com/mozilla/geckodriver/releases/download/v0.23.0/geckodriver-v0.23.0-linux64.tar.gz \
        | tar zx -C /usr/bin/ \
        && chmod +x /usr/bin/geckodriver

FROM autoscrape-worker-deps AS autoscrape-worker
CMD [ "pipenv", "run", "celery", "-A", "autoscrape.tasks", "worker", "--loglevel=info" ]

FROM autoscrape-server-deps AS autoscrape-server
EXPOSE 5000
CMD [ "pipenv", "run", "python", "autoscrape-server.py" ]

FROM rabbitmq:3.7.8-management as rabbitmq
EXPOSE 15672

