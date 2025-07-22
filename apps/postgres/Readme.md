
```yaml
  postgres:
    image: ghcr.io/vijayakumarravi/postgres
    container_name: postgres
    environment:
      TZ: Asia/Kolkata
      POSTGRES_USER: postgres
      POSTGRES_DB: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
        # postgres data
      - ./pgbackrest/postgresql:/var/lib/postgresql/data
        # pgbackrest configs and logs
      - ./pgbackrest/etc:/etc/pgbackrest
      - ./pgbackrest/log:/var/log/pgbackrest
      - ./pgbackrest/backup:/var/lib/pgbackrest
      - ./pgbackrest/tmp:/tmp/pgbackrest
        # cronjob (optional)
      - ./pgbackrest/cronjob:/cronjob
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U postgres" ]
      interval: 5s
      timeout: 5s
      retries: 5
```
