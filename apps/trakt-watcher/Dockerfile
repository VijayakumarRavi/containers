FROM python:3.12-slim
ARG VERSION
WORKDIR /app

COPY . /
RUN chmod +x /entrypoint.sh

RUN pip install --no-cache-dir --prefix=/install trakt.py~=${VERSION} requests pyyaml six

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "/trakt-watcher.py"]
